# Distribution validation — 0.2.1

Checked on 2026-10-20.

- Existing file-operation and settings tests passed, including collision preservation, symlinks, cancellation cleanup, backup sync, and ZIP/7z round trips.
- Downloaded the published ZIP from GitHub and verified the extracted application signature. It contains x86_64 and arm64, hardened runtime, Developer ID team 844PYVP7EV, and a stapled notarization ticket. Both stored notarization reports have status Accepted.
- Release DMG and ZIP match SHA256SUMS. The cask uses the published ZIP SHA-256, with a macOS 13 minimum and the correct TotalCommand.app artifact.
- Homebrew 7 parsed the cask; brew style passed without offenses.

## Remaining manual checks

This was not a test on a separate clean Mac. Homebrew audit stopped because the installed Command Line Tools are older than Homebrew requires. Homebrew installation in the agent environment stopped because nested sandbox-exec is prohibited; no sandbox protections were disabled. DMG mounting was also unavailable in this environment. Therefore a complete Homebrew install/uninstall and Gatekeeper first launch still need verification in a normal user Terminal on a clean machine.

```sh
brew install --cask ferdisahin/tap/total-command
```

Open TotalCommand.app and check Finder permissions, both panels, copy/move cancellation, and large-file behavior. Also test on an Intel Mac and the minimum supported macOS release before promoting this preview to stable.

To remove a test installation: `brew uninstall --cask total-command`. This retains preferences; `--zap` removes them.
