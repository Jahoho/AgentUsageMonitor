import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func quotaObservationStoreAppliesCadenceAndCapturesANewResetCycleImmediately() async throws {
    let fileURL = temporaryQuotaObservationFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    let store = QuotaObservationStore(fileURL: fileURL)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let firstReset = start.addingTimeInterval(3_600)
    let nextReset = start.addingTimeInterval(7_200)

    try await store.record(
        [quotaObservation(capturedAt: start, resetAt: firstReset, remainingFraction: 0.9)],
        now: start
    )
    try await store.record(
        [quotaObservation(capturedAt: start.addingTimeInterval(60), resetAt: firstReset, remainingFraction: 0.8)],
        now: start.addingTimeInterval(60)
    )
    try await store.record(
        [quotaObservation(capturedAt: start.addingTimeInterval(120), resetAt: nextReset, remainingFraction: 1)],
        now: start.addingTimeInterval(120)
    )
    try await store.record(
        [quotaObservation(capturedAt: start.addingTimeInterval(360), resetAt: nextReset, remainingFraction: 0.9)],
        now: start.addingTimeInterval(360)
    )
    try await store.record(
        [quotaObservation(capturedAt: start.addingTimeInterval(420), resetAt: nextReset, remainingFraction: 0.8)],
        now: start.addingTimeInterval(420)
    )

    let observations = try await store.load(now: start.addingTimeInterval(420))

    #expect(observations.map(\.capturedAt) == [
        start,
        start.addingTimeInterval(120),
        start.addingTimeInterval(420)
    ])
    #expect(observations.map(\.remainingFraction) == [0.9, 1, 0.8])
}

@Test func quotaObservationStorePrunesExpiredAndMalformedLinesOnLoad() async throws {
    let fileURL = temporaryQuotaObservationFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    let now = Date(timeIntervalSince1970: 1_700_001_000)
    let expired = quotaObservation(
        capturedAt: now.addingTimeInterval(-200),
        resetAt: now.addingTimeInterval(100),
        remainingFraction: 0.2
    )
    let current = quotaObservation(
        capturedAt: now.addingTimeInterval(-50),
        resetAt: now.addingTimeInterval(500),
        remainingFraction: 0.7
    )
    try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    let initialLines = [
        String(decoding: try encoder.encode(expired), as: UTF8.self),
        "not-json",
        String(decoding: try encoder.encode(current), as: UTF8.self)
    ].joined(separator: "\n") + "\n"
    try Data(initialLines.utf8).write(to: fileURL)

    let store = QuotaObservationStore(fileURL: fileURL, retentionInterval: 100)
    let observations = try await store.load(now: now)
    let compactedText = try String(contentsOf: fileURL, encoding: .utf8)

    #expect(observations == [current])
    #expect(compactedText.split(whereSeparator: \.isNewline).count == 1)
}

@Test func quotaObservationStoreUsesOwnerOnlyPermissions() async throws {
    let fileURL = temporaryQuotaObservationFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let store = QuotaObservationStore(fileURL: fileURL)

    try await store.record(
        [
            quotaObservation(
                capturedAt: now,
                resetAt: now.addingTimeInterval(3_600),
                remainingFraction: 0.5
            )
        ],
        now: now
    )

    #expect(try testPOSIXPermissions(at: fileURL) == LocalDataProtection.filePermissions)
    #expect(
        try testPOSIXPermissions(at: fileURL.deletingLastPathComponent())
            == LocalDataProtection.directoryPermissions
    )
}

private func temporaryQuotaObservationFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("QuotaObservationStoreTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("quota-observations-v1.jsonl")
}

private func quotaObservation(
    capturedAt: Date,
    resetAt: Date,
    remainingFraction: Double
) -> QuotaObservation {
    QuotaObservation(
        providerID: "codex",
        accountScopeID: String(repeating: "a", count: 64),
        quotaID: "codex-session",
        remainingFraction: remainingFraction,
        capturedAt: capturedAt,
        resetAt: resetAt
    )
}
