Grove 0.3.0 adds signed in-app updates and a repository-focused Library.

- Choose Grove > Check for Updates… or use the Updates section in Settings. Automatic update checks are optional.
- Build repository descriptions and detect integrations from bounded source scans, with on-device Apple Intelligence when available.
- View a compact Overview, hide integrations you do not want to see, and restore them from Hidden Integrations. Hidden choices survive rescans.
- Search local descriptions and integrations, pin repositories to Quick Access, and resume incomplete profile generation.
- New users receive GitHub CLI setup guidance and connect their own GitHub account.

Download the ZIP, unzip Grove.app, and move it to Applications. This release supports macOS 15 or later and includes Intel and Apple Silicon binaries. Apple Intelligence requires macOS 26 and supported hardware.

This is the first release with the updater, so installing it from 0.2.x is manual. Later releases can install from inside Grove. The app is Developer ID signed and notarized. Updates verify a signed feed and archive before installation and wait for active work and saved workspace data before relaunching.

Source is available under the MIT license. Release downloads contain no user inventory, workspace archive, saved account, or GitHub credential. Each user signs in through their own GitHub CLI. Runtime on Intel hardware and macOS 15 has not been directly tested.
