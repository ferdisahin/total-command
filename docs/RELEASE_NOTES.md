Total Command 0.2.2 (unreleased preview)

- Check for updates from the application menu or Settings → Updates.
- Optional daily/weekly checks; optional preview releases. Automatic checks are off by default.
- Numeric semantic-version comparison, explicit network failures, and notifications deferred during file operations.
- Opens the GitHub release page for user-initiated installation; does not replace the application automatically.

---

Total Command 0.2.1 is an early macOS preview with a native dual-pane interface.

Includes tabs, list/icon views, Quick Look thumbnails, background copy/move, drag and drop, batch rename previews, folder comparison, one-way synchronization with backups, ZIP/7z creation and archive extraction, a command bar, and six categories of persistent settings.

Known limitations: no built-in FTP/SFTP, encrypted archives, plugins, archive write-back or bidirectional synchronization. Folder comparison uses size and modification time, not content hashes. Copy/move cancellation takes effect between files.

Public release artifacts must be signed with Developer ID, notarized and stapled. Development CI artifacts are ad-hoc signed and are not the public release.

Includes the new red floppy-disk application icon for Finder, Dock, and application dialogs.
