# AllInOneIME Core

The part of [AllInOneIME](https://github.com/MicroZ-LLC/AllInOneIME) that every platform shares: the two-level input
state machine (`Composer`), the `@` commands, the AI providers and their prompts, the config, the extensions and
plugins, the language packs' engines, the interface text. A Swift package with no user interface and no system code of
its own: what it needs of the system goes through `Platform` (`Sources/AllInOneIMECore/Platform/`), which each shell
fills in at launch (`Platform.current = …`). The macOS input method is the first shell; Windows, iOS and Android follow.

## Products

| Product | What it is |
|---|---|
| `AllInOneIMEText` | The interface text and its language (`tr`, `UIString`, `InterfaceText`, `StringCatalog`) |
| `AllInOneIMECore` | Everything else of the core; re-exports `AllInOneIMEText` and `AllInOneIMEScriptEngine` (the `ScriptEngine` protocol) |
| `AllInOneIMEQuickJS` | QuickJS-ng (`Sources/CQuickJS`, vendored) as a `ScriptEngine` (`QuickJSEngine`): plugins and `@js` on Windows, Linux and Android, where the core links it; Apple platforms keep JavaScriptCore |
| `AllInOneIMERime` | librime (local pinyin) behind the `PinyinEngine` protocol; on macOS and Windows for now. The headers are in `Sources/CRime/include`; the shell links the library (`-L`) |
| `AllInOneIMECLI` | The command line (`CLI.run`): level two from a terminal, with a shell's own `main` |
| `AllInOneIMEWire` | The wire protocol's engine side (`docs/wire-protocol-v1.md`): messages, frames, the server and the Composer's adapter, whatever carries them (the Windows shell's pipe, later Android's JNI and a C ABI) |
| `AllInOneIMETestSupport` | What a shell's tests share with the core's (`FakeEngine`, `ScriptFolder`, `Timing`, …) |
| `Strings` (plugin) | `swift package --allow-writing-to-package-directory strings [--check]`: the String Catalog in step with the code |

The package has no unsafe flags, so a shell can depend on it by URL. On macOS the shell weak-links FoundationModels
(`-weak_framework FoundationModels`; the core also imports it `@_weakLinked`) so that the app starts on macOS 14.

`AllInOneIMECore` has resources (`Sources/AllInOneIMECore/Resources/`: `RedactionWords.txt`, the English words the key
detector knows), which SwiftPM builds into a bundle beside the binary, `AllInOneIME-Core_AllInOneIMECore`. A shell
ships it with what it ships:

- on Apple's systems, `AllInOneIME-Core_AllInOneIMECore.bundle` in the app's `Contents/Resources` (the macOS
  Makefile's `app` puts it there, and fails without it), or beside a command-line tool;
- on Windows and Linux, the `AllInOneIME-Core_AllInOneIMECore.resources` folder beside the executable, or beside the
  DLL or `.so` the core is built into when another program loads it.

The core looks for it there itself (`CoreResources`) and doesn't stop without it, as `Bundle.module` would: it logs that
the words are missing and goes on knowing no English word, so with redaction on (`Config.redaction`) more ordinary
words are taken for a key and hidden from the AI.

## A text field's session

Each shell drives one `InputSession` (`Sources/AllInOneIMECore/Session/`) per text field: it hands it its events (keys
with what the field says around them, the focus, a click in the panel) and does what comes back (commit, the marked
text, the panel, a notice, open, copy …); the session's async work answers through a callback the shell hands back on
the session's thread. What the shell provides is `SessionServices`. How a shell drives it, and what the Windows engine
needs to: [docs/input-session.md](docs/input-session.md).

## Building and testing

```
swift build --build-tests     # macOS, Linux, Windows
swift test                    # the core's tests (the end-to-end ones run the input method: ALLINONEIME_TEST_BINARY)
Scripts/test.sh               # the same, offline, as CI runs them on Linux and macOS (off macOS it skips the few of what only Apple's Foundation does)
Scripts/check-core-portable.sh       # the core stays platform-neutral (imports, Platform/Apple/, no processes started)
Scripts/check-core-portable-test.sh  # the check's own tests
Scripts/check-core-standalone.sh     # nothing here reaches outside this folder
```

Off macOS the tests build against small stand-ins for what they import of Apple's (`Tests/LinuxShims`). On Windows
the tests that call POSIX directly are left out (`Package.swift`).

`Resources/Localizable.xcstrings` is the String Catalog of the core's interface text, keyed by the English text; a
shell has its own catalog for its own text and merges the two for its build (`swift package strings --merge OUT`).
`LanguagePacks/` holds the Korean and Hindi tables, `Plugins/` the plugins the tests check, `Examples/` an example
of every kind of extension.

## License

[FSL-1.1-ALv2](LICENSE), like AllInOneIME. Third-party components: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
