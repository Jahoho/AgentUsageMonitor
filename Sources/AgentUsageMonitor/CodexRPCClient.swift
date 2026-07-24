import AgentUsageCore
import Darwin
import Foundation

struct CodexRPCClient: CodexRateLimitSnapshotFetching {
    static let defaultTimeoutSeconds: TimeInterval = 8

    private let environment: [String: String]
    private let executable: String
    private let arguments: [String]
    private let timeoutSeconds: TimeInterval

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executable: String = "codex",
        arguments: [String] = ["-s", "read-only", "-a", "untrusted", "app-server"],
        timeoutSeconds: TimeInterval = Self.defaultTimeoutSeconds
    ) {
        self.environment = environment
        self.executable = executable
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
    }

    func fetchSnapshot() async throws -> CodexRateLimitSnapshot {
        let session = CodexRPCSession(
            environment: environment,
            executable: executable,
            arguments: arguments
        )

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: CodexRateLimitSnapshot.self) { group in
                group.addTask {
                    try session.run()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeoutSeconds))
                    session.shutdown()
                    throw CodexRPCError.timeout
                }

                guard let result = try await group.next() else {
                    throw CodexRPCError.timeout
                }
                group.cancelAll()
                return result
            }
        } onCancel: {
            session.shutdown()
        }
    }

}

private final class CodexRPCSession: @unchecked Sendable {
    private let environment: [String: String]
    private let executable: String
    private let arguments: [String]
    private let lock = NSLock()
    private var process: Process?
    private var shutdownRequested = false
    private var terminationStarted = false

    init(environment: [String: String], executable: String, arguments: [String]) {
        self.environment = environment
        self.executable = executable
        self.arguments = arguments
    }

    func run() throws -> CodexRateLimitSnapshot {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinHandle = stdinPipe.fileHandleForWriting
        guard fcntl(stdinHandle.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw CodexRPCError.startFailed(
                "failed to configure stdin pipe: \(String(cString: strerror(errno)))"
            )
        }

        lock.lock()
        guard shutdownRequested == false else {
            lock.unlock()
            throw CancellationError()
        }
        self.process = process
        lock.unlock()

        defer {
            shutdown()
        }

        do {
            try Task.checkCancellation()
            try process.run()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if isShutdownRequested {
                throw CancellationError()
            }
            throw CodexRPCError.startFailed(error.localizedDescription)
        }

        if isShutdownRequested || Task.isCancelled {
            shutdown()
            throw CancellationError()
        }
        let responseReader = CodexRPCLineReader(handle: stdoutPipe.fileHandleForReading)

        try sendRequest(
            ["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "AgentUsageMonitor", "version": "0.2.0"]]],
            to: stdinPipe
        )
        _ = try readResponse(id: 1, from: responseReader)
        try sendRequest(["method": "initialized", "params": [:]], to: stdinPipe)

        try sendRequest(["id": 2, "method": "account/read", "params": [:]], to: stdinPipe)
        let accountResponse = try? readResponse(id: 2, from: responseReader)
        let identity = accountResponse.flatMap(parseIdentity)

        try sendRequest(["id": 3, "method": "account/rateLimits/read", "params": [:]], to: stdinPipe)
        let limitsResponse = try readResponse(id: 3, from: responseReader)

        guard let result = limitsResponse["result"] as? [String: Any] else {
            throw CodexRPCError.malformed("missing result")
        }

        return try CodexRPCResponseParser.snapshot(from: result, identity: identity)
    }

    private func sendRequest(_ payload: [String: Any], to pipe: Pipe) throws {
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(0x0A)

        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw CodexRPCError.requestFailed("failed to write request: \(error.localizedDescription)")
        }
    }

    private func readResponse(id: Int, from reader: CodexRPCLineReader) throws -> [String: Any] {
        while true {
            let line = try reader.readLine()
            guard line.isEmpty == false else {
                continue
            }

            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue
            }

            if let error = object["error"] as? [String: Any] {
                throw CodexRPCError.requestFailed(error["message"] as? String ?? "unknown error")
            }

            if let responseID = object["id"] as? Int, responseID == id {
                return object
            }
        }
    }

    private func parseIdentity(from response: [String: Any]) -> (email: String?, plan: String?)? {
        guard
            let result = response["result"] as? [String: Any],
            let account = result["account"] as? [String: Any]
        else {
            return nil
        }

        return (
            email: normalized(account["email"] as? String),
            plan: normalized(account["planType"] as? String) ?? normalized(account["plan_type"] as? String)
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }
        return value
    }

    func shutdown() {
        let processToTerminate: Process?

        lock.lock()
        shutdownRequested = true
        if terminationStarted == false, let process, process.isRunning {
            terminationStarted = true
            processToTerminate = process
        } else {
            processToTerminate = nil
        }
        lock.unlock()

        guard let processToTerminate else {
            return
        }

        processToTerminate.terminate()
        let deadline = ProcessInfo.processInfo.systemUptime + 0.1
        while processToTerminate.isRunning,
              ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        if processToTerminate.isRunning {
            Darwin.kill(processToTerminate.processIdentifier, SIGKILL)
        }
    }

    private var isShutdownRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return shutdownRequested
    }
}

final class CodexRPCLineReader {
    static let defaultChunkSize = 4 * 1_024
    static let defaultMaximumLineBytes = 1_024 * 1_024

    private let handle: FileHandle
    private let chunkSize: Int
    private let maximumLineBytes: Int
    private var buffer = Data()

    init(
        handle: FileHandle,
        chunkSize: Int = defaultChunkSize,
        maximumLineBytes: Int = defaultMaximumLineBytes
    ) {
        precondition(chunkSize > 0)
        precondition(maximumLineBytes > 0)
        self.handle = handle
        self.chunkSize = chunkSize
        self.maximumLineBytes = maximumLineBytes
    }

    func readLine() throws -> Data {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newlineIndex])
                guard line.count <= maximumLineBytes else {
                    throw lineTooLongError()
                }
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                return line
            }

            guard buffer.count <= maximumLineBytes else {
                throw lineTooLongError()
            }

            let chunk = handle.readData(ofLength: chunkSize)
            guard chunk.isEmpty == false else {
                if buffer.isEmpty {
                    throw CodexRPCError.malformed("Codex app-server closed stdout")
                }
                throw CodexRPCError.malformed(
                    "Codex app-server closed stdout mid-line (partial payload discarded)"
                )
            }
            buffer.append(chunk)
        }
    }

    private func lineTooLongError() -> CodexRPCError {
        CodexRPCError.malformed(
            "Codex app-server response line exceeded \(maximumLineBytes) bytes"
        )
    }
}

enum CodexRPCResponseParser {
    static func snapshot(
        from result: [String: Any],
        identity: (email: String?, plan: String?)?
    ) throws -> CodexRateLimitSnapshot {
        guard let rateLimits = selectedRateLimits(from: result) else {
            throw CodexRPCError.malformed("missing rateLimits")
        }

        let primary = (rateLimits["primary"] as? [String: Any]).flatMap(makeWindow)
        let secondary = (rateLimits["secondary"] as? [String: Any]).flatMap(makeWindow)

        guard primary != nil || secondary != nil else {
            throw CodexRPCError.malformed("missing rate limit windows")
        }

        let quotaPlan = normalized(rateLimits["planType"] as? String)
            ?? normalized(rateLimits["plan_type"] as? String)

        return CodexRateLimitSnapshot(
            primary: primary,
            secondary: secondary,
            source: "CLI RPC",
            email: identity?.email,
            plan: identity?.plan ?? quotaPlan,
            accountPlan: identity?.plan,
            quotaPlan: quotaPlan,
            limitName: normalized(rateLimits["limitName"] as? String)
                ?? normalized(rateLimits["limit_name"] as? String)
                ?? normalized(rateLimits["limitId"] as? String)
                ?? normalized(rateLimits["limit_id"] as? String),
            resetBank: CodexResetParser.resetBank(in: result, source: "CLI RPC")
        )
    }

    private static func selectedRateLimits(from result: [String: Any]) -> [String: Any]? {
        let root = result["rateLimits"] as? [String: Any]
            ?? result["rate_limits"] as? [String: Any]
        let byLimitID = result["rateLimitsByLimitId"] as? [String: [String: Any]]
            ?? result["rate_limits_by_limit_id"] as? [String: [String: Any]]

        if let codex = byLimitID?["codex"] {
            return codex
        }

        if let root, normalized(root["limitId"] as? String) == "codex"
            || normalized(root["limit_id"] as? String) == "codex" {
            return root
        }

        if let codexLike = byLimitID?.values.first(where: { value in
            let id = normalized(value["limitId"] as? String)
                ?? normalized(value["limit_id"] as? String)
                ?? ""
            return id == "codex"
        }) {
            return codexLike
        }

        return root ?? byLimitID?.values.sorted { lhs, rhs in
            let lhsName = normalized(lhs["limitName"] as? String)
                ?? normalized(lhs["limit_name"] as? String)
                ?? normalized(lhs["limitId"] as? String)
                ?? ""
            let rhsName = normalized(rhs["limitName"] as? String)
                ?? normalized(rhs["limit_name"] as? String)
                ?? normalized(rhs["limitId"] as? String)
                ?? ""
            return lhsName < rhsName
        }.first
    }

    private static func makeWindow(from object: [String: Any]) -> CodexRateLimitWindow? {
        guard let usedPercent = flexibleDouble(
            object["usedPercent"] ?? object["used_percent"] ?? object["used"]
        ) else {
            return nil
        }

        let windowMinutes = flexibleInt(
            object["windowDurationMins"] ?? object["window_duration_mins"]
        )
        let resetSeconds = flexibleDouble(
            object["resetsAt"] ?? object["resets_at"] ?? object["resetAt"] ?? object["reset_at"]
        )

        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetSeconds.map { Date(timestamp: $0) }
        )
    }

    private static func flexibleDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func flexibleInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }
        return value
    }
}

enum CodexRPCError: LocalizedError {
    case startFailed(String)
    case requestFailed(String)
    case malformed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .startFailed(let message):
            return "Codex app-server failed to start: \(message)"
        case .requestFailed(let message):
            return "Codex app-server request failed: \(message)"
        case .malformed(let message):
            return "Codex app-server returned invalid data: \(message)"
        case .timeout:
            return "Codex app-server timed out."
        }
    }

    var isTransient: Bool {
        switch self {
        case .timeout, .requestFailed:
            return true
        case .malformed(let message):
            return message.localizedCaseInsensitiveContains("closed stdout")
        case .startFailed:
            return false
        }
    }
}
