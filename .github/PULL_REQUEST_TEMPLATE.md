## User Problem And Outcome

Describe the real usage scenario, the decision or workflow that was difficult, and the smallest useful outcome delivered.

## Scope And Tradeoffs

Explain what changed, what deliberately did not change, and why this is the smallest coherent solution.

## Source And Trust Boundary

State whether this change affects official, observed, estimated, or unavailable data. List new network destinations, credentials, local files, listeners, persistence, or command execution.

## Verification Evidence

List the focused checks, manual scenarios, and failure cases that support the result. Include remaining limitations rather than presenting partial validation as complete.

- [ ] Focused tests pass.
- [ ] `./scripts/release-check.sh` passes.
- [ ] UI behavior was checked manually when applicable.
- [ ] Error, unavailable, malformed, and timeout cases were considered.

## Documentation And Release Impact

List changed public behavior, documentation updates, migration concerns, and the changelog entry. Write `None` only after checking each category.

## Safety Checklist

- [ ] No credentials, auth files, provider payloads, local logs, personal paths, or account data are included.
- [ ] Provider errors and diagnostics redact secrets.
- [ ] Missing official fields do not become zero, synthetic history, or stale current data.
- [ ] Privacy, data-source, architecture, and user documentation are updated when behavior changes.
- [ ] The change is focused and does not include unrelated refactoring.
