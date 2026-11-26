#!/bin/sh
# Scripts/test-scope.sh against a table: the paths a change touched, and the test jobs it then needs, written as
# "core mac update" with "-" for one it doesn't (core: core-test, mac: mac-test, update: the updater's test in
# mac-test). A wrong line in test-scope.sh skips a test job without a word; this fails instead. Run by `make lint`.
# The paths are read in a scratch folder that holds the few files the table needs (a core test file's text decides
# whether it counts for mac-test too), so that the table doesn't depend on the tests the repository has today.
#
#   Scripts/test-scope-test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
scope=$here/test-scope.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/allinoneime-scope-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
failures=0
checks=0

# A plain test of the core's, one that runs the input method (PlugLangCLI) and one that declares a test the hosted
# runner skips (the first in Core/Scripts/hosted-runner-skips.txt).
tests=$work/Core/Tests/AllInOneIMECoreTests
mkdir -p "$tests"
printf '@Test func plain() {}\n' > "$tests/PlainTests.swift"
printf '@Test(.enabled(if: PlugLangCLI.available)) func runsTheApp() {}\n' > "$tests/AppTests.swift"
slow=$("$here/../Core/Scripts/hosted-runner-skips.sh" --functions | head -1)
printf '@Test func %s() {}\n' "$slow" > "$tests/SlowTests.swift"

# verdict INPUT: test-scope.sh's answer for INPUT (the paths, a line each), as "core mac update" with "-" for false.
verdict() {
    (cd "$work" && printf '%s' "$1" | "$scope") | awk -F= '{ printf "%s%s", (NR > 1 ? " " : ""), ($2 == "true" ? $1 : "-") }'
}

# expect WHAT WANT INPUT
expect() {
    checks=$((checks + 1))
    got=$(verdict "$3") || got="failed"
    if [ "$got" = "$2" ]; then
        echo "✔ $1: $got"
    else
        echo "✘ $1: $got, not $2"
        failures=$((failures + 1))
    fi
}

# together WHAT WANT PATH…: the paths as one change.
together() {
    what=$1 want=$2
    shift 2
    expect "$what" "$want" "$(printf '%s\n' "$@")"
}

# each WHAT WANT PATH…: each path as a change of its own.
each() {
    what=$1 want=$2
    shift 2
    for path in "$@"; do expect "$what ($path)" "$want" "$path
"; done
}

expect "nothing changed" "- - -" ""
each "docs nobody's tests read" "- - -" docs/user-guide.md site/public/index.html AGENTS.md CLAUDE.md
each "the core's docs" "- - -" Core/docs/wire-protocol-v1.md Core/README.md Core/LICENSE
each "the core's code" "core mac -" Core/Sources/AllInOneIMECore/Composer.swift Core/Sources/AllInOneIMEWire/WireServer.swift
each "the core's scripts and resources" "core mac -" Core/Scripts/test.sh Core/Resources/Localizable.xcstrings \
    Core/Sources/AllInOneIMECore/Resources/RedactionWords.txt
expect "a test of the core's" "core - -" "Core/Tests/AllInOneIMECoreTests/PlainTests.swift
"
expect "a test of the core's that runs the input method" "core mac -" "Core/Tests/AllInOneIMECoreTests/AppTests.swift
"
expect "a test of the core's the hosted runner skips ($slow)" "core mac -" "Core/Tests/AllInOneIMECoreTests/SlowTests.swift
"
expect "a test of the core's deleted" "core mac -" "Core/Tests/AllInOneIMECoreTests/GoneTests.swift
"
each "what the shell's tests share" "core mac -" Core/Tests/AllInOneIMETestSupport/FakeEngine.swift \
    Core/Tests/HostScenarios/chromium-caret.hostcase
each "the scripts core-test runs too" "core mac -" Scripts/test-scope.sh Scripts/core-tests-with-app.sh \
    Scripts/check-split-paths.sh
each "the shell's code, tests, scripts and resources" "- mac -" Sources/AllInOneIME/CandidatePanel.swift \
    Sources/AllInOneIMEMac/FieldReading.swift Tests/AllInOneIMEMacTests/UpdateInstallTests.swift Scripts/swiftlint.sh \
    Scripts/test-scope-test.sh Resources/user-guide.md Resources/en.lproj/InfoPlist.strings
each "the files the shell's tests read" "- mac -" README.md README.zh-CN.md CHANGELOG.md CHANGELOG.zh-CN.md \
    THIRD_PARTY_NOTICES.md LICENSE
each "anything else" "core mac -" .github/workflows/quality.yml .swiftlint.yml changes/issue-12.md NewFolder/file.txt \
    docs-old/page.md
each "the updater, the installer and the apps' packaging" "- mac update" Sources/AllInOneIMEInstaller/Installer.swift \
    Sources/AllInOneIMEMac/UpdateInstall.swift Sources/AllInOneIME/Updates.swift Sources/AllInOneIME/main.swift \
    Sources/AllInOneIMEMac/AppBundles.swift Sources/AllInOneIMESettings/main.swift Scripts/test-update.sh \
    Scripts/build-update-manifest.swift Scripts/installed-input-method.sh Scripts/strip-rpaths.sh \
    Scripts/check-weak-links.sh Scripts/sign-identity.sh Scripts/profile-entitlements.sh Resources/Info.plist \
    Resources/Settings-Info.plist Resources/Installer-Info.plist Resources/AllInOneIME.entitlements \
    Resources/Signing/AllInOneIME-DeveloperID.provisionprofile
each "the core's updater and how the apps are built" "core mac update" Core/Sources/AllInOneIMECore/Update.swift \
    Core/Sources/AllInOneIMECore/AppVersion.swift Makefile Package.swift Package.resolved Core/Package.swift \
    Core/Package.resolved
together "docs, a test of the core's and the shell's code" "core mac -" docs/a.md \
    Core/Tests/AllInOneIMECoreTests/PlainTests.swift Sources/AllInOneIME/CandidatePanel.swift
together "docs and a test of the core's" "core - -" docs/a.md Core/Tests/AllInOneIMECoreTests/PlainTests.swift
together "docs and the installer" "- mac update" site/index.html Sources/AllInOneIMEInstaller/main.swift
expect "the last path without its line break" "- mac -" "docs/a.md
Sources/AllInOneIME/CandidatePanel.swift"

if [ "$failures" -gt 0 ]; then
    echo "test-scope-test: $failures of $checks failed (Scripts/test-scope.sh, or the table above, is wrong)" >&2
    exit 1
fi
echo "test-scope-test: all $checks passed"
