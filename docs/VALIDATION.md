# Distribution validation — 0.2.1

Checked on 2026-10-20.

- Existing file-operation and settings tests passed, including collision preservation, symlinks, cancellation cleanup, backup sync, and ZIP/7z round trips.
- Downloaded the published ZIP from GitHub and verified the extracted application signature. It contains x86_64 and arm64, hardened runtime, Developer ID team 844PYVP7EV, and a stapled notarization ticket. Both stored notarization reports have status Accepted.
- Release DMG and ZIP match SHA256SUMS. The cask uses the published ZIP SHA-256, with a macOS 13 minimum and the correct TotalCommand.app artifact.
- Homebrew 7 parsed the cask; brew style passed without offenses.

## Remaining manual checks

This was not a test on a separate clean Mac. Homebrew audit stopped because the installed Command Line Tools are older than Homebrew requires. Homebrew installation in the agent environment stopped because nested sandbox-exec is prohibited; no sandbox protections were disabled. DMG mounting was also unavailable in this environment. The maintainer subsequently confirmed a successful normal-Terminal Homebrew installation of 0.2.1 into /Applications. Uninstall and Gatekeeper first launch on a separate clean machine remain unverified.

```sh
brew install --cask ferdisahin/tap/total-command
```

Open TotalCommand.app and check Finder permissions, both panels, copy/move cancellation, and large-file behavior. Also test on an Intel Mac and the minimum supported macOS release before promoting this preview to stable.

To remove a test installation: `brew uninstall --cask total-command`. This retains preferences; `--zap` removes them.

## 0.2.2 development checks

Added semantic-version/channel selection tests, invalid feed and HTTP error tests, and daily/weekly scheduling tests. Update settings defaults and reset are covered. A live GitHub check from the new native settings tab completed successfully and displayed no newer eligible version. Universal development build and the existing file-operation suite passed. This is not a signed 0.2.2 release validation.

A separate QA app with injected HTTP fixtures also verified the loading state, persistent HTTP 429 rate-limit explanation, and update-available alert. The synthetic v9.0.0 fixture was not published. Native layout was reviewed in the existing light appearance; dark appearance and VoiceOver were not separately exercised.

## 0.2.3 development checks

Queue tests cover FIFO execution, pending/running cancellation, pause/resume between jobs, continuation after failure and the 100-entry finished-history limit. Existing transfer, archive, preference and update tests passed. Native UI checks verified Return on the parent entry, cancelling a queued copy and copying a second file after resuming. The cancelled copy did not create its destination; the completed file matched its source. The experimental middle bar was removed after its layout failed; the original two-pane split is retained. This is not a signed 0.2.3 release validation.
