#!/bin/sh
# Which of the quality gate's test jobs a change needs (quality.yml's `changes` job): reads the paths it changed, one a
# line, from a checkout of it, and prints `core=true|false`, `mac=true|false` and `update=true|false` for
# $GITHUB_OUTPUT. core: the core's tests (`make test-core`, core-test on GitHub's machines); mac: the macOS shell's
# (`make test-mac`, mac-test on the Mac mini), which builds on the core; update: the updater's end-to-end test too
# (`make update-test`, Scripts/test-update.sh, in mac-test). A path counts for
#   - neither: the docs nobody's tests read (docs/, site/, AGENTS.md, CLAUDE.md) and the core's (Core/docs/, Core/'s
#     own Markdown files and LICENSE);
#   - core: the core's tests (Core/Tests/), but for what the shell's tests use too (AllInOneIMETestSupport, the host
#     scenarios its replayer plays: HostScenarios) and a file of tests that runs the input method (it names
#     PlugLangCLI: Scripts/core-tests-with-app.sh), or one deleted (it may have), which count for both; so does a file
#     that declares a test GitHub's hosted runner is too slow for (Core/Scripts/hosted-runner-skips.txt): core-test
#     skips it there and mac-test runs it;
#   - mac: Sources/, Tests/, Scripts/ and Resources/, and the files the shell's tests read (README.md, CHANGELOG.md and
#     their translations, THIRD_PARTY_NOTICES.md, LICENSE);
#   - both: the rest of Core/, the scripts core-test runs too, and anything else (.github/, the Package files, the
#     Makefile, a new folder).
# And for update (with mac): what the updater's test runs (the updater's code, the input method's command line that
# starts it, the apps' code-signature checks and bundle swap, the version, the Settings app it updates too, the
# installer, the update manifest's tool) and what makes and signs the apps it updates (the Makefile, the Package files,
# the scripts `make app` runs, the apps' Info.plist files, entitlements and provisioning profile).
# A push to mainline or a release branch, or a run with no base to compare with, runs both without asking this (and the
# updater's test on a release branch).
#
#   git diff --name-only --no-renames origin/<base>...HEAD | Scripts/test-scope.sh
#
# Scripts/test-scope-test.sh, part of `make lint`, checks it against a table of paths.
set -eu
core=false mac=false update=false
# The declarations of the tests only mac-test runs on a pull request: "func name(".
hosted="func ($("$(dirname "$0")/../Core/Scripts/hosted-runner-skips.sh" --functions | paste -sd'|' -))\\("
while IFS= read -r path || [ -n "$path" ]; do
    case $path in
    '' | docs/* | site/* | AGENTS.md | CLAUDE.md | Core/docs/*) ;;
    Core/Tests/AllInOneIMETestSupport/* | Core/Tests/HostScenarios/*) core=true mac=true ;;
    Core/Tests/*)
        core=true
        if [ ! -f "$path" ] || grep -q PlugLangCLI "$path" || grep -Eq "$hosted" "$path"; then mac=true; fi ;;
    Core/*/*) core=true mac=true ;;
    Core/*.md | Core/LICENSE) ;;
    Scripts/test-scope.sh | Scripts/core-tests-with-app.sh | Scripts/check-split-paths.sh) core=true mac=true ;;
    Sources/* | Tests/* | Scripts/* | Resources/*) mac=true ;;
    README.md | README.*.md | CHANGELOG.md | CHANGELOG.*.md | THIRD_PARTY_NOTICES.md | LICENSE) mac=true ;;
    *) core=true mac=true ;;
    esac
    case $path in
    Sources/AllInOneIMEInstaller/* | Sources/*/Update*.swift | Core/Sources/AllInOneIMECore/Update*.swift \
        | Sources/AllInOneIME/main.swift | Sources/AllInOneIMEMac/AppBundles.swift | Sources/AllInOneIMESettings/* \
        | Core/Sources/AllInOneIMECore/AppVersion.swift \
        | Scripts/test-update.sh | Scripts/build-update-manifest.swift | Scripts/installed-input-method.sh \
        | Scripts/strip-rpaths.sh | Scripts/check-weak-links.sh | Scripts/sign-identity.sh | Scripts/profile-entitlements.sh \
        | Makefile | Package.swift | Package.resolved | Core/Package.swift | Core/Package.resolved \
        | Resources/*Info.plist | Resources/*.entitlements | Resources/Signing/*) update=true mac=true ;;
    esac
done
echo "core=$core"
echo "mac=$mac"
echo "update=$update"
