import AgentUsageCore
import Foundation

struct ProviderMonitorService {
    static let defaultTimeoutSeconds: TimeInterval = 25

    private let adapters: [any ProviderSnapshotAdapter]
    private let providerTimeoutSeconds: TimeInterval

    init(
        adapters: [any ProviderSnapshotAdapter] = ProviderRegistry.liveAdapters(),
        providerTimeoutSeconds: TimeInterval = Self.defaultTimeoutSeconds
    ) {
        self.adapters = adapters
        self.providerTimeoutSeconds = providerTimeoutSeconds
    }

    var registrations: [ProviderRegistration] {
        adapters.map(\.registration)
    }

    func registration(for providerID: String) -> ProviderRegistration? {
        registrations.first { $0.id == providerID }
    }

    func loadProviderSnapshots() async -> [ProviderSnapshot] {
        await withTaskGroup(of: (Int, ProviderSnapshot).self) { group in
            for (index, adapter) in adapters.enumerated() {
                group.addTask {
                    (index, await loadSnapshot(from: adapter))
                }
            }

            var snapshots = Array<ProviderSnapshot?>(repeating: nil, count: adapters.count)
            for await (index, snapshot) in group {
                snapshots[index] = snapshot
            }

            return snapshots.compactMap { $0 }
        }
    }

    private func loadSnapshot(from adapter: any ProviderSnapshotAdapter) async -> ProviderSnapshot {
        let timeoutSeconds = providerTimeoutSeconds
        return await withCheckedContinuation { continuation in
            let raceBox = ProviderSnapshotRaceBox()

            let adapterTask = Task.detached(priority: .userInitiated) {
                let snapshot = await adapter.snapshot()
                raceBox.resumeOnce(continuation, returning: snapshot, winner: .adapter)
            }

            let timeoutWorkItem = DispatchWorkItem {
                raceBox.resumeOnce(
                    continuation,
                    returning: timeoutSnapshot(for: adapter),
                    winner: .timeout
                )
            }

            raceBox.setTasks(adapterTask: adapterTask, timeoutWorkItem: timeoutWorkItem)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeoutSeconds,
                execute: timeoutWorkItem
            )
        }
    }

    private func timeoutSnapshot(for adapter: any ProviderSnapshotAdapter) -> ProviderSnapshot {
        let failedAt = Date()
        return ProviderSnapshot(
            id: adapter.providerID,
            name: adapter.providerName,
            kind: adapter.providerKind,
            health: .error,
            headline: "\(adapter.providerName) refresh timed out",
            metrics: [
                UsageMetric(
                    id: "refresh-timeout",
                    label: "Refresh",
                    value: "Timed out",
                    detail: "This provider did not respond within \(Int(providerTimeoutSeconds)) seconds.",
                    confidence: .unavailable
                )
            ],
            bars: [],
            sourceDiagnostics: [
                ProviderSourceDiagnostic(
                    id: "provider-refresh",
                    name: "Provider refresh",
                    confidence: .unavailable,
                    status: .failure,
                    attemptedAt: failedAt,
                    lastFailureAt: failedAt,
                    message: "The provider exceeded the \(Int(providerTimeoutSeconds))-second refresh limit."
                )
            ],
            notes: [
                "The background refresh loop keeps running; only this provider was skipped for this cycle."
            ],
            actions: []
        )
    }
}

private final class ProviderSnapshotRaceBox: @unchecked Sendable {
    enum Winner {
        case adapter
        case timeout
    }

    private let lock = NSLock()
    private var winner: Winner?
    private var adapterTask: Task<Void, Never>?
    private var timeoutWorkItem: DispatchWorkItem?

    func setTasks(adapterTask: Task<Void, Never>, timeoutWorkItem: DispatchWorkItem) {
        let existingWinner: Winner?

        lock.lock()
        existingWinner = winner
        if existingWinner == nil {
            self.adapterTask = adapterTask
            self.timeoutWorkItem = timeoutWorkItem
        }
        lock.unlock()

        switch existingWinner {
        case .adapter:
            timeoutWorkItem.cancel()
        case .timeout:
            adapterTask.cancel()
        case nil:
            break
        }
    }

    func resumeOnce(
        _ continuation: CheckedContinuation<ProviderSnapshot, Never>,
        returning snapshot: ProviderSnapshot,
        winner: Winner
    ) {
        let adapterTaskToCancel: Task<Void, Never>?
        let timeoutWorkItemToCancel: DispatchWorkItem?

        lock.lock()
        guard self.winner == nil else {
            lock.unlock()
            return
        }

        self.winner = winner
        switch winner {
        case .adapter:
            adapterTaskToCancel = nil
            timeoutWorkItemToCancel = timeoutWorkItem
        case .timeout:
            adapterTaskToCancel = adapterTask
            timeoutWorkItemToCancel = nil
        }
        adapterTask = nil
        timeoutWorkItem = nil
        lock.unlock()

        adapterTaskToCancel?.cancel()
        timeoutWorkItemToCancel?.cancel()
        continuation.resume(returning: snapshot)
    }
}
