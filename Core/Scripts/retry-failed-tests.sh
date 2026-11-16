#!/bin/sh
# Runs `swift test …` (the command given), and when it fails on a few tests only, runs those again once, alone and one at
# a time: a test that then passes failed under load (a busy CI machine's timeouts: ProcessOutputTests, a child process
# past its limit, a panel's layout), not on the change. Each such test is named as a GitHub warning ("flaky: …") and
# added to $FLAKY_TESTS_FILE (and the job's summary on GitHub), so that it gets fixed rather than forgotten.
#   - Nothing is run again when the build fails, when the run didn't end (a crash: no results file, no "Test run with"
#     line), when more than $RETRY_LIMIT tests failed (default 15: that is a real break), or when a failed test's name
#     can't be found again in `swift test list`. The first run's status is then the result.
#   - The tests are found in Swift Testing's xUnit results (--xunit-output): a test's suite (`classname`, the module then
#     its types, "AllInOneIMECoreTests.Outer.Inner") and its function (`name`, "test(_:)"), which `swift test list` names
#     "AllInOneIMECoreTests.Outer/Inner/test(_:)" ("AllInOneIMECoreTests.test()" outside a type). A run with an XCTest
#     failure (none in this repository) isn't run again.
#   - The second run takes the first one's arguments without its --filter, plus --skip-build, --no-parallel and a filter
#     of exactly these tests; its own per-test timeouts are the tests' own.
# Usage: retry-failed-tests.sh swift test [--package-path P] [--filter F] [--skip S] …
set -u
limit=${RETRY_LIMIT:-15}
work=$(mktemp -d "${TMPDIR:-/tmp}/allinoneime-retry.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Runs a command, its output shown as it comes and kept in the file $1. Through a FIFO, not a pipe into `tee`: a pipe
# ends when every process holding it does, so a test's child left running (a `sleep 60` a timeout gave up on) kept the
# run waiting; here what's printed after the command ends has a moment to arrive, then the copy stops.
run_logged() {
    log=$1
    shift
    fifo="$work/output"
    rm -f "$fifo"
    mkfifo "$fifo" || return 1
    tee "$log" < "$fifo" &
    copier=$!
    "$@" > "$fifo" 2>&1
    code=$?
    waited=0
    while kill -0 "$copier" 2>/dev/null && [ "$waited" -lt 20 ]; do sleep 0.1; waited=$((waited + 1)); done
    kill "$copier" 2>/dev/null
    wait "$copier" 2>/dev/null
    rm -f "$fifo"
    return "$code"
}

# The first run.
status=0
run_logged "$work/first.log" "$@" --xunit-output "$work/first.xml" || status=$?
[ "$status" -eq 0 ] && exit 0

results="$work/first-swift-testing.xml"
give_up() { echo "retry-failed-tests: not run again: $1" >&2; exit "$status"; }
[ -s "$results" ] || give_up "no Swift Testing results (the build failed, or the run didn't end)"
grep -q "Test run with .* failed" "$work/first.log" || give_up "the run didn't end"
# XCTest's failures aren't in Swift Testing's results: one ("Executed 3 tests, with 1 failure") fails the run as it was.
grep -Eq "Executed [0-9]+ tests?, with [1-9][0-9]* failures?" "$work/first.log" && give_up "an XCTest test failed"

# The failed tests: "classname<TAB>name", once each.
awk '
    function attr(line, key,    s) {
        # " name=" and not the end of " classname=".
        if (!match(line, " " key "=\"[^\"]*\"")) return ""
        s = substr(line, RSTART + length(key) + 3, RLENGTH - length(key) - 4)
        gsub(/&quot;/, "\"", s); gsub(/&apos;/, "\047", s); gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&amp;/, "\\&", s)
        return s
    }
    /<testcase / { suite = attr($0, "classname"); test = attr($0, "name"); open = ($0 !~ /\/>[[:space:]]*$/); next }
    /<failure/ || /<error/ { if (open && !((suite, test) in seen)) { seen[suite, test] = 1; print suite "\t" test } }
    /<\/testcase>/ { open = 0 }
' "$results" > "$work/failed.tsv"
count=$(wc -l < "$work/failed.tsv" | tr -d ' ')
[ "$count" -gt 0 ] || give_up "no failed test in the results"
[ "$count" -le "$limit" ] || give_up "$count tests failed (more than $limit)"

# The first run's arguments without its --filter and --xunit-output, one per line, for the second run; its package path
# for `swift test list`.
skip_next=0
package=""
prev=""
: > "$work/args"
for arg in "$@"; do
    case $prev in --package-path) package=$arg ;; esac
    prev=$arg
    if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
    case $arg in
        --filter|--xunit-output) skip_next=1; continue ;;
        --filter=*|--xunit-output=*) continue ;;
        --package-path=*) package=${arg#--package-path=} ;;
    esac
    printf '%s\n' "$arg" >> "$work/args"
done

# Each failed test's id, as `swift test list` prints it, found there.
listed="$work/listed"
swift test list --skip-build ${package:+--package-path "$package"} > "$listed" 2>/dev/null || give_up "swift test list failed"

filter=""
: > "$work/ids"
while IFS="$(printf '\t')" read -r suite test; do
    module=${suite%%.*}
    if [ "$module" = "$suite" ]; then id="$module.$test"; else id="$module.$(printf '%s' "${suite#*.}" | tr . /)/$test"; fi
    grep -Fxq "$id" "$listed" || give_up "\"$id\" (from $suite $test) isn't in swift test list"
    printf '%s\n' "$id" >> "$work/ids"
    escaped=$(printf '%s' "$id" | sed 's/[][\\.*^$+?(){}|]/\\&/g')
    filter="${filter:+$filter|}^$escaped"
done < "$work/failed.tsv"

echo
echo "retry-failed-tests: $count failed; running them again, alone and one at a time:"
sed 's/^/  /' "$work/ids"
# The second run: the first's arguments (one per line in $work/args) without its filter, plus this one.
set --
while IFS= read -r arg; do set -- "$@" "$arg"; done < "$work/args"
second=0
run_logged "$work/second.log" "$@" --skip-build --no-parallel --filter "$filter" --xunit-output "$work/second.xml" || second=$?
ran=$(grep -c "<testcase " "$work/second-swift-testing.xml" 2>/dev/null) || true
ran=${ran:-0}
if [ "$second" -ne 0 ] || [ "$ran" -lt "$count" ]; then
    echo "retry-failed-tests: they failed again ($ran of $count run): a real failure" >&2
    exit "$status"
fi
while IFS= read -r id; do
    echo "::warning title=Flaky test::flaky: $id failed under load, passed alone"
    [ -n "${FLAKY_TESTS_FILE:-}" ] && printf '%s\n' "$id" >> "$FLAKY_TESTS_FILE"
    [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf -- '- flaky: `%s` failed under load, passed alone\n' "$id" >> "$GITHUB_STEP_SUMMARY"
done < "$work/ids"
echo "retry-failed-tests: all $count passed alone; counted as passed (named above as flaky)"
exit 0
