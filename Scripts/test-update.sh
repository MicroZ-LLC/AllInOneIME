#!/bin/sh
# The in-app updater end to end, on this Mac, without touching the user's install (`make update-test`):
# a temporary "Input Methods" and "Applications" holding this build (the installed version), a test server on
# 127.0.0.1 with a newer version made from the same build (9.9.0, re-signed ad hoc) and its update-v2.json signed
# with a test key. Checks: the check finds it, another key is refused, a download that doesn't match changes
# nothing, a failure after the swap rolls back, the update itself (the helper outliving the process that started
# it, as the input method does), and a downgrade is refused. Then the move to the new system identity (`Migration`):
# 9.9.1 with the new bundle IDs over this build again, its preferences, keychain items (the login keychain's too),
# input sources, launch agents and caches stood for by files in the test install (Preferences/, Keychain/,
# InputSources.plist, LaunchAgents/, Caches/): a failure after the swap puts everything back, the update carries them over
# (the login keychain's keys as handover items) and cleans up the old identity, and so does `--migrate-identity` (the
# 0.7.2 installer's way); the new input source is registered and left to the user (the move never asks to enable it),
# the old one's entry waiting in the record (identity-cleanup.json) until it is added; a cleanup step that fails is left
# in the record for the new version, and another run finishes it, changing nothing else; once the user has added the new
# input source, another run takes the old one out and deletes the record. `make install-check` and the installer refuse
# an installed copy with the new identity. The user's settings,
# packs, installed apps, input sources and running input method are the same afterwards.
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
# FIELD of the item of SERVICE and ACCOUNT in a test keychain's FILE (data: decoded); empty when there is none.
login_item() {
    i=0
    while service=$(plist_value "$1" "$i:service"); do
        if [ "$service" = "$2" ] && [ "$(plist_value "$1" "$i:account")" = "$3" ]; then
            if [ "$4" = data ]; then plutil -extract "$i.data" raw -o - "$1" | base64 -d; else plist_value "$1" "$i:$4"; fi
            return
        fi
        i=$((i + 1))
    done
}
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
        "$root/LaunchAgents" "$root/InputSources.plist" "$root/Updates.noindex/result.json" "$root/Caches"
    ditto "$build/AllInOneIME.app" "$root/Input Methods/AllInOneIME.app"
    ditto "$build/AllInOneIME Settings.app" "$root/Applications/AllInOneIME Settings.app"
    # Another copy of the old Settings app, and a launch agent with an old label: cleaned up after the switch.
    ditto "$build/AllInOneIME Settings.app" "$root/Applications/AllInOneIME Settings copy.app"
    mkdir -p "$root/Preferences" "$root/Keychain" "$root/LaunchAgents"
    plutil -create xml1 "$root/LaunchAgents/watch.plist"
    plutil -insert Label -string "${old_ime%%.inputmethod.*}.realtest-watch" "$root/LaunchAgents/watch.plist"
    # The old input method's caches (they go) and another app's (they stay).
    mkdir -p "$root/Caches/$old_ime/com.apple.e5rt.e5bundlecache" "$root/Caches/com.example.other"
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
    # The login keychain (key sync off): an API key and a replaced copy, handed over to the new identity.
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><array>' \
        "<dict><key>service</key><string>AllInOneIME API key</string><key>account</key><string>claude</string><key>data</key><data>$(printf 'sk-test-claude' | base64)</data><key>attributes</key><dict><key>labl</key><string>AllInOneIME: Claude</string><key>icmt</key><string>api.anthropic.com</string></dict></dict>" \
        "<dict><key>service</key><string>AllInOneIME replaced API key</string><key>account</key><string>deepseek</string><key>data</key><data>$(printf 'sk-test-replaced' | base64)</data><key>attributes</key><dict/></dict>" \
        '</array></plist>' > "$root/Keychain/login.plist"
    cp "$root/Keychain/login.plist" "$root/login-before.plist"
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        "<plist version=\"1.0\"><dict><key>$old_ime</key><dict><key>registered</key><true/><key>enabled</key><true/><key>selected</key><true/></dict></dict></plist>" \
        > "$root/InputSources.plist"
    cp "$root/Preferences/$new_ime.plist" "$root/new-ime-before.plist"
}
record="$root/identity-cleanup.json"
# Moved: the settings and keys carried over, the old identity cleaned up but for its input source's entry; the new input
# source registered and left to the user (never enabled by the move: only the user adds one), the old one's entry
# waiting for it, the record keeping that step alone, handed over (6b, 6c and 6d).
moved() {
    carried \
        && [ "$(plist_value "$root/InputSources.plist" "$new_ime:registered")" = true ] \
        && [ "$(plist_value "$root/InputSources.plist" "$new_ime:enabled")" != true ] \
        && [ "$(plist_value "$root/InputSources.plist" "$old_ime:enabled")" = true ] \
        && [ "$(plutil -extract inputSource raw -o - "$record" 2>/dev/null)" = "$old_ime" ] \
        && [ "$(plutil -extract handedOver raw -o - "$record")" = true ] || return 1
    for key in apps defaultsDomains launchAgents keychainItems loginKeys caches; do
        [ "$(plutil -extract "$key" raw -o - "$record")" = 0 ] || return 1
    done
}
# Then, the user having added the new input source, the old one taken out and the record gone (6d', 6e).
finished() {
    carried && [ "$(plist_value "$root/InputSources.plist" "$new_ime:enabled")" = true ] \
        && [ "$(plist_value "$root/InputSources.plist" "$old_ime:enabled")" = false ] && [ ! -e "$record" ]
}
# What the move did besides the input sources.
carried() {
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
        && [ ! -e "$root/Applications/AllInOneIME Settings copy.app" ] && [ ! -e "$root/LaunchAgents/watch.plist" ] \
        && [ ! -e "$root/Caches/$old_ime" ] && [ -d "$root/Caches/com.example.other" ] \
        && [ -z "$(ls -A "$root/Updates.noindex" 2>/dev/null | grep -E '^(update|identity)-')" ] \
        && [ "$(login_item "$root/Keychain/$new_group.plist" "AllInOneIME API key (handed over)" claude data)" = sk-test-claude ] \
        && [ "$(login_item "$root/Keychain/$new_group.plist" "AllInOneIME API key (handed over)" claude attributes:icmt)" = api.anthropic.com ] \
        && [ "$(login_item "$root/Keychain/$new_group.plist" "AllInOneIME replaced API key (handed over)" deepseek data)" = sk-test-replaced ] \
        && [ "$(login_item "$root/Keychain/$new_group.plist" "AllInOneIME API key (handed over)" claude synchronizable)" = false ] \
        && [ -z "$(plist_value "$root/Keychain/login.plist" 0:account)" ]
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
        && [ -d "$root/Caches/$old_ime" ] \
        && cmp -s "$root/Keychain/login.plist" "$root/login-before.plist" \
        && [ -z "$(login_item "$root/Keychain/$new_group.plist" "AllInOneIME API key (handed over)" claude data)" ] \
        && [ ! -e "$root/identity-cleanup.json" ] \
        && grep -q '"ok" : false' "$root/Updates.noindex/result.json" \
        && grep -q "is back" "$root/Updates.noindex/result.json" && ! grep -q "nothing was changed" "$root/Updates.noindex/result.json" \
        && grep -q "apps: swapped" "$root/update.log" && grep -q "apps: the previous ones are back" "$root/update.log" \
        && pass "a failure in the move to the new identity puts everything back (logged): $old, its settings and keys as they were" \
        || { echo "$out"; cat "$root/update.log"; fail "the move's rollback"; }; }

# 6b. The update to the new identity, as the input method starts it.
reinstall
out=$("$installed" --install-update $args --detach 2>&1) || { echo "$out"; fail "the move starts"; }
for _ in $(seq 1 120); do [ -f "$root/Updates.noindex/result.json" ] && grep -q '"to" : "9.9.1"' "$root/Updates.noindex/result.json" && break; sleep 0.5; done
if grep -q '"ok" : true' "$root/Updates.noindex/result.json" 2>/dev/null && moved; then
    pass "updated $old → 9.9.1 with the new identity: settings and keys carried over, the old identity cleaned up; the new input source left to the user, the old one's entry waiting for it"
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
    && echo "$out" | grep -q "registered, not enabled" && echo "$out" | grep -q "isn't enabled yet" \
    && echo "$out" | grep -q "no AllInOneIME input source works" && ! echo "$out" | grep -q "registered, enabled" \
    && pass "--migrate-identity moves to the new identity the same way, and says the new input source is the user's to add" \
    || { echo "$out"; fail "--migrate-identity"; }

# 6d. A cleanup step that fails (a launch agent's property list that can't be deleted): the move goes through, and the
# record keeps that step alone, handed over to the new version; another run finishes it and deletes the record.
reinstall
rm -rf "$root/incoming" && mkdir -p "$root/incoming" && ditto -x -k "$server/AllInOneIME-9.9.1-update.zip" "$root/incoming"
chmod a-w "$root/LaunchAgents"
out=$("$installed" --migrate-identity "$root/incoming/AllInOneIME.app" --target-dir "$root" 2>&1) && status=0 || status=$?
chmod u+w "$root/LaunchAgents"
if [ "$status" -eq 0 ] && echo "$out" | grep -q "left for its next launch" && [ -e "$root/LaunchAgents/watch.plist" ] \
    && [ "$(stat -f '%Lp' "$record")" = 600 ] \
    && [ "$(plutil -extract handedOver raw -o - "$record")" = true ] \
    && [ "$(plutil -extract launchAgents.0.label raw -o - "$record")" = "${old_ime%%.inputmethod.*}.realtest-watch" ] \
    && [ "$(plutil -extract launchAgents.0.plist raw -o - "$record")" = "$root/LaunchAgents/watch.plist" ] \
    && [ "$(plutil -extract apps raw -o - "$record")" = 0 ] && [ "$(plutil -extract loginKeys raw -o - "$record")" = 0 ] \
    && [ "$(plutil -extract defaultsDomains raw -o - "$record")" = 0 ] && [ "$(plutil -extract inputSource raw -o - "$record")" = "$old_ime" ] \
    && ! grep -q sk-test "$record"; then
    pass "a cleanup step that fails is left in the record (0600, handed over, that step and the input source's) for the new version"
else
    echo "$out"; cat "$record" 2>/dev/null; fail "a cleanup step left in the record"
fi
out=$("$bridge" --migrate-identity "$root/Input Methods/AllInOneIME.app" --target-dir "$root" 2>&1) && moved \
    && pass "another run finishes the step left; the input source's waits in the record" \
    || { echo "$out"; cat "$record" 2>/dev/null; fail "another run finishes the step left"; }

# 6d'. The user adds the new input source (System Settings, as only they can): the next run takes the old one out and
# deletes the record.
/usr/libexec/PlistBuddy -c "Delete :$new_ime" -c "Add :$new_ime dict" -c "Add :$new_ime:registered bool true" \
    -c "Add :$new_ime:enabled bool true" -c "Add :$new_ime:listed bool true" -c "Add :$new_ime:selected bool true" \
    -c "Set :$old_ime:selected false" "$root/InputSources.plist"
out=$("$bridge" --migrate-identity "$root/Input Methods/AllInOneIME.app" --target-dir "$root" 2>&1) && finished \
    && pass "once the user has added it, the old input source goes and the record with it" \
    || { echo "$out"; cat "$record" 2>/dev/null; fail "the old input source once the new one is added"; }

# 6e. Another run (the new identity installed already): nothing changes.
state() {
    find "$root/Preferences" "$root/Keychain" "$root/InputSources.plist" "$root/LaunchAgents" "$root/Input Methods" "$root/Applications" \
        -exec stat -f '%N %z %m' {} + | sort
}
state > "$root/moved.txt"
out=$("$bridge" --migrate-identity "$root/Input Methods/AllInOneIME.app" --target-dir "$root" 2>&1) && finished \
    && state | cmp -s - "$root/moved.txt" \
    && pass "another run of --migrate-identity changes nothing" || { echo "$out"; state | diff "$root/moved.txt" -; fail "another run of --migrate-identity"; }

# 6f. The installer of this version (`make install-check`, which `make install` runs first) never replaces an installed
# copy with the new identity.
mkdir -p "$root/guard/Input Methods" && ditto "$root/Input Methods/AllInOneIME.app" "$root/guard/Input Methods/AllInOneIME.app"
out=$(make -s -C "$repo" install-check INSTALL_DIR="$root/guard/Input Methods" 2>&1) && fail "install-check refuses a newer identity" \
    || { echo "$out" | grep -q "is newer than" && pass "make install refuses to replace an installed copy with the new identity" \
        || { echo "$out"; fail "install-check refuses a newer identity"; }; }
rm -rf "$root/guard/Input Methods/AllInOneIME.app" && ditto "$build/AllInOneIME.app" "$root/guard/Input Methods/AllInOneIME.app"
out=$(make -s -C "$repo" install-check INSTALL_DIR="$root/guard/Input Methods" 2>&1) \
    && pass "make install-check lets this identity's copy be replaced" || { echo "$out"; fail "install-check over this identity"; }
# The disk image's installer (its debug build, without the apps it carries) in a home of the test's own: it refuses
# before it reads anything else.
if (cd "$repo" && swift build --product AllInOneIMEInstaller > "$root/installer-build.log" 2>&1); then
    mkdir -p "$root/home/Library/Input Methods"
    ditto "$root/Input Methods/AllInOneIME.app" "$root/home/Library/Input Methods/AllInOneIME.app"
    out=$(CFFIXED_USER_HOME="$root/home" "$(cd "$repo" && swift build --show-bin-path)/AllInOneIMEInstaller" --install 2>&1) \
        && fail "the installer refuses a newer identity" \
        || { echo "$out" | grep -q "is newer than" && [ "$(version "$root/home/Library/Input Methods/AllInOneIME.app")" = 9.9.1 ] \
            && pass "the installer refuses to replace an installed copy with the new identity" || { echo "$out"; fail "the installer refuses a newer identity"; }; }
else
    cat "$root/installer-build.log"; fail "the installer builds"
fi

# 7. The user's own things.
snapshot "$root/after.txt"
if cmp -s "$root/before.txt" "$root/after.txt"; then
    pass "the user's settings, packs, installed apps and running input method are untouched ($(wc -l < "$root/before.txt" | tr -d ' ') items)"
else
    diff "$root/before.txt" "$root/after.txt"; fail "the user's things are untouched"
fi

echo "--- helper log"; cat "$root/update.log"
[ "$failures" -eq 0 ] && echo "UPDATE TEST PASSED" || { echo "UPDATE TEST FAILED ($failures)"; exit 1; }
