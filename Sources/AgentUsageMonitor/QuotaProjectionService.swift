import AgentUsageCore
import CryptoKit
import Foundation

protocol QuotaProjectionProviding: Sendable {
    func refreshProjections(
        from snapshots: [ProviderSnapshot],
        now: Date
    ) async -> [String: QuotaProjection]
}

actor QuotaProjectionService: QuotaProjectionProviding {
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

    func refreshProjections(
        from snapshots: [ProviderSnapshot],
        now: Date = Date()
    ) async -> [String: QuotaProjection] {
        guard let snapshot = snapshots.first(where: { $0.id == "codex" }) else {
            return [:]
        }
        if let reason = Self.currentUnavailabilityReason(for: snapshot, now: now) {
            return unavailable(reason, now: now)
        }
        guard let accountIdentity = Self.officialAccountIdentity(in: snapshot) else {
            return unavailable(.accountScopeUnavailable, now: now)
        }

        do {
            let accountScopeID = try opaqueScopeID(
                providerID: snapshot.id,
                accountIdentity: accountIdentity
            )
            let current = quotaObservations(
                from: snapshot,
                accountScopeID: accountScopeID,
                now: now
            )
            guard current.isEmpty == false else {
                let reason: QuotaProjectionAvailabilityReason = Self.hasOfficialRemainingQuota(snapshot)
                    ? .resetUnavailable
                    : .currentQuotaUnavailable
                return unavailable(reason, now: now)
            }

            try await observationStore.record(current, now: now)
            let history = try await observationStore.load(now: now)
            guard let projection = QuotaProjectionAnalyzer.analyze(
                current: current,
                history: history,
                now: now
            ) else {
                return unavailable(.insufficientHistory, now: now)
            }
            return [snapshot.id: projection]
        } catch {
            // History and projections are optional and must never affect current provider health.
            return unavailable(.historyUnavailable, now: now)
        }
    }

    nonisolated static func currentUnavailabilityReason(
        for snapshot: ProviderSnapshot,
        now: Date
    ) -> QuotaProjectionAvailabilityReason? {
        guard snapshot.kind == .subscription,
              snapshot.health == .ready,
              snapshot.sourceDiagnostics?.contains(where: { diagnostic in
                diagnostic.confidence == .official
                    && diagnostic.status == .success
                    && diagnostic.isFallback == false
              }) == true,
              snapshot.sourceDiagnostics?.contains(where: \.isFallback) != true,
              isFresh(snapshot.updatedAt, now: now)
        else {
            return .currentQuotaUnavailable
        }
        guard officialAccountIdentity(in: snapshot) != nil else {
            return .accountScopeUnavailable
        }
        guard snapshot.bars.contains(where: { bar in
            bar.confidence == .official
                && bar.remainingFraction?.isFinite == true
                && bar.remainingFraction.map { (0...1).contains($0) } == true
                && bar.resetAt.map { $0 > now } == true
        }) else {
            return hasOfficialRemainingQuota(snapshot)
                ? .resetUnavailable
                : .currentQuotaUnavailable
        }
        return nil
    }

    private func quotaObservations(
        from snapshot: ProviderSnapshot,
        accountScopeID: String,
        now: Date
    ) -> [QuotaObservation] {
        snapshot.bars.compactMap { bar in
            guard bar.confidence == .official,
                  let remainingFraction = bar.remainingFraction,
                  remainingFraction.isFinite,
                  (0...1).contains(remainingFraction),
                  let resetAt = bar.resetAt,
                  resetAt > now
            else {
                return nil
            }

            return QuotaObservation(
                providerID: snapshot.id,
                accountScopeID: accountScopeID,
                quotaID: bar.id,
                remainingFraction: remainingFraction,
                capturedAt: snapshot.updatedAt,
                resetAt: resetAt
            )
        }
    }

    private nonisolated static func hasOfficialRemainingQuota(_ snapshot: ProviderSnapshot) -> Bool {
        snapshot.bars.contains { bar in
            bar.confidence == .official
                && bar.remainingFraction?.isFinite == true
                && bar.remainingFraction.map { (0...1).contains($0) } == true
        }
    }

    private func unavailable(
        _ reason: QuotaProjectionAvailabilityReason,
        now: Date
    ) -> [String: QuotaProjection] {
        [
            "codex": QuotaProjection.unavailable(
                providerID: "codex",
                reason: reason,
                generatedAt: now
            )
        ]
    }

    private nonisolated static func officialAccountIdentity(in snapshot: ProviderSnapshot) -> String? {
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

    private nonisolated static func isFresh(_ capturedAt: Date, now: Date) -> Bool {
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
                throw QuotaProjectionServiceError.invalidScopeKey
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

private enum QuotaProjectionServiceError: Error {
    case invalidScopeKey
}
