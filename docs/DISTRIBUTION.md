# Distribution

## Current Release Model

The `0.1.x` line is source-first. Users build locally from a tagged GitHub source release or a Git clone. The project does not yet publish a signed and notarized `.app` as a trusted binary download.

Requirements:

- macOS 14 or later
- Xcode 16 or another Swift 6 toolchain

## Verify From Source

Run the complete release gate:

```bash
./scripts/release-check.sh
```

Inside a Git checkout this performs:

1. whitespace and conflict-marker validation;
2. tracked-file and credential-pattern security checks;
3. all Swift tests;
4. a clean staged Release build;
5. package identity, resources and local ad-hoc signature verification.

GitHub's automatically generated source archives do not include `.git`. In that environment, repository-only checks are skipped while tests, packaging and package verification still run.

## Local Package

Build and verify the `.app` separately when needed:

```bash
./scripts/package-app.sh
./scripts/verify-package.sh
```

The output is:

```text
releases/AgentUsageMonitor.app
```

The package script builds into a hidden staging bundle, seals the completed bundle with a local ad-hoc signature, and verifies both the staging bundle and final Release path without carrying stale resources forward. Because a Desktop/FileProvider checkout can attach Finder metadata after packaging, strict verification is repeated on a metadata-free temporary copy without mutating the Release bundle. The app icon is generated reproducibly by `scripts/generate-app-icon.swift`.

SwiftPM resources are copied to:

```text
releases/AgentUsageMonitor.app/Contents/Resources/AgentUsageMonitor_AgentUsageMonitor.bundle
```

The app loads this standard bundle location when packaged and falls back to SwiftPM's generated `Bundle.module` lookup during local development.

## Local Installation

Quit any running copy, then run:

```bash
./scripts/install-app.sh
./scripts/verify-installation.sh
```

Installation uses a verified staging copy without carrying workspace-only extended attributes, retains the previous app as a temporary rollback bundle, compares the installed app with the Release package, and requires the actual `/Applications` bundle to pass strict on-disk signature verification before removing the rollback copy.

After a successful install, only this bundle remains:

```text
/Applications/AgentUsageMonitor.app
```

The installer removes historical or temporary app paths but does not delete Keychain items, Application Support usage history or caches. See [Privacy](../PRIVACY.md) for data removal.

## Architecture And Trust Limits

The current local package is built for the host architecture. On Apple Silicon it is `arm64`; on Intel it is `x86_64`.

The current bundle receives a local ad-hoc signature so macOS can verify that its executable, plist and resources belong together. It has no Developer ID identity and is not notarized. It should not be attached to a GitHub Release as though it were a trusted production binary. Users who build locally control the resulting executable and macOS trust decision.

## Future Binary Distribution

A public binary release requires:

- a final reverse-DNS bundle identifier;
- Developer ID signing with hardened runtime;
- a universal binary or clearly separated architecture artifacts;
- Apple notarization and stapling;
- strict `codesign` and `spctl` verification;
- a clean-machine launch and upgrade test;
- published checksums and documented uninstall behavior.

The complete maintainer flow is in [Release Checklist](RELEASE_CHECKLIST.md).
