#!/bin/sh
# Keeps Sources/AllInOneIMECore (all of it, subfolders too) platform-neutral. It fails when
#   - a core file imports an Apple-only module anywhere but Sources/AllInOneIMECore/Platform/Apple/, guarded or not;
#   - a file in Platform/Apple/ imports one outside `#if canImport(...)`, or isn't wholly inside one: its first line of
#     code is the `#if canImport(...)`, its last the `#endif`;
#   - a core file starts a program itself (`Process(`, `posix_spawn`) instead of through the ProcessLauncher (only
#     Platform/FoundationProcessLauncher.swift does).
#
#   Scripts/check-core-portable.sh            check (run by `make test`)
#   Scripts/check-core-portable.sh --list     print every offence, one a line
set -eu
export LC_ALL=C

cd "$(dirname "$0")/.."
CORE=Sources/AllInOneIMECore
APPLE=$CORE/Platform/Apple
LAUNCHERS="$CORE/Platform/FoundationProcessLauncher.swift"
MODULES='AppKit|Carbon|Security|JavaScriptCore|FoundationModels|NaturalLanguage|PDFKit|os|CoreGraphics|CryptoKit|EventKit|InputMethodKit|SwiftUI|Combine|AVFoundation|Speech|Contacts|CoreServices|ApplicationServices|UIKit|WebKit|IOKit'

# "path: import Module (why)" for each Apple-only import that isn't allowed. An import is guarded inside the first
# branch of an `#if canImport(...)` or an `#elseif canImport(...)`; multi-line string literals (""") are skipped.
imports() {
    find "$CORE" -name '*.swift' | sort | while read -r file; do
        case "$file" in "$APPLE"/*) apple=1 ;; *) apple=0 ;; esac
        awk -v path="$file" -v apple="$apple" -v modules="^($MODULES)$" '
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
                sub(/^[ \t]*(@[A-Za-z_]+[ \t]+)*import[ \t]+/, "")
                sub(/^(typealias|struct|class|enum|protocol|let|var|func)[ \t]+/, "")
                module = $0
                sub(/[ \t.;\/].*$/, "", module)
                if (module !~ modules) next
                if (!apple) print path ": import " module " (Apple modules belong in Platform/Apple/)"
                else if (!guarded) print path ": import " module " (outside #if canImport)"
            }
        ' "$file"
    done
}

# Each Platform/Apple/ file is wholly inside one `#if canImport(...)`: its first line of code opens it, its last closes it.
wholly_guarded() {
    find "$APPLE" -name '*.swift' 2>/dev/null | sort | while read -r file; do
        code=$(grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*//' "$file" || true)
        first=$(printf '%s\n' "$code" | head -n 1)
        last=$(printf '%s\n' "$code" | tail -n 1)
        case "$first" in "#if canImport("*) ;; *) echo "$file: not wholly inside #if canImport(...) (first line: $first)" ;; esac
        case "$last" in "#endif"*) ;; *) echo "$file: not wholly inside #if canImport(...) (last line: $last)" ;; esac
    done
}

# Programs started anywhere but the ProcessLauncher implementation (comments aside).
processes() {
    find "$CORE" -name '*.swift' | sort | while read -r file; do
        case " $LAUNCHERS " in *" $file "*) continue ;; esac
        grep -n -E '(^|[^A-Za-z0-9_])(Process\(|posix_spawn)' "$file" | grep -v -E '^[0-9]+:[[:space:]]*//' \
            | sed "s|^\([0-9]*\):.*|$file:\1: starts a program (use Platform.current.processes, a ProcessLauncher)|" || true
    done
}

found=$( { imports; wholly_guarded; processes; } )
if [ "${1:-}" = "--list" ]; then
    [ -n "$found" ] && echo "$found"
    exit 0
fi
if [ -n "$found" ]; then
    echo "error: $CORE isn't platform-neutral:" >&2
    echo "$found" | sed 's/^/  /' >&2
    exit 1
fi
echo "core-portable: no Apple-only import outside Platform/Apple/ (each guarded), no program started outside the ProcessLauncher"
