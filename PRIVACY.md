# Privacy

Agent Usage Monitor is a local macOS application. It does not operate a hosted service and does not send analytics, crash reports, advertising identifiers or usage telemetry to the maintainer.

## Data Flow Summary

Provider requests go directly from the Mac to the provider named in the interface. Local usage history and credential metadata remain on the Mac unless the user deliberately shares them. Agent Usage Monitor data directories use owner-only `0700` permissions and local metadata, event and cache files use `0600` permissions.

| Data | Why it is used | Storage |
| --- | --- | --- |
| DeepSeek and OpenRouter API keys | Authenticate official provider requests | macOS Keychain, service `AgentUsageMonitor` |
| Provider key labels and local ids | Identify multiple configured accounts | `~/Library/Application Support/AgentUsageMonitor/` |
| DeepSeek response usage fields | Build observed token and activity views | `usage-events.jsonl` in Application Support |
| Codex access token | Request current official Codex quota | Read from the existing Codex auth file and held in memory; not copied into app state |
| Codex official quota samples | Support local quota projection and completed-cycle subscription review | Scalar samples in `quota-observations-v1.jsonl`; account identity is replaced with a keyed opaque scope before storage, and derived results are computed locally rather than persisted |
| Codex session usage fields | Build local observed token and activity views | Parsed local cache under `~/Library/Caches/AgentUsageMonitor/` |
| Launch-at-login choice | Register the packaged app with macOS | Managed by `SMAppService` and macOS |

## Codex Files

When Codex monitoring is active, the app may read:

- `$CODEX_HOME/auth.json` or `~/.codex/auth.json`
- `$CODEX_HOME/sessions/` and `$CODEX_HOME/archived_sessions/`
- the equivalent directories under `~/.codex/` when `CODEX_HOME` is not set

The session-log reader extracts timestamps, session identifiers, model names, reasoning-effort metadata and explicit token counters. It does not display prompt or response text.

To avoid reparsing large histories on every refresh, the app stores a rebuildable cache at:

```text
~/Library/Caches/AgentUsageMonitor/codex-observed-usage-v1.json
```

That cache can contain local file paths, session identifiers and derived token events. It never supplies official Codex quota bars and can be deleted at any time; the app will rebuild it from the source logs.

## DeepSeek Proxy

The optional proxy listens only on IPv4 loopback:

```text
http://127.0.0.1:18491
```

Requests are forwarded only to `https://api.deepseek.com`. Redirects are disabled, authority-changing targets are rejected, and explicit response usage fields are stored locally. The app does not infer token counts from response text.

Processes running under the same local user can reach loopback services. Do not treat the proxy as an authorization boundary between applications on the same Mac.

## Network Destinations

Depending on configured providers and user actions, the app communicates with:

- `https://chatgpt.com` for current Codex usage and reset-credit data
- `https://api.deepseek.com` for DeepSeek balance and proxied API requests
- `https://openrouter.ai` for OpenRouter key, credit and activity data
- provider documentation or account websites opened explicitly by the user

The optional Codex Web Debug window loads the official ChatGPT site only when the user opens it. Local Codex CLI RPC is a child process, not a maintainer-operated network service.

## Retention And Removal

Official quota observations are sampled no more than once every five minutes per quota window and retained for approximately 90 days. The history contains provider, anonymous account scope, quota-window id, remaining fraction, capture time and official reset time only. It does not contain email addresses, account ids, access tokens, response payloads or complete provider snapshots. A random local key used to create the anonymous account scope is stored in Keychain under service `AgentUsageMonitor`.

Quota projections and weekly recap results are computed on the Mac from those scalar samples and the current Official quota scope. Derived outputs are held in memory, are not sent to the maintainer or a third party, and are never used as a fallback when current Official quota is unavailable.

Deleting a DeepSeek or OpenRouter credential in Settings removes its Keychain secret and local metadata entry. To remove all remaining local application data after quitting the app, delete:

```text
~/Library/Application Support/AgentUsageMonitor/
~/Library/Caches/AgentUsageMonitor/
```

Use Keychain Access to remove any remaining items whose service is `AgentUsageMonitor`. Removing the application does not delete Codex's own auth or session files because those files belong to Codex, not this project.

## Sharing Diagnostics

Before attaching logs, screenshots or configuration to a GitHub issue:

- remove API keys, bearer tokens, cookies and authorization headers;
- remove personal email addresses, account ids and local usernames;
- do not upload `auth.json`, Codex session logs, Keychain exports, `usage-events.jsonl` or `quota-observations-v1.jsonl`;
- prefer the app's source diagnostics, which are designed to omit credential values.

## Changes

Privacy-impacting changes should update this document in the same pull request. Material changes will be called out in release notes.
