# AllInOneIME for Windows

The Windows shell of AllInOneIME, on the core in `../Core` (the same Swift package the macOS app is built on). It is a
start: for now only the command line, `allinoneime-cli`, which runs level two (translate / polish, the rewrites) with
the core's code and settings (`config.json` where the core keeps it on Windows, under `%APPDATA%`). The input method's
text service (Text Services Framework, C++) is in `tip/`, with its own README; the per-user engine it talks to, the
settings window and the installer come next.

```
swift build                                   # Swift 6.4 for Windows, with Visual Studio's MSVC and Windows SDK
swift run allinoneime-cli --help
```

The core builds and its tests build here too: `swift build --build-tests` in `../Core`.
