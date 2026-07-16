# Roadmap

The roadmap is intentionally conservative. New surfaces are accepted only when their source, privacy behavior and failure semantics can be documented and tested.

## v0.1 - Public Source Release

- Publish the Swift package under the MIT License.
- Keep Codex official quota separate from observed local token activity.
- Support DeepSeek and OpenRouter multi-key workflows without storing secrets outside Keychain.
- Maintain provider-scoped diagnostics, bounded refreshes and verified local packaging.
- Establish CI, security reporting, privacy documentation and repeatable release checks.

## v0.2 - Trusted Binary Distribution

- Select the final bundle identifier.
- Add Developer ID signing, hardened runtime and notarization.
- Produce universal or architecture-specific verified artifacts.
- Test install, update, rollback and removal on a clean Mac.
- Publish checksums and concise release notes.

## v0.3 - Provider Reliability

- Add guarded live-contract tests that use opt-in test credentials outside normal CI.
- Improve source diagnostics without exposing provider payloads or account data.
- Add a stable Claude subscription reader only when an official machine-readable source is available.
- Evaluate Tavily and other providers against the source-integrity requirements in `DATA_SOURCES.md`.

## v0.4 - Product Quality

- Expand VoiceOver labels and keyboard-only verification.
- Add localized user-facing strings without changing source semantics.
- Add opt-in, local-only resource diagnostics for large history scans.
- Refine provider onboarding and first-run empty states.

## Deferred

- Cloud sync, remote dashboards and maintainer-operated telemetry.
- Scraping private account pages as an automatic fallback.
- Estimated subscription quota when an official source is unavailable.
- Automatic updating before signed binary distribution exists.
