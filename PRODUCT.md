# Product

## Users

Builders who actively use AI coding agents across subscription products and API providers. They need quick, low-friction answers about remaining quota, recent activity, API balance, and whether a number is official, observed, estimated, or unavailable.

## Product Purpose

Agent Usage Monitor is an independent macOS menu bar monitor for Codex, Claude, DeepSeek, OpenRouter, and future providers. It keeps usage data visible while preserving each provider's accounting model: subscription quota stays separate from API spend, official values are clearly distinguished from local observations, and uncertain data is never presented as exact.

## Brand Personality

Quiet, precise, and technically calm. The app should feel like a compact instrument panel for serious agent work: restrained enough for repeated daily use, but polished enough that quota status, expiry risk, and cost signals are immediately legible.

## Anti-references

Avoid marketing-page composition, oversized hero sections, decorative card grids, fake analytics, synthetic activity, and any design that makes local estimates look official. Avoid crowded dashboards that turn the popover into a report; provider pages should stay compact and high-signal, with diagnostics and long setup text moved to Settings.

## Design Principles

- Trust labels are part of the product, not decoration: every non-obvious number needs a confidence signal or clear source context.
- The menu bar is the first monitor surface; the popover should answer the next question without forcing a full dashboard workflow.
- Keep provider pages sparse: remaining quota, a few key metrics, real activity, and official actions only when useful.
- Prefer official network or CLI values for quota and reset data; fall back to observed local activity only when the UI explicitly says it is observed or estimated.
- Preserve native macOS feel: light mode stays soft and warm, dark mode should feel like a translucent gray frosted instrument over the desktop.

## Accessibility & Inclusion

Target readable contrast in both light and dark appearances, with body text at WCAG AA contrast or better. Avoid relying on color alone for confidence or status; pair color with labels, layout, or concise text. Respect reduced-motion settings and keep hover details usable without precise pointer movement.
