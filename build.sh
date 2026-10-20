#!/bin/zsh
set -eu
cd "$(dirname "$0")"
BUILD_ARCHS="${BUILD_ARCHS:-$(uname -m)}"
BUILD_WORK=$(mktemp -d "${TMPDIR:-/tmp}/total-command-build.XXXXXX")
trap 'rm -rf "$BUILD_WORK"' EXIT
mkdir -p TotalCommand.app/Contents/MacOS TotalCommand.app/Contents/Resources
cp Resources/Info.plist TotalCommand.app/Contents/Info.plist
cp Resources/AppIcon.icns TotalCommand.app/Contents/Resources/AppIcon.icns
for language in en tr; do
  cp -R "Resources/$language.lproj" TotalCommand.app/Contents/Resources/
done
if [[ -f LICENSE ]]; then cp LICENSE TotalCommand.app/Contents/Resources/LICENSE; fi
binaries=()
for arch in ${=BUILD_ARCHS}; do
  case "$arch" in arm64|x86_64) ;; *) print -u2 "Unsupported architecture: $arch"; exit 1 ;; esac
  binary="$BUILD_WORK/TotalCommand-$arch"
  swiftc -O -target "$arch-apple-macos13.0" Sources/Localization.swift Sources/Core.swift Sources/Jobs.swift Sources/Remote.swift Sources/SiteManager.swift Sources/Diff.swift Sources/DiffWindow.swift Sources/MultiRename.swift Sources/FileSplitter.swift Sources/Updates.swift Sources/Settings.swift Sources/QueueWindow.swift Sources/main.swift \
    -o "$binary" -framework Cocoa -framework QuickLookUI -framework QuickLookThumbnailing \
    -module-cache-path "${TMPDIR:-/tmp}/total-command-module-cache/$arch"
  binaries+=("$binary")
done
if (( ${#binaries} == 1 )); then
  cp "${binaries[1]}" TotalCommand.app/Contents/MacOS/TotalCommand
else
  lipo -create "${binaries[@]}" -output TotalCommand.app/Contents/MacOS/TotalCommand
fi
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" TotalCommand.app
else
  codesign --force --sign - TotalCommand.app
fi
codesign --verify --strict --verbose=1 TotalCommand.app
