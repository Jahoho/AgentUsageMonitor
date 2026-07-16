# Security Policy

Agent Usage Monitor handles local authentication material and forwards optional DeepSeek requests, so security reports are treated as high priority.

## Supported Versions

Only the latest tagged release and the current `main` branch receive security fixes. Pre-release builds and older `0.x` versions may be asked to upgrade before a report is investigated.

## Reporting A Vulnerability

Do not open a public issue for a suspected vulnerability.

Use GitHub's private vulnerability reporting flow:

```text
https://github.com/Jahoho/AgentUsageMonitor/security/advisories/new
```

Include:

- the affected version or commit;
- macOS version and hardware architecture;
- a concise impact assessment;
- minimal reproduction steps or a proof of concept;
- whether credentials, local files or network requests are exposed.

Never include live API keys, access tokens, cookies, private session logs or personal account data. Use synthetic values and redact paths where possible.

## Response Targets

This is an independently maintained project. The following are best-effort targets rather than a service-level agreement:

- acknowledge a complete report within 3 business days;
- provide an initial severity assessment within 7 days;
- coordinate a fix and disclosure date based on impact and exploitability.

Please allow a reasonable remediation window before public disclosure.

## High-Priority Security Boundaries

Reports are especially useful when they involve:

- API keys or Codex tokens leaving their intended process or provider boundary;
- secrets written to logs, JSON metadata, diagnostics or UI text;
- the DeepSeek proxy accepting non-loopback traffic or forwarding credentials away from the pinned official host;
- request smuggling, unbounded memory use or timeout bypass in the local proxy;
- arbitrary command execution through provider-controlled data;
- unsafe package, installer or update behavior.

## Security Design Notes

- API keys are stored as generic-password items in macOS Keychain.
- Credential values are redacted from provider errors.
- The DeepSeek proxy binds to `127.0.0.1`, validates request framing, rejects authority-changing targets and does not follow redirects.
- Provider operations have bounded timeouts and failures remain provider-scoped.
- The project has no maintainer-operated backend, analytics SDK or automatic updater.

These controls reduce risk but do not constitute a formal third-party security audit.

For ordinary defects and feature requests, use the public issue templates.
