#!/bin/sh
# Runs a command (`swift test …`) with TMPDIR set to a folder of its own, removed when it ends, however it ends: what
# reads TMPDIR writes there and goes with it (swiftc's TemporaryDirectory.* folders, shell children, Foundation on
# Linux). Apple's Foundation doesn't read it (FileManager's temporaryDirectory is the user's), so on macOS the tests
# remove their own (TestScratch, SourceCompiler) and CI sweeps what's left (Scripts/sweep-test-tmp.sh): 246,000 test
# folders filled the Mac mini's disk (2026-11-16). The Makefile's `swift test` lines run through it;
# Core/Scripts/test.sh does the same for the core.
set -eu
base=${TMPDIR:-/tmp}
run=$(mktemp -d "${base%/}/allinoneime-tests.XXXXXX")
trap 'rm -rf "$run"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
status=0
TMPDIR="$run/" "$@" || status=$?
exit "$status"
