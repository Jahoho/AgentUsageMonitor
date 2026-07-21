# Changelog

Notable user-visible changes are documented here. The project follows semantic versioning once a public tag is published.

## [Unreleased]

### Added

- Privacy-scoped local history for eligible current official Codex quota samples.
- A compact Estimated Codex quota projection in Overview and the Codex detail page, showing a remaining-at-reset range or possible exhaustion while suppressing sparse and unstable forecasts.

### Planned

- Weekly Codex subscription review aligned to official reset cycles.
- Signed and notarized macOS distribution.
- Additional providers only when a stable official or explicitly observed usage source is available.

## [0.1.0] - 2026-07-16

### Added

- Native macOS menu bar application with adaptive popover sizing and anchored page transitions.
- Provider-neutral usage, confidence, activity and quota models.
- Current official Codex session/weekly quota, reset timing and reset-credit support through OAuth API or CLI RPC.
- Observed Codex token and hourly activity derived from local session telemetry with session, replay and duplicate filtering.
- Multiple DeepSeek credentials stored in Keychain, official balance checks and a loopback-only usage-capturing proxy.
- Multiple OpenRouter credentials with official spend, limits, credits, managed-key names and hash-scoped activity.
- Source diagnostics, provider-scoped timeout handling and strict fallback policies.
- Launch-at-login support, standard secure-field editing commands and light/dark appearance support.
- Verified local packaging and rollback-safe installation scripts.

### Security

- DeepSeek proxy origin validation, bounded request parsing, pinned HTTPS upstream, redirect refusal and loopback-only binding.
- Credential transaction rollback and defensive provider-error redaction.
- Bounded Codex RPC line parsing, cancellation and child-process termination.
- Dispatch-backed provider deadlines and cancellation-safe Codex RPC startup.

### Known Limitations

- Public binaries are not yet signed or notarized.
- Claude exact subscription quota remains unavailable.
- Codex local token activity is observed telemetry and may not equal an official account dashboard.
