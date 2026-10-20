# Release checking

Version 0.2.2 adds manual update checks and opt-in daily or weekly checks while the application is open and active. Controls are under Settings → Updates. Automatic checking defaults to off. No network request is sent for update checking until the user checks manually or enables a schedule.

The application requests the public GitHub release list for ferdisahin/total-command (the latest 100 published entries), without a token, cookies, or stored credentials. GitHub receives the app version/User-Agent and ordinary network connection information. File contents and paths are not included.

Versions use SemVer ordering, not string ordering or publication date. Drafts, invalid tags, equal versions and older versions are ignored. Preview releases require opt-in, including semantic prerelease tags even if the GitHub prerelease flag is missing. Stable releases remain eligible on the preview channel.

Checks time out after 20 seconds. Failed automatic checks are silent and wait until the next scheduled interval; manual checks show a recoverable error. Concurrent checks share one request. A newer version prompts once per tag automatically; a manual check can show it again. Update prompts wait until a file operation or modal interaction has finished and the app is active.

The action opens the canonical GitHub release page. It does not download, execute, install or replace software. Homebrew installations can be updated with `brew update` and `brew upgrade --cask total-command`. Each release still requires Developer ID signing, notarization and a matching cask checksum. A fully automatic installer is not included in this release.

API reference: https://docs.github.com/en/rest/releases/releases#list-releases
