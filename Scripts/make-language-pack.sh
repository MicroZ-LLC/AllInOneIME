#!/bin/sh
# Builds a language pack archive from an engine's data folder (`make pack`): data only, with pack.json at
# the top. Writes OUT (.tar.xz), OUT.sha256 and OUT.json, the entry for the signed packs.json
# (Scripts/build-packs-index.swift), pointing at URL.
#
#   make-language-pack.sh DATA ID VERSION MIN_APP_VERSION UPSTREAM URL OUT
#
# rime-ice's Lua scripts are left out: they are code, and the app carries its own copy (SharedSupport/rime-lua).
set -eu
data=$1 id=$2 version=$3 min_app=$4 upstream=$5 url=$6 out=$7

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
rsync -a --exclude lua --exclude '*.userdb' --exclude user.yaml --exclude installation.yaml "$data/" "$stage/"
printf '{"id":"%s","upstream":"%s","version":"%s"}\n' "$id" "$upstream" "$version" > "$stage/pack.json"

# The app refuses a pack with links or code (LanguagePackStore.validate): fail here first.
if [ -n "$(find "$stage" -type l)" ]; then echo "error: links in $data" >&2; exit 1; fi
code=$(find "$stage" -type f \( -name '*.lua' -o -name '*.dylib' -o -name '*.so' -o -name '*.sh' -o -name '*.py' -o -name '*.js' \))
if [ -n "$code" ]; then echo "error: code in the pack: $code" >&2; exit 1; fi
chmod -R u=rwX,go=rX "$stage"

mkdir -p "$(dirname "$out")"
rm -f "$out"
# No Mac metadata (._ files, extended attributes) and no owner names from this Mac.
COPYFILE_DISABLE=1 tar -C "$stage" --no-mac-metadata --no-xattrs --uid 0 --gid 0 --uname root --gname wheel -cJf "$out" .

sha=$(shasum -a 256 "$out" | cut -d' ' -f1)
size=$(stat -f %z "$out")
installed=$(find "$stage" -type f -exec stat -f %z {} + | awk '{ s += $1 } END { print s }')
echo "$sha" > "$out.sha256"
printf '{"id":"%s","installedSize":%s,"minAppVersion":"%s","sha256":"%s","size":%s,"upstream":"%s","url":"%s","version":"%s"}\n' \
    "$id" "$installed" "$min_app" "$sha" "$size" "$upstream" "$url" "$version" > "$out.json"
echo "Built $out ($size bytes, $installed unpacked), sha256 $sha"
