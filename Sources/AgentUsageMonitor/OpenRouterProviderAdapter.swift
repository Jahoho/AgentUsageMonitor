import AgentUsageCore
import Foundation

struct OpenRouterProviderAdapter: ProviderSnapshotAdapter {
    let registration = ProviderRegistration.openRouter

    private let credentialStore: any OpenRouterCredentialStoring
    private let usageClient: any OpenRouterUsageFetching
    private let maximumActivityKeyCount = 50

    init(
        credentialStore: any OpenRouterCredentialStoring = OpenRouterCredentialStore(),
        usageClient: any OpenRouterUsageFetching = OpenRouterUsageClient()
    ) {
        self.credentialStore = credentialStore
        self.usageClient = usageClient
    }

    func snapshot() async -> ProviderSnapshot {
        let attemptedAt = Date()
        do {
            let credentials = try credentialStore.credentials()
            guard credentials.isEmpty == false else {
                return setupSnapshot()
            }

            var resolvedCredentials: [OpenRouterResolvedCredential] = []
            var unresolvedAccounts: [String: ProviderAccountSnapshot] = [:]
            for credential in credentials {
                do {
                    guard let apiKey = try credentialStore.readSecret(for: credential.id) else {
                        unresolvedAccounts[credential.id] = missingSecretAccount(for: credential)
                        continue
                    }
                    resolvedCredentials.append(
                        OpenRouterResolvedCredential(credential: credential, apiKey: apiKey)
                    )
                } catch {
                    unresolvedAccounts[credential.id] = errorAccount(
                        for: credential,
                        message: error.localizedDescription
                    )
                }
            }
            let selection = uniqueResolvedCredentials(resolvedCredentials)
            let outcomes = await fetchCurrentUsage(for: selection.credentials)
            let outcomesByCredentialID = Dictionary(
                uniqueKeysWithValues: outcomes.map { ($0.resolved.credential.id, $0) }
            )
            let selectedCredentialIDs = Set(selection.credentials.map(\.credential.id))

            var accounts: [ProviderAccountSnapshot] = []
            var notes = selection.notes
            var managementCandidates: [OpenRouterManagementCandidate] = []
            var primaryAccountID: String?
            var credits: OpenRouterCreditsInfo?

            for credential in credentials {
                if let unresolvedAccount = unresolvedAccounts[credential.id] {
                    accounts.append(unresolvedAccount)
                    continue
                }

                guard selectedCredentialIDs.contains(credential.id) else {
                    continue
                }

                guard let outcome = outcomesByCredentialID[credential.id] else {
                    accounts.append(errorAccount(for: credential, message: "Official usage request did not complete."))
                    continue
                }

                if let result = outcome.result {
                    let isManagementKey = result.usage.key.isManagementKey == true
                    let accountUsage = OpenRouterAccountUsage(
                        id: savedAccountID(credential.id),
                        name: credential.label,
                        detail: savedCredentialDetail(
                            credential: credential,
                            key: result.usage.key,
                            apiKey: outcome.resolved.apiKey
                        ),
                        nameConfidence: .observed,
                        isDefault: credential.isDefault,
                        key: result.usage.key,
                        activityNote: isManagementKey
                            ? "Management keys administer account data and do not make inference requests."
                            : nil
                    )
                    accounts.append(OpenRouterSnapshotFactory.accountSnapshot(from: accountUsage))
                    appendUnique(
                        result.notes.map { sanitized($0, secrets: [outcome.resolved.apiKey]) },
                        to: &notes
                    )

                    if credential.isDefault {
                        primaryAccountID = savedAccountID(credential.id)
                    }
                    if isManagementKey {
                        managementCandidates.append(
                            OpenRouterManagementCandidate(
                                apiKey: outcome.resolved.apiKey,
                                credentialLabel: credential.label
                            )
                        )
                        if credits == nil {
                            credits = result.usage.credits
                        }
                    }
                } else {
                    accounts.append(
                        errorAccount(
                            for: credential,
                            message: outcome.errorDescription ?? "Official usage sync failed."
                        )
                    )
                }
            }

            if let catalog = await firstAvailableManagementCatalog(
                candidates: managementCandidates,
                notes: &notes
            ) {
                let managedAccounts = await managedAccountSnapshots(
                    keys: catalog.keys,
                    managementAPIKey: catalog.apiKey,
                    notes: &notes
                )
                accounts.append(contentsOf: managedAccounts)
            }

            let successfulCurrentUsageCount = outcomes.filter { $0.result != nil }.count
            let currentUsageRequestCount = outcomes.count + unresolvedAccounts.count
            let failedCurrentUsageCount = currentUsageRequestCount - successfulCurrentUsageCount
            let currentUsageStatus: ProviderSourceStatus
            if successfulCurrentUsageCount == 0 {
                currentUsageStatus = .failure
            } else if failedCurrentUsageCount > 0 {
                currentUsageStatus = .partial
            } else {
                currentUsageStatus = .success
            }
            let currentUsageDiagnostic = ProviderSourceDiagnostic(
                id: "openrouter-current-key-api",
                name: "Official current-key API",
                confidence: .official,
                status: currentUsageStatus,
                attemptedAt: attemptedAt,
                lastSuccessAt: successfulCurrentUsageCount > 0 ? attemptedAt : nil,
                lastFailureAt: failedCurrentUsageCount > 0 ? attemptedAt : nil,
                message: "\(successfulCurrentUsageCount)/\(currentUsageRequestCount) eligible key request(s) returned official usage."
            )

            return OpenRouterSnapshotFactory.snapshot(
                accounts: accounts,
                primaryAccountID: primaryAccountID,
                credits: credits,
                additionalNotes: notes
            ).replacingSourceDiagnostics([currentUsageDiagnostic])
        } catch {
            return errorSnapshot(error, redacting: nil, attemptedAt: attemptedAt)
        }
    }

    private func fetchCurrentUsage(
        for credentials: [OpenRouterResolvedCredential]
    ) async -> [OpenRouterCurrentUsageOutcome] {
        let usageClient = usageClient
        return await withTaskGroup(of: OpenRouterCurrentUsageOutcome.self) { group in
            for resolved in credentials {
                group.addTask {
                    do {
                        let result = try await usageClient.fetchUsage(apiKey: resolved.apiKey)
                        return OpenRouterCurrentUsageOutcome(
                            resolved: resolved,
                            result: result,
                            errorDescription: nil
                        )
                    } catch {
                        return OpenRouterCurrentUsageOutcome(
                            resolved: resolved,
                            result: nil,
                            errorDescription: sanitized(error.localizedDescription, secrets: [resolved.apiKey])
                        )
                    }
                }
            }

            var outcomes: [OpenRouterCurrentUsageOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }
    }

    private func firstAvailableManagementCatalog(
        candidates: [OpenRouterManagementCandidate],
        notes: inout [String]
    ) async -> OpenRouterManagementCatalog? {
        for candidate in candidates {
            do {
                let keys = try await usageClient.fetchManagedKeys(apiKey: candidate.apiKey)
                return OpenRouterManagementCatalog(apiKey: candidate.apiKey, keys: keys)
            } catch {
                if Task.isCancelled {
                    return nil
                }
                let message = sanitized(error.localizedDescription, secrets: [candidate.apiKey])
                appendUnique(
                    ["Official key catalog sync via \(candidate.credentialLabel) failed: \(message)"],
                    to: &notes
                )
            }
        }
        return nil
    }

    private func managedAccountSnapshots(
        keys: [OpenRouterManagedKeyInfo],
        managementAPIKey: String,
        notes: inout [String]
    ) async -> [ProviderAccountSnapshot] {
        let activityKeys = Array(keys.prefix(maximumActivityKeyCount))
        let activityOutcomes = await fetchManagedActivity(
            for: activityKeys,
            managementAPIKey: managementAPIKey
        )
        let activityByHash = Dictionary(uniqueKeysWithValues: activityOutcomes.map { ($0.keyHash, $0) })

        if keys.count > maximumActivityKeyCount {
            appendUnique(
                [
                    "Official activity was requested for the first \(maximumActivityKeyCount) keys only; "
                        + "the remaining \(keys.count - maximumActivityKeyCount) key profiles still show official spend and limits."
                ],
                to: &notes
            )
        }

        return keys.map { key in
            let outcome = activityByHash[key.hash]
            let activityNote: String?
            if outcome == nil, keys.count > maximumActivityKeyCount {
                activityNote = "Activity was not requested because this account exceeds the 50-key refresh safety limit."
            } else {
                activityNote = nil
            }

            let usage = OpenRouterAccountUsage(
                id: managedAccountID(key.hash),
                name: managedKeyName(key),
                detail: managedKeyDetail(key),
                sourceDetail: "OpenRouter GET /api/v1/keys and /api/v1/activity",
                key: key.keyInfo,
                activity: outcome?.activity,
                activityError: outcome?.errorDescription,
                activityNote: activityNote
            )
            return OpenRouterSnapshotFactory.accountSnapshot(from: usage)
        }
    }

    private func fetchManagedActivity(
        for keys: [OpenRouterManagedKeyInfo],
        managementAPIKey: String
    ) async -> [OpenRouterActivityOutcome] {
        let usageClient = usageClient
        return await withTaskGroup(of: OpenRouterActivityOutcome.self) { group in
            for key in keys {
                group.addTask {
                    do {
                        let activity = try await usageClient.fetchActivity(
                            apiKey: managementAPIKey,
                            keyHash: key.hash
                        )
                        return OpenRouterActivityOutcome(
                            keyHash: key.hash,
                            activity: activity,
                            errorDescription: nil
                        )
                    } catch {
                        return OpenRouterActivityOutcome(
                            keyHash: key.hash,
                            activity: nil,
                            errorDescription: sanitized(
                                error.localizedDescription,
                                secrets: [managementAPIKey]
                            )
                        )
                    }
                }
            }

            var outcomes: [OpenRouterActivityOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }
    }

    private func uniqueResolvedCredentials(
        _ credentials: [OpenRouterResolvedCredential]
    ) -> (credentials: [OpenRouterResolvedCredential], notes: [String]) {
        let groups = Dictionary(grouping: credentials, by: \.apiKey)
        var selected: [OpenRouterResolvedCredential] = []
        var notes: [String] = []

        for group in groups.values {
            let sorted = group.sorted {
                if $0.credential.isDefault != $1.credential.isDefault {
                    return $0.credential.isDefault
                }
                return $0.credential.createdAt < $1.credential.createdAt
            }
            guard let first = sorted.first else { continue }
            selected.append(first)

            for duplicate in sorted.dropFirst() {
                notes.append(
                    "Duplicate saved credential \(duplicate.credential.label) uses the same API key as "
                        + "\(first.credential.label) and was omitted from usage display."
                )
            }
        }

        selected.sort { $0.credential.createdAt < $1.credential.createdAt }
        return (selected, notes)
    }

    private func setupSnapshot() -> ProviderSnapshot {
        ProviderSnapshot(
            id: providerID,
            name: providerName,
            kind: providerKind,
            health: .needsSetup,
            headline: "Add an OpenRouter API key",
            metrics: [
                UsageMetric(
                    id: "source",
                    label: "Source",
                    value: "Not configured",
                    detail: "Save an OpenRouter key under Settings -> OpenRouter.",
                    confidence: .unavailable
                )
            ],
            bars: [],
            sourceDiagnostics: [
                ProviderSourceDiagnostic(
                    id: "openrouter-current-key-api",
                    name: "Official current-key API",
                    confidence: .official,
                    status: .notAttempted,
                    message: "No API key is configured."
                )
            ],
            notes: [
                "Keys are stored as separate entries in macOS Keychain.",
                "Usage will be read only from OpenRouter's official APIs."
            ],
            actions: OpenRouterSnapshotFactory.actions
        )
    }

    private func missingSecretAccount(for credential: OpenRouterCredential) -> ProviderAccountSnapshot {
        errorAccount(for: credential, message: "The Keychain secret for this credential is missing.")
    }

    private func errorAccount(
        for credential: OpenRouterCredential,
        message: String
    ) -> ProviderAccountSnapshot {
        ProviderAccountSnapshot(
            id: savedAccountID(credential.id),
            name: credential.label,
            detail: "Local credential label",
            isDefault: credential.isDefault,
            health: .error,
            metrics: [
                UsageMetric(
                    id: "source",
                    label: "Source",
                    value: "Official API failed",
                    detail: message,
                    confidence: .unavailable
                )
            ],
            notes: ["No cached, observed, or estimated usage is shown for this key."]
        )
    }

    private func errorSnapshot(
        _ error: Error,
        redacting apiKey: String?,
        attemptedAt: Date
    ) -> ProviderSnapshot {
        let secrets = apiKey.map { [$0] } ?? []
        let errorDescription = sanitized(error.localizedDescription, secrets: secrets)

        return ProviderSnapshot(
            id: providerID,
            name: providerName,
            kind: providerKind,
            health: .error,
            headline: "OpenRouter official usage sync failed",
            metrics: [
                UsageMetric(
                    id: "source",
                    label: "Source",
                    value: "Official API failed",
                    detail: errorDescription,
                    confidence: .unavailable
                )
            ],
            bars: [],
            activity: nil,
            sourceDiagnostics: [
                ProviderSourceDiagnostic(
                    id: "openrouter-current-key-api",
                    name: "Official current-key API",
                    confidence: .official,
                    status: .failure,
                    attemptedAt: attemptedAt,
                    lastFailureAt: attemptedAt,
                    message: errorDescription
                )
            ],
            notes: [
                "No cached, locally observed, or estimated usage is shown after an official sync failure.",
                "The app does not store or print your API key outside macOS Keychain."
            ],
            actions: OpenRouterSnapshotFactory.actions
        )
    }

    private func savedCredentialDetail(
        credential: OpenRouterCredential,
        key: OpenRouterKeyInfo,
        apiKey: String
    ) -> String {
        var parts = [
            "Local label",
            key.isManagementKey == true ? "Official management key" : "Official current key"
        ]
        let label = sanitized(key.label ?? "", secrets: [apiKey])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty == false {
            parts.append("Official label: \(label)")
        }
        if credential.isDefault {
            parts.append("Default")
        }
        return parts.joined(separator: "; ")
    }

    private func managedKeyName(_ key: OpenRouterManagedKeyInfo) -> String {
        for candidate in [key.name, key.label] {
            let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty == false {
                return value
            }
        }
        return "Key \(key.hash.prefix(8))"
    }

    private func managedKeyDetail(_ key: OpenRouterManagedKeyInfo) -> String {
        var parts = ["Official management key catalog"]
        if let label = key.label?.trimmingCharacters(in: .whitespacesAndNewlines),
           label.isEmpty == false,
           label != managedKeyName(key) {
            parts.append("Official label: \(label)")
        }
        if key.disabled {
            parts.append("Disabled")
        }
        if let workspaceID = key.workspaceID, workspaceID.isEmpty == false {
            parts.append("Workspace: \(workspaceID)")
        }
        return parts.joined(separator: "; ")
    }

    private func savedAccountID(_ credentialID: String) -> String {
        "saved-\(credentialID)"
    }

    private func managedAccountID(_ keyHash: String) -> String {
        "managed-\(keyHash)"
    }
}

private struct OpenRouterCurrentUsageOutcome: Sendable {
    let resolved: OpenRouterResolvedCredential
    let result: OpenRouterUsageFetchResult?
    let errorDescription: String?
}

private struct OpenRouterManagementCandidate: Sendable {
    let apiKey: String
    let credentialLabel: String
}

private struct OpenRouterManagementCatalog: Sendable {
    let apiKey: String
    let keys: [OpenRouterManagedKeyInfo]
}

private struct OpenRouterActivityOutcome: Sendable {
    let keyHash: String
    let activity: [OpenRouterActivityItem]?
    let errorDescription: String?
}

private func sanitized(_ message: String, secrets: [String]) -> String {
    secrets.reduce(message) { result, secret in
        guard secret.isEmpty == false else { return result }
        return result.replacingOccurrences(of: secret, with: "[redacted]")
    }
}

private func appendUnique(_ messages: [String], to destination: inout [String]) {
    for message in messages where message.isEmpty == false && destination.contains(message) == false {
        destination.append(message)
    }
}
