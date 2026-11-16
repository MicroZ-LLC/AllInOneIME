#!/bin/sh
# Removes what test runs left in TMPDIR more than 6 hours ago, on the Mac mini's CI runner (quality.yml's mac-test runs
# it first), where a run killed midway can't clean up after itself (Scripts/test-tmpdir.sh) and older runs left one
# folder per test. Only names the tests make: a run's own folder (allinoneime-tests.*), and a name that starts with a
# prefix the tests give FileManager's temporary directory, then -, _ or ., with a UUID in it. Nothing outside TMPDIR,
# nothing younger than 6 hours (a run going on), never Kiro's, Apple's or Swift's own (kiro*, com.apple*,
# swift-generated-sources*). `--dry-run` lists instead of removing.
set -eu
cd "$(dirname "$0")/.."
dir=${TMPDIR:-/tmp}
dry=${1:-}
prefixes=$(grep -rhoE '(temporaryDirectory|NSTemporaryDirectory\(\))[^"]{0,80}"[A-Za-z][A-Za-z0-9._-]{3,}' \
        Core/Tests Tests 2>/dev/null |
    grep -oE '"[A-Za-z][A-Za-z0-9._-]+$' | tr -d '"' | sed -E 's/[-_.]+$//' |
    grep -viE '^(kiro|com\.apple|swift-generated-sources)' | sort -u)
uuid='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
find "$dir" -mindepth 1 -maxdepth 1 -mmin +360 2>/dev/null | while IFS= read -r path; do
    name=$(basename "$path")
    match=no
    case "$name" in
        allinoneime-tests.*) match=yes ;;
        kiro*|com.apple*|swift-generated-sources*) continue ;;
        *)
            printf '%s\n' "$name" | grep -qE "$uuid" || continue
            for prefix in $prefixes; do
                case "$name" in "$prefix"-*|"$prefix"_*|"$prefix".*) match=yes; break ;; esac
            done
            ;;
    esac
    [ "$match" = yes ] || continue
    if [ "$dry" = --dry-run ]; then echo "$path"; else rm -rf "$path"; fi
done
