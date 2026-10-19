#!/bin/sh
# librime for the Windows shell: the official release build (BSD-3) of the version the macOS shell links (the root
# Makefile's LIBRIME_VERSION), MSVC x64. It has its plugins built into rime.dll (librime-lua, librime-octagram,
# librime-predict: version-info.txt lists them), where the macOS build has them as rime-plugins/*.dylib. Downloaded
# once into ThirdParty, checked against its SHA-256 and unpacked into ThirdParty/librime, as `make deps` does on the Mac:
#
#   ThirdParty/librime/dist/lib/      rime.dll, rime.lib (its import library), rime.pdb
#   ThirdParty/librime/dist/bin/      rime_deployer.exe, rime_dict_manager.exe, rime_patch.exe
#   ThirdParty/librime/dist/include/  rime_api.h, ...
#
# ThirdParty: $ALLINONEIME_THIRDPARTY if it is set (an absolute path: a folder several checkouts on this PC share),
# else Windows/ThirdParty. The same rule as Package.swift and the Rime tests here. Nothing is done when the folder
# already has this build.
#
#   Scripts/fetch-librime.sh      (in Git Bash; the .7z is unpacked by Windows' own tar.exe, or 7-Zip's if it is there)
set -eu

LIBRIME_VERSION=1.16.1
LIBRIME_ARCHIVE=rime-de4700e-Windows-msvc-x64.7z
LIBRIME_SHA256=e17c1bb4acc9934669e7a62003aef3f8b56d0afa89e5d893ed7dbf34546abb6e
LIBRIME_URL=https://github.com/rime/librime/releases/download/$LIBRIME_VERSION/$LIBRIME_ARCHIVE

windows=$(cd "$(dirname "$0")/.." && pwd)
deps=$(cygpath -u "${ALLINONEIME_THIRDPARTY:-$windows/ThirdParty}")
dest=$deps/librime
stamp=$dest/.archive

# The macOS shell's librime (the root Makefile, when this is the whole repository) and this one are the same version.
makefile=$windows/../Makefile
if [ -f "$makefile" ]; then
    mac=$(sed -n 's/^LIBRIME_VERSION *:= *//p' "$makefile")
    if [ -n "$mac" ] && [ "$mac" != "$LIBRIME_VERSION" ]; then
        echo "fetch-librime: the macOS shell links librime $mac (Makefile), this script $LIBRIME_VERSION: update" \
            "LIBRIME_VERSION, LIBRIME_ARCHIVE and LIBRIME_SHA256 here (and Windows/README.md) to its Windows build" >&2
        exit 1
    fi
fi

if [ -f "$dest/dist/lib/rime.dll" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$LIBRIME_ARCHIVE $LIBRIME_SHA256" ]; then
    echo "fetch-librime: librime $LIBRIME_VERSION is in $dest"
    exit 0
fi

mkdir -p "$deps"
archive=$deps/$LIBRIME_ARCHIVE
if [ ! -f "$archive" ]; then
    echo "fetch-librime: downloading $LIBRIME_URL"
    curl -fsSL --retry 3 -o "$archive.part" "$LIBRIME_URL"
    mv "$archive.part" "$archive"
fi
actual=$(sha256sum "$archive" | cut -d' ' -f1)
if [ "$actual" != "$LIBRIME_SHA256" ]; then
    echo "fetch-librime: $archive has SHA-256 $actual, not $LIBRIME_SHA256: removed, run again" >&2
    rm -f "$archive"
    exit 1
fi

# Unpacked beside the old copy, which is replaced only once the new one is whole.
staging=$deps/librime.unpacking
rm -rf "$staging" && mkdir -p "$staging"
# Windows' bsdtar (libarchive, with liblzma on Windows 11) reads 7-Zip archives; Git Bash's GNU tar doesn't.
systar="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}")/System32/tar.exe"
if [ -x "$systar" ] && "$systar" -xf "$(cygpath -w "$archive")" -C "$(cygpath -w "$staging")" 2>/dev/null; then
    :
elif command -v 7z >/dev/null 2>&1; then
    rm -rf "$staging" && mkdir -p "$staging"
    7z x -y -o"$(cygpath -w "$staging")" "$(cygpath -w "$archive")" >/dev/null
else
    echo "fetch-librime: can't unpack $archive: Windows' tar.exe ($systar) can't read it and there is no 7z on PATH" \
        "(install 7-Zip)" >&2
    rm -rf "$staging"
    exit 1
fi
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
