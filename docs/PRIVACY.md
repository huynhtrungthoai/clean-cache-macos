# Privacy Policy

**CleanPilot** · Effective: 2026-09-27

## English

CleanPilot is a local disk-cleanup utility. **We do not collect, store, or transmit any of your
data.** There is no account, no analytics, no crash reporting, no advertising, and no telemetry
of any kind — the app has no network access at all.

Everything happens on your own Mac, at the moment you run the app:

- **What the app reads.** Directory listings and file metadata (size, modification time, symlink
  targets) for the locations the scan reaches, so it can show you what is using your disk. The
  direct-download build walks the whole volume from a whitelist of roots, which includes system
  areas and other users' home folders; the Mac App Store build is confined by the sandbox to the
  folder you grant once (your home) plus `/Applications`. It does not read the *contents* of your
  documents. One opt-in exception: the content probe (off by default). When you turn it on, the app
  reads the first 64 KB of crash-dump files it has identified, solely to tell which process wrote
  them; those file headers never leave your machine.
- **What the app writes.** Only its own data on your Mac: which appearance skin you picked, which
  language the interface uses, — in the Mac App Store version — a security-scoped bookmark
  recording which folder you granted access to, and a small local SQLite database of scan
  snapshots (sizes and file counts of recognized items, kept to the last 30 scans) so growth can
  be compared across scans. All of it lives on your machine and never leaves it.
- **Deletions.** CleanPilot never deletes outright. Items you choose are moved to the macOS Trash
  through the system's own Trash mechanism, and emptying the Trash is a separate action you take.
  In the direct-download build the app asks Finder to empty it and Finder confirms with you first;
  in the Mac App Store build the sandbox does not allow that request at all, so the app only opens
  the Trash and you empty it yourself in Finder.
- **Feedback.** If you contact us by email, the messaging group, or a GitHub issue, you are doing
  so yourself through a third-party service; whatever you include in that message is governed by
  that service's policy, not by this app.

CleanPilot requests macOS permissions only where the operating system requires them to deliver a
feature you asked for — for example, in the direct-download build, permission to send Finder the
"empty the Trash" command. The App Store build never asks for it: the sandbox refuses that command,
so there the app only opens the Trash window. Each grant can be revoked in System Settings.

Questions: open an issue at <https://github.com/huynhtrungthoai/clean-cache-macos/issues>.
