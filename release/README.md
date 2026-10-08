# Releases

Releases are built from pushed `main`. `version.json` contains the marketing version and monotonically increasing build number. Increment both for each public release. Never replace published archives or reuse a build number.

Sparkle 2.10.0 verifies the signed feed and archive before extraction. The feed is the `appcast.xml` asset on the latest GitHub release. Each enclosure points to its immutable version tag. The public key is committed here. The private signing key stays in the release maintainer's Keychain under account `agency.ziplyne.grove.updates`, backed up through a secret manager. Contributors build with the public key; they cannot publish a trusted update without the private key.

1. Update the version, run `swift test`, and review the source and packaged files for private data.
2. Build with `GROVE_UNIVERSAL=1` and `GROVE_SIGNING_IDENTITY`, `GROVE_TEAM_ID`, `GROVE_PROVISIONING_PROFILE` supplied by your protected release environment. Run `./scripts/build-app.sh`. Generated artifacts go outside the repository.
3. Supply `NOTARY_API_KEY_FILE`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER` through a secret broker. Run `./scripts/notarize-app.sh /path/to/Grove.app`. The key file must be protected and removed afterwards. Never add a profile, private key, or authentication file to the repository.
4. Test a signed update from the preceding build, including relaunch, saved workspace preservation, and an interrupted or blocked operation. Keep test feeds local and remove any `SUFeedURL` preference override afterwards.
5. Commit and push the reviewed source. Put only this release's ZIP in its artifact folder. Write public release notes without personal repositories or screenshots.
6. Set the expected `GROVE_TEAM_ID` and run `python3 scripts/publish-release.py /path/to/Grove-VERSION-macOS.zip --notes /path/to/notes.md`. This validates the archived bundle, signing and notarization, creates a signed appcast using the Keychain key, and uploads a draft release. The script downloads draft assets and compares their hashes before publication. Review the draft, then rerun with `--publish` when publication is authorized. That path also verifies the public assets and latest feed.
7. Fetch the latest feed and check the installed app reports the current version. GitHub's public assets become available only after publication.

The publishing script refuses dirty or unpushed source. It never commits, pushes, or changes credentials. The public CI workflow runs synthetic tests and creates an ad hoc bundle without signing secrets. Developer ID distribution uses the release maintainer's protected environment.

Release archives contain the app, icon and Sparkle framework. User inventory, encrypted workspaces, preferences and Keychain items remain outside the bundle. Runtime behavior on older macOS and Intel hardware still needs separate verification even when universal builds succeed.
