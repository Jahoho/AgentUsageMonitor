import AgentUsageCore
import Foundation
import Network

enum DeepSeekRedirectPolicy {
    static func requestToFollow(_ request: URLRequest) -> URLRequest? {
        nil
    }
}

private enum DeepSeekHopByHopHeaderFilter {
    private static let fixedHeaderNames: Set<String> = [
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "proxy-connection",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade"
    ]

    static func skippedHeaderNames(
        connectionValues: [String],
        additionalHeaderNames: Set<String>
    ) -> Set<String> {
        var names = fixedHeaderNames.union(additionalHeaderNames)
        for value in connectionValues {
            for token in value.split(separator: ",") {
                let name = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if name.isEmpty == false {
                    names.insert(name)
                }
            }
        }
        return names
    }
}

enum DeepSeekUpstreamRequestBuilder {
    private static let additionalSkippedHeaderNames: Set<String> = [
        "content-length",
        "host"
    ]

    static func makeRequest(
        parsedRequest: ParsedHTTPRequest,
        credential: DeepSeekProxyCredential?
    ) -> URLRequest? {
        guard let targetURL = DeepSeekUpstreamURLBuilder.makeURL(
            forOriginFormTarget: parsedRequest.path
        ) else {
            return nil
        }

        var request = URLRequest(url: targetURL)
        request.httpMethod = parsedRequest.method
        request.httpBody = parsedRequest.body

        let connectionValues = parsedRequest.headers.compactMap { name, value in
            name.caseInsensitiveCompare("Connection") == .orderedSame ? value : nil
        }
        let skippedHeaderNames = DeepSeekHopByHopHeaderFilter.skippedHeaderNames(
            connectionValues: connectionValues,
            additionalHeaderNames: additionalSkippedHeaderNames
        )
        for (name, value) in parsedRequest.headers
        where skippedHeaderNames.contains(name.lowercased()) == false {
            request.setValue(value, forHTTPHeaderField: name)
        }

        if request.value(forHTTPHeaderField: "Authorization") == nil,
           let apiKey = credential?.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // URLSession transparently decodes compressed bodies. Request identity so
        // forwarded response headers always describe the streamed bytes.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }
}

enum DeepSeekHTTPResponseHeadBuilder {
    private static let additionalSkippedHeaderNames: Set<String> = [
        "content-encoding",
        "content-length"
    ]

    static func makeHead(_ response: HTTPURLResponse) -> Data {
        let reason = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
        var lines = ["HTTP/1.1 \(response.statusCode) \(reason)"]

        let rawHeaders = response.allHeaderFields.map { rawName, rawValue in
            (name: String(describing: rawName), value: String(describing: rawValue))
        }
        let connectionValues = rawHeaders.compactMap { header in
            header.name.caseInsensitiveCompare("Connection") == .orderedSame ? header.value : nil
        }
        let skippedHeaderNames = DeepSeekHopByHopHeaderFilter.skippedHeaderNames(
            connectionValues: connectionValues,
            additionalHeaderNames: additionalSkippedHeaderNames
        )
        let headers = rawHeaders.compactMap { header -> (String, String)? in
            let name = header.name
            let value = header.value
            guard
                skippedHeaderNames.contains(name.lowercased()) == false,
                isValidHeaderName(name),
                value.contains("\r") == false,
                value.contains("\n") == false
            else {
                return nil
            }
            return (name, value)
        }
        .sorted { lhs, rhs in
            lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
        }

        lines.append(contentsOf: headers.map { "\($0.0): \($0.1)" })
        lines.append("Connection: close")
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    private static func isValidHeaderName(_ value: String) -> Bool {
        value.isEmpty == false && value.utf8.allSatisfy { byte in
            switch byte {
            case 48...57, 65...90, 97...122:
                return true
            case 33, 35...39, 42, 43, 45, 46, 94, 95, 96, 124, 126:
                return true
            default:
                return false
            }
        }
    }
}

enum DeepSeekHTTPErrorResponseBuilder {
    static func makeResponse(status: Int, body: Data) -> Data {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status)
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """

        var responseData = Data(header.utf8)
        responseData.append(body)
        return responseData
    }
}

protocol DeepSeekDownstreamWriting: Sendable {
    func send(_ data: Data, completion: @escaping @Sendable (Bool) -> Void)
    func finish()
    func sendError(status: Int, body: Data)
}

final class DeepSeekNWDownstreamWriter: DeepSeekDownstreamWriting, @unchecked Sendable {
    private let connection: NWConnection
    private let outputQueue = DispatchQueue(label: "AgentUsageMonitor.DeepSeekNWDownstreamWriter")
    private var isFinished = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    func send(_ data: Data, completion: @escaping @Sendable (Bool) -> Void) {
        outputQueue.async { [self] in
            guard isFinished == false else {
                completion(false)
                return
            }

            connection.send(content: data, completion: .contentProcessed { error in
                completion(error == nil)
            })
        }
    }

    func finish() {
        outputQueue.async { [self] in
            guard markFinished() else { return }
            connection.send(
                content: nil,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { [weak connection] _ in
                    connection?.cancel()
                }
            )
        }
    }

    func sendError(status: Int, body: Data) {
        outputQueue.async { [self] in
            guard markFinished() else { return }
            let responseData = DeepSeekHTTPErrorResponseBuilder.makeResponse(status: status, body: body)
            connection.send(content: responseData, completion: .contentProcessed { [weak connection] _ in
                connection?.cancel()
            })
        }
    }

    private func markFinished() -> Bool {
        guard isFinished == false else { return false }
        isFinished = true
        return true
    }
}

final class DeepSeekStreamingUsageCapture: @unchecked Sendable {
    private enum Mode {
        case buffered
        case eventStream
    }

    private static let maximumCaptureBytes = 32 * 1024 * 1024
    private static let lineFeedDelimiter = Data("\n\n".utf8)
    private static let carriageReturnDelimiter = Data("\r\n\r\n".utf8)

    private let accountID: String?
    private var mode = Mode.buffered
    private var buffer = Data()
    private var latestEvent: UsageEvent?
    private var isCaptureDisabled = false

    init(accountID: String?) {
        self.accountID = accountID
    }

    func receive(response: HTTPURLResponse) {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        mode = contentType.contains("text/event-stream") ? .eventStream : .buffered
    }

    func receive(_ data: Data) {
        guard isCaptureDisabled == false else { return }
        guard data.count <= Self.maximumCaptureBytes - min(buffer.count, Self.maximumCaptureBytes) else {
            buffer.removeAll(keepingCapacity: false)
            isCaptureDisabled = true
            return
        }

        buffer.append(data)
        if mode == .eventStream {
            drainCompleteSSEBlocks()
        }
    }

    func finalEvent() -> UsageEvent? {
        guard isCaptureDisabled == false else { return latestEvent }

        switch mode {
        case .buffered:
            return UsageEventParser.deepSeekEvent(
                from: buffer,
                accountID: accountID
            ) ?? UsageEventParser.deepSeekEventFromSSE(
                from: buffer,
                accountID: accountID
            )
        case .eventStream:
            if buffer.isEmpty == false {
                var finalBlock = buffer
                finalBlock.append(Self.lineFeedDelimiter)
                if let event = UsageEventParser.deepSeekEventFromSSE(
                    from: finalBlock,
                    accountID: accountID
                ) {
                    latestEvent = event
                }
                buffer.removeAll(keepingCapacity: false)
            }
            return latestEvent
        }
    }

    private func drainCompleteSSEBlocks() {
        while let delimiterRange = nextDelimiterRange() {
            let block = Data(buffer[..<delimiterRange.upperBound])
            buffer.removeSubrange(..<delimiterRange.upperBound)
            if let event = UsageEventParser.deepSeekEventFromSSE(
                from: block,
                accountID: accountID
            ) {
                latestEvent = event
            }
        }
    }

    private func nextDelimiterRange() -> Range<Data.Index>? {
        let lineFeedRange = buffer.range(of: Self.lineFeedDelimiter)
        let carriageReturnRange = buffer.range(of: Self.carriageReturnDelimiter)
        switch (lineFeedRange, carriageReturnRange) {
        case (.some(let lhs), .some(let rhs)):
            return lhs.lowerBound < rhs.lowerBound ? lhs : rhs
        case (.some(let range), nil), (nil, .some(let range)):
            return range
        case (nil, nil):
            return nil
        }
    }
}

final class DeepSeekUpstreamRelay: @unchecked Sendable {
    private struct PendingWrite: Sendable {
        let data: Data
        let completion: @Sendable (Bool) -> Void
    }

    private enum TerminalAction: Sendable {
        case finish
        case sendError(status: Int, body: Data)
    }

    private let writer: any DeepSeekDownstreamWriting
    private let usageStore: any UsageEventStoring
    private let capture: DeepSeekStreamingUsageCapture
    private let lock = NSLock()
    private var responseStarted = false
    private var completionRequested = false
    private var writeInFlight = false
    private var writeFailed = false
    private var terminalAction: TerminalAction?
    private var terminalActionSent = false
    private var pendingWrites: [PendingWrite] = []

    init(
        writer: any DeepSeekDownstreamWriting,
        usageStore: any UsageEventStoring,
        accountID: String?
    ) {
        self.writer = writer
        self.usageStore = usageStore
        self.capture = DeepSeekStreamingUsageCapture(accountID: accountID)
    }

    func receive(
        response: HTTPURLResponse,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let nextWrite: PendingWrite?
        lock.lock()
        guard canAcceptWrite, responseStarted == false else {
            lock.unlock()
            completion(false)
            return
        }
        responseStarted = true
        capture.receive(response: response)
        pendingWrites.append(
            PendingWrite(
                data: DeepSeekHTTPResponseHeadBuilder.makeHead(response),
                completion: completion
            )
        )
        nextWrite = takeNextWriteIfAvailable()
        lock.unlock()

        send(nextWrite)
    }

    func receive(
        data: Data,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let nextWrite: PendingWrite?
        lock.lock()
        guard canAcceptWrite, responseStarted else {
            lock.unlock()
            completion(false)
            return
        }
        capture.receive(data)
        pendingWrites.append(PendingWrite(data: data, completion: completion))
        nextWrite = takeNextWriteIfAvailable()
        lock.unlock()

        send(nextWrite)
    }

    func complete(error: Error?) {
        let event: UsageEvent?
        let action: TerminalAction?
        lock.lock()
        guard completionRequested == false else {
            lock.unlock()
            return
        }
        completionRequested = true
        event = capture.finalEvent()

        if let error, responseStarted == false {
            terminalAction = .sendError(
                status: 502,
                body: Data(error.localizedDescription.utf8)
            )
        } else if responseStarted {
            terminalAction = .finish
        } else {
            terminalAction = .sendError(
                status: 502,
                body: Data("Proxy response missing".utf8)
            )
        }
        action = takeTerminalActionIfReady()
        lock.unlock()

        if let event {
            let usageStore = usageStore
            Task {
                await usageStore.append(event)
            }
        }

        perform(action)
    }

    private var canAcceptWrite: Bool {
        completionRequested == false && writeFailed == false && terminalActionSent == false
    }

    private func takeNextWriteIfAvailable() -> PendingWrite? {
        guard
            writeInFlight == false,
            writeFailed == false,
            pendingWrites.isEmpty == false
        else {
            return nil
        }

        writeInFlight = true
        return pendingWrites.removeFirst()
    }

    private func send(_ write: PendingWrite?) {
        guard let write else { return }
        writer.send(write.data) { [self] succeeded in
            writeDidComplete(write, succeeded: succeeded)
        }
    }

    private func writeDidComplete(_ write: PendingWrite, succeeded: Bool) {
        let nextWrite: PendingWrite?
        let rejectedCompletions: [@Sendable (Bool) -> Void]
        let action: TerminalAction?

        lock.lock()
        writeInFlight = false
        if succeeded {
            rejectedCompletions = []
            nextWrite = takeNextWriteIfAvailable()
            action = nextWrite == nil ? takeTerminalActionIfReady() : nil
        } else {
            writeFailed = true
            rejectedCompletions = pendingWrites.map(\.completion)
            pendingWrites.removeAll(keepingCapacity: false)
            nextWrite = nil
            action = takeWriteFailureAction()
        }
        lock.unlock()

        write.completion(succeeded)
        for completion in rejectedCompletions {
            completion(false)
        }
        perform(action)
        send(nextWrite)
    }

    private func takeTerminalActionIfReady() -> TerminalAction? {
        guard
            completionRequested,
            writeInFlight == false,
            pendingWrites.isEmpty,
            terminalActionSent == false,
            let terminalAction
        else {
            return nil
        }

        terminalActionSent = true
        return terminalAction
    }

    private func takeWriteFailureAction() -> TerminalAction? {
        guard terminalActionSent == false else { return nil }
        terminalActionSent = true
        return .finish
    }

    private func perform(_ action: TerminalAction?) {
        switch action {
        case .finish:
            writer.finish()
        case .sendError(let status, let body):
            writer.sendError(status: status, body: body)
        case nil:
            break
        }
    }
}

private enum DeepSeekUpstreamSessionError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "DeepSeek returned a non-HTTP response."
    }
}

private final class DeepSeekResponseDispositionCompletionBox: @unchecked Sendable {
    private let completion: (URLSession.ResponseDisposition) -> Void

    init(_ completion: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.completion = completion
    }

    func callAsFunction(_ disposition: URLSession.ResponseDisposition) {
        completion(disposition)
    }
}

final class DeepSeekUpstreamSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var relays: [Int: DeepSeekUpstreamRelay] = [:]

    func register(_ relay: DeepSeekUpstreamRelay, for task: URLSessionTask) {
        lock.lock()
        relays[task.taskIdentifier] = relay
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(DeepSeekRedirectPolicy.requestToFollow(request))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let relay = relay(for: dataTask) else {
            completionHandler(.cancel)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            relay.complete(error: DeepSeekUpstreamSessionError.invalidResponse)
            completionHandler(.cancel)
            return
        }

        let responseCompletion = DeepSeekResponseDispositionCompletionBox(completionHandler)
        relay.receive(response: httpResponse) { didSend in
            responseCompletion(didSend ? .allow : .cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard let relay = relay(for: dataTask) else {
            dataTask.cancel()
            return
        }

        dataTask.suspend()
        relay.receive(data: data) { didSend in
            if didSend {
                dataTask.resume()
            } else {
                dataTask.cancel()
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        takeRelay(for: task)?.complete(error: error)
    }

    private func relay(for task: URLSessionTask) -> DeepSeekUpstreamRelay? {
        lock.lock()
        defer { lock.unlock() }
        return relays[task.taskIdentifier]
    }

    private func takeRelay(for task: URLSessionTask) -> DeepSeekUpstreamRelay? {
        lock.lock()
        defer { lock.unlock() }
        return relays.removeValue(forKey: task.taskIdentifier)
    }
}

final class DeepSeekUpstreamSession: @unchecked Sendable {
    private let delegate: DeepSeekUpstreamSessionDelegate
    private let session: URLSession
    private let lifecycleLock = NSLock()
    private var isActive = true

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        let delegate = DeepSeekUpstreamSessionDelegate()
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility
        self.delegate = delegate
        self.session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
    }

    @discardableResult
    func start(
        request: URLRequest,
        relay: DeepSeekUpstreamRelay
    ) -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard isActive else { return false }

        let task = session.dataTask(with: request)
        delegate.register(relay, for: task)
        task.resume()
        return true
    }

    func invalidateAndCancel() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard isActive else { return }
        isActive = false
        session.invalidateAndCancel()
    }
}

enum DeepSeekUpstreamSessionFactory {
    static func makeSession() -> DeepSeekUpstreamSession {
        DeepSeekUpstreamSession()
    }
}
