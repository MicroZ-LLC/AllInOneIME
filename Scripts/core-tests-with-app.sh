#!/bin/sh
# The core's tests that run the input method's debug build as their child process: every suite or test in the core's
# tests enabled by `PlugLangCLI.available` (Core/Tests/AllInOneIMECoreTests/Acceptance/
# PluginLanguageAcceptanceTests.swift), as one regular expression for `swift test --filter` or `--skip`. `make test-mac`
# runs them with the binary it has just built; `make test-core` skips them (the core alone builds no input method, so
# CI's core-test has none, and a local one may be out of date). Read from the tests themselves, so that a new one isn't
# left out of both; fails when it finds none.
#
#   Scripts/core-tests-with-app.sh [the core's folder, default Core]
set -eu
found=$(find "${1:-$(dirname "$0")/../Core}/Tests" -name '*.swift' -exec awk '
    /enabled\(if: PlugLangCLI\.available/ { want = 1 }
    want && match($0, /(func|struct|class|enum|actor) [A-Za-z_][A-Za-z0-9_]*/) {
        split(substr($0, RSTART, RLENGTH), declared, " ")
        # A test function by its name and "(", a suite by its name and the "/" before its tests.
        print(declared[1] == "func" ? "/" declared[2] "\\(" : declared[2] "/")
        want = 0
    }' {} + | sort -u | paste -sd'|' -)
if [ -z "$found" ]; then
    echo "core-tests-with-app: no test of the core's is enabled by PlugLangCLI.available (moved? update this)" >&2
    exit 1
fi
echo "$found"
