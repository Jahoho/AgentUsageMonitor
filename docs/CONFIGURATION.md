# Configuration Guide

## Run The App

Build the packaged local review app:

```bash
./scripts/package-app.sh
open releases/AgentUsageMonitor.app
```

If an older copy is already running, quit it from the power button in the app header or from `Settings` -> `App` -> `Quit Agent Usage Monitor`.

Or run from source:

```bash
swift run AgentUsageMonitor
```

## DeepSeek API

1. Open the app from the menu bar.
2. Go to `Settings` -> `DeepSeek`.
3. Add a label, paste your DeepSeek API key, and click `Add API key`.
4. Go to `DeepSeek` and refresh.

Expected result:

- Balance shows as `Official` from DeepSeek `/user/balance`.
- Proxy status shows `http://127.0.0.1:18491`.
- Provider pages show compact usage status. `Today tokens` stays `Unavailable` or `0` until a real request passes through the local proxy.
- Longer setup/source details are in Settings and these docs.

You can add multiple DeepSeek API keys. The app stores each secret in Keychain and keeps only the label/id in local app state. Use the checkmark button to choose the default key for proxy requests that do not include their own `Authorization` header. Use the trash button to delete a key from both Settings and Keychain.

## OpenRouter API

1. Open the app from the menu bar.
2. Go to `Settings` -> `OpenRouter`.
3. Add a label, paste an OpenRouter API key, and click `Add API key`.
4. Go to `OpenRouter` and refresh.

Expected result:

- Daily, weekly, monthly, and all-time spend come from the official `/api/v1/key` response.
- A configured key limit and remaining amount appear as an official quota bar.
- Management keys also show official account credit totals from `/api/v1/credits`.
- Token totals and activity are not shown because OpenRouter does not expose an enumerable account-wide token history API.

Each key stays in macOS Keychain while its label and local id are stored separately in Application Support. If the current official response is missing, invalid, or incomplete, OpenRouter reports an error and does not substitute cached, local, or estimated usage.

## Overview

Use `Overview` as the live work panel:

- `Active agent` highlights the provider with current-hour activity, then the provider with the most observed activity today.
- `Today activity` aggregates observed hourly token usage across connected providers, not one provider at a time.
- `Sources` keeps provider health visible without showing provider setup details.

Use `Settings` for lower-frequency actions:

- `Settings` -> `App` -> `Start at login` controls the packaged app's macOS login item.
- `Settings` -> `Codex`, `Claude`, `DeepSeek`, and `OpenRouter` contain provider websites, web sync, docs, and API configuration.

If `Start at login` says approval is needed, open macOS `System Settings` -> `General` -> `Login Items` and approve Agent Usage Monitor.

## DeepSeek Token Tracking

Set DeepSeek-compatible tools to this base URL:

```text
http://127.0.0.1:18491
```

Keep the model and request body the same as normal. The app forwards requests to:

```text
https://api.deepseek.com
```

After a non-streaming request completes, refresh the app. `Today tokens`, `30d tokens`, and activity should appear as `Observed`.

Streaming-format responses can also be tracked when the DeepSeek SSE stream includes a usage event, for example when the client enables usage reporting for streamed chat completions. The proxy forwards response chunks incrementally and records the final explicit usage event at most once.

If the proxied request includes a configured `Authorization: Bearer ...` key, usage is associated with that saved key. If it does not include authorization, the proxy uses the current default DeepSeek key.

The DeepSeek activity chart groups today's observed token usage into hourly buckets. It stays hidden until the proxy has recorded real token events.

The DeepSeek page shows `Balance`, `Today tokens`, `Today cost`, and `30d tokens`. Cost values are calculated from observed proxy token events and the current official DeepSeek API price table.

Current limit:

- DeepSeek website usage-history charts are not imported because the public docs expose balance and per-response usage, not a stable usage-history API. Saving an API key does not backfill website history.
- Inbound chunked HTTP requests to the local proxy are rejected clearly instead of being parsed manually. Normal Content-Length requests are supported.
- The proxy listens only on `127.0.0.1`, rejects redirects away from the pinned official upstream, and applies bounded header/body sizes plus request deadlines.

## Codex Subscription

Codex uses subscription quota, not this app's API accounting.

Preferred setup:

1. Sign in to Codex normally with the Codex CLI or Codex desktop app.
2. Confirm this file exists:

```text
~/.codex/auth.json
```

3. Open Agent Usage Monitor and refresh the `Codex` tab.

The app tries these sources in order:

1. `~/.codex/auth.json` or `$CODEX_HOME/auth.json` -> ChatGPT Codex usage endpoint.
2. `codex -s read-only -a untrusted app-server` -> `account/rateLimits/read`.

You can also use the `Codex` tab actions:

- Open Codex Web Debug to inspect the official page when troubleshooting.
- Open Codex pricing docs.

The app only shows Codex quota when a current reliable official OAuth/API or CLI/RPC value is readable. Otherwise Codex reports an error with source diagnostics instead of showing cached, local, or estimated usage.

Quota bars show remaining percentage, not used percentage.

Codex token activity is read from local Codex session logs. The app extracts timestamp and token usage fields only; prompt text is not displayed by the monitor. Token cards show the reported total, including cached input, plus one cached-input percentage. They do not show a local USD or credit estimate.

Important:

- CLI login is preferred because it gives the app a local official auth source without asking you to paste credentials.
- The UI separates ChatGPT account plan from Codex quota tier because Codex can expose these as different fields.
- Codex OAuth and RPC values are marked `Official`.

## Claude Subscription

Claude uses subscription quota, not this app's API accounting.

Use `Settings` -> `Claude`:

- Click `Open Claude account`.
- Sign in with the Claude account that owns your subscription.

You can also use the `Claude` tab actions:

- Open Claude Code usage documentation.
- Check local Claude Code CLI availability.
- Use Claude Code's official interactive usage command when available. The monitor does not script or scrape private Claude subscription output yet.

The app only shows exact quota when a reliable official value is readable. Otherwise the quota area remains `Unavailable`.

## Verify Setup

Run:

```bash
swift test
./scripts/package-app.sh
./scripts/verify-package.sh
```

Then open:

```text
releases/AgentUsageMonitor.app
```

See [Privacy](../PRIVACY.md) before sharing diagnostics or removing local application data.
