# Product

## Product Thesis

AI coding users do not have one usage problem. They move between subscription quota, metered API spend, and local agent activity, while provider dashboards expose different units, time windows, and levels of reliability.

Agent Usage Monitor is a local decision tool for that fragmented workflow. It should answer a few practical questions quickly:

- Do I have enough reliable quota to start or continue this task?
- Which provider is driving activity right now?
- Is this number current and official, locally observed, estimated, or unavailable?
- Is my weekly pattern repeatedly creating pressure, or do I usually finish with comfortable headroom?
- For metered APIs, what did the provider report and what did this app merely observe?

The product is not trying to collapse those questions into one synthetic score. Its purpose is to make the differences legible enough that users can make better choices without opening several dashboards.

## Primary User

The primary user is a hands-on builder who regularly uses at least one subscription coding agent and may also use metered API providers. They value speed and privacy, understand that provider data is imperfect, and would rather see an honest unavailable state than a polished but misleading estimate.

This is not currently an enterprise FinOps product. It does not provide team budgets, administrative policy, cloud synchronization, invoice reconciliation, or organization-wide reporting.

## Real Usage Scenarios

### Before a long coding session

The user wants to know whether the current subscription window is likely to support another focused block of work. The app shows current Official headroom first and adds a projection only when the local same-cycle history is strong enough.

### While switching between agents

The user wants one glanceable place to see the active provider, current quota pressure, and recent observed activity. Overview prioritizes the live work context; provider pages retain source-specific detail.

### After a weekly reset

The user does not need another copy of “87% used.” They need a recap of the completed cycle: how much headroom remained, whether use clustered on a few days, how this cycle compared with their own recent baseline, and whether pressure is becoming a repeated pattern.

### When an official source fails

The user needs to know that the answer is missing. The app must not replace a failed current quota read with an old snapshot, local token activity, or an estimate that looks official.

### When API spend and token activity differ

The user needs the official balance or spend for financial decisions and may also want locally observed token activity for workflow context. Those values stay separate because they answer different questions.

## Product Strategy

### Trust before breadth

The project does not try to win by supporting the largest provider list. A provider is useful only when its source, confidence, privacy behavior, and failure semantics can be explained and tested.

### Decision support before dashboard density

Overview answers the highest-frequency questions. Provider pages explain the constraining source-specific details. Settings holds setup, diagnostics, and low-frequency actions. The popover should not become a miniature analytics portal.

### Progressive intelligence

Derived features earn their place in stages:

1. capture a current trustworthy source;
2. retain the minimum privacy-scoped history;
3. expose an estimate only when quality gates pass;
4. turn completed history into reflection without prescribing a purchase decision.

This is why quota projection and weekly recap follow the official-history foundation, and why Capacity Portfolio remains deferred until multiple providers expose genuinely comparable quota windows.

### Local-first by default

Secrets stay in Keychain, derived history stays on the Mac, and the project has no maintainer-operated telemetry backend. New persistence or network access must create enough user value to justify its privacy and maintenance cost.

## Design Principles

- Trust labels are part of the product, not decoration. Every non-obvious number needs a confidence signal or clear source context.
- The menu bar is the first monitor surface. The popover should answer the next question without forcing a full dashboard workflow.
- Keep provider pages sparse: remaining quota, a few key metrics, real activity, and official actions only when useful.
- Never let observed activity, derived history, or stale snapshots silently become current Official quota.
- Prefer graceful incompleteness over false precision. Unavailable is a valid product state.
- Preserve native macOS feel: light mode stays soft and warm, dark mode should feel like a translucent gray frosted instrument over the desktop.

## Product Boundaries

The current product intentionally avoids:

- automatic scraping of private provider dashboards as a hidden fallback;
- upgrade or downgrade recommendations based on a small personal history;
- estimated current quota when the official source is unavailable;
- cloud sync or maintainer-operated analytics;
- automatic updates before trusted binary distribution exists;
- adding providers whose only available signal cannot be classified honestly.

## Success Signals

Without collecting product analytics, quality is evaluated through deterministic tests, manual release checks, real personal usage, and opt-in user feedback. A release is moving in the right direction when:

- the user can identify the constraining provider and its source in a few seconds;
- current Official failures remain visible and never look healthy because local history exists;
- projection withholds a forecast when its evidence is sparse or unstable;
- weekly recap adds a new observation about behavior rather than repeating current usage;
- users can explain why two numbers differ because their accounting models are visible;
- setup and diagnostics remain available without crowding the daily monitoring surface.

## Brand Personality

Quiet, precise, and technically calm. The app should feel like a compact instrument panel for serious agent work: restrained enough for repeated daily use, but polished enough that quota status, reset pressure, and cost signals are immediately legible.

## Anti-References

Avoid oversized hero sections, decorative card grids, fake analytics, synthetic activity, and any design that makes local estimates look official. Avoid crowded dashboards that turn the popover into a report; diagnostics and long setup text belong in Settings or documentation.

## Accessibility And Inclusion

Target readable contrast in both light and dark appearances, with body text at WCAG AA contrast or better. Avoid relying on color alone for confidence or status; pair color with labels, layout, or concise text. Respect reduced-motion settings and keep hover details usable without precise pointer movement.
