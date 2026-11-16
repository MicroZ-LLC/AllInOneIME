#!/bin/sh
# The core's tests, offline, on macOS or Linux: `swift test` in this package, with the arguments given (`--filter`,
# `--skip`, `--skip-build`). The macOS shell's `make test-core` and its CI (quality.yml's core-test, on an export of
# this folder alone, on Linux and macOS) run them this way.
#   - No AWS files are read: a test whose settings pick Bedrock (the default provider) without stubbing the credentials
#     would otherwise send a real, billed request.
#   - Swift's plain global queues instead of its cooperative pool, which has one thread per core and adds none when one
#     waits: many tests wait on theirs (a session's work, a child process), and the rest stood still meanwhile.
#   - Off macOS, the acceptance tests of what only Apple's Foundation does are skipped, by name: requests byte for byte
#     as Apple's writes them (a Double with 17 digits, 0.69999999999999996, where Linux's writes 0.7; a header's name as
#     set, x-api-key, where Linux's capitalizes it: the same requests otherwise), settings compared with NSDictionary
#     (which on Linux tells equal values apart), the on-device model listed (`#available(macOS 26, *)` holds off Apple's
#     systems), the questions' file in ~/Library, iCloud's folder removed to the Trash (Linux has none: it's deleted).
#     What the platform lacks otherwise (date detection, Apple's on-device model, a C compiler, language packs) the
#     tests skip themselves. Run them as a user other than root: root reads whatever a file's mode says, and the tests
#     of what can't be read need it kept out.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
if [ "$(uname -s)" != Darwin ]; then
    set -- --skip 's4_otherProvidersRequestsAreByteIdenticalToRelease063|prompt_existingPromptsByteIdentical|askingSendsTheSameRequestAsBefore|requestsUnchangedWhenOff|requestsUnchangedWhenOnAndNothingFound|itRoundTripsWithoutAddingUnsetKeys|s2_listedOnlyFromMacOS26|theFileIsUnderApplicationSupport|removeFromICloud' "$@"
fi
export AWS_CONFIG_FILE=/nonexistent/aws-config AWS_SHARED_CREDENTIALS_FILE=/nonexistent/aws-credentials
export SWIFT_DEBUG_CONCURRENCY_ENABLE_COOPERATIVE_QUEUES=0
base=${TMPDIR:-/tmp}
run=$(mktemp -d "${base%/}/allinoneime-tests.XXXXXX")
trap 'rm -rf "$run"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
status=0
TMPDIR="$run/" "$root/Scripts/retry-failed-tests.sh" swift test --package-path "$root" "$@" || status=$?
exit "$status"
