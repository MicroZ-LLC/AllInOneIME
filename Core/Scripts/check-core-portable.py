#!/usr/bin/env python3
"""Keeps Sources/AllInOneIMECore (all of it, subfolders too) platform-neutral (run by check-core-portable.sh).

It reads each file with its comments and string literals blanked out (line numbers kept), so nothing in a comment or a
string counts, and nothing there (an unbalanced \"\"\" in a comment, say) changes how the rest is read. It fails when
  - a core file imports a module that isn't one every platform has (ALLOWED), anywhere but Platform/Apple/; a C library
    (C_LIBRARIES), or one of the package's own that the core depends on only on some systems (OWN_GUARDED), only under
    its own guard (`#if canImport(Glibc)`, `#elseif os(Linux)`, ...);
  - a file in Platform/Apple/ isn't wholly inside `#if canImport(...)`: every line of code is in the branch of one; a
    file in Platform/Windows/ isn't wholly inside `#if os(Windows)` (that alone, or in a `&&`);
  - a core file starts a program itself (`Process(`, `posix_spawn`, `fork(`, `system(`, `CreateProcessW(`,
    `ShellExecuteW(`, ...) instead of through the ProcessLauncher; its files start them only their own way (LAUNCHERS).
A guard counts only when its branch can't be taken without it (`implies`): `#if !(canImport(X))`,
`#if canImport(X) || true` and `#if !(os(Linux) || os(Windows))` guard nothing.

    check-core-portable.py [--list] [--root DIR]    the offences, one a line (DIR: the package, by default this one)
"""
import os
import re
import sys

# What the core may import outside Platform/Apple/: Foundation and the libraries of every platform's Swift, and the
# package's own modules below the core.
ALLOWED = {"Foundation", "FoundationNetworking", "FoundationXML", "FoundationEssentials", "Dispatch", "Crypto",
           "AllInOneIMEText", "AllInOneIMEScriptEngine", "Synchronization"}
# The C libraries, each allowed under a guard that names it or its systems.
APPLE_SYSTEMS = ["macOS", "iOS", "tvOS", "watchOS", "visionOS"]
C_LIBRARIES = {
    "Darwin": APPLE_SYSTEMS,
    "Glibc": ["Linux"],
    "Musl": ["Linux"],
    "Android": ["Android"],
    "WinSDK": ["Windows"],
    "ucrt": ["Windows"],
}
# The package's own modules that the core depends on only on some systems, each allowed under its guard as a C library
# is: QuickJS, the JavaScript where there is no JavaScriptCore (Package.swift's condition).
OWN_GUARDED = {"AllInOneIMEQuickJS": ["Linux", "Windows", "Android"]}
IMPORT = re.compile(
    r"(?m)(?:^|;)[ \t]*"
    r"(?:@\w+(?:\s*\([^()]*\))?\s*|(?:public|package|internal|private|fileprivate|open)\s+)*"
    r"\bimport\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_]\w*)")
DIRECTIVE = re.compile(r"^\s*#\s*(if|elseif|else|endif)\b(.*)$")
C_MODULE = r"(?:Darwin|Glibc|Musl|Android|WinSDK|ucrt|Foundation)\s*\.\s*"
PROGRAMS = [
    re.compile(r"(?<!\w)Process\s*(?:\(|\.\s*(?:run|init|launchedProcess)\b)"),
    re.compile(r":\s*Process\s*[?!]?\s*=\s*\.\s*init\b"),
    re.compile(r"(?<!\w)(?:v?fork|_?popen|_?wsystem|_?wpopen|exec[lv]\w*|posix_spawn\w*)\s*\("),
    # Windows' own: CreateProcess(W/A/AsUser/WithLogon/WithToken), ShellExecute(Ex), WinExec, the C runtime's _spawn
    # family (_spawnl, _wspawnvpe, ...: not any name that starts "_spawn").
    re.compile(r"(?<!\w)(?:CreateProcess\w*|ShellExecute\w*|WinExec|_w?spawn[lv]p?e?|_w?exec[lv]\w*)\s*\("),
    re.compile(r"(?<!\w)" + C_MODULE + r"system\s*\("),
]
# The ProcessLauncher's files, the only ones that start programs, each its own way only: Foundation's `Process`,
# Windows' `CreateProcessW` (not CreateProcessAsUserW, ShellExecuteW, posix_spawn, ...).
LAUNCHERS = {
    "Platform/FoundationProcessLauncher.swift": PROGRAMS[:2],
    "Platform/Windows/WindowsProcessLauncher.swift": [re.compile(r"(?<!\w)CreateProcessW\s*\(")],
}
# `system(` unqualified: the C call when its argument is a string literal, or when the core has no `system` of its own
# (Prompt.system, ...) that it could mean.
SYSTEM_WITH_TEXT = re.compile(r"(?<![\w.])system\s*\(\s*#*\"")
SYSTEM_CALL = re.compile(r"(?<![\w.])system\s*\(")
SYSTEM_DECLARED = re.compile(r"\bfunc\s+system\b")


def strip(src):
    """`src` with every comment and string literal's text blanked (newlines kept); string delimiters and the code of
    interpolations stay."""
    out = list(src)
    n = len(src)
    opener = re.compile(r'(#*)("""|")')

    def blank(a, b):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    def code(i, closing):
        depth = 0
        while i < n:
            if src.startswith("//", i):
                j = src.find("\n", i)
                j = n if j < 0 else j
                blank(i, j)
                i = j
                continue
            if src.startswith("/*", i):
                j, nested = i + 2, 1
                while j < n and nested:
                    if src.startswith("/*", j):
                        nested, j = nested + 1, j + 2
                    elif src.startswith("*/", j):
                        nested, j = nested - 1, j + 2
                    else:
                        j += 1
                blank(i, j)
                i = j
                continue
            c = src[i]
            if c in "#\"":
                m = opener.match(src, i)
                if m:
                    i = string(m.end(), m.group(1), m.group(2))
                    continue
            if closing:
                if c == "(":
                    depth += 1
                elif c == ")":
                    if depth == 0:
                        return i
                    depth -= 1
            i += 1
        return i

    def string(i, hashes, quote):
        close, escape = quote + hashes, "\\" + hashes
        start = i
        while i < n:
            if src.startswith(escape, i):
                j = i + len(escape)
                if j < n and src[j] == "(":  # interpolation: code again, up to its `)`
                    blank(start, i)
                    i = code(j + 1, True) + 1
                    start = i
                else:
                    i = j + 1
                continue
            if src.startswith(close, i):
                blank(start, i)
                return i + len(close)
            if quote == '"' and src[i] == "\n":  # not closed on its line
                blank(start, i)
                return i
            i += 1
        blank(start, n)
        return n

    code(0, False)
    return "".join(out)


def branches(lines):
    """For each line, the conditions of the `#if` branches it is in (None for an `#else`), outermost first."""
    stack, result = [], []
    for line in lines:
        m = DIRECTIVE.match(line)
        if m:
            kind, condition = m.group(1), re.sub(r"\s+", "", m.group(2))
            if kind == "if":
                stack.append(condition)
            elif kind == "elseif" and stack:
                stack[-1] = condition
            elif kind == "else" and stack:
                stack[-1] = None
            elif kind == "endif" and stack:
                stack.pop()
            result.append(None)  # a directive: not code
            continue
        result.append(list(stack))
    return result


def split(expression, operator):
    """`expression`'s parts between `operator`s (`&&`, `||`) outside parentheses."""
    parts, depth, start, i = [], 0, 0, 0
    while i < len(expression):
        if expression[i] == "(":
            depth += 1
        elif expression[i] == ")":
            depth -= 1
        elif depth == 0 and expression.startswith(operator, i):
            parts.append(expression[start:i])
            i += len(operator)
            start = i
            continue
        i += 1
    return parts + [expression[start:]]


def unwrapped(expression):
    """`expression` without the parentheses around all of it: "((a&&b))" is "a&&b", "(a)&&(b)" stays."""
    while expression.startswith("(") and expression.endswith(")"):
        depth = 0
        for i, c in enumerate(expression):
            depth += {"(": 1, ")": -1}.get(c, 0)
            if depth == 0 and i < len(expression) - 1:
                return expression  # the first "(" closes before the end
        expression = expression[1:-1]
    return expression


def implies(condition, atoms, alternatives=True):
    r"""Whether the branch `condition` (spaces removed; None: an `#else`) is taken only when one of `atoms` (regular
    expressions, each a whole check: `os\(Windows\)`) holds: it is one of them (in parentheses or not), a `&&` with one
    term that implies it, or (when `alternatives`) a `||` whose alternatives each do. Nothing negated implies anything:
    `!canImport(X)`, `!(os(Linux)||os(Windows))`; nor does a `||` with another way in (`canImport(X)||true`)."""
    if condition is None:
        return False
    expression = unwrapped(condition)
    options = split(expression, "||")
    if len(options) > 1:
        return alternatives and all(implies(o, atoms, alternatives) for o in options)
    terms = split(expression, "&&")
    if len(terms) > 1:
        return any(implies(t, atoms, alternatives) for t in terms)
    return any(re.fullmatch(atom, expression) for atom in atoms)


def check_of(check, values):
    """The atoms (`implies`) for `check(value)`, one of `values`."""
    return [re.escape(check) + r"\(" + re.escape(v) + r"\)" for v in values]


ANY_CAN_IMPORT = [r"canImport\(\w+\)"]
WINDOWS = check_of("os", ["Windows"])


def check(root):
    core = os.path.join(root, "Sources", "AllInOneIMECore")
    files = []
    for folder, _, entries in os.walk(core):
        files += [os.path.join(folder, e) for e in entries if e.endswith(".swift")]
    files.sort()
    stripped = {}
    for path in files:
        with open(path, encoding="utf-8", errors="replace") as f:
            stripped[path] = strip(f.read())
    declares_system = any(SYSTEM_DECLARED.search(text) for text in stripped.values())

    found = []
    for path in files:
        relative = os.path.relpath(path, core).replace(os.sep, "/")
        shown = os.path.relpath(path, root).replace(os.sep, "/")
        apple = relative.startswith("Platform/Apple/")
        windows = relative.startswith("Platform/Windows/")
        text = stripped[path]
        lines = text.split("\n")
        where = branches(lines)

        # Imports.
        for m in IMPORT.finditer(text):
            module = m.group(1)
            line = text.count("\n", 0, m.start(1))
            conditions = where[line] or []
            if module in ALLOWED:
                continue
            if module in C_LIBRARIES or module in OWN_GUARDED:
                systems = C_LIBRARIES.get(module) or OWN_GUARDED[module]
                what = "a C library" if module in C_LIBRARIES else "the core's on some systems only"
                guard = check_of("canImport", [module]) + check_of("os", systems)
                if not any(implies(c, guard) for c in conditions):
                    found.append(f"{shown}:{line + 1}: import {module} ({what}, only under #if canImport({module}) or its os(...))")
                continue
            if not apple:
                found.append(f"{shown}:{line + 1}: import {module} (not one every platform has: only in Platform/Apple/)")
            elif not any(implies(c, ANY_CAN_IMPORT) for c in conditions):
                found.append(f"{shown}:{line + 1}: import {module} (outside #if canImport)")

        # Platform/Apple/ files wholly inside `#if canImport(...)`.
        if apple:
            code = [i for i, l in enumerate(lines) if l.strip() and where[i] is not None]
            if not code:
                found.append(f"{shown}: not wholly inside #if canImport(...) (no code)")
            for i in code:
                if not any(implies(c, ANY_CAN_IMPORT) for c in where[i]):
                    found.append(f"{shown}:{i + 1}: not wholly inside #if canImport(...): {lines[i].strip()}")

        # Platform/Windows/ files wholly inside `#if os(Windows)`: that alone, or in a `&&`.
        if windows:
            code = [i for i, l in enumerate(lines) if l.strip() and where[i] is not None]
            if not code:
                found.append(f"{shown}: not wholly inside #if os(Windows) (no code)")
            for i in code:
                if not any(implies(c, WINDOWS, alternatives=False) for c in where[i]):
                    found.append(f"{shown}:{i + 1}: not wholly inside #if os(Windows): {lines[i].strip()}")

        # Programs: none but in a launcher, and there its own way only (blanked before the rest is looked for).
        own = LAUNCHERS.get(relative, [])
        for i, l in enumerate(lines):
            for allowed in own:
                l = allowed.sub(lambda m: " " * len(m.group(0)), l)
            if (any(p.search(l) for p in PROGRAMS) or SYSTEM_WITH_TEXT.search(l)
                    or (not declares_system and SYSTEM_CALL.search(l))):
                found.append(f"{shown}:{i + 1}: starts a program (use Platform.current.processes, a ProcessLauncher)")
    return found


def main(arguments):
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    listing = False
    while arguments:
        argument = arguments.pop(0)
        if argument == "--list":
            listing = True
        elif argument == "--root" and arguments:
            root = arguments.pop(0)
        else:
            print(__doc__.strip().splitlines()[-1].strip(), file=sys.stderr)
            return 2
    found = check(root)
    if listing:
        for line in found:
            print(line)
        return 0
    if found:
        print("error: Sources/AllInOneIMECore isn't platform-neutral:", file=sys.stderr)
        for line in found:
            print("  " + line, file=sys.stderr)
        return 1
    print("core-portable: imports only what every platform has (Apple's in Platform/Apple/, wholly guarded; C libraries "
          "under their guard), Platform/Windows/ wholly under os(Windows), no program started outside the ProcessLauncher")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
