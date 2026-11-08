#!/bin/sh
# The in-app updater end to end, on this Mac, without touching the user's install (`make update-test`):
# a temporary "Input Methods" and "Applications" holding this build (the installed version), a test server on
# 127.0.0.1 with a newer version made from the same build (9.9.0, re-signed ad hoc) and its update-v2.json signed
# with a test key. Checks: the check finds it, another key is refused, a download that doesn't match changes
# nothing, a failure after the swap rolls back, the update itself (the helper outliving the process that started
# it, as the input method does), and a downgrade is refused. Then the move to the new system identity (`Migration`):
# 9.9.1 with the new bundle IDs over this build again, its preferences, keychain items, input sources and launch
# agents stood for by files in the test install (Preferences/, Keychain/, InputSources.plist, LaunchAgents/): a failure
# after the swap puts everything back, the update carries them over and cleans up the old identity, and so does
# `--migrate-identity` (the 0.7.2 installer's way), a second run changing nothing. The user's settings, packs, installed
# apps, input sources and running input method are the same afterwards.
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
        # The new identity's preferences never written, the user's input sources never changed.
        ls "$HOME/Library/Preferences/$new_ime.plist" "$HOME/Library/Preferences/$new_settings.plist" 2>/dev/null || true
        defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | shasum
        pgrep -x -U "$(id -u)" AllInOneIME | while read -r pid; do
            ps -o comm= -p "$pid" | grep -F "$HOME/Library/Input Methods/" >/dev/null && echo "running $pid"
        done || true
    } > "$1"
}
# The two identities (AppIdentity in AllInOneIMECore; the keychain groups: KeySync.accessGroup and Migration.new).
old_ime=com.aipinyin.inputmethod.AIPinyin old_settings=com.aipinyin.settings old_group=9SR8N3UD5Y.com.aipinyin.shared
new_ime=com.allinoneime.inputmethod.AllInOneIME new_settings=com.allinoneime.settings new_group=9SR8N3UD5Y.com.allinoneime.shared
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
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -sf "http://127.0.0.1:$port/update-v2.json" > /dev/null && break; sleep 0.5; done
manifest="http://127.0.0.1:$port/update-v2.json"
# This build has the old identity: its manifest goes to update.json too (the versions before 0.7.1 read it).
cmp -s "$server/update.json" "$server/update-v2.json" && cmp -s "$server/update.json.sig" "$server/update-v2.json.sig" \
    && pass "the old identity's update is in update.json and update-v2.json" || fail "update.json and update-v2.json"
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

# 6. The new system identity: 9.9.1 with the new bundle IDs, over this build installed again.
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }
# KEY of the item for ACCOUNT in a test keychain's FILE (its data decoded).
item() {
    i=0
    while account=$(plist_value "$1" "$i:account"); do
        if [ "$account" = "$2" ]; then
            if [ "$3" = data ]; then plutil -extract "$i.data" raw -o - "$1" | base64 -d; else plist_value "$1" "$i:$3"; fi
            return
        fi
        i=$((i + 1))
    done
}
reinstall() {
    rm -rf "$root/Input Methods/AllInOneIME.app" "$root/Applications/AllInOneIME Settings.app" "$root/Preferences" "$root/Keychain" \
        "$root/LaunchAgents" "$root/InputSources.plist" "$root/Updates.noindex/result.json"
    ditto "$build/AllInOneIME.app" "$root/Input Methods/AllInOneIME.app"
    ditto "$build/AllInOneIME Settings.app" "$root/Applications/AllInOneIME Settings.app"
    # Another copy of the old Settings app, and a launch agent with an old label: cleaned up after the switch.
    ditto "$build/AllInOneIME Settings.app" "$root/Applications/AllInOneIME Settings copy.app"
    mkdir -p "$root/Preferences" "$root/Keychain" "$root/LaunchAgents"
    plutil -create xml1 "$root/LaunchAgents/watch.plist"
    plutil -insert Label -string "${old_ime%%.inputmethod.*}.realtest-watch" "$root/LaunchAgents/watch.plist"
    # The old domains (the new input method's has a key of its own already, which stays), two keys in the old group
    # (one synced, one not; test values) and the old input source enabled and selected.
    plutil -create xml1 "$root/Preferences/$old_ime.plist"
    plutil -insert recentApps -json '["com.apple.TextEdit"]' "$root/Preferences/$old_ime.plist"
    plutil -insert shared -string old "$root/Preferences/$old_ime.plist"
    plutil -create xml1 "$root/Preferences/$old_settings.plist"
    plutil -insert width -integer 640 "$root/Preferences/$old_settings.plist"
    plutil -create xml1 "$root/Preferences/$new_ime.plist"
    plutil -insert shared -string new "$root/Preferences/$new_ime.plist"
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><array>' \
        "<dict><key>service</key><string>AllInOneIME API key</string><key>account</key><string>openai</string><key>synchronizable</key><true/><key>data</key><data>$(printf 'sk-test-openai' | base64)</data><key>attributes</key><dict><key>labl</key><string>AllInOneIME: OpenAI</string></dict></dict>" \
        "<dict><key>service</key><string>AllInOneIME API key</string><key>account</key><string>gemini</string><key>synchronizable</key><false/><key>data</key><data>$(printf 'test-gemini' | base64)</data><key>attributes</key><dict/></dict>" \
        '</array></plist>' > "$root/Keychain/$old_group.plist"
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        "<plist version=\"1.0\"><dict><key>$old_ime</key><dict><key>registered</key><true/><key>enabled</key><true/><key>selected</key><true/></dict></dict></plist>" \
        > "$root/InputSources.plist"
    cp "$root/Preferences/$new_ime.plist" "$root/new-ime-before.plist"
}
# Moved, the settings and keys carried over, the old identity cleaned up (6b, 6c and 6d).
moved() {
    [ "$(plist_value "$root/Input Methods/AllInOneIME.app/Contents/Info.plist" CFBundleIdentifier)" = "$new_ime" ] \
        && [ "$(plist_value "$root/Applications/AllInOneIME Settings.app/Contents/Info.plist" CFBundleIdentifier)" = "$new_settings" ] \
        && [ "$("$installed" --version)" = "9.9.1" ] \
        && [ "$(plist_value "$root/Preferences/$new_ime.plist" shared)" = new ] \
        && [ "$(plist_value "$root/Preferences/$new_ime.plist" recentApps:0)" = com.apple.TextEdit ] \
        && [ "$(plist_value "$root/Preferences/$new_settings.plist" width)" = 640 ] \
        && [ ! -e "$root/Preferences/$old_ime.plist" ] && [ ! -e "$root/Preferences/$old_settings.plist" ] \
        && [ "$(item "$root/Keychain/$new_group.plist" openai data)" = sk-test-openai ] \
        && [ "$(item "$root/Keychain/$new_group.plist" openai synchronizable)" = true ] \
        && [ "$(item "$root/Keychain/$new_group.plist" openai attributes:labl)" = "AllInOneIME: OpenAI" ] \
        && [ "$(item "$root/Keychain/$new_group.plist" gemini data)" = test-gemini ] \
        && [ "$(item "$root/Keychain/$new_group.plist" gemini synchronizable)" = false ] \
        && [ -z "$(plist_value "$root/Keychain/$old_group.plist" 0:account)" ] \
        && [ "$(plist_value "$root/InputSources.plist" "$new_ime:enabled")" = true ] \
        && [ "$(plist_value "$root/InputSources.plist" "$new_ime:selected")" = true ] \
        && [ "$(plist_value "$root/InputSources.plist" "$old_ime:enabled")" = false ] \
        && [ ! -e "$root/Applications/AllInOneIME Settings copy.app" ] && [ ! -e "$root/LaunchAgents/watch.plist" ] \
        && [ -z "$(ls -A "$root/Updates.noindex" 2>/dev/null | grep -E '^(update|identity)-')" ]
}
mkdir -p "$root/new"
for app in "AllInOneIME.app" "AllInOneIME Settings.app"; do
    ditto "$build/$app" "$root/new/$app"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 9.9.1' -c 'Set :CFBundleVersion 991' "$root/new/$app/Contents/Info.plist"
done
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_ime" -c "Set :TISInputSourceID $new_ime" \
    -c "Set :InputMethodConnectionName ${new_ime}_Connection" "$root/new/AllInOneIME.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_settings" "$root/new/AllInOneIME Settings.app/Contents/Info.plist"
for app in "AllInOneIME.app" "AllInOneIME Settings.app"; do codesign --force --sign - "$root/new/$app" 2>/dev/null; done
ditto -c -k --norsrc --noextattr --noacl "$root/new" "$server/AllInOneIME-9.9.1-update.zip"
rm -rf "$root/new"
cp "$server/update.json" "$root/update-v1-before.json"
swift "$repo/Scripts/build-update-manifest.swift" --test-key "$root/test.key" --out "$server" \
    --zip "$server/AllInOneIME-9.9.1-update.zip" --url "http://127.0.0.1:$port/AllInOneIME-9.9.1-update.zip" \
    --notes "https://github.com/MicroZ-LLC/AllInOneIME/releases" --summary-en "Test update." --summary-zh "测试更新。" > /dev/null
cmp -s "$server/update.json" "$root/update-v1-before.json" && grep -q '"version" : "9.9.1"' "$server/update-v2.json" \
    && pass "the new identity's update is in update-v2.json only (update.json stays at the old identity's)" \
    || fail "update.json is left as it is for the new identity"

# 6a. A failure after the swap: the previous apps back, and the copies of the preferences and keys taken out again.
reinstall
out=$("$installed" --install-update $args --simulate-failure after-swap 2>&1) && fail "the move's rollback" \
    || { [ "$(plist_value "$root/Input Methods/AllInOneIME.app/Contents/Info.plist" CFBundleIdentifier)" = "$old_ime" ] \
        && [ "$(version "$root/Input Methods/AllInOneIME.app")" = "$old" ] && [ "$("$installed" --version)" = "$old" ] \
        && [ "$(plist_value "$root/Applications/AllInOneIME Settings.app/Contents/Info.plist" CFBundleIdentifier)" = "$old_settings" ] \
        && cmp -s "$root/Preferences/$new_ime.plist" "$root/new-ime-before.plist" && [ ! -e "$root/Preferences/$new_settings.plist" ] \
        && [ "$(plist_value "$root/Preferences/$old_ime.plist" shared)" = old ] \
        && [ -z "$(plist_value "$root/Keychain/$new_group.plist" 0:account)" ] \
        && [ "$(item "$root/Keychain/$old_group.plist" gemini data)" = test-gemini ] \
        && [ "$(item "$root/Keychain/$old_group.plist" openai data)" = sk-test-openai ] \
        && [ "$(plist_value "$root/InputSources.plist" "$old_ime:selected")" = true ] \
        && [ "$(plist_value "$root/InputSources.plist" "$new_ime:enabled")" != true ] \
        && [ -e "$root/Applications/AllInOneIME Settings copy.app" ] && [ -e "$root/LaunchAgents/watch.plist" ] \
        && grep -q '"ok" : false' "$root/Updates.noindex/result.json" \
        && pass "a failure in the move to the new identity puts everything back: $old, its settings and keys as they were" \
        || { echo "$out"; cat "$root/update.log"; fail "the move's rollback"; }; }

# 6b. The update to the new identity, as the input method starts it.
reinstall
out=$("$installed" --install-update $args --detach 2>&1) || { echo "$out"; fail "the move starts"; }
for _ in $(seq 1 120); do [ -f "$root/Updates.noindex/result.json" ] && grep -q '"to" : "9.9.1"' "$root/Updates.noindex/result.json" && break; sleep 0.5; done
if grep -q '"ok" : true' "$root/Updates.noindex/result.json" 2>/dev/null && moved; then
    pass "updated $old → 9.9.1 with the new identity: settings and keys carried over, input source switched, the old identity cleaned up"
else
    echo "$out"; cat "$root/update.log"; fail "the update to the new identity"
fi

# 6c. `--migrate-identity`, as the 0.7.2 installer calls it on an installed 0.7.1: the new apps unpacked side by side.
bridge="$build/AllInOneIME.app/Contents/MacOS/AllInOneIME"
out=$("$bridge" --migrate-identity --check 2>&1) && [ "$out" = "migrate-identity: 1" ] \
    && pass "--migrate-identity --check answers" || { echo "$out"; fail "--migrate-identity --check"; }
reinstall
rm -rf "$root/incoming" && mkdir -p "$root/incoming" && ditto -x -k "$server/AllInOneIME-9.9.1-update.zip" "$root/incoming"
out=$("$installed" --migrate-identity "$root/incoming/AllInOneIME.app" --target-dir "$root" 2>&1) && moved \
    && pass "--migrate-identity moves to the new identity the same way" || { echo "$out"; fail "--migrate-identity"; }

# 6d. Another run (the new identity installed already): nothing changes.
state() {
    find "$root/Preferences" "$root/Keychain" "$root/InputSources.plist" "$root/LaunchAgents" "$root/Input Methods" "$root/Applications" \
        -exec stat -f '%N %z %m' {} + | sort
}
state > "$root/moved.txt"
out=$("$bridge" --migrate-identity "$root/Input Methods/AllInOneIME.app" --target-dir "$root" 2>&1) && moved \
    && state | cmp -s - "$root/moved.txt" \
    && pass "another run of --migrate-identity changes nothing" || { echo "$out"; state | diff "$root/moved.txt" -; fail "another run of --migrate-identity"; }

# 7. The user's own things.
snapshot "$root/after.txt"
if cmp -s "$root/before.txt" "$root/after.txt"; then
    pass "the user's settings, packs, installed apps and running input method are untouched ($(wc -l < "$root/before.txt" | tr -d ' ') items)"
else
    diff "$root/before.txt" "$root/after.txt"; fail "the user's things are untouched"
fi

echo "--- helper log"; cat "$root/update.log"
[ "$failures" -eq 0 ] && echo "UPDATE TEST PASSED" || { echo "UPDATE TEST FAILED ($failures)"; exit 1; }
