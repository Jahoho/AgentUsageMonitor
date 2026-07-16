import Foundation

struct ParsedHTTPRequest: Equatable, Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    func headerValue(named targetName: String) -> String? {
        headers.first { name, _ in
            name.caseInsensitiveCompare(targetName) == .orderedSame
        }?.value
    }
}

enum HTTPRequestParseResult: Equatable, Sendable {
    case incomplete
    case complete(ParsedHTTPRequest)
    case invalid(String)
    case unsupported(String)
}

enum HTTPRequestParser {
    private static let maximumHeaderBytes = 64 * 1024
    private static let maximumBodyBytes = 32 * 1024 * 1024
    private static let singletonHeaderNames: Set<String> = [
        "authorization",
        "connection",
        "content-length",
        "host",
        "transfer-encoding",
    ]

    static func parse(_ data: Data) -> HTTPRequestParseResult {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > maximumHeaderBytes {
                return .invalid("Request headers are too large.")
            }
            return .incomplete
        }

        guard headerRange.lowerBound <= maximumHeaderBytes else {
            return .invalid("Request headers are too large.")
        }

        guard let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return .invalid("Request headers are not valid UTF-8.")
        }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard
            let requestLine = lines.first,
            requestLine.isEmpty == false
        else {
            return .invalid("Request line is missing.")
        }

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count == 3 else {
            return .invalid("Request line is malformed.")
        }

        let method = String(requestParts[0])
        let version = String(requestParts[2])
        guard
            isValidHTTPToken(method),
            version == "HTTP/1.0" || version == "HTTP/1.1"
        else {
            return .invalid("Request line contains unsupported tokens.")
        }

        let requestTarget = String(requestParts[1])
        guard isValidOriginFormTarget(requestTarget) else {
            return .invalid("Request target must use origin-form.")
        }

        var headers: [String: String] = [:]
        var seenSingletonHeaders: Set<String> = []
        for line in lines.dropFirst() where line.isEmpty == false {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return .invalid("Header line is malformed.")
            }

            let headerName = parts[0]
            guard isValidHTTPToken(headerName) else {
                return .invalid("Header name is invalid.")
            }

            let rawHeaderValue = parts[1]
            guard isValidHeaderValue(rawHeaderValue) else {
                return .invalid("Header value is invalid.")
            }

            let normalizedHeaderName = headerName.lowercased()
            if singletonHeaderNames.contains(normalizedHeaderName) {
                guard seenSingletonHeaders.insert(normalizedHeaderName).inserted else {
                    return .invalid("Duplicate \(headerName) header is not allowed.")
                }
            }

            headers[headerName] = rawHeaderValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if headerValue("Transfer-Encoding", in: headers) != nil {
            return .unsupported("Transfer-Encoding is not supported by the local proxy.")
        }

        let contentLength: Int
        if let contentLengthText = headerValue("Content-Length", in: headers) {
            guard let parsedContentLength = Int(contentLengthText), parsedContentLength >= 0 else {
                return .invalid("Content-Length is invalid.")
            }
            guard parsedContentLength <= maximumBodyBytes else {
                return .invalid("Request body is too large.")
            }
            contentLength = parsedContentLength
        } else {
            contentLength = 0
        }

        let bodyStart = headerRange.upperBound
        let requiredLength = bodyStart + contentLength
        guard data.count >= requiredLength else {
            return .incomplete
        }

        return .complete(
            ParsedHTTPRequest(
                method: method,
                path: requestTarget,
                headers: headers,
                body: Data(data[bodyStart..<requiredLength])
            )
        )
    }

    private static func isValidOriginFormTarget(_ target: String) -> Bool {
        guard target.hasPrefix("/"), target.hasPrefix("//") == false else {
            return false
        }

        return target.unicodeScalars.allSatisfy { scalar in
            scalar.value > 0x20 && scalar.value != 0x5C && scalar.value != 0x7F
        } && target.contains("#") == false
    }

    private static func isValidHTTPToken(_ value: String) -> Bool {
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

    private static func isValidHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x09 || (scalar.value >= 0x20 && scalar.value != 0x7F)
        }
    }

    private static func headerValue(_ targetName: String, in headers: [String: String]) -> String? {
        headers.first { name, _ in
            name.caseInsensitiveCompare(targetName) == .orderedSame
        }?.value
    }
}
