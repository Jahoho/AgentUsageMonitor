enum ProviderSnapshotFreshnessPolicy: Equatable, Sendable {
    case preserveLastKnown
    case requireCurrent

    var canPreservePreviousSnapshot: Bool {
        self == .preserveLastKnown
    }
}
