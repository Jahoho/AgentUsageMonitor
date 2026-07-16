## Summary

Describe the user-visible problem and the smallest behavior changed to solve it.

## Source And Trust Boundary

State whether this change affects official, observed, estimated, or unavailable data. List new network destinations, credentials, local files, listeners, persistence, or command execution.

## Verification

- [ ] Focused tests pass.
- [ ] `./scripts/release-check.sh` passes.
- [ ] UI behavior was checked manually when applicable.
- [ ] Error, unavailable, malformed, and timeout cases were considered.

## Safety Checklist

- [ ] No credentials, auth files, provider payloads, local logs, personal paths, or account data are included.
- [ ] Provider errors and diagnostics redact secrets.
- [ ] Missing official fields do not become zero, synthetic history, or stale current data.
- [ ] Privacy, data-source, architecture, and user documentation are updated when behavior changes.
- [ ] The change is focused and does not include unrelated refactoring.
