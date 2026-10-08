# Grove

A native macOS workspace for your GitHub repositories and the services behind them. Organize repositories into projects, keep connected resources together, inspect deployment and app information, and find recent work from the menu bar.

Built with SwiftUI and AppKit, with an optional on-device Apple Intelligence assistant. No third-party Swift packages or cloud AI account is required. Grove is independent of GitHub, Apple, and the connected providers.

## Features

- Search names, descriptions, owners, languages, and topics across accessible repositories.
- Filter by owner, recent pushes, missing descriptions, archived repositories, or forks. Twelve remembered sort choices cover creation, push, update, names, stars, and issues/PRs in both directions.
- Group repositories into projects using stable GitHub IDs. Rename and transfer operations preserve project membership. Pin projects and share connections across repositories and projects.
- Open or copy links immediately, with clipboard feedback. Hide and restore owners locally.
- Use Quick Access from the menu bar or Command-Shift-P, with search, owner filtering, keyboard selection, sorting, and pinned service links.
- Refresh automatically while Grove is running, including after wake and network recovery. Saved data remains available when a request fails.
- Discover possible services from bounded, known repository configuration files. Suggestions remain unverified until you connect the matching provider account.
- Keep optional environment labels, notes, and exact dashboard URLs on service connections.
- Review every GitHub mutation. Delete and transfer require the exact full repository name. Supported provider name changes have separate live reviews.
- Ask Grove about repositories and saved service information using Apple Intelligence on this Mac. AI proposals use the normal mutation review.

## Service support

A verified resource means Grove successfully read that resource. It does not imply that its deployments, subscriptions, or error monitoring are healthy. Missing values are omitted. Each connection shows its last check, authorization errors, and stale data.

| Service | Information Grove reads | Changes inside Grove |
| --- | --- | --- |
| Expo | EAS project identity and recent builds | Dashboard settings |
| OneSignal | App identity, available subscription totals, bundle metadata | Reviewed app name |
| Search Console | Property access and available 28-day search totals | Dashboard settings |
| Cloudflare | Worker settings and deployment history, or Pages project and deployments | Dashboard settings |
| Vercel | Project identity, framework, recent deployments | Reviewed project name |
| RevenueCat | Project apps and available overview metrics | Dashboard settings |
| Sentry | Project identity, platform, latest release metadata | Reviewed project name |
| Google Analytics | Property identity and available 28-day reporting | Dashboard settings |
| App Store Connect | App identity and recent version states | Dashboard settings |
| Google Play | Package access verification only | Play Console |
| Custom Link | Saved HTTPS link; no provider check | Local title and link |

Resource pickers return a bounded first page, up to 200 entries depending on the provider. Exact IDs remain usable when a resource is outside that page. Expo and Google Play use manual IDs. Enter `pages:project-name` for a Cloudflare Pages connection; Workers use the script name. Google Play does not create edit sessions or import review content. Grove never sends notifications, changes subscriptions, publishes builds, or deploys projects.

## Requirements

| Purpose | Requirement |
| --- | --- |
| Repository and project workspace | macOS 15 or later |
| Build from source | Full Xcode 26 or later with the macOS 26 SDK and Swift toolchain |
| GitHub access | GitHub CLI (`gh`), signed in to github.com |
| Optional assistant | macOS 26 or later, supported hardware, and an available Apple Intelligence system model |
| Provider verification | Your own API credentials with permission to read the selected resources |

Grove finds `gh` at `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, or `/usr/bin/gh`. GitHub Enterprise hosts and other CLI paths are currently unsupported. The package declares macOS 15 support; runtime verification for this release uses a newer macOS version.

## Install and connect

Download the app from [Releases](https://github.com/ZipLyne-Agency/grove/releases), unzip it, and move Grove to Applications. GitHub CLI manages its own authentication:

```sh
brew install gh
gh auth login --hostname github.com
```

Launch Grove. It reads your accessible GitHub inventory automatically. Closing the main window leaves Quick Access running in the menu bar; Quit Grove exits completely. Reopen after installing a newer build. Command-F searches, Command-R refreshes, and Command-0 shows the library.

Create a project and select its repositories. Add a connection, choose the provider, and save a dashboard link or connect a credential account. A single credential account can serve multiple resources. Replacing its credential clears previous snapshots and checks the resources again. Removing an account leaves its connections as saved links.

## Provider credentials

Grove stores provider credentials in macOS Keychain. Paste a token or credentials JSON into the secure account field. Existing values are never displayed again. Use the narrowest permissions that support the reads you need; reviewed remote renames require additional write permission.

| Provider | Credential and scope |
| --- | --- |
| OneSignal | Organization API key |
| Expo | Expo access token |
| Cloudflare | Scoped API token; account ID |
| Vercel | Access token; optional team ID |
| RevenueCat | V2 secret key; app/project read and optional overview metrics read |
| Sentry | Token with project access; organization slug |
| Search Console / Analytics | OAuth JSON with `client_id`, `client_secret`, `refresh_token`, or service account JSON |
| Google Play | OAuth or service account JSON with Play Console access |
| App Store Connect | JSON with `issuer_id`, `key_id`, and `private_key` containing the `.p8` PEM |

For Google service accounts, grant access to the intended property in the provider before connecting it. A delegated user email is optional and works only if your Google Workspace administrator has already configured domain-wide delegation. Grove does not configure delegation, grant access, or change Google IAM. OAuth credentials must already have the relevant scopes. The account label and delegated subject help identify the intended account.

## Reviews and permissions

Grove uses the existing GitHub CLI login without storing its token or changing its scopes. Organization SSO, administrator access, and destination policies still apply. Deletion may require `delete_repo` for OAuth or classic tokens; fine-grained tokens have their own permissions.

Mutation previews identify the account, resource, operation, and result. They expire after five minutes and are consumed once. Grove checks the live account, immutable repository ID, metadata, and permissions before a GitHub write. Provider name reviews check the credential and live resource name again before writing. Cancel sends no mutation. No mutation is retried automatically.

Transfers are reported as requested because GitHub completes them asynchronously. An uncertain GitHub write blocks further mutations until refresh, including after restarting Grove. An uncertain provider rename asks you to sync and inspect the result before trying again. Local project edits, unlinking, and connection removal never delete provider resources.

## Privacy and local data

Repository metadata, including private names and descriptions, is cached at `~/Library/Application Support/Grove/inventory.json` with owner-only file permissions. Projects, account labels, connections, and selected provider snapshots are encrypted in `workspace.enc`, with the encryption key in macOS Keychain. API credentials are separate Keychain items. Developer ID builds use the Data Protection Keychain with device-only accessibility and synchronization disabled. Ad hoc development builds use the legacy login Keychain and do not provide device-only protection. These stores are separate; ad hoc builds use `workspace-development.enc`, and credentials entered there must be entered again in the signed app. Hidden owners and sorting preferences live in local app preferences.

GitHub reads and writes run through `gh`. Provider requests use fixed API hosts, bounded responses, request timeouts, and no cookie storage or redirects. Raw provider responses, authentication headers, notification credentials, customer records, and review text are not saved. A damaged or newer workspace is preserved and editing is blocked until it can be opened.

Repository questions may read a bounded README excerpt from GitHub. The assistant uses Apple's on-device Foundation Models framework, with saved service metrics and their check times. Names, descriptions, README text, and provider content are data, not instructions. Grove implements no cloud AI provider, analytics, telemetry, or saved AI conversations.

Do not attach credentials, caches, private READMEs, or unsanitized screenshots to public issues. This repository contains source and synthetic test fixtures only.

## Build and development

```sh
git clone https://github.com/ZipLyne-Agency/grove.git
cd grove
swift test
./scripts/build-app.sh
```

The build generates `~/Assets/grove/files/Grove.app` and its icon without relying on existing files there. Set `GROVE_OUTPUT` for a different directory. Local builds use an ad hoc signature by default. For a universal build with a Developer ID signature:

```sh
GROVE_UNIVERSAL=1 GROVE_TEAM_ID=YOURTEAMID GROVE_PROVISIONING_PROFILE=/path/to/Grove.provisionprofile GROVE_SIGNING_IDENTITY="Developer ID Application: Your Organization (TEAMID)" ./scripts/build-app.sh
```

The Developer ID profile must match the bundle identifier, team, and signing certificate. The build embeds it to authorize Data Protection Keychain access. Use `GROVE_CONFIGURATION=debug` for local UI inspection and `GROVE_BUILD_JOBS` to set build concurrency.

`scripts/notarize-app.sh` accepts the app path and reads `NOTARY_API_KEY_FILE`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER` from your secret broker. It notarizes, staples, assesses, and creates the release ZIP. Never commit signing credentials.

An optional provisioning mode, `Grove --import-setup-stdin`, accepts JSON containing `accounts` (`account` plus `credential`), `projects`, and `connections` using the Codable models in `GroveCore`. Use a local secret broker and stdin, never command-line secret arguments or a checked-in setup file. Import preserves existing workspace entries with other IDs and refuses unreadable workspaces. Quit Grove before importing: an exclusive workspace lock prevents setup and the app from writing concurrently.

Default tests use synthetic transports and perform no live mutations. Opt-in provider/GitHub reads and the on-device model smoke are disabled by default. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Assistant limits

Apple Intelligence is optional. Projects, services, and repositories work when the model is unavailable. A collection question samples at most 35 repositories. README excerpts and service context are bounded and may be incomplete or stale. Answers can be incorrect. A proposal targets one selected repository and requires the same explicit review as a manual edit.

Organization profile changes and unsupported provider settings open their dashboards. Bulk mutations, cloud AI, and automatic installation of app updates are outside this release.

## License

[MIT](LICENSE), copyright 2026 ZipLyne. Apple frameworks, GitHub CLI, and connected services have their own terms.
