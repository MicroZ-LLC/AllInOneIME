#!/bin/sh
# rime-ice's data for the Windows shell (GPL-3.0), as `make deps` builds it on the Mac: rime-ice at the release the
# macOS shell pins (the root Makefile's RIME_ICE_TAG: its full.zip, the same SHA-256), with the macOS shell's schema
# list (Resources/rime/default.custom.yaml: rime_ice only), unpacked into ThirdParty/rime-data and its dictionaries
# prebuilt into rime-data/build (rime_ice.table.bin, .prism.bin, .reverse.bin, ...) by librime's own rime_deployer.exe,
# so deployment at startup is quick. Fetches librime first (Scripts/fetch-librime.sh), whose ThirdParty rule it shares:
# $ALLINONEIME_THIRDPARTY if it is set, else Windows/ThirdParty. Nothing is done when the data is already built from
# this release and this schema list.
#
#   Scripts/build-rime-data.sh      (in Git Bash)
set -eu

RIME_ICE_TAG=2026.06.30
RIME_ICE_ZIP=rime-ice-$RIME_ICE_TAG-full.zip
RIME_ICE_SHA256=675d23b070be00e1b800f9a6db033ef98f4493cd5b568ed8aa3b3541769c46ac
RIME_ICE_URL=https://github.com/iDvel/rime-ice/releases/download/$RIME_ICE_TAG/full.zip

windows=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$windows/.." && pwd)
deps=$(cygpath -u "${ALLINONEIME_THIRDPARTY:-$windows/ThirdParty}")
data=$deps/rime-data
patch=$repo/Resources/rime/default.custom.yaml
built=$data/build/rime_ice.table.bin
stamp=$data/.built

# The macOS shell's rime-ice (the root Makefile) and this one are the same release.
makefile=$repo/Makefile
if [ -f "$makefile" ]; then
    mac_tag=$(sed -n 's/^RIME_ICE_TAG *:= *//p' "$makefile")
    mac_sha=$(sed -n 's/^RIME_ICE_SHA256 *:= *//p' "$makefile")
    if [ "$mac_tag $mac_sha" != "$RIME_ICE_TAG $RIME_ICE_SHA256" ]; then
        echo "build-rime-data: the macOS shell pins rime-ice $mac_tag ($mac_sha, Makefile), this script $RIME_ICE_TAG" \
            "($RIME_ICE_SHA256): update RIME_ICE_TAG and RIME_ICE_SHA256 here (and Windows/README.md)" >&2
        exit 1
    fi
fi

"$windows/Scripts/fetch-librime.sh"
dist=$deps/librime/dist

wanted="$RIME_ICE_ZIP $RIME_ICE_SHA256 $(sha256sum "$patch" | cut -d' ' -f1) $(cat "$deps/librime/.archive")"
if [ -f "$built" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$wanted" ]; then
    echo "build-rime-data: rime-ice $RIME_ICE_TAG is built in $data"
    exit 0
fi

zip=$deps/$RIME_ICE_ZIP
if [ ! -f "$zip" ]; then
    echo "build-rime-data: downloading $RIME_ICE_URL"
    curl -fsSL --retry 3 -o "$zip.part" "$RIME_ICE_URL"
    mv "$zip.part" "$zip"
fi
actual=$(sha256sum "$zip" | cut -d' ' -f1)
if [ "$actual" != "$RIME_ICE_SHA256" ]; then
    echo "build-rime-data: $zip has SHA-256 $actual, not $RIME_ICE_SHA256: removed, run again" >&2
    rm -f "$zip"
    exit 1
fi

rm -rf "$data" && mkdir -p "$data"
unzip -q "$zip" -d "$data"
cp "$patch" "$data/"
# rime_deployer.exe finds rime.dll, in dist/lib, on PATH. Its arguments: the user folder, the shared one, the staging
# (build) folder; here all rime-data, as on the Mac. Given from inside it, as relative paths: rime_deployer reads its
# arguments in the ANSI code page and takes them for UTF-8, so a folder named outside ASCII (C:\Users\张三\...) given in
# full fails.
log=$deps/rime-prebuild.log
echo "build-rime-data: prebuilding the dictionaries (rime_deployer --build; log: $log)"
if ! (cd "$data" && PATH="$dist/lib:$PATH" "$dist/bin/rime_deployer.exe" --build . . build) > "$log" 2>&1; then
    echo "build-rime-data: rime_deployer failed (log: $log)" >&2
    exit 1
fi
# What the deployer leaves of a user folder: the input method's own user folder has its own.
rm -f "$data/user.yaml" "$data/installation.yaml"
rm -rf "$data"/*.userdb
if [ ! -f "$built" ]; then
    echo "build-rime-data: no $built after rime_deployer (log: $log)" >&2
    exit 1
fi
echo "$wanted" > "$stamp"
echo "build-rime-data: rime-ice $RIME_ICE_TAG built in $data"
