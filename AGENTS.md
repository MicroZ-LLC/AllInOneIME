# Rules for working on AllInOneIME

Every change follows these, whoever writes it: a person, Claude Code, Codex, Kiro, or the agent pipeline
(`.github/agent/`). Each rule has its reason; the ones marked **(checked)** are enforced by `make lint`, `make test` or
CI, so a change that breaks them doesn't merge. The rest are checked by the independent review on each PR
(`.github/review/prompt.md`). Changing a rule needs the owner's OK.

## Product

1. **One behaviour everywhere.** The same thing works the same way in every app, input, panel and platform (every
   candidate panel: first row chosen, ↑↓ move, Return/Tab insert, → or Esc give the keys back). A per-app, per-input,
   per-feature or per-platform difference needs the owner's OK: stop and ask, with the reason.
   *Why: users learn one product, not a list of exceptions.*
2. **Subtract.** No new `@` command, shortcut or setting without the owner's OK (an issue labelled for the pipeline
   that asks for one in so many words has it). Reuse an existing command, key or per-app setting; prefer learning from
   use (as "Use the selected text" is learned per app) over a new switch.
   *Why: small and instant, like Raycast; every setting is a question every user has to answer.*
3. **Fixed identity.** AllInOneIME is listed under English (U.S.) in Input Sources: in `Resources/Info.plist`
   `TISIntendedLanguage` stays `en`, `tsInputMethodCharacterRepertoireKey` starts with `Latn`, and the bundle and source
   IDs stay `com.allinoneime.inputmethod.AllInOneIME` **(checked: InputSourceGroupTests)**.
   *Why: macOS ties the input source and the permissions users granted to them.*
4. **Privacy.** Nothing leaves the Mac except what the user sent on purpose (the action key, a command), through the
   path README's Privacy section describes; a new kind of data going out, or a new place it goes, updates that section
   in both READMEs and needs the owner's OK. Nothing typed is logged.
   *Why: an input method sees everything a user types.*

## Code

5. **The core stays portable.** `Core/` builds on its own (no path above it), and `Core/Sources` imports no AppKit,
   UIKit or other Apple-only framework outside `Platform/Apple/` (wholly under `#if canImport`), starts processes only
   through the ProcessLauncher, and guards FoundationNetworking **(checked: `make lint`, `make test`'s iOS build)**.
   Logic goes in the core, with unit tests (Swift Testing). *Why: every platform shares the core.*
6. **Never block the main thread** on file or network I/O, a process (`waitUntilExit`), a semaphore, a sleep or
   `DispatchQueue.main.sync` **(checked for new calls: SwiftLint `blocking_call`)**. Where one runs on another thread,
   disable the rule on that line and say which thread. *Why: InputMethodKit calls in on the main thread; a wait there
   freezes typing in every app.*
7. **No crash shortcuts in shipped code** (`Sources/`, `Core/Sources/`): no `try!`, `as!`, force unwrap, `[unowned
   self]`, or empty `catch`/`if`/`else` (a comment inside saying why it's empty is fine) **(checked: SwiftLint)**. In
   tests use `throws` and `#require`. *Why: a crash in an input method takes the user's typing with it.*
8. **Small units.** New functions at most 60 lines of code, complexity 15, types 400 lines, files 400 lines of code
   (not counting comments and blank lines); a file over 400 today may not grow, so a change there moves code out first
   **(checked: SwiftLint, Scripts/check-ratchet.sh)**. *Why: what one reviewer can hold in their head.*
9. **Match the code around it**: naming, idiom, comment density (comments say why), Swift 6 strict concurrency. No
   style rules beyond that; no unrelated refactors, version bumps or reformatting in a change.
   *Why: reviewable diffs.*
10. **No secrets or private content**: no keys, tokens, certificates, personal data, internal hostnames, or anything
    specific to a company or a person's machine, in code, tests, docs or commits. Fake keys in tests are obviously fake
    (AWS's documented `…EXAMPLE` keys). *Why: the repository is public and its history is forever.*

## Tests

11. **Acceptance tests are the spec's.** Files under `Core/Tests/*/Acceptance/` and `Tests/*/Acceptance/` are written
    only by a separate agent (or person) from the issue's text; whoever implements the change never edits them (the
    pipeline puts them back). If one looks wrong, say so in the PR. *Why: the implementer can't grade their own work.*
12. **Tests are offline and free**: no network, no paid AI call, no real credentials. Stub the provider; `make test`
    points the AWS files at nothing **(checked: CI runs the tests with no keys)**. Live tests run only behind their
    `ALLINONEIME_*_LIVE=1` switch. *Why: CI runs on every PR; a real request costs money and flakes.*
13. **A test that passed before still passes** (`make test`). *Why: the pipeline merges without a person.*

## Text and docs

14. **Interface text in every language**: write `tr("中文", "English")`, then `make strings` for the other languages'
    catalogs **(checked: `make strings-check`)**. *Why: the interface ships in every language the catalogs list.*
15. **Every user-visible change gets a CHANGELOG line** in English (`CHANGELOG.md`) and Chinese (`CHANGELOG.zh-CN.md`),
    in the top `## X.Y.Z (unreleased)` section (added if missing) under Added/Changed/Fixed (新增/变更/修复), written like
    the entries around it: what the user sees and does, keys, commands and config names in backticks.
    README.md and README.zh-CN.md change where they describe it; English docs are English only. Leave `docs/readme/`
    (other languages) and the wiki: they're updated at release time. *Why: the changelog is the release notes.*

## Process

16. **Every change passes the same gate**: `make lint` (static checks) and `make test`, together `make check`, run by
    CI (`.github/workflows/quality.yml`) on every PR into `mainline` or `release-*`, plus the independent review.
    Nothing merges around them, the pipeline included. *Why: quality by machines, not memory.*
17. **Baselines only go down.** `.swiftlint.baseline.json` and `Scripts/oversized-files.txt` hold today's debt; after
    fixing some, `make lint-baseline` lowers them. A PR that raises them fails CI **(checked)**. *Why: a ratchet.*
18. **Commit messages** read like the repository's: `Area: what changed, as the user sees it`, plain English, no
    `feat:` prefix. Code, comments and commits are in English.
19. **Windows lives elsewhere**: the Windows shell moved, with its history, to MicroZ-LLC/AllInOneIME-Windows in
    0.7.5 (on hold); it builds on the core mirrored to MicroZ-LLC/AllInOneIME-Core at each release
    (`Scripts/mirror-core.sh`). Keep `Core/` standalone for it (rule 5).

## Bugs

20. **Every bug is reproduced first**, before any fix: a failing test (written by a separate agent where the rules
    above ask for one), or, for what a test can't reach (the window server, focus, keys, other apps), a scripted run
    on a real Mac that shows it, with the exact steps and what was seen. The fix is verified by the same reproduction
    now passing. A bug that can't be reproduced is reported as such, with what was tried; a fix is then only a
    defensive change plus the logging that would catch it next time, said so plainly. A GitHub issue for a bug that
    we (a person or an agent: a review, a bug hunt, the pipeline) found is opened only once it's verified real this
    way, with the reproduction in it; an unverified suspicion stays in the notes, not in the issue list.
    *Why: the owner, 2026-11-14: fixes made from a guess came back; a reproduction proves the cause and the fix; the
    issue list holds only real bugs.*
