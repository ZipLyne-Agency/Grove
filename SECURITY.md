# Security

## Report a vulnerability privately

Use GitHub's **Report a vulnerability** option in the Security tab of this repository. If unavailable, contact ZipLyne through [ziplyne.agency](https://ziplyne.agency) to arrange a private report. Do not include exploit details or private account data in a public issue.

Include the affected commit or version, the behavior, its impact, and a minimal reproduction using synthetic repositories or a mocked transport. Never send tokens, CLI credential files, local inventory caches, or private README contents.

## Scope and current support

Grove is an early source release. The main branch receives fixes; there is no separate supported release series or response-time commitment yet.

Important boundaries include single-use approval, live account and repository identity checks, cancellation, destination validation, and keeping AI proposals separate from execution. Tests cover these boundaries with simulated transports. Passing tests or a secret scan do not establish that every application behavior is secure.

Local inventory caches can contain private metadata. Credentials remain managed by GitHub CLI. Review permissions before authorizing a destructive action, and keep backups of repositories you may delete.
