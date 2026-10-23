# Plugins: plan

@ commands come in three tiers: **built-in** (`@improve`, `@translate`, `@question`, `@agent`, `@open`, `@note`,
`@reminder`, `@py`, `@js`, `@tasks`, `@settings`, `@imessage`, `@reportissue`;
`@read` and `@search` are built but not offered yet, their names still taken), **plugins** installed from the plugin
library (what not everyone wants, like `@stock`), and the user's **custom** commands (Settings → Custom @ Commands).
When names clash: built-in > plugin > custom, so a plugin named like a built-in command never shows up.

## What a plugin is

A folder in `~/.config/allinoneime/plugins/<name>/`:

- `plugin.json`, the manifest:
  ```json
  { "name": "stock", "version": "1.0.0", "api": 1, "minAppVersion": "0.3.0",
    "type": "script",
    "summary": {"en": "Stock quotes: @stock AAPL 600519 700", "zh": "股票行情：@stock AAPL 600519 700"},
    "script": "main.js", "hosts": ["query1.finance.yahoo.com"],
    "timeoutSeconds": 10, "ascii": true,
    "author": "weijianz-opc", "homepage": "https://github.com/MicroZ-LLC/AllInOneIME-plugins",
    "icon": "chart.line.uptrend.xyaxis", "color": "green" }
  ```
  `type` is `script` (JavaScript, below), `prompt` (an AI instruction in `prompt`, like a custom command) or
  `link` (a web address opened in the browser, below).
  `icon` (an SF Symbol name) and `color` (`blue`, `green`, … or `#RRGGBB`) draw it in the command list.
- `main.js` for a script plugin: `function run(input, context) { return "one line" }`. A `throw` is the error
  shown. `context` is below; `function run(input)` works too.
- `install.json`, written when installed from the library: `{version, files: {name: sha256}, source: "registry"}`.
  A folder without it is a **local** plugin (an author's, not reviewed).

## Link plugins

A `link` plugin runs no code: the text after the command goes into a web address, which opens in the default
browser. Nothing is inserted; the draft is cleared, as when `@open` opens something. Made for "share" and
"compose" pages, where the user posts it themselves, signed in as usual:

```json
{ "name": "x", "version": "1.0.0", "api": 1, "minAppVersion": "0.5.0", "type": "link",
  "url": "https://x.com/intent/post?text={input}",
  "summary": {"en": "Post to X: opens the composer with your text", "zh": "发到 X：打开发帖框，文字已填好"},
  "author": "weijianz-opc", "icon": "bird", "color": "#000000" }
```

- `url` is required: `https://`, with `{input}` exactly once, in the query or the fragment (after `?` or `#`), so
  the text can never choose the host or the path. Its host is the plugin's host ("the text after @x goes to
  x.com"); `script` and `hosts` aren't used.
- The text is percent-encoded as a query value: everything but `A–Z a–z 0–9 - . _ ~` as UTF-8, a space as `%20`
  (not `+`), a newline as `%0A`. At most 4000 characters (longer: an error, and the draft stays).
- Nothing after the command: like any command, the action key only says to write something (paste the clipboard's
  text into the command with ⌃V, or ⌘V outside terminals); the page never opens empty from the input method. With
  text selected in the field, the selection is the text.
- Not a command inside a text (it fetches nothing), but it can be the outer one: `@x 今天 @stock AAPL 涨了` runs
  `@stock` first and opens the link with its output in the text.
- Refused during secure input, like every command.
- Custom commands have the same type (`{"name": "google", "type": "link", "url": "https://www.google.com/search?q={input}"}`,
  or "Open a web page" in Settings → Custom @ Commands).

[Core/Plugins/](../Core/Plugins/) in the repository has `@x`, `@threads`, `@bsky` and `@weibo`, and a script plugin, `@xe`
(currency conversion, `@xe 100 USD CNY`); the library publishes them.

## How a script runs

In a **child process**: `AllInOneIME --run-plugin <dir> --language zh|en` with the text on standard input, the
result on standard output. The engine is JavaScriptCore on the Mac (part of macOS: nothing to install), and
QuickJS-ng (built into the app) on Windows, Linux and Android. JavaScriptCore can't stop a running script, and
QuickJS-ng only where it checks (some of its built-in functions run to their end), so a stuck plugin must not run
inside the input method; a child process is killed by the existing runner (timeout, output limit, Esc), the same
path as custom `run` commands.

### Two engines: write for both

Both are modern JavaScript, and a plugin runs the same on either as long as it keeps to what they share. Where they
differ, measured (QuickJS-ng 0.17.0, macOS 27's JavaScriptCore):

| | QuickJS-ng | JavaScriptCore |
|---|---|---|
| `Intl` (`Intl.NumberFormat`, `Intl.DateTimeFormat`, …) | none | there |
| `(1234.5).toLocaleString()` | `1234.5` | `1,234.5` |
| `localeCompare`, so sorting by it | by code point: `Z,a,b,ä,é` | by language: `a,ä,b,é,Z` |
| `String(new Date(0))` (`Date#toString`), in California | `… GMT-0800` | `… GMT-0800 (Pacific Standard Time)` |
| Globals only one has | `atob`, `btoa`, `performance`, `queueMicrotask`, `DOMException`, `InternalError`, `SharedArrayBuffer`, `DisposableStack`, `AsyncDisposableStack`, `SuppressedError` | `Intl`, `WebAssembly`, `console` |

So: format numbers and dates yourself (`toFixed`, `getFullYear()` and the like, or the ISO form,
`toISOString()`), compare text with `<` or your own order rather than `localeCompare`, and don't use the globals
only one engine has (on the Mac, `btoa` is a ReferenceError).

The script sees nothing but `fetch`:

```js
fetch(url, {headers}) → {status, ok, text, json()}              // throws when the request fails
fetch([url, …], {headers}) → [{status, ok, text, json()} | {ok: false, error}]   // in parallel
```

- HTTPS only, and only to the manifest's `hosts` (redirects too); no cookies, no cache.
- At most 8 requests a run, 1 MB a response, 5 s a request; the run itself ends after `timeoutSeconds` (≤ 20).
- No file system, processes, environment, timers or clipboard: neither engine has them, as the app makes it.
- Secure input (password fields) refuses plugins like any command.
- The text goes to the plugin's hosts as typed: "Hide sensitive information before sending" (Settings → AI Provider →
  Privacy) covers requests to the AI, so a `prompt` plugin, but not what a script or link plugin sends. Likewise an
  app set to "No AI in this app" (Settings → Apps) refuses `prompt` plugins and still runs script and link plugins.

`run(input, context)` gets the text (trimmed) and a plain object, `context`:

- `context.language` (from 0.6.5): `"zh"` or `"en"`, the language the input method's own interface is showing
  (config `uiLanguage`, the settings window's "Interface language", else the system's), so a plugin can answer
  in it. Older apps call `run(input)` alone (and an unknown language leaves `{}`), so don't rely on it: read
  it as `(context && context.language) || "en"`.
- `context.preferences` (from 0.6.7), for a plugin that declares `preferences` (see Completions below): its settings as
  `load` and `query` get them, the defaults filled in, passwords too (on standard input, never on a command line:
  `AllInOneIME --run-plugin <dir> --with-preferences` reads `{ "input", "preferences" }` there).
- Nothing else: not the app being typed in, the field, or anything about the user.

## The library (milestone 2, done)

A public repo [`MicroZ-LLC/AllInOneIME-plugins`](https://github.com/MicroZ-LLC/AllInOneIME-plugins), served from
`https://plugins.allinoneime.com/` (`PluginLibrary.defaultBaseURL`; a Cloudflare Worker, `site/`, passing on its
main branch's files; 0.5.0 reads `raw.githubusercontent.com/…/main/` directly):

- `plugins/<name>/<version>/`: `plugin.json` and its files. A version folder never changes once published (CI
  refuses a pull request that modifies one); an update is a new folder.
- `index.json`, every version (newest first):
  ```json
  { "schema": 1, "generated": "2026-10-10T12:00:00Z",
    "plugins": [{ "name": "stock", "version": "1.0.0", "api": 1, "minAppVersion": "0.2.0", "type": "script",
                  "summary": {"en": "…", "zh": "…"}, "hosts": ["query1.finance.yahoo.com"],
                  "author": "…", "homepage": "…", "icon": "…", "color": "green",
                  "base": "plugins/stock/1.0.0/", "files": {"main.js": "<sha256>", "plugin.json": "<sha256>"} }] }
  ```
  A `link` plugin's entry also carries its `url`.
- `index.json.sig`: the Ed25519 signature (base64) of the exact bytes of `index.json`. The public key is built into
  the app (`PluginLibrary.publicKey`); the private key lives only in the maintainer's login keychain. Hashes alone
  aren't enough: whoever can push to the repo could change files and hashes together.
- `scripts/build-index` (a Swift script, CryptoKit) validates every plugin (schema, name = folder, https host names,
  sizes, plain file names, no `eval(` / `Function(` / `new Function`), writes `index.json` and signs it with the key
  from the keychain. CI runs it with `--validate` on pull requests and `--check` on main (the index matches the
  plugins, the signature is valid); CI can't sign. Only the maintainer merges.

In the app (`PluginLibrary`, Settings → Plugins → "Browse Library…"):

- Network only when the user opens or refreshes the library, or installs: no background polling.
- The signature is verified **before** the index is parsed; an unknown `schema` is refused. Offered is, per plugin,
  the newest version whose `api`, `minAppVersion` and `type` this app supports.
- Installing first shows what the plugin contacts ("what you type after @stock goes to query1.finance.yahoo.com").
  Then: names must be 1–24 lowercase letters, file names plain (no `/`, `..`, leading `.`, `install.json`), `base`
  a plain relative path under the library. Every file is downloaded into `<name>.tmp/` and checked against its sha256;
  `plugin.json` must match the entry (name, version, hosts) and be usable; `install.json` is written; then the folder
  is swapped into place in one step (`renamex_np` with `RENAME_SWAP`). Any failure removes the temporary folder and
  leaves the installed version as it was.
- A library plugin with a newer version in the index gets an "Update" button (in the library list and next to the
  installed plugin); updates are manual. A local plugin (no `install.json`) of the same name is never overwritten:
  the library shows it as local.
- Installing or removing a plugin rescans the plugins folder, so the command list has it at the next keystroke.

## Completions (suggestions)

A `script` plugin may also complete what is typed (Suggestions, 0.6.7): rows in the candidate panel, Tab inserts one.
It declares its sources in `completions` (optional; `api` 1 stays valid) and its settings in `preferences`:

```json
{ "name": "github", "type": "script", "script": "main.js", "hosts": ["api.github.com"],
  "preferences": [
    { "name": "repos", "type": "text", "title": {"en": "Repositories", "zh": "仓库"},
      "placeholder": "owner/repo, owner/other", "default": "MicroZ-LLC/AllInOneIME" },
    { "name": "token", "type": "password", "title": {"en": "Token (optional, for private repositories)", "zh": "Token（可选，私有仓库用）"} } ],
  "completions": [
    { "name": "issues", "title": {"en": "GitHub issues", "zh": "GitHub issue"},
      "prefix": "#", "minChars": 1, "compare": "prefix",
      "list": true, "refresh": "15m",
      "query": true, "queryMinChars": 2,
      "insert": { "default": ["{arg} {title}", "{arg}"], "chat": ["{arg} {title} {url}", "{arg} {url}", "{arg}"],
                  "terminal": "{match}" } } ] }
```

| Key | Default | Meaning |
|---|---|---|
| `name` | required | `[a-z0-9]{1,24}`, unique in the plugin |
| `title` | required | shown in Settings and in the rows' footer |
| `prefix` | none | the text a token starts with (`#`, `PROJ-`; any case, `＃` counts as `#`); not `@` |
| `minChars` | 1 with a prefix, 3 without | characters after the prefix before rows show |
| `compare` | `prefix` | `prefix` (`#12` shows `#1234`) or `exact`; without a prefix only `exact`, and only for tokens of digits (a 12-digit account id) |
| `list` | `false` | the script exports `load(ctx)`; its last good list is kept |
| `refresh` | `1h` | `5m` … `7d`: how often the list is loaded again while the source is used (not after a week unused) |
| `query` | `false` | the script exports `query(text, ctx)`, a live lookup; only with a `prefix` (without one, every number typed anywhere would be sent) |
| `queryMinChars` | 3 | characters after the prefix before `query` is first called (at least 1) |
| `insert` | `{"default": "{arg}"}` | what a row inserts per app class: `default`, `chat` (chat apps and browsers), `terminal` (terminals and code editors: anything but `null` is `{match}` there); a template or a list tried in turn (the first whose variables all exist), `null` for no rows in that class |

An entry that breaks these rules (or any entry of a `prompt` or `link` plugin, or of one with `timeoutSeconds` over 20) is
refused on its own, its reason shown under the plugin in Settings; the plugin and its command still load. A preference is
`text` (kept in the config) or `password` (kept in the keychain, like extensions' passwords); one of another type is the
plugin's problem.

The script, in its child process as `run` is (`AllInOneIME --run-plugin <dir> --completion load|query`, `ctx` on standard
input), with the same `fetch` to its `hosts`: those the user approved when turning the source on, and only while
plugin.json still lists them (the hosts approved come on standard input too):

- `load(ctx)` returns `{ items: [Item], fetchedAt?: unixSeconds }`, the whole list: at most 20,000 items and 4 MB. It may
  take the plugin's `timeoutSeconds` (20 at most).
- `query(text, ctx)` returns `{ items: [Item] }`; `text` is only what follows the prefix (`"12"` for `#12`). 3 seconds at
  most. It's called once the token has `queryMinChars` after the prefix, then again only when what its answers give for
  the longer token leaves fewer than 5 rows (after a pause of 150 ms in typing), one call at a time; a newer token
  cancels the call before.
- `Item`: `{ match, title?, subtitle?, arg?, variables? }`: `match` (1–64 letters, digits and `. _ - @ #`, the prefix
  included) is what the token is compared with; `title` and `subtitle` are what the row shows; `arg` (default `match`)
  and `variables` (texts of the plugin's choosing) fill the templates: `{match}`, `{arg}`, and any of the item's
  variables by name (`{url}`, `{title}`…). The order is the rank; the rows the user picked before come first.
- What a row puts in is the plugin's to decide, per app class, in `insert`: the number alone (`{arg}`), with its title
  (`{arg} {title}`), or with a link too (`{arg} {title} {url}`). The example inserts `#1234 Fix login` in documents and
  mail, `#1234 Fix login https://github.com/…/issues/1234` in chat apps, and `#1234` in terminals; a template whose
  variables an item lacks is skipped for the next in its list.
- `ctx` is `{ source, preferences, language }` (`"zh"` or `"en"`): nothing about the app, the field or the text around
  the caret.
- An output that isn't an object with an `items` array, too large, a throw or a timeout keeps the old list; failures
  back off (1 min, 5 min, 30 min, 2 h) and the fifth in a row pauses the source until Refresh now, an update or a day
  later. Bad items are dropped one by one; control, bidi and zero-width characters are taken out of everything first.
- Only what wasn't typed goes in: `#12` and the row `#1234` insert `34` and the rest of the template.

The user turns each source on in Settings → Plugins; the switch says what it does and, for a source with `query`, where
what is typed after the prefix goes. An update that changes `hosts`, `query`, the script, or the source's `prefix`,
`queryMinChars` or `compare` needs turning on again.
[Core/Plugins/github](../Core/Plugins/github/) is the example.

### Without a plugin: a custom command

A custom command of type `suggestions` is a source of the same kind, for a program of your own (a CLI that lists your
tickets, say): `prefix`, `minChars`, `compare`, `refresh`, `query`, `queryMinChars` and `insert` mean what they mean
above, with the same limits and defaults; a prefix is required, and the list is always on. Its `argv` runs as a `run`
command's does, with no input for the list and, with `query`, what follows the prefix as one argument (in place of
`{input}`, else last); `timeoutSeconds` is 20 at most, a query's 3 seconds. It may print the `{ items }` above, or lines
`match⇥title⇥url` (a title is also `{title}`). It's the user's own: no approval and no `hosts` (it runs locally), on
while it exists; rows, keys, picks, the cache, back-off and pause are a plugin source's. An entry that breaks the rules
isn't a source, and Settings → Custom Commands says why.

```json
{ "name": "jira", "type": "suggestions", "summary": "Jira issues", "prefix": "PROJ-",
  "argv": ["/Users/me/bin/jira-list"], "timeoutSeconds": 10, "refresh": "1h",
  "insert": { "default": ["{arg} {title}", "{arg}"], "chat": ["{arg} {title} {url}", "{arg}"] } }
```

A 10-line program, and the editor's presets: [README, Suggestions from a program of your own](../README.md#suggestions-from-a-program-of-your-own-new).

## Milestones

1. **@stock end to end, installed by hand** (this branch): manifest and store, the JavaScript host with
   `fetch`, the child-process runner, plugins in the command list, a Plugins section in Settings (installed
   plugins, uninstall, open the folder), tests with recorded Yahoo responses.
2. **Library** (done): signed index, browse / install / update in Settings, the registry repo with CI and a signing script.
3. **More**: prompt plugins in the library, update all, author documentation.

## Commands inside a text (nested @)

`@reply 告诉他 @stock AAPL 现在多少钱`: commands that fetch something (plugins and custom programs) can sit
inside the text. They run first, together; each one's output takes its place; then the outer command (or
@improve, without one) works on the result. An inner command is a known name after `@` (not after a letter or
digit: `a@b.com` stays text), a space, and its argument: a word, plus the words right after it without lowercase
letters (`AAPL TSLA`, `600519 700`; `@stock SNDK is good to buy` takes `SNDK`), or the text in 「…」 / quotes. `@张三` and anything else stay as typed.

**One model call at most.** Only commands that run code or fetch data go inside a text; the AI runs once, as the
outer command. An AI command inside a text (`@question …` after `@reply`) stays text, and the model never plans
the order: whoever needs that much opens a session (`@agent`) or Terminal. This keeps every command quick,
predictable and one request's worth of cost.

Commands that **send** something run last, on the final text, only after the user confirms in the candidate panel.
The first one is built in: `@imessage` picks the recipient from Contacts in the panel, runs the commands inside the
message, shows "Send to 张三 (…): …" and sends only on a second ⏎ (Esc goes back to editing); nothing is inserted.
The recipient model and the sender (`Recipient`, `MessageSender`) are meant for more of them. Next: plugins that send
(`@slack 张三`), with stored credentials (keychain) and their own targets (person, thread) to pick from the candidates.
