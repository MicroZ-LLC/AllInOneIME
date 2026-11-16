#!/bin/sh
# Offline test of retry-failed-tests.sh, with a fake `swift` that prints fixed results: a test that fails once then
# passes is run again alone and counts as passed; one that fails again, a build error, a crash, too many failures, a
# name `swift test list` doesn't know and an XCTest failure each keep the first run's failure. `make test-core` runs it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/allinoneime-retry-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"

# The fake: `swift test list` prints $FAKE/list; `swift test … --xunit-output P` is run N (counted in $FAKE/runs), which
# writes $FAKE/runN.xml to P-swift-testing.xml when there is one, prints $FAKE/runN.log, keeps its arguments in
# $FAKE/runN.args and exits with $FAKE/runN.rc.
cat > "$work/bin/swift" <<'FAKE'
#!/bin/sh
if [ "$1 $2" = "test list" ]; then cat "$FAKE/list"; exit 0; fi
n=$(( $(cat "$FAKE/runs" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE/runs"
printf '%s\n' "$@" > "$FAKE/run$n.args"
xunit=""
prev=""
for arg in "$@"; do [ "$prev" = --xunit-output ] && xunit=$arg; prev=$arg; done
[ -f "$FAKE/run$n.xml" ] && [ -n "$xunit" ] && cp "$FAKE/run$n.xml" "${xunit%.xml}-swift-testing.xml"
[ -f "$FAKE/run$n.log" ] && cat "$FAKE/run$n.log"
exit "$(cat "$FAKE/run$n.rc" 2>/dev/null || echo 0)"
FAKE
chmod +x "$work/bin/swift"

failures=0
# case NAME EXPECTED_STATUS EXPECTED_RUNS [VAR=VALUE …]: runs the script in $FAKE (set up before) and checks its status
# and how many times `swift test` ran.
check() {
    name=$1 expected=$2 runs=$3
    shift 3
    status=0
    env PATH="$work/bin:$PATH" FAKE="$FAKE" GITHUB_STEP_SUMMARY= FLAKY_TESTS_FILE="$FAKE/flaky" "$@" \
        "$here/retry-failed-tests.sh" swift test --package-path /p --filter Original --skip Skipped > "$FAKE/out" 2>&1 \
        || status=$?
    ran=$(cat "$FAKE/runs" 2>/dev/null || echo 0)
    if [ "$status" -ne "$expected" ] || [ "$ran" -ne "$runs" ]; then
        echo "✘ $name: status $status (expected $expected), swift test ran $ran times (expected $runs)"
        sed 's/^/    /' "$FAKE/out"
        failures=$((failures + 1))
    else
        echo "✔ $name"
    fi
}
setup() {
    FAKE="$work/$1"
    mkdir "$FAKE"
    printf '%s\n' 'Mod.Suite/a()' 'Mod.Suite/Inner/b(_:)' 'Mod.c()' 'Mod.Suite/passes()' > "$FAKE/list"
}
xml() {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuites>\n  <testsuite name="TestResults">\n'
    for test in "$@"; do
        case $test in
            fail:*) set -- "${test#fail:}"; printf '    <testcase classname="%s" name="%s" time="1" >\n      <failure message="x" />\n    </testcase>\n' "${1%%|*}" "${1#*|}" ;;
            pass:*) set -- "${test#pass:}"; printf '    <testcase classname="%s" name="%s" time="1" />\n' "${1%%|*}" "${1#*|}" ;;
        esac
    done
    printf '  </testsuite>\n</testsuites>\n'
}
ended="✘ Test run with 4 tests in 2 suites failed after 1 seconds with 3 issues."

setup flaky
xml 'fail:Mod.Suite|a()' 'fail:Mod.Suite.Inner|b(_:)' 'fail:Mod|c()' 'pass:Mod.Suite|passes()' > "$FAKE/run1.xml"
echo "$ended" > "$FAKE/run1.log"; echo 1 > "$FAKE/run1.rc"
xml 'pass:Mod.Suite|a()' 'pass:Mod.Suite.Inner|b(_:)' 'pass:Mod|c()' > "$FAKE/run2.xml"; echo 0 > "$FAKE/run2.rc"
check "failed once, passed alone: passes, named as flaky" 0 2
grep -qx -- '--no-parallel' "$FAKE/run2.args" && grep -qx -- '--skip-build' "$FAKE/run2.args" \
    && grep -Fqx -- '^Mod\.Suite/a\(\)|^Mod\.Suite/Inner/b\(_:\)|^Mod\.c\(\)' "$FAKE/run2.args" \
    && ! grep -Fqx Original "$FAKE/run2.args" && grep -Fqx Skipped "$FAKE/run2.args" && grep -Fqx /p "$FAKE/run2.args" \
    || { echo "✘ the second run's arguments:"; sed 's/^/    /' "$FAKE/run2.args"; failures=$((failures + 1)); }
[ "$(cat "$FAKE/flaky")" = "$(printf 'Mod.Suite/a()\nMod.Suite/Inner/b(_:)\nMod.c()')" ] && grep -q '::warning' "$FAKE/out" \
    || { echo "✘ the flaky tests weren't named"; failures=$((failures + 1)); }

setup real
xml 'fail:Mod.Suite|a()' > "$FAKE/run1.xml"; echo "$ended" > "$FAKE/run1.log"; echo 1 > "$FAKE/run1.rc"
xml 'fail:Mod.Suite|a()' > "$FAKE/run2.xml"; echo 1 > "$FAKE/run2.rc"
check "failed again alone: fails" 1 2

setup build
echo "error: compile failed" > "$FAKE/run1.log"; echo 1 > "$FAKE/run1.rc"
check "build error: not run again" 1 1

setup crash
xml 'fail:Mod.Suite|a()' > "$FAKE/run1.xml"; echo "◇ Test a() started." > "$FAKE/run1.log"; echo 1 > "$FAKE/run1.rc"
check "crash (no end of run): not run again" 1 1

setup many
xml 'fail:Mod.Suite|a()' 'fail:Mod|c()' > "$FAKE/run1.xml"; echo "$ended" > "$FAKE/run1.log"; echo 1 > "$FAKE/run1.rc"
check "more failures than the limit: not run again" 1 1 RETRY_LIMIT=1

setup unknown
xml 'fail:Mod.Other|z()' > "$FAKE/run1.xml"; echo "$ended" > "$FAKE/run1.log"; echo 1 > "$FAKE/run1.rc"
check "a name swift test list doesn't know: not run again" 1 1

setup xctest
xml 'fail:Mod.Suite|a()' > "$FAKE/run1.xml"; printf '%s\nExecuted 3 tests, with 1 failure\n' "$ended" > "$FAKE/run1.log"
echo 1 > "$FAKE/run1.rc"
check "an XCTest failure: not run again" 1 1

setup passes
echo 0 > "$FAKE/run1.rc"
check "passing: run once" 0 1

[ "$failures" -eq 0 ] || { echo "retry-failed-tests-test: $failures failed"; exit 1; }
echo "retry-failed-tests-test: all passed"
