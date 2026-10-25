# Script extensions: protocol 1

A script extension adds a command to AllInOneIME without touching the app: a program in any language plus a few
lines of metadata. The same mechanism serves a personal script, a team's private bundle of tools, and existing
Raycast Script Commands. Extensions live outside the app's repository; this page is the contract between them.

This is protocol version **1**. Within version 1, changes only add things: keys an app doesn't know are ignored, so a
newer extension still loads in an older app. An extension that needs a newer protocol (`schemaVersion` above the
app's) is listed in Settings as needing a newer AllInOneIME, and isn't run.

[`Core/Examples/extensions`](../Core/Examples/extensions) has an example of every feature, to start from:

| Example | Shows |
|---|---|
| `clock.sh` | a `list` run again as you type, and every 30 seconds (`rerun`); rows with `text.copy` |
| `countdown.sh` | `show`: progress as it prints; an optional argument; `timeout`; `ALLINONEIME_LANGUAGE` |
| `uuid.sh` | `input none`: the action key on its name runs it; `insert` |
| `timer.sh` | `background`: a notification with a `summary` and its `detail` |
| `battery.sh` | a `status` line (`status self`, `statusRefresh`) |
| `say.sh` | `confirm`, and `silent` (its last line as a notice) |
| `word-count.sh` | a Raycast Script Command as Raycast writes it (`mode compact`, `packageName`) |
| `bookmarks/` | a bundle: each list row action (`open`, `copy`, `run` for a second step), a row of information only, a text and a password preference; a completion source (`bm.` and a title, a Markdown link: §11) |
| `units/` | a bundle: a dropdown preference, two commands sharing code in `lib/` through `ALLINONEIME_EXTENSION_DIR` |

## 1. Where extensions come from

Extensions are read from folders:

- `~/.config/allinoneime/extensions/` (in the list from the start),
- folders added under Settings → Commands → Script Extensions → Add Folder…,
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
| `completion` | a completion source, as JSON on one line: suggestions as you type a prefix (§11) | none |

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
| `ALLINONEIME_VERSION` | the app's version, like `0.6.4` |
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
  typed after its name, and the selection stays as it is. "Hide sensitive information before sending" (Settings →
  Privacy) applies to requests to the AI only, not to what an extension gets. An app in "Apps without AI" (Settings →
  Privacy) still runs extensions: they aren't the AI.
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

- `schemaVersion`, `name` (letters, digits, `-`, `_`; two bundles can't share one) and `commands` or `snippets` are
  required.
- Each command names its `script` (a path inside the bundle) and takes the keys of §2 in JSON: strings, `true` /
  `false`, numbers, and the `argumentN` and `completion` objects as they are. They override the `@allinoneime.` lines in
  the script, if it has any.
- The other paths a bundle's command gives are inside it too, from its script's folder as written (no `..`, no `/…`,
  `~/…` or `C:…`): an `icon` image, a `status` program given as a path (`./left.sh`; a program name alone, `date`, is
  still looked for in the script's folder, then on the PATH), and a `currentDirectoryPath` that isn't `~/…` or
  absolute. One that isn't is a bad value: the command doesn't load, and Settings says why.
- `preferences`, in Raycast's shape: `name`, `type` (`textfield`, `password`, `checkbox` or `dropdown` with `data`),
  `title`, `description`, `required`, `default`. Settings shows them under the bundle. Each reaches every command as
  `ALLINONEIME_PREF_<NAME>` (the name in capitals, other characters as `_`: `apiToken` → `ALLINONEIME_PREF_APITOKEN`);
  a checkbox is `true` or `false`. Password values are kept in the macOS keychain, never in a file; the others in the
  config file. While a required preference has no value, its commands say so instead of running. Settings saves a
  text field on Return and when you leave it.
- `snippets`: texts to insert, for a team's addresses, links and replies. Each has a `name` (and maybe an `alias`), its
  `text` with the placeholders of a custom `snippet` command (`{input}`, `{name?}`, `{clipboard}`, `{selection}`,
  `{date}`, `{time}`, `{cursor}`; see the README), and optionally a `summary`, an `icon` (an SF Symbol) and a `color`.
  Every one of these is a string: a snippet with a `text` (or another key) that isn't one is left out, and Settings says
  why. They run nothing. A bundle may ship only snippets. Plugins can't ship them. A `commands` or `snippets` that isn't
  a list of entries is reported too, and the other list still loads.

  ```json
  "snippets": [
    { "name": "addr", "text": "1 Main Street\nSpringfield", "summary": "Office address", "alias": "teamaddr" },
    { "name": "wifi", "text": "guest / hunter2" }
  ]
  ```

## 7. Names, order, turning things off

- **Collisions** are resolved in this order: built-in commands, plugins, custom commands, bundles, single scripts,
  Raycast scripts; within each, the folders' order, then file names. The bundles' snippets come after all the bundles'
  commands, before single scripts. A bundle command or snippet whose name is taken uses its `alias` if that's free. Two
  with one name in a bundle: the first is kept. Settings marks each command left out, and why; a snippet left out is
  marked in its extension source's "Loaded" line and review, and in `--list-extensions`.
- **Turning things off.** Each command, and each bundle as a whole, has a switch in Settings (`disabledExtensions` in
  the config: a command's id, or a bundle's name). A command turned off frees its name. A snippet is turned off with
  `"<bundle>/<name>"` there.
- **The command list** ranks by use. Typing finds names starting with the letters, then names containing them, then
  commands with a word of their title or a keyword starting with them. A digit right after letters is part of a name
  when a command's name goes on that way (`@base6` → `@base64`); otherwise digits pick a row.
- **Limits.** A few processes at a time (status lines two at once, background runs four), 64 KB of output, the
  timeouts above. A completion's runs have limits of their own (§11).

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
| `completionSources` | `[]` | the completion sources turned on (§11), plugins' too: for a command, `"plugin": "script-extensions"` and its id as `source`, with what was approved (its script's SHA-256, `query`, and its `terms`: prefix, `queryMinChars`, `compare`); this Mac's own, never synced |

## 10. Extension sources

A bundle can be installed from a Git repository and updated from there: Settings → Commands → Extension
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
| `url` | `ssh://…`, `git@host:path`, `https://…`, or `file://…` (a repository on this Mac). `http://` isn't used, nor an https address with a user name, password or token in it (git's credential helper keeps those) |
| `path` | the bundle's folder in the repository (none: found as above) |
| `branch` | the branch followed (none: the repository's default) |
| `pin` | a tag or commit the clone stays on; `null` follows the branch. A pinned source isn't checked for updates |
| `autoCheck` | `true` (default): checked once a day and about 30 s after the input method starts |
| `authHint` | shown under a git error |

**What happens.**

- **Git.** `/usr/bin/git` (Xcode's or the command line tools'; without them, a clear error instead of the installer)
  runs as you, with your login shell's PATH and SSH agent, so your keys, `~/.ssh/config`, your own ssh command
  (`GIT_SSH_COMMAND`, `core.sshCommand`, left exactly as they are) and credential helpers sign in; the app never sees a
  password. Never interactively: git runs in a session of its own with no controlling terminal and standard input
  closed, so ssh can't ask for a host key or a password (it fails, as "Host key verification failed." or "Permission
  denied"), with `GIT_TERMINAL_PROMPT=0` and `SSH_ASKPASS_REQUIRE=never`, 60 seconds a call, hooks off
  (`-c core.hooksPath=/dev/null`) for every call. Only the ssh, https and file transports (`GIT_ALLOW_PROTOCOL`).
- **Names.** Every branch, tag or commit (the config's, Settings', a pin, and the repository's own default branch) has to
  be a name `git check-ref-format --branch` accepts and can't start with `-`; git gets it after `--end-of-options`. A
  repository whose default branch is named like an option is refused.
- **Adding.** A shallow clone (`--depth 1`, the one branch, no tags; the pin fetched and checked out) into a hidden
  staging folder (`Sources/.staging/`). Nothing of it is in place or loads until you've seen the review (the bundle,
  each command's name, title, description and output, the programs it runs and what its status line runs, a script
  that is a link out of the repository, its preferences, the address and commit) and clicked Enable, which moves it into place as
  `~/Library/Application Support/AllInOneIME/Sources/<repository>-<hash>/` (the hash is of the address; in one step,
  swapped with any older clone there) and adds the bundle's folder to `extensionFolders`. Cancel deletes the staged
  clone, never one in place. A bundle folder that leads out of the repository (a link) is refused. A command whose name
  is taken follows §7, and the review says so.
- **Only reviewed code loads.** A folder of the sources folder in the load list that isn't a reviewed source's bundle
  (a config copied from another Mac, a lost `sources.json`) isn't loaded, and is taken out of the load list when the
  input method starts and when Settings shows the page.
- **Trust** is per source and address: once enabled, its fast-forward updates don't need another review. A force push
  is different: the rewritten history could be anything, so Re-clone shows the review again and only Enable puts it in
  place (the reviewed clone keeps working meanwhile).
- **Checking** (`autoCheck`, or Check Now): `git fetch` of the branch (100 commits deep), and the commits after the
  clone's listed (subject, author, date). Nothing changes.
- **Update** (only when you click it, or `--update-sources`): fetched again, then the clone is moved to the new commit
  if it follows the clone's (a fast-forward; never a merge). If the history was rewritten (a force push, or more than
  100 new commits), Update is refused: Re-clone stages a new clone and shows the review (from a terminal,
  `--add-source` again). The loader reads the changed files as for any folder (§1).
- **Pin.** Changing the pin checks that ref out first, and the config keeps it only when that worked; Unpin goes back to
  the branch's newest commit (a fast-forward, as Update). When the pinned commit is further back than a check fetches,
  Unpin clones the branch anew and shows the review; the pin is cleared only on Enable.
- **Removing** moves the clone to the Trash and takes the source and its folder out of the config; the bundle's
  `extensionPreferences` (and passwords in the keychain) stay, so adding it back restores them.
- **State.** What's known of each clone (trusted, its branch and commit, the last check and error, what's new) is in
  `sources.json` next to the clones. The command line writes it too; a running input method reads it again. An entry it
  can't read is skipped; a file that isn't JSON is moved aside as `sources.json.bad-<date>`, never overwritten. Left-over
  staging and temporary folders an hour old are removed when the input method starts (a younger one may be in use).
- **A source's folder is only ever its bundle.** If its `extension.json` isn't a valid bundle (no `name`, say), the review
  and Settings say what's wrong, and its other scripts aren't loaded as single scripts instead (§1's fallback is for
  folders you add yourself).

**Command line** (on `~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME`):

| | |
|---|---|
| `--add-source URL [--path P] [--branch B] [--pin REF]` | clone into staging, print the review, put it in place and enable it (running it is the consent); also how a force-pushed source is reviewed again; non-zero on any error |
| `--update-sources` | check every reviewed source that isn't pinned and fast-forward it (a force-pushed one isn't moved: it says to run `--add-source` again); print what changed; non-zero if any failed |
| `--list-extensions` | the loaded commands (name, output, source or folder), those turned off or hidden, unreviewed source folders, and the files left out |

They take only these options (and `--config FILE`, `--sources-dir DIR` for tests); any other is refused.

There is no signature on a source: it runs what its repository holds, as you. Add only repositories you trust.

## 11. Completions

A command may also complete what you type (0.6.7.1): rows in the candidate panel as you type its prefix (`#12`,
`bm.sw`), the same rows, keys and choices as a plugin's completions (docs/plugins.md, "Completions"), from a list its
script prints, and, if it says so, a lookup of what follows the prefix. The command is still a command, run as before.

**Declaring it.** One source per command, with the keys of a plugin's `completions` entry, the same meaning, defaults
and limits: `prefix`, `minChars`, `compare`, `list`, `refresh`, `query`, `queryMinChars`, `insert` (a template, a list
of them tried in turn, or per class of app `default` / `chat` / `terminal`, `null` for no rows in that class). There is
no `name` or `title`: the source is the command's (its name, its title).

- A single script: one metadata line, any comment mark as other keys.

  ```bash
  #!/bin/bash
  # @allinoneime.schemaVersion 1
  # @allinoneime.title Tickets
  # @allinoneime.completion {"prefix": "TCK-", "list": true, "refresh": "15m", "query": true, "queryMinChars": 2, "insert": {"default": ["[{title}]({url})", "{arg}"], "terminal": "{match}"}}
  ```

- A bundle: `"completion"` in the command's entry, used over its script's own line, as the other keys are (§6).

  ```json
  { "script": "bookmarks.sh", "name": "bm", "title": "Bookmarks", "output": "list",
    "completion": { "prefix": "bm.", "list": true, "refresh": "1h",
                    "insert": { "default": "[{title}]({url})", "terminal": null } } }
  ```

A declaration that breaks the rules (a `query` without a `prefix`, a source without a prefix that isn't `exact` over
digits, a template that isn't one, a value out of range, anything but a JSON object) is refused on its own: Settings
says why under the command, and the command still loads.

**Running it.** As its commands run (§3: its folder or `currentDirectoryPath`, the PATH, its process group, its last
line on standard error as the error), with nothing on standard input, and limits of its own:

- **The list:** with `ALLINONEIME_COMPLETION=load` and no arguments, it prints
  `{ "items": [Item], "fetchedAt"?: unixSeconds }` as JSON on standard output. Up to 20 seconds (whatever its
  `timeout`), 20,000 items and 4 MB (the 64 KB of a command's output doesn't apply).
- **A lookup** (`query`): with `ALLINONEIME_COMPLETION=query` and what follows the prefix as its one argument (`$1`:
  `12` for `TCK-12`; never in the environment), it prints `{ "items": [Item] }`. Up to 3 seconds. It's called as a
  plugin's query is: once the token has `queryMinChars` after the prefix, then again only when what its answers give
  leaves fewer than 5 rows, after a pause of 150 ms in typing.
- **Environment:** `ALLINONEIME_PROTOCOL`, `ALLINONEIME_VERSION`, `ALLINONEIME_COMPLETION`, `ALLINONEIME_LANGUAGE` (the
  interface's), `ALLINONEIME_EXTENSION_DIR` and the bundle's `ALLINONEIME_PREF_<NAME>` (passwords from the keychain, as
  for its commands; while a required one has no value, it doesn't run and its status says what to set). Never the app
  in front, the language being typed or the token itself (`ALLINONEIME_APP`, `ALLINONEIME_INPUT_LANGUAGE` and
  `ALLINONEIME_QUERY` aren't set): a lookup gets only its argument.
- **`Item`**, as a plugin's: `{ match, title?, subtitle?, arg?, variables? }`, `match` (1–64 letters, digits and
  `. _ - @ #`, the prefix included) compared with the token, `title` and `subtitle` shown, `arg` (default `match`) and
  `variables` filling the templates (`{match}`, `{arg}`, `{url}`, `{title}`…: give `title`, the title alone, and `url` as
  variables for the Insert choices). Bad items are dropped one by one; an output that isn't an object with `items`, too
  large, a failure or a timeout keeps the old list and backs off (1 min, 5 min, 30 min, 2 h; the fifth in a row pauses
  it until Refresh now, an update or a day later).
- **One at a time.** One completion program of a bundle runs at a time (a bundle's programs may share state: a cookie
  file, a cache); the others wait their turn. A newer lookup for the same source cancels the one before, waiting or
  running (SIGTERM to its process group, then SIGKILL half a second later); the next program of the bundle starts only
  once a cancelled one has exited, so a script that cleans up on SIGTERM is done before it.
- The list is kept on this Mac (cached in `~/Library/Caches/AllInOneIME/suggestions/`, readable only by you) and loaded
  again every `refresh` while you use it, not after a week unused; rows you picked come first. Nothing runs, and no rows
  show, during secure input or in a password field.

**What a row puts in.** The first template the item fills that can go in there: one that starts with the token adds
what wasn't typed; one that doesn't (`[{title}]({url})`) takes the token's place where the text field tells where its
text is (the token, prefix and all, taken out and the text put in, one change you can undo as one), and is skipped for
the next elsewhere (terminals). The token is taken out only where the field still holds it when the row goes in (read
back first): where it holds other text there by then, what wasn't typed of the next template that starts with the token
goes in at the caret instead, or nothing; after a click elsewhere in the text, Tab, Return and the arrows are the app's.
Its `insert` is the default: Settings → General → Insert (With title, With title and
link, Markdown link) and each app's own choice apply to it, as to every source.

**Trust.** As a plugin's completions: off until you turn it on in Settings → Commands, under the command (its switch,
what it does: it runs this script in the background, and with `query` it also gets what you type after the prefix;
then its last refresh, items, last error and Refresh Now). Turning it on pins the command's script file (its
SHA-256: a single script's `completion` line is part of it), `query`, and the terms a plugin's source is pinned by: its
`prefix`, `queryMinChars` and `compare`. A change to any of them, an extension source's update or your own edit, turns
it off again, and Settings says so; until it's on again nothing of it runs, and a script file that changed since is
never run for it. Nothing else is pinned: another file of the bundle the script reads or sources (`lib/common.sh`), its
`refresh`, `minChars` and `insert` may change and it stays on. Turning the command or its bundle off turns its
suggestions off too.

