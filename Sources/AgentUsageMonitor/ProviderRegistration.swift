import AgentUsageCore

enum ProviderNavigationIcon: Equatable, Sendable {
    case overview
    case brand(resourceName: String)
    case system(symbolName: String)

    var brandResourceName: String? {
        guard case .brand(let resourceName) = self else {
            return nil
        }
        return resourceName
    }
}

struct ProviderNavigationMetadata: Equatable, Sendable {
    let title: String
    let icon: ProviderNavigationIcon
}

struct ProviderRegistration: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let kind: ProviderKind
    let supportsQuotaProjection: Bool
    let navigation: ProviderNavigationMetadata
    let freshnessPolicy: ProviderSnapshotFreshnessPolicy
}

extension ProviderRegistration {
    static let codex = ProviderRegistration(
        id: "codex",
        displayName: "Codex",
        kind: .subscription,
        supportsQuotaProjection: true,
        navigation: ProviderNavigationMetadata(
            title: "Codex",
            icon: .brand(resourceName: "codex")
        ),
        freshnessPolicy: .requireCurrent
    )

    static let claude = ProviderRegistration(
        id: "claude",
        displayName: "Claude",
        kind: .subscription,
        supportsQuotaProjection: false,
        navigation: ProviderNavigationMetadata(
            title: "Claude",
            icon: .brand(resourceName: "claude")
        ),
        freshnessPolicy: .preserveLastKnown
    )

    static let deepSeek = ProviderRegistration(
        id: "deepseek",
        displayName: "DeepSeek",
        kind: .api,
        supportsQuotaProjection: false,
        navigation: ProviderNavigationMetadata(
            title: "DeepSeek",
            icon: .brand(resourceName: "deepseek")
        ),
        freshnessPolicy: .preserveLastKnown
    )

    static let openRouter = ProviderRegistration(
        id: "openrouter",
        displayName: "OpenRouter",
        kind: .api,
        supportsQuotaProjection: false,
        navigation: ProviderNavigationMetadata(
            title: "OpenRouter",
            icon: .brand(resourceName: "openrouter")
        ),
        freshnessPolicy: .requireCurrent
    )
}

struct DashboardNavigationItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let icon: ProviderNavigationIcon
}

enum DashboardNavigation {
    static func items(for registrations: [ProviderRegistration]) -> [DashboardNavigationItem] {
        [
            DashboardNavigationItem(id: "overview", title: "Overview", icon: .overview)
        ] + registrations.map { registration in
            DashboardNavigationItem(
                id: registration.id,
                title: registration.navigation.title,
                icon: registration.navigation.icon
            )
        } + [
            DashboardNavigationItem(
                id: "settings",
                title: "Settings",
                icon: .system(symbolName: "gearshape.fill")
            )
        ]
    }
}

private struct ProviderRegistryEntry: Sendable {
    let registration: ProviderRegistration
    let makeAdapter: @Sendable () -> any ProviderSnapshotAdapter
}

enum ProviderRegistry {
    private static let liveEntries: [ProviderRegistryEntry] = [
        ProviderRegistryEntry(
            registration: .codex,
            makeAdapter: { CodexProviderAdapter() }
        ),
        ProviderRegistryEntry(
            registration: .claude,
            makeAdapter: { ClaudeProviderAdapter() }
        ),
        ProviderRegistryEntry(
            registration: .deepSeek,
            makeAdapter: { DeepSeekProviderAdapter() }
        ),
        ProviderRegistryEntry(
            registration: .openRouter,
            makeAdapter: { OpenRouterProviderAdapter() }
        )
    ]

    static var liveRegistrations: [ProviderRegistration] {
        liveEntries.map(\.registration)
    }

    static func registration(for providerID: String) -> ProviderRegistration? {
        liveEntries.first { $0.registration.id == providerID }?.registration
    }

    static func liveAdapters() -> [any ProviderSnapshotAdapter] {
        liveEntries.map { entry in
            entry.makeAdapter()
        }
    }
}
