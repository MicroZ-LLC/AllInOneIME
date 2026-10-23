# Suggestions fixtures

What a completion plugin's script returns, and the files a plugin and a coding language pack are made of, for
`Acceptance/Suggestions*AcceptanceTests.swift` (spec: Suggestions v1). Generic examples only (GitHub issues of
`octo-org/octo-repo`, AWS's documentation account ids).

- `outputs/`: what `load(ctx)` or `query(text, ctx)` returns, as JSON.
  - `good-list.json`: a list with `fetchedAt` (2 hours before the tests' clock), titles, subtitles and `url` variables.
  - `good-query.json`: a query's answer; one of its items is also in `good-list.json` (merged once, the list's first).
  - `control-characters.json`: titles, subtitles, `arg` and variables with control characters (BEL, ESC, NUL, NEL),
    bidi controls (RLO, LRI/PDI, RLM, ALM), zero-width characters (ZWSP, ZWJ, ZWNJ, WJ), a BOM and a line separator:
    none of them is ever shown or inserted.
  - `bad-matches.json`: items whose `match` breaks the rules (empty, a space, a slash, 65 characters, an emoji, a quote,
    a number, missing) titled `BAD-…`, and items that aren't objects (a string, null), between two good ones: each bad
    one is dropped on its own, the good ones show (spec 6.5).
  - `stripped-matches.json`: matches with control, bidi or zero-width characters in them: good once those are taken
    out (`#6002`, `#6003`, `#6004`), or not (`BAD-…`: nothing left, a space left) (spec 6.6).
  - `duplicates.json`: the same `match` twice: shown once, the first.
  - `not-a-list.json`: `items` that isn't a list (other outputs that aren't an object with an `items` array are made by
    the tests).
  - Too large outputs (20,001 items; more than 4 MiB) are made by the tests (`SuggestionsFixtures.tooManyItems`,
    `tooManyBytes`) rather than kept here.
- `plugins/`: `github` (the spec's example: `#` issues, a list and a live query, a password preference) and `aws`
  (account ids, no prefix, `exact`), each a `plugin.json` and its `main.js`.
- `packs/`: coding language packs (`python`, `javascript`) in the pack format.
