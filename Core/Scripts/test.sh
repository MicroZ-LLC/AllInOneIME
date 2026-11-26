#!/bin/sh
# The core's tests, offline, on macOS or Linux: `swift test` in this package, with the arguments given (`--filter`,
# `--skip`, `--skip-build`). The macOS shell's `make test-core` and its CI (quality.yml's core-test, on an export of
# this folder alone, on Linux and macOS) run them this way.
#   - No AWS files are read: a test whose settings pick Bedrock (the default provider) without stubbing the credentials
#     would otherwise send a real, billed request.
#   - Swift's plain global queues instead of its cooperative pool, which has one thread per core and adds none when one
#     waits: many tests wait on theirs (a session's work, a child process), and the rest stood still meanwhile. And at
#     most 32 tests at a time: those queues have 64 threads in all on macOS, and a test that waits holds one, so with
#     every test started at once the waiting ones held them all and the work they wait for (`FakeHost.settle`'s) had
#     none: on a loaded Mac, tests waiting 10 s for what takes milliseconds failed (the Makefile's TEST_THREADS).
#   - Off macOS, the acceptance tests of what only Apple's Foundation does are skipped, by name: requests byte for byte
#     as Apple's writes them (a Double with 17 digits, 0.69999999999999996, where Linux's writes 0.7; a header's name as
#     set, x-api-key, where Linux's capitalizes it: the same requests otherwise), settings compared with NSDictionary
#     (which on Linux tells equal values apart), the on-device model listed (`#available(macOS 26, *)` holds off Apple's
#     systems), the questions' file in ~/Library, iCloud's folder removed to the Trash (Linux has none: it's deleted).
#     What the platform lacks otherwise (date detection, Apple's on-device model, a C compiler, language packs) the
#     tests skip themselves. Run them as a user other than root: root reads whatever a file's mode says, and the tests
#     of what can't be read need it kept out.
#   - On a hosted CI runner (ALLINONEIME_CI_HOSTED=1: quality.yml's core-test (macOS)), the tests that bound what they
#     time to a fraction of a second, which such a runner misses even with the test run alone, are skipped by name
#     (hosted-runner-skips.txt; `make test-mac` runs them on the Mac mini), once `swift test list` shows the list names
#     those tests and no others (hosted-runner-skips.sh --check).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
if [ "$(uname -s)" != Darwin ]; then
    set -- --skip 's4_otherProvidersRequestsAreByteIdenticalToRelease063|prompt_existingPromptsByteIdentical|askingSendsTheSameRequestAsBefore|requestsUnchangedWhenOff|requestsUnchangedWhenOnAndNothingFound|itRoundTripsWithoutAddingUnsetKeys|s2_listedOnlyFromMacOS26|theFileIsUnderApplicationSupport|removeFromICloud' "$@"
fi
export AWS_CONFIG_FILE=/nonexistent/aws-config AWS_SHARED_CREDENTIALS_FILE=/nonexistent/aws-credentials
export SWIFT_DEBUG_CONCURRENCY_ENABLE_COOPERATIVE_QUEUES=0 SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=32
base=${TMPDIR:-/tmp}
run=$(mktemp -d "${base%/}/allinoneime-tests.XXXXXX")
trap 'rm -rf "$run"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ "${ALLINONEIME_CI_HOSTED:-}" = 1 ]; then
    built=""
    for arg in "$@"; do [ "$arg" = --skip-build ] && built=--skip-build; done
    hosted=$(TMPDIR="$run/" "$root/Scripts/hosted-runner-skips.sh" --check --package-path "$root" $built)
    echo "On a hosted runner: skipping the tests in Scripts/hosted-runner-skips.txt (mac-test runs them on the Mac mini)."
    set -- --skip "$hosted" "$@"
fi
status=0
TMPDIR="$run/" "$root/Scripts/retry-failed-tests.sh" swift test --package-path "$root" "$@" || status=$?
exit "$status"
