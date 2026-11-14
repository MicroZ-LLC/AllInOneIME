#!/bin/sh
# The size ratchet: keeps the shipped Swift files (Sources/ and Core/Sources/) from growing past what one person can
# review, without a rewrite first. A file's size is its lines of code: lines that aren't blank or only a comment (so
# explaining code never counts against it). A file may have at most LIMIT of them; the files over it today are listed
# in Scripts/oversized-files.txt with their size, and may not grow past it. A file that shrank is locked in at its new
# size with --update (the script says when); nothing here ever raises a number. With --base REF (CI: the PR's base) it
# also checks that the baselines themselves only went down: no listed file's number raised, no more files or lines
# listed in all, and no SwiftLint violation in .swiftlint.baseline.json that REF's lacks (a moved file is fine).
# Run by `make lint` (`make lint LINT_BASE=REF` passes --base).
#
#   Scripts/check-ratchet.sh              check
#   Scripts/check-ratchet.sh --update     lower the numbers of files that shrank, drop those back under LIMIT
#   Scripts/check-ratchet.sh --base REF   check, and that the baselines didn't grow since REF (a git commit or branch)
#   Scripts/check-ratchet.sh --report     "PATH RECORDED NOW" for each listed file (the weekly health report)
set -eu
LIMIT=400
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
list=Scripts/oversized-files.txt
skip='Core/Sources/AllInOneIMECore/RedactionWordList.swift'   # generated (make redaction-words), not written

mode=${1:-check}
case $mode in
check | --update | --report) ;;
--base) [ $# -eq 2 ] || { echo "usage: $0 --base REF" >&2; exit 2; } ;;
*) echo "usage: $0 [--update | --base REF | --report]" >&2; exit 2 ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# "SIZE PATH" for every file in scope, by lines of code.
find Sources Core/Sources -name '*.swift' -type f | LC_ALL=C sort | while IFS= read -r file; do
    [ "$file" = "$skip" ] && continue
    awk -v file="$file" '
        { line = $0; sub(/^[ \t]+/, "", line) }
        block { if (index(line, "*/")) block = 0; next }
        line == "" || line ~ /^\/\// { next }
        line ~ /^\/\*/ { if (!index(substr(line, 3), "*/")) block = 1; next }
        { n++ }
        END { print n + 0, file }' "$file"
done >"$tmp/now"

# A list's "SIZE PATH" lines, without its comments.
entries() { grep -v -e '^#' -e '^[[:space:]]*$' "$1" || true; }
entries "$list" >"$tmp/listed"

if [ "$mode" = --report ]; then
    awk 'NR == FNR { now[$2] = $1; next } { print $2, $1, ($2 in now) ? now[$2] : "gone" }' "$tmp/now" "$tmp/listed"
    exit 0
fi

# Today's sizes against the list: "fail MESSAGE" for each file over its number, "keep SIZE PATH" for each file still
# over the limit (its new number), and "shrank" if any number can go down or any line can go.
awk -v limit="$LIMIT" -v list="$list" -v listed="$tmp/listed" '
    BEGIN { while ((getline entry < listed) > 0) { split(entry, f, " "); allowed[f[2]] = f[1] } }
    {
        size = $1; path = $2; seen[path] = 1
        if (path in allowed) {
            if (size > allowed[path])
                printf "fail %s grew to %d lines of code, past its %d (it is over the limit, %d): make it smaller\n", path, size, allowed[path], limit
            else {
                if (size > limit) print "keep", size, path
                if (size < allowed[path] || size <= limit) shrank = 1
            }
        } else if (size > limit)
            printf "fail %s has %d lines of code, over the limit (%d): split it (only renamed it? rename it in %s)\n", path, size, limit, list
    }
    END { for (path in allowed) if (!(path in seen)) shrank = 1; if (shrank) print "shrank" }' "$tmp/now" >"$tmp/result"
sed -n 's/^fail //p' "$tmp/result" >"$tmp/failures"

if [ "$mode" = --update ]; then
    if [ -s "$tmp/failures" ]; then
        sed 's/^/check-ratchet: /' "$tmp/failures" >&2
        echo "check-ratchet: fix these first: --update only lowers numbers" >&2
        exit 1
    fi
    { grep '^#' "$list"; sed -n 's/^keep //p' "$tmp/result" | LC_ALL=C sort -k2; } >"$tmp/new"
    cp "$tmp/new" "$list"
    echo "check-ratchet: $list updated: $(entries "$list" | wc -l | tr -d ' ') files over $LIMIT lines of code"
    exit 0
fi

status=0
if [ -s "$tmp/failures" ]; then
    sed 's/^/check-ratchet: /' "$tmp/failures" >&2
    status=1
fi

if [ "$mode" = --base ]; then
    base=$2
    if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
        echo "check-ratchet: no commit $base to compare the baselines with" >&2
        exit 2
    fi
    # A base from before the ratchet has no baselines: nothing to compare.
    git show "$base:$list" >"$tmp/was.txt" 2>/dev/null || cp "$list" "$tmp/was.txt"
    entries "$tmp/was.txt" >"$tmp/was"
    awk '
        NR == FNR { was[$2] = $1; files0++; lines0 += $1; next }
        { files1++; lines1 += $1; if (($2 in was) && $1 > was[$2]) printf "  %s: %d, was %d\n", $2, $1, was[$2] }
        END { if (files1 > files0) printf "  %d files listed, were %d\n", files1, files0
              if (lines1 > lines0) printf "  %d lines listed in all, were %d\n", lines1, lines0 }' \
        "$tmp/was" "$tmp/listed" >"$tmp/raised"
    if [ -s "$tmp/raised" ]; then
        echo "check-ratchet: $list went up since $base:" >&2
        cat "$tmp/raised" >&2
        status=1
    fi
    git show "$base:.swiftlint.baseline.json" >"$tmp/lint" 2>/dev/null || cp .swiftlint.baseline.json "$tmp/lint"
    python3 - "$tmp/lint" .swiftlint.baseline.json >"$tmp/added" <<'EOF'
import collections, json, sys
# A violation is its rule and its line's text: its file and line number may change (the file moved, code above it).
count = lambda path: collections.Counter((e["violation"]["ruleIdentifier"], e["text"]) for e in json.load(open(path)))
old, new = count(sys.argv[1]), count(sys.argv[2])
for (rule, text), n in sorted(new.items()):
    if n > old[(rule, text)]:
        print(f"  {rule}: {text.strip()[:100]}")
EOF
    if [ -s "$tmp/added" ]; then
        echo "check-ratchet: .swiftlint.baseline.json has violations $base's lacks; fix them instead:" >&2
        cat "$tmp/added" >&2
        status=1
    fi
fi

[ $status -eq 0 ] || exit 1
if grep -q '^shrank$' "$tmp/result"; then
    echo "check-ratchet: files shrank or went under the limit; lock that in: Scripts/check-ratchet.sh --update"
fi
echo "check-ratchet: no file grew ($(wc -l <"$tmp/listed" | tr -d ' ') listed over $LIMIT lines of code)"
