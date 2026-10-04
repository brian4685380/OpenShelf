# Security

OpenShelf works with files and clipboard content locally. It does not upload content, run analytics, or require an account. Opening files and links hands them to the appropriate application; that application may have its own network behavior.

CLI requests briefly store file paths (not file contents) in a per-user temporary queue with owner-only directory permissions. Request IDs are UUIDs, directory symlinks are rejected, and stale requests expire after ten seconds. The CLI removes its request/reply after success or timeout. The app retains only a bounded in-memory set of completed request IDs to prevent duplicate actions.

## Distribution

Use this repository's GitHub Releases or the `brian4685380/openshelf` Homebrew tap. Homebrew verifies the release ZIP's SHA-256 checksum. Release pages include `SHA256SUMS` for ZIP and DMG downloads.

Current releases are ad-hoc signed, not Developer ID signed or notarized by Apple. A valid ad-hoc signature checks bundle integrity; it is not identity verification or a malware review. Never disable Gatekeeper system-wide to install OpenShelf.

## Reporting a vulnerability

Please do not publish private files, exploit payloads, or sensitive clipboard contents in an issue. If private vulnerability reporting is available, use the repository's **Security → Report a vulnerability** page. Otherwise, open a minimal issue requesting a private contact channel without disclosing the vulnerability details.

Security fixes target the latest release. Older releases are not maintained as separate security branches. There is no guaranteed response time; this is a community-maintained project.
