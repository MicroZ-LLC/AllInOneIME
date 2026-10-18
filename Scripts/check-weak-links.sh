#!/bin/sh
# Fails unless each Mach-O executable given links FoundationModels (Apple's on-device model, macOS 26) weakly: under
# LC_LOAD_WEAK_DYLIB, never LC_LOAD_DYLIB, in every architecture. A strong link and the app doesn't start on macOS 14
# or 15. Package.swift passes -weak_framework to everything that links the core, and the core imports it
# @_weakLinked; this checks what the linker made of them.
# Usage: Scripts/check-weak-links.sh EXECUTABLE...   (run by make app, make installer-app and make cli)
set -eu
[ $# -gt 0 ] || { echo "usage: $0 EXECUTABLE..." >&2; exit 2; }
status=0
for binary in "$@"; do
    # Run here, not in a pipeline, so a failing otool stops the script.
    commands=$(otool -l -arch all "$binary")
    # The load command of each FoundationModels entry, one a line (one per architecture).
    loads=$(printf '%s\n' "$commands" | awk '
        $1 == "cmd" { cmd = $2 }
        $1 == "name" && $2 ~ /\/FoundationModels\.framework\// { print cmd }')
    if [ -z "$loads" ]; then
        echo "check-weak-links: $binary doesn't link FoundationModels at all" >&2
        status=1
    elif printf '%s\n' "$loads" | grep -qv '^LC_LOAD_WEAK_DYLIB$'; then
        echo "check-weak-links: $binary links FoundationModels strongly ($(printf '%s\n' "$loads" | sort -u | tr '\n' ' '))" >&2
        status=1
    fi
done
exit $status
