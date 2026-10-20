#!/bin/zsh
set -eu
cd "$(dirname "$0")"
TEST_BIN=$(mktemp -d "${TMPDIR:-/tmp}/panelmac-tests.XXXXXX")
trap 'rm -rf "$TEST_BIN"' EXIT
swiftc Sources/Localization.swift Sources/Core.swift Sources/Jobs.swift Sources/Remote.swift Sources/SiteManager.swift Sources/Diff.swift Sources/MultiRename.swift Sources/FileSplitter.swift Sources/Updates.swift Sources/Settings.swift Tests/LocalizationTests.swift Tests/CoreTests.swift Tests/RemoteTests.swift Tests/DiffTests.swift Tests/MultiRenameTests.swift Tests/FileSplitterTests.swift Tests/UpdateTests.swift Tests/JobTests.swift -framework Cocoa -o "$TEST_BIN/tests" -module-cache-path "${TMPDIR:-/tmp}/panelmac-module-cache"
"$TEST_BIN/tests"
