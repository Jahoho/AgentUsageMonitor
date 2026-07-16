import AgentUsageCore

protocol ProviderSnapshotAdapter: Sendable {
    var registration: ProviderRegistration { get }

    func snapshot() async -> ProviderSnapshot
}

extension ProviderSnapshotAdapter {
    var providerID: String { registration.id }
    var providerName: String { registration.displayName }
    var providerKind: ProviderKind { registration.kind }
}
