# Contributing

Thank you for helping improve Agent Usage Monitor. The project favors small, reviewable changes that preserve source accuracy, local privacy and a native macOS experience.

## Before Starting

- Search existing issues before opening a new one.
- Discuss substantial provider integrations, persistence changes and UI redesigns before implementation.
- Report vulnerabilities through [SECURITY.md](SECURITY.md), never through a public issue.

## Development Setup

Requirements:

- macOS 14 or later
- Xcode 16 or another Swift 6 toolchain

Clone and verify:

```bash
git clone https://github.com/Jahoho/AgentUsageMonitor.git
cd AgentUsageMonitor
swift test --no-parallel
swift run AgentUsageMonitor
```

The project intentionally has no third-party Swift package dependencies.

## Architecture Boundaries

- `AgentUsageCore` owns provider-neutral models, pure parsers, confidence semantics and aggregation.
- `AgentUsageMonitor` owns SwiftUI/AppKit, networking, Keychain, process execution, persistence and provider orchestration.
- Provider-specific behavior belongs in an adapter; the dashboard consumes shared `ProviderSnapshot` models.

Read [Architecture](docs/ARCHITECTURE.md) before changing a provider contract or persistence boundary.

## Data Integrity Rules

Every usage value must be one of:

- `Official`: returned by a current official API, dashboard or CLI surface.
- `Observed`: captured from explicit local telemetry or a response handled by the app.
- `Estimated`: derived from a documented formula and complete required inputs.
- `Unavailable`: no reliable value is currently accessible.

Do not convert missing fields to zero, infer historical usage from a current balance, or present local activity as official subscription quota. Current-source providers must fail visibly when the official response is missing or malformed.

## Security And Privacy

- Never commit credentials, auth files, provider responses, personal logs or local databases.
- Use synthetic fixtures in tests.
- Keep secrets in Keychain and non-secret labels in Application Support.
- Redact provider errors before they enter snapshots or diagnostics.
- Keep local HTTP listeners loopback-only and outbound credentials pinned to the intended authority.
- Update [PRIVACY.md](PRIVACY.md) when a change reads, stores or transmits new data.

Run the repository security check before submitting:

```bash
./scripts/security-check.sh
```

## Testing

For focused changes, run the nearest test target first. Before opening a pull request, run:

```bash
./scripts/release-check.sh
```

UI changes should also be checked in light and dark appearances, with Reduce Motion enabled, and on both sparse and long provider pages. Provider changes should include malformed, unavailable and transient-failure cases, not only successful fixtures.

## Pull Requests

Keep pull requests focused and explain:

- the user-visible problem;
- the source or trust boundary involved;
- how the behavior was verified;
- any remaining limitation.

Use concise commit subjects such as `fix: bound codex rpc cancellation` or `docs: clarify local usage retention`. Update documentation and tests in the same pull request when behavior changes.

By contributing, you agree that your contribution is licensed under the project's [MIT License](LICENSE).
