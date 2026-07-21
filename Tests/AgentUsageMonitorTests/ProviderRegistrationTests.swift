import Testing
@testable import AgentUsageMonitor

@Test func liveProviderRegistrationsDriveNavigationAndFreshness() throws {
    let registrations = ProviderMonitorService().registrations

    #expect(registrations.map(\.id) == ["codex", "claude", "deepseek", "openrouter"])
    #expect(Set(registrations.map(\.id)).count == registrations.count)
    #expect(
        DashboardNavigation.items(for: registrations).map(\.id)
            == ["overview", "codex", "claude", "deepseek", "openrouter", "settings"]
    )

    let codex = try #require(registrations.first { $0.id == "codex" })
    let claude = try #require(registrations.first { $0.id == "claude" })
    let deepSeek = try #require(registrations.first { $0.id == "deepseek" })
    let openRouter = try #require(registrations.first { $0.id == "openrouter" })

    #expect(codex.freshnessPolicy == .requireCurrent)
    #expect(openRouter.freshnessPolicy == .requireCurrent)
    #expect(claude.freshnessPolicy == .preserveLastKnown)
    #expect(deepSeek.freshnessPolicy == .preserveLastKnown)
    #expect(codex.supportsQuotaProjection)
    #expect(claude.supportsQuotaProjection == false)
    #expect(deepSeek.supportsQuotaProjection == false)
    #expect(openRouter.supportsQuotaProjection == false)
    #expect(codex.navigation.icon.brandResourceName == "codex")
    #expect(openRouter.navigation.icon.brandResourceName == "openrouter")
    #expect(ProviderRegistry.liveRegistrations == registrations)
    #expect(ProviderRegistry.registration(for: "deepseek") == deepSeek)
}

@Test func dashboardNavigationUsesRegisteredTitlesAndIcons() {
    let registration = ProviderRegistration(
        id: "example",
        displayName: "Example API",
        kind: .api,
        supportsQuotaProjection: false,
        navigation: ProviderNavigationMetadata(
            title: "Example",
            icon: .brand(resourceName: "example-mark")
        ),
        freshnessPolicy: .requireCurrent
    )

    let items = DashboardNavigation.items(for: [registration])

    #expect(items.map(\.id) == ["overview", "example", "settings"])
    #expect(items[1].title == "Example")
    #expect(items[1].icon.brandResourceName == "example-mark")
}
