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
| `AllInOneIMECore` | Everything else of the core; re-exports `AllInOneIMEText` |
| `AllInOneIMERime` | librime (local pinyin) behind the `PinyinEngine` protocol; macOS only for now. The headers are in `Sources/CRime/include`; the shell links the library (`-L`) |
| `AllInOneIMECLI` | The command line (`CLI.run`): level two from a terminal, with a shell's own `main` |
| `AllInOneIMETestSupport` | What a shell's tests share with the core's (`FakeEngine`, `ScriptFolder`, `Timing`, …) |
| `Strings` (plugin) | `swift package --allow-writing-to-package-directory strings [--check]`: the String Catalog in step with the code |

The package has no unsafe flags, so a shell can depend on it by URL. On macOS the shell weak-links FoundationModels
(`-weak_framework FoundationModels`; the core also imports it `@_weakLinked`) so that the app starts on macOS 14.

## Building and testing

```
swift build --build-tests     # macOS, Linux, Windows
swift test                    # the core's tests (the end-to-end ones run the input method: ALLINONEIME_TEST_BINARY)
Scripts/check-core-portable.sh       # the core stays platform-neutral (imports, Platform/Apple/, no processes started)
Scripts/check-core-portable-test.sh  # the check's own tests
```

Off macOS the tests build against small stand-ins for what they import of Apple's (`Tests/LinuxShims`). On Windows
the tests that call POSIX directly are left out (`Package.swift`).

`Resources/Localizable.xcstrings` is the String Catalog of the core's interface text, keyed by the English text; a
shell has its own catalog for its own text and merges the two for its build (`swift package strings --merge OUT`).
`LanguagePacks/` holds the Korean and Hindi tables, `Plugins/` the plugins the tests check, `Examples/` an example
of every kind of extension.

## License

[FSL-1.1-ALv2](LICENSE), like AllInOneIME. Third-party components: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
