#!/bin/sh
# The in-app updater end to end, on this Mac, without touching the user's install (`make update-test`):
# a temporary "Input Methods" and "Applications" holding this build (the installed version), a test server on
# 127.0.0.1 with a newer version made from the same build (9.9.0, re-signed ad hoc) and its update.json signed
# with a test key. Checks: the check finds it, another key is refused, a download that doesn't match changes
# nothing, a failure after the swap rolls back, the update itself (the helper outliving the process that started
# it, as the input method does), and a downgrade is refused; the user's settings, packs, installed apps and
# running input method are the same afterwards.
# Usage: Scripts/test-update.sh BUILD-DIR (with AllInOneIME.app and "AllInOneIME Settings.app")
set -eu

build=$(cd "${1:-build}" && pwd)
repo=$(cd "$(dirname "$0")/.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/allinoneime-update-test.XXXXXX")
root=$(cd "$root" && pwd -P)
server="$root/server"
port=$((18000 + $$ % 2000))
failures=0
pass() { echo "✓ $1"; }
fail() { echo "✗ $1"; failures=$((failures + 1)); }
version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist"; }
cleanup() {
    if [ -n "${http:-}" ]; then kill "$http" 2>/dev/null; wait "$http" 2>/dev/null || true; fi
    rm -rf "$root"
}
trap cleanup EXIT

[ -d "$build/AllInOneIME.app" ] && [ -d "$build/AllInOneIME Settings.app" ] || { echo "no apps in $build (make app settings-app)"; exit 1; }
old=$(version "$build/AllInOneIME.app")

# What must not change: the user's settings, packs and installed apps, and the input method running now.
snapshot() {
    {
        find "$HOME/.config/allinoneime" "$HOME/Library/Application Support/AllInOneIME/LanguagePacks" -type f \
            -exec stat -f '%N %z %m' {} + 2>/dev/null | sort
        stat -f '%N %i %m' "$HOME/Library/Input Methods/AllInOneIME.app" "$HOME/Applications/AllInOneIME Settings.app" 2>/dev/null || true
        [ -d "$HOME/Library/Application Support/AllInOneIME/Updates.noindex" ] && echo "real Updates.noindex exists" || true
        pgrep -x -U "$(id -u)" AllInOneIME | while read -r pid; do
            ps -o comm= -p "$pid" | grep -F "$HOME/Library/Input Methods/" >/dev/null && echo "running $pid"
        done || true
    } > "$1"
}
snapshot "$root/before.txt"

# The "installed" apps: this build.
mkdir -p "$root/Input Methods" "$root/Applications" "$server" "$root/new"
ditto "$build/AllInOneIME.app" "$root/Input Methods/AllInOneIME.app"
ditto "$build/AllInOneIME Settings.app" "$root/Applications/AllInOneIME Settings.app"
installed="$root/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME"

# The "new" version: the same build as 9.9.0, re-signed (ad hoc), zipped as `make update-zip` does.
for app in "AllInOneIME.app" "AllInOneIME Settings.app"; do
    ditto "$build/$app" "$root/new/$app"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 9.9.0' -c 'Set :CFBundleVersion 99' "$root/new/$app/Contents/Info.plist"
    codesign --force --sign - "$root/new/$app" 2>/dev/null
done
ditto -c -k --norsrc --noextattr --noacl "$root/new" "$server/AllInOneIME-9.9.0-update.zip"
rm -rf "$root/new"
key=$(swift "$repo/Scripts/build-update-manifest.swift" --test-key "$root/test.key" --out "$server" \
    --zip "$server/AllInOneIME-9.9.0-update.zip" --url "http://127.0.0.1:$port/AllInOneIME-9.9.0-update.zip" \
    --notes "https://github.com/MicroZ-LLC/AllInOneIME/releases" --summary-en "Test update." --summary-zh "测试更新。" \
    | sed -n 's/^test public key: //p')
# A download that doesn't match the manifest: the archive with one byte changed (served in its place in step 2).
cp "$server/AllInOneIME-9.9.0-update.zip" "$root/changed.zip"
printf 'X' | dd of="$root/changed.zip" bs=1 seek=100 conv=notrunc 2>/dev/null
python3 -I -m http.server "$port" --bind 127.0.0.1 --directory "$server" > "$root/server.log" 2>&1 &
http=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -sf "http://127.0.0.1:$port/update.json" > /dev/null && break; sleep 0.5; done
manifest="http://127.0.0.1:$port/update.json"
args="--manifest-url $manifest --key $key --target-dir $root"
echo "test install: $root (installed $old, offered 9.9.0, server :$port)"

# 1. The check.
out=$("$installed" --check-update --manifest-url "$manifest" --key "$key" 2>&1) && echo "$out" | grep -q "update available" \
    && pass "the check finds 9.9.0 (signature checks out)" || { echo "$out"; fail "the check finds 9.9.0"; }
other=$(swift -e 'import CryptoKit; print(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())')
out=$("$installed" --check-update --manifest-url "$manifest" --key "$other" 2>&1) && fail "another key is refused" \
    || { echo "$out" | grep -q "signature" && pass "a manifest signed with another key is refused" || { echo "$out"; fail "another key is refused"; }; }

# 2. A download that doesn't match the signed manifest: nothing changes.
mv "$server/AllInOneIME-9.9.0-update.zip" "$server/good.zip"
cp "$root/changed.zip" "$server/AllInOneIME-9.9.0-update.zip"
out=$("$installed" --install-update $args 2>&1) && fail "a changed archive is refused" \
    || { echo "$out" | grep -q "doesn't match" && [ "$(version "$root/Input Methods/AllInOneIME.app")" = "$old" ] \
        && [ -z "$(ls -A "$root/Updates.noindex" 2>/dev/null | grep update-)" ] \
        && pass "a changed archive is refused; nothing installed or left behind" || { echo "$out"; fail "a changed archive is refused"; }; }
mv "$server/good.zip" "$server/AllInOneIME-9.9.0-update.zip"

# 3. A failure after the swap: the previous apps are put back.
out=$("$installed" --install-update $args --simulate-failure after-swap 2>&1) && fail "rollback" \
    || { [ "$(version "$root/Input Methods/AllInOneIME.app")" = "$old" ] \
        && [ "$(version "$root/Applications/AllInOneIME Settings.app")" = "$old" ] \
        && codesign --verify --strict "$root/Input Methods/AllInOneIME.app" 2>/dev/null \
        && [ "$("$installed" --version)" = "$old" ] \
        && grep -q '"ok" : false' "$root/Updates.noindex/result.json" \
        && [ -z "$(ls -A "$root/Updates.noindex" | grep update-)" ] \
        && pass "a failure after the swap rolls back: $old is back, intact and starts" || { echo "$out"; cat "$root/update.log"; fail "rollback"; }; }

# 4. The update, as the input method does it: the helper outlives the process that started it.
out=$("$installed" --install-update $args --detach 2>&1) || { echo "$out"; fail "the update starts"; }
for _ in $(seq 1 120); do [ -f "$root/Updates.noindex/result.json" ] && grep -q '"to" : "9.9.0"' "$root/Updates.noindex/result.json" && break; sleep 0.5; done
if grep -q '"ok" : true' "$root/Updates.noindex/result.json" 2>/dev/null \
    && [ "$(version "$root/Input Methods/AllInOneIME.app")" = "9.9.0" ] \
    && [ "$(version "$root/Applications/AllInOneIME Settings.app")" = "9.9.0" ] \
    && [ "$("$installed" --version)" = "9.9.0" ] \
    && [ -z "$(ls -A "$root/Updates.noindex" | grep update-)" ]; then
    pass "updated $old → 9.9.0: both apps swapped, the new one starts, nothing left behind"
else
    echo "$out"; cat "$root/update.log"; fail "the update"
fi

# 5. The same version again (or an older one): refused.
out=$("$installed" --install-update $args 2>&1) && fail "a downgrade is refused" \
    || { echo "$out" | grep -q "isn't newer" && [ "$(version "$root/Input Methods/AllInOneIME.app")" = "9.9.0" ] \
        && pass "the same version again is refused" || { echo "$out"; fail "a downgrade is refused"; }; }

# 6. The user's own things.
snapshot "$root/after.txt"
if cmp -s "$root/before.txt" "$root/after.txt"; then
    pass "the user's settings, packs, installed apps and running input method are untouched ($(wc -l < "$root/before.txt" | tr -d ' ') items)"
else
    diff "$root/before.txt" "$root/after.txt"; fail "the user's things are untouched"
fi

echo "--- helper log"; cat "$root/update.log"
[ "$failures" -eq 0 ] && echo "UPDATE TEST PASSED" || { echo "UPDATE TEST FAILED ($failures)"; exit 1; }
