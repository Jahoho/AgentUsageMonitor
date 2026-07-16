import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func codexRPCLineReaderPreservesBufferedLinesAcrossReads() throws {
    let pipe = Pipe()
    pipe.fileHandleForWriting.write(Data("first\nsecond\n".utf8))
    try pipe.fileHandleForWriting.close()
    let reader = CodexRPCLineReader(
        handle: pipe.fileHandleForReading,
        chunkSize: 64,
        maximumLineBytes: 128
    )

    #expect(try String(decoding: reader.readLine(), as: UTF8.self) == "first")
    #expect(try String(decoding: reader.readLine(), as: UTF8.self) == "second")
}

@Test func codexRPCLineReaderCombinesChunksAndRejectsOversizedLines() throws {
    let chunkedPipe = Pipe()
    chunkedPipe.fileHandleForWriting.write(Data("chunked-line\n".utf8))
    try chunkedPipe.fileHandleForWriting.close()
    let chunkedReader = CodexRPCLineReader(
        handle: chunkedPipe.fileHandleForReading,
        chunkSize: 3,
        maximumLineBytes: 32
    )

    #expect(try String(decoding: chunkedReader.readLine(), as: UTF8.self) == "chunked-line")

    let oversizedPipe = Pipe()
    oversizedPipe.fileHandleForWriting.write(Data("12345\n".utf8))
    try oversizedPipe.fileHandleForWriting.close()
    let oversizedReader = CodexRPCLineReader(
        handle: oversizedPipe.fileHandleForReading,
        chunkSize: 2,
        maximumLineBytes: 4
    )

    do {
        _ = try oversizedReader.readLine()
        Issue.record("Expected an oversized RPC response line to fail.")
    } catch {
        #expect(error.localizedDescription.contains("exceeded 4 bytes"))
    }
}

@Test func codexRPCLineReaderRejectsEOFInPartialLine() throws {
    let pipe = Pipe()
    pipe.fileHandleForWriting.write(Data("partial".utf8))
    try pipe.fileHandleForWriting.close()
    let reader = CodexRPCLineReader(handle: pipe.fileHandleForReading, chunkSize: 4)

    do {
        _ = try reader.readLine()
        Issue.record("Expected a partial RPC response line to fail at EOF.")
    } catch {
        #expect(error.localizedDescription.contains("closed stdout mid-line"))
    }
}

@Test func codexRPCParserParsesOfficialResetCreditCount() throws {
    let result = try #require(JSONSerialization.jsonObject(with: Data("""
    {
      "rateLimits": {
        "limitId": "codex",
        "primary": { "usedPercent": 20, "windowDurationMins": 300, "resetsAt": 1704074400 }
      },
      "rateLimitResetCredits": {
        "availableCount": 2,
        "credits": [
          {
            "id": "RateLimitResetCredit_1",
            "resetType": "codexRateLimits",
            "status": "available",
            "grantedAt": 1897401600,
            "expiresAt": 1900000000,
            "title": "Full reset (Weekly + 5 hr)",
            "description": "Ready to redeem"
          }
        ]
      }
    }
    """.utf8)) as? [String: Any])

    let snapshot = try CodexRPCResponseParser.snapshot(
        from: result,
        identity: (email: "user@example.com", plan: "pro")
    )

    #expect(snapshot.resetBank?.availableCount(now: snapshot.updatedAt) == 2)
    #expect(snapshot.resetBank?.source == "CLI RPC")
    #expect(snapshot.resetBank?.nextExpiry(now: snapshot.updatedAt)?.id == "RateLimitResetCredit_1")
    #expect(snapshot.resetBank?.nextExpiry(now: snapshot.updatedAt)?.expiresAt == Date(timeIntervalSince1970: 1_900_000_000))
}

@Test func codexRPCParserNormalizesMillisecondResetTimestamps() throws {
    let result = try #require(JSONSerialization.jsonObject(with: Data("""
    {
      "rateLimits": {
        "limitId": "codex",
        "primary": { "usedPercent": 20, "windowDurationMins": 300, "resetsAt": 1704074400000 }
      }
    }
    """.utf8)) as? [String: Any])

    let snapshot = try CodexRPCResponseParser.snapshot(from: result, identity: nil)

    #expect(snapshot.primary?.resetsAt == Date(timeIntervalSince1970: 1_704_074_400))
}

@Test func codexRPCClientCancellationTerminatesBlockingProcess() async {
    let client = CodexRPCClient(
        executable: "/bin/sleep",
        arguments: ["60"],
        timeoutSeconds: 60
    )
    let start = Date()
    let task = Task {
        try await client.fetchSnapshot()
    }

    try? await Task.sleep(for: .milliseconds(50))
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Expected the blocking RPC client task to be cancelled or fail.")
    } catch {}

    #expect(Date().timeIntervalSince(start) < 2)
}

@Test func codexRPCClientBrokenStdinFailsWithoutTerminatingHostProcess() async {
    let client = CodexRPCClient(
        executable: "/bin/sh",
        arguments: [
            "-c",
            "IFS= read -r line; printf '%s\\n' '{\"id\":1,\"result\":{}}'; exec 0<&-; sleep 1"
        ],
        timeoutSeconds: 2
    )

    do {
        _ = try await client.fetchSnapshot()
        Issue.record("Expected the RPC client to fail after the child closed stdin.")
    } catch {
        #expect(error.localizedDescription.contains("failed to write request"))
    }
}

@Test func codexRPCClientTimeoutForceTerminatesProcessIgnoringSIGTERM() async {
    let client = CodexRPCClient(
        executable: "/bin/sh",
        arguments: ["-c", "trap '' TERM; exec /bin/sleep 60"],
        timeoutSeconds: 0.1
    )
    let start = Date()

    do {
        _ = try await client.fetchSnapshot()
        Issue.record("Expected the blocking RPC client to time out.")
    } catch {}

    #expect(Date().timeIntervalSince(start) < 1)
}
