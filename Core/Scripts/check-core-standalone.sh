#!/bin/sh
# Keeps the core standalone: this folder (the package) builds and tests as it is, alone, as its own repository will
# (and as core-portable.yml's export of it does). It fails when
#   - Package.swift depends on a package by path (`.package(path:)`), or names a path with ".." in it;
#   - a C header or module map includes a file outside the package, or one it doesn't have (`#include "…"`,
#     `header "…"`): something `make deps` puts in place, say;
#   - a Swift file walks from `#filePath` (or `#file`) above the package: more `deletingLastPathComponent()` than the
#     file is deep, or a "../" appended on the way;
#   - a script finds its files from its own place (`$0`, `__file__`) and climbs above the package with "..";
#   - a workflow names a path above it ("../");
#   - a symbolic link points outside it.
# Test data that merely mentions "..", say a path a check must refuse, isn't a way out and doesn't count.
#
#   Scripts/check-core-standalone.sh            check (run by the macOS shell's `make test`, and in CI)
#   Scripts/check-core-standalone.sh --list     print every offence, one a line
#   Scripts/check-core-standalone.sh --release  build each of the package's library products in release, as a shell
#                                               that depends on the core does (`make test`, and CI on macOS and Linux)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)

if [ "${1:-}" = --release ]; then
    # Each library product but AllInOneIMETestSupport, the tests' (its acceptance helpers import the core @testable,
    # which a release build doesn't allow: Package.swift). The products as this system's manifest has them (on Linux
    # and Windows without AllInOneIMERime), from `swift package describe`, so a new one is built too.
    products=$(swift package --package-path "$root" describe | awk '
        /^Products:/ { listing = 1; next }
        /^[^ ]/ { listing = 0 }
        listing && $1 == "Name:" { name = $2 }
        listing && $1 == "Library:" && name != "AllInOneIMETestSupport" { print name }')
    if [ -z "$products" ]; then
        echo "core-standalone: no library products in $root/Package.swift"
        exit 1
    fi
    for product in $products; do
        echo "core-standalone: swift build -c release --product $product"
        swift build --package-path "$root" -c release --product "$product"
    done
    echo "core-standalone: every product builds in release ($(echo $products))"
    exit 0
fi
exec python3 - "$root" "$@" <<'EOF'
import os
import re
import sys

root = os.path.realpath(sys.argv[1])
listing = "--list" in sys.argv[2:]
offences = []
SKIP = {".build", ".swiftpm", ".git"}


def files():
    for folder, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP]
        for name in names:
            yield os.path.join(folder, name)


def shown(path):
    return os.path.relpath(path, root)


def inside(path):
    path = os.path.normpath(path)
    return path == root or path.startswith(root + os.sep)


def offence(path, line, what):
    offences.append(f"{shown(path)}:{line}: {what}")


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (UnicodeDecodeError, OSError):
        return None


# A walk from #filePath: URL(fileURLWithPath: #filePath) then .deletingLastPathComponent() and
# .appendingPathComponent("…") calls, on one line or several.
WALK = re.compile(r"URL\(\s*fileURLWithPath:\s*#file(?:Path)?\s*\)((?:\s*\.\s*(?:resolvingSymlinksInPath\(\)|standardized(?:FileURL)?"
                  r"|deletingLastPathComponent\(\)|appendingPathComponent\(\s*\"[^\"]*\"[^)]*\)))*)")
STEP = re.compile(r"(deletingLastPathComponent)\(\)|appendingPathComponent\(\s*\"([^\"]*)\"")
INCLUDE = re.compile(r"^\s*#\s*(?:include|import)\s*\"([^\"]+)\"|^\s*(?:umbrella\s+)?header\s+\"([^\"]+)\"", re.M)
STRING = re.compile(r"\"((?:[^\"\\\n]|\\.)*)\"")
SELF_PLACE = re.compile(r"\$0|\$\{?BASH_SOURCE|__file__")

for path in files():
    name = os.path.basename(path)
    folder = os.path.dirname(path)
    if os.path.islink(path):
        if not inside(os.path.realpath(path)):
            offence(path, 0, f"a link to {os.readlink(path)}, outside the package")
        continue
    text = read(path)
    if text is None:
        continue
    relative = shown(path)

    if relative == "Package.swift":
        for m in re.finditer(r"\.package\(\s*(?:name:\s*\"[^\"]*\",\s*)?path:", text):
            offence(path, line_of(text, m.start()), "a package dependency by path")
        for m in STRING.finditer(text):
            if re.search(r"(^|/)\.\.(/|$)", m.group(1)):
                offence(path, line_of(text, m.start()), f"a path above the package: \"{m.group(1)}\"")

    if name.endswith((".h", ".c", ".m", ".modulemap")):
        for m in INCLUDE.finditer(text):
            target = m.group(1) or m.group(2)
            if not inside(os.path.join(folder, target)):
                offence(path, line_of(text, m.start()), f"includes a file outside the package: \"{target}\"")
            elif not os.path.isfile(os.path.join(folder, target)):
                offence(path, line_of(text, m.start()), f"includes a file the package doesn't have: \"{target}\"")

    if name.endswith(".swift"):
        for m in WALK.finditer(text):
            parts = relative.split(os.sep)  # the file's place in the package, its own name last
            for step in STEP.finditer(m.group(1)):
                if step.group(1):
                    if not parts:
                        offence(path, line_of(text, m.start()), "walks from #filePath above the package")
                        break
                    parts.pop()
                else:
                    for part in step.group(2).split("/"):
                        if part == "..":
                            if not parts:
                                offence(path, line_of(text, m.start()), "walks from #filePath above the package")
                                break
                            parts.pop()
                        elif part not in ("", "."):
                            parts.append(part)

    if name.endswith((".sh", ".py")) or (text.startswith("#!") and "/Scripts/" in "/" + relative):
        for number, line in enumerate(text.splitlines(), 1):
            if not SELF_PLACE.search(line) or ".." not in line:
                continue
            # From the script's folder, each ".." (as "/.." after `dirname "$0"`, or a ".." argument) climbs once.
            climbs = len(re.findall(r"(?:^|[/\"'(,\s])\.\.(?=[/\"')\s,]|$)", line.split("#", 1)[0] if name.endswith(".sh") else line))
            if not inside(os.path.join(folder, *([".."] * climbs))):
                offence(path, number, "climbs from the script's own place above the package")

    if relative.startswith(".github" + os.sep):
        for number, line in enumerate(text.splitlines(), 1):
            if re.search(r"(^|[\s:=\"'])\.\./", line.split("#", 1)[0]):
                offence(path, number, "a path above the package")

if listing:
    for o in offences:
        print(o)
    sys.exit(0)
if offences:
    print("core-standalone: the core reaches outside its folder:")
    for o in offences:
        print("  " + o)
    sys.exit(1)
print("core-standalone: nothing reaches outside the package (no path dependencies, includes, #filePath walks, script "
      "paths or links above it)")
EOF
