#!/bin/sh
# librime for the Windows shell: the official release build (BSD-3) of the version the macOS shell links (the root
# Makefile's LIBRIME_VERSION), MSVC x64. It has its plugins built into rime.dll (librime-lua, librime-octagram,
# librime-predict: version-info.txt lists them), where the macOS build has them as rime-plugins/*.dylib. With it, OpenCC's
# data (Apache-2.0) for Traditional characters (Settings → Input → Chinese → Characters), from librime's own build of its
# dependencies for the same release, as the root Makefile takes the macOS one's: the .ocd2 format follows the OpenCC
# linked into librime, so never OpenCC's own releases or master; only the files the app uses (OPENCC_FILES, the
# Makefile's, `ChineseCharacters.openCCFiles` in the core). Each downloaded once into ThirdParty, checked against its
# SHA-256 and unpacked, as `make deps` does on the Mac:
#
#   ThirdParty/librime/dist/lib/      rime.dll, rime.lib (its import library), rime.pdb
#   ThirdParty/librime/dist/bin/      rime_deployer.exe, rime_dict_manager.exe, rime_patch.exe
#   ThirdParty/librime/dist/include/  rime_api.h, ...
#   ThirdParty/opencc/                s2twp.json, s2hk.json, s2tw.json and their dictionaries (*.ocd2), which
#                                     Scripts/build-rime-data.sh puts into rime-data/opencc
#
# ThirdParty: $ALLINONEIME_THIRDPARTY if it is set (an absolute path: a folder several checkouts on this PC share),
# else Windows/ThirdParty. The same rule as Package.swift and the Rime tests here. Nothing is done when the folder
# already has these builds.
#
#   Scripts/fetch-librime.sh      (in Git Bash; the .7z files are unpacked by Windows' own tar.exe, or 7-Zip's if it is there)
set -eu

LIBRIME_VERSION=1.16.1
LIBRIME_ARCHIVE=rime-de4700e-Windows-msvc-x64.7z
LIBRIME_SHA256=e17c1bb4acc9934669e7a62003aef3f8b56d0afa89e5d893ed7dbf34546abb6e
LIBRIME_URL=https://github.com/rime/librime/releases/download/$LIBRIME_VERSION/$LIBRIME_ARCHIVE
RIME_DEPS_ARCHIVE=rime-deps-de4700e-Windows-msvc-x64.7z
RIME_DEPS_SHA256=8ddfa46881a8f20c37fbbfdc3b9d0e9c5f7958f486cce4335a18be6ea8277af2
RIME_DEPS_URL=https://github.com/rime/librime/releases/download/$LIBRIME_VERSION/$RIME_DEPS_ARCHIVE
OPENCC_FILES="s2twp.json s2hk.json s2tw.json STPhrases.ocd2 STCharacters.ocd2 TWPhrases.ocd2 TWVariants.ocd2 HKVariants.ocd2"

windows=$(cd "$(dirname "$0")/.." && pwd)
deps=$(cygpath -u "${ALLINONEIME_THIRDPARTY:-$windows/ThirdParty}")
dest=$deps/librime
stamp=$dest/.archive
opencc=$deps/opencc

# The macOS shell's librime and OpenCC files (the root Makefile, when this is the whole repository) and these are the same.
makefile=$windows/../Makefile
if [ -f "$makefile" ]; then
    mac=$(sed -n 's/^LIBRIME_VERSION *:= *//p' "$makefile")
    if [ -n "$mac" ] && [ "$mac" != "$LIBRIME_VERSION" ]; then
        echo "fetch-librime: the macOS shell links librime $mac (Makefile), this script $LIBRIME_VERSION: update" \
            "LIBRIME_VERSION, LIBRIME_ARCHIVE, LIBRIME_SHA256, RIME_DEPS_ARCHIVE and RIME_DEPS_SHA256 here (and" \
            "Windows/README.md) to its Windows builds" >&2
        exit 1
    fi
    mac_files=$(sed -n 's/^OPENCC_FILES *:= *//p' "$makefile")
    if [ -n "$mac_files" ] && [ "$mac_files" != "$OPENCC_FILES" ]; then
        echo "fetch-librime: the macOS shell carries the OpenCC files $mac_files (Makefile), this script $OPENCC_FILES:" \
            "update OPENCC_FILES here" >&2
        exit 1
    fi
fi

# The release asset $1, whose SHA-256 is $2, downloaded into ThirdParty once (from $3) and checked.
fetch() {
    archive=$deps/$1
    if [ ! -f "$archive" ]; then
        echo "fetch-librime: downloading $3"
        curl -fsSL --retry 3 -o "$archive.part" "$3"
        mv "$archive.part" "$archive"
    fi
    actual=$(sha256sum "$archive" | cut -d' ' -f1)
    if [ "$actual" != "$2" ]; then
        echo "fetch-librime: $archive has SHA-256 $actual, not $2: removed, run again" >&2
        rm -f "$archive"
        exit 1
    fi
}

# The 7-Zip archive $1 unpacked into $2, a folder of its own made anew.
unpack() {
    rm -rf "$2" && mkdir -p "$2"
    # Windows' bsdtar (libarchive, with liblzma on Windows 11) reads 7-Zip archives; Git Bash's GNU tar doesn't.
    systar="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}")/System32/tar.exe"
    if [ -x "$systar" ] && "$systar" -xf "$(cygpath -w "$1")" -C "$(cygpath -w "$2")" 2>/dev/null; then
        :
    elif command -v 7z >/dev/null 2>&1; then
        rm -rf "$2" && mkdir -p "$2"
        7z x -y -o"$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null
    else
        echo "fetch-librime: can't unpack $1: Windows' tar.exe ($systar) can't read it and there is no 7z on PATH" \
            "(install 7-Zip)" >&2
        rm -rf "$2"
        exit 1
    fi
}

mkdir -p "$deps"

if [ -f "$dest/dist/lib/rime.dll" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$LIBRIME_ARCHIVE $LIBRIME_SHA256" ]; then
    echo "fetch-librime: librime $LIBRIME_VERSION is in $dest"
else
    fetch "$LIBRIME_ARCHIVE" "$LIBRIME_SHA256" "$LIBRIME_URL"
    # Unpacked beside the old copy, which is replaced only once the new one is whole.
    staging=$deps/librime.unpacking
    unpack "$deps/$LIBRIME_ARCHIVE" "$staging"
    for file in dist/lib/rime.dll dist/lib/rime.lib dist/bin/rime_deployer.exe dist/include/rime_api.h; do
        if [ ! -f "$staging/$file" ]; then
            echo "fetch-librime: $LIBRIME_ARCHIVE has no $file" >&2
            rm -rf "$staging"
            exit 1
        fi
    done
    # rime-ice's Lua scripts need librime-lua, built in.
    if ! grep -q 'librime-lua' "$staging/version-info.txt"; then
        echo "fetch-librime: $LIBRIME_ARCHIVE is built without librime-lua (version-info.txt), which rime-ice needs" >&2
        rm -rf "$staging"
        exit 1
    fi
    echo "$LIBRIME_ARCHIVE $LIBRIME_SHA256" > "$staging/.archive"
    rm -rf "$dest"
    mv "$staging" "$dest"
    echo "fetch-librime: librime $LIBRIME_VERSION ($LIBRIME_ARCHIVE) in $dest"
fi

# OpenCC's data: the asset's share/opencc, only OPENCC_FILES (the asset also has OpenCC's library and headers, unused).
wanted="$RIME_DEPS_ARCHIVE $RIME_DEPS_SHA256 $OPENCC_FILES"
if [ -f "$opencc/s2twp.json" ] && [ "$(cat "$opencc/.archive" 2>/dev/null)" = "$wanted" ]; then
    echo "fetch-librime: OpenCC's data is in $opencc"
else
    fetch "$RIME_DEPS_ARCHIVE" "$RIME_DEPS_SHA256" "$RIME_DEPS_URL"
    staging=$deps/rime-deps.unpacking
    unpack "$deps/$RIME_DEPS_ARCHIVE" "$staging"
    rm -rf "$opencc.new" && mkdir -p "$opencc.new"
    for file in $OPENCC_FILES; do
        if [ ! -f "$staging/share/opencc/$file" ]; then
            echo "fetch-librime: $RIME_DEPS_ARCHIVE has no share/opencc/$file" >&2
            rm -rf "$staging" "$opencc.new"
            exit 1
        fi
        cp "$staging/share/opencc/$file" "$opencc.new/"
    done
    rm -rf "$staging"
    echo "$wanted" > "$opencc.new/.archive"
    rm -rf "$opencc"
    mv "$opencc.new" "$opencc"
    echo "fetch-librime: OpenCC's data ($RIME_DEPS_ARCHIVE) in $opencc"
fi
