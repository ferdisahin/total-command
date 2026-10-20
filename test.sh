#!/bin/zsh
set -eu
cd "$(dirname "$0")"
TEST_BIN=$(mktemp -d "${TMPDIR:-/tmp}/panelmac-tests.XXXXXX")
trap 'rm -rf "$TEST_BIN"' EXIT
swiftc Sources/Core.swift Sources/Jobs.swift Sources/Updates.swift Sources/Settings.swift Tests/CoreTests.swift Tests/UpdateTests.swift Tests/JobTests.swift -framework Cocoa -o "$TEST_BIN/tests" -module-cache-path "${TMPDIR:-/tmp}/panelmac-module-cache"
"$TEST_BIN/tests"
