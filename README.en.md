# Total Command

[Türkçe](README.tr.md) · [Language selection](README.md)

<img src="Resources/AppIcon.png" width="96" alt="Total Command icon">

An independent native macOS dual-pane file manager built with Swift and AppKit, inspired by Total Commander. The application interface is currently in Turkish.

## Install

Requires macOS 13 or later. Supports Apple Silicon and Intel. Version 0.2.2 is an early preview, signed with Developer ID and notarized by Apple.

Download the [0.2.2 release](https://github.com/ferdisahin/total-command/releases/tag/v0.2.2), open the DMG and drag `TotalCommand.app` to Applications, or install with Homebrew:

```sh
brew install --cask ferdisahin/tap/total-command
```

To upgrade, run `brew update` followed by `brew upgrade --cask ferdisahin/tap/total-command`. Uninstall with `brew uninstall --cask total-command`; preferences are retained unless you add `--zap`.

## Build and test

Install the Xcode Command Line Tools. No third-party package is required for building. Archive operations use macOS `/usr/bin/bsdtar`.

```sh
./build.sh
./test.sh
```

For a universal development build:

```sh
BUILD_ARCHS='arm64 x86_64' ./build.sh
```

Default development builds are ad-hoc signed. Public releases are separately signed and notarized.

## In development: 0.2.3

- A pinned `[..]` parent-folder entry in both list and icon views. It ignores sorting and filtering, is excluded from file operations, and is hidden at the filesystem root.
- A copy/move queue with pending-job cancellation, pause/resume between jobs, and session history including errors.

These additions are not included in the published 0.2.2 download yet.

## File management

- Two independent panels, per-panel tabs, list/icon views and sortable name, extension, size and modification-date columns.
- Editable paths, back/forward/up navigation, mounted disks and favorite locations.
- Filename filtering, hidden files, multiple selection, wildcard selection and invert selection.
- Background copy/move with item-based progress and cancellation. Dragging from Finder or the other panel copies into the destination panel's current folder.
- Command+C/X/V file clipboard; normal text editing behavior inside text fields.
- New folders/text files, rename and batch rename with a preview.
- Quick Look, opening in the selected editor, file information, reveal in Finder and copy path.
- Quick Look thumbnails for supported images, PDFs and videos in icon view.
- Context menus and persistent favorites.
- Size/date comparison and one-way folder synchronization with a preview and backups.
- Run a shell command in the active folder and view its output, or open Terminal there.
- Connect to SMB/AFP servers through Finder; refresh to list a newly mounted volume.

## Archives

Create ZIP and 7z archives. Extract ZIP, 7z, RAR, TAR, GZ, BZ2 and XZ as supported by the system archive engine. RAR variants depend on the system engine; encrypted archives are unsupported.

Double-clicking an archive opens its contents in a temporary folder. Edits are not written back to the original archive. Parent navigation at the archive root returns to the archive's original location. Extract creates a new unique folder in the opposite panel. Temporary archive folders are cleaned up when the application exits.

## Settings

Open the Settings button, **Total Command → Ayarlar…**, or Command+,.

| Section | Options |
|---|---|
| General | Restore tabs, startup folders, text editor, default view |
| Appearance | System/light/dark theme, 11–15 pt type, row height, date style, folders first, extensions, thumbnails, hidden files and command bar |
| Files | Ask/keep both/skip name collisions; confirmations for move and Trash |
| Archives | Default ZIP/7z format and opening archives inside a panel |
| Search | Include hidden files; 100/1,000/5,000 result limits |
| Keyboard | Enable function keys, Space preview, configurable F3–F8 actions |
| Updates | Manual/daily/weekly checks, preview releases and check status |

Settings save automatically. Reset preserves favorites and stored tabs. Restored tabs take precedence over startup folders. Appearance changes apply to both panels.

## Updates

Use **Total Command → Güncellemeleri Kontrol Et…** or **Settings → Güncellemeler** to check GitHub releases. Automatic checks are off by default; daily or weekly checks and preview releases are optional. A new release opens its GitHub download page for user-initiated installation. The app does not replace itself automatically. See [update behavior](docs/UPDATES.md).

## Default shortcuts

F2 rename; F3 preview; F4 edit; F5 copy; F6 move; F7 new folder; F8 move to Trash. Mac keyboards may require Fn. Space opens Quick Look, Tab switches panels, Return opens the selection, and Command+Up opens the parent folder. Command+T/W opens/closes tabs; Command+D/B adds/opens favorites; Command+F searches; Command+M opens batch rename; Command+R refreshes; Command+U swaps panels.

## Behavior and limitations

Name collisions never overwrite a destination file automatically. The default asks before keeping both copies with numbered names. Synchronization runs from the active panel to the opposite panel, compares size/date, and does not remove extra destination files. Replaced targets are preserved with a `.totalcommand-backup` suffix. Content/hash comparison is not implemented.

Copy and move jobs run sequentially in the queue. Pausing holds the next job; it does not freeze the active job. Queued sources and destination paths are captured when the job is added. Files that disappear before execution cause a logged error; the next job can continue. Other commands require the queue to finish. Cancellation is checked between files and may wait for a large individual file. A cancelled folder copy's temporary destination is removed, while earlier completed files remain. Session history retains the last 100 finished jobs and is lost on exit. There is no full-operation undo or restart recovery.

Search matches file names rather than contents and skips application bundles. Native FTP/SFTP, plugins, encrypted/split archives, archive writeback, file splitting/joining, two-way synchronization and advanced content comparison are not implemented. This application does not have full feature parity with Total Commander.

## Validation

Tests cover Unicode/space-containing filenames, collisions, nested directories, symlinks, self-transfer rejection, cancellation cleanup, move, batch rename, safe archive paths, backup synchronization, preferences, ZIP/7z round trips, update version/channel handling and queue behavior. See [validation notes](docs/VALIDATION.md) for remaining manual checks. Not all archive variants, remote servers, OS versions or hardware have been tested end to end.

## License

Copyright © 2026 Ferdi Sahin. **GPL-3.0-only**; see [LICENSE](LICENSE). Distributed modified versions must provide their corresponding source under GPLv3. No warranty is provided. This is an independent project, not an official Total Commander product.
