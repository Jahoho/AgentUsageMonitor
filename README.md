<p align="center">
  <img src="docs/assets/agent-usage-monitor-icon.png" width="128" height="128" alt="Agent Usage Monitor icon">
</p>

<h1 align="center">Agent Usage Monitor</h1>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  A source-aware macOS menu bar monitor for AI subscription limits, API spend, and observed token activity.
</p>

<p align="center">
  <a href="https://github.com/Jahoho/AgentUsageMonitor/actions/workflows/ci.yml"><img src="https://github.com/Jahoho/AgentUsageMonitor/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2ea44f" alt="MIT License"></a>
</p>

Agent Usage Monitor keeps the usage signals that matter during daily AI-assisted work in one compact native macOS interface. It deliberately separates official provider data from locally observed activity and reports missing data as unavailable instead of filling gaps with guesses.

The initial public release is source-first. The repository is ready to build and verify locally; signed and notarized binary distribution is planned for a later release.

## Provider Coverage

| Provider | Current usage surface | Data source |
| --- | --- | --- |
| Codex | Current quota, reset timing, reset credits, a compact local quota projection, and an expandable weekly recap | Current official ChatGPT Codex API or Codex CLI RPC; projections and recaps use privacy-scoped local official samples |
| Codex activity | Today, rolling 30-day and hourly local token activity | Observed fields from local Codex session logs |
| Claude | Claude Code installation status and official usage entry points | Local CLI availability; exact quota remains unavailable |
| DeepSeek | Account balance | Official `/user/balance` API |
| DeepSeek activity | Per-key tokens, models, hourly activity and strictly priced supported requests | Explicit usage fields captured by the loopback proxy |
| OpenRouter | Key spend, limits and account credits | Official key and credit APIs |
| OpenRouter activity | Managed-key names, model activity and completed daily usage | Official management-key APIs |

More detail, including fallback behavior and known source limits, is documented in [Data Sources](docs/DATA_SOURCES.md).

## Product Principles

- **Source integrity.** Official, observed, estimated and unavailable values are not interchangeable.
- **Fail closed.** Current official surfaces report an error when the provider does not return usable data; stale or synthetic values do not silently replace them.
- **Local control.** API keys stay in macOS Keychain. The project has no hosted backend, analytics service, advertising SDK or maintainer-operated telemetry endpoint.
- **Native focus.** The app is a lightweight SwiftUI/AppKit menu bar utility with a compact adaptive popover and no Dock icon.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or another Swift 6 toolchain
- Apple Silicon or Intel Mac when building from source

The local packaging script produces a binary for the architecture of the build machine. Public universal, signed and notarized binaries are not available yet.

## Build From Source

```bash
git clone https://github.com/Jahoho/AgentUsageMonitor.git
cd AgentUsageMonitor
swift test --no-parallel
swift run AgentUsageMonitor
```

The app appears as a gauge icon in the menu bar. Click it to open the monitor.

To build and verify a local `.app` bundle:

```bash
./scripts/release-check.sh
```

To install that verified local build:

```bash
./scripts/install-app.sh
./scripts/verify-installation.sh
open /Applications/AgentUsageMonitor.app
```

Quit an existing Agent Usage Monitor process before running the installer. The installer verifies a staged replacement and restores the previous app if replacement verification fails.

## Configuration

Provider setup lives inside `Settings` and is documented in [Configuration](docs/CONFIGURATION.md). The most important behaviors are:

- Codex reuses the existing local Codex login; the app never asks for a ChatGPT password.
- DeepSeek supports multiple labeled keys and an optional loopback-only proxy at `127.0.0.1:18491` for explicit usage capture.
- OpenRouter supports multiple labeled keys. Management keys can expose additional official account and activity data.
- Claude remains intentionally limited until a stable, machine-readable official subscription source is available.
- Quota projection appears only on an eligible subscription Coding Plan provider page. Overview and directly billed API-key providers do not show it.

## Privacy And Security

Agent Usage Monitor reads only the provider files and credentials needed for enabled usage surfaces. Derived usage history stays on the Mac, and secrets are not written to project logs or JSON metadata.

Read [Privacy](PRIVACY.md) for the exact local files, network destinations, retention behavior and removal steps. Security issues should follow the private process in [Security Policy](SECURITY.md), not a public issue.

## Development

The package has two layers:

- `AgentUsageCore`: provider-neutral models, pure parsers, confidence semantics and aggregation.
- `AgentUsageMonitor`: macOS UI, provider adapters, networking, Keychain, local process integration and packaging.

Start with the [Documentation Index](docs/README.md), [Architecture](docs/ARCHITECTURE.md) and [Contributing Guide](CONTRIBUTING.md). The full release command runs whitespace checks, repository security checks, the complete automated test suite, a clean Release build and package verification.

## Current Limitations

- The app is not signed or notarized for third-party binary distribution.
- Claude does not expose exact subscription quota in the current adapter.
- Codex local token activity is observed telemetry, not an official account billing total.
- Codex quota projection needs at least five same-cycle Official samples; short windows require 30 continuous minutes, while long windows require 6 hours of sampled coverage and sufficient density. Normal overnight gaps widen uncertainty instead of invalidating all history.
- Codex weekly recap appears only after a completed cycle was observed near its start and reset with at least 15% of the expected five-minute samples. Rhythm ignores changes across gaps longer than four hours; personal baseline needs three earlier complete cycles, while plan fit needs three complete cycles and remains descriptive rather than recommending a plan change.
- DeepSeek historical activity includes only requests that pass through this app's proxy.
- OpenRouter token activity requires a management key and only reflects records returned by the official API.

See the [Roadmap](docs/ROADMAP.md) for the intentionally small next steps.

## License And Trademarks

The project source is available under the [MIT License](LICENSE). Provider names and logos are used only to identify compatible services; they remain the property of their respective owners. See [Notices](NOTICE.md).

Agent Usage Monitor is an independent project and is not affiliated with, endorsed by or sponsored by OpenAI, Anthropic, DeepSeek, OpenRouter or Apple.
