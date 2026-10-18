#!/bin/sh
# Keeps Sources/AllInOneIMECore (all of it, subfolders too) platform-neutral (Scripts/check-core-portable.py reads the
# code, comments and strings left out). It fails when
#   - a core file imports anything but what every platform has (Foundation, FoundationNetworking, FoundationXML,
#     FoundationEssentials, Dispatch, Crypto, AllInOneIMEText, Synchronization) outside Platform/Apple/; a C library
#     (Darwin, Glibc, Musl, Android, WinSDK, ucrt) only under its own `#if canImport(...)` or `#if os(...)`;
#   - a file in Platform/Apple/ isn't wholly inside `#if canImport(...)`: every line of code in such a branch; a file
#     in Platform/Windows/ isn't wholly inside `#if os(Windows)`;
#   - a core file starts a program itself (`Process(`, `posix_spawn`, `fork(`, `system(`, `CreateProcessW(`,
#     `ShellExecuteW(`, ...) instead of through the ProcessLauncher (only Platform/FoundationProcessLauncher.swift and
#     Platform/Windows/WindowsProcessLauncher.swift do).
# Scripts/check-core-portable-test.sh checks the check.
#
#   Scripts/check-core-portable.sh            check (run by `make test`)
#   Scripts/check-core-portable.sh --list     print every offence, one a line
set -eu
exec python3 "$(dirname "$0")/check-core-portable.py" "$@"
