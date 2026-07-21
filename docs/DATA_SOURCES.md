# Data Sources

Agent Usage Monitor uses one shared confidence vocabulary while preserving each provider's accounting model.

## Confidence Levels

| Label | Meaning |
| --- | --- |
| `Official` | A current value returned by an official provider API, dashboard or CLI surface. |
| `Observed` | Explicit usage telemetry captured locally by this app or read from a local provider log. |
| `Estimated` | A derived value calculated from documented inputs; never a substitute for official quota. |
| `Unavailable` | The provider does not currently expose a reliable value, or the current request failed validation. |

An `Official` label describes the source of a value. It does not imply that the provider endorses this project.

## Provider Matrix

| Provider surface | Source | Confidence | History and fallback behavior |
| --- | --- | --- | --- |
| Codex quota windows | ChatGPT Codex usage API or `account/rateLimits/read` CLI RPC | Official | Requires a usable current response. Eligible scalar samples may be retained locally for analysis, but previous official quota is never used as fallback. |
| Codex quota projection | Recent same-account, same-window and same-reset-cycle Official quota samples | Estimated when reliable; otherwise Unavailable | Requires at least five continuous samples plus 30 minutes of coverage for short windows or 6 hours for long windows. Sparse, unstable or overly wide results are suppressed. Never supplies current quota. |
| Codex reset credits | Official reset-credit API or CLI RPC fields | Official | Expiry appears only when the source exposes an explicit date. No 30-day rule is inferred. |
| Codex token activity | Explicit token counters in local live and archived session logs | Observed | Rolling 30x24-hour history after duplicate, replay and future-event filtering. Never populates quota bars. |
| Claude subscription | Local Claude Code availability and user-opened official usage surface | Unavailable for exact quota | No scraping, local estimate or stale quota fallback. |
| DeepSeek balance | `GET https://api.deepseek.com/user/balance` | Official | Each saved key refreshes independently; a failed key does not invalidate another current key. |
| DeepSeek token activity | Explicit JSON or completed SSE usage fields seen by the local proxy | Observed | Covers only requests routed through `127.0.0.1:18491`; no website-history backfill. |
| DeepSeek cost | Supported model price table plus complete observed token splits | Estimated | The entire affected window becomes unavailable when any event cannot be priced exactly. |
| OpenRouter current-key spend and limits | `GET https://openrouter.ai/api/v1/key` | Official | Missing required fields fail closed. Previous official data is not shown as current. |
| OpenRouter credits | `GET https://openrouter.ai/api/v1/credits` for confirmed management keys | Official | An optional credit failure does not discard a valid current-key response. |
| OpenRouter managed activity | Official `/keys` catalog and hash-filtered `/activity` data | Official | Only returned keys, models and completed UTC dates are shown; dates are not synthesized. |

## Failure Semantics

- Codex and OpenRouter require current official values for their official surfaces. A failed refresh remains visible as an error.
- Local Codex activity may remain visible as `Observed` while official quota is in error, but it cannot make the provider appear healthy or create quota bars.
- DeepSeek can preserve explicitly observed local activity or successful per-key values when another independent source fails. Diagnostics identify fallback provenance.
- Missing numeric fields are not silently converted to zero unless zero is explicitly returned by the source.
- Reset countdowns are calculated from absolute official timestamps when available.

## Refresh And Time Windows

The menu bar performs a background provider refresh approximately every 60 seconds. Network timeouts and provider retries are bounded so one source cannot indefinitely block the dashboard.

Observed `30d` summaries use a rolling 30x24-hour interval. OpenRouter official activity follows the completed dates returned by its API. Different time zones, provider-side refresh delays and account scope can make local observed totals differ from provider dashboards.

## Local Official Quota History

The app records a Codex quota observation only when the current raw provider refresh is Ready, an official source reports success without fallback, the account can be reduced to a local opaque scope, and the bar includes both a finite remaining fraction and an explicit future reset timestamp. The sample timestamp comes from the current provider snapshot, not from a previous dashboard state.

Samples are rate-limited to one per provider, anonymous account scope and quota window every five minutes, with a new official reset cycle captured immediately. They are retained locally for approximately 90 days.

Quota projection compares only samples from the same provider, anonymous account scope, quota-window id and Official reset cycle. It removes isolated one-sample source spikes, starts a new trend after a capacity increase above two percentage points, and treats smaller upward movement as source noise. Every estimate requires at least five samples and at least 15% of the expected five-minute sample density. Short windows use up to three hours of recent history, need 30 minutes of coverage and allow no gap above 45 minutes. Long windows use up to 36 hours, need 6 hours of coverage and allow no gap above 4 hours.

The point estimate combines a robust recency-weighted trend with recent pace. Recent pace receives less weight as the reset gets farther away, so a short burst is not extended unchanged across a long forecast. The displayed range includes fit and holdout error plus uncertainty from discrete quota changes and variation between activity periods. If modeled error exceeds 20 percentage points, the projection remains `Unavailable` instead of showing an unhelpfully wide estimate.

When the entire range stays above zero, the card shows the percentage expected to remain at reset. If the range crosses zero, it says the quota may run out; if the entire range is at or below zero, it shows the approximate exhaustion time. Every displayed projection is `Estimated`. With multiple windows, the valid projection with the lowest lower bound is shown.

History cannot populate current Official bars, change provider health or hide a failed Official refresh. In particular, a current Official failure becomes `Unavailable` before history is loaded; no stale sample is treated as present capacity. The same history may later support the separately documented weekly subscription review.

## Adding A Provider

A provider is accepted only when its data source can be classified honestly:

1. Prefer stable documented official APIs or CLI output.
2. Use observed local activity only when the app captures explicit usage fields.
3. Do not scrape private dashboards as an invisible fallback.
4. Fail closed when required fields disappear or change type.
5. Add parser fixtures, transport tests, timeout behavior and user-facing source documentation in the same change.
