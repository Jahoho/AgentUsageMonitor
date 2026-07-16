# Release Checklist

This checklist defines the minimum gate for a public source release. Signed binary distribution has additional requirements at the end.

## 1. Prepare

- Confirm the intended release commit is on `main`.
- Confirm `CFBundleShortVersionString` and `CFBundleVersion` match the release plan.
- Update `CHANGELOG.md` and move completed items out of `Unreleased`.
- Confirm README provider claims still match `DATA_SOURCES.md` and current adapters.
- Confirm the working tree contains no unrelated or local-only files.

## 2. Security And Privacy

- Run `./scripts/security-check.sh`.
- Review every new network destination, local file read and persistence field.
- Confirm secrets remain in Keychain and provider errors redact credential values.
- Confirm no auth files, session logs, API responses, local databases, signing certificates or provisioning profiles are tracked.
- Update `PRIVACY.md` when data access, retention or transmission changes.

## 3. Automated Verification

Run:

```bash
./scripts/release-check.sh
```

This must pass repository checks, all Swift tests, a Release build and package verification. CI must also pass on both the Apple Silicon and Intel macOS runners configured in `.github/workflows/ci.yml`.

## 4. Manual Smoke Test

- Launch the packaged app from a fresh install and verify one running process.
- Open every tab, test adaptive sizing and confirm clicking outside closes the popover.
- Verify paste and text-editing commands in DeepSeek and OpenRouter secure fields.
- Leave the app running through multiple background refresh cycles and confirm it stays responsive.
- Verify current Codex quota and separate observed token/activity behavior.
- Verify a real DeepSeek proxy request and one standard OpenRouter key.
- Check light mode, dark mode and Reduce Motion.
- Verify launch-at-login status from the packaged app.

Never use production credentials in screenshots, issue attachments or release notes.

## 5. Publish Source Release

- Create an annotated `vX.Y.Z` tag from the verified `main` commit.
- Push only the intended public branch and tags.
- Create a GitHub Release from `CHANGELOG.md` with clear known limitations.
- Do not attach the current locally built `.app` as a trusted public binary.
- Verify the automatically generated GitHub source archive builds without a `.git` directory.

## 6. GitHub Repository Settings

After the repository is created:

- set `main` as the default branch;
- require the CI workflow before merging;
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
