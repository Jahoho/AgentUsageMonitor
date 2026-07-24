# Roadmap

The roadmap is intentionally evidence-led. A feature moves forward when it answers a recurring user decision, has an honest data source, preserves local privacy, and can fail without misleading the rest of the product.

Priorities follow four questions:

1. Does this solve a real monitoring or planning problem?
2. Can the result be labeled Official, Observed, Estimated, or Unavailable without ambiguity?
3. Is the privacy and operational cost proportionate to the value?
4. Is there enough evidence to expand the surface rather than improve the current one?

## Released — v0.1.0 Public Source Foundation

The first public release established the trust and engineering boundaries:

- a native source-first macOS menu bar app under the MIT License;
- separate models for subscription quota, API spend, and local token activity;
- Codex Official quota kept separate from Observed local activity;
- DeepSeek and OpenRouter multi-key workflows with secrets in Keychain;
- provider-scoped diagnostics, bounded refreshes, local privacy documentation, CI, and repeatable release checks.

## Next Source Release — v0.2.0 Capacity Intelligence

**Status:** implemented on the feature branch; release validation is still pending.

**Product outcome:** move from “show me the current percentage” to “help me judge whether capacity is likely to last and what my completed weekly pattern means.”

Delivered behavior:

- Local, privacy-scoped history from current official quota samples without a fallback path.
- A compact provider-detail quota projection with a remaining range, explicit Estimated labeling, and suppression of sparse or unstable forecasts.
- An Overview-only expandable weekly subscription recap with completed-cycle outcome, attributable rhythm, personal baseline, descriptive plan fit, and explicit data quality.
- More reliable long-window handling, projection scoping to eligible subscription Coding Plans, and a larger navigation hit area.
- Locally ad-hoc-signed packages with verified resource integrity and rollback-safe installation.

Release exit criteria:

- Observe the first real completed weekly cycle and confirm the recap adds insight beyond current quota.
- Complete the product/documentation refresh and finalize the `0.2.0` changelog.
- Pass the full local release gate, clean-install smoke test, and both protected GitHub CI jobs.
- Verify the generated GitHub source archive builds without repository metadata.
- Publish source and release notes only; do not attach the current local app as a trusted binary.

Guardrails remain deliberate: no projection state in the menu-bar icon, no notifications, no upgrade/downgrade prescription, and no current quota synthesized from history.

## After v0.2 — Validate Before Expanding

The next product work should respond to real use rather than a fixed version number:

- Validate whether the weekly recap changes planning behavior after several real cycles.
- Decide whether a lightweight reflection note or next-cycle intention adds value without turning the popover into a journal.
- Improve first-run guidance and empty states using the questions users actually ask during setup.
- Expand VoiceOver, keyboard-only, and reduced-motion verification.
- Add opt-in local resource diagnostics only if large history scans become a recurring support problem.

## Conditional Track — Provider Reliability

Provider breadth is not a release goal on its own:

- Add guarded live-contract tests with opt-in test credentials outside normal CI when provider drift becomes costly.
- Improve source diagnostics without exposing payloads or account data.
- Add Claude subscription quota only when an official machine-readable source is stable enough to fail closed.
- Evaluate every provider candidate against the source-integrity requirements in `DATA_SOURCES.md`.

## Later Milestone — Trusted Binary Distribution

Developer ID distribution should begin when easier installation is more valuable than another product-learning cycle:

- select the final reverse-DNS bundle identifier;
- add hardened-runtime Developer ID signing, notarization, and stapling;
- produce universal or clearly separated architecture artifacts;
- test clean install, upgrade, rollback, and removal on another Mac;
- publish checksums and documented trust boundaries.

## Deferred

- Cloud sync, remote dashboards and maintainer-operated telemetry.
- Scraping private account pages as an automatic fallback.
- Estimated subscription quota when an official source is unavailable.
- Capacity Portfolio until enough providers expose comparable official quota windows.
- Automatic updating before signed binary distribution exists.
