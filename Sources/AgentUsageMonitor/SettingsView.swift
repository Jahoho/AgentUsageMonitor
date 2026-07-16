import AgentUsageCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)
                Text("Credentials, sources, and app controls")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
            }

            ProviderDiagnosticsPanel(snapshots: viewModel.snapshots.filter { $0.id != "overview" })

            SettingsPanel(title: "Codex") {
                VStack(spacing: 8) {
                    LoginEntryButton(
                        providerID: "codex",
                        title: "Open Codex",
                        subtitle: "Web app",
                        action: {
                            viewModel.open(
                                ProviderAction(
                                    id: "settings-codex-web",
                                    title: "Open Codex",
                                    url: URL(string: "https://chatgpt.com/codex/")
                                )
                            )
                        }
                    )

                    LoginEntryButton(
                        providerID: "codex",
                        title: "Open Codex Web Debug",
                        subtitle: "Inspect official page",
                        action: {
                            viewModel.openCodexWebSync()
                        }
                    )

                    LoginEntryButton(
                        providerID: "codex",
                        title: "Open Codex pricing",
                        subtitle: "Quota and plan reference",
                        action: {
                            viewModel.open(
                                ProviderAction(
                                    id: "settings-codex-pricing",
                                    title: "Open Codex pricing",
                                    url: URL(string: "https://developers.openai.com/codex/pricing")
                                )
                            )
                        }
                    )
                }
            }

            SettingsPanel(title: "Claude") {
                VStack(spacing: 8) {
                    LoginEntryButton(
                        providerID: "claude",
                        title: "Open Claude account",
                        subtitle: "Subscription settings",
                        action: {
                            viewModel.open(
                                ProviderAction(
                                    id: "settings-claude-login",
                                    title: "Open Claude account",
                                    url: URL(string: "https://claude.ai/settings")
                                )
                            )
                        }
                    )

                    LoginEntryButton(
                        providerID: "claude",
                        title: "Open Claude Code docs",
                        subtitle: "Usage and cost reference",
                        action: {
                            viewModel.open(
                                ProviderAction(
                                    id: "settings-claude-docs",
                                    title: "Open Claude Code docs",
                                    url: URL(string: "https://code.claude.com/docs/en/costs")
                                )
                            )
                        }
                    )
                }
            }

            DeepSeekConfigurationPanel(viewModel: viewModel)

            OpenRouterConfigurationPanel(viewModel: viewModel)

            SettingsPanel(title: "App") {
                VStack(alignment: .leading, spacing: 10) {
                    LaunchAtLoginSettingsRow(
                        state: viewModel.launchAtLoginState,
                        setEnabled: viewModel.setLaunchAtLoginEnabled
                    )

                    Button {
                        viewModel.quitApplication()
                    } label: {
                        Label("Quit Agent Usage Monitor", systemImage: "power")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(ActionButtonStyle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.refreshLaunchAtLoginState()
        }
    }
}

private struct OpenRouterConfigurationPanel: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        SettingsPanel(title: "OpenRouter") {
            VStack(alignment: .leading, spacing: 10) {
                LoginEntryButton(
                    providerID: "openrouter",
                    title: "Open OpenRouter activity",
                    subtitle: "Official requests and spend",
                    action: {
                        viewModel.open(
                            ProviderAction(
                                id: "settings-openrouter-activity",
                                title: "Open OpenRouter activity",
                                url: URL(string: "https://openrouter.ai/activity")
                            )
                        )
                    }
                )

                LoginEntryButton(
                    providerID: "openrouter",
                    title: "Open OpenRouter API keys",
                    subtitle: "Create or rotate provider keys",
                    action: {
                        viewModel.open(
                            ProviderAction(
                                id: "settings-openrouter-keys",
                                title: "Open OpenRouter API keys",
                                url: URL(string: "https://openrouter.ai/settings/keys")
                            )
                        )
                    }
                )

                VStack(spacing: 7) {
                    TextField("Label, e.g. Work key", text: $viewModel.openRouterAPIKeyLabelInput)
                        .textFieldStyle(.roundedBorder)
                    SecureField("sk-or-v1-...", text: $viewModel.openRouterAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    viewModel.saveOpenRouterAPIKey()
                } label: {
                    Label("Add API key", systemImage: "key")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(
                    viewModel.openRouterAPIKeyInput
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )

                if viewModel.openRouterCredentials.isEmpty {
                    Text("No OpenRouter API keys saved.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignSurface.muted)
                } else {
                    VStack(spacing: 7) {
                        ForEach(viewModel.openRouterCredentials) { credential in
                            OpenRouterCredentialRow(
                                credential: credential,
                                makeDefault: {
                                    viewModel.setDefaultOpenRouterCredential(id: credential.id)
                                },
                                delete: {
                                    viewModel.deleteOpenRouterCredential(id: credential.id)
                                }
                            )
                        }
                    }
                }

                if viewModel.openRouterSettingsMessage.isEmpty == false {
                    Text(viewModel.openRouterSettingsMessage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignSurface.muted)
                }

                Text("Standard keys expose their own official spend and limits. A management key additionally unlocks official default-workspace key names, account credits, and per-key model activity for the last 30 completed UTC days. Local estimates are never substituted.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DeepSeekConfigurationPanel: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        SettingsPanel(title: "DeepSeek") {
            VStack(alignment: .leading, spacing: 10) {
                LoginEntryButton(
                    providerID: "deepseek",
                    title: "Open DeepSeek console",
                    subtitle: "Balance, usage, and keys",
                    action: {
                        viewModel.open(
                            ProviderAction(
                                id: "settings-deepseek-console",
                                title: "Open DeepSeek console",
                                url: URL(string: "https://platform.deepseek.com/")
                            )
                        )
                    }
                )

                LoginEntryButton(
                    providerID: "deepseek",
                    title: "Open DeepSeek API keys",
                    subtitle: "Create or rotate provider keys",
                    action: {
                        viewModel.open(
                            ProviderAction(
                                id: "settings-deepseek-keys",
                                title: "Open DeepSeek API keys",
                                url: URL(string: "https://platform.deepseek.com/api_keys")
                            )
                        )
                    }
                )

                VStack(spacing: 7) {
                    TextField("Label, e.g. Work key", text: $viewModel.deepSeekAPIKeyLabelInput)
                        .textFieldStyle(.roundedBorder)
                    SecureField("sk-...", text: $viewModel.deepSeekAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    viewModel.saveDeepSeekAPIKey()
                } label: {
                    Label("Add API key", systemImage: "key")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(ActionButtonStyle())

                if viewModel.deepSeekCredentials.isEmpty {
                    Text("No DeepSeek API keys saved.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignSurface.muted)
                } else {
                    VStack(spacing: 7) {
                        ForEach(viewModel.deepSeekCredentials) { credential in
                            DeepSeekCredentialRow(
                                credential: credential,
                                makeDefault: {
                                    viewModel.setDefaultDeepSeekCredential(id: credential.id)
                                },
                                delete: {
                                    viewModel.deleteDeepSeekCredential(id: credential.id)
                                }
                            )
                        }
                    }
                }

                if viewModel.settingsMessage.isEmpty == false {
                    Text(viewModel.settingsMessage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignSurface.muted)
                }

                Divider()
                    .overlay(DesignSurface.track)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Usage tracking")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSurface.text)
                    Text("Set DeepSeek-compatible clients to this OpenAI-compatible base URL. API keys only unlock official balance checks; website usage history is not backfilled by DeepSeek's public API.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignSurface.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CopyableValue("http://127.0.0.1:18491")
                Text(viewModel.deepSeekProxyMessage)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)

                Text("Today tokens, 30d tokens, and estimated costs update after requests pass through the local proxy.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LaunchAtLoginSettingsRow: View {
    let state: LaunchAtLoginState
    let setEnabled: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "power.circle.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DesignSurface.activity)
                .frame(width: 32, height: 32)
                .background(DesignSurface.track.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Start at login")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)
                Text(state.detailText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { state.isOn },
                set: { setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help(state.statusText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(DesignSurface.track.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DeepSeekCredentialRow: View {
    let credential: DeepSeekCredential
    let makeDefault: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            BrandIcon(providerID: "deepseek", isSelected: false)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(credential.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Stored in Keychain")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
            }

            Spacer(minLength: 6)

            if credential.isDefault {
                ConfidencePill(text: "Default", confidence: .observed)
            } else {
                Button(action: makeDefault) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSurface.muted)
                .help("Use as default proxy key")
            }

            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSurface.muted)
            .help("Delete API key")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(DesignSurface.track.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct OpenRouterCredentialRow: View {
    let credential: OpenRouterCredential
    let makeDefault: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            BrandIcon(providerID: "openrouter", isSelected: false)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(credential.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Stored in Keychain")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
            }

            Spacer(minLength: 6)

            if credential.isDefault {
                ConfidencePill(text: "Default", confidence: .observed)
            } else {
                Button(action: makeDefault) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSurface.muted)
                .help("Use as default display key")
            }

            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSurface.muted)
            .help("Delete API key")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(DesignSurface.track.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProviderDiagnosticsPanel: View {
    let snapshots: [ProviderSnapshot]

    var body: some View {
        SettingsPanel(title: "Provider status") {
            VStack(spacing: 10) {
                ForEach(snapshots) { snapshot in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sourceSummary(for: snapshot))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(DesignSurface.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            ForEach(snapshot.sourceDiagnostics ?? []) { diagnostic in
                                ProviderSourceDiagnosticRow(diagnostic: diagnostic)
                            }

                            ForEach(Array(snapshot.notes.enumerated()), id: \.offset) { _, note in
                                Text(note)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(DesignSurface.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack(spacing: 9) {
                            BrandIcon(providerID: snapshot.id, isSelected: false)
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.name)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(DesignSurface.text)
                                Text(snapshot.headline)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(DesignSurface.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }

                            Spacer()

                            ConfidencePill(text: snapshot.health.rawValue, confidence: confidence(for: snapshot.health))
                        }
                    }
                }
            }
        }
    }

    private func sourceSummary(for snapshot: ProviderSnapshot) -> String {
        let source = snapshot.metrics.first { $0.id == "source" }?.value
        let account = snapshot.metrics.first { $0.id == "account" }?.value
        let updated = snapshot.updatedAt.formatted(date: .omitted, time: .shortened)

        return [
            source.map { "Source: \($0)" },
            account.map { "Account: \($0)" },
            "Updated: \(updated)"
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    private func confidence(for health: ProviderHealth) -> UsageConfidence {
        switch health {
        case .ready:
            return .observed
        case .needsSetup, .unavailable, .error:
            return .unavailable
        }
    }
}

private struct ProviderSourceDiagnosticRow: View {
    let diagnostic: ProviderSourceDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: statusIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 14)

                Text(diagnostic.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSurface.text)

                Spacer(minLength: 6)

                if diagnostic.isFallback {
                    ConfidencePill(text: "Fallback", confidence: .unavailable)
                }

                ConfidencePill(text: diagnostic.status.rawValue, confidence: statusConfidence)
            }

            if timingText.isEmpty == false {
                Text(timingText)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(DesignSurface.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if diagnostic.message.isEmpty == false {
                Text(diagnostic.message)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }

    private var timingText: String {
        [
            diagnostic.lastSuccessAt.map { "Success \(formatted($0))" },
            diagnostic.lastFailureAt.map { "Failure \(formatted($0))" },
            diagnostic.attemptedAt.map { "Attempt \(formatted($0))" }
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    private var statusIcon: String {
        switch diagnostic.status {
        case .success:
            return "checkmark.circle.fill"
        case .partial:
            return "exclamationmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        case .cancelled:
            return "minus.circle.fill"
        case .notAttempted:
            return "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch diagnostic.status {
        case .success:
            return DesignSurface.official
        case .partial:
            return .orange
        case .failure:
            return .red
        case .cancelled, .notAttempted:
            return DesignSurface.muted
        }
    }

    private var statusConfidence: UsageConfidence {
        diagnostic.status == .success ? diagnostic.confidence : .unavailable
    }
}

private struct LoginEntryButton: View {
    let providerID: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                BrandIcon(providerID: providerID, isSelected: false)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSurface.text)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignSurface.muted)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSurface.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ActionButtonStyle())
    }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignSurface.text)
            content
        }
        .padding(12)
        .background(DesignSurface.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CopyableValue: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        HStack {
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignSurface.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DesignSurface.track.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
