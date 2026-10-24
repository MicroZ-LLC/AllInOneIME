# Coding languages

Coding language packs (Suggestions v1, spec 2; decision 22): what the Code input suggests besides the words already in
the text field, from the pack of Code's language (one at a time), one JSON file per language. They are **not installed
with the app**: the language library publishes them, like the input languages' packs but listed apart
(`coding-packs.json`, signed with the same key). Picking a language for Code (Settings → Input, or the input menu)
downloads its pack; the Input page lists the packs installed and the library.

```json
{ "language": "python", "title": "Python", "version": "1.0.0",
  "keywords": ["def", "class", "return"],
  "builtins": ["len", "range"],
  "snippets": [ { "trigger": "def", "body": "def ${1:name}(${2}):\n    $0", "title": "function" } ] }
```

- `language`: the pack's id, 1–32 small letters, digits, `+`, `#` or `-`; the file's name.
- `keywords`: the language's keywords, offered from 2 typed characters on (one typed in full isn't).
- `builtins` (optional): its built-in functions, types and constants, and common library names, offered as keywords
  are, after them.
- `snippets`: offered while what is typed starts the `trigger` (the whole trigger too) and the body starts with what is
  typed (so `include` for `#include`, `const` for an arrow function); the `body` goes in as text, its line breaks kept,
  its second and later lines indented as the line the caret is on, `${n:text}` as its text, `${n}` and `$n` as nothing.
  Where the field reports where its caret is, the caret goes to the first tab stop in reading order, whichever comes
  first of `$0` and the numbered ones (`$1`, `${1:…}`); a numbered one so chosen is left empty, its text out wherever it
  is (its mirrors too), and the others keep theirs (`try:\n    $0\nexcept ${1:Exception}:` puts the caret in the try
  block, `Exception` kept). Elsewhere every stop keeps its text and the caret stays at the end. No tab stops beyond the
  caret: put the place to type first first. A trigger may have several snippets; two that go in exactly alike are one
  row. A row's comment is the snippet's `title` (or "snippet" where the title is only the trigger), a keyword's
  "keyword", a built-in's "built-in": never the language, which is Code's.
- At most 2,000 keywords, as many built-ins and 500 snippets (a body of 4,000 characters at most), 1 MiB in all.

`make coding-packs` writes each pack and its index entry (`build/coding-packs/<language>-<version>.json` and `.json.entry`);
`swift Scripts/build-packs-index.swift --coding OUT_DIR build/coding-packs/*.entry` writes and signs `coding-packs.json`.
The packs' files are release assets of the language library, as the input languages' packs are.

| Pack | Keywords and built-ins | Snippets' triggers |
| --- | --- | --- |
| `c` | C's keywords, the preprocessor's, common types and library functions | `int` (main), `include`, `define`, `ifndef`, `if`, `else`, `for`, `while`, `do`, `switch`, `struct`, `typedef`, `enum`, `void`, `printf`, `fprintf`, `scanf`, `malloc` |
| `cpp` | C++'s keywords, the preprocessor's, common `std` names | `int` (main), `include`, `pragma`, `using`, `class`, `struct`, `template`, `namespace`, `enum`, `void`, `if`, `else`, `for`, `while`, `do`, `switch`, `try`, `cout`, `cin`, `vector`, `sort`, `auto`, `throw` |
| `go` | Go's keywords, builtins and common types | `func`, `package`, `import`, `if`, `else`, `for`, `switch`, `type`, `go`, `defer`, `fmt`, `errors`, `make` |
| `java` | Java's keywords, common classes | `public`, `private`, `class`, `interface`, `enum`, `record`, `if`, `else`, `for`, `while`, `do`, `switch`, `try`, `System`, `import`, `package`, `throw`, `List`, `Map`, `Scanner` |
| `javascript` | JavaScript's keywords, common globals | `function`, `const`, `for`, `if`, `try`, `console`, `import` |
| `python` | Python's keywords, common builtins and exceptions | `def`, `async`, `class`, `if`, `elif`, `else`, `for`, `while`, `try`, `with`, `import`, `from`, `lambda`, `print`, `raise`, `match` |
| `typescript` | TypeScript's keywords, its types and utility types, common globals | `function`, `async`, `const`, `class`, `constructor`, `interface`, `type`, `enum`, `if`, `else`, `for`, `while`, `switch`, `try`, `import`, `export`, `console`, `setTimeout`, `throw` |

The Core tests (SuggestionsCodingPacksTests.swift) check every pack here: kept as a downloaded one is, no word twice nor
both a keyword and a built-in, every word offered saying which it is, each snippet offered for its trigger.
