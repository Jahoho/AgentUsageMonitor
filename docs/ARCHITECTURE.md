# Architecture

## Overview

The app separates provider-neutral usage concepts from macOS-specific integration.

- `AgentUsageCore`: data models, confidence labels, provider snapshots, remaining-quota semantics, DeepSeek response/SSE parsing, aggregation helpers.
- `AgentUsageMonitor`: menu bar UI, provider adapters, provider orchestration, macOS Keychain, local command checks, official URL opening.
- `Packaging`: local `.app` bundle metadata for personal review builds. Release and installation scripts build into hidden staging bundles, validate identity/resources before replacement, and retain the previous bundle until the staged replacement passes content verification.

`MenuBarStatusSnapshot` is the canonical compact status model. It chooses the one provider the user most needs to know about using this priority:

1. provider with current-hour observed activity
2. low remaining quota
3. provider errors
4. providers with observed activity today
5. ready providers
6. setup/unavailable states

`AppDelegate` renders that snapshot into the menu bar status light and refreshes it in the background. The compact icon uses the quota ring color for state, avoids a separate status dot, and draws the provider mark in white for contrast across changing wallpapers. Future popover capsules or optional focus HUDs should reuse the same model.

Background menu bar refresh runs full provider refresh every 60 seconds. This preserves real-time quota and status updates for the menu bar. It can trigger macOS privacy prompts for local provider files or CLI probes; approving those prompts allows the app to keep syncing.

When Codex is the compact menu-bar provider, the ring uses the 5h/session quota bar (`codex-session`) rather than the weekly bar. This keeps the menu bar aligned with the currently running Codex work loop.

`ProviderRegistry` is the single live-provider registration list. Each entry pairs an adapter factory with immutable identity, kind, navigation icon metadata, and freshness policy. `ProviderMonitorService` consumes that ordered registry and remains intentionally thin: it owns concurrent loading and per-provider timeout protection, while each provider adapter owns source-specific IO and snapshot construction:

- `CodexProviderAdapter`: Codex OAuth API and Codex CLI RPC official quota reads.
- `ClaudeProviderAdapter`: Claude Code availability and subscription setup guidance.
- `DeepSeekProviderAdapter`: concurrent per-key official balance checks plus account-attributed observed proxy events and model activity.
- `OpenRouterProviderAdapter`: concurrent saved-key checks plus management-key discovery of official key names, spend, limits, and per-key model activity.

The menu UI follows the same split:

- `DashboardView`: fixed-width, content-measured popover shell, one bounded root scroll surface, and selected page routing.
- `HeaderView`, `BrandIconView`, and `BrandLogoStore`: top navigation and bundled logo rendering.
- `ApplicationMenu`: standard AppKit responder-chain commands for Undo, Cut, Copy, Paste, and Select All in the accessory-style menu bar app.
- `OverviewView`: active-agent summary, all-provider activity aggregation, and concise provider source health.
- `ProviderSnapshotView`, `UsageViews`, and `ActivityStrip`: provider pages, quota bars, metric tiles, account selection, model rows, and hourly/daily activity charts.
- `SettingsView`: credentials, login shortcuts, proxy endpoint, and app controls.
- `LaunchAtLoginController`: thin wrapper around `SMAppService.mainApp` that exposes readable state for SwiftUI and preserves macOS approval/error messages.
- `DeepSeekCredentialStore`: non-secret DeepSeek key metadata in Application Support plus per-key secrets in Keychain.
- `OpenRouterCredentialStore`: non-secret OpenRouter key metadata in Application Support plus per-key secrets in Keychain, including safe migration from the legacy single-key item.
- `HTTPRequestParser`: bounded local HTTP request parsing for the DeepSeek proxy, including strict origin-form targets and case-insensitive singleton-header validation.
- `JSONUsageEventStore`: append-only JSONL usage event storage with legacy JSON array migration.

## Data Confidence

Subscription usage is not treated like API billing. Every value carries a confidence level:

- `Official`: official API, official dashboard, or official CLI value.
- `Observed`: captured by this app through proxy or telemetry.
- `Estimated`: computed from local history or pricing assumptions.
- `Unavailable`: not accessible yet.

## Provider Model

Each provider returns a `ProviderSnapshot` containing:

- provider identity and kind
- update time
- health state
- usage metrics
- quota bars
- optional activity buckets
- optional per-account profiles with their own health, metrics, bars, activity, and model summaries
- optional per-source diagnostics with current status, recent success/failure times, and fallback provenance
- notes and actions

Provider adapters refresh concurrently and results are returned in the registered provider order. A slow DeepSeek balance request or Claude probe should not delay Codex quota rendering, and a hung provider is isolated to its own timeout snapshot.

Dashboard refreshes may merge transient provider errors with the previous in-memory snapshot when that provider registration explicitly permits last-known data. DeepSeek and other observed sources can preserve a previous usable snapshot with a failure note; their source diagnostic is marked as fallback and retains the latest in-memory success/failure history. Codex and OpenRouter registrations require current data because both pages expose current official usage: when the current official source does not return usable data, the UI reports an error instead of showing stale, cached, local, or estimated usage.

This keeps the UI generic. Header navigation, brand-logo preloading, refresh ordering, timeout identity, and fallback behavior all consume the same registration metadata. Adding a provider means adding an adapter that returns the shared snapshot shape and one `ProviderRegistry` entry.

Quota bars use `remainingFraction`. Legacy stored snapshots that contain the old `usedFraction` key are still decoded, but new snapshots encode only the remaining-quota field.

Quota reset timing stores both display text and an optional absolute `resetAt` date. Official API/RPC snapshots write `resetAt` directly. UI surfaces render the remaining reset time from `resetAt` so live official snapshots do not freeze stale countdown strings.

Codex official timestamp fields are normalized through a shared timestamp helper before they become `Date` values. This covers official responses that expose Unix seconds and responses that expose Unix milliseconds for rate-limit resets or reset-credit expiry dates. The helper is intentionally used only at external-data boundaries; persisted Swift `Date` values keep the platform encoder's existing representation.

Provider pages intentionally show only high-signal information: remaining quota bars, a small metric set, and real activity charts when data exists. Providers with multiple keys expose a compact account picker below the existing provider aggregate; Codex and Claude keep their previous page paths because they do not populate account profiles. `30d` observed summaries use a rolling 30x24-hour window, while OpenRouter's official activity uses only the completed UTC dates returned by its API.

Overview is the live work surface, not another detailed provider page or shortcut directory. It highlights the active provider, renders all-provider observed activity for today, and keeps provider health scannable. Low-frequency startup, website, and provider configuration actions live in Settings.

Brand marks are bundled as local resources under `Sources/AgentUsageMonitor/Resources/Logos` so the menu UI does not depend on runtime network requests.

## Codex Subscription Strategy

Codex subscription data is handled as a subscription provider, not an API cost provider.

The current reader uses the same provider-neutral `ProviderSnapshot` shape as every other source, with these official source tiers:

1. OAuth APIs: reads the local Codex auth file from `$CODEX_HOME/auth.json` or `~/.codex/auth.json`, requests `https://chatgpt.com/backend-api/wham/usage` with local HTTP cache bypassed for current quota windows, and concurrently requests `https://chatgpt.com/backend-api/wham/rate-limit-reset-credits` for reset-credit count and explicit expiry details.
2. Codex CLI RPC: starts `codex -s read-only -a untrusted app-server` and reads `account/rateLimits/read`.

OAuth and CLI RPC are attempted concurrently behind a 20-second adapter-level timeout. A source may make one bounded retry only for transient transport failures such as a network timeout, HTTP 429/5xx, RPC timeout, or a closed app-server pipe. The budget is long enough for two complete default eight-second source attempts plus retry delay. Default OAuth attempts use a fresh ephemeral `URLSession`, so a retry does not inherit a stalled shared-session connection. Authentication, schema, and other permanent failures are not retried. If both official sources remain slow or unavailable, Codex returns an error snapshot with source diagnostics. The app does not show cached snapshots or estimated values as official Codex quota.

The app never stores Codex tokens in app state. It only reads the existing local Codex auth file at refresh time.

Exact remaining quota is shown only when a reliable current official source can be read.

Successful official Codex quota snapshots are not used as future fallback data. If a later official refresh fails or the app restarts while official sources are temporarily unavailable, Codex reports the official sync error rather than showing last-known quota.

Codex account plan and Codex quota tier are kept separate. `account/read` may return the ChatGPT subscription label, while `account/rateLimits/read` can return an internal Codex quota tier.

Codex reset credits are official only when they come from official surfaces. The OAuth reset-credit endpoint exposes authoritative `available_count` plus per-credit ISO expiry details when available. Newer RPC schemas can expose the same information as `rateLimitResetCredits.availableCount` and `rateLimitResetCredits.credits`, using Unix-second timestamps; older CLI/backend combinations may expose only a count or omit the field. The reported count remains authoritative because official detail arrays may be capped, while entries with `expiresAt: null` remain count-only and never receive an inferred date. Web Debug can inspect explicit dates found in official page text or metadata for immediate troubleshooting, but it neither persists a quota snapshot nor feeds the provider path. The app never infers expiry from the general 30-day promotion rule.

Codex local token activity is attached as `Observed` telemetry when it can be read quickly. The log reader preserves reported input, cached input, output, and total token fields. User-visible `Today local tokens`, `30d local tokens`, `Latest local tokens`, `Top local model`, and hourly activity use the source-reported `total_tokens`, which includes cached input as a breakdown of input usage. Each token card shows one total plus the exact cached-input share instead of a second competing token count. Future-dated events are excluded. These values are never presented as official Codex quota or expected to equal an account dashboard that uses a different time zone, refresh delay, or server-side scope.

Codex token cards do not show an API-equivalent USD or credit estimate. Local session logs do not identify GPT-5.6 cache-write tokens, fast-mode multipliers, or every server-side billing adjustment, so presenting a price would create a known risk of under- or over-estimation. Official quota bars and reset data remain separate and current-source-only.

Local activity enrichment is time-bounded so slow or large Codex session logs cannot block current official quota/error reporting. The official OAuth/RPC race completes before a due local log scan starts, preventing a large changed log from competing with latency-sensitive official requests. The current snapshot waits at most one second for a first local result; the detached scan may finish later and warm both the parser cache and the in-memory Observed payload for the next refresh. A completed local enrichment is reused for five minutes, and a later timeout keeps the latest completed Observed token metrics plus 24 hourly buckets instead of removing the section. Before the first completed scan, unavailable metric slots remain visible. None of these local caches can populate official quota bars.

The generic provider timeout still wins over a non-cooperative Codex refresh. In that exceptional path the dashboard keeps the provider in error, keeps quota bars and reset credits empty, and may carry forward only the last completed metrics/activity whose labels and confidence are explicitly `Observed`. Source histories are retained with a timeout failure; no previous official quota is preserved.

The reader deduplicates session logs by `session_meta.payload.id` when the same session appears in both live and archived directories. Within each log, `info.total_token_usage.total_tokens` acts as a cumulative guard: rows whose cumulative total is unchanged are treated as duplicate telemetry, while cumulative decreases are treated as a new segment and kept.

Observed Codex log scans cover all discovered live and archived session logs by default. This avoids a moving byte budget dropping still-valid events and making a rolling 30-day total decrease when new logs push older files out of the scan. Explicit file/byte limits remain injectable for tests and constrained callers, but production does not truncate the history. Parsed files are cached by path, modification time, and byte count both in memory and in `~/Library/Caches/AgentUsageMonitor/codex-observed-usage-v1.json`; unchanged files are decoded from that cache and only new, changed, or removed files update it. Cache schema v2 migrates v1 entries in place and removes already-cached dense replay bursts without rereading every unchanged source log. Concurrent refreshes for the same Codex home/cache pair share one in-flight scan. A transient file-read or directory-enumeration failure preserves only cached entries under the failed path while known deletions elsewhere are still pruned, and the next refresh retries the failed path. This cache is only a rebuildable index for Observed local token/activity telemetry and never supplies official quota bars.

Forked Codex logs can replay parent `token_count` history at spawn or task restoration time. This affects both explicit subagents and ordinary VS Code sessions whose metadata has `forked_from_id` without a `parent_thread_id`. The reader excludes dense same-second replay bursts and sparse replay rows whose 5h rate-limit reset time is more than 10 minutes older than the event timestamp. This keeps copied historical context out of local activity while preserving normal post-fork token events.

The remaining Codex local-activity limitation is intentionally documented for the parser only: if a future Codex log format emits low-density replay rows without rate-limit metadata, the parser may still need a new rule. Those values stay `Observed` and are not shown as official Codex subscription quota.

Codex session metadata currently does not expose a stable account identifier. If the same `CODEX_HOME` has been used by multiple accounts, local Observed history cannot be reliably split by account; official OAuth/RPC quota remains scoped to the current authenticated account and is unaffected.

## Boundary Review

The current package boundary is sound: `AgentUsageCore` imports only Foundation and owns domain models plus pure parsers/aggregation, while the `AgentUsageMonitor` executable owns SwiftUI/AppKit, WebKit, Keychain, process execution, networking, and provider orchestration. The dependency remains one-way from Monitor to Core. Provider-neutral HTTP transport injection lives in `HTTPDataFetching`, while each provider client retains its own endpoint, response error, and authorization rules.

The current boundary improvements are deliberately incremental:

1. `CodexUsageAPIParser` now owns pure OAuth usage-window parsing in Core. Request construction, auth, timeouts, HTTP status handling, and the supplemental reset-credit request remain in Monitor.
2. Provider-neutral source diagnostic models live in Core, while each adapter owns the meaning and lifecycle of its actual sources. Codex source racing remains adapter-private until another provider demonstrates the same orchestration requirement; local Observed enrichment stays a separate post-processing step.
3. Web Debug no longer writes `CodexUsageSnapshotStore`; it is an immediate troubleshooting surface only and cannot become an implicit quota fallback.
4. Codex RPC stdout uses one reusable 4 KiB buffered line reader with a 1 MiB per-line limit. Request ordering and parsing remain unchanged; cancellation sends SIGTERM and escalates to SIGKILL after a short grace period so a process that ignores termination cannot keep a blocking stdout read alive.
5. Keep the single Monitor executable target for now. A separate platform/provider library is justified only when UI-free Monitor tests or compile-time isolation provide a measurable benefit.
6. Evolve the Observed Codex cache to store per-file byte offsets plus parser state if active session files grow large enough to exceed the enrichment budget. The current cache avoids whole-history rescans but still reparses an entire changed file and rewrites the compact cache artifact.

The popover follows the system appearance. Light mode keeps the existing warm restrained palette; dark mode uses a native `NSVisualEffectView` behind a translucent gray layer so the popover reads as brighter frosted glass over the desktop, with white/gray text and blue accents. Width stays fixed at 392 points for stable scanning. Height follows the measured header plus selected-page content between a 260-point comfort floor and a 720-point preferred ceiling, further capped to the active screen's visible height. A single root scroll view handles only genuine overflow, so sparse provider pages shrink while Settings and expanded diagnostics remain usable without nested scrolling. Header chrome and the root scroll view keep stable identities across tabs; selected content changes immediately without a crossfade, while native `NSPopover` content-size animation keeps the arrow and top edge anchored so only the lower viewport and bottom edge visibly expand or contract. Resize motion becomes immediate when macOS Reduce Motion is enabled. `NSPopover` transient behavior handles same-app dismissal, and a global mouse monitor is installed only while the popover is visible so clicks delivered to other apps or the desktop close it without intercepting clicks inside the popover.

## Claude Subscription Strategy

Claude subscription data is handled as a subscription provider.

The first version provides:

- Claude Code availability detection
- guidance to use official interactive usage commands where available
- future support for OpenTelemetry as observed activity data

Exact subscription quota is shown only when a reliable official source can be read.

## DeepSeek API Strategy

DeepSeek uses an API provider model:

- one or more API keys stored in macOS Keychain
- non-secret key labels/default state stored in Application Support
- balances queried from the official DeepSeek `/user/balance` API
- local proxy at `http://127.0.0.1:18491`
- non-streaming JSON responses parsed for `usage.prompt_tokens`, `usage.completion_tokens`, and `usage.total_tokens`
- streaming SSE responses parsed from the `data:` usage chunk when the request returns one
- observed usage events stored as JSONL in the user's Application Support directory

DeepSeek token counts are `Observed` because the app sees the request result through its local proxy. DeepSeek account balance is `Official` because it is read from the provider API. The public DeepSeek API docs expose balance and per-response token usage; the app does not claim to import website usage-history charts without a stable official history endpoint, and an API key alone does not backfill historical dashboard usage.

When a proxied request carries an `Authorization` bearer token that matches a saved credential, the recorded usage event stores the credential id as `accountID`. If the request has no authorization header, the proxy injects the current default DeepSeek key. Events without a current matching credential remain in an explicit `Unattributed requests` profile; they are never guessed into one of the saved keys.

The proxy binds specifically to IPv4 loopback (`127.0.0.1`), not a wildcard interface. Listener state is reported as starting, ready, failed, or stopped; the UI calls it running only after Network.framework reaches `ready`. Listener and upstream-session start/stop transitions share one lifecycle lock, and stopping the proxy invalidates its ephemeral URLSession so in-flight upstream work is cancelled.

Inbound request targets must use origin-form and the upstream URL builder independently verifies that the final scheme and host remain `https://api.deepseek.com`. The dedicated ephemeral URLSession never follows redirects, so a later 3xx response cannot move a credential-bearing request to another authority. Authorization, Content-Length, Host, and Transfer-Encoding are singleton headers and duplicate case variants are rejected. Request methods, HTTP versions, names, and values are validated before URLSession sees them. Request headers are capped at 64 KiB, Content-Length bodies at 32 MiB, incomplete headers receive a single 408 response after 10 seconds, and the full inbound request has a 60-second hard deadline. Transfer-Encoding requests fail clearly instead of hanging.

The proxy forwards the official response head and body incrementally instead of buffering the complete upstream response. It preserves end-to-end response headers, removes fixed hop-by-hop fields plus every field named by `Connection`, requests identity encoding so URLSession does not silently change the streamed bytes, and uses a close-delimited HTTP/1.1 body for the local client. A serialized downstream write path keeps chunks ordered and delays final close until the last accepted write completes.

Usage capture runs beside forwarding and never delays a chunk until the entire response completes. Non-streaming JSON is retained within a bounded capture budget; SSE capture drains complete event blocks as they arrive and keeps only the latest valid usage event. The final event is appended at most once, and streamed text is never converted into inferred token counts.

DeepSeek balance checks run concurrently and fail independently per key. DeepSeek activity is grouped into today's 24 hourly buckets per attributed key from recorded usage events, and 30-day model rows sum only the exact prompt, completion, and total token fields captured in actual responses. The app does not render synthetic activity bars when no event data exists, does not assign a model cost to these rows, and does not present this partial proxy coverage as website history.

DeepSeek cost cards are computed from observed proxy token events using an explicit model allowlist from the official DeepSeek API price table. A window is priced only when every event has a supported model plus a complete, internally consistent input/cache/output token split. Unknown models, malformed splits, and mixed windows remain Unavailable instead of receiving a guessed default price. Costs remain calculated values, while the underlying token counts are observed locally; the UI includes the bundled price verification date.

## OpenRouter API Strategy

OpenRouter uses a current official API provider model:

- one or more API keys stored as separate macOS Keychain entries, with labels/default state stored separately as non-secret metadata
- `GET https://openrouter.ai/api/v1/key` for official daily, weekly, monthly, and all-time key usage plus limit and remaining values
- `GET https://openrouter.ai/api/v1/credits` only when `/api/v1/key` explicitly marks the credential as a management key
- `GET https://openrouter.ai/api/v1/keys` only with a confirmed management key, using offset pagination for official hashes, names, state, spend, and limits
- `GET https://openrouter.ai/api/v1/activity?api_key_hash=...` only with that management key, for official per-key activity over the last 30 completed UTC days
- no webpage scraping, local proxy accounting, cached usage fallback, or inferred dollar/token values

The current-key, managed-key, and activity response usage fields are required during decoding. If OpenRouter omits or changes those fields, the affected source reports an error rather than converting missing data to zero. A standard key never calls management-only endpoints. Saved keys refresh concurrently, and one key, Keychain item, credit request, or activity request can fail without discarding valid official data for other keys.

OpenRouter key limits become quota bars only when the official response includes both a positive `limit` and `limit_remaining`. The reset period is displayed from the official daily/weekly/monthly enum; the app does not invent an absolute reset timestamp. Account credit balance is arithmetic over official `total_credits` and `total_usage`, and is labeled Official because both inputs come from the same official response.

OpenRouter model rows group only activity items returned for the exact official key hash. `totalTokens` is prompt plus completion tokens; reasoning tokens remain a separate official field and are not added a second time. Daily charts include only returned dates, with no synthetic zero days or extrapolated current-day usage. Standard keys therefore show official spend/limits but no token activity; their user-entered labels remain Observed local metadata, while names returned by `/keys` are Official. The current management catalog covers the default workspace because `/keys` defaults to that scope; individually saved keys remain visible even when they cannot be matched to a catalog hash. Management-key activity failures remain explicit. `ProviderSnapshotFreshnessPolicy` prevents a previous OpenRouter snapshot from hiding a current official API failure.

## Privacy

- API keys never enter docs, tests, logs, or local state files.
- DeepSeek local metadata contains labels and ids only, never raw API keys.
- OpenRouter local metadata contains labels and ids only; every secret stays in its own Keychain item and is defensively redacted from provider errors.
- AgentUsageMonitor-owned Application Support and cache directories are restricted to `0700`; metadata, observed-event and parsed-cache files are restricted to `0600`.
- Provider errors should not include credential values.
- Official account login remains in the user-controlled browser or CLI.
- The DeepSeek proxy is isolated from the LAN by its loopback-only listener. Processes running as the same local user remain inside this trust boundary; requests without Authorization intentionally use the saved default DeepSeek key.

## Background Work

The app starts a local DeepSeek proxy after a DeepSeek API key is saved. The proxy only listens on `127.0.0.1` and exists to forward user-directed DeepSeek API requests. A non-nil listener object is not considered proof of readiness; Network.framework state drives the Settings status.

The app also runs a background refresh loop for the menu bar status light. The loop uses the same provider loading path as manual refresh, so the menu bar reflects official quota and provider status as soon as the app can read them.

DeepSeek credential metadata and local proxy lifecycle are configured at launch and when settings change, not after every provider refresh. This keeps routine dashboard publication free of synchronous Keychain/proxy work on the main actor; provider adapters continue reading required secrets only from their background refresh tasks.

Each provider refresh has a 25-second hard timeout, leaving enough room for Codex's bounded 20-second official-source race and one-second local enrichment. The deadline uses a dispatch timer so non-cooperative synchronous work cannot occupy the same cooperative executor that must deliver the timeout. If one provider hangs, the app returns an error snapshot for that provider and continues refreshing the others instead of leaving the dashboard stuck in a refreshing state.

The packaged app can register itself as a macOS login item from Settings -> App. Source builds may report that login startup is available only after packaging because `SMAppService` expects a real `.app` bundle.

## Conditional Docs

No server-side permissions, scheduled jobs, email, SEO, or embedded autonomous agent flows exist in the MVP.

## Related Documents

- `README.md`: public product overview and source build entry point.
- `PRIVACY.md`: local data, credentials, network destinations and removal.
- `SECURITY.md`: private vulnerability reporting and security boundaries.
- `docs/DATA_SOURCES.md`: provider confidence and fallback contract.
- `docs/CONFIGURATION.md`: provider setup and expected behavior.
- `docs/TEST_PLAN.md`: automated and manual verification map.
- `docs/DISTRIBUTION.md`: local packaging and current release limits.
- `docs/RELEASE_CHECKLIST.md`: maintainer release gate.
