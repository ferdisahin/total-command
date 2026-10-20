# GitHub, signing and Homebrew

## Current state

GitHub target: `ferdisahin/total-command`. The selected license is GPL-3.0-only. The public source repository and Developer ID-signed, Apple-notarized v0.2.1 preview release are published. The Homebrew cask is maintained in `ferdisahin/homebrew-tap`. Development builds are locally ad-hoc signed.

## Apple signing

Use an active Apple Developer Program membership and a **Developer ID Application** certificate with its private key in the macOS Keychain. A Mac App Store distribution certificate is a different identity.

Inspect identities locally:

```sh
security find-identity -v -p codesigning
```

Create a notarytool Keychain credential profile using an Apple-supported authentication method. Enter credentials locally, never in chat, source files or Git commits. The profile name can be `total-command-notary`.

```sh
xcrun notarytool store-credentials total-command-notary
```

After committing the release source (LICENSE is included), use the 40-character SHA-1 identity listed by `security find-identity`. Selecting by hash avoids locale issues with non-ASCII names:

```sh
SIGNING_IDENTITY='DEVELOPER_ID_APPLICATION_SHA1' \
NOTARY_PROFILE='total-command-notary' \
./scripts/release.sh
```

The script tests, builds arm64 + x86_64, signs with hardened runtime and secure timestamp, notarizes/staples the app, builds/signs/notarizes/staples a DMG, and writes final DMG/ZIP checksums. It does not upload to GitHub. Apple can reject a submission; the script stops and records the notary result.

Official workflow: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## GitHub

The GitHub owner is `ferdisahin` and the license is GPL-3.0-only. Confirm the stable bundle identifier before the first public release. The current bundle identifier is `com.totalcommand.desktop`; do not casually change it after release, because preferences and OS permissions use it.

The CI workflow builds and tests pull requests without signing secrets. CI artifacts are clearly marked as development builds. The maintainer signs releases locally, so certificates do not need to be uploaded to GitHub.

Once the public repository exists and the release source is committed, create and push an annotated `v0.2.1` tag from that exact commit. Upload the matching final artifacts using the GitHub release UI, or with authenticated GitHub CLI:

```sh
./scripts/publish.sh ferdisahin/total-command
```

This creates a **draft prerelease**, requiring a final review before publication. The script requires an existing remote tag and clean working tree.

## Homebrew

A native GUI application is distributed as a **Cask**. Begin with a personal tap named `ferdisahin/homebrew-tap`. A personal tap is independent from acceptance into the central `homebrew/cask` repository.

Generate the Cask only after final notarized artifacts exist. The cask uses the ZIP containing the stapled app, avoiding a DMG mount during installation:

```sh
./scripts/generate-cask.sh ferdisahin total-command
```

Copy `packaging/Casks/total-command.rb` into `Casks/total-command.rb` in the public `homebrew-tap` repository. Publish the GitHub release before testing installation, because the Cask downloads its ZIP from that release URL.

Users can then install with:

```sh
brew tap ferdisahin/tap
brew install --cask ferdisahin/tap/total-command
```

Test the Cask with `brew style`, `brew audit --cask` and a clean install/uninstall using the actual published artifact. A new version requires a new immutable release file, new checksum and Cask update. Do not use `sha256 :no_check`.

Official guides:
- https://docs.brew.sh/Cask-Cookbook
- https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap
