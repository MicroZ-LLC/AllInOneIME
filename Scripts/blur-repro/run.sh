#!/bin/sh
# Builds and runs the focus-loss reproduction (blur-repro.swift) against the real apps on this Mac: what an open "@"
# list or unfinished pinyin becomes when the field loses the focus without a click.
#   Scripts/blur-repro/run.sh [OUT] [--only textedit,terminal,safari,chrome] [--no-screenshots]
# Needs, on the Mac it runs on:
#   - the screen unlocked, and nobody typing for the few minutes it takes (it brings apps forward and types into them);
#   - this checkout's input method installed and enabled (`make install`);
#   - Accessibility and Screen Recording for "AllInOneIME BlurRepro" (System Settings → Privacy & Security; the first
#     run asks and stops; a rebuild is a new app to macOS and asks again, so the build is kept: BUILD=1 rebuilds).
# No AI request goes out: the test's config gives each app `noAI` and turns Autocomplete off. The user's config and
# input source are put back at the end, and by this script again should the run have been stopped.
# Exit status: 0 done, 2 blocked (locked screen, a permission missing), 1 otherwise.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=/tmp/allinoneime-blur-repro
case "${1:-}" in ""|-*) ;; *) out=$1; shift ;; esac
app="$root/build/BlurRepro.app"
bin="$app/Contents/MacOS/BlurRepro"
if [ ! -x "$bin" ] || [ "${BUILD:-}" = 1 ]; then
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    sed -e 's/RealTest/BlurRepro/g' -e 's/realtest/blurrepro/g' "$root/Scripts/RealTest-Info.plist" > "$app/Contents/Info.plist"
    swiftc -O -o "$bin" "$here/blur-repro.swift" -framework AppKit -framework Carbon
    cp "$here/page.html" "$app/Contents/Resources/page.html"
    codesign --force --sign - "$app"
fi
mkdir -p "$out"
# Through `open`, as `make realtest-run` does: the app runs in the login session, with its own permissions.
open -W -n --stdout "$out/output.txt" --stderr "$out/stderr.txt" "$app" --args "$out" "$@" || true
"$bin" --restore "$out"
cat "$out/output.txt"
if grep -q '^BLUR-REPRO DONE' "$out/output.txt"; then exit 0
elif grep -q '^BLUR-REPRO BLOCKED' "$out/output.txt"; then exit 2
else exit 1; fi
