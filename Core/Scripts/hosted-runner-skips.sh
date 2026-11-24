#!/bin/sh
# The tests GitHub's hosted runner is too slow for (hosted-runner-skips.txt, beside this script, says which and why):
# Core/Scripts/test.sh skips them there (ALLINONEIME_CI_HOSTED=1) and `make test-mac` runs them on the Mac mini.
#   hosted-runner-skips.sh               one regular expression of them all, for `swift test --skip` or `--filter`: each
#                                        id escaped and anchored at its start, as retry-failed-tests.sh writes them
#   hosted-runner-skips.sh --check [A…]  the same, once `swift test list A…` (--package-path P, --skip-build) shows that
#                                        it picks exactly these tests: none missing (renamed or removed, its line would
#                                        skip nothing, and a renamed one would fail on the hosted runner again) and
#                                        none other (skipped there, and run on the Mac only by chance); fails otherwise
#   hosted-runner-skips.sh --functions   their functions' names, one a line (Scripts/test-scope.sh: a change to a file
#                                        that declares one runs mac-test)
set -eu
list=$(cd "$(dirname "$0")" && pwd)/hosted-runner-skips.txt
ids=$(grep -v -e '^#' -e '^[[:space:]]*$' "$list") || { echo "hosted-runner-skips: no test in $list" >&2; exit 1; }

case ${1:-} in
--functions)
    printf '%s\n' "$ids" | sed -e 's|.*/||' -e 's|(.*||' | sort -u
    exit 0 ;;
esac

regex=$(printf '%s\n' "$ids" | sed -e 's/[][\\.*^$+?(){}|]/\\&/g' -e 's/^/^/' | paste -sd'|' -)

if [ "${1:-}" = --check ]; then
    shift
    # Its output, a build's lines among the tests' ids, is shown only when it fails.
    listed=$(swift test list "$@") || {
        printf '%s\n' "$listed" >&2
        echo "hosted-runner-skips: swift test list failed" >&2
        exit 1
    }
    missing=$(printf '%s\n' "$ids" | while IFS= read -r id; do
        printf '%s\n' "$listed" | grep -Fxq -- "$id" || printf '  %s\n' "$id"
    done)
    others=$(printf '%s\n' "$listed" | grep -E -- "$regex" | grep -Fxv -- "$ids" | sed 's/^/  /' || true)
    if [ -n "$missing" ] || [ -n "$others" ]; then
        [ -z "$missing" ] || printf 'hosted-runner-skips: not in swift test list (renamed or removed? update %s):\n%s\n' \
            "$list" "$missing" >&2
        [ -z "$others" ] || printf 'hosted-runner-skips: also picked, though not listed:\n%s\n' "$others" >&2
        exit 1
    fi
fi
echo "$regex"
