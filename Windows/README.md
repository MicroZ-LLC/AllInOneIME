# AllInOneIME for Windows

The Windows shell of AllInOneIME, on the core in `../Core` (the same Swift package the macOS app is built on). It is a
start: for now the command line, `allinoneime-cli`, which runs level two (translate / polish, the rewrites) with the
core's code and settings (`config.json` where the core keeps it on Windows, under `%APPDATA%`), and the tests of level
one's engine, the core's librime binding (`AllInOneIMERime`), on librime's Windows build with rime-ice's data. The
input method itself (a Text Services Framework text service), its settings window and its installer come next.

```
swift build                                   # Swift 6.4 for Windows, with Visual Studio's MSVC and Windows SDK
swift run allinoneime-cli --help
```

The core builds and its tests build here too: `swift build --build-tests` in `../Core`.

## Level one: librime and rime-ice

The same versions as the macOS shell (the root `Makefile`), downloaded, checked and unpacked into `ThirdParty/`
(git-ignored), in the Mac's layout (`ThirdParty/librime/dist/...`, `ThirdParty/rime-data/`). In Git Bash:

```
Scripts/build-rime-data.sh    # librime (Scripts/fetch-librime.sh), then rime-ice, its dictionaries prebuilt
swift test                    # the Rime tests (Tests/AllInOneIMERimeTests): 24, in 5 s to a minute
```

`Scripts/fetch-librime.sh` alone fetches librime only. Both do nothing when `ThirdParty` already has what they would
make, and both fail when the root `Makefile` pins another version than theirs: the two shells move together.
`ALLINONEIME_THIRDPARTY` (an absolute path), as on the Mac, puts `ThirdParty` elsewhere, a folder several checkouts on
this PC share; `Package.swift` and the tests read it too.

| | Version | Download | Size | SHA-256 |
|---|---|---|---|---|
| librime (BSD-3) | 1.16.1, de4700e, MSVC x64 | [`rime-de4700e-Windows-msvc-x64.7z`](https://github.com/rime/librime/releases/download/1.16.1/rime-de4700e-Windows-msvc-x64.7z) | 7,373,905 | `e17c1bb4acc9934669e7a62003aef3f8b56d0afa89e5d893ed7dbf34546abb6e` |
| rime-ice (GPL-3.0) | 2026.06.30, 6810e89 | [`full.zip`](https://github.com/iDvel/rime-ice/releases/download/2026.06.30/full.zip), saved as `rime-ice-2026.06.30-full.zip` | 16,050,491 | `675d23b070be00e1b800f9a6db033ef98f4493cd5b568ed8aa3b3541769c46ac` |

librime's official Windows build has the same plugins as the macOS one, at the same commits (its `version-info.txt`):
librime-lua 68f9c36 (rime-ice's Lua scripts: the date, the calculator...), librime-octagram dfcc151, librime-predict
920bd41. Unpacked, `ThirdParty/librime` is 55 MB: `dist/lib/rime.dll` (3,727,872 bytes), `rime.lib` (its import
library, 301,656), `rime.pdb` (49,917,952: its symbols), `dist/bin/rime_deployer.exe` and two more tools, and
`dist/include/rime_api.h`, the same headers as the core's `Sources/CRime/include`. `ThirdParty/rime-data` is 126 MB,
76 MB of it the prebuilt dictionaries in `build/` (`rime_ice.table.bin` 60,703,784 bytes, `rime_ice.prism.bin`,
`.reverse.bin`, and those of `melt_eng` and `radical_pinyin`), built in about 20 s.

### Linking

The core has no unsafe flags: its `CRime` names the library (`link "rime"`) and the shell says where it is.
`Package.swift`'s `linksRime` passes `-L ThirdParty/librime/dist/lib` (for `rime.lib`) and delay-loads `rime.dll`
(`/DELAYLOAD:rime.dll`, `delayimp`): Windows doesn't look for it when the program starts, so the program loads it
itself, by its full path (`LoadLibraryExW`), before its first call into librime. The tests do that from `ThirdParty`
(`RimeFixture.loadLibrary`), where on the Mac an rpath to that folder does it; the input method will load it from its
own folder. `rime.dll` has the C++ runtime built in: it needs only `KERNEL32`, `USER32` and `dbghelp`, no Visual C++
redistributable.

### Tests

`Tests/AllInOneIMERimeTests` are the macOS shell's Rime tests (the root's `Tests/AllInOneIMERimeTests`), on Windows:
deployment from the prebuilt data, nihao → 你好, a sentence, punctuation and the ASCII mode, rime-ice's Lua date, the
Composer with the real engine (the action keys, @ commands, English mode, Caps Lock, Shift), a redeploy, fuzzy pinyin
(n ↔ l) and its rules in rime-ice's schema, and the learned words' sync through a shared folder. Added here: paging
(Page Down / Page Up and rime-ice's `=` / `-`), picking a candidate (by its place, its number key, on the second page),
learning (a word picked from the second page comes up front the next time), and `installation.yaml` as librime writes
it on Windows. Before `Scripts/fetch-librime.sh` they don't link (no `rime.lib`; `swift build` without the tests needs
none); with librime but before `Scripts/build-rime-data.sh` the engine tests fail, naming the folder, and the schema's
is skipped unless `ALLINONEIME_REQUIRE_RIME_DATA=1`. librime's warnings (glog) go to stderr and fail nothing:
`circular dependencies detected in melt_eng.schema`, `lua/lunar.db` not in the user folder.

## What differs from macOS

- **The package**: a `.7z`, which Git Bash's tar can't read; Windows 11's own `tar.exe` (bsdtar, with LZMA) unpacks it,
  or 7-Zip's `7z` if that is on `PATH`. The plugins are built into `rime.dll`, not `rime-plugins/*.dylib`; there is no
  `rime_table_decompiler`.
- **Line ends**: librime writes its YAML files on Windows with `\r\n` (`installation.yaml`, `build/*.yaml`), which Swift
  takes for one Character: `components(separatedBy: "\n")` doesn't split them there. The core's `RimeSync` (the
  learned words' sync) reads `installation.yaml` by lines that end either way.
- **Paths**: librime takes its folders as UTF-8 (with forward slashes too), but gives them back
  (`get_user_data_sync_dir`, ...) in the ANSI code page; `RimeService.userDataSyncDir` decodes it so.
  `rime_deployer.exe` reads its arguments in the ANSI code page and takes them for UTF-8, so
  `Scripts/build-rime-data.sh` runs it inside `rime-data` with relative paths. All 24 tests pass with the user folder
  and `ThirdParty` under Chinese names (`临时`, `第三方`), as under a Chinese user name; that run started the test runner
  directly, since `swiftc` itself fails when `TMP` is outside ASCII.
- **The prebuilt dictionaries** are nearly portable. Built here, `*.table.bin` and `*.reverse.bin` are byte for byte the
  Mac's (those of the published Chinese pack, zh-pinyin 1.0.0). `rime_ice.prism.bin` and `radical_pinyin.prism.bin`
  differ only in the schema's checksum (a CRC of the compiled schema file, which has the sources' modification times in
  it, and `\r\n` here): two builds on Windows differ the same way. `melt_eng.prism.bin` (its English words) has one
  spelling more here (8,378,264 bytes against 8,377,216), for a reason not found yet. With the Mac's pack as the data
  all 24 tests pass too: librime uses its tables as they are; at the first deployment it builds `rime_ice`'s prism
  (40 KB) in the user folder, as it does `radical_pinyin`'s with either data. Deployment took 0.8 to 1.2 s with the
  pack and 0.3 to 0.8 s with the data built here, on files read before; up to 15 s on files just unpacked or with other
  builds running on the PC. So the Chinese pack the Mac downloads can serve Windows as it is;
  `Scripts/build-rime-data.sh` builds the data here instead, as `make deps` does on the Mac.
