# AGENTS.md

## Project

Agent Usage Monitor is a native macOS menu bar app for monitoring AI subscription limits, API spend and explicitly observed token activity.

## Engineering Rules

- Keep provider accounting models separate. Subscription quota, API spend and local token activity are not interchangeable.
- Preserve confidence semantics: `Official`, `Observed`, `Estimated` and `Unavailable` must remain explicit.
- Fail closed when required official fields are missing or malformed; do not invent zeroes, dates, history or fallback quota.
- Never store API keys in source files, docs, logs, fixtures or JSON metadata.
- Keep provider errors free of credential values and personal account data.
- Keep changes focused, readable and consistent with the existing package boundaries.

## Architecture

- `AgentUsageCore` owns provider-neutral models, pure parsing, confidence semantics and aggregation.
- `AgentUsageMonitor` owns macOS UI, Keychain, networking, process execution, persistence and provider adapters.
- New providers enter through `ProviderRegistry` and return the shared `ProviderSnapshot` model.
- Documentation under `docs/` must change with user-visible source, privacy or fallback behavior.

## Verification

- Focused tests: `swift test --filter <suite-or-test>`
- Full tests: `swift test`
- Repository security check: `./scripts/security-check.sh`
- Release gate: `./scripts/release-check.sh`
- Installation verification: `./scripts/install-app.sh && ./scripts/verify-installation.sh`

Do not commit `.vscode/`, local auth/session data, `.build/`, `releases/`, generated signing material or unrelated user changes.
