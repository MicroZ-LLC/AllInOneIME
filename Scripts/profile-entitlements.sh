#!/bin/sh
# The input method's entitlements for a build with a provisioning profile (`make app PROFILE=…`, `make dmg`): checks that
# the profile fits the signature, then adds the three entitlements it grants to ENTITLEMENTS (already the plain XML of
# Resources/AllInOneIME.entitlements). A profile that doesn't fit makes macOS kill the input method at launch (there is
# no input method then), so every check failing stops the build:
#   - the profile is for this app (its application identifier is TEAM.<CFBundleIdentifier of INFO_PLIST>) and allows
#     GROUP among its keychain access groups;
#   - the signing certificate (SIGN_HASH, its SHA-1) is among the profile's DeveloperCertificates, and its team (the
#     certificate's OU) is the profile's;
#   - the profile has more than 30 days left;
#   - with --all-devices (`make dmg`): it provisions all devices (a Developer ID profile, not a Development one, which
#     lists a few Macs).
# Reads only the profile (public: every shipped copy carries it) and its certificates; nothing from the keychain.
#
# Usage: Scripts/profile-entitlements.sh PROFILE SIGN_HASH INFO_PLIST GROUP ENTITLEMENTS [--all-devices]
set -eu
[ $# -ge 5 ] || { echo "usage: $0 PROFILE SIGN_HASH INFO_PLIST GROUP ENTITLEMENTS [--all-devices]" >&2; exit 2; }
profile=$1 hash=$2 info=$3 group=$4 out=$5 all=${6:-}
buddy=/usr/libexec/PlistBuddy
fail() { echo "error: $profile: $*" >&2; exit 1; }

[ -f "$profile" ] || fail "no such provisioning profile"
[ -n "$hash" ] || fail "a provisioning profile needs a signing identity (none matches SIGN_IDENTITY)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
security cms -D -i "$profile" > "$tmp/profile.plist" 2>/dev/null || fail "not a provisioning profile"
read_key() { $buddy -c "Print :$1" "$tmp/profile.plist" 2>/dev/null; }

team=$(read_key TeamIdentifier:0) || fail "no team"
app_id=$(read_key Entitlements:com.apple.application-identifier) || fail "no application identifier"
bundle=$($buddy -c 'Print :CFBundleIdentifier' "$info")
[ "$app_id" = "$team.$bundle" ] || fail "it is for $app_id, not $team.$bundle"
[ "$(read_key Entitlements:com.apple.developer.team-identifier)" = "$team" ] || fail "its team identifier isn't $team"

# The access group: one of the profile's, exactly or by its trailing `*`.
allowed=no
i=0
while pattern=$(read_key "Entitlements:keychain-access-groups:$i"); do
    case $group in $pattern) allowed=yes ;; esac
    i=$((i + 1))
done
[ $allowed = yes ] || fail "it doesn't allow the keychain access group $group"

# The signing certificate, by its SHA-1, and its team.
hash=$(printf '%s' "$hash" | tr '[:lower:]' '[:upper:]')
found=no cert_team=
i=0
while encoded=$(plutil -extract "DeveloperCertificates.$i" raw -o - "$tmp/profile.plist" 2>/dev/null); do
    printf '%s' "$encoded" | base64 -d > "$tmp/cert.der"
    sha=$(shasum -a 1 "$tmp/cert.der" | cut -c1-40 | tr '[:lower:]' '[:upper:]')
    if [ "$sha" = "$hash" ]; then
        found=yes
        cert_team=$(openssl x509 -inform der -in "$tmp/cert.der" -noout -subject 2>/dev/null \
            | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')
        break
    fi
    i=$((i + 1))
done
[ $found = yes ] || fail "the signing certificate ($hash) isn't one of its $i certificates (sign with one it lists: SIGN_IDENTITY=<its SHA-1>)"
[ "$cert_team" = "$team" ] || fail "the signing certificate's team (${cert_team:-none}) isn't the profile's ($team)"

expires=$(plutil -extract ExpirationDate raw -o - "$tmp/profile.plist") || fail "no expiration date"
expires_at=$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s) || fail "can't read its expiration date ($expires)"
days=$(( (expires_at - $(date +%s)) / 86400 ))
[ $days -gt 30 ] || fail "it expires in $days days ($expires): make a new one"

if [ "$all" = --all-devices ]; then
    [ "$(plutil -extract ProvisionsAllDevices raw -o - "$tmp/profile.plist" 2>/dev/null || true)" = true ] \
        || fail "it doesn't provision all devices (a Development profile?): a release needs the Developer ID one"
fi

$buddy -c "Add :com.apple.application-identifier string $app_id" \
       -c "Add :com.apple.developer.team-identifier string $team" \
       -c "Add :keychain-access-groups array" \
       -c "Add :keychain-access-groups:0 string $group" "$out" >/dev/null
echo "profile: $(read_key Name) (team $team, $days days left); signing certificate listed; keychain group $group"
