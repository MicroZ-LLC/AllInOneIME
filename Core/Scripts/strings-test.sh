#!/bin/sh
# The String Catalog tool (Scripts/strings/main.swift) on a fixture, a core and a shell: text that moves from the shell's
# code to the core's goes, with `make strings` (the core's run, then the shell's with --move-to-base), to the core's
# catalog with the shell's translations of it, and leaves the shell's; after that both catalogs pass --check and merge
# into one. Without --move-to-base (a core that is a checkout of its repository) the key stays in both, and --check says
# so. Run by the macOS shell's `make test`.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
swift build --package-path "$root" --product strings-tool >/dev/null
tool="$(swift build --package-path "$root" --show-bin-path)/strings-tool"
work=$(mktemp -d "${TMPDIR:-/tmp}/allinoneime-strings-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
failed=0
fail() { echo "strings-test: $1"; failed=1; }

setup() {
    rm -rf "$work/core" "$work/shell"
    mkdir -p "$work/core/Sources" "$work/core/Resources" "$work/shell/Sources" "$work/shell/Resources"
    # "Moved" was the shell's text (translated in the shell's catalog); its code is the core's now.
    printf '%s\n' 'let a = tr("留下", "Stays")' 'let b = tr("移来", "Moved")' > "$work/core/Sources/Core.swift"
    printf '%s\n' 'let c = tr("壳的", "The shell'"'"'s")' > "$work/shell/Sources/Shell.swift"
    cat > "$work/core/Resources/Localizable.xcstrings" <<'EOF'
{
  "sourceLanguage" : "en",
  "strings" : {
    "Stays" : { "localizations" : { "fr" : { "stringUnit" : { "state" : "translated", "value" : "Reste" } } } }
  },
  "version" : "1.0"
}
EOF
    cat > "$work/shell/Resources/Localizable.xcstrings" <<'EOF'
{
  "sourceLanguage" : "en",
  "strings" : {
    "Moved" : { "localizations" : { "fr" : { "stringUnit" : { "state" : "translated", "value" : "Déplacé" } } } },
    "The shell's" : { "localizations" : { "fr" : { "stringUnit" : { "state" : "translated", "value" : "Du shell" } } } }
  },
  "version" : "1.0"
}
EOF
}

core() { (cd "$work/core" && "$tool" "$@"); }
shell() {
    (cd "$work/shell" && "$tool" --sources Sources --sources ../core/Sources --base ../core/Resources/Localizable.xcstrings "$@")
}

# make strings, the core a folder of the shell's.
setup
core > /dev/null
shell --move-to-base > /dev/null
grep -q '"Moved"' "$work/shell/Resources/Localizable.xcstrings" && fail "the moved key is still in the shell's catalog"
grep -q '"Déplacé"' "$work/core/Resources/Localizable.xcstrings" || fail "the core's catalog lacks the shell's translation"
grep -q '"Du shell"' "$work/shell/Resources/Localizable.xcstrings" || fail "the shell's own text left its catalog"
core --check > /dev/null || fail "the core's catalog fails --check after the move"
shell --check > /dev/null || fail "the shell's catalog fails --check after the move"
shell --merge "$work/merged.xcstrings" > /dev/null || fail "the catalogs don't merge after the move"
grep -q '"Déplacé"' "$work/merged.xcstrings" 2>/dev/null || fail "the merged catalog lacks the moved translation"

# The core a checkout: nothing is written to it, and --check reports the key in both.
setup
core > /dev/null
shell > /dev/null
grep -q '"Moved"' "$work/shell/Resources/Localizable.xcstrings" || fail "without --move-to-base the key left the shell's catalog"
shell --check > /dev/null && fail "--check passes with a key in both catalogs"

if [ "$failed" -ne 0 ]; then
    echo "strings-test: FAILED"
    exit 1
fi
echo "strings-test: text moved from a shell's code to the core's moves to the core's catalog, with its translations"
