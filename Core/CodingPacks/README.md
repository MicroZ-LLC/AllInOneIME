# Coding languages

Coding language packs (Suggestions v1, spec 2): what coding mode suggests besides the words already in the text field,
one JSON file per language. They are **not installed with the app**: the language library publishes them, like the
input languages' packs but listed apart (`coding-packs.json`, signed with the same key), and Settings → Coding languages
downloads the ones you code in.

```json
{ "language": "python", "title": "Python", "version": "1.0.0",
  "keywords": ["def", "class", "return"],
  "snippets": [ { "trigger": "def", "body": "def ${1:name}(${2}):\n    $0", "title": "function" } ] }
```

- `language`: the pack's id, 1–32 small letters, digits, `+`, `#` or `-`; the file's name.
- `keywords`: words offered from 2 typed characters on (one typed in full isn't).
- `snippets`: offered while what is typed starts the `trigger` (the whole trigger too); the `body` goes in as text, its
  line breaks kept, `${n:text}` as its text, `${n}` and `$n` as nothing, the caret at `$0` (where the field reports
  where its caret is; else at the end). No tab stops beyond the caret.
- At most 2,000 keywords and 500 snippets (a body of 4,000 characters at most), 1 MiB in all.

`make coding-packs` writes each pack and its index entry (`build/coding-packs/<language>-<version>.json` and `.json.entry`);
`swift Scripts/build-packs-index.swift --coding OUT_DIR build/coding-packs/*.entry` writes and signs `coding-packs.json`.
The packs' files are release assets of the language library, as the input languages' packs are.

| Pack | Keywords | Snippets |
| --- | --- | --- |
| `python` | Python's keywords, common builtins | `def`, `class`, `ifmain`, `for`, `with`, `try`, `print` |
| `javascript` | JavaScript's keywords, common globals | `function`, `arrow`, `for`, `if`, `try`, `console`, `import` |
