<div align="center">

**English** · [简体中文](README.zh-CN.md) · [繁體中文](docs/readme/README_zh-TW.md) · [日本語](docs/readme/README_ja.md) · [한국어](docs/readme/README_ko.md) · [Français](docs/readme/README_fr.md) · [Deutsch](docs/readme/README_de.md) · [Español](docs/readme/README_es.md) · [Português (Brasil)](docs/readme/README_pt-BR.md) · [Italiano](docs/readme/README_it.md) · [Русский](docs/readme/README_ru.md) · [Tiếng Việt](docs/readme/README_vi.md) · [ไทย](docs/readme/README_th.md) · [Bahasa Indonesia](docs/readme/README_id.md) · [हिन्दी](docs/readme/README_hi.md) · [العربية](docs/readme/README_ar.md) · [Türkçe](docs/readme/README_tr.md)

<br>

<img src="Resources/AppIcon.png" width="112" alt="AllInOneIME icon">

# AllInOneIME

### AI commands in every text field on your Mac.

Type `@improve`, `@translate` or `@question` in any app, press ⏎, and pick the result.<br>
No copying into a chat window, no switching apps. Your own AI provider, your own keys.

[![Release](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#installation)
[![Apple silicon and Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#installation)
[![License: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](LICENSE)
[![Downloads](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[Download](https://allinoneime.com/download)** · **[Website](https://allinoneime.com)** · **[Docs](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[Extensions](docs/extensions.md)**

[How to use](#how-to-use) · [Commands](#-commands-beta) · [Your own commands](#your-own-commands) · [Languages](#input-and-translation) · [Voice](#voice-input) · [Installation](#installation) · [Privacy](#privacy)

<br>

<img src="docs/en/demo.png" width="820" alt="@translate and a sentence, then ⏎: a line in Spanish, French and German">

</div>

> [!NOTE]
> From 0.6.3 on, AllInOneIME is signed with a Developer ID and notarized by Apple: no more allowing it in System
> Settings → Privacy & Security. After updating from an earlier version, macOS asks once for your login password for
> each key AllInOneIME saved in the keychain: enter it and click "Always Allow". Download AllInOneIME only from
> [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) or [allinoneime.com](https://allinoneime.com).

A macOS input method with AI commands in every text field. Start a sentence with `@` and press ⏎ when done:
`@improve` polishes what you wrote and offers a few rewrites, `@translate` translates it into the languages you pick,
`@question` asks a question, `@claude` hands it to Claude Code, and `@open` finds files and apps or opens a web
address. You can also hold right ⌥ and talk. Without `@`, your keys go to the app as usual. It also types Chinese
(pinyin, built on Rime and rime-ice), French, Korean (Hangul) and Hindi (Devanagari from Latin letters), and runs
your own scripts as @ commands.

![@improve and a rough sentence, then ⏎: polished versions, plus rewrites](docs/en/improve.png)

For more detail (every command and setting, installation troubleshooting, privacy), see the
[Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Made by [Weijian Zhang](https://weijianz.com) at MicroZ LLC.

## How to use

Without `@`, it stays out of the way: in English, letters are typed directly and ⏎ is Return; nothing goes online.
A new install writes English; to type Chinese (pinyin), French, Korean or Hindi too, add it in the settings (see [Input and translation](#input-and-translation)).

| Key | What it does |
|---|---|
| Type pinyin, Space / digits | In Chinese mode: pick words, as in any pinyin input method |
| `@` (at the start of a sentence) | Opens the command list: the most used lately first, 5 at a time, scrolled with ↑↓, the wheel or the trackpad; or type letters to find one (a name typed in full first, then names starting with them, then names containing them). ⏎, Tab, Space or a digit chooses |
| ⏎ | Runs the command. Works even if the pinyin isn't picked yet: it's picked first, as with Space |
| Space, ⏎ / digits | Once the results are up: insert the highlighted / numbered one; 0 is the original. ⏎ inserts even with a follow-up half typed (it's dropped) |
| ⇧⏎ | With a follow-up typed after AI results: sends it (the next question of an `@question` conversation, or a refine). While a command is typed, or on AI results with nothing typed: inserts what you typed as is, `@command` included. On other results (`@open`, a reminder …) it inserts the highlighted row, as ⏎ does. On `@config` and `@doctor` results, with nothing typed, it does nothing |
| ⌘C | Copies the highlighted result (for `@open`, the path); the candidate panel stays open |
| ⌃V | In a command (e.g. after `@improve `): appends the clipboard text after what you've typed instead of pasting it into the app. Multiple lines become one, up to 2000 characters at a time (`@note` keeps the line breaks and takes up to 20000). Works in any app; without a command, the key goes to the app as usual |
| ⌘V | Like ⌃V, but some apps handle ⌘V themselves (terminals such as Ghostty, iTerm2 and Terminal, and Notes) and paste into the app as usual; use ⌃V there |
| Esc, ⌫ | Back to the sentence to keep editing; typing punctuation or digits after the results continues it. After a refine: back to the results before it |
| Letters, once AI results are up | A follow-up: after `@question` the next question (see [Conversations](#conversations-with-question-new)), after `@improve` or a prompt command an instruction such as `shorter` (see [Refining the results](#refining-the-results-new)); ⇧⏎ sends it. After `@translate` letters continue the sentence, and ⏎ translates it again |
| ⌘⏎, ⌘1–⌘5 | In an `@question` conversation: shows where to continue it (Claude Code, Claude, ChatGPT, Gemini, or copy it); ⌘1, ⌘2 … pick one |
| Click a row | In the candidate panel: picks it, as its digit would (a word, a command in the list, a result, an `@open` file, a recipient, an extension's row); the row under the pointer is highlighted. The text field keeps the focus |
| Tap Shift | With more than one input language: the next one, in their order (English → Chinese → French → …, then back to the first) |
| Hold right ⌥ | Talk, release to stop. In the language you're typing (English, Chinese, French, Korean or Hindi). In a command, the text goes after it; otherwise it's inserted directly |

## @ commands (beta)

| Command | What it does |
|---|---|
| `@improve` | Polish: 1–3 are three versions in the sentence's own language, 4 onward the rewrite styles (added and ordered in the settings), 0 is the original. No translation; with "@improve also translates" on, it works like `@translate @improve` |
| `@translate` | Translate into the languages you added (settings → Translate, drag to reorder), a line each, three versions with only one; the sentence's own language is skipped. `@translate @improve` together translates and rewrites in one request |
| `@question` | Ask a question; the answer appears in the candidates, ⏎ or Space inserts it, ⌘C copies it. Type on and ⇧⏎ asks a follow-up: the panel becomes a conversation of up to 5 rounds, then offers to continue in Claude or another AI. With nothing typed after it, it lists your last 5 questions, newest first; typing narrows them down (words anywhere in the question, any case, Chinese too). A digit, ↑↓ then ⏎, or a click shows a question's saved answer at once, offline, to insert or copy as usual; ⌘R there asks it again for a fresh answer. With no match, or nothing picked, ⏎ asks what you typed |
| `@claude` | Hands the task to Claude Code: in the background by default, with a notification when it's done (click it to open the session in Terminal and go on), or see `@tasks`. It uses your own Claude Code (the `claude` command) with its own sign-in and settings. Turn off "@claude runs in the background and notifies me" in the settings to open it in Terminal as before. The first time it opens Terminal, macOS asks whether AllInOneIME may control Terminal: click OK |
| `@tasks` | Lists the background Claude tasks (working / done / waiting for you) with their last replies; ⏎ opens one in Terminal, ⌘C copies the reply |
| `@settings` | Opens the settings window right away (picking it is enough) |
| `@config` | Changes settings as you describe them: `@config output languages English and French`, `@config use Chinese in WeChat`, `@config candidates in a column`. ⏎ shows the changes, old → new; ⏎ (or 1) applies them, Esc cancels, type more and press ⇧⏎ to refine them; ⌘Z or `@config undo` puts them back. See [Settings by describing them](#settings-by-describing-them-new) |
| `@doctor` | Checks your setup on this Mac and fixes what it safely can: ⏎ lists the results, problems first; a digit fixes that one, ⏎ the safe ones, through `@config`'s preview. `@doctor why doesn't translate work` also has the AI explain the likely cause. See [Checking your setup](#checking-your-setup-new) |
| `@open` | Lists matching files, folders and apps as you type (Spotlight). Several keywords work, separated by spaces: each must be in the path, at least one in the name (a standard folder's name counts for what's in it: `downloads pdf` finds the PDFs in Downloads). Apps and the standard folders are also found by their Chinese names, and a Chinese interface shows them that way. What you opened with `@open` comes first, then apps and those folders, then recently used or changed files; when the names find two files or fewer and no app or folder of those, the files in your home folder are searched by content too, those rows marked "content"; when there's nothing else, ⏎ lists them to pick from instead of opening the first. With a web address (`github.com`, `localhost:3000`, `https://…`), the first row is "open in the browser" and contents aren't searched; a file named exactly that (say `MANIFEST.in`) comes first. Text starting with `~/` or `/` is a path: Tab completes it and goes into folders; ⏎ opens, ⌘C copies the path |
| `@note` | Saves the text to the Notes app, in a folder named AllInOneIME (made when missing); nothing is inserted. Pasted text keeps its line breaks, up to 20000 characters |
| `@reminder` | Adds a reminder to the Reminders app, in a list named AllInOneIME. Write the time in the text; it's read on the Mac, and a row shows what was read: ⏎ or Space adds it, Esc goes back to edit. With a time, it has an alarm then; with only a date, it's all day |
| `@calculate` | Calculates on this Mac; the result appears in the candidates, ⏎ or Space inserts it: `@calculate 23*17` → `391`. It also works inside a sentence: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Runs a line of Python (the Mac's `python3`) and inserts the result: the value of the code's last expression, e.g. `@py 2**100`, `@py import math; math.sqrt(2)`, or else what it printed. Not offered without `python3` (Xcode's command line tools have it) |
| `@js` | Runs a line of JavaScript and inserts the same: the value of the last expression or what `console.log` printed, e.g. `@js [1, 2, 3].map(x => x * 2)`. It uses macOS's built-in JavaScriptCore, so there's nothing to install; it can't read files, reach the network or run other programs |
| `@reportissue` | Reports a problem: opens GitHub's page for a new issue in your browser, what you typed after the command as its title, and "What happened / What you expected" to fill in. It adds the app and macOS versions, your Mac's architecture, the interface and input languages, the installed language packs, which kind of AI provider (and the model, if it's a public one; otherwise "custom"), the action key, and how many custom commands, plugins and extensions you have, never their names, your text, paths or keys. ⏎ (or your action key) first shows all of it in the candidate panel; ⏎ again, or a click on the row, opens the page, where you read it and click Submit (with your GitHub account); Esc goes back. Also in the input menu ("Report an Issue…") and Settings → About |
| `@imessage` | Sends an iMessage: type a name, a phone number or an email (a Chinese name also by its pinyin, in full or the initials) and pick the recipient in the candidate panel (the ones you messaged lately come first; a full number or address works too), then write the message (commands inside it such as `@stock AAPL` run first). ⏎ shows "Send to Alex (…): message" in the panel, ⏎ again sends it, Esc goes back to editing; nothing is typed into the text field. The first time, macOS asks whether AllInOneIME may access Contacts and control Messages: click OK for both |

Example: `@q` ⏎, type `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ saves a note.
`@reminder call Bob tomorrow at 3pm` ⏎, check the time it read, then ⏎ again to add it. Once the command is chosen, you can also hold right ⌥
and talk. In Chinese mode, `@open` and `@calculate` switch to English letters for the moment and go back to Chinese when you're done.

The code for `@py` and `@js` is typed in English letters, and full-width punctuation (from Chinese mode) becomes ASCII; write it on one line, with `;` between statements.
It runs in a separate process, stopped after 10 seconds or with Esc at any time; on an error, the error's first line is shown, e.g. `ZeroDivisionError: division by zero`.
Output with several lines is inserted as printed; in a terminal it goes in as one line (a terminal runs every line it is given).
A terminal inside an editor (VS Code, Cursor, JetBrains) can't be told apart from the editor itself, so there any command's output with several lines goes in as it is.
Both also work inside another command's sentence: `@reply the answer is @py 2**100`; put code with spaces in quotes: `@question explain @py "sum(x * x for x in range(10))"`.
Not the other way round: the code of `@py` and `@js` always runs exactly as you typed it, and `@commands` in it don't run first.

![Typing @ opens the command list; @question plus a question, then ⏎ for the answer](docs/en/commands.png)

![@open finds apps as you type; starting with /, it's a path: the folder is listed, Tab completes](docs/en/open.png)

When `@` isn't followed by a command, as in `@john`, the `@` is inserted as usual, so @-mentioning
people in chat apps still works.
`@question`, `@improve` and `@translate` send to your own Bedrock only when you press the action key; `@open` searches only on this
Mac; `@note` and `@reminder` go only to Notes and Reminders on this Mac; `@claude` uses the Claude Code installed on your Mac (the `claude` command) and its own account, and it asks you
first, as usual, before changing files or running commands. Without Claude Code installed, `@claude` isn't offered.
`@imessage` reads Contacts on this Mac only (names, phone numbers, emails), never goes through the AI, and Messages sends
the message; without the Messages app it isn't offered.

`@calculate` works on this Mac, offline: `+ - * /` (also `× ÷`), `^` or `**` for powers, parentheses, percent (`50%` is 0.5,
`200*5%` is 10; as on a calculator, a percentage added or subtracted is of what comes before: `100+10%` is 110,
`100-10%` is 90), the functions `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` is base 10, angles
are radians, `round(x, 2)` keeps two decimals) and the constants `pi` (`π`) and `e`. Full-width digits and signs work too. Arithmetic is exact in decimal, so `0.1+0.2` is `0.3`; results have at most 15 significant digits, and
whole numbers of up to 38 digits are written out in full (`2^100` → `1267650600228229401496703205376`).

### On the selected text (new)

Select some text in any app (a sentence in Notes, a paragraph in Mail), type `@improve`, `@translate`, `@question`
or another command that takes text, and press ⏎: the command works on the selection, and the result you pick replaces
it. The selection stays as it is, selected, while you type: the command is written in the candidate panel, whose first
line is what you type and the next "On the selection: “…” (N characters)". Esc, ⇧⏎ or clicking elsewhere leave the text
as it was; so does a selection you change meanwhile, which cancels the command. Text typed after the command is an
instruction for `@improve` and `@translate` (`@translate ja`, `@improve more formal`) and the question for `@question`
(`@question what does this mean`), about the selection. `@open`, `@claude`, `@tasks`, `@settings`, `@reminder`,
`@imessage`, `@reportissue`, terminal commands and script extensions don't use it: they take what you type, and the
selection stays as it is. Up to 5000 characters; never read during secure input or in a
terminal. Turn it off under Settings → General → "Use the selected text" if it misbehaves in an app.

### Refining the results (new)

While the results of `@improve`, a prompt command (your own or a plugin's) or the rewrite of a selection are up, type
what to change, such as `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese` or `用更口语的说法` (pinyin works,
and a tap of Shift switches languages), and press ⇧⏎: the results go to the AI again with your instruction, and the new
ones replace them in the same panel. ⏎ inserts the selected result, also with an instruction half typed (it's dropped).
Refine again as often as you like; the panel's top line lists the steps ("Refined: shorter · more formal"), and you can
pick a row at any time as usual. A letter starts the instruction (shown as "refine › …" at the top of the panel); while
it's empty, digits, Space and ⏎ pick as before, and ⇧⏎ inserts what you typed as is. Refining starts once the results are
complete: typing while the first results still stream in continues the sentence, as before. While a refine runs you can
already type the next instruction; the refine goes on, and ⇧⏎ runs the next one once its results are in. Esc clears the
instruction, then goes back one step to the results before the last refine (during a refine: stops it), then back to the
sentence; ⌫ on an empty line steps back the same way. On selected text, the result you pick still replaces
exactly the selection, which stays untouched until then. A refine that fails (or is refused during secure input) leaves
the results as they were, its instruction ready for ⇧⏎ to try again. The same refine of the same results is answered from
the cache. `@translate` has no refine: typing after its results continues the sentence, and ⏎ translates it again.

### Conversations with @question (new)

Once `@question` has answered, what you type is the next question: ⇧⏎ asks it, with the questions and answers so far,
and the panel grows into the conversation, the earlier rounds dimmed as Q / A rows, the latest answer below them. The
line on top says which round comes next ("question 2/5 › …"). Every answer can be inserted: its digit (1–5), ↑↓ then ⏎, or
a click; the latest is selected, and ⌘C copies the selected one. ⏎ inserts it even with a question half typed (it's
dropped). Esc clears what you typed, then goes back one round; at the first, it leaves as before. The panel grows to
about half the screen, then scrolls, the latest at the bottom.

After 5 rounds (`questionRounds` in the config, 2–10) the next question's line becomes "5 rounds in: continue in Claude
or another AI", with the choices numbered ⌘1, ⌘2 …; ⌘⏎ shows them at any round (while an answer is still coming in it
does nothing, and never reaches the app). What you type then is the first message there; only ⌘1, ⌘2 … send it (⇧⏎
asks nothing more, and opens nothing). A question about selected text takes that text along, quoted as a block of its
own. The choices:

- **Claude Code**, when the `claude` command is installed: an interactive session in Terminal, starting with the
  conversation and "Let's continue this discussion".
- **Claude** or **ChatGPT** on the web, the conversation filled in (a long one goes on the clipboard: paste it).
- **Gemini** on the web, the conversation on the clipboard to paste.
- **Copy the conversation**, in Markdown (**Q:** / **A:**).

Which ones, and in which order (the first is the default): Settings → General → "Continue a conversation in"
(`questionContinueIn` in the config). With Apple Intelligence on this Mac a long conversation doesn't fit its small context:
the oldest answers are shortened, then the oldest rounds left out, and the panel says "earlier rounds shortened". A
conversation is saved under its first question in the recent questions, and picking it shows the rounds to go on with.

### Recent questions (new)

`@question` with nothing typed after it lists your last 5 questions, newest first, with when they were asked ("3 hours
ago"). Typing narrows them down: every word anywhere in the question, in any case (Chinese without spaces too). A digit,
↑↓ then ⏎, or a click shows a question's saved answer at once, without going online: Space or ⏎ inserts it, ⌘C copies
it, ⌘R asks it again for a fresh answer (a conversation: its latest question), Esc goes back to the list. A saved
conversation shows all its rounds: type to go on with it. With no match, or nothing picked, ⏎ asks what you typed. A new answer to the same question, or a conversation
that goes on, replaces the saved one.

- They're kept only on this Mac (see Privacy): not while secure input is on, and never for questions on selected text.
- Settings → General → "Remember recent questions" turns it off (`rememberQuestions` in the config); turned off there,
  it deletes them too. Turned off through `@config`, they're kept, so that undoing it puts back exactly what was (its
  preview says so); "Clear (N)" deletes them.

### Notes and reminders

`@note` makes a new note; its first line is the title. After copying some text, ⌃V after `@note ` (or ⌘V, outside terminals) saves it with its line breaks, shown as ↵ in the command.
If you leave the text field (click elsewhere, switch apps) or press ⇧⏎ (insert as typed) before a note with line breaks is saved, it isn't typed into the app (in a terminal, each line would run as a command): it goes on the clipboard instead ("The note wasn't saved; its text is on the clipboard"). A note of one line is inserted as typed.

`@reminder` reads times like `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (its 1st), `end of the year` (Chinese times too).
The day and the time can be apart (`tomorrow call Bob at 5`); weeks start on Monday.
A time without am or pm (`at 5`) is the next one, never between midnight and 6 a.m.; a time already past today is tomorrow, but a part of the day still going (`this afternoon`, `tonight`) is today, all day; a date already past this year is next year's.
Written to repeat (`standup every Monday at 9`), it is added once, for the next time: the words stay in the title and the row says "once only".
The row to confirm shows the time it read, e.g. "tomorrow 3:00 PM" (following the Mac's 12/24-hour setting); if it's wrong, Esc goes back to the text. With no time or date in it, it has none ("no date").

`@stock` and the like inside these two aren't run: the text is saved as written (typing `@` there doesn't open the command list). The first time, macOS asks whether AllInOneIME may control Notes (`@note`) or access Reminders (`@reminder`): allow it.
If you didn't, allow AllInOneIME in System Settings → Privacy & Security → Automation (Notes) or → Reminders.
When a save fails (no permission, say), the notice says why and the text comes back into the command, to fix and send again; when you have to fix something first (a permission, an account), it's also put on the clipboard (going to System Settings takes the focus from the text field). If you've moved to another text field or are typing something else, it goes on the clipboard instead ("Not saved; the text is on the clipboard.").

### Your own commands

In the settings, under "Custom @ Commands", click "Add Command…": give it a name and choose what it does (an AI
instruction, a program, a program in Terminal, or a web page), or start from an example. Your commands come after the built-in
ones; names are English letters only and can't be a built-in command's; they work from the next sentence.
They're kept in `customCommands` in the config file (`~/.config/allinoneime/config.json`), which you can also edit:

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | What it does |
|---|---|
| `prompt` | Goes to the AI with `prompt` as its instruction; the answer appears in the candidates, to insert or copy (⌘C) |
| `run` | Runs `argv` in the background; what it prints appears in the candidates (several lines are inserted as printed, in a terminal as one line). On an error, its last line is shown |
| `terminal` | Runs `argv` in a new Terminal window; nothing is inserted |
| `link` | Puts the text into the web address `url` and opens it in the default browser; nothing is inserted |

- `{input}` becomes what you wrote after the command, and it always stays within the one argument it's in: no shell is involved. For a shell, say so, like `sh` above (`zsh -c`).
- `stdin`: what goes to the program's standard input, with `{input}` replaced too.
- A `link`'s `url` must be `https://`, with `{input}` once, after the `?` or `#`; the text is encoded (a space is `%20`, a newline `%0A`), 4000 characters at most.
- `run` and `terminal` type English letters by default (like `@open`; in Chinese mode, Chinese comes back after), and full-width punctuation becomes ASCII. Set `"ascii": false` to keep text as typed.
- Programs run in your home folder with your login shell's PATH (so Homebrew, pyenv and nvm installs are found). `run` stops a program after 10 seconds (`timeoutSeconds`) or when it prints too much; Esc stops it at any time.
- `summary` is the description in the command list (optional).
- When the program in `argv` isn't found (say, no `python3`), the command isn't offered and `@python …` is inserted as text; once it's installed, the command appears in the next text field.

`run` and `terminal` run code on your Mac: only add commands you wrote and trust. They, too, run only when you press the action key, and never during secure input.

### Script extensions

Add your own @ commands as programs: a script in any language (bash, Python, Node, Swift, …) with a few lines of
metadata in its comments. Put it in `~/.config/allinoneime/extensions`, or in a folder you add under Settings →
Custom Commands → Script Extensions. Raycast Script Commands work as they are, and folders that already hold them are
found with Spotlight.

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh` is `@flights`. Write its arguments after it, commas between: `@flights beijing, new york` runs it with
`beijing` and `new york` as `$1` and `$2` (more commas stay in the last one); a required one left empty says what's
missing instead of running. What it prints is used as its `output` says:

| `output` | What happens |
|---|---|
| `insert` (default) | All of it, and each line, to insert |
| `show` | Shown in the panel as it prints (progress); nothing inserted. Leave the field and it goes on in the background (up to four at once) |
| `list` | A list in Alfred's Script Filter JSON, run again as you type; picking a row inserts, opens (a web address, file or folder; never something that would run), copies or runs a second step |
| `silent` | Its last line near the cursor; nothing inserted |

A command can also take no input (`input none`: ⏎ on its name runs it), run in the `background` and notify you when
it's done (the menu bar panel lists it meanwhile), show a `status` beside its name in the command list, or ask first
(`confirm`). It runs in its own folder with your login shell's PATH and `ALLINONEIME_*` variables: the interface and
input language, the app you're typing in, the text. A **bundle** is a folder with an `extension.json` naming its
commands: they share code and preferences, which Settings shows (passwords go to the keychain). Settings lists every
command with a switch, and the scripts left out with why.

Raycast's modes map as `fullOutput` → `show`, `compact` and `silent` → `silent`, `inline` with `refreshTime` → a
status. The whole protocol is in [docs/extensions.md](docs/extensions.md); [Examples/extensions](Examples/extensions)
has one of each kind. Extensions run code on your Mac: use ones you trust. They run only when you run them (a status
or a list as you type it), never during secure input, and stop when the input method quits.

#### Extension sources (new)

A bundle can come from a Git repository, yours or your team's, and stay up to date from there. Settings → Custom
Commands → Extension Sources → **Add from Link…**: paste the repository's address (`git@github.com:you/my-extensions.git`,
`ssh://…`, `https://…`; optionally a branch, the bundle's folder in the repository, and a tag or commit to pin it to).
AllInOneIME clones it with **your own git and SSH setup** (keys, agent, ~/.ssh/config, credential helpers), so a
private repository works as it does in Terminal; the app never asks for or stores a password. The clone goes into
`~/Library/Application Support/AllInOneIME/Sources/`: first into a hidden staging folder, never straight into an
extensions folder. (Don't put a name, password or token in an https address: git's credential helper keeps them.)

- **Review first.** Before anything loads you see the bundle, every command (name, title, description, output), the
  programs they run, its preferences, and the commit, under the warning "This source isn't signed: it will run
  programs from <address>". Only **Enable** adds it; Cancel deletes the clone. You review a source once.
- **Updates are yours to apply.** Once a day (and soon after the input method starts) a source is fetched to see what's
  new: Settings shows "N updates" with the commits (subject, author, date) and a badge on the page. Nothing changes
  until you click **Update**, which only fast-forwards and runs no hooks. A force push makes the source need a review
  again: **Re-clone** shows it, and only Enable puts the rewritten history in place (until then the reviewed version
  keeps working).
  A source pinned to a tag or commit isn't checked. Turn the daily check off per source (`autoCheck`).
- **Errors** are git's own words, with "This uses your own git and SSH setup; check that `git ls-remote <url>` works in
  Terminal", and your own reminder under it if you set one (`authHint` in the config).
- **Remove** moves the clone to the Trash; the bundle's preferences are kept for next time.
- From a terminal: `AllInOneIME --add-source <url> [--path …] [--branch …] [--pin …]` (prints the review and enables
  it; again after a force push), `--update-sources` (fast-forwards every reviewed source that isn't pinned),
  `--list-extensions` (on `~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME`).
- Only reviewed code loads: a source folder in the load list that wasn't reviewed on this Mac (a copied config) is left
  out. git never waits for an answer: no terminal and no prompts, so an unknown host key or a password prompt fails at once.

The config keeps them as `extensionSources`; the repository layout is in [docs/extensions.md](docs/extensions.md#10-extension-sources).

### Plugins

Plugins are ready-made `@` commands for things not everyone needs, like `@stock AAPL 600519 700` for stock quotes.
Installed, they work like any command; "Plugins" in the settings shows what's installed and where each sends your text,
and removes them. Plugins are JavaScript run in a separate process: they can reach only the websites they declare
(HTTPS), and can't read files or run other programs. "Browse Library…" under Plugins in the settings installs them
from the [plugin library](https://github.com/MicroZ-LLC/AllInOneIME-plugins): it shows which websites a plugin
contacts before installing; the library's index is signed and every file must match it. A newer version shows an
"Update" button; nothing updates by itself. Your own plugins go in `~/.config/allinoneime/plugins/` ("Open Plugins
Folder"): local plugins, never overwritten by the library.
"Link" plugins run no code: they put the text into a web address and open it in the browser, like `@x nice weather
today`, which opens X's composer with the text filled in; posting is up to you on the page. The library has four
(`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` converts currencies: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, one line
with the date of the rate (rates by ExchangeRate-API). Writing one: [docs/plugins.md](docs/plugins.md).

Commands that fetch something (plugins and programs) also work inside a sentence: `@reply tell her @stock AAPL is up today`.
The inner ones run first, their output takes their place, and the outer command works on the result. The argument is
the word after the command, plus the uppercase codes or numbers right after it (`@stock AAPL TSLA`, `@stock 600519 700`);
a lowercase word ends it (`@stock SNDK is good to buy` looks up SNDK). Quotes mark it exactly: `@stock "aapl tsla"`.
`@calculate` works inside a sentence too; its argument is the whole expression after it, spaces included, up to other text:
`@reply the total is @calculate 23 * 17 dollars`.
Inside `@claude` and terminal commands they aren't run: those get the text as written (typing `@` there doesn't open the command list).

### Action key

⏎ by default; change it under "Action key" in the settings (`actionKey` in the config): ⏎, Tap ⌥ (either side: press
and let go right away; holding right ⌥ is still for talking), ⌥Space, or Space (press Space once more after the words
are picked; twice in English mode).
Whatever the action key, @ commands also run on ⏎. If ⌥Space is already a shortcut for Alfred, Raycast or the like,
they get it first.

### Typing results out

Turn on "Type results out" under Settings → General (`typeOut` in the config) and a command's result is typed into the
app character by character, like a person typing, instead of going in at once; pinyin picks still go in at once. The
slider sets the pace, from 6 seconds a character to 40 a second (`typeOutRate`), and "Speed up and slow down (like a
person)" types in bursts of changing pace (`typeOutVaries`). Esc stops it where it is; any other key types the rest at
once.

"Make occasional typos and fix them" (`typeOutMistakes`) makes it look even more like a person: now and then the key
next to the right one, noticed up to three letters later, deleted and typed again; a letter or a space typed twice and
deleted; or a short word typed, deleted and typed again. A few in 100 characters, never two close together, and never
at the start of a line. In code, web and email addresses and numbers, a typo is only a wrong letter or digit, fixed at
once (never a wrong bracket, quote or space, which editors pair or indent on). The wrong letters are neighbors on your
keyboard layout (QWERTY, AZERTY, QWERTZ…). Chinese, Japanese and Korean only hesitate (two characters typed, deleted
and typed again), never with a wrong character.

In a field that takes typos back (Apple's text views such as TextEdit and Notes, browsers, most editors): typed to
the end, or with another key pressed to type the rest at once, the text is exactly the result; Esc (or leaving the
field) in the middle of a typo takes the typo out first, so the field holds an exact start of the result. If the
cursor moves while a typo shows (a click), the typo is taken out where it was and the rest is typed without typos.

Typos are never made in terminals, nor in apps that don't tell the input method where the cursor is. Each time, the
first typo is a plain one (a wrong letter, corrected in one go), until the field has shown it takes a typo back; while a
typo shows, the input method checks before every key that the field holds what it typed. A field that ignores where
to replace text can't take a typo back: there that first typo stays, so the text ends up one character off (also
after Esc or another key), and the app gets no typos again. Settings → General lists those apps under the typos
switch; "Forget apps where typos couldn't be fixed" lets them try again.

### Per-app settings (new)

Settings → Apps gives an app settings of its own, each optional; what an app doesn't set follows the settings for every app:

| Setting | For example | In the config |
| --- | --- | --- |
| The input language its text fields start in | Slack in English, WeChat in pinyin | `inputLanguage` |
| The rewrite styles `@improve` offers there | Mail formal and tactful, Slack casual | `rewriteStyles` |
| Type results out, or not | on in a chat app, off in Mail | `typeOut` |
| No AI in this app | `@improve`, `@translate`, `@question`, `@claude` and your prompt commands send nothing there and say so; typing and the other commands work | `noAI` |

"Add App…" lists the apps you typed in lately, or picks one in /Applications. The input menu's "This App: <name>" has
quick switches for the app you're typing in (No AI, Type Results Out, the language it starts in). In the config they're
under `appProfiles`, by bundle ID:
`"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`.
Bundle IDs match ignoring case (`com.apple.Mail` is Mail's `com.apple.mail`). `@reportissue` counts the apps that set
something, never naming them.

- The starting language works like the default input language: a text field takes it when it becomes active, and a
  Shift switch then sticks for that app's fields until the setting changes.
- With No AI, the AI commands stay in the @ list; running one shows the notice and keeps what you wrote. Your own
  terminal commands (`"type": "terminal"`) run programs, not the AI, so they still work there.

### Settings by describing them (new)

`@config` turns a sentence into settings: `@config output languages English and French`, `@config 微信里用中文，邮件里语气正式一点`,
`@config candidates in a column`, `@config turn off the typos`, `@config use Claude`. ⏎ shows the changes in the candidate
panel, a row each, old → new, with the labels Settings uses ("Translation languages: English, Japanese → English, French",
"Apps · WeChat · Starts in: Same as everywhere → Chinese"); nothing is changed or typed yet. ⏎ (or 1) applies them all, Esc
cancels, and typing more then ⇧⏎ refines the proposal ("also German"; ⇧⏎ with nothing typed does nothing, and
⏎ applies the proposal shown). Once applied, ⌘Z while the confirmation is up, or
`@config undo` within the next 10 minutes, puts back exactly the values those settings had.

- **What it can change:** the translation and input languages (and the default one), the rewrite styles, the candidate
  layout, typing results out (on/off, speed, speeding up and slowing down, typos), using the selection, remembering
  questions, hiding sensitive information (on/off, what is hidden, words to add), checking for updates, per-app settings
  (an app named as you call it, found among your apps by name or bundle ID), and the AI provider: which one, the Bedrock
  profile (from `~/.aws`) and region, a model the app knows for it, and an OpenAI-compatible base URL (`https://` only).
- **What it never touches:** API keys and anything in the keychain, custom commands, extension folders and sources,
  plugins, the jargon list, anything that runs programs, and every other setting. Those rows are refused, with the
  reason, and the rest can still be applied.
- **Checked like Settings:** a language that isn't one, more than 5 translation languages, a value out of range, an app
  it can't tell, or a language whose pack isn't installed ("needs the Korean language pack: download it in Settings →
  Input") is refused row by row; an invalid config is never written.
- **Keys:** it never switches to a provider that has no key (none in the keychain or your shell): the row says "Gemini
  API needs an API key: ⏎ opens Settings to add it (never sent to the AI); you can switch to it there", and applying
  opens Settings → AI Provider with a small sheet for that key (Save, or Save and Use to switch to it), while the other
  rows still apply. With a key, the provider switches, Test Connection runs and its result shows under the confirmation.
  A key typed into the sentence is dropped before anything is sent.
- **On this Mac first:** it uses Apple Intelligence whenever this Mac has it (macOS 26), whatever provider you chose and
  even before one is set up, held to the allowed settings and values, with lookups for your apps, AWS profiles and
  language packs. Without it, your provider answers. The request holds only the allowed settings and their current
  values (never a key, nor the words you hide), and hiding sensitive information applies as for any request.

### Checking your setup (new)

`@doctor` ⏎ checks the setup on this Mac in a second or two (the connection test shows while it runs) and lists the
results in the candidate panel, a row each, ✗ problems first, then ⚠ warnings, then ✓ what is fine, each with a short
fix: the input method (installed, enabled, in your input sources), the AI provider (its key saved or the Bedrock profile's
credentials found, never read or shown; Test Connection; Apple Intelligence), the permissions (Accessibility, the
microphone if you dictate, controlling Notes, Reminders, Terminal and Messages, asked of macOS without a prompt), secure
input, the language packs of your input languages, `config.json` (readable, unknown keys, values out of range, a language
twice, more than 5 translation languages), extensions and plugins that didn't load, updates, and recent errors in the
app's own logs.

The rows with a fix are numbered: a digit (or a click) shows what it does in `@config`'s preview, and ⏎ applies it; ⏎ on
the list fixes all the safe ones at once (settings repaired, repeated languages removed, the input method enabled again).
Opening a System Settings pane, downloading a language pack, Check for Updates (it opens Settings) and Settings' key
field are picked one by one. Settings
changes undo like `@config`'s (⌘Z, `@config undo`). No fix deletes your data or touches a key.

`@doctor <question>` (`@doctor why doesn't translate work`) runs the checks, then the AI explains the likely cause from
their results and marks the fixes it suggests (⏎ still applies only the safe ones; the others by their number). In an
app with No AI the checks still run and only the question is refused. On Apple Intelligence when this Mac has it, which calls the checks
it needs as tools; otherwise your provider, and the panel says so. Only the check results (no paths beyond `~`, no keys,
none of your text) and your question are sent; the checks send nothing except the Test Connection request (only when
the provider has a key or credentials to test).

## Menu bar panel

<img src="docs/en/panel-swipe.png" width="520" alt="The menu bar panel: frosted glass, with notes, reminders and Claude tasks on cards; a row swiped left shows its Remove button">

Click AllInOneIME's icon in the menu bar (the ∞-and-cursor mark, without a box; the boxed one is the input source) and the panel drops down under it; a click elsewhere closes it:

- Notes: the notes saved with `@note`, the newest 5; click one to open it in Notes.
- Reminders: the reminders not done yet in the AllInOneIME list of Reminders (`@reminder` adds to that list), the soonest due first, 8 shown; click the circle to tick one off, or the title to open Reminders.
- Claude Tasks: like `@tasks`, the background Claude tasks (what `@claude` hands off), up to 30, 5 shown at a time: scroll for more, or search their titles and replies in the search box; with their progress and the first line of the last reply; click one to open it in Terminal and go on.

Swipe a row (a note, a reminder or a task) to the left with two fingers to show its Remove button, or all the way to remove it at once; with a mouse, right-click it. Removing only takes it off the panel: the note stays in Notes, the reminder in Reminders (not completed), the task in Claude Code.

The header has the counts (like "2 reminders · 1 task running"; tasks waiting for you are counted apart, like "1 waiting for you") and a refresh button.
It never takes the focus from the app you're typing in: ticking off a reminder or refreshing leaves that app in front; only the Claude tasks' search box, once clicked, takes the keyboard.
The icon is shown by default; turn it off under "Menu Bar Panel" in the settings.

What it reads, and when:

- Notes: the list is the panel's own record (kept while it's closed too), and Notes is never launched: only when Notes is running already, and AllInOneIME was allowed to control it before, does the panel check it for edited titles and deleted notes.
- Reminders: the AllInOneIME list is read when the panel drops down, every 60 seconds and when reminders change. The panel never makes macOS ask for access by itself: if macOS hasn't asked you yet, it shows "Allow Access to Reminders", and only that button asks; if you said no, it shows "Open System Settings".
- Claude tasks: the panel runs `claude agents` only while it's down: once when it drops down, on Refresh, and when `@claude` hands off a task; and every 15 seconds while a task isn't done yet, no longer once they're all done. The last replies are read from the end of Claude Code's transcripts on this Mac (`~/.claude/projects`), and only when a transcript has changed.
- While it's closed, none of this runs; it only keeps a record of the notes `@note` saves.

## Input and translation

In the settings:

- **Input languages**: one to five of English, Chinese (pinyin), French, Korean and Hindi, added with + (always there; greyed out at five). A new install starts with English only. New text fields start in the first; tap Shift for the next, in their order; with one, Shift doesn't switch.
  - **French** types with its own keyboard layout: AZERTY unless you pick another on its card. Its dead keys (^, ¨, `, ´, ~) compose from it too.
  - **Korean** types Hangul in the 2-set (Dubeolsik) layout, each syllable put together as you type (g k s → 한); Shift gives ㄲ ㄸ ㅃ ㅆ ㅉ and ㅒ ㅖ.
  - **Hindi**: type the words as they sound in Latin letters and get Devanagari (namaste → नमस्ते). Common words are spelled as Hindi writes them; otherwise Space inserts the first spelling, a digit another, ⏎ the letters as typed, and "." the danda (।).
  - A command's name, `@open`'s text and code (`@py`, `@js`) are typed in letters whatever the language; it comes back after the command.
  - `@improve` keeps a Korean, Hindi or French sentence in its own language, and `@translate` translates it into your languages (French is told apart from English when it's one of your input languages).
- **Language packs**: the app comes with English (and French, which needs only macOS's layout). Chinese, Korean and Hindi are packs you download when you add them: adding Chinese (pinyin) downloads its dictionaries (about 34 MB, 125 MB unpacked) with a progress bar, and pinyin works as soon as it's done, without a restart; Korean's pack (its key table and how jamo make syllables) and Hindi's (its letters and common words) are a few kilobytes. A pack is data only (dictionaries, tables and schemas, never code), listed in a signed index and checked against its SHA-256 before it's used, like plugins. Each language's card shows its pack (version, size, where it came from) with Delete…, and removing the language offers to delete its pack. Updating from 0.6.1 or earlier keeps Chinese without a download: the installer keeps the dictionaries the old version came with.
- **Candidate layout**: for picking words, pinyin and Hindi candidates are side by side by default (Horizontal), like the system's own input methods: ← → choose and ↑↓ (or - =) turn the page. Choose Vertical on the Input page, under the input languages, for one under the other (↑↓ choose). The @ command list and the results are always vertical.
- **Fuzzy pinyin** (with Chinese input): sounds you don't tell apart typed either way, e.g. z ↔ zh, n ↔ l, in ↔ ing. On the Input page, pick Chinese (pinyin) in the bar of input languages, turn on "Fuzzy pinyin" and pick the pairs; the dictionaries are deployed again in a second or two. It writes `rime_ice.custom.yaml` in the Rime user folder, and never over a file of your own there.
- **Translate (@translate)**: add the languages to translate into (Spanish, French, German, Japanese, Korean, Chinese, Hindi, Bengali, Tamil and the other main Indian languages…) and drag them into order. Hindi typed in Latin letters ("aap kaise ho") comes back in Devanagari. `@translate` writes a line in each, in this order (three versions with only one); the sentence's own language is skipped. A new install translates into the first language in your Mac's preferred languages that isn't English; with English alone, `@translate` opens this page to add one.
- **Keyboard layouts**: French types with the layout picked on its card (`keyboardLayouts` in the config). For the other languages, under the input method macOS keeps your last Latin layout (AZERTY, QWERTZ, Spanish, US International…), so you type as usual, `@` included wherever your layout has it, and dead keys compose in a command's text too (⌥E then E → é, ^ then e → ê). Layouts without Latin letters (Russian, Hindi InScript) can't be used under an input method: switch to them with ⌃Space, or paste (⌃V) or dictate text into a command.
- `@improve` polishes and rewrites without translating; `@translate @improve` together translates and rewrites in one request. Turn on "@improve also translates" in the settings to make `@improve` always do that.

## Rewrite styles

After lines 1–3 come the rewrites, **in the language you typed**: English rewrites for English, Chinese rewrites for Chinese. Pick any of them in the settings:

- Polish: same tone, more natural
- Concise
- Formal: for managers and clients
- Casual
- Tactful
- Jargon: Amazon-speak in English (bandwidth, circle back…), big-tech jargon in Chinese. Bad news is played down, e.g. "this is a blocker bug" → "Oh! Looks like your team has the bandwidth to fix this minor issue!"

Rewrites that only change punctuation or repeat another line aren't shown.

### Jargon list (your own terms)

Jargon has no built-in term list. You can prepare your own (for example, the phrases your team uses), and the model
prefers its terms. In the candidates, the Jargon line notes what the terms it used mean.

The list is a text file with one term per line, optionally followed by its meaning, separated by "=", a colon or a
Tab (you can copy two columns from a spreadsheet and paste them). Lines starting with `#` are comments:

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

Under "Rewrite Styles → Jargon list" in the settings, click "New" to create an empty list at `~/.config/allinoneime/jargon.txt` and open it;
if you already have a list file, click "Choose File…" to use it where it is (`jargonFile` in the config). Changes apply right away.
Only the first 150 terms are read. With "Jargon" checked, the list is sent to Bedrock along with each request.

<img src="docs/en/panel-dark.png" width="420" alt="The candidate panel in dark mode">

## Voice input

<img src="docs/en/voice.png" width="340" alt="Hold right ⌥ to talk">

Hold right ⌥ and talk; when you let go, the text is inserted. It's recognized in the language you're typing (English, Chinese, French, Korean or Hindi). If you type a command first (e.g. `@improve `, `@question `) and then talk, the text goes after the command and ⏎ runs it; you can also press ⏎ without letting go of right ⌥ to run it as soon as you finish. Speech is recognized on the Mac by macOS's built-in speech recognition (SpeechAnalyzer), and no audio is uploaded; it needs macOS 26 or later.

The first time:

- macOS asks whether AllInOneIME may use the microphone. You can also click "Allow Microphone" in the settings beforehand.
- If this Mac doesn't have the speech model for that language yet, it's downloaded once, automatically. You can also download it in the settings.

Recording starts only after you've held the key for about 0.2 s, so a quick tap on right ⌥ doesn't turn on the microphone (with the action key set to "Tap ⌥", a tap runs the action). If you press another key while holding it (an ⌥ shortcut, ⌥←), it counts as a shortcut and nothing is recorded either. Pressing any other key while recording cancels the recording.

## Installation

Running it needs macOS 14 or later, voice input macOS 26 or later. The installer is universal: it works on Macs with
Apple silicon and Intel. So far it has only been tested on macOS 27 on Apple silicon (the Intel build only through its self-test under Rosetta).

1. Download `AllInOneIME-<version>.dmg` from [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) (only from there) and open it.
2. Double-click "Install AllInOneIME" in it and click Install. The input method goes into `~/Library/Input Methods`
   and "AllInOneIME Settings" into `~/Applications`. For this user only; no administrator password needed.
3. The installer is signed with a Developer ID and notarized by Apple, so the first time macOS only asks whether to open
   an app downloaded from the internet: click Open. (Versions before 0.6.3 weren't notarized: each had to be allowed
   once in System Settings → Privacy & Security → Open Anyway.)

After that, AllInOneIME is enabled and in your input sources; switch to it with Ctrl+Space
(the 🌐 key switches only if "Press 🌐 key to" is set to "Change Input Source" in System Settings → Keyboard).
If the installer tells you to add it by hand, this Mac doesn't let programs enable it, so add it once yourself:
System Settings → Keyboard → Text Input → Input Sources → Edit… → + (bottom left) → English → AllInOneIME
(it types pinyin too once you add Chinese under Input in its settings).

If Ctrl+Space doesn't get you to AllInOneIME, or it switches back to U.S. after a while, run the installer again: it adds AllInOneIME back to your input sources.

Updating: Settings → About → Check for Updates. When there's a new version, About says so (and a line in the menu bar panel),
with what's new; "Update to <version>" downloads it, checks it against the update information signed with AllInOneIME's
release key, installs it and restarts the input method. Your settings, language packs, learned words and extensions stay, and
if anything goes wrong the version you had is put back. AllInOneIME looks once a day by itself, in the background (turn it off
with "Check for updates automatically" under About); nothing is installed until you click. This works from 0.6.3 on; to update
an older version, or if you prefer, install the new version's disk image over it, without uninstalling first.
Before upgrading, read the [changelog](CHANGELOG.md): it has each version's changes and upgrade notes.

Updating to 0.6.3 from an earlier version: 0.6.3 is the first version signed with a Developer ID, so the keychain
doesn't yet know it as the app that saved your keys. The first time it needs each key it saved (an API key, the
AllInOneIME Cloud sign-in, an extension's password), macOS asks for your login password: enter it and click "Always
Allow". It doesn't ask again, also after later updates. Amazon Bedrock's keys are in `~/.aws/credentials`, which
isn't affected. Accessibility (System Settings → Privacy & Security → Accessibility), which pasting into terminals and
reading the selection use, needs one step too: if AllInOneIME is listed, remove it and turn it on again when asked.

If you had AIPinyin installed (AllInOneIME's earlier name), just install: the old AIPinyin.app and its settings launcher are removed,
and the entry in your input sources gets the new name, with no need to add it again. Settings, the jargon list and learned words move to the new folders
(`~/.config/allinoneime` and others) on first launch, and each old folder is left as a link to the new one.

To uninstall, open "Install AllInOneIME" and click Uninstall…. Settings and learned words are kept.

### Building from source

Building needs Xcode 26 or later, since voice input uses the macOS 26 SDK.

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` downloads librime and the rime-ice dictionaries and verifies them, builds, and installs into the same places, adding it to your input sources the same way.
The app it installs has no Chinese dictionaries (they're the Chinese language pack): an install that had them keeps them as the pack; otherwise `make install-pack` installs the pack from the checkout's dictionaries, without a download.
`make status` shows the installed version (`version:`) and whether it's in your input sources (`listed:`). To uninstall: `make uninstall`.

## Setting up the AI

Translations and rewrites use your own AI provider, and the costs go to your account: Amazon Bedrock in your AWS account by default, or the Claude API, Gemini or an OpenAI-compatible service (see "Other AI providers" below).

### Amazon Bedrock

1. Enable Bedrock in the AWS console and make sure you can use the chosen model. The default is Claude Haiku 4.5; the first time you use an Anthropic model, you fill in a use-case form once.
2. Create an access key with the `bedrock:InvokeModelWithResponseStream` permission and put it in a profile in `~/.aws/credentials`.
   Only such static keys are supported for now, not SSO or assume-role.
3. Open "AllInOneIME Settings": you can find it in Spotlight or in Applications, or open it from the input method's icon in the menu bar → Settings….
   Pick the profile, region and model, and click "Test Connection". "Language" at the top of the settings window can be English or Chinese; by default ("System") it follows the system
   (Chinese if Chinese comes before English in the system's preferred languages, English otherwise). The settings window, the hints in the candidate panel and the input menu all follow it.

<img src="docs/en/settings.png" width="420" alt="The settings window">

### Other AI providers: Claude API, Gemini, OpenAI-compatible services

You don't need AWS: pick one under "AI Provider" in the settings, paste an API key, click "Save", then "Test Connection".

| Provider | Default model | API key |
|---|---|---|
| Claude API | `claude-haiku-5-5` (fastest, cheapest; Sonnet 5.5 and Opus 5.5 are more careful but slower and pricier) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| OpenAI-compatible | OpenAI's `gpt-6-luna` (or `gpt-5.4-mini`); "Common Services…" has DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter and Ollama on this Mac: picking one fills in its base URL, then enter its model | The service's key; set the Base URL to its address, e.g. `https://api.deepseek.com/v1`, or `http://localhost:11434/v1` for Ollama on this Mac |

- API keys are kept in the system keychain, never in the config file. Without one there, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) and `OPENAI_API_KEY` from your shell are used.
- The API key row says whether a key is set: "✓ Saved · ends in a1b2" (its last 4 characters, kept with it so the key itself isn't read to show them) with Replace… and Remove…, "✓ From $OPENAI_API_KEY" for one in your shell, or "No API key yet" with the field to paste it.
- "Thinking" is low by default: the input method waits on every sentence, and less thinking is faster. Choose "Not set" for models that don't take it.
- With Claude Opus 5.5 or Sonnet 5.5 chosen, requests carry the Claude API's refusal fallback (`fallbacks: "default"`): when a safety classifier declines, the server retries on another model.
- In the config file: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), and `model`, `baseURL`, `effort` and `temperature` under `anthropic`, `gemini` and `openai` (unset ones use the defaults).

### Apple Intelligence on this Mac (macOS 26)

On a Mac with Apple Intelligence (Apple silicon, macOS 26 or later, turned on in System Settings → Apple Intelligence & Siri), choose "Apple Intelligence (on this Mac)" under "AI Provider": no key, no cost, and nothing you type leaves the Mac. It uses the model built into macOS (the Foundation Models framework), with the same instructions and answer format as the other providers, but only the examples written in the sentence's own language (a small model copies an example's language too readily).

- It's a small model: its context is about 4K tokens (8K on macOS 27), so a long paragraph may be too long for it, and it speaks fewer languages (English, Chinese, Japanese, Korean, French, German, Spanish and a few more; not Hindi). Either one says so. Its results are below the cloud models', and its `@question` answers on facts and code are often wrong.
- Where it can't be used, it's listed greyed out with the reason (not supported on this Mac, turned off, model not ready), and the settings link to System Settings → Apple Intelligence & Siri. Before macOS 26 it isn't listed.
- "Output tokens", temperature and the timeout under "Model Settings" apply to it. In the config file: `"provider": "apple"`.

### Hiding sensitive information (new)

Settings → AI Provider → Privacy → "Hide sensitive information before sending" (off by default): before a request goes
to the AI, what it finds in your text is replaced on the Mac with placeholders such as `[EMAIL_1]` (the same value, the
same placeholder), and the results get the real values back before they're shown or inserted. The panel says "2 items
hidden from the AI". Each kind can be turned off:

| Kind | For example | In the config |
| --- | --- | --- |
| Email addresses | `bob@example.com` | `emails` |
| Phone numbers | `+1 (555) 123-4567`, `138 0013 8000` | `phones` |
| Payment card numbers (Luhn-checked) | `4111 1111 1111 1111` | `cards` |
| API keys and tokens | known prefixes such as `sk-` or `ghp_`, long random strings | `keys` |
| IP addresses | `203.0.113.42`, `2001:db8::1` | `ips` |
| Your own words, in any case | a codename such as `Project Atlas`, a name | `customWords` |

- It applies to `@improve`, `@translate`, `@question`, your prompt commands and prompt plugins, and refining their results
  (the same placeholders), with every provider, including AllInOneIME Cloud and Apple Intelligence. Jargon list entries
  holding a value to hide aren't sent.
- It recognizes formatted values; it can't recognize names or addresses, so add those as your own words. `@claude`,
  plugins that fetch from a website (`@stock`) or open one (`@x`) and script extensions send text as typed. More
  under Privacy.
- In the config: `"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`.

All settings are stored in `~/.config/allinoneime/config.json`; after a change, the next translation uses the new settings, with no restart. The newer keys:

| Key | What it does | Default |
|---|---|---|
| `inputLanguages` | Input languages, one to five, the first is the default: `"en"` English, `"zh"` Chinese (pinyin), `"fr"` French, `"ko"` Korean, `"hi"` Hindi, e.g. `["en", "zh"]`, `["fr", "en", "ko"]`. Chinese, Korean and Hindi work once their pack is installed | `["en"]` (a new install) |
| `keyboardLayouts` | The keyboard layout an input language types with, by its code (only French so far): `{"fr": "com.apple.keylayout.French-PC"}` | French: `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | What `@translate` translates into, in order: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | `@improve` also translates (as `@translate @improve`) | `false` |
| `voiceInput` | Hold right ⌥ to talk | `true` |
| `actionKey` | Action key: `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Space), `"space"` (Space) | `"enter"` |
| `uiLanguage` | Interface language (settings window, candidate panel hints, menu): `"zh"`, `"en"` | `null` (follow the system) |
| `rewriteStyles` | Rewrite styles: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, e.g. `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | Your own jargon list file | `null` (i.e. `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | The menu bar icon and its drop-down panel | `true` |
| `candidateLayout` | Pinyin and Hindi candidates: `"vertical"` (one under the other) or `"horizontal"` (side by side; ← → choose, ↑↓ turn the page) | `"horizontal"` |
| `fuzzyPinyin` | Fuzzy pinyin pairs: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | @ commands work on the text selected in the field (see On the selected text) | `true` |
| `checkForUpdates` | Look for a new version once a day, in the background; nothing is installed until you click | `true` |
| `rememberQuestions` | Keep your last 5 `@question`s and their answers on this Mac, listed under `@question` (see Recent questions) | `true` |
| `questionRounds` | Rounds of an `@question` conversation in the panel before it suggests continuing elsewhere, 2–10 | `5` |
| `questionContinueIn` | Where an `@question` conversation can continue, in order, the first the default: `claudeCode`, `claudeWeb`, `chatgpt`, `gemini`, `copy` | Claude Code (if installed), Claude, ChatGPT, copy |
| `appProfiles` | Settings of one app, by bundle ID, each optional: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI` (see Per-app settings) | `{}` |
| `redaction` | Hide sensitive information from the AI (see Privacy): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`; each detector (`emails`, `phones`, `cards`, `keys`, `ips`) is on unless set to `false` | `enabled: false` |

## Privacy

- Typing (English and pinyin) and `@calculate` calculations are entirely local. Only when you press the action key on `@improve`, `@translate` or `@question` is that sentence sent to the AI provider you chose (your own Bedrock, or the service whose key you added). With "Jargon" checked and a jargon list set, the list is sent along with it. Refining the results (an instruction typed after them, then ⇧⏎) sends the same request again with the results shown and your instruction; a follow-up question (⇧⏎) sends the conversation so far with it.
- `@config` and `@doctor <question>` send text to a model when you press ⏎: Apple Intelligence on this Mac whenever it's available (nothing leaves the Mac), else your provider. `@config` sends your sentence (a key typed into it is taken out first) with the current values of the settings it may change: never a key, nor the words you hide from the AI (only how many there are), and your AWS profiles' names only when the sentence is about AWS or Bedrock. `@doctor <question>` sends your question with the check results, masked: no paths beyond `~`, no keys, log lines as fixed phrases. Hiding sensitive information applies to both, as to any request. The checks alone (`@doctor` with nothing after it) send nothing but the Test Connection request, and that only when the provider has a key or credentials to test.
- Continuing an `@question` conversation elsewhere (⌘1 … after the last round, or ⌘⏎) sends it, with what you typed, to the service you pick: Claude Code on this Mac (Anthropic), claude.ai, chatgpt.com or gemini.google.com, in the web address or through the clipboard. It goes as you saw it: values hidden from the AI's requests (see below) are in it as they are, since you choose to send it there. Nothing goes anywhere until you pick one; "Copy the conversation" only puts it on the clipboard.
- With AllInOneIME Cloud, the sentence goes through the developer's server to a model provider (currently through OpenRouter): the server keeps counts only, never the text. Signing in keeps only your email address.
- Hide sensitive information (Settings → AI Provider → Privacy, off by default): before any request goes out (`@improve`, `@translate`, `@question`, your prompt commands and prompt plugins, with every provider including AllInOneIME Cloud), email addresses, phone numbers, payment card numbers (Luhn-checked), API keys and tokens (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…` and long random strings), IP addresses and your own words (a codename, a name) are replaced on the Mac with placeholders such as `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]`; the same value gets the same placeholder. The model's results get the real values back before they're shown or inserted, and the panel says "2 items hidden from the AI". A result whose placeholder the model changed beyond recognition is shown as written, marked "⚠ placeholder changed". Jargon list entries holding a hidden value aren't sent. Each kind can be turned off. Full-width forms (`zhang＠example.com`, `１３８…`) are found too, and a value or phrase may be split by a line break. It recognizes formatted values like emails, numbers and keys; it can't recognize names or addresses (add those as your own words), nor look-alike letters from other alphabets. Applies to requests to your AI service; `@claude`, plugins that fetch from a website (`@stock`) or open one (`@x`) and script extensions send text as typed. In the config: `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- Voice is recorded only while you hold right ⌥ and is recognized on the Mac; the recognized text is sent only in the commands above, when you press the action key.
- The input method reads the clipboard text, once, only when you press ⌃V or ⌘V in a command; content that password managers mark as concealed isn't read. The text is shown in the command first and, again, is sent only when you press the action key. Recent macOS versions ask whether AllInOneIME may read the clipboard: allow it. To stop being asked every time, set AllInOneIME's paste permission to always allow in System Settings → Privacy & Security.
- In password fields macOS switches to its own keyboard (U.S. or ABC) and back when you leave them. Whenever the app you type in holds secure input, AllInOneIME doesn't compose text and can't record: keys go in as typed. And while the system is in secure input (password fields, Terminal's Secure Keyboard Entry, etc.), nothing is sent to the AI.
- `@note` and `@reminder` don't go to the AI: AllInOneIME hands the text only to Notes and Reminders on this Mac, and reads the reminder's time on the Mac too (whether those apps sync it to your other devices depends on their accounts, such as iCloud). So they work during secure input as well.
- `@reportissue` (and "Report an Issue…") sends nothing itself: it opens GitHub's new-issue page in your browser with the title you typed and the versions, languages, provider kind and counts listed above, shown in the candidate panel first. Nothing reaches GitHub unless you click Submit there.
- `@open` searches only on this Mac. It remembers what you opened with it (the latest 200), in the input method's own preferences (not in config.json), to list those first.
- For "Add App…" in Settings → Apps, the input method keeps the bundle IDs of the last 12 apps you typed in, in its own preferences; nothing else about them.
- `@question` remembers your last 5 questions with their answers and when they were asked, only on this Mac, in `~/Library/Application Support/AllInOneIME/recent-questions.json` (readable only by your user account), to list them under `@question`; a saved answer is shown from there without going online. Nothing is kept while secure input is on, and questions asked on selected text aren't kept at all (their answer is about the selection, which would end up on disk). Turning off "Remember recent questions" in Settings → General deletes them too; turning it off through `@config` (`rememberQuestions` in the config) keeps them, so it can be undone exactly. "Clear" deletes them.
- To list your notes, the menu bar panel keeps the id and first line (up to 80 characters) of the last 30 notes saved with `@note`, in the input method's own preferences, also while the panel is off.
- `@py` and `@js` run only when you press the action key, and only code you typed or pasted yourself: the AI's answers and other commands' output are never run as code. `@py` uses your Mac's `python3`, which can read and write files and go online as it does in Terminal; `@js` runs in a separate process that can't read files, reach the network or run other programs. Neither runs during secure input.
- Update check: once a day (unless "Check for updates automatically" is off), AllInOneIME downloads https://allinoneime.com/update.json and its signature; the request carries no identifiers and nothing you typed. An update is downloaded, from the GitHub release, only when you click Update.
- Extension sources: git runs on your Mac, as you, only for the sources you added: a fetch once a day for those that
  check by themselves (none for a pinned one), and when you click Check Now, Update or Re-clone. It talks only to the
  repository's host, signed in by your own git and SSH setup; nothing you type goes with it.
- Logs don't record what you type. For every third-party input method, macOS warns "The developer can access anything you type with this input source"; it's a generic system warning.

## Development

```sh
make test         # unit tests, plus tests that run the real Rime engine
make pack         # the Chinese language pack: build/packs/zh-pinyin-<version>.tar.xz, its sha256, its packs.json entry
make packs        # all the language packs: Chinese, and Korean and Hindi from LanguagePacks/ (ko-hangul, hi-phonetic)
make selftest     # drives the input method through a simulated text field: real Bedrock calls, plus on-device recognition tested with synthesized speech
make realtest     # types into a real app's text field (needs the screen unlocked; takes over the foreground for about 1 minute)
make screenshots  # regenerates the screenshots in docs/
make cli && .build/release/allinoneime-cli --styles concise,jargon "this is a blocker bug your team need fix it asap"   # try polishing and rewrites in the terminal
make icon         # regenerates the app icon and the menu bar icon from Resources/AppIcon.png
make dmg          # the release installer, build/AllInOneIME-<version>.dmg (universal; signed if there's a Developer ID certificate, optionally notarized), and the in-app update, build/AllInOneIME-<version>-update.zip
make update-test  # the in-app updater end to end: a temporary install, a test server on 127.0.0.1, a test key (never the installed app)
```

`make selftest` and `make realtest` don't depend on your settings. The self-test uses a config of its own (Amazon Bedrock with the AWS profile and region from yours, everything else the defaults); the real-app test sets the provider to Bedrock while it runs and puts yours back. What they can't check at the moment is skipped, not failed: live Bedrock checks without credentials for that profile, and anything typed while secure input is on (the screen locked, a password field). The last line counts passed, failed and skipped checks; only failures fail the run, and a run with skips ends in INCOMPLETE, or SKIPPED when nothing that types ran (BLOCKED: the real-app test started on a locked screen), never PASSED.

Code layout:

- `Sources/AllInOneIMECore`: Bedrock client, SigV4, prompts, the two-level input state machine (including @ commands and the voice gesture); no AppKit dependency
- `Sources/AllInOneIMERime`: librime wrapper
- `Sources/AllInOneIME`: the InputMethodKit input method, candidate panel, settings window, speech recognition
- `Sources/AllInOneIMESettings`: the "AllInOneIME Settings" launcher
- `Sources/AllInOneIMEInstaller`: "Install AllInOneIME" on the disk image: installs, updates and uninstalls

Language packs have their own library, apart from the plugins: the repository
[MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), served at
https://languages.allinoneime.com/, signed with their own key. `make pack` builds the archive; it's published as a
release asset there (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), and `swift Scripts/build-packs-index.swift <languages repo>
build/packs/*.tar.xz.json` writes `packs.json` there and signs it into `packs.json.sig` with the language packs' key
from the keychain (`allinoneime-languages-signing`). The app reads https://languages.allinoneime.com/packs.json, checks
the signature, then the archive's size and SHA-256. To try a pack from a local server: `--test-key` signs with a test key, and
`AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Releasing a version (the in-app updater reads https://allinoneime.com/update.json, signed with the releases' own key):

1. Bump the version (`AppVersion.swift` and the three Info.plists; `AppVersionTests` checks they agree) and the changelogs.
2. `make dmg NOTARY_PROFILE=<profile>`: `build/AllInOneIME-<version>.dmg` with its `.sha256`, and
   `build/AllInOneIME-<version>-update.zip` (both apps, as the disk image's installer carries them). The apps and the
   image are signed with the Developer ID Application certificate in the keychain, and the image is notarized with
   that `xcrun notarytool` keychain profile and stapled.
3. Upload both to the GitHub release `v<version>` and publish it.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"` (a sentence or two each): writes
   `site/public/update.json` (version, build and minimum macOS read from the apps, the asset's address, size and SHA-256,
   the release notes' address and the summary) and signs it into `update.json.sig` with the key from the login keychain
   (`allinoneime-releases-signing`; macOS may ask to allow access). Commit both.
5. Deploy the site (`cd site && npx wrangler@4 deploy`), only once the release's assets download: the apps check once a day,
   and `AllInOneIME --check-update` shows what they see.

The app checks the manifest's signature with the public key built into it before reading it, never installs a version that
isn't newer, downloads only over https from allinoneime.com or the repository's GitHub release assets, and installs the
archive only once its size and SHA-256 match the manifest, both apps' bundle IDs, versions and code signatures check out and
the new input method starts. The input method then hands over to its own executable as a helper (`--apply-update`), which
waits for it to quit, swaps the apps the way the installer does (the old ones moved aside, put back if anything fails) and
registers the new one. To try it against a local server: `make update-test`, or `--test-key` with
`Scripts/build-update-manifest.swift` and `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`.

The bundle ID is still `com.aipinyin.inputmethod.AIPinyin`: macOS uses it to remember the added input source and the microphone permission, so changing it would mean adding the input method and granting the permission again.

## License

Copyright © 2026 MicroZ LLC. Source available under the [Functional Source License 1.1](LICENSE) (FSL-1.1-ALv2): use it,
read it, change it and share it for anything but a competing product. Each version becomes Apache-2.0 two years after
its release. Versions up to 0.6.1 were released under the GPL-3.0 and stay available under it.

Third-party components (librime and its plugins under BSD-3-Clause; rime-ice's Lua scripts and the Chinese language pack
under GPL-3.0) are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
