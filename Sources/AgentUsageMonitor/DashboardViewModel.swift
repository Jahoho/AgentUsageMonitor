import AgentUsageCore
import AppKit
import Foundation

enum DeepSeekProxyStatusMessage {
    static func text(for state: DeepSeekProxyState, port: UInt16) -> String {
        switch state {
        case .stopped:
            return "DeepSeek proxy is not running."
        case .starting:
            return "DeepSeek proxy is starting at http://127.0.0.1:\(port)."
        case .ready:
            return "DeepSeek proxy is running at http://127.0.0.1:\(port)."
        case .failed(let message):
            return "DeepSeek proxy failed: \(message)"
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var selectedProviderID = "overview"
    @Published private(set) var snapshots: [ProviderSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var menuBarStatus = MenuBarStatusFactory.snapshot(from: [])
    @Published private(set) var capacityInsights: [String: CapacityInsight] = [:]
    @Published var deepSeekAPIKeyLabelInput = ""
    @Published var deepSeekAPIKeyInput = ""
    @Published var settingsMessage = ""
    @Published var openRouterAPIKeyLabelInput = ""
    @Published var openRouterAPIKeyInput = ""
    @Published private(set) var openRouterSettingsMessage = ""
    @Published private(set) var deepSeekProxyMessage = "DeepSeek proxy is not running."
    @Published private(set) var launchAtLoginState = LaunchAtLoginController.currentState()
    @Published private(set) var deepSeekCredentials: [DeepSeekCredential] = []
    @Published private(set) var openRouterCredentials: [OpenRouterCredential] = []

    private let providerMonitorService: ProviderMonitorService
    private let deepSeekCredentialStore: any DeepSeekCredentialStoring
    private let openRouterCredentialStore: any OpenRouterCredentialStoring
    private let usageStore: any UsageEventStoring
    private let capacityInsightProvider: any CapacityInsightProviding
    private var deepSeekProxyServer: DeepSeekProxyServer?
    private var codexWebSessionWindow: CodexWebSessionWindow?
    private var capacityInsightTask: Task<Void, Never>?
    private var lastRefreshAt: Date?

    init(
        providerMonitorService: ProviderMonitorService = ProviderMonitorService(),
        deepSeekCredentialStore: any DeepSeekCredentialStoring = DeepSeekCredentialStore(),
        openRouterCredentialStore: any OpenRouterCredentialStoring = OpenRouterCredentialStore(),
        usageStore: any UsageEventStoring = JSONUsageEventStore(),
        capacityInsightProvider: any CapacityInsightProviding = CapacityInsightService()
    ) {
        self.providerMonitorService = providerMonitorService
        self.deepSeekCredentialStore = deepSeekCredentialStore
        self.openRouterCredentialStore = openRouterCredentialStore
        self.usageStore = usageStore
        self.capacityInsightProvider = capacityInsightProvider
        reloadDeepSeekCredentials()
        reloadOpenRouterCredentials()
    }

    var selectedSnapshot: ProviderSnapshot? {
        snapshots.first { $0.id == selectedProviderID } ?? snapshots.first
    }

    var providerRegistrations: [ProviderRegistration] {
        providerMonitorService.registrations
    }

    var navigationItems: [DashboardNavigationItem] {
        DashboardNavigation.items(for: providerRegistrations)
    }

    func refresh() async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let providerMonitorService = providerMonitorService
        let latestProviderSnapshots = await Task.detached(priority: .userInitiated) {
            await providerMonitorService.loadProviderSnapshots()
        }.value
        let providerSnapshots = mergedProviderSnapshots(latestProviderSnapshots)
        let overview = UsageAggregator.overview(from: providerSnapshots)
        snapshots = [overview] + providerSnapshots
        menuBarStatus = MenuBarStatusFactory.snapshot(from: providerSnapshots)
        lastRefreshAt = Date()
        refreshCapacityInsights(from: latestProviderSnapshots)
    }

    func startLocalServices() {
        startDeepSeekProxyIfPossible()
    }

    private func refreshCapacityInsights(from currentSnapshots: [ProviderSnapshot]) {
        let now = Date()
        if let currentCodex = currentSnapshots.first(where: { $0.id == "codex" }) {
            if let reason = CapacityInsightService.currentUnavailabilityReason(
                for: currentCodex,
                now: now
            ) {
                capacityInsights["codex"] = CapacityInsight.unavailable(
                    providerID: "codex",
                    reason: reason,
                    generatedAt: now
                )
            } else if let existing = capacityInsights["codex"],
                      capacityInsightMatchesCurrentQuota(existing, snapshot: currentCodex) == false {
                capacityInsights.removeValue(forKey: "codex")
            }
        } else {
            capacityInsights.removeValue(forKey: "codex")
        }

        capacityInsightTask?.cancel()
        let capacityInsightProvider = capacityInsightProvider
        capacityInsightTask = Task { [weak self] in
            let insights = await capacityInsightProvider.refreshInsights(
                from: currentSnapshots,
                now: now
            )
            guard Task.isCancelled == false else {
                return
            }
            self?.capacityInsights = insights
        }
    }

    private func capacityInsightMatchesCurrentQuota(
        _ insight: CapacityInsight,
        snapshot: ProviderSnapshot
    ) -> Bool {
        guard insight.windows.isEmpty == false else {
            return false
        }

        return insight.windows.allSatisfy { window in
            guard let currentReset = snapshot.bars.first(where: { $0.id == window.quotaID })?.resetAt else {
                return false
            }
            return abs(currentReset.timeIntervalSince(window.resetAt)) <= 5 * 60
        }
    }

    private func mergedProviderSnapshots(_ latestSnapshots: [ProviderSnapshot]) -> [ProviderSnapshot] {
        let previousSnapshotsByID = Dictionary(
            uniqueKeysWithValues: snapshots
                .filter { $0.id != "overview" }
                .map { ($0.id, $0) }
        )

        return latestSnapshots.map { rawLatest in
            let previous = previousSnapshotsByID[rawLatest.id]
            let latestWithHistory = mergingSourceHistory(in: rawLatest, previous: previous)
            let latest = mergingCodexObservedActivity(
                in: latestWithHistory,
                previous: previous
            )
            guard latest.health == .error,
                  providerMonitorService.registration(for: latest.id)?
                    .freshnessPolicy.canPreservePreviousSnapshot == true,
                  let previous,
                  shouldPreserve(previous)
            else {
                return latest
            }

            return previousSnapshot(previous, preservingAgainst: latest)
        }
    }

    private func mergingSourceHistory(
        in latest: ProviderSnapshot,
        previous: ProviderSnapshot?
    ) -> ProviderSnapshot {
        guard let latestDiagnostics = latest.sourceDiagnostics else {
            return latest
        }

        let previousDiagnostics = previous?.sourceDiagnostics ?? []
        let previousByID = Dictionary(
            uniqueKeysWithValues: previousDiagnostics.map { ($0.id, $0) }
        )
        var mergedDiagnostics = latestDiagnostics.map {
            $0.preservingHistory(from: previousByID[$0.id])
        }

        if let refreshTimeout = mergedDiagnostics.first(where: { $0.id == "provider-refresh" }) {
            let latestIDs = Set(mergedDiagnostics.map(\.id))
            mergedDiagnostics += previousDiagnostics
                .filter { latestIDs.contains($0.id) == false }
                .map { previousDiagnostic in
                    ProviderSourceDiagnostic(
                        id: previousDiagnostic.id,
                        name: previousDiagnostic.name,
                        confidence: previousDiagnostic.confidence,
                        status: .failure,
                        attemptedAt: refreshTimeout.attemptedAt,
                        lastSuccessAt: previousDiagnostic.lastSuccessAt,
                        lastFailureAt: refreshTimeout.lastFailureAt
                            ?? refreshTimeout.attemptedAt
                            ?? previousDiagnostic.lastFailureAt,
                        message: "Provider refresh timed out before this source returned."
                    )
                }
        }

        return latest.replacingSourceDiagnostics(mergedDiagnostics)
    }

    private func mergingCodexObservedActivity(
        in latest: ProviderSnapshot,
        previous: ProviderSnapshot?
    ) -> ProviderSnapshot {
        guard latest.id == "codex",
              latest.health == .error,
              latest.sourceDiagnostics?.contains(where: { $0.id == "provider-refresh" }) == true,
              let previous
        else {
            return latest
        }

        let observedMetricIDs: Set<String> = [
            "today-tokens", "30d-tokens", "latest-tokens", "top-model"
        ]
        let existingMetricIDs = Set(latest.metrics.map(\.id))
        let previousObservedMetrics = previous.metrics.filter {
            observedMetricIDs.contains($0.id) && existingMetricIDs.contains($0.id) == false
        }
        let activity = latest.activity ?? previous.activity
        guard previousObservedMetrics.isEmpty == false || activity != nil else {
            return latest
        }

        let preservationNote = "Provider refresh timed out. Showing the last completed Observed local activity; no Codex quota was preserved."
        return ProviderSnapshot(
            id: latest.id,
            name: latest.name,
            kind: latest.kind,
            updatedAt: latest.updatedAt,
            health: latest.health,
            headline: latest.headline,
            metrics: latest.metrics + previousObservedMetrics,
            bars: latest.bars,
            quotaCreditBank: latest.quotaCreditBank,
            activity: activity,
            accounts: latest.accounts,
            sourceDiagnostics: latest.sourceDiagnostics,
            notes: latest.notes.contains(preservationNote)
                ? latest.notes
                : latest.notes + [preservationNote],
            actions: latest.actions.isEmpty ? previous.actions : latest.actions
        )
    }

    private func shouldPreserve(_ snapshot: ProviderSnapshot) -> Bool {
        snapshot.health == .ready
            || snapshot.bars.contains { $0.remainingFraction != nil }
            || snapshot.activity?.contains { $0.value > 0 } == true
            || snapshot.metrics.contains { $0.confidence != .unavailable }
    }

    private func previousSnapshot(
        _ previous: ProviderSnapshot,
        preservingAgainst latestError: ProviderSnapshot
    ) -> ProviderSnapshot {
        let notes = previous.notes
            .filter { $0.hasPrefix("Latest refresh failed:") == false }
            + ["Latest refresh failed: \(latestError.headline). Showing last known data."]

        return ProviderSnapshot(
            id: previous.id,
            name: previous.name,
            kind: previous.kind,
            updatedAt: previous.updatedAt,
            health: previous.health,
            headline: previous.headline,
            metrics: previous.metrics,
            bars: previous.bars,
            quotaCreditBank: previous.quotaCreditBank,
            activity: previous.activity,
            accounts: previous.accounts,
            sourceDiagnostics: latestError.sourceDiagnostics?.map { $0.markingFallback() }
                ?? previous.sourceDiagnostics?.map { $0.markingFallback() },
            notes: notes,
            actions: previous.actions.isEmpty ? latestError.actions : previous.actions
        )
    }

    func refreshIfStale(maxAge: TimeInterval = 20) async {
        if let lastRefreshAt, abs(lastRefreshAt.timeIntervalSinceNow) < maxAge {
            return
        }
        await refresh()
    }

    func saveDeepSeekAPIKey() {
        let trimmedKey = deepSeekAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else {
            settingsMessage = "DeepSeek API key is empty."
            return
        }

        do {
            let credential = try deepSeekCredentialStore.addCredential(
                label: deepSeekAPIKeyLabelInput,
                apiKey: trimmedKey
            )
            reloadDeepSeekCredentials()
            deepSeekAPIKeyLabelInput = ""
            deepSeekAPIKeyInput = ""
            settingsMessage = "\(credential.label) saved to Keychain."
            startDeepSeekProxyIfPossible()
            Task {
                await refresh()
            }
        } catch {
            settingsMessage = "Failed to save key: \(error.localizedDescription)"
        }
    }

    func deleteDeepSeekCredential(id: String) {
        do {
            try deepSeekCredentialStore.deleteCredential(id: id)
            reloadDeepSeekCredentials()
            settingsMessage = "DeepSeek API key deleted."
            startDeepSeekProxyIfPossible()
            Task {
                await refresh()
            }
        } catch {
            settingsMessage = "Failed to delete key: \(error.localizedDescription)"
        }
    }

    func saveOpenRouterAPIKey() {
        let trimmedKey = openRouterAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else {
            openRouterSettingsMessage = "OpenRouter API key is empty."
            return
        }

        do {
            let credential = try openRouterCredentialStore.addCredential(
                label: openRouterAPIKeyLabelInput,
                apiKey: trimmedKey
            )
            reloadOpenRouterCredentials()
            openRouterAPIKeyLabelInput = ""
            openRouterAPIKeyInput = ""
            openRouterSettingsMessage = "\(credential.label) saved to Keychain."
            Task {
                await refresh()
            }
        } catch {
            openRouterSettingsMessage = "Failed to save key: \(error.localizedDescription)"
        }
    }

    func deleteOpenRouterCredential(id: String) {
        do {
            try openRouterCredentialStore.deleteCredential(id: id)
            reloadOpenRouterCredentials()
            openRouterAPIKeyInput = ""
            openRouterSettingsMessage = "OpenRouter API key deleted."
            Task {
                await refresh()
            }
        } catch {
            openRouterSettingsMessage = "Failed to delete key: \(error.localizedDescription)"
        }
    }

    func setDefaultOpenRouterCredential(id: String) {
        do {
            try openRouterCredentialStore.setDefaultCredential(id: id)
            reloadOpenRouterCredentials()
            openRouterSettingsMessage = "Default OpenRouter API key updated."
            Task {
                await refresh()
            }
        } catch {
            openRouterSettingsMessage = "Failed to update default key: \(error.localizedDescription)"
        }
    }

    func setDefaultDeepSeekCredential(id: String) {
        do {
            try deepSeekCredentialStore.setDefaultCredential(id: id)
            reloadDeepSeekCredentials()
            settingsMessage = "Default DeepSeek API key updated."
            startDeepSeekProxyIfPossible()
        } catch {
            settingsMessage = "Failed to update default key: \(error.localizedDescription)"
        }
    }

    func open(_ action: ProviderAction) {
        if action.id == "codex-web-sync" {
            openCodexWebSync()
            return
        }

        guard let url = action.url else { return }
        NSWorkspace.shared.open(url)
    }

    func openCodexWebSync() {
        if codexWebSessionWindow == nil {
            codexWebSessionWindow = CodexWebSessionWindow { [weak self] in
                Task { @MainActor in
                    await self?.refresh()
                }
            }
        }

        codexWebSessionWindow?.show()
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginState = LaunchAtLoginController.currentState()
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        launchAtLoginState = LaunchAtLoginController.setEnabled(isEnabled)
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    private func startDeepSeekProxyIfPossible() {
        let deepSeekCredentialStore = deepSeekCredentialStore
        let credentialProvider: @Sendable (_ requestAPIKey: String?) -> DeepSeekProxyCredential? = { requestAPIKey in
            try? deepSeekCredentialStore.proxyCredential(for: requestAPIKey)
        }

        guard deepSeekCredentials.isEmpty == false else {
            deepSeekProxyServer?.stop()
            deepSeekProxyServer = nil
            deepSeekProxyMessage = "Save a DeepSeek API key to start the local proxy."
            return
        }

        if let existingServer = deepSeekProxyServer {
            switch existingServer.state {
            case .starting, .ready:
                deepSeekProxyMessage = DeepSeekProxyStatusMessage.text(
                    for: existingServer.state,
                    port: existingServer.port
                )
                return
            case .stopped, .failed:
                existingServer.stateUpdateHandler = nil
                existingServer.stop()
                deepSeekProxyServer = nil
            }
        }

        let server = DeepSeekProxyServer(usageStore: usageStore, credentialProvider: credentialProvider)
        server.stateUpdateHandler = { [weak self, weak server] state in
            Task { @MainActor in
                guard
                    let self,
                    let server,
                    self.deepSeekProxyServer === server
                else {
                    return
                }

                self.deepSeekProxyMessage = DeepSeekProxyStatusMessage.text(
                    for: state,
                    port: server.port
                )
            }
        }
        deepSeekProxyServer = server

        do {
            try server.start()
            deepSeekProxyMessage = DeepSeekProxyStatusMessage.text(
                for: server.state,
                port: server.port
            )
        } catch {
            server.stateUpdateHandler = nil
            deepSeekProxyServer = nil
            deepSeekProxyMessage = "DeepSeek proxy failed to start: \(error.localizedDescription)"
        }
    }

    private func reloadDeepSeekCredentials() {
        do {
            deepSeekCredentials = try deepSeekCredentialStore.credentials()
        } catch {
            deepSeekCredentials = []
            settingsMessage = "Failed to load DeepSeek keys: \(error.localizedDescription)"
        }
    }

    private func reloadOpenRouterCredentials() {
        do {
            openRouterCredentials = try openRouterCredentialStore.credentials()
        } catch {
            openRouterCredentials = []
            openRouterSettingsMessage = "Failed to load OpenRouter keys: \(error.localizedDescription)"
        }
    }
}
