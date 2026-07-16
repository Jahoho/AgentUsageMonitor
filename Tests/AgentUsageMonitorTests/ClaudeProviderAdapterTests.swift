import Testing
@testable import AgentUsageMonitor

@Test func claudeProviderAdapterReportsCLIAvailabilityWithoutOfficialQuota() async {
    let adapter = ClaudeProviderAdapter(
        commandReader: TestLocalCommandReader(output: "Claude Code 1.2.3")
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .ready)
    #expect(snapshot.metrics.first { $0.id == "claude-code" }?.value == "Detected")
    #expect(snapshot.metrics.first { $0.id == "usage-source" }?.confidence == .unavailable)
}

@Test func claudeProviderAdapterNeedsSetupWhenCLIMissing() async {
    let adapter = ClaudeProviderAdapter(commandReader: TestLocalCommandReader(output: nil))

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .needsSetup)
    #expect(snapshot.metrics.first { $0.id == "claude-code" }?.value == "Not found")
}

private struct TestLocalCommandReader: LocalCommandReading {
    let output: String?

    func firstSuccessfulOutput(commands: [[String]]) -> String? {
        output
    }
}
