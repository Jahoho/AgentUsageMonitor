import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func codexUsageLogReaderDoesNotTruncateObservedHistoryByDefault() {
    #expect(CodexUsageLogReader.defaultMaxLogFileCount == nil)
    #expect(CodexUsageLogReader.defaultMaxTotalLogBytes == nil)
}

@Test func codexUsageLogReaderCarriesSessionModelIntoUsageEvents() throws {
    let codexHome = temporaryCodexHome()
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-03T01:00:00.000Z","payload":{"model":"gpt-5.5","effort":"high"}}"#,
            #"{"timestamp":"2026-07-03T01:01:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":150}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.count == 1)
    #expect(events[0].model == "gpt-5.5 high")
}

@Test func codexUsageLogReaderUsesDirectModelWhenUsageLineProvidesOne() throws {
    let codexHome = temporaryCodexHome()
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-03T01:00:00.000Z","payload":{"model":"gpt-5.5","effort":"high"}}"#,
            #"{"timestamp":"2026-07-03T01:01:00.000Z","payload":{"model":"gpt-5.4","effort":"medium","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":150}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.count == 1)
    #expect(events[0].model == "gpt-5.4 medium")
}

@Test func codexUsageLogReaderUsesReasoningEffortFromSessionContext() throws {
    let codexHome = temporaryCodexHome()
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-03T01:00:00.000Z","payload":{"model":"gpt-5.5","reasoning_effort":"high"}}"#,
            #"{"timestamp":"2026-07-03T01:01:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":150}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.count == 1)
    #expect(events[0].model == "gpt-5.5 high")
}

@Test func codexUsageLogReaderUsesModelAndReasoningEffortFromInfoWhenAvailable() throws {
    let codexHome = temporaryCodexHome()
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-03T01:01:00.000Z","payload":{"info":{"model":"gpt-5.4","reasoning_effort":"xhigh","last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":150}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.count == 1)
    #expect(events[0].model == "gpt-5.4 xhigh")
}

@Test func codexUsageLogReaderCarriesInfoModelIntoFollowingUsageEvents() throws {
    let codexHome = temporaryCodexHome()
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-03T01:01:00.000Z","payload":{"info":{"model":"gpt-5.6-sol","reasoning_effort":"ultra","last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":150}}}}"#,
            #"{"timestamp":"2026-07-03T01:02:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":40,"output_tokens":100,"reasoning_output_tokens":20,"total_tokens":300}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.count == 2)
    #expect(events.map(\.model) == ["gpt-5.6-sol ultra", "gpt-5.6-sol ultra"])
}

@Test func codexUsageLogReaderParsesTimestampsWithoutFractionalSeconds() throws {
    let codexHome = temporaryCodexHome()
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-03T01:01:00Z","payload":{"info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":150}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.count == 1)
    #expect(events[0].totalTokens == 150)
}

@Test func codexUsageLogReaderSkipsSubagentReplayTokenCounts() throws {
    let codexHome = temporaryCodexHome()
    let replayLines = (0..<25).map { index in
        #"{"timestamp":"2026-07-05T08:10:00.\#(String(format: "%03d", index + 50))Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":\#(1_000 + index)}}}}"#
    }
    try writeSessionLog(
        codexHome: codexHome,
        fileName: "parent.jsonl",
        lines: [
            #"{"timestamp":"2026-07-05T08:00:00.000Z","type":"session_meta","payload":{"id":"parent","session_id":"parent","source":"vscode"}}"#,
            #"{"timestamp":"2026-07-05T08:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":1050}}}}"#
        ]
    )
    try writeSessionLog(
        codexHome: codexHome,
        fileName: "subagent.jsonl",
        lines: [
            #"{"timestamp":"2026-07-05T08:10:00.000Z","type":"session_meta","payload":{"id":"child","session_id":"parent","forked_from_id":"parent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent","agent_nickname":"Reviewer"}}}}}"#,
            #"{"timestamp":"2026-07-05T08:10:00.001Z","type":"session_meta","payload":{"id":"parent","session_id":"parent","source":"vscode"}}"#,
            #"{"timestamp":"2026-07-05T08:10:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1500,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":2100}}}}"#,
            #"{"timestamp":"2026-07-05T08:12:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":100,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":330}}}}"#
        ] + replayLines
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.map(\.totalTokens).sorted() == [330, 1050, 2100])
}

@Test func codexUsageLogReaderSkipsDenseSubagentReplayRowsWithoutPayloadType() throws {
    let codexHome = temporaryCodexHome()
    let replayLines = (0..<25).map { index in
        #"{"timestamp":"2026-07-05T08:10:00.\#(String(format: "%03d", index + 50))Z","payload":{"info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":\#(1_000 + index)}}}}"#
    }
    try writeSessionLog(
        codexHome: codexHome,
        fileName: "subagent.jsonl",
        lines: [
            #"{"timestamp":"2026-07-05T08:10:00.000Z","type":"session_meta","payload":{"id":"child","session_id":"parent","forked_from_id":"parent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent","agent_nickname":"Reviewer"}}}}}"#,
            #"{"timestamp":"2026-07-05T08:10:01.000Z","payload":{"info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1500,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":2100}}}}"#
        ] + replayLines
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.map(\.totalTokens) == [2100])
}

@Test func codexUsageLogReaderSkipsReplayFromForkedMainSession() throws {
    let codexHome = temporaryCodexHome()
    let replayLines = (0..<25).map { index in
        #"{"timestamp":"2026-07-05T08:10:00.\#(String(format: "%03d", index + 50))Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":\#(1_000 + index)}}}}"#
    }
    try writeSessionLog(
        codexHome: codexHome,
        fileName: "forked-main.jsonl",
        lines: [
            #"{"timestamp":"2026-07-05T08:10:00.000Z","type":"session_meta","payload":{"id":"resumed","forked_from_id":"parent","source":"vscode"}}"#,
            #"{"timestamp":"2026-07-05T08:10:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":1050}},"rate_limits":{"primary":{"resets_at":1783238399}}}}"#,
            #"{"timestamp":"2026-07-05T08:10:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1500,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":2100}},"rate_limits":{"primary":{"resets_at":1783257000}}}}"#
        ] + replayLines
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.map(\.totalTokens) == [2100])
}

@Test func codexUsageLogReaderSkipsSparseSubagentReplayRowsWithStaleRateLimitReset() throws {
    let codexHome = temporaryCodexHome()
    try writeSessionLog(
        codexHome: codexHome,
        fileName: "subagent.jsonl",
        lines: [
            #"{"timestamp":"2026-07-05T08:10:00.000Z","type":"session_meta","payload":{"id":"child","session_id":"parent","forked_from_id":"parent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent","agent_nickname":"Reviewer"}}}}}"#,
            #"{"timestamp":"2026-07-05T08:10:00.100Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":1050}},"rate_limits":{"primary":{"resets_at":1783238399},"secondary":{"resets_at":1783843800}}}}"#,
            #"{"timestamp":"2026-07-05T08:10:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":100,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":330}},"rate_limits":{"primary":{"resets_at":1783238970},"secondary":{"resets_at":1783843800}}}}"#,
            #"{"timestamp":"2026-07-05T08:10:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1500,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":2100}},"rate_limits":{"primary":{"resets_at":1783257000},"secondary":{"resets_at":1783843800}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.map(\.totalTokens).sorted() == [330, 2100])
}

@Test func codexUsageLogReaderSkipsDuplicateRowsWhenCumulativeUsageDoesNotChange() throws {
    let codexHome = temporaryCodexHome()
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-05T08:10:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1000},"last_token_usage":{"input_tokens":900,"cached_input_tokens":100,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":1000}}}}"#,
            #"{"timestamp":"2026-07-05T08:10:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1000},"last_token_usage":{"input_tokens":900,"cached_input_tokens":100,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":1000}}}}"#,
            #"{"timestamp":"2026-07-05T08:10:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1300},"last_token_usage":{"input_tokens":250,"cached_input_tokens":50,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":300}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.map(\.totalTokens) == [1000, 300])
}

@Test func codexUsageLogReaderKeepsUsageWhenCumulativeUsageResets() throws {
    let codexHome = temporaryCodexHome()
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-05T08:10:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":5000},"last_token_usage":{"input_tokens":4500,"cached_input_tokens":1000,"output_tokens":500,"reasoning_output_tokens":0,"total_tokens":5000}}}}"#,
            #"{"timestamp":"2026-07-05T08:10:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":800},"last_token_usage":{"input_tokens":700,"cached_input_tokens":200,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":800}}}}"#,
            #"{"timestamp":"2026-07-05T08:10:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1200},"last_token_usage":{"input_tokens":350,"cached_input_tokens":50,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":400}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.map(\.totalTokens) == [5000, 800, 400])
}

@Test func codexUsageLogReaderDoesNotDoubleCountDuplicateSessionsAcrossDirectories() throws {
    let codexHome = temporaryCodexHome()
    let lines = [
        #"{"timestamp":"2026-07-05T08:00:00.000Z","type":"session_meta","payload":{"id":"session-a","session_id":"session-a","source":"vscode"}}"#,
        #"{"timestamp":"2026-07-05T08:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":1050}}}}"#
    ]
    try writeSessionLog(
        codexHome: codexHome,
        directoryName: "sessions",
        fileName: "session-a-live.jsonl",
        lines: lines
    )
    try writeSessionLog(
        codexHome: codexHome,
        directoryName: "archived_sessions",
        fileName: "session-a-archived.jsonl",
        lines: lines
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.map(\.totalTokens) == [1050])
}

@Test func codexUsageLogReaderDoesNotDeduplicateFilesByParentSessionIDFallback() throws {
    let codexHome = temporaryCodexHome()
    try writeSessionLog(
        codexHome: codexHome,
        directoryName: "sessions",
        fileName: "subagent-a.jsonl",
        lines: [
            #"{"timestamp":"2026-07-05T08:00:00.000Z","type":"session_meta","payload":{"session_id":"parent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent","agent_nickname":"A"}}}}}"#,
            #"{"timestamp":"2026-07-05T08:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":1050}}}}"#
        ]
    )
    try writeSessionLog(
        codexHome: codexHome,
        directoryName: "archived_sessions",
        fileName: "subagent-b.jsonl",
        lines: [
            #"{"timestamp":"2026-07-05T08:02:00.000Z","type":"session_meta","payload":{"session_id":"parent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent","agent_nickname":"B"}}}}}"#,
            #"{"timestamp":"2026-07-05T08:03:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1500,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":2100}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    let events = reader.loadEvents()

    #expect(events.map(\.totalTokens).sorted() == [1050, 2100])
}

@Test func codexUsageLogReaderPrefersRecentFilesWithinByteBudget() throws {
    let codexHome = temporaryCodexHome()
    let oldURL = try writeSessionLog(
        codexHome: codexHome,
        fileName: "old.jsonl",
        lines: [
            #"{"timestamp":"2026-07-04T08:01:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":80,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}}}}"#
        ]
    )
    let recentURL = try writeSessionLog(
        codexHome: codexHome,
        fileName: "recent.jsonl",
        lines: [
            #"{"timestamp":"2026-07-05T08:01:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":160,"cached_input_tokens":0,"output_tokens":40,"reasoning_output_tokens":0,"total_tokens":200}}}}"#
        ]
    )
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1_000)],
        ofItemAtPath: oldURL.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 2_000)],
        ofItemAtPath: recentURL.path
    )
    let recentSize = try #require(recentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path],
        maxTotalLogBytes: recentSize
    )

    let events = reader.loadEvents()

    #expect(events.map(\.totalTokens) == [200])
}

@Test func codexUsageLogReaderInvalidatesParsedFileCacheWhenLogChanges() throws {
    let codexHome = temporaryCodexHome()
    let fileURL = try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-05T08:01:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":80,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path]
    )

    #expect(reader.loadEvents().map(\.totalTokens) == [100])

    try (
        [
            #"{"timestamp":"2026-07-05T08:02:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":160,"cached_input_tokens":0,"output_tokens":40,"reasoning_output_tokens":0,"total_tokens":200}}}}"#,
            #"{"timestamp":"2026-07-05T08:02:01.000Z","payload":{"model":"gpt-5.5","effort":"high"}}"#
        ].joined(separator: "\n") + "\n"
    ).write(to: fileURL, atomically: true, encoding: .utf8)

    #expect(reader.loadEvents().map(\.totalTokens) == [200])
}

@Test func codexUsageLogReaderPersistsAndPrunesParsedFileCache() throws {
    let codexHome = temporaryCodexHome()
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexUsageLogReaderCacheTests-\(UUID().uuidString)")
        .appendingPathComponent("codex-observed-usage.json")
    let fileURL = try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-05T08:01:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":80,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path],
        persistentCacheURL: cacheURL
    )

    #expect(reader.loadEvents().map(\.totalTokens) == [100])
    #expect(FileManager.default.fileExists(atPath: cacheURL.path))
    #expect(try testPOSIXPermissions(at: cacheURL) == LocalDataProtection.filePermissions)
    #expect(
        try testPOSIXPermissions(at: cacheURL.deletingLastPathComponent())
            == LocalDataProtection.directoryPermissions
    )

    let initialCache = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any]
    let initialFiles = initialCache?["files"] as? [String: Any]
    #expect(initialCache?["codexHomePath"] as? String == codexHome.standardizedFileURL.path)
    #expect(initialFiles?.count == 1)

    try FileManager.default.removeItem(at: fileURL)

    #expect(reader.loadEvents().isEmpty)
    let prunedCache = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any]
    let prunedFiles = prunedCache?["files"] as? [String: Any]
    #expect(prunedFiles?.isEmpty == true)
}

@Test func codexUsageLogReaderMigratesLegacyCacheByRemovingDenseReplayBursts() throws {
    let codexHome = temporaryCodexHome()
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexUsageLogReaderLegacyCacheTests-\(UUID().uuidString)")
        .appendingPathComponent("codex-observed-usage.json")
    let replayLines = (0..<25).map { index in
        #"{"timestamp":"2026-07-05T08:10:00.\#(String(format: "%03d", index + 50))Z","payload":{"info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":\#(1_000 + index)}}}}"#
    }
    try writeSessionLog(
        codexHome: codexHome,
        lines: replayLines + [
            #"{"timestamp":"2026-07-05T08:10:01.000Z","payload":{"info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1500,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":2100}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path],
        persistentCacheURL: cacheURL
    )
    #expect(reader.loadEvents().count == 26)

    var legacyCache = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any]
    )
    legacyCache["version"] = 1
    try JSONSerialization.data(withJSONObject: legacyCache).write(to: cacheURL, options: .atomic)

    let migratedEvents = reader.loadEvents()
    let migratedCache = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any]
    )

    #expect(migratedEvents.map(\.totalTokens) == [2100])
    #expect(migratedCache["version"] as? Int == 2)
}

@Test func codexUsageLogReaderRebuildsCorruptedPersistentCache() throws {
    let codexHome = temporaryCodexHome()
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexUsageLogReaderCorruptCacheTests-\(UUID().uuidString)")
    let cacheURL = cacheDirectory.appendingPathComponent("codex-observed-usage.json")
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: cacheURL)
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-05T08:01:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":160,"cached_input_tokens":0,"output_tokens":40,"reasoning_output_tokens":0,"total_tokens":200}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path],
        persistentCacheURL: cacheURL
    )

    #expect(reader.loadEvents().map(\.totalTokens) == [200])
    #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) is [String: Any])
}

@Test func codexUsageLogReaderRetriesLogReadFailuresInsteadOfCachingEmptyResults() throws {
    let codexHome = temporaryCodexHome()
    let sessionsURL = codexHome.appendingPathComponent("sessions", isDirectory: true)
    let fileURL = sessionsURL.appendingPathComponent("session.jsonl")
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexUsageLogReaderRetryTests-\(UUID().uuidString)")
        .appendingPathComponent("codex-observed-usage.json")
    let validData = Data(
        (#"{"timestamp":"2026-07-05T08:01:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":80,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}}}}"# + "\n").utf8
    )
    let fixedModificationDate = Date(timeIntervalSince1970: 2_000)
    try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
    try Data(repeating: 0xFF, count: validData.count).write(to: fileURL)
    try FileManager.default.setAttributes([.modificationDate: fixedModificationDate], ofItemAtPath: fileURL.path)
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path],
        persistentCacheURL: cacheURL
    )

    #expect(reader.loadEvents().isEmpty)
    #expect(FileManager.default.fileExists(atPath: cacheURL.path) == false)

    try validData.write(to: fileURL)
    try FileManager.default.setAttributes([.modificationDate: fixedModificationDate], ofItemAtPath: fileURL.path)

    #expect(reader.loadEvents().map(\.totalTokens) == [100])
}

@Test func codexUsageLogReaderKeepsLastParsedHistoryWhenDirectoryScanIsIncomplete() throws {
    let codexHome = temporaryCodexHome()
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexUsageLogReaderIncompleteScanTests-\(UUID().uuidString)")
        .appendingPathComponent("codex-observed-usage.json")
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-05T08:01:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":80,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path],
        persistentCacheURL: cacheURL
    )

    #expect(reader.loadEvents().map(\.totalTokens) == [100])
    let completeCacheData = try Data(contentsOf: cacheURL)

    let sessionsURL = codexHome.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.removeItem(at: sessionsURL)
    try Data("temporarily unavailable".utf8).write(to: sessionsURL)

    #expect(reader.loadEvents().map(\.totalTokens) == [100])
    #expect(try Data(contentsOf: cacheURL) == completeCacheData)

    try FileManager.default.removeItem(at: sessionsURL)
    try writeSessionLog(
        codexHome: codexHome,
        lines: [
            #"{"timestamp":"2026-07-05T08:02:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":160,"cached_input_tokens":0,"output_tokens":40,"reasoning_output_tokens":0,"total_tokens":200}}}}"#
        ]
    )

    #expect(reader.loadEvents().map(\.totalTokens) == [200])
}

@Test func codexUsageLogReaderPrunesKnownDeletionWhenAnotherFileReadFails() throws {
    let codexHome = temporaryCodexHome()
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexUsageLogReaderPartialFailureTests-\(UUID().uuidString)")
        .appendingPathComponent("codex-observed-usage.json")
    let deletedFileURL = try writeSessionLog(
        codexHome: codexHome,
        fileName: "deleted.jsonl",
        lines: [
            #"{"timestamp":"2026-07-05T08:01:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":80,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}}}}"#
        ]
    )
    let unreadableFileURL = try writeSessionLog(
        codexHome: codexHome,
        fileName: "unreadable.jsonl",
        lines: [
            #"{"timestamp":"2026-07-05T08:02:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":160,"cached_input_tokens":0,"output_tokens":40,"reasoning_output_tokens":0,"total_tokens":200}}}}"#
        ]
    )
    let reader = CodexUsageLogReader(
        fileManager: .default,
        environment: ["CODEX_HOME": codexHome.path],
        persistentCacheURL: cacheURL
    )

    #expect(reader.loadEvents().map(\.totalTokens).sorted() == [100, 200])

    try FileManager.default.removeItem(at: deletedFileURL)
    try Data(repeating: 0xFF, count: 512).write(to: unreadableFileURL)

    #expect(reader.loadEvents().map(\.totalTokens) == [200])
    let cache = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any]
    let cachedFiles = cache?["files"] as? [String: Any]
    #expect(cachedFiles?.count == 1)
    #expect(cachedFiles?.keys.contains { $0.hasSuffix("/deleted.jsonl") } == false)
    #expect(cachedFiles?.keys.contains { $0.hasSuffix("/unreadable.jsonl") } == true)
}

private func temporaryCodexHome() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexUsageLogReaderTests-\(UUID().uuidString)", isDirectory: true)
}

@discardableResult
private func writeSessionLog(
    codexHome: URL,
    directoryName: String = "sessions",
    fileName: String = "session.jsonl",
    lines: [String]
) throws -> URL {
    let sessionsURL = codexHome.appendingPathComponent(directoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
    let fileURL = sessionsURL.appendingPathComponent(fileName)
    try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
}
