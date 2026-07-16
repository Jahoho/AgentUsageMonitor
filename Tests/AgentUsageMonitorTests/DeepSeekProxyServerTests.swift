import AgentUsageCore
import Foundation
import Network
import Testing
@testable import AgentUsageMonitor

@Test func deepSeekProxyParametersRequireIPv4Loopback() throws {
    let parameters = try DeepSeekProxyNetworkConfiguration.makeParameters(port: 18491)

    guard case .hostPort(let host, let port)? = parameters.requiredLocalEndpoint else {
        #expect(Bool(false), "Expected a required local host and port.")
        return
    }

    #expect(host == .ipv4(.loopback))
    #expect(port == NWEndpoint.Port(rawValue: 18491))
}

@Test func deepSeekProxyStateReportsRunningOnlyWhenReady() {
    #expect(DeepSeekProxyState.stopped.isRunning == false)
    #expect(DeepSeekProxyState.starting.isRunning == false)
    #expect(DeepSeekProxyState.ready.isRunning)
    #expect(DeepSeekProxyState.failed("bind failed").isRunning == false)
}

@Test func deepSeekProxyStatePreservesFailureAfterListenerCancellation() {
    let failedState = DeepSeekProxyState.failed("Address already in use")

    #expect(failedState.applying(.cancelled) == failedState)
    #expect(DeepSeekProxyState.ready.applying(.cancelled) == .stopped)
}

@Test func deepSeekProxyStatusMessageReflectsListenerState() {
    #expect(
        DeepSeekProxyStatusMessage.text(for: .starting, port: 18491)
            == "DeepSeek proxy is starting at http://127.0.0.1:18491."
    )
    #expect(
        DeepSeekProxyStatusMessage.text(for: .ready, port: 18491)
            == "DeepSeek proxy is running at http://127.0.0.1:18491."
    )
    #expect(
        DeepSeekProxyStatusMessage.text(for: .failed("Address already in use"), port: 18491)
            == "DeepSeek proxy failed: Address already in use"
    )
}

@Test func deepSeekRequestReadContextTimesOutOnlyWhileHeadersAreIncomplete() {
    let incompleteContext = DeepSeekRequestReadContext()
    incompleteContext.append(Data("POST /chat/completions HTTP/1.1\r\nHost: local".utf8))

    #expect(incompleteContext.finishForHeaderTimeout())
    #expect(incompleteContext.finishForHeaderTimeout() == false)

    let completeHeaderContext = DeepSeekRequestReadContext()
    completeHeaderContext.append(Data("POST /chat/completions HTTP/1.1\r\nHost: local\r\n\r\n".utf8))

    #expect(completeHeaderContext.finishForHeaderTimeout() == false)
    #expect(completeHeaderContext.finishForRequestTimeout())
    #expect(completeHeaderContext.finishForRequestTimeout() == false)

    let finishedContext = DeepSeekRequestReadContext()
    #expect(finishedContext.finish())
    #expect(finishedContext.finishForRequestTimeout() == false)
    #expect(finishedContext.finish() == false)
}

@Test func deepSeekUpstreamSessionNeverFollowsRedirects() {
    let redirectRequest = URLRequest(url: URL(string: "https://attacker.example/capture")!)

    #expect(DeepSeekRedirectPolicy.requestToFollow(redirectRequest) == nil)
}

@Test func deepSeekUpstreamSessionRejectsStartAfterInvalidation() {
    let session = DeepSeekUpstreamSession()
    let relay = DeepSeekUpstreamRelay(
        writer: DeepSeekProxyTestDownstreamWriter(),
        usageStore: DeepSeekProxyTestUsageStore(),
        accountID: nil
    )
    let request = URLRequest(url: URL(string: "https://api.deepseek.com/v1/models")!)

    session.invalidateAndCancel()

    #expect(session.start(request: request, relay: relay) == false)
}

@Test func deepSeekUpstreamRequestUsesIdentityEncodingAndPinnedOfficialURL() throws {
    let parsedRequest = ParsedHTTPRequest(
        method: "POST",
        path: "/v1/chat/completions?stream=true",
        headers: [
            "Content-Type": "application/json",
            "Content-Length": "2",
            "Connection": "keep-alive, X-Remove-Me, x-mixed-case",
            "Host": "127.0.0.1:18491",
            "X-Mixed-Case": "remove-mixed",
            "X-Remove-Me": "remove-request",
            "X-Client-Trace": "trace-1"
        ],
        body: Data("{}".utf8)
    )
    let credential = DeepSeekProxyCredential(accountID: "account-1", apiKey: "secret-key")

    let request = try #require(
        DeepSeekUpstreamRequestBuilder.makeRequest(
            parsedRequest: parsedRequest,
            credential: credential
        )
    )

    #expect(request.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions?stream=true")
    #expect(request.httpMethod == "POST")
    #expect(request.httpBody == Data("{}".utf8))
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
    #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
    #expect(request.value(forHTTPHeaderField: "X-Client-Trace") == "trace-1")
    #expect(request.value(forHTTPHeaderField: "Host") == nil)
    #expect(request.value(forHTTPHeaderField: "Content-Length") == nil)
    #expect(request.value(forHTTPHeaderField: "Connection") == nil)
    #expect(request.value(forHTTPHeaderField: "X-Remove-Me") == nil)
    #expect(request.value(forHTTPHeaderField: "X-Mixed-Case") == nil)
}

@Test func deepSeekResponseHeadPreservesOfficialEndToEndHeaders() throws {
    let response = try #require(
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/v1/chat/completions")!,
            statusCode: 201,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/event-stream; charset=utf-8",
                "Content-Length": "999",
                "Content-Encoding": "gzip",
                "Connection": "keep-alive, X-Upstream-Hop, x-mixed-case",
                "Keep-Alive": "timeout=5",
                "Transfer-Encoding": "chunked",
                "X-Mixed-Case": "remove-mixed",
                "X-Request-ID": "request-123",
                "X-Upstream-Hop": "remove-response"
            ]
        )
    )

    let head = try #require(String(data: DeepSeekHTTPResponseHeadBuilder.makeHead(response), encoding: .utf8))
    let lowercasedHead = head.lowercased()

    #expect(head.hasPrefix("HTTP/1.1 201 "))
    #expect(lowercasedHead.contains("content-type: text/event-stream; charset=utf-8\r\n"))
    #expect(lowercasedHead.contains("x-request-id: request-123\r\n"))
    #expect(lowercasedHead.contains("connection: close\r\n"))
    #expect(lowercasedHead.contains("content-length:") == false)
    #expect(lowercasedHead.contains("content-encoding:") == false)
    #expect(lowercasedHead.contains("keep-alive:") == false)
    #expect(lowercasedHead.contains("transfer-encoding:") == false)
    #expect(lowercasedHead.contains("x-upstream-hop:") == false)
    #expect(lowercasedHead.contains("x-mixed-case:") == false)
    #expect(head.hasSuffix("\r\n\r\n"))
}

@Test func deepSeekStreamingUsageCaptureParsesSSEAcrossNetworkChunks() throws {
    let response = try #require(
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )
    )
    let capture = DeepSeekStreamingUsageCapture(accountID: "stream-account")
    capture.receive(response: response)
    capture.receive(Data(#"data: {"id":"chunk","model":"deepseek-chat","choices":[],"usage":{"prompt_tokens":11,"completion_tokens":2"#.utf8))
    capture.receive(Data(#"2,"total_tokens":33,"prompt_cache_hit_tokens":4,"prompt_cache_miss_tokens":7}}"#.utf8))
    capture.receive(Data("\n\ndata: [DONE]\n\n".utf8))

    let event = try #require(capture.finalEvent())

    #expect(event.accountID == "stream-account")
    #expect(event.model == "deepseek-chat")
    #expect(event.totalTokens == 33)
    #expect(event.cachedInputTokens == 4)
}

@Test func deepSeekStreamingUsageCaptureParsesChunkedJSONBody() throws {
    let response = try #require(
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )
    )
    let capture = DeepSeekStreamingUsageCapture(accountID: "json-account")
    capture.receive(response: response)
    capture.receive(Data(#"{"id":"response","model":"deepseek-reasoner","usage":{"prompt_tokens":10,"completion_tokens":"#.utf8))
    capture.receive(Data(#"20,"total_tokens":30}}"#.utf8))

    let event = try #require(capture.finalEvent())

    #expect(event.accountID == "json-account")
    #expect(event.model == "deepseek-reasoner")
    #expect(event.totalTokens == 30)
}

@Test func deepSeekUpstreamRelayWritesBodyOnlyAfterResponseHeadCompletes() throws {
    let response = try #require(
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/event-stream",
                "X-Request-ID": "request-456"
            ]
        )
    )
    let writer = DeepSeekProxyTestDownstreamWriter()
    let store = DeepSeekProxyTestUsageStore()
    let relay = DeepSeekUpstreamRelay(
        writer: writer,
        usageStore: store,
        accountID: "stream-account"
    )
    let headCompletion = DeepSeekProxyTestBoolRecorder()
    let bodyCompletion = DeepSeekProxyTestBoolRecorder()
    let body = Data("data: first\n\n".utf8)

    relay.receive(response: response) { headCompletion.record($0) }
    relay.receive(data: body) { bodyCompletion.record($0) }

    #expect(writer.payloads == [DeepSeekHTTPResponseHeadBuilder.makeHead(response)])
    #expect(writer.pendingSendCount == 1)
    #expect(headCompletion.values.isEmpty)
    #expect(bodyCompletion.values.isEmpty)

    writer.completeNextSend(succeeding: true)

    #expect(headCompletion.values == [true])
    #expect(writer.payloads == [DeepSeekHTTPResponseHeadBuilder.makeHead(response), body])
    #expect(writer.pendingSendCount == 1)
    #expect(bodyCompletion.values.isEmpty)

    writer.completeNextSend(succeeding: true)

    #expect(bodyCompletion.values == [true])
}

@Test(.timeLimit(.minutes(1)))
func deepSeekUpstreamRelayDrainsLastChunkAndRecordsUsageOnceAfterUpstreamError() async throws {
    let response = try #require(
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )
    )
    let writer = DeepSeekProxyTestDownstreamWriter()
    let store = DeepSeekProxyTestUsageStore()
    let relay = DeepSeekUpstreamRelay(
        writer: writer,
        usageStore: store,
        accountID: "stream-account"
    )
    let bodyCompletion = DeepSeekProxyTestBoolRecorder()
    let usageChunk = Data(
        #"data: {"model":"deepseek-chat","usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#.utf8
    ) + Data("\n\n".utf8)

    relay.receive(response: response) { _ in }
    writer.completeNextSend(succeeding: true)
    relay.receive(data: usageChunk) { bodyCompletion.record($0) }

    relay.complete(error: URLError(.networkConnectionLost))
    relay.complete(error: URLError(.timedOut))

    #expect(writer.finishCount == 0)
    #expect(writer.errors.isEmpty)
    #expect(bodyCompletion.values.isEmpty)

    writer.completeNextSend(succeeding: true)

    #expect(bodyCompletion.values == [true])
    #expect(writer.finishCount == 1)
    #expect(writer.errors.isEmpty)
    #expect(writer.payloads == [DeepSeekHTTPResponseHeadBuilder.makeHead(response), usageChunk])

    for _ in 0..<100 where await store.load(providerID: "deepseek").isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }

    let events = await store.load(providerID: "deepseek")
    #expect(events.count == 1)
    #expect(events.first?.totalTokens == 15)
    #expect(writer.finishCount == 1)
}

@Test func deepSeekUpstreamRelayStopsQueuedWritesAfterWriteFailure() throws {
    let response = try #require(
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )
    )
    let writer = DeepSeekProxyTestDownstreamWriter()
    let relay = DeepSeekUpstreamRelay(
        writer: writer,
        usageStore: DeepSeekProxyTestUsageStore(),
        accountID: nil
    )
    let firstCompletion = DeepSeekProxyTestBoolRecorder()
    let secondCompletion = DeepSeekProxyTestBoolRecorder()
    let laterCompletion = DeepSeekProxyTestBoolRecorder()
    let firstBody = Data("data: first\n\n".utf8)
    let secondBody = Data("data: second\n\n".utf8)

    relay.receive(response: response) { _ in }
    writer.completeNextSend(succeeding: true)
    relay.receive(data: firstBody) { firstCompletion.record($0) }
    relay.receive(data: secondBody) { secondCompletion.record($0) }

    #expect(writer.payloads == [DeepSeekHTTPResponseHeadBuilder.makeHead(response), firstBody])

    writer.completeNextSend(succeeding: false)

    #expect(firstCompletion.values == [false])
    #expect(secondCompletion.values == [false])
    #expect(writer.payloads == [DeepSeekHTTPResponseHeadBuilder.makeHead(response), firstBody])
    #expect(writer.finishCount == 1)

    relay.receive(data: Data("data: later\n\n".utf8)) { laterCompletion.record($0) }
    relay.complete(error: URLError(.networkConnectionLost))

    #expect(laterCompletion.values == [false])
    #expect(writer.payloads == [DeepSeekHTTPResponseHeadBuilder.makeHead(response), firstBody])
    #expect(writer.finishCount == 1)
    #expect(writer.errors.isEmpty)
}

@Test func deepSeekUpstreamRelaySendsOneBadGatewayBeforeResponseHead() {
    let writer = DeepSeekProxyTestDownstreamWriter()
    let relay = DeepSeekUpstreamRelay(
        writer: writer,
        usageStore: DeepSeekProxyTestUsageStore(),
        accountID: nil
    )

    relay.complete(error: URLError(.cannotConnectToHost))
    relay.complete(error: URLError(.timedOut))

    #expect(writer.errors.count == 1)
    #expect(writer.errors.first?.status == 502)
    #expect(writer.payloads.isEmpty)
    #expect(writer.finishCount == 0)
}

@Test(.timeLimit(.minutes(1)))
func deepSeekProxyReportsRunningWhenListenerIsReady() async throws {
    let server = DeepSeekProxyServer(
        port: 0,
        usageStore: DeepSeekProxyTestUsageStore(),
        credentialProvider: { _ in nil }
    )
    defer { server.stop() }

    try server.start()

    for _ in 0..<100 where server.isRunning == false {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(server.state == .ready)
    #expect(server.isRunning)

    server.stop()
    #expect(server.state == .stopped)
    #expect(server.isRunning == false)
}

@Test(.timeLimit(.minutes(1)))
func deepSeekProxyRecreatesUpstreamSessionAfterRestart() async throws {
    let server = DeepSeekProxyServer(
        port: 0,
        usageStore: DeepSeekProxyTestUsageStore(),
        credentialProvider: { _ in nil }
    )
    defer { server.stop() }

    try server.start()
    for _ in 0..<100 where server.isRunning == false {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(server.hasActiveUpstreamSession)

    server.stop()
    #expect(server.hasActiveUpstreamSession == false)

    try server.start()
    for _ in 0..<100 where server.isRunning == false {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(server.state == .ready)
    #expect(server.hasActiveUpstreamSession)
}

@Test func deepSeekUpstreamURLKeepsOfficialHostAndQuery() {
    let url = DeepSeekUpstreamURLBuilder.makeURL(
        forOriginFormTarget: "/v1/chat/completions?stream=true"
    )

    #expect(url?.scheme == "https")
    #expect(url?.host == "api.deepseek.com")
    #expect(url?.path == "/v1/chat/completions")
    #expect(url?.query == "stream=true")
    #expect(url?.user == nil)
    #expect(url?.password == nil)
}

@Test(arguments: [
    "@attacker.example/capture",
    "https://attacker.example/capture",
    "//attacker.example/capture",
    "/\\attacker.example/capture",
])
func deepSeekUpstreamURLRejectsTargetsThatCouldChangeAuthority(target: String) {
    #expect(DeepSeekUpstreamURLBuilder.makeURL(forOriginFormTarget: target) == nil)
}

private actor DeepSeekProxyTestUsageStore: UsageEventStoring {
    private var events: [UsageEvent] = []

    func load(providerID: String?) async -> [UsageEvent] {
        guard let providerID else { return events }
        return events.filter { $0.providerID == providerID }
    }

    func append(_ event: UsageEvent) async {
        events.append(event)
    }
}

private final class DeepSeekProxyTestDownstreamWriter: DeepSeekDownstreamWriting, @unchecked Sendable {
    private struct PendingSend: Sendable {
        let completion: @Sendable (Bool) -> Void
    }

    private let lock = NSLock()
    private var storedPayloads: [Data] = []
    private var storedFinishCount = 0
    private var storedErrors: [(status: Int, body: Data)] = []
    private var pendingSends: [PendingSend] = []

    var payloads: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return storedPayloads
    }

    var finishCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedFinishCount
    }

    var errors: [(status: Int, body: Data)] {
        lock.lock()
        defer { lock.unlock() }
        return storedErrors
    }

    var pendingSendCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingSends.count
    }

    func send(_ data: Data, completion: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        storedPayloads.append(data)
        pendingSends.append(PendingSend(completion: completion))
        lock.unlock()
    }

    func finish() {
        lock.lock()
        storedFinishCount += 1
        lock.unlock()
    }

    func sendError(status: Int, body: Data) {
        lock.lock()
        storedErrors.append((status: status, body: body))
        lock.unlock()
    }

    func completeNextSend(succeeding: Bool) {
        let completion: (@Sendable (Bool) -> Void)?
        lock.lock()
        completion = pendingSends.isEmpty ? nil : pendingSends.removeFirst().completion
        lock.unlock()
        completion?(succeeding)
    }
}

private final class DeepSeekProxyTestBoolRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Bool] = []

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func record(_ value: Bool) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}
