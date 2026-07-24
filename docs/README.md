# Documentation

This directory separates daily setup and trust questions from implementation and release references.

## Start With Your Question

| Question | Start here |
| --- | --- |
| How do I connect a provider safely? | [Configuration](CONFIGURATION.md) |
| Is this value Official, Observed, Estimated, or Unavailable? | [Data Sources](DATA_SOURCES.md) |
| What stays on my Mac? | [Privacy](../PRIVACY.md) |
| Why does the product keep these numbers separate? | [Product Principles](../PRODUCT.md) |
| How is the app structured and tested? | [Architecture](ARCHITECTURE.md) and [Test Plan](TEST_PLAN.md) |
| What is implemented next, and what is deliberately deferred? | [Roadmap](ROADMAP.md) |
| How is a public version prepared? | [Release Checklist](RELEASE_CHECKLIST.md) |

## For Users

| Document | Purpose |
| --- | --- |
| [Configuration](CONFIGURATION.md) | Connect Codex, Claude, DeepSeek and OpenRouter safely. |
| [Data Sources](DATA_SOURCES.md) | Understand which values are official, observed, estimated or unavailable. |
| [Distribution](DISTRIBUTION.md) | Build, package and install the current source-first release. |
| [Privacy](../PRIVACY.md) | Review local files, credentials, network destinations and removal steps. |
| [Security](../SECURITY.md) | Report vulnerabilities privately. |
| [Changelog](../CHANGELOG.md) | Review user-visible changes in released and upcoming versions. |

## For Contributors

| Document | Purpose |
| --- | --- |
| [Architecture](ARCHITECTURE.md) | System boundaries, provider strategies and trust-sensitive behavior. |
| [Test Plan](TEST_PLAN.md) | Automated coverage, package checks and manual acceptance cases. |
| [Release Checklist](RELEASE_CHECKLIST.md) | Repeatable maintainer checklist for a public version. |
| [Roadmap](ROADMAP.md) | Small, source-integrity-first development phases. |
| [Product Principles](../PRODUCT.md) | Audience, product posture and design principles. |
| [Contributing](../CONTRIBUTING.md) | Development workflow and pull-request expectations. |

## Keeping Documentation Current

The source code and tests remain the final authority when documentation and implementation disagree. Documentation changes should ship with the behavior they describe:

- user-visible behavior updates belong in the README, Configuration and Changelog;
- new data sources, confidence rules or fallback behavior update Data Sources;
- new files, credentials, retention or network destinations update Privacy and Security;
- shared contracts or persistence changes update Architecture and Test Plan;
- product sequencing and explicit non-goals update Product Principles and Roadmap.
