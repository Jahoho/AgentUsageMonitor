import AgentUsageCore
import Foundation

struct DeepSeekProviderAdapter: ProviderSnapshotAdapter, @unchecked Sendable {
    let registration = ProviderRegistration.deepSeek

    private let credentialStore: any DeepSeekCredentialStoring
    private let usageStore: any UsageEventStoring
    private let balanceClient: any DeepSeekBalanceFetching

    init(
        credentialStore: any DeepSeekCredentialStoring = DeepSeekCredentialStore(),
        usageStore: any UsageEventStoring = JSONUsageEventStore(),
        balanceClient: any DeepSeekBalanceFetching = DeepSeekBalanceClient()
    ) {
        self.credentialStore = credentialStore
        self.usageStore = usageStore
        self.balanceClient = balanceClient
    }

    func snapshot() async -> ProviderSnapshot {
        let attemptedAt = Date()
        do {
            let credentials = try credentialStore.credentials()
            guard credentials.isEmpty == false else {
                return ProviderSnapshot(
                    id: "deepseek",
                    name: "DeepSeek",
                    kind: .api,
                    health: .needsSetup,
                    headline: "Add a DeepSeek API key",
                    metrics: [
                        UsageMetric(
                            id: "balance",
                            label: "Balance",
                            value: "Not configured",
                            detail: "Save one or more keys under Settings -> DeepSeek.",
                            confidence: .unavailable
                        )
                    ],
                    bars: [],
                    sourceDiagnostics: [
                        ProviderSourceDiagnostic(
                            id: "deepseek-balance-api",
                            name: "Official balance API",
                            confidence: .official,
                            status: .notAttempted,
                            message: "No API key is configured."
                        )
                    ],
                    notes: [
                        "The key will be stored in macOS Keychain.",
                        "Balance is queried from DeepSeek's official API.",
                        "Website usage history is not imported unless DeepSeek exposes a stable official API."
                    ],
                    actions: [
                        ProviderAction(
                            id: "deepseek-console",
                            title: "Open DeepSeek Console",
                            url: URL(string: "https://platform.deepseek.com/")
                        )
                    ]
                )
            }

            async let eventsTask = usageStore.load(providerID: "deepseek")
            var resolvedCredentials: [DeepSeekResolvedCredential] = []
            var unresolvedAccounts: [String: DeepSeekBalanceAccount] = [:]
            for credential in credentials {
                do {
                    guard let apiKey = try credentialStore.readSecret(for: credential.id) else {
                        unresolvedAccounts[credential.id] = DeepSeekBalanceAccount(
                            id: credential.id,
                            label: credential.label,
                            isDefault: credential.isDefault,
                            response: nil,
                            errorMessage: "Missing Keychain item"
                        )
                        continue
                    }
                    resolvedCredentials.append(
                        DeepSeekResolvedCredential(credential: credential, apiKey: apiKey)
                    )
                } catch {
                    unresolvedAccounts[credential.id] = DeepSeekBalanceAccount(
                        id: credential.id,
                        label: credential.label,
                        isDefault: credential.isDefault,
                        response: nil,
                        errorMessage: error.localizedDescription
                    )
                }
            }

            let balanceOutcomes = await fetchBalances(for: resolvedCredentials)
            let outcomesByCredentialID = Dictionary(
                uniqueKeysWithValues: balanceOutcomes.map { ($0.credential.id, $0) }
            )
            let accounts = credentials.map { credential in
                if let unresolvedAccount = unresolvedAccounts[credential.id] {
                    return unresolvedAccount
                }
                guard let outcome = outcomesByCredentialID[credential.id] else {
                    return DeepSeekBalanceAccount(
                        id: credential.id,
                        label: credential.label,
                        isDefault: credential.isDefault,
                        response: nil,
                        errorMessage: "Official balance request did not complete."
                    )
                }

                if let response = outcome.response {
                    return DeepSeekBalanceAccount(
                        id: credential.id,
                        label: credential.label,
                        isDefault: credential.isDefault,
                        response: response
                    )
                }
                return DeepSeekBalanceAccount(
                    id: credential.id,
                    label: credential.label,
                    isDefault: credential.isDefault,
                    response: nil,
                    errorMessage: outcome.errorDescription
                )
            }

            let events = await eventsTask
            let summary = UsageSummarizer.summarize(events: events)
            let costSummary = DeepSeekCostEstimator.summarize(events: events)
            let activity = UsageActivitySummarizer.todayHourlyBuckets(events: events)
            let successfulBalanceCount = accounts.filter { $0.response != nil }.count
            let failedBalanceCount = accounts.count - successfulBalanceCount
            let balanceStatus: ProviderSourceStatus
            if successfulBalanceCount == 0 {
                balanceStatus = .failure
            } else if failedBalanceCount > 0 {
                balanceStatus = .partial
            } else {
                balanceStatus = .success
            }
            let balanceDiagnostic = ProviderSourceDiagnostic(
                id: "deepseek-balance-api",
                name: "Official balance API",
                confidence: .official,
                status: balanceStatus,
                attemptedAt: attemptedAt,
                lastSuccessAt: successfulBalanceCount > 0 ? attemptedAt : nil,
                lastFailureAt: failedBalanceCount > 0 ? attemptedAt : nil,
                message: "\(successfulBalanceCount)/\(accounts.count) key balance request(s) returned official data."
            )

            return DeepSeekSnapshotFactory.snapshot(
                from: accounts,
                usageSummary: summary,
                costSummary: costSummary,
                activity: activity,
                events: events
            ).replacingSourceDiagnostics([balanceDiagnostic])
        } catch {
            return ProviderSnapshot(
                id: "deepseek",
                name: "DeepSeek",
                kind: .api,
                health: .error,
                headline: "DeepSeek balance query failed",
                metrics: [
                    UsageMetric(
                        id: "error",
                        label: "Error",
                        value: "Check key",
                        detail: error.localizedDescription,
                        confidence: .unavailable
                    )
                ],
                bars: [],
                sourceDiagnostics: [
                    ProviderSourceDiagnostic(
                        id: "deepseek-balance-api",
                        name: "Official balance API",
                        confidence: .official,
                        status: .failure,
                        attemptedAt: attemptedAt,
                        lastFailureAt: attemptedAt,
                        message: error.localizedDescription
                    )
                ],
                notes: [
                    "The app did not store or print your API key.",
                    "Open the console to verify the key and account balance."
                ],
                actions: [
                    ProviderAction(
                        id: "deepseek-console",
                        title: "Open DeepSeek Console",
                        url: URL(string: "https://platform.deepseek.com/")
                    )
                ]
            )
        }
    }

    private func fetchBalances(
        for credentials: [DeepSeekResolvedCredential]
    ) async -> [DeepSeekBalanceOutcome] {
        let balanceClient = balanceClient
        return await withTaskGroup(of: DeepSeekBalanceOutcome.self) { group in
            for resolved in credentials {
                group.addTask {
                    do {
                        let response = try await balanceClient.fetchBalance(apiKey: resolved.apiKey)
                        return DeepSeekBalanceOutcome(
                            credential: resolved.credential,
                            response: response,
                            errorDescription: nil
                        )
                    } catch {
                        return DeepSeekBalanceOutcome(
                            credential: resolved.credential,
                            response: nil,
                            errorDescription: error.localizedDescription.replacingOccurrences(
                                of: resolved.apiKey,
                                with: "[redacted]"
                            )
                        )
                    }
                }
            }

            var outcomes: [DeepSeekBalanceOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }
    }
}

private struct DeepSeekBalanceOutcome: Sendable {
    let credential: DeepSeekCredential
    let response: DeepSeekBalanceResponse?
    let errorDescription: String?
}
