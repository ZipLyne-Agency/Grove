# Grove

A native macOS app for managing GitHub repositories across your personal account and organizations. Browse projects in one library, find recent work from the menu bar, and review every change before it reaches GitHub.

Built with SwiftUI and AppKit. Optional Apple Intelligence runs on your Mac. No third-party Swift packages, bundled models, background polling, or cloud AI service.

**Status:** early release, built from source. Packaged builds are locally signed, not notarized. GitHub permissions and organization policies still apply. Grove is an independent project, not affiliated with GitHub or Apple.

## Features

- Search repository names, descriptions, owners, languages, and topics.
- Filter by owner, recent pushes, missing descriptions, archived repositories, and forks. Sort by last push, name, or stars.
- Open Quick Access from the menu bar or with Command-Shift-P. Search, filter owners, navigate with arrow keys, and press Return to reveal a result.
- Copy repository links, full names, and clone commands through a confirmation sheet.
- Review renames, description edits, transfers, archive changes, and deletion. Transfer and deletion require the exact full repository name.
- Hide and restore owners locally without changing GitHub access.
- Ask Apple Intelligence about a repository, an owner, or your library. Suggestions require a separate review before any change.

## Requirements

| Purpose | Requirement |
| --- | --- |
| Run the library | macOS 15 or later |
| Build from source | Full Xcode 26 or later, including the macOS 26 SDK and Swift toolchain |
| GitHub access | GitHub CLI (`gh`) installed and signed in to github.com |
| Optional assistant | macOS 26 or later, a supported Mac, and an available Apple Intelligence system model |

The current build was verified with Xcode 27 and Swift 6.4. The macOS 15 deployment target is declared in the package; runtime checks in this initial release were performed on a newer macOS version.

Grove finds `gh` at `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, or `/usr/bin/gh`. GitHub Enterprise hosts and other CLI locations are currently unsupported.

## Build and install

Install GitHub CLI if needed, then sign in:

```sh
brew install gh
gh auth login --hostname github.com
```

Clone and build:

```sh
git clone https://github.com/ZipLyne-Agency/grove.git
cd grove
swift test
./scripts/build-app.sh
```

The build creates `~/Assets/grove/files/Grove.app`, generates its icon, and applies an ad hoc local signature. It does not depend on files already in that directory. To choose a different output directory:

```sh
GROVE_OUTPUT="$HOME/Downloads/Grove-build" ./scripts/build-app.sh
```

Copy the resulting app to Applications and launch it. Confirm **Connect GitHub** to read your account and accessible repositories. The main window can be closed while Quick Access remains in the menu bar. Quit Grove to exit completely.

Command-F searches the library, Command-R opens the refresh review, and Command-0 shows the library. Reopen the app after installing a newer build.

## Permissions and confirmations

Grove uses your existing GitHub CLI sign-in. It does not request a token, store one, or change its scopes. Only repositories accessible to that account appear. Organization SSO, destination policies, and administrator access can restrict changes. Deletion may require the separate `delete_repo` scope for OAuth or classic tokens; fine-grained credentials remain subject to their own permissions.

Selection, search, sorting, and opening local panels happen immediately. Connecting, refreshing, opening a browser, copying to the clipboard, changing local owner visibility, and asking the assistant require confirmation. The Copy Name button inside an existing typed-name review copies immediately.

Mutation previews identify the account, repository, operation, and result. They expire after five minutes. Grove consumes an approval once, checks the live account and repository identity and metadata, and verifies administrator access before writing. Transfer checks the destination and name collision. Cancel sends no write. Deletion has no default Return shortcut.

Transfers are reported as requested because GitHub finishes them asynchronously. An uncertain write result pauses further changes until refresh, including after an app restart. Grove does not automatically retry mutations.

## Privacy

Repository names, descriptions, and other metadata stay in the local cache at `~/Library/Application Support/Grove/inventory.json`. This can include private repository information. The cache directory is created with owner-only permissions and the file with owner read/write permissions. Hidden-owner preferences are stored in local app preferences.

Confirmed GitHub operations communicate with GitHub through `gh`. A repository question reads a bounded README excerpt from GitHub after confirmation; the model answer runs on-device through Apple's Foundation Models framework. Grove does not implement a cloud AI provider, analytics, telemetry, or persistence of AI conversations, authentication tokens, or HTTP headers. The GitHub CLI manages its own authentication separately.

Never attach your cache, CLI credentials, private README contents, or unsanitized screenshots to a public issue. This repository contains source and synthetic test fixtures only. Local screenshots, account inventories, and build artifacts are excluded.

## Assistant limitations

Apple Intelligence is optional. The library works when the system model is unavailable. Repository questions use an excerpt of the README. Collection questions consider at most the 35 most recently pushed repositories in the selected context, with coverage explained in the UI. Answers can be incomplete or incorrect. A proposal applies to one explicitly selected repository and opens the same approval flow as a manual edit.

Claude, other cloud models, bulk mutations, organization renaming inside Grove, automatic updates, and notarized binary distribution are not included. Organization profile edits open GitHub settings for manual changes.

## Development

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout and checks, and [SECURITY.md](SECURITY.md) for private vulnerability reporting.

Default tests use simulated transports and perform no live GitHub mutations. Opt-in live-read and on-device-model smoke tests are skipped unless explicitly enabled. Native UI checks covered search, clipboard reviews, editor cancellation, assistant output, and minimum-window layout. Quick Access interaction checks used a debug-only anchor because background automation cannot keep a transient status-bar popover open; physical menu-bar positioning still needs a manual check.

## License

[MIT](LICENSE), copyright 2026 ZipLyne. Apple frameworks and GitHub CLI are separate dependencies under their respective terms.
