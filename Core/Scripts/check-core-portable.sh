#!/bin/sh
# Keeps Sources/AllInOneIMECore (all of it, subfolders too) platform-neutral (Scripts/check-core-portable.py reads the
# code, comments and strings left out). It fails when
#   - a core file imports anything but what every platform has (Foundation, FoundationNetworking, FoundationXML,
#     FoundationEssentials, Dispatch, Crypto, AllInOneIMEText, AllInOneIMEScriptEngine, Synchronization) outside
#     Platform/Apple/; a C library (Darwin, Glibc, Musl, Android, WinSDK, ucrt), or AllInOneIMEQuickJS (the core's on
#     Windows, Linux and Android only), only under its own `#if canImport(...)` or `#if os(...)`;
#   - a file in Platform/Apple/ isn't wholly inside `#if canImport(...)`: every line of code in such a branch; a file
#     in Platform/Windows/ isn't wholly inside `#if os(Windows)` (that alone, or in a `&&`);
#   - a core file starts a program itself (`Process(`, `posix_spawn`, `fork(`, `system(`, `CreateProcessW(`,
#     `ShellExecuteW(`, ...) instead of through the ProcessLauncher (only Platform/FoundationProcessLauncher.swift does,
#     with `Process`, and Platform/Windows/WindowsProcessLauncher.swift, with `CreateProcessW`);
#   - a file of the package (any target's under Sources/ or Tests/) uses `URLSession`, `URLRequest`, `HTTPURLResponse`
#     or another of FoundationNetworking's types without `#if canImport(FoundationNetworking) import FoundationNetworking
#     #endif`, in the file or re-exported (`@_exported`) by another of its target: Apple's Foundation has them, Linux's
#     and Windows' don't.
# A guard counts only when its branch can't be taken without it: `#if !(canImport(X))` or `#if canImport(X) || true`
# guards nothing.
# Scripts/check-core-portable-test.sh checks the check.
#
#   Scripts/check-core-portable.sh            check (run by `make test`)
#   Scripts/check-core-portable.sh --list     print every offence, one a line
set -eu
exec python3 "$(dirname "$0")/check-core-portable.py" "$@"
