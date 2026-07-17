import AgentUsageCore
import CryptoKit
import Foundation

protocol CapacityInsightRecording: Sendable {
    func recordCurrentQuota(from snapshots: [ProviderSnapshot], now: Date) async
}

actor CapacityInsightService: CapacityInsightRecording {
    static let maximumSnapshotAge: TimeInterval = 5 * 60
    static let futureDateTolerance: TimeInterval = 5 * 60

    private let observationStore: any QuotaObservationStoring
    private let secretStore: any SecretStore
    private var cachedScopeKey: SymmetricKey?

    init(
        observationStore: any QuotaObservationStoring = QuotaObservationStore(),
        secretStore: any SecretStore = KeychainStore(service: "AgentUsageMonitor")
    ) {
        self.observationStore = observationStore
        self.secretStore = secretStore
    }

    func recordCurrentQuota(from snapshots: [ProviderSnapshot], now: Date = Date()) async {
        do {
            let observations = try observations(from: snapshots, now: now)
            guard observations.isEmpty == false else {
                return
            }
            try await observationStore.record(observations, now: now)
        } catch {
            // Historical analysis is optional and must never affect current provider health.
        }
    }

    private func observations(
        from snapshots: [ProviderSnapshot],
        now: Date
    ) throws -> [QuotaObservation] {
        var observations: [QuotaObservation] = []

        for snapshot in snapshots where snapshot.id == "codex" {
            guard snapshot.kind == .subscription,
                  snapshot.health == .ready,
                  snapshot.sourceDiagnostics?.contains(where: { diagnostic in
                      diagnostic.confidence == .official
                          && diagnostic.status == .success
                          && diagnostic.isFallback == false
                  }) == true,
                  snapshot.sourceDiagnostics?.contains(where: \.isFallback) != true,
                  isFresh(snapshot.updatedAt, now: now),
                  let accountIdentity = officialAccountIdentity(in: snapshot)
            else {
                continue
            }

            let accountScopeID = try opaqueScopeID(
                providerID: snapshot.id,
                accountIdentity: accountIdentity
            )

            for bar in snapshot.bars {
                guard bar.confidence == .official,
                      let remainingFraction = bar.remainingFraction,
                      remainingFraction.isFinite,
                      (0...1).contains(remainingFraction),
                      let resetAt = bar.resetAt,
                      resetAt > snapshot.updatedAt
                else {
                    continue
                }

                observations.append(
                    QuotaObservation(
                        providerID: snapshot.id,
                        accountScopeID: accountScopeID,
                        quotaID: bar.id,
                        remainingFraction: remainingFraction,
                        capturedAt: snapshot.updatedAt,
                        resetAt: resetAt
                    )
                )
            }
        }

        return observations
    }

    private func officialAccountIdentity(in snapshot: ProviderSnapshot) -> String? {
        guard let accountMetric = snapshot.metrics.first(where: { metric in
            metric.id == "account" && metric.confidence == .official
        }) else {
            return nil
        }

        let normalized = accountMetric.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func isFresh(_ capturedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        return age <= Self.maximumSnapshotAge && age >= -Self.futureDateTolerance
    }

    private func opaqueScopeID(providerID: String, accountIdentity: String) throws -> String {
        let key = try scopeKey()
        let message = Data("\(providerID)\u{0}\(accountIdentity)".utf8)
        let digest = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func scopeKey() throws -> SymmetricKey {
        if let cachedScopeKey {
            return cachedScopeKey
        }

        if let encodedKey = try secretStore.read(account: KeychainAccount.quotaHistoryScopeKey) {
            guard let data = Data(base64Encoded: encodedKey), data.count == 32 else {
                throw CapacityInsightError.invalidScopeKey
            }
            let key = SymmetricKey(data: data)
            cachedScopeKey = key
            return key
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try secretStore.save(
            data.base64EncodedString(),
            account: KeychainAccount.quotaHistoryScopeKey
        )
        cachedScopeKey = key
        return key
    }
}

private enum CapacityInsightError: Error {
    case invalidScopeKey
}
