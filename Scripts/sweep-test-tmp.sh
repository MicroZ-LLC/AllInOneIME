#!/bin/sh
# Removes what test runs left in TMPDIR more than 6 hours ago, on the Mac mini's CI runner (quality.yml's mac-test runs
# it first), where a run killed midway can't clean up after itself (Scripts/test-tmpdir.sh) and older runs left one
# folder per test. Only names the tests make: a run's own folder (allinoneime-tests.*), and a name that is a prefix the
# tests give FileManager's temporary directory, then -, _ or ., a UUID, and an extension at most. Nothing outside TMPDIR,
# nothing younger than 6 hours (a run going on), never Kiro's, Apple's or Swift's own (kiro*, com.apple*,
# swift-generated-sources*). `--dry-run` lists instead of removing.
set -eu
cd "$(dirname "$0")/.."
dir=${TMPDIR:-/tmp}
dry=${1:-}
# The prefixes the tests name: in FileManager's temporary directory directly or through TestScratch; SourceCompiler's
# and the wire server's test mode by name (their calls span two lines). Not the app's own (Sources, Core/Sources).
prefixes=$( { grep -rhoE '(temporaryDirectory|NSTemporaryDirectory\(\))[^"]{0,80}"[A-Za-z][A-Za-z0-9._-]{3,}' \
        Core/Tests Tests 2>/dev/null
    grep -rhoE 'TestScratch\.temporary\("[A-Za-z][A-Za-z0-9._-]{3,}' Core/Tests Tests 2>/dev/null
    echo '"source-compiler-'; echo '"allinoneime-wire-settings-'; } |
    grep -oE '"[A-Za-z][A-Za-z0-9._-]+$' | tr -d '"' | sed -E 's/[-_.]+$//' |
    grep -viE '^(kiro|com\.apple|swift-generated-sources)' | sort -u)
uuid='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
# One expression for every name, matched whole: a run's own folder, or a prefix, -, _ or ., a UUID and an extension at
# most (config-<UUID>.json), so another program's folder that merely starts the same way is left alone.
alternatives=$(printf '%s\n' "$prefixes" | sed 's/[.]/\\./g' | paste -sd'|' -)
# The Rime tests' folders end in the process's number, not a UUID.
names="allinoneime-tests\.[A-Za-z0-9]+|allinoneime-rime(-sync)?-tests-[0-9]+|($alternatives)[-_.]$uuid(\.[A-Za-z0-9]+)?"
cd "$dir"
find . -mindepth 1 -maxdepth 1 -mmin +360 2>/dev/null | sed 's#^\./##' |
    grep -vE '^(kiro|com\.apple|swift-generated-sources)' | grep -xE "$names" |
    while IFS= read -r name; do
        if [ "$dry" = --dry-run ]; then echo "$dir/$name"; else rm -rf "./$name"; fi
    done
