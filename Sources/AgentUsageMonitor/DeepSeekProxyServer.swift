import AgentUsageCore
import Foundation
import Network

enum DeepSeekProxyListenerEvent: Equatable, Sendable {
    case starting
    case ready
    case failed(String)
    case cancelled
}

enum DeepSeekProxyState: Equatable, Sendable {
    case stopped
    case starting
    case ready
    case failed(String)

    var isRunning: Bool {
        self == .ready
    }

    func applying(_ event: DeepSeekProxyListenerEvent) -> DeepSeekProxyState {
        switch event {
        case .starting:
            return .starting
        case .ready:
            return .ready
        case .failed(let message):
            return .failed(message)
        case .cancelled:
            if case .failed = self {
                return self
            }
            return .stopped
        }
    }
}

// Production mutations are serialized on DeepSeekProxyServer.networkQueue.
final class DeepSeekRequestReadContext: @unchecked Sendable {
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    private(set) var accumulated = Data()
    private(set) var isFinished = false
    private var headerTimeoutWorkItem: DispatchWorkItem?
    private var requestTimeoutWorkItem: DispatchWorkItem?

    func installHeaderTimeout(_ workItem: DispatchWorkItem) {
        headerTimeoutWorkItem = workItem
    }

    func installRequestTimeout(_ workItem: DispatchWorkItem) {
        requestTimeoutWorkItem = workItem
    }

    func append(_ data: Data) {
        accumulated.append(data)
        if hasCompleteHeaders {
            headerTimeoutWorkItem?.cancel()
        }
    }

    func finishForHeaderTimeout() -> Bool {
        guard isFinished == false, hasCompleteHeaders == false else {
            return false
        }

        return markFinished()
    }

    func finishForRequestTimeout() -> Bool {
        finish()
    }

    func finish() -> Bool {
        guard isFinished == false else {
            return false
        }

        return markFinished()
    }

    private func markFinished() -> Bool {
        isFinished = true
        headerTimeoutWorkItem?.cancel()
        requestTimeoutWorkItem?.cancel()
        return true
    }

    private var hasCompleteHeaders: Bool {
        accumulated.range(of: Self.headerTerminator) != nil
    }
}

final class DeepSeekProxyServer: @unchecked Sendable {
    typealias StateUpdateHandler = @Sendable (DeepSeekProxyState) -> Void

    let port: UInt16

    private let usageStore: any UsageEventStoring
    private let credentialProvider: @Sendable (_ requestAPIKey: String?) -> DeepSeekProxyCredential?
    private let headerReadTimeout: TimeInterval
    private let requestReadTimeout: TimeInterval
    private let networkQueue = DispatchQueue(label: "AgentUsageMonitor.DeepSeekProxyServer")
    private let lifecycleLock = NSLock()
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var upstreamSession: DeepSeekUpstreamSession?
    private var listenerGeneration: UUID?
    private var storedState = DeepSeekProxyState.stopped
    private var storedStateUpdateHandler: StateUpdateHandler?

    init(
        port: UInt16 = 18491,
        usageStore: any UsageEventStoring,
        headerReadTimeout: TimeInterval = 10,
        requestReadTimeout: TimeInterval = 60,
        credentialProvider: @escaping @Sendable (_ requestAPIKey: String?) -> DeepSeekProxyCredential?
    ) {
        let boundedHeaderReadTimeout = max(0.1, headerReadTimeout)
        self.port = port
        self.usageStore = usageStore
        self.headerReadTimeout = boundedHeaderReadTimeout
        self.requestReadTimeout = max(boundedHeaderReadTimeout, requestReadTimeout)
        self.credentialProvider = credentialProvider
    }

    var state: DeepSeekProxyState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedState
    }

    var isRunning: Bool {
        state.isRunning
    }

    var hasActiveUpstreamSession: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return upstreamSession != nil
    }

    var stateUpdateHandler: StateUpdateHandler? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return storedStateUpdateHandler
        }
        set {
            stateLock.lock()
            storedStateUpdateHandler = newValue
            stateLock.unlock()
        }
    }

    func start() throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard listener == nil else { return }

        let parameters = try DeepSeekProxyNetworkConfiguration.makeParameters(port: port)
        let listener = try NWListener(using: parameters)
        let generation = UUID()
        listener.stateUpdateHandler = { [weak self] listenerState in
            self?.handle(listenerState, generation: generation)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        self.listener = listener
        upstreamSession = DeepSeekUpstreamSessionFactory.makeSession()
        activateListener(generation: generation)
        listener.start(queue: networkQueue)
    }

    func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        let listener = listener
        let upstreamSession = upstreamSession
        self.listener = nil
        self.upstreamSession = nil
        deactivateListener()
        listener?.cancel()
        upstreamSession?.invalidateAndCancel()
    }

    private func handle(_ connection: NWConnection) {
        let context = DeepSeekRequestReadContext()
        let timeoutWorkItem = DispatchWorkItem { [weak self, weak connection, weak context] in
            guard
                let self,
                let connection,
                context?.finishForHeaderTimeout() == true
            else {
                return
            }

            self.send(status: 408, body: Data("Request headers timed out".utf8), to: connection)
        }
        context.installHeaderTimeout(timeoutWorkItem)
        let requestTimeoutWorkItem = DispatchWorkItem { [weak self, weak connection, weak context] in
            guard
                let self,
                let connection,
                context?.finishForRequestTimeout() == true
            else {
                return
            }

            self.send(status: 408, body: Data("Request body timed out".utf8), to: connection)
        }
        context.installRequestTimeout(requestTimeoutWorkItem)

        connection.start(queue: networkQueue)
        networkQueue.asyncAfter(
            deadline: .now() + headerReadTimeout,
            execute: timeoutWorkItem
        )
        networkQueue.asyncAfter(
            deadline: .now() + requestReadTimeout,
            execute: requestTimeoutWorkItem
        )
        receiveRequest(on: connection, context: context)
    }

    private func receiveRequest(on connection: NWConnection, context: DeepSeekRequestReadContext) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, context.isFinished == false else { return }

            if let data {
                context.append(data)
            }

            if error != nil {
                if context.finish() {
                    self.send(status: 502, body: Data("Proxy read failed".utf8), to: connection)
                }
                return
            }

            switch HTTPRequestParser.parse(context.accumulated) {
            case .complete(let request):
                if context.finish() {
                    self.forward(parsedRequest: request, connection: connection)
                }
            case .incomplete where isComplete:
                if context.finish() {
                    self.send(status: 400, body: Data("Incomplete HTTP request".utf8), to: connection)
                }
            case .incomplete:
                self.receiveRequest(on: connection, context: context)
            case .invalid(let message):
                if context.finish() {
                    self.send(status: 400, body: Data(message.utf8), to: connection)
                }
            case .unsupported(let message):
                if context.finish() {
                    self.send(status: 501, body: Data(message.utf8), to: connection)
                }
            }
        }
    }

    private func handle(_ listenerState: NWListener.State, generation: UUID) {
        let event: DeepSeekProxyListenerEvent
        switch listenerState {
        case .setup:
            event = .starting
        case .waiting(let error):
            event = .failed(error.localizedDescription)
        case .ready:
            event = .ready
        case .failed(let error):
            event = .failed(error.localizedDescription)
        case .cancelled:
            event = .cancelled
        @unknown default:
            event = .failed("Unknown listener state.")
        }

        apply(event, generation: generation)
    }

    private func activateListener(generation: UUID) {
        stateLock.lock()
        listenerGeneration = generation
        let nextState = storedState.applying(.starting)
        storedState = nextState
        let handler = storedStateUpdateHandler
        stateLock.unlock()
        handler?(nextState)
    }

    private func deactivateListener() {
        stateLock.lock()
        listenerGeneration = nil
        storedState = .stopped
        let handler = storedStateUpdateHandler
        stateLock.unlock()
        handler?(.stopped)
    }

    private func apply(_ event: DeepSeekProxyListenerEvent, generation: UUID) {
        stateLock.lock()
        guard listenerGeneration == generation else {
            stateLock.unlock()
            return
        }

        let nextState = storedState.applying(event)
        guard nextState != storedState else {
            stateLock.unlock()
            return
        }

        storedState = nextState
        let handler = storedStateUpdateHandler
        stateLock.unlock()
        handler?(nextState)
    }

    private func forward(parsedRequest: ParsedHTTPRequest, connection: NWConnection) {
        let requestAPIKey = bearerToken(from: parsedRequest.headerValue(named: "Authorization"))
        let proxyCredential = credentialProvider(requestAPIKey)
        guard let request = DeepSeekUpstreamRequestBuilder.makeRequest(
            parsedRequest: parsedRequest,
            credential: proxyCredential
        ) else {
            send(status: 400, body: Data("Invalid DeepSeek path".utf8), to: connection)
            return
        }

        guard let upstreamSession = activeUpstreamSession() else {
            send(status: 503, body: Data("DeepSeek proxy is stopping".utf8), to: connection)
            return
        }

        let relay = DeepSeekUpstreamRelay(
            writer: DeepSeekNWDownstreamWriter(connection: connection),
            usageStore: usageStore,
            accountID: proxyCredential?.accountID
        )
        if upstreamSession.start(request: request, relay: relay) == false {
            relay.complete(error: DeepSeekProxyError.upstreamSessionInactive)
        }
    }

    private func activeUpstreamSession() -> DeepSeekUpstreamSession? {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return upstreamSession
    }

    private func send(status: Int, body: Data, to connection: NWConnection) {
        let responseData = DeepSeekHTTPErrorResponseBuilder.makeResponse(status: status, body: body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func bearerToken(from authorizationHeader: String?) -> String? {
        guard let authorizationHeader else {
            return nil
        }

        let parts = authorizationHeader.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else {
            return nil
        }

        return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DeepSeekProxyNetworkConfiguration {
    static func makeParameters(port: UInt16) throws -> NWParameters {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw DeepSeekProxyError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: nwPort
        )
        return parameters
    }
}

enum DeepSeekUpstreamURLBuilder {
    private static let officialBaseURL = URL(string: "https://api.deepseek.com")!

    static func makeURL(forOriginFormTarget target: String) -> URL? {
        guard
            target.hasPrefix("/"),
            target.hasPrefix("//") == false,
            target.contains("\\") == false,
            target.contains("#") == false,
            let url = URL(string: target, relativeTo: officialBaseURL)?.absoluteURL,
            url.scheme == "https",
            url.host == "api.deepseek.com",
            url.port == nil,
            url.user == nil,
            url.password == nil,
            url.fragment == nil
        else {
            return nil
        }

        return url
    }
}

enum DeepSeekProxyError: LocalizedError {
    case invalidPort
    case upstreamSessionInactive

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "Invalid proxy port."
        case .upstreamSessionInactive:
            return "DeepSeek proxy is stopping."
        }
    }
}
