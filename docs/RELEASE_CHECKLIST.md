# Release Checklist

This checklist defines the minimum gate for a public source release. It separates product acceptance, source integrity, GitHub integration, and publishing so a passing build is not mistaken for a finished release.

## 1. Prepare The Release Candidate

- Confirm the release branch is based on the current protected GitHub `main`, not a stale local branch.
- Confirm `CFBundleShortVersionString`, `CFBundleVersion`, and user-visible client version fields match the release plan.
- Update `CHANGELOG.md` and move completed items out of `Unreleased`.
- Write release notes around the user problem, resulting behavior, trust boundary, and known limitation rather than copying commit subjects.
- Confirm README and Configuration claims match `DATA_SOURCES.md`, Privacy, current adapters, and the final UI.
- Confirm Roadmap marks delivered and deferred work honestly.
- Check every relative Markdown link.
- Confirm the working tree contains no unrelated or local-only files.

## 2. Security And Privacy

- Run `./scripts/security-check.sh`.
- Review every new network destination, local file read and persistence field.
- Confirm secrets remain in Keychain and provider errors redact credential values.
- Confirm no auth files, session logs, API responses, local databases, signing certificates or provisioning profiles are tracked.
- Update `PRIVACY.md` when data access, retention or transmission changes.

## 3. Automated Verification

Run the local gate:

```bash
./scripts/release-check.sh
```

This must pass repository checks, all Swift tests, a Release build, and package verification.

Before merge:

- open a focused pull request against `main`;
- confirm both required GitHub checks pass: `Release check (macos-15)` and `Release check (macos-15-intel)`;
- resolve every review conversation;
- verify a GitHub-style source archive without `.git` still passes the release gate.

## 4. Manual Smoke Test

- Launch the packaged app from a fresh install and verify one running process.
- Open every tab, test adaptive sizing and confirm clicking outside closes the popover.
- Confirm the full visible area of each navigation tab is clickable.
- Verify paste and text-editing commands in DeepSeek and OpenRouter secure fields.
- Leave the app running through multiple background refresh cycles and confirm it stays responsive.
- Verify current Codex quota and separate observed token/activity behavior.
- Confirm Quota projection appears only on an eligible subscription provider page, remains Estimated, and becomes Unavailable when current Official quota fails.
- Confirm Weekly recap waits for a completed trustworthy reset, expands in Overview, and does not repeat current used percentage.
- For a release that changes recap logic, validate at least one real completed cycle in addition to synthetic tests.
- Verify a real DeepSeek proxy request and one standard OpenRouter key.
- Check light mode, dark mode and Reduce Motion.
- Verify launch-at-login status from the packaged app.

Never use production credentials in screenshots, issue attachments or release notes.

## 5. Merge And Tag

- Merge only after the protected pull-request checks pass.
- Confirm the merged `main` commit has a successful CI run.
- Create an annotated `vX.Y.Z` tag from that exact verified `main` commit.
- Push only the intended tag.

## 6. Publish And Verify

- Create a GitHub Release from the curated changelog with clear source, privacy, and known-limitations notes.
- Do not attach the current locally built `.app` as a trusted public binary.
- Download the automatically generated GitHub source archive and repeat its build verification.
- Confirm the release is marked latest, its tag resolves to the intended commit, and README links render correctly.
- Leave unfinished follow-up work in Roadmap or Issues rather than hiding it in the release notes.

## 7. GitHub Repository Controls

Verify these controls periodically:

- set `main` as the default branch;
- require both architecture CI checks before merging;
- require linear history and resolved review conversations;
- prevent force pushes and branch deletion;
- keep workflow token permissions read-only by default;
- enable Dependabot alerts, secret scanning and push protection;
- enable private vulnerability reporting;
- protect tags matching `v*` when release automation is introduced.

## Signed Binary Release Requirements

Before publishing a downloadable `.app`, DMG or ZIP:

- choose the final reverse-DNS bundle identifier;
- build the intended architecture set or a universal binary;
- sign the complete bundle with Developer ID and hardened runtime;
- notarize and staple the distributed artifact;
- verify with `codesign`, `spctl` and a clean-machine launch test;
- publish checksums and document the upgrade and uninstall paths.
