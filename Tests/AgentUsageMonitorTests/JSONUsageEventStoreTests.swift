import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func jsonUsageEventStoreAppendsJSONLines() async throws {
    let urls = temporaryUsageStoreURLs()
    let store = JSONUsageEventStore(fileURL: urls.jsonl, legacyFileURL: urls.legacy)
    let deepSeekEvent = usageEvent(providerID: "deepseek", totalTokens: 10)
    let codexEvent = usageEvent(providerID: "codex", totalTokens: 20)

    await store.append(deepSeekEvent)
    await store.append(codexEvent)

    let deepSeekEvents = await store.load(providerID: "deepseek")
    let text = (try? String(contentsOf: urls.jsonl, encoding: .utf8)) ?? ""

    #expect(deepSeekEvents == [deepSeekEvent])
    #expect(text.split(whereSeparator: \.isNewline).count == 2)
    #expect(try testPOSIXPermissions(at: urls.jsonl) == LocalDataProtection.filePermissions)
    #expect(
        try testPOSIXPermissions(at: urls.jsonl.deletingLastPathComponent())
            == LocalDataProtection.directoryPermissions
    )
}

@Test func jsonUsageEventStoreMigratesLegacyJSONWithoutDeletingIt() async throws {
    let urls = temporaryUsageStoreURLs()
    let legacyEvents = [usageEvent(providerID: "deepseek", totalTokens: 42)]
    let data = try JSONEncoder().encode(legacyEvents)
    try FileManager.default.createDirectory(
        at: urls.legacy.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: urls.legacy)

    let store = JSONUsageEventStore(fileURL: urls.jsonl, legacyFileURL: urls.legacy)
    let loaded = await store.load(providerID: nil)

    #expect(loaded == legacyEvents)
    #expect(FileManager.default.fileExists(atPath: urls.jsonl.path))
    #expect(FileManager.default.fileExists(atPath: urls.legacy.path))
    #expect(try testPOSIXPermissions(at: urls.jsonl) == LocalDataProtection.filePermissions)
    #expect(try testPOSIXPermissions(at: urls.legacy) == LocalDataProtection.filePermissions)
}

private func temporaryUsageStoreURLs() -> (jsonl: URL, legacy: URL) {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentUsageMonitorUsageStoreTests-\(UUID().uuidString)", isDirectory: true)
    return (
        directoryURL.appendingPathComponent("usage-events.jsonl"),
        directoryURL.appendingPathComponent("usage-events.json")
    )
}

private func usageEvent(providerID: String, totalTokens: Int) -> UsageEvent {
    UsageEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", totalTokens))") ?? UUID(),
        providerID: providerID,
        model: "test",
        inputTokens: totalTokens / 2,
        outputTokens: totalTokens / 2,
        totalTokens: totalTokens,
        createdAt: Date(timeIntervalSince1970: TimeInterval(totalTokens)),
        confidence: .observed
    )
}
