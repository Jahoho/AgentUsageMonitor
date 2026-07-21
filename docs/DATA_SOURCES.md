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
| Codex quota projection | Recent same-account, same-window and same-reset-cycle Official quota samples | Estimated when reliable; otherwise Unavailable | Requires at least five samples plus 30 continuous minutes for short windows or 6 hours of sufficiently dense coverage for long windows. Normal long-window sampling gaps widen uncertainty instead of invalidating all history. Never supplies current quota. |
| Codex weekly review | Same-account Official weekly quota samples retained locally | Observed when the current cycle has enough history; otherwise Unavailable | Reports only captured change and coverage. Previous-cycle comparison requires comparable start coverage and a same-progress sample; it never extrapolates a full week or supplies current quota. |
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

Quota projection compares only samples from the same provider, anonymous account scope, quota-window id and Official reset cycle. It removes isolated one-sample source spikes, starts a new trend after a capacity increase above two percentage points, and treats smaller upward movement as source noise. Every estimate requires at least five samples and at least 15% of the expected five-minute sample density. Short windows use up to three hours of recent history, need 30 minutes of coverage and allow no gap above 45 minutes. Long windows use up to 36 hours and need 6 hours of coverage; a gap above 4 hours starts a new recent-pace segment but does not discard the broader elapsed-time trend.

Short-window point estimates combine a robust recency-weighted trend with recent pace. Long windows anchor the baseline to average consumption across elapsed calendar time, including idle periods, while recent pace receives less weight as the reset gets farther away. Quota movement between two samples is distributed across the time buckets it spans, so an overnight gap is not misread as one instantaneous burst. The displayed range includes fit and holdout error plus uncertainty from discrete quota changes and variation between activity periods.

Modeled error above 20 percentage points normally remains `Unavailable`. The strict exception is a long window whose entire range still reaches zero before reset: the card may show the qualitative expected-exhaustion result, but omits an approximate clock time when the range is that wide.

When the entire range stays above zero, the card shows the percentage expected to remain at reset. If the range crosses zero, it says the quota may run out; if the entire range is at or below zero, it shows expected exhaustion and includes an approximate time only when modeled error is at most 20 percentage points. Every displayed projection is `Estimated`. With multiple windows, the valid projection with the lowest lower bound is shown.

History cannot populate current Official bars, change provider health or hide a failed Official refresh. In particular, a current Official failure becomes `Unavailable` before history is loaded; no stale sample is treated as present capacity. The same history also supports the separately documented weekly subscription review.

## Weekly Subscription Review

The weekly review is derived from the same protected scalar history. Official window duration takes priority over primary/secondary source position when assigning the Session or Weekly id. Legacy long-primary observations are interpreted as weekly only in memory when their reset lead exceeds one day; the stored file remains unchanged.

A material capacity refill starts a new observed cycle. Reset-time movement on its own does not create a fake cycle. The current summary requires two samples spanning at least 30 minutes and reports observed quota decrease, observed duration and density against the five-minute capture schedule. It claims cycle-to-date coverage only when capture began near full capacity with at least six days of reset lead; otherwise the wording is limited to the observed span.

Comparison uses the previous observed cycle at the same elapsed progress point. Both cycles must begin near full capacity, and the previous sample must be within two hours of the target. When those conditions are not met, the Overview card says comparison is still being collected. No unobserved time is filled with zero usage or a predicted pace.

## Adding A Provider

A provider is accepted only when its data source can be classified honestly:

1. Prefer stable documented official APIs or CLI output.
2. Use observed local activity only when the app captures explicit usage fields.
3. Do not scrape private dashboards as an invisible fallback.
4. Fail closed when required fields disappear or change type.
5. Add parser fixtures, transport tests, timeout behavior and user-facing source documentation in the same change.
