#!/bin/sh
# Keeps Sources/AllInOneIMECore platform-neutral: fails when a core file imports an Apple-only module
# outside `#if canImport(...)`. The files that still do are listed in Scripts/core-portable-allowlist.txt
# ("File.swift module"). That list only shrinks: a new import fails, and so does an entry that's no
# longer needed (remove it from the list).
#
#   Scripts/check-core-portable.sh            check (run by `make test`)
#   Scripts/check-core-portable.sh --list     print today's offenders, in the list's format
set -eu
export LC_ALL=C

cd "$(dirname "$0")/.."
CORE=Sources/AllInOneIMECore
ALLOWLIST=Scripts/core-portable-allowlist.txt
MODULES='AppKit|Carbon|Security|JavaScriptCore|FoundationModels|NaturalLanguage|PDFKit|os|CoreGraphics|CryptoKit|EventKit|InputMethodKit|SwiftUI|Combine'

# "File.swift module" for each unguarded import. An import is guarded inside the first branch of an
# `#if canImport(...)` or an `#elseif canImport(...)`; multi-line string literals (""") are skipped.
offenders() {
    for file in "$CORE"/*.swift; do
        awk -v name="$(basename "$file")" -v modules="^($MODULES)$" '
            {
                line = $0
                quotes = gsub(/"""/, "&", line)
                if (inString) { if (quotes % 2 == 1) inString = 0; next }
                if (quotes % 2 == 1) { inString = 1; next }
            }
            /^[ \t]*#if[ \t(]/     { depth++; guard[depth] = ($0 ~ /canImport[ \t]*\(/); next }
            /^[ \t]*#elseif[ \t(]/ { guard[depth] = ($0 ~ /canImport[ \t]*\(/); next }
            /^[ \t]*#else/         { guard[depth] = 0; next }
            /^[ \t]*#endif/        { if (depth > 0) depth--; next }
            /^[ \t]*(@[A-Za-z_]+[ \t]+)*import[ \t]/ {
                guarded = 0
                for (i = 1; i <= depth; i++) if (guard[i]) guarded = 1
                if (guarded) next
                sub(/^[ \t]*(@[A-Za-z_]+[ \t]+)*import[ \t]+/, "")
                sub(/^(typealias|struct|class|enum|protocol|let|var|func)[ \t]+/, "")
                module = $0
                sub(/[ \t.;\/].*$/, "", module)
                if (module ~ modules) print name " " module
            }
        ' "$file"
    done | sort -u
}

if [ "${1:-}" = "--list" ]; then
    offenders
    exit 0
fi

found=$(mktemp)
allowed=$(mktemp)
trap 'rm -f "$found" "$allowed"' EXIT
offenders > "$found"
grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$ALLOWLIST" | sed 's/[[:space:]][[:space:]]*/ /g; s/ $//' | sort -u > "$allowed"

status=0
new=$(comm -23 "$found" "$allowed")
if [ -n "$new" ]; then
    echo "error: Apple-only imports in $CORE (guard them with #if canImport(...), or keep them out of the core):" >&2
    echo "$new" | sed 's/^/  /' >&2
    status=1
fi
stale=$(comm -13 "$found" "$allowed")
if [ -n "$stale" ]; then
    echo "error: $ALLOWLIST lists imports that are gone; remove these lines:" >&2
    echo "$stale" | sed 's/^/  /' >&2
    status=1
fi
[ $status -eq 0 ] && echo "core-portable: $(wc -l < "$found" | tr -d ' ') allowlisted Apple-only imports, no new ones"
exit $status
