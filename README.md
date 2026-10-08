# Grove

A native macOS workspace for GitHub repositories and the services they use. Group repositories into projects, remember service links, and open recent work from the menu bar.

Built with SwiftUI and AppKit. No third-party Swift packages are required. Grove is independent of GitHub, Apple, and the services listed in it.

## Features

- Search and filter accessible repositories by name, description, owner, language, and topics.
- Twelve remembered sort choices, including newest created and most recently pushed.
- Local projects with shared service links and pinned Quick Access entries.
- Simple service rows: a name, a link, and an Open button. Add any service manually.
- Find Services scans dependency manifests, configuration, and README excerpts from a repository's default branch. The optional on-device assistant suggests services beyond the built-in configuration detector. Review the suggestions before saving them.
- Automatic GitHub refresh after waking or reconnecting. Service providers are never polled.
- Reviewed GitHub edits, archive, transfer, and deletion. Transfer and deletion require the exact repository name.
- Optional on-device Apple Intelligence for repository questions and change proposals.

Service links are a reminder of what a project uses. Grove does not track deployments, build completion, subscriptions, errors, or service health. No provider credentials or account setup are needed.

## Install

Download Grove from [Releases](https://github.com/ZipLyne-Agency/grove/releases), unzip, and move it to Applications. Quit earlier instances before opening a newer build.

Grove requires macOS 15 or later and a GitHub CLI login:

```sh
brew install gh
gh auth login --hostname github.com
```

Grove reads accessible repositories automatically. Closing its window leaves Quick Access in the menu bar; Quit Grove exits completely. Command-Shift-P opens Quick Access, Command-F searches, and Command-R refreshes GitHub.

Grove supports github.com and finds `gh` at `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, or `/usr/bin/gh`. GitHub Enterprise and other CLI locations are currently unsupported.

## Service links and scanning

Open a repository or project's Services tab to add a service name and HTTPS link. One saved service can appear in multiple repositories or projects. Editing or removing a link only changes Grove.

Find Services reads a bounded set of known files, never executes configuration, and excludes environment and credential files. Its on-device model sees bounded excerpts; the configuration detector examines the full bounded files. Monorepo layouts, runtime configuration, and services without code references may be missed. When Apple Intelligence is unavailable or cannot finish, Grove shows the configuration detector's results and explains that fallback.

Scan links come from Grove's fixed service catalog; the model cannot generate URLs. Services outside that catalog can be added manually. Edit a suggested link to save your exact project page. A scan is a suggestion, not proof that a service is used or configured correctly.

Apple Intelligence requires macOS 26, supported hardware, and an available system model. Repository and service management work without it. No source or service information is sent to a cloud AI provider.

## Privacy and reviews

GitHub uses the existing `gh` login; Grove never stores its token or changes its scopes. Repository metadata is cached locally with owner-only permissions. Projects and service links are encrypted with a Keychain-backed key. Existing provider accounts from earlier versions remain stored for compatibility and can be removed in Settings; their credentials and old snapshots are not used by the service list or assistant.

Developer ID builds use the Data Protection Keychain with device-only accessibility and synchronization disabled. Ad hoc development builds use the login Keychain and a separate `workspace-development.enc` archive.

GitHub mutation previews expire after five minutes and are consumed once. Grove rechecks the live account, repository identity, metadata, and permissions before a write. An uncertain write blocks further changes until refresh, including after reopening. No mutation is retried automatically. Organization SSO, scopes, and destination policies still apply.

Names, notes, repository files, and model output are untrusted data. AI suggestions never execute changes. Grove has no analytics, telemetry, or saved AI conversations. Do not attach credentials, caches, private source, or unsanitized screenshots to public issues.

## Development

Build with full Xcode 26 or later, the macOS 26 SDK, and Swift:

```sh
git clone https://github.com/ZipLyne-Agency/grove.git
cd grove
swift test
./scripts/build-app.sh
```

Generated artifacts go to `~/Assets/grove/files`; set `GROVE_OUTPUT` to change that location. The build defaults to an ad hoc signature. Set `GROVE_UNIVERSAL=1` for Intel and Apple Silicon. Developer ID builds also require `GROVE_SIGNING_IDENTITY`, `GROVE_TEAM_ID`, and `GROVE_PROVISIONING_PROFILE` for the matching profile. `scripts/notarize-app.sh` reads `NOTARY_API_KEY_FILE`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER` from the caller's secret broker.

Default tests use synthetic transports. Opt-in live reads and on-device model checks are disabled by default. Older macOS and Intel runtime behavior have not been directly verified. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE), copyright 2026 ZipLyne. Apple frameworks, GitHub CLI, and connected services have their own terms.
