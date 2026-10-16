#!/bin/sh
# Picks the codesigning identity to sign with (Makefile, Scripts/make-dmg.sh): prints "HASH NAME" of the
# first valid one `security find-identity` lists whose name or SHA-1 hash contains IDENTITY, or nothing (and
# fails) if none does. codesign itself refuses a name several identities match ("ambiguous"), e.g. two Apple
# Development certificates in the keychain; signing with the hash leaves it no choice, and this says which.
# Usage: Scripts/sign-identity.sh IDENTITY
set -eu
identity=${1:-}
[ -n "$identity" ] || exit 1

list=$(security find-identity -v -p codesigning 2>/dev/null) || exit 1
# `  1) 78387717E5… "Apple Development: Name (TEAMID)"` as "78387717E5… Apple Development: Name (TEAMID)",
# each hash once, in the listed order.
matches=$(printf '%s\n' "$list" \
    | sed -n 's/^ *[0-9][0-9]*) \([0-9A-F]\{40\}\) "\(.*\)"$/\1 \2/p' \
    | grep -F -- "$identity" | awk '!seen[$1]++' || true)
[ -n "$matches" ] || exit 1

first=$(printf '%s\n' "$matches" | head -1)
count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
if [ "$count" -gt 1 ]; then
    echo "note: $count signing identities match '$identity'; using the first, \"${first#* }\"" >&2
fi
printf '%s\n' "$first"
