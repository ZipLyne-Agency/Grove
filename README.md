# Grove

A native macOS workspace for GitHub repositories and the services they use. Keep each repository’s description, integrations and service links together in Library, and open recent work from the menu bar.

Built with SwiftUI and AppKit. Signed in-app updates use Sparkle. Grove is independent of GitHub, Apple, and the services listed in it.

## Features

- Search and filter accessible repositories by name, description, owner, language, and topics.
- Twelve remembered sort choices, including newest created and most recently pushed.
- One Library for all repositories, with local descriptions, integrations and pinned Quick Access entries.
- Simple service rows: a name, a link, and an Open button. Add any service manually.
- Generate repository profiles across the whole inventory, including hidden owners. Each completed profile is saved so a stopped run can resume.
- Scan nested manifests, deployment configuration and source files on the default branch. Overview highlights the repository and its integrations. Hide unused detections and restore them from Hidden Integrations.
- Generate descriptions with optional on-device Apple Intelligence, with a labeled README or metadata fallback. Edit them locally without changing GitHub.
- Automatic GitHub refresh after waking or reconnecting. Service providers are never polled.
- Reviewed GitHub edits, archive, transfer, and deletion. Transfer and deletion require the exact repository name.
- Optional on-device Apple Intelligence for repository questions and change proposals.

Service links are a reminder of what a repository uses. Grove does not track deployments, build completion, subscriptions, errors, or service health. No provider credentials or account setup are needed.

## Install

Download Grove from [Releases](https://github.com/ZipLyne-Agency/grove/releases), unzip, and move it to Applications. Choose **Grove > Check for Updates…** for later releases. Settings also offers automatic update checks. The first installation of version 0.3.0 is manual; older versions have no updater.

Grove requires macOS 15 or later and a GitHub CLI login:

```sh
brew install gh
gh auth login --hostname github.com
```

Grove reads accessible repositories automatically. Closing its window leaves Quick Access in the menu bar; Quit Grove exits completely. Command-Shift-P opens Quick Access, Command-F searches, and Command-R refreshes GitHub.

Grove supports github.com and finds `gh` at `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, or `/usr/bin/gh`. GitHub Enterprise and other CLI locations are currently unsupported.

## Service links and scanning

Open a repository’s Integrations tab to inspect detected services, and add service names with exact HTTPS dashboard links. One saved link can belong to multiple repositories. Editing a link or a generated description only changes Grove. GitHub metadata edits remain a separate reviewed action.

Use the Library toolbar’s profile menu to generate missing profiles, refresh all profiles, or refresh the selected repository. Every accessible repository is included, even when its owner is hidden from the visible list. Stopping retains completed profiles. Local description edits survive later integration scans.

The scan pins an immutable Git tree and reads eligible text in bounded batches, including nested apps and backend folders. Large files use the pinned Git blob API to avoid truncated bulk responses. It never executes repository configuration. Environment files, credentials, lockfiles, generated output and vendor dependencies are excluded. The limits are 5,000 files, 4 MB per file and 100 MB of text per repository. Each profile shows coverage and limitations, including unreadable files, truncated trees and linked submodules. A partial scan is labeled explicitly. Retry Incomplete Profiles reruns only missing or partial profiles.

A fixed service catalog detects SDK, dependency, configuration and source references. Explicit endpoints outside the catalog appear as hostnames without paths or query strings. References show what exists in the scanned code; they do not prove deployment or active usage. Runtime-only configuration and integrations without matching references may be missed. Documentation, content data and examples appear separately. Saved dashboard links preserve their exact URLs.

Description generation uses bounded, sanitized README prose, paths and integration names on device. When the model is unavailable or cannot finish, a labeled fallback uses the existing description or README. Source text is kept in memory while scanning; saved profiles contain descriptions, service names, file evidence and coverage.

Apple Intelligence requires macOS 26, supported hardware, and an available system model. Repository and service management work without it. No source or service information is sent to a cloud AI provider.

## Privacy and reviews

GitHub uses the existing `gh` login; Grove never stores its token or changes its scopes. Repository metadata is cached locally with owner-only permissions. Repository profiles, notes, pins and service links are encrypted with a Keychain-backed key. Existing project links, notes and pins migrate to their member repositories; legacy project data is retained. Existing provider accounts from earlier versions remain stored for compatibility and can be removed in Settings; their credentials and old snapshots are not used by the service list or assistant.

Developer ID builds use the Data Protection Keychain with device-only accessibility and synchronization disabled. Ad hoc development builds use the login Keychain and a separate `workspace-development.enc` archive.

GitHub mutation previews expire after five minutes and are consumed once. Grove rechecks the live account, repository identity, metadata, and permissions before a write. An uncertain write blocks further changes until refresh, including after reopening. No mutation is retried automatically. Organization SSO, scopes, and destination policies still apply.

Names, notes, repository files, and model output are untrusted data. AI suggestions never execute changes. Grove has no analytics, telemetry, or saved AI conversations. Automatic update checks are enabled on first launch and can be disabled in Settings. These checks contact GitHub to fetch the signed release feed and downloads, revealing the usual network address and app version; Sparkle system profiling is disabled. Do not attach credentials, caches, private source, or unsanitized screenshots to public issues.

## Development

Build with full Xcode 26 or later, the macOS 26 SDK, and Swift:

```sh
git clone https://github.com/ZipLyne-Agency/grove.git
cd grove
swift test
./scripts/build-app.sh
```

Generated artifacts go to `~/Assets/grove/files`; set `GROVE_OUTPUT` to change that location. The build defaults to an ad hoc signature. Set `GROVE_UNIVERSAL=1` for Intel and Apple Silicon. Developer ID builds also require `GROVE_SIGNING_IDENTITY`, `GROVE_TEAM_ID`, and `GROVE_PROVISIONING_PROFILE` for the matching profile. `scripts/notarize-app.sh` reads `NOTARY_API_KEY_FILE`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER` from the caller's secret broker.

With Grove quit, `Grove.app/Contents/MacOS/Grove --profile-summary` prints local profile counts and incomplete coverage without source text, descriptions, URLs or credentials.

Default tests use synthetic transports. Opt-in live reads and on-device model checks are disabled by default. Older macOS and Intel runtime behavior have not been directly verified. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Releasing

See [release/README.md](release/README.md) for signed, notarized releases and the in-app update feed.

## License

[MIT](LICENSE), copyright 2026 ZipLyne. Apple frameworks, GitHub CLI, and connected services have their own terms.
