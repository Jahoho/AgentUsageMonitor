import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func httpRequestParserCompletesGETWithoutContentLength() {
    let requestData = Data("""
    GET /user/balance HTTP/1.1\r
    Host: 127.0.0.1\r
    \r
    
    """.utf8)

    switch HTTPRequestParser.parse(requestData) {
    case .complete(let request):
        #expect(request.method == "GET")
        #expect(request.path == "/user/balance")
        #expect(request.body.isEmpty)
    default:
        #expect(Bool(false), "Expected a complete GET request.")
    }
}

@Test func httpRequestParserWaitsForPOSTBody() {
    let partialRequest = Data("""
    POST /chat/completions HTTP/1.1\r
    Host: 127.0.0.1\r
    Content-Length: 5\r
    \r
    hi
    """.utf8)

    #expect(HTTPRequestParser.parse(partialRequest) == .incomplete)
}

@Test func httpRequestParserCompletesPOSTWithContentLength() {
    let requestData = Data("""
    POST /chat/completions HTTP/1.1\r
    Host: 127.0.0.1\r
    Content-Length: 5\r
    \r
    hello
    """.utf8)

    switch HTTPRequestParser.parse(requestData) {
    case .complete(let request):
        #expect(request.method == "POST")
        #expect(String(decoding: request.body, as: UTF8.self) == "hello")
    default:
        #expect(Bool(false), "Expected a complete POST request.")
    }
}

@Test func httpRequestParserRejectsChunkedRequests() {
    let requestData = Data("""
    POST /chat/completions HTTP/1.1\r
    Host: 127.0.0.1\r
    Transfer-Encoding: chunked\r
    \r
    0\r
    \r
    
    """.utf8)

    switch HTTPRequestParser.parse(requestData) {
    case .unsupported(let message):
        #expect(message.contains("Transfer-Encoding"))
    default:
        #expect(Bool(false), "Expected chunked request to be unsupported.")
    }
}

@Test func httpRequestParserRejectsAnyTransferEncoding() {
    let requestData = Data(
        "POST /chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: gzip\r\n\r\n".utf8
    )

    switch HTTPRequestParser.parse(requestData) {
    case .unsupported(let message):
        #expect(message.contains("Transfer-Encoding"))
    default:
        #expect(Bool(false), "Expected Transfer-Encoding to be unsupported.")
    }
}

@Test func httpRequestParserRejectsWhitespaceInHeaderName() {
    let requestData = Data(
        "GET /user/balance HTTP/1.1\r\nAuthorization : Bearer secret\r\n\r\n".utf8
    )

    switch HTTPRequestParser.parse(requestData) {
    case .invalid(let message):
        #expect(message.contains("Header name"))
    default:
        #expect(Bool(false), "Expected an invalid header name to be rejected.")
    }
}

@Test func httpRequestParserRejectsControlCharactersInHeaderValue() {
    let requestData = Data(
        "GET /user/balance HTTP/1.1\r\nX-Test: safe\u{0000}unsafe\r\n\r\n".utf8
    )

    switch HTTPRequestParser.parse(requestData) {
    case .invalid(let message):
        #expect(message.contains("Header value"))
    default:
        #expect(Bool(false), "Expected a control character in a header value to be rejected.")
    }
}

@Test(arguments: [
    "G\tET /user/balance HTTP/1.1",
    "GET /user/balance HTTP/2",
])
func httpRequestParserRejectsUnsupportedRequestLineTokens(requestLine: String) {
    let requestData = Data("\(requestLine)\r\nHost: 127.0.0.1\r\n\r\n".utf8)

    switch HTTPRequestParser.parse(requestData) {
    case .invalid(let message):
        #expect(message.contains("Request line"))
    default:
        #expect(Bool(false), "Expected unsupported request-line tokens to be rejected.")
    }
}

@Test(arguments: [
    "GET @attacker.example/capture HTTP/1.1",
    "GET https://attacker.example/capture HTTP/1.1",
    "GET //attacker.example/capture HTTP/1.1",
])
func httpRequestParserRejectsNonOriginFormTargets(requestLine: String) {
    let requestData = Data("\(requestLine)\r\nHost: 127.0.0.1\r\n\r\n".utf8)

    switch HTTPRequestParser.parse(requestData) {
    case .invalid(let message):
        #expect(message.contains("target"))
    default:
        #expect(Bool(false), "Expected a non-origin-form request target to be rejected.")
    }
}

@Test func httpRequestParserAcceptsOriginFormTargetWithQuery() {
    let requestData = Data("GET /v1/chat/completions?stream=true HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)

    switch HTTPRequestParser.parse(requestData) {
    case .complete(let request):
        #expect(request.path == "/v1/chat/completions?stream=true")
    default:
        #expect(Bool(false), "Expected a valid origin-form request target.")
    }
}

@Test(arguments: ["Authorization", "Connection", "Content-Length", "Host", "Transfer-Encoding"])
func httpRequestParserRejectsDuplicateSensitiveHeaders(headerName: String) {
    let lowercasedName = headerName.lowercased()
    let requestData = Data(
        "POST /chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\n\(headerName): first\r\n\(lowercasedName): second\r\n\r\n".utf8
    )

    switch HTTPRequestParser.parse(requestData) {
    case .invalid(let message):
        #expect(message.contains("Duplicate"))
    default:
        #expect(Bool(false), "Expected a duplicate sensitive header to be rejected.")
    }
}

@Test func httpRequestParserRejectsOversizedHeadersBeforeTerminator() {
    let oversizedHeader = "GET /chat/completions HTTP/1.1\r\nX-Fill: "
        + String(repeating: "a", count: 64 * 1024)

    switch HTTPRequestParser.parse(Data(oversizedHeader.utf8)) {
    case .invalid(let message):
        #expect(message.localizedCaseInsensitiveContains("large"))
    default:
        #expect(Bool(false), "Expected oversized request headers to be rejected.")
    }
}

@Test(arguments: [32 * 1024 * 1024 + 1, Int.max])
func httpRequestParserRejectsOversizedContentLength(contentLength: Int) {
    let requestData = Data(
        "POST /chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: \(contentLength)\r\n\r\n".utf8
    )

    switch HTTPRequestParser.parse(requestData) {
    case .invalid(let message):
        #expect(message.localizedCaseInsensitiveContains("large"))
    default:
        #expect(Bool(false), "Expected an oversized request body to be rejected.")
    }
}
