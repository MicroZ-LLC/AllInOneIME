# Script extensions: protocol 1

A script extension adds an @ command to AllInOneIME without touching the app: a program in any language plus a few
lines of metadata. The same mechanism serves a personal script, a team's private bundle of tools, and existing
Raycast Script Commands. Extensions live outside the app's repository; this page is the contract between them.

This is protocol version **1**. Within version 1, changes only add things: keys an app doesn't know are ignored, so a
newer extension still loads in an older app. An extension that needs a newer protocol (`schemaVersion` above the
app's) is listed in Settings as needing a newer AllInOneIME, and isn't run.

[`Examples/extensions`](../Examples/extensions) has an example of every feature, to start from:

| Example | Shows |
|---|---|
| `clock.sh` | a `list` run again as you type, and every 30 seconds (`rerun`); rows with `text.copy` |
| `countdown.sh` | `show`: progress as it prints; an optional argument; `timeout`; `ALLINONEIME_LANGUAGE` |
| `uuid.sh` | `input none`: the action key on its name runs it; `insert` |
| `timer.sh` | `background`: a notification with a `summary` and its `detail` |
| `battery.sh` | a `status` line (`status self`, `statusRefresh`) |
| `say.sh` | `confirm`, and `silent` (its last line as a notice) |
| `word-count.sh` | a Raycast Script Command as Raycast writes it (`mode compact`, `packageName`) |
| `bookmarks/` | a bundle: each list row action (`open`, `copy`, `run` for a second step), a row of information only, a text and a password preference |
| `units/` | a bundle: a dropdown preference, two commands sharing code in `lib/` through `ALLINONEIME_EXTENSION_DIR` |

## 1. Where extensions come from

Extensions are read from folders:

- `~/.config/allinoneime/extensions/` (in the list from the start),
- folders added under Settings → Custom Commands → Script Extensions → Add Folder…,
- folders holding Raycast Script Commands, found with Spotlight (on by default; a found folder can be hidden),
- bundles installed from a Git repository: extension sources (§10).

A folder you add (and the first one) is read whole, as below. From a folder Spotlight found, only its Raycast Script
Commands are taken: its `@allinoneime.` scripts and bundles are left alone, since a found folder may be any copy of
anything that holds a Raycast script (a second checkout of a repository, a backup). To use all of such a folder, add
it. Each search replaces the folders found before, so one removed, or no longer holding a Raycast script, drops out of
the list.

A script, or a bundle, that is byte for byte the same as one read before it under the same name (its `extension.json`
and the scripts it lists, for a bundle) is a copy: it's left out quietly, and Settings says only "Skipped N identical
copies". A different script or bundle under a name already taken is listed as left out, and why (§7).

In each folder:

- **A single script** is a file in the folder with metadata (§2). Files whose name contains `.template.`, and hidden
  files, are left out. Subfolders aren't read, except bundles.
- **A bundle** is a subfolder with an `extension.json` (§6): its commands, and settings they share. A folder added
  that has an `extension.json` itself is that one bundle (this is how an extension source's bundle is loaded).
- **Symbolic links** are followed: a linked folder, script or bundle is read as what it points to. A link to nothing
  is listed in Settings as such.

The index of what the folders hold is kept in memory and rebuilt in the background when a text field becomes active
or the settings change; a file is read again only when its size, modification date or permissions changed, and only
its metadata, first line and SHA-256 (to tell copies apart) are kept. Nothing is scanned, read from the keychain or run while a key is being handled,
and the command list stays fast with a thousand extensions.

## 2. Metadata

Comment lines near the top of the file (within its first 64 KB), each starting with a comment mark (`#`, `//`, `--`,
`;`, `%`, `'` or `*`); a line without one isn't metadata:

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

A file may use `@allinoneime.<key> <value>` (the protocol's own keys) or `@raycast.<key> <value>` (read as they are,
§8). When a file has both, the `@allinoneime.` keys are used.

| Key | Value | Default |
|---|---|---|
| `schemaVersion` | `1` | required |
| `name` | the @ name: letters and digits, a letter first, at most 24 | the file name's letters and digits, from the first letter (`base64.py` → `@base64`, `convert-timestamp.sh` → `@converttimestamp`) |
| `title` | shown in the command list and Settings | the name |
| `description` | shown in Settings | none |
| `group` | shown after the title in the command list | none (a bundle's title for its commands) |
| `keywords` | comma-separated words the command list also finds it by | none |
| `icon` | an emoji, an SF Symbol name, or an image file (a path from the script's folder) | one for its output |
| `input` | `none`, `optional` or `required` (then its first argument is required, whatever it says) | `required` if one of its arguments is, else `optional` |
| `argument1`…`argument3` | Raycast's JSON (below) | one free-text argument |
| `output` | `insert`, `show`, `list` or `silent` (§4) | `insert` |
| `background` | `true`: it starts, and the text field is free at once (§5) | `false` |
| `status` | `self`, or a command line: its first line is shown beside the name in the command list | none |
| `statusRefresh` | how often the status runs at most: `10s`, `5m`, `1h`, `1d` (at least 10 s) | `1m` |
| `confirm` | `true`: the action key asks once more before it runs | `false` |
| `timeout` | seconds before it's stopped | 10; 600 with `background` |
| `queryDelay` | `list`: milliseconds after the last key before it runs again | 150 |
| `currentDirectoryPath` | where it runs (from the script's folder, or `~/…`) | the script's folder |

A bundle's command may also set `alias`: the name it takes when its `name` is another command's (§7).

**Arguments** use Raycast's JSON: `{"type": "text", "placeholder": "city", "optional": true, "percentEncoded": true}`.
`type` is `text`, `password` or `dropdown`; a dropdown lists its choices in `data`:
`[{"title": "Celsius", "value": "c"}]`. (Raycast's older `"secure": true` is a password.)

**Input.** `none`: the command needs nothing after its name; what's typed after it is ignored. In the command list,
Tab or Space completes its name; the action key (⏎ by default) runs it. `optional`: all its arguments are optional.

**Status.** `self` runs the script itself, with `ALLINONEIME_STATUS=1` and no arguments. Anything else is a command
line (no shell; quote with `"…"`), whose program is looked for in the script's folder first. A status is run only
while the command list shows the command, at most every `statusRefresh`, two at a time (one that ends, failed or
not, lets the next due one start), and is stopped after 5 seconds: a slow one never holds the list up; its value
shows when it arrives. A failed one keeps the value it had.

## 3. Running

**Arguments.** The text after the command:

- No arguments (`input none`): nothing is passed.
- One: all of the text, trimmed.
- Two or three: the text split at commas (`,` or `，`), each part trimmed; the last one takes the rest, commas and
  all. `@flights beijing, new york` → `$1=beijing`, `$2=new york`.
- A required argument left empty shows a notice naming the missing placeholders, and nothing runs. A dropdown takes a
  choice's title or value, in any case, and gets its value; anything else lists the choices. A `percentEncoded` value
  is percent-encoded (as JavaScript's `encodeURIComponent`). A password is passed as typed (it shows as typed in
  the text being written, too).

They're passed as `$1`…`$3`.

**Environment.** The input method's own environment, with the PATH of your login shell (read once, so Homebrew,
pyenv and nvm programs are found) and `/usr/local/bin` added to it. Other variables your shell's startup files
export (in `.zshrc`, say) don't arrive: a bundle's preferences are the way to pass settings. And:

| Variable | Value |
|---|---|
| `ALLINONEIME_PROTOCOL` | `1` |
| `ALLINONEIME_VERSION` | the app's version, like `0.6.3` |
| `ALLINONEIME_LANGUAGE` | the interface language: `en` or `zh` |
| `ALLINONEIME_INPUT_LANGUAGE` | the language being typed: `en`, `zh`, `fr`, `ko` or `hi` |
| `ALLINONEIME_APP` | the bundle id of the app being typed in |
| `ALLINONEIME_QUERY` | all the text after the command (empty for a command with a `password` argument) |
| `ALLINONEIME_EXTENSION_DIR` | the bundle's folder (a single script's own folder) |
| `ALLINONEIME_PREF_<NAME>` | each of the bundle's preferences (§6) |
| `ALLINONEIME_STATUS` | `1` when it runs for its status line |
| `ALLINONEIME_ACTION` | `run` when a list row's `run` action runs it (§4) |

**Process.**

- It runs in its folder (or `currentDirectoryPath`), with no standard input, started as a shell would start it:
  - an executable file runs as itself: a compiled program, or a script whose `#!` line the system reads;
  - a script that isn't executable runs through the program on its `#!` line (`#!/usr/bin/env python3` →
    `/usr/bin/env python3 script`), and so does one whose `#!` line follows a byte order mark (the system doesn't
    read it then);
  - an executable text file without a `#!` line runs with `/bin/sh` (as a shell does when the system can't run it);
  - a file that's neither executable nor has a `#!` line isn't loaded (Settings says why).
- It runs in a process group of its own. Stopping it (Esc, its `timeout`, more than 64 KB of output, a newer query
  of the same command) sends SIGTERM to the group, then SIGKILL half a second later: what it started goes too. When
  it ends by itself, what it started in the background and left running keeps running, as after a script run in a
  shell (a server it starts on purpose, say); wait for it (`wait`) if it should end with the script.
- One process per command at a time: a newer query stops the one before.
- Nothing runs while secure input is on (a password field, the lock screen).
- An extension doesn't run inside another command's text (`@question … @flights …` leaves it as text).
- It gets the text as typed. With text selected in the field, it doesn't use the selection: its arguments are what's
  typed after its name, and the selection stays as it is. "Hide sensitive information before sending" (Settings → AI
  Provider → Privacy) applies to requests to the AI only, not to what an extension gets. An app set to "No AI in this
  app" (Settings → Apps) still runs extensions: they aren't the AI.
- Color codes and other terminal escapes are removed from what it prints.

**Exit status.** Non-zero is a failure: the last line of standard error with words in it (else of standard output)
is shown as the error. The action key tries again.

## 4. Output

| `output` | What happens to what it prints |
|---|---|
| `insert` | Candidates to insert: all of it (1), and when there are several lines, each line on its own (2–9). ⏎, Space or a digit inserts one; ⌘C copies it. |
| `show` | Shown in the panel as it's printed (a progress), the last lines; nothing is inserted. ⌘C copies all of it, ⏎ closes. Left running when the text field is left, it goes on in the background (§5). |
| `list` | A list in Alfred's Script Filter JSON (below), run again as the text after the command changes, `queryDelay` after the last key; the run before is stopped. ↑↓ pick a row, the action key does its action, Tab completes its `autocomplete`, ⌘C copies its `text.copy`. The rows aren't numbered while you type (a digit is text: `@convert 10 km`). With a required argument left empty, the action key says what's missing. `confirm` and `background` don't apply to a list. |
| `silent` | Its last line is shown near the cursor; nothing is inserted. |

A command that prints nothing ends with a short notice that it ran (a list that prints nothing says "No results").

**A result with a detail.** If what it prints is a JSON object with `summary` (and `detail`), the summary is the line
(inserted, shown, or the notice) and the detail is shown beside it, and in a background command's notification:

```json
{ "summary": "3 tests failed", "detail": "parser, cache, ui" }
```

**Lists.** The subset of Alfred's Script Filter JSON that is used, and our `action`:

```json
{ "items": [
    { "title": "Jane Doe", "subtitle": "Engineer · Seattle", "arg": "https://example.com/jane",
      "action": "open", "valid": true, "text": { "copy": "jdoe" }, "autocomplete": "jane " }
  ],
  "rerun": 2.0 }
```

- `title` (required), `subtitle`: the row. At most 50 rows are kept. A list shown after a `run` step (below) numbers
  the first 9 rows that can be picked, and digits pick them.
- `arg`: what the action uses (a string, or the first of a list).
- `action` (ours): `insert` (puts `arg`, or the title, where you type), `open`, `copy` (copies `text.copy`, else
  `arg`, else the title), or `run` (runs the command again with `arg` as `$1` and `ALLINONEIME_ACTION=run`, a second
  step: a list it prints is shown to pick from; anything else is offered to insert). Without `action`: `open` when
  `arg` is an http(s) address or a path, else `insert`.
- `open` opens an `http://` or `https://` address in the default browser, or a folder, an app or a file given by
  a `file://` address, an absolute path or a `~/…` path that exists, as Finder would. It never opens what opening
  would run: an executable file (a program, a script with its executable bit, `/usr/bin/say`), or a file or bundle
  named `.sh`, `.bash`, `.zsh`, `.csh`, `.tcsh`, `.ksh`, `.fish`, `.command`, `.tool`, `.terminal`, `.py`, `.pyw`,
  `.rb`, `.pl`, `.php`, `.lua`, `.tcl`, `.js`, `.jar`, `.applescript`, `.scpt`, `.workflow` or `.action`. Other
  schemes (`smb:`, `mailto:`, an app's own) and relative paths aren't opened either: a notice says so, and the list
  stays. Nothing opened this way goes into `@open`'s history.
- `valid: false`: a row of information only, not picked.
- `text.copy`: what ⌘C copies of the row.
- `autocomplete`: what Tab puts after the command name.
- `rerun`: seconds after which the list runs again while the same text is shown (at least 0.5).
- Other Alfred keys (`uid`, `icon`, `match`, `mods`, `variables`, …) are ignored.

Output that isn't a list shows as one row of information with its last line.

## 5. Background commands

`background: true` starts the command when the action key is pressed: the text field is free at once (a notice says
it started). A `show` command still running when the text field is left goes on the same way.

While it runs, the menu bar panel lists it under "Background Commands". When it's done, a notification shows its
summary and detail, or its last line (or the error); clicking the notification, or its row in the panel, opens what
it printed in the default text editor. At most 4 run in the background at once, and a command isn't started twice
while it runs: a `background` command started then says so instead, and a `show` left running then is stopped.

When the input method quits (an update, logging out), what's running for extensions is stopped, with what it
started. (If the input method crashes, they can't be.)

## 6. Bundles and preferences

A bundle is a folder with `extension.json` and the scripts it names. Its scripts can share code (a `lib/` folder,
reached through `ALLINONEIME_EXTENSION_DIR`) and settings. One folder to install, update or remove.

```json
{
  "schemaVersion": 1,
  "name": "units",
  "title": "Unit Converter",
  "version": "1.0.0",
  "author": "…",
  "description": "…",
  "preferences": [
    { "name": "precision", "type": "dropdown", "title": "Decimals", "default": "2",
      "data": [{ "title": "0", "value": "0" }, { "title": "2", "value": "2" }] },
    { "name": "apiToken", "type": "password", "title": "API token", "required": true }
  ],
  "commands": [
    { "script": "convert.sh", "name": "convert", "title": "Convert Units", "output": "list",
      "argument1": { "type": "text", "placeholder": "amount and unit" } },
    { "script": "bin/units.py", "name": "unitlist", "output": "show", "input": "none", "alias": "unitsknown" }
  ]
}
```

- `schemaVersion`, `name` (letters, digits, `-`, `_`; two bundles can't share one) and `commands` are required.
- Each command names its `script` (a path inside the bundle) and takes the keys of §2 in JSON: strings, `true` /
  `false`, numbers, and the `argumentN` objects as they are. They override the `@allinoneime.` lines in the script, if
  it has any.
- `preferences`, in Raycast's shape: `name`, `type` (`textfield`, `password`, `checkbox` or `dropdown` with `data`),
  `title`, `description`, `required`, `default`. Settings shows them under the bundle. Each reaches every command as
  `ALLINONEIME_PREF_<NAME>` (the name in capitals, other characters as `_`: `apiToken` → `ALLINONEIME_PREF_APITOKEN`);
  a checkbox is `true` or `false`. Password values are kept in the macOS keychain, never in a file; the others in the
  config file. While a required preference has no value, its commands say so instead of running. Settings saves a
  text field on Return and when you leave it.

## 7. Names, order, turning things off

- **Collisions** are resolved in this order: built-in commands, plugins, custom commands, bundles, single scripts,
  Raycast scripts; within each, the folders' order, then file names. A bundle command whose name is taken uses its
  `alias` if that's free. Two commands with one name in a bundle: the first is kept. Settings marks each command left
  out, and why.
- **Turning things off.** Each command, and each bundle as a whole, has a switch in Settings (`disabledExtensions` in
  the config: a command's id, or a bundle's name). A command turned off frees its name.
- **The command list** ranks by use. Typing finds names starting with the letters, then names containing them, then
  commands with a word of their title or a keyword starting with them. A digit right after letters is part of a name
  when a command's name goes on that way (`@base6` → `@base64`); otherwise digits pick a row.
- **Limits.** A few processes at a time (status lines two at once, background runs four), 64 KB of output, the
  timeouts above.

## 8. Raycast Script Commands

Raycast's keys are read as they are, and mean:

| Raycast | Here |
|---|---|
| `schemaVersion`, `title`, `mode` | required, as in Raycast (Raycast's `schemaVersion` is `1`; another is reported) |
| `mode fullOutput` | `output show` |
| `mode compact`, `mode silent` | `output silent` |
| `mode inline` with `refreshTime` | `status self`, `statusRefresh` = `refreshTime` (running it is `silent`) |
| `mode inline` alone | `output silent` |
| `needsConfirmation` | `confirm` |
| `currentDirectoryPath` | `currentDirectoryPath` |
| `argument1`…`argument3` | the same |
| no arguments | `input none` |
| `packageName` | `group` (the folder's name if unset) |
| `icon` | an emoji or an image file; web addresses aren't fetched |
| `platform` | a script whose platform leaves out macOS is skipped |

`iconDark`, `author` and `authorURL` are ignored.

## 9. The config file

| Key | Default | Meaning |
|---|---|---|
| `extensionFolders` | `["~/.config/allinoneime/extensions"]` | folders added |
| `findRaycastScripts` | `true` | also the folders Spotlight finds holding Raycast scripts |
| `hiddenExtensionFolders` | `[]` | found folders not used |
| `disabledExtensions` | `[]` | commands (ids) and bundles (names) turned off |
| `extensionPreferences` | `{}` | bundle → preference → value (not passwords) |
| `extensionSources` | `[]` | Git repositories bundles are installed from (§10) |

## 10. Extension sources

A bundle can be installed from a Git repository and updated from there: Settings → Custom Commands → Extension
Sources → Add from Link…, or `AllInOneIME --add-source <url>`.

**The repository.** Any layout, as long as the bundle is a folder with its `extension.json` (§6) and the scripts it
names:

```
my-extensions/                 the repository
├── README.md
└── extensions/team/           the bundle ("path": "extensions/team")
    ├── extension.json
    ├── standup.sh
    └── lib/common.sh
```

With no `path`, the folder holding an `extension.json` is found (the root, or one up to four levels down; not inside
hidden folders or `node_modules`); when there are several, Settings lists them to pick from and `--add-source` asks
for `--path`. A source is one bundle, and an address is one source: bundles meant to be used together go in one
bundle, others in a repository of their own.

**The config.**

```json
"extensionSources": [
  { "url": "git@github.com:you/my-extensions.git", "path": "extensions/team", "branch": "main", "pin": null,
    "autoCheck": true, "authHint": "Optional: your own reminder of how to sign in, shown under a git error" }
]
```

| Key | Meaning |
|---|---|
| `url` | `ssh://…`, `git@host:path`, `https://…`, or `file://…` (a repository on this Mac). `http://` isn't used |
| `path` | the bundle's folder in the repository (none: found as above) |
| `branch` | the branch followed (none: the repository's default) |
| `pin` | a tag or commit the clone stays on; `null` follows the branch. A pinned source isn't checked for updates |
| `autoCheck` | `true` (default): checked once a day and about 30 s after the input method starts |
| `authHint` | shown under a git error |

**What happens.**

- **Git.** `/usr/bin/git` (Xcode's or the command line tools'; without them, a clear error instead of the installer)
  runs as you, with your login shell's PATH and SSH agent, so your keys, `~/.ssh/config` and credential helpers sign in;
  the app never sees a password. Never interactively: `GIT_TERMINAL_PROMPT=0`, ssh with `-o BatchMode=yes` added to
  your own ssh command (`GIT_SSH_COMMAND` or `core.sshCommand`), standard input closed, 60 seconds a call, hooks off
  (`-c core.hooksPath=/dev/null`) for every call.
- **Adding.** A shallow clone (`--depth 1`, the one branch, no tags; the pin fetched and checked out) into a temporary
  folder, moved into place as `~/Library/Application Support/AllInOneIME/Sources/<repository>-<hash>/` (the hash is of
  the address). Nothing of it loads until you've seen the review (the bundle, each command's name, title,
  description and output, the programs it runs, its preferences, the address and commit) and clicked Enable, which
  adds the bundle's folder to `extensionFolders`. Cancel deletes the clone. A command whose name is taken follows §7,
  and the review says so.
- **Trust** is per source and address: once enabled, its updates don't need another review.
- **Checking** (`autoCheck`, or Check Now): `git fetch` of the branch (100 commits deep), and the commits after the
  clone's listed (subject, author, date). Nothing changes.
- **Update** (only when you click it, or `--update-sources`): fetched again, then the clone is moved to the new commit
  if it follows the clone's (a fast-forward; never a merge). If the history was rewritten (a force push, or more than
  100 new commits), Re-clone replaces the clone instead. The loader reads the changed files as for any folder (§1).
- **Removing** moves the clone to the Trash and takes the source and its folder out of the config; the bundle's
  `extensionPreferences` (and passwords in the keychain) stay, so adding it back restores them.
- **State.** What's known of each clone (trusted, its branch and commit, the last check and error, what's new) is in
  `sources.json` next to the clones. The command line writes it too; a running input method reads it again.

**Command line** (on `~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME`):

| | |
|---|---|
| `--add-source URL [--path P] [--branch B] [--pin REF]` | clone, print the review, enable (running it is the consent); non-zero on any error |
| `--update-sources` | check and fast-forward every enabled source that isn't pinned; print what changed |
| `--list-extensions` | the loaded commands (name, output, source or folder), those turned off or hidden, and the files left out |

There is no signature on a source: it runs what its repository holds, as you. Add only repositories you trust.
