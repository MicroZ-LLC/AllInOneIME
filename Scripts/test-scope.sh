#!/bin/sh
# Which of the quality gate's test jobs a change needs (quality.yml's `changes` job): reads the paths it changed, one a
# line, from a checkout of it, and prints `core=true|false` and `mac=true|false` for $GITHUB_OUTPUT. core: the core's
# tests (`make test-core`, core-test on GitHub's machines); mac: the macOS shell's (`make test-mac`, mac-test on the Mac
# mini), which builds on the core. A path counts for
#   - neither: the docs nobody's tests read (docs/, site/, AGENTS.md, CLAUDE.md) and the core's (Core/docs/, Core/'s
#     own Markdown files and LICENSE);
#   - core: the core's tests (Core/Tests/), but for what the shell's tests use too (AllInOneIMETestSupport, the host
#     scenarios its replayer plays: HostScenarios) and a file of tests that runs the input method (it names PlugLangCLI: Scripts/core-tests-with-app.sh), or one deleted (it
#     may have), which count for both;
#   - mac: Sources/, Tests/, Scripts/ and Resources/, and the files the shell's tests read (README.md, CHANGELOG.md and
#     their translations, THIRD_PARTY_NOTICES.md, LICENSE);
#   - both: the rest of Core/, the scripts core-test runs too, and anything else (.github/, the Package files, the
#     Makefile, a new folder).
# A push to mainline or a release branch, or a run with no base to compare with, runs both without asking this.
#
#   git diff --name-only --no-renames origin/<base>...HEAD | Scripts/test-scope.sh
set -eu
core=false mac=false
while IFS= read -r path || [ -n "$path" ]; do
    case $path in
    '' | docs/* | site/* | AGENTS.md | CLAUDE.md | Core/docs/*) ;;
    Core/Tests/AllInOneIMETestSupport/* | Core/Tests/HostScenarios/*) core=true mac=true ;;
    Core/Tests/*)
        core=true
        if [ ! -f "$path" ] || grep -q PlugLangCLI "$path"; then mac=true; fi ;;
    Core/*/*) core=true mac=true ;;
    Core/*.md | Core/LICENSE) ;;
    Scripts/test-scope.sh | Scripts/core-tests-with-app.sh | Scripts/check-split-paths.sh) core=true mac=true ;;
    Sources/* | Tests/* | Scripts/* | Resources/*) mac=true ;;
    README.md | README.*.md | CHANGELOG.md | CHANGELOG.*.md | THIRD_PARTY_NOTICES.md | LICENSE) mac=true ;;
    *) core=true mac=true ;;
    esac
done
echo "core=$core"
echo "mac=$mac"
