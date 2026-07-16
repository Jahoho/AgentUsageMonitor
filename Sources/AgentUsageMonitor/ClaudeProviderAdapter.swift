import AgentUsageCore
import Foundation

struct ClaudeProviderAdapter: ProviderSnapshotAdapter, @unchecked Sendable {
    let registration = ProviderRegistration.claude

    private let commandReader: any LocalCommandReading

    init(commandReader: any LocalCommandReading = LocalCommandReader()) {
        self.commandReader = commandReader
    }

    func snapshot() async -> ProviderSnapshot {
        let attemptedAt = Date()
        let claudeVersion = commandReader.firstSuccessfulOutput(commands: [
            ["claude", "--version"],
            ["claude", "-v"]
        ])

        let cliNote = claudeVersion.map { "Claude Code detected: \($0)" } ?? "Claude Code CLI was not found on PATH."

        return ProviderSnapshot(
            id: "claude",
            name: "Claude",
            kind: .subscription,
            health: claudeVersion == nil ? .needsSetup : .ready,
            headline: claudeVersion == nil ? "Connect Claude subscription source" : "Claude Code is available",
            metrics: [
                UsageMetric(
                    id: "claude-code",
                    label: "Claude Code",
                    value: claudeVersion == nil ? "Not found" : "Detected",
                    detail: claudeVersion ?? "Install or expose Claude Code on PATH.",
                    confidence: claudeVersion == nil ? .unavailable : .observed
                ),
                UsageMetric(
                    id: "usage-source",
                    label: "Usage source",
                    value: claudeVersion == nil ? "Unavailable" : "Interactive command",
                    detail: "Open Claude Code and use its official usage command; this app does not script private subscription output.",
                    confidence: .unavailable
                )
            ],
            bars: [
                UsageBar(
                    id: "claude-plan",
                    label: "Plan",
                    remainingFraction: nil,
                    usedText: "Waiting for Claude Code /usage",
                    resetText: "Unknown",
                    confidence: .unavailable
                )
            ],
            sourceDiagnostics: [
                ProviderSourceDiagnostic(
                    id: "claude-cli",
                    name: "Claude Code CLI",
                    confidence: .observed,
                    status: claudeVersion == nil ? .failure : .success,
                    attemptedAt: attemptedAt,
                    lastSuccessAt: claudeVersion == nil ? nil : attemptedAt,
                    lastFailureAt: claudeVersion == nil ? attemptedAt : nil,
                    message: claudeVersion ?? "Claude Code CLI was not found on PATH."
                )
            ],
            notes: [
                cliNote,
                "Exact Claude subscription quota will stay unavailable until a stable official readable source exists.",
                "Future versions can add OpenTelemetry as observed activity data."
            ],
            actions: [
                ProviderAction(
                    id: "claude-code-docs",
                    title: "Open Claude Code Usage Docs",
                    url: URL(string: "https://code.claude.com/docs/en/costs")
                ),
                ProviderAction(
                    id: "claude-account",
                    title: "Open Claude Account",
                    url: URL(string: "https://claude.ai/settings")
                )
            ]
        )
    }
}
