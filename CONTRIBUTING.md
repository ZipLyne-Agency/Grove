# Contributing to Grove

Small, focused pull requests are welcome. Open an issue for a larger feature or behavior change before implementation. Include the problem, the resulting behavior, and the checks you ran.

## Project layout

| Path | Responsibility |
| --- | --- |
| `Sources/Grove` | Native library, menu bar, assistant, and review UI |
| `Sources/GroveCore` | GitHub and provider transports, authorization, discovery, encrypted workspace persistence, and approvals |
| `Tests/GroveTests` | Repository/workspace state, stale-result isolation, and reviews |
| `Tests/GroveCoreTests` | Approval, identity, provider projection, persistence, and query tests |
| `scripts/build-app.sh` | Local or universal app bundle, signing, and generated icon |

## Checks

Use full Xcode 26 or later. Run `swift test` for source changes and `./scripts/build-app.sh` when changing the app or packaging. Describe manual UI checks for visible changes, including keyboard use and the minimum 1040 by 700 window.

Default tests use synthetic fixtures and mocked GitHub and provider responses. Do not run mutations against a real repository as part of a test. Keep new fixtures synthetic and keep generated files outside the checkout.

The debug-only `--keep-quick-access-open` argument keeps Quick Access open and anchors it to the library window for background UI automation. Release builds exclude this override. Verify real status-bar positioning and normal click-away dismissal separately.

## Preserve the approval contract

Every GitHub change needs an explicit review. AI output can propose one change but cannot execute it. Keep approvals bound to immutable repository identity and a single preview, consumed once before asynchronous work. Preserve live account and permission checks, typed-name transfer and deletion confirmation, expiry, and the refresh requirement after an uncertain result.

Provider renames need their own one-use reviews, credential binding, and live name checks. Provider reads must project explicitly selected fields rather than persist raw JSON. Keep credentials in Keychain and response headers out of error messages.

Do not add automatic mutation retries or include authentication data, account caches, private project metadata, or real repository screenshots in a contribution. Report vulnerabilities privately through the process in SECURITY.md.

Contributions are made under the repository's MIT license.
