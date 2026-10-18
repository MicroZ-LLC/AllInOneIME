#!/bin/sh
# Checks the core's lint guard (Scripts/check-core-portable.py) against small trees of one or two files: what it must
# catch (each way around it found so far) and what it must let through. Run by `make test`.
set -eu
checker="$(cd "$(dirname "$0")" && pwd)/check-core-portable.py"
root=$(mktemp -d "${TMPDIR:-/tmp}/core-portable-test.XXXXXX")
trap 'rm -rf "$root"' EXIT
failures=0 cases=0

fresh() { rm -rf "$root/Sources"; mkdir -p "$root/Sources/AllInOneIMECore"; }
# put FILE: stdin as Sources/AllInOneIMECore/FILE.
put() { mkdir -p "$(dirname "$root/Sources/AllInOneIMECore/$1")"; cat > "$root/Sources/AllInOneIMECore/$1"; }
# expect fail|pass NAME: the tree as it is now caught, or let through.
expect() {
    cases=$((cases + 1))
    out=$(python3 "$checker" --list --root "$root")
    if [ "$1" = fail ] && [ -z "$out" ]; then
        echo "check-core-portable-test: not caught: $2"; failures=$((failures + 1))
    elif [ "$1" = pass ] && [ -n "$out" ]; then
        echo "check-core-portable-test: wrongly caught: $2"; echo "$out" | sed 's/^/    /'; failures=$((failures + 1))
    fi
}
# caught NAME [TEXT]: a tree of one core file, TEXT (printf's escapes) or stdin, caught; allowed: let through.
one() { fresh; if [ $# -gt 1 ]; then printf '%b' "$2" | put Fixture.swift; else put Fixture.swift; fi; }
caught() { one "$@"; expect fail "$1"; }
allowed() { one "$@"; expect pass "$1"; }

# MARK: - Imports outside Platform/Apple/

caught "a plain Apple import" 'import Foundation\nimport AppKit\n'
caught "internal import" 'internal import AppKit\n'
caught "public import" 'public import Security\n'
caught "package import" 'package import os\n'
caught "private import" 'private import AppKit\n'
caught "fileprivate import" 'fileprivate import AppKit\n'
caught "@_spi(X) import" '@_spi(Private) import AppKit\n'
caught "@preconcurrency import" '@preconcurrency import AppKit\n'
caught "@testable import" '@testable import AppKit\n'
caught "an attribute on the line before" '@preconcurrency\nimport AppKit\n'
caught "an attribute and an access level" '@preconcurrency internal import AppKit\n'
caught "import struct X.Y" 'import struct AppKit.NSRect\n'
caught "import func X.y" 'import func Security.SecItemAdd\n'
caught "two imports on one line" 'import Foundation; import AppKit\n'
caught "two imports on one line, no space" 'import Foundation;import AppKit\n'
caught "a module that isn't Apple's but isn't everywhere either" 'import AllInOneIMEMac\n'
caught "an Apple import guarded, outside Platform/Apple/" '#if canImport(AppKit)\nimport AppKit\n#endif\n'
caught '""" in a line comment' '// a """ in a comment\nimport AppKit\nlet a = 1\n'
caught '""" in a block comment' '/* a """ here */\nimport AppKit\n'
caught '""" in a single-line raw string' 'let s = #" """ "#\nimport AppKit\n'
caught '""" after an escaped quote in a string' 'let s = "a \\" """ b"\nimport AppKit\n'
caught "an import after a multi-line string" 'let s = """\n  text\n  """\nimport AppKit\n'
caught "an import after a nested block comment" '/* outer /* nested */ still a comment */\nimport AppKit\n'

# C libraries: only under their own guard.
caught "a C library unguarded" 'import Glibc\n'
caught "a C library under another system's guard" '#if os(Windows)\nimport Glibc\n#endif\n'
caught "a C library in an #else" '#if canImport(Darwin)\n#else\nimport Glibc\n#endif\n'
caught "a C library under a negated guard" '#if !canImport(Glibc)\nimport Glibc\n#endif\n'
caught "a C library after its guard closed" '#if canImport(Glibc)\n#endif\nimport Glibc\n'
caught "WinSDK unguarded" 'import WinSDK\n'
caught "WinSDK under Linux's guard" '#if os(Linux)\nimport WinSDK\n#endif\n'
caught "ucrt under Darwin's guard" '#if canImport(Darwin)\nimport ucrt\n#endif\n'

# MARK: - Programs

caught "Process()" 'let p = Process()\n'
caught "Foundation.Process()" 'let p = Foundation.Process()\n'
caught "Process.run(" 'try Process.run(url, arguments: []) { _ in }\n'
caught ": Process = .init" 'let p: Process = .init()\n'
caught "Process.init" 'let p = Process.init()\n'
caught "Process() in a string's interpolation" 'let s = "\\(Process())"\n'
caught "fork(" 'let pid = fork()\n'
caught "vfork(" 'let pid = vfork()\n'
caught "popen(" 'let f = popen("ls", "r")\n'
caught "_popen(" 'let f = _popen("dir", "r")\n'
caught "system(\"...\")" 'system("ls")\n'
caught "system( with no system of the core's" 'let c = command\nsystem(c)\n'
caught "Glibc.system(" 'Glibc.system(command)\n'
caught "execv(" 'execv(path, argv)\n'
caught "CreateProcessW(" '_ = CreateProcessW(nil, line, nil, nil, false, 0, nil, nil, &startup, &info)\n'
caught "ShellExecuteExW(" '_ = ShellExecuteExW(&execute)\n'
caught "ShellExecuteW(" '_ = ShellExecuteW(nil, verb, file, nil, nil, 1)\n'
caught "WinExec(" '_ = WinExec(line, 1)\n'
caught "_wspawnv(" '_ = _wspawnv(0, path, argv)\n'
caught "_spawnlpe(" '_ = _spawnlpe(0, name, arg, nil, envp)\n'
caught "execve(" 'execve(path, argv, envp)\n'
caught "posix_spawn(" 'posix_spawn(&pid, path, nil, nil, argv, envp)\n'
caught "posix_spawnp(" 'posix_spawnp(&pid, "sh", nil, nil, argv, envp)\n'
caught "posix_spawnattr_*(" 'var a: posix_spawnattr_t?\nposix_spawnattr_init(&a)\n'
fresh
printf 'let p = Process()\n' | put Platform/Apple/Launch.swift
expect fail "Process() in Platform/Apple/ (not the launcher)"
fresh
printf '#if os(Windows)\nimport WinSDK\nfunc f() { _ = CreateProcessW(nil, nil, nil, nil, false, 0, nil, nil, nil, nil) }\n#endif\n' \
    | put Platform/Windows/WindowsPrograms.swift
expect fail "CreateProcessW( in Platform/Windows/ (not the launcher)"

# MARK: - Platform/Apple/ wholly guarded

fresh
printf '#if canImport(Security)\nimport Security\n#endif\nfunc leaked() {}\n#if canImport(Security)\nfunc kept() {}\n#endif\n' \
    | put Platform/Apple/Gap.swift
expect fail "Platform/Apple/: code between two guarded blocks"
fresh
printf '#if canImport(Security)\nimport Security\nfunc kept() {}\n#else\nfunc leaked() {}\n#endif\n' | put Platform/Apple/Else.swift
expect fail "Platform/Apple/: code in the #else"
fresh
printf 'import Foundation\nfunc leaked() {}\n' | put Platform/Apple/None.swift
expect fail "Platform/Apple/: no guard at all"
fresh
printf '// About this file\n#if os(macOS)\nimport Foundation\nfunc leaked() {}\n#endif\n' | put Platform/Apple/OS.swift
expect fail "Platform/Apple/: under #if os(...), not canImport"
fresh
printf '#if !canImport(Security)\nfunc leaked() {}\n#endif\n' | put Platform/Apple/Negated.swift
expect fail "Platform/Apple/: under a negated canImport"
fresh
printf '#if canImport(os)\nimport Foundation\n#endif\nlet s = """\n  text\n  """\n' | put Platform/Apple/String.swift
expect fail "Platform/Apple/: a multi-line string after the block"

# MARK: - Platform/Windows/ wholly guarded

fresh
printf 'import Foundation\nfunc leaked() {}\n' | put Platform/Windows/None.swift
expect fail "Platform/Windows/: no guard at all"
fresh
printf '#if canImport(WinSDK)\nimport WinSDK\nfunc leaked() {}\n#endif\n' | put Platform/Windows/CanImport.swift
expect fail "Platform/Windows/: under canImport, not os(Windows)"
fresh
printf '#if os(Windows)\nfunc kept() {}\n#else\nfunc leaked() {}\n#endif\n' | put Platform/Windows/Else.swift
expect fail "Platform/Windows/: code in the #else"
fresh
printf '#if !os(Windows)\nfunc leaked() {}\n#endif\n' | put Platform/Windows/Negated.swift
expect fail "Platform/Windows/: under a negated os(Windows)"

# MARK: - What passes

allowed "an ordinary core file" <<'EOF'
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@_exported import AllInOneIMEText
internal import Dispatch
@preconcurrency import Crypto
import struct Foundation.URL
import FoundationXML; import FoundationEssentials
import Synchronization
// import AppKit, Process(), fork(), system("ls") in a comment
/* import AppKit
   Process() */
let a = "import AppKit; Process(); system(\"ls\")"
let b = #"import AppKit "quoted" """ Process()"#
let c = """
    import sys
    Process() // in the text
    """
let d = "nested \("import AppKit" + "Process()") strings"
let e = ProcessInfo.processInfo.environment
let f = FoundationProcess.self
func importer(_ imported: Int) {}
func _spawnTask() {}
_spawnTask()
EOF
allowed "the C libraries, each under its guard" <<'EOF'
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif os(Android)
import Android
#elseif os(Windows)
import WinSDK
import ucrt
#endif
#if canImport(WinSDK)
import WinSDK
#endif
#if os(macOS) || os(iOS)
import Darwin
#endif
EOF
fresh
put Prompt.swift <<'EOF'
enum Prompt {
    static func system(_ plan: Int) -> String { "" }
}
EOF
put Other.swift <<'EOF'
extension Prompt {
    static func other() -> String { system(1) + Prompt.system(2) + Self.system(3) }
}
EOF
expect pass "the core's own system(...)"
fresh
printf 'import Foundation\nlet p = Process()\nposix_spawn(nil, nil, nil, nil, nil, nil)\n' | put Platform/FoundationProcessLauncher.swift
expect pass "programs started in the ProcessLauncher"
fresh
put Platform/Windows/WindowsProcessLauncher.swift <<'EOF'
// What this file is.
#if os(Windows)
import Foundation
import WinSDK

func start() { _ = CreateProcessW(nil, nil, nil, nil, false, 0, nil, nil, nil, nil) }
#endif
EOF
expect pass "programs started in the Windows ProcessLauncher, wholly under os(Windows)"
fresh
put Platform/Apple/Wrapped.swift <<'EOF'
// What this file is.

#if canImport(Security)
import Foundation
import Security
@preconcurrency import os

/// A doc comment.
struct Kept {
    #if os(macOS)
    let mac = true
    #else
    let mac = false
    #endif
}
#endif
// The end.
EOF
expect pass "a Platform/Apple/ file wholly guarded"
fresh
put Platform/Apple/Branches.swift <<'EOF'
#if canImport(FoundationModels)
import FoundationModels
#elseif canImport(Security)
import Security
#endif
EOF
expect pass "a Platform/Apple/ file in two canImport branches"

# The package's own core.
cases=$((cases + 1))
if ! out=$(python3 "$checker" --list) || [ -n "$out" ]; then
    echo "check-core-portable-test: the core itself is caught:"; echo "$out" | sed 's/^/    /'; failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
    echo "check-core-portable-test: $failures of $cases cases failed" >&2
    exit 1
fi
echo "check-core-portable-test: $cases cases pass"
