#!/usr/bin/env python3
"""Merges reviewed translations into the interface text's String Catalogs.

    Scripts/import-translations.py DIR [--lang CODE]... [--dry-run]

DIR holds one JSON file per language, <code>.json (zh-Hant.json, ja.json, pt-BR.json, ...), each an object that maps
"<catalog>\t<key>" to the translation of that key: <catalog> is "core" (Core/Resources/Localizable.xcstrings, the
core's text) or "app" (Resources/Localizable.xcstrings, the macOS app's own), <key> the catalog's key (the English
format, or a key of its own such as "account.notSubscribed"). Without --lang, every <code>.json in DIR.

Each value goes in as localizations[<code>].stringUnit = {state: "translated", value}, replacing what that language had
for the key. English ("en", which only keys of their own have) is never written. A value is refused, and the catalogs
keep what they had for it, when:
  - its catalog or key isn't in the catalogs;
  - its format doesn't read: a "%" that isn't "%%", "%@" or "%n$@" (what InterfaceText.fill takes);
  - its placeholders differ from the key's (the English value's, for a key of its own): it must refer to the same
    arguments, each of them, in any order ("%2$@ ... %1$@" for "%@ ... %@").
A different count of "%%" (a literal "%") is only reported.

The catalogs keep their order and layout (as the strings tool writes them), so `make strings` changes nothing after
this. Exits 1 when a value was refused (the others are written anyway, unless --dry-run), 2 on bad usage.
"""

import argparse
import collections
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOGS = {
    "core": ROOT / "Core" / "Resources" / "Localizable.xcstrings",
    "app": ROOT / "Resources" / "Localizable.xcstrings",
}
TOKEN = re.compile(r"%(?:(%)|(@)|([0-9]+)\$@)")


def placeholders(text):
    """The arguments `text` refers to (0-based, each once) and its count of "%%"; None when it doesn't read."""
    referenced, literal, sequential, i = [], 0, 0, 0
    while True:
        i = text.find("%", i)
        if i < 0:
            return collections.Counter(referenced), literal
        match = TOKEN.match(text, i)
        if not match:
            return None
        if match.group(1):
            literal += 1
        elif match.group(2):
            referenced.append(sequential)
            sequential += 1
        else:
            position = int(match.group(3))
            if position < 1:
                return None
            referenced.append(position - 1)
        i = match.end()


def read(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write(catalog, path):
    # As JSONSerialization writes it (.prettyPrinted, .sortedKeys, .withoutEscapingSlashes): the strings' order is the
    # file's own, kept; new entries' keys are put in sorted order.
    text = json.dumps(catalog, indent=2, separators=(",", " : "), ensure_ascii=False) + "\n"
    if path.read_text(encoding="utf-8") != text:
        path.write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("dir", type=pathlib.Path)
    parser.add_argument("--lang", action="append", default=[])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    languages = args.lang or sorted(p.stem for p in args.dir.glob("*.json"))
    if not languages:
        print(f"import-translations: no <code>.json in {args.dir}")
        return 2
    if "en" in languages:
        print("import-translations: English comes from the code; en.json isn't read")
        languages.remove("en")

    catalogs = {name: read(path) for name, path in CATALOGS.items()}
    refused, warnings = [], []
    counts = collections.Counter()
    for language in languages:
        path = args.dir / f"{language}.json"
        if not path.exists():
            print(f"import-translations: {path} not found")
            return 2
        for entry_key, value in read(path).items():
            name, _, key = entry_key.partition("\t")
            where = f"{language} {name} {key!r}"
            strings = catalogs.get(name, {}).get("strings")
            if strings is None or key not in strings:
                refused.append(f"{where}: no such key in the catalogs")
                continue
            if not isinstance(value, str) or not value:
                refused.append(f"{where}: empty")
                continue
            entry = strings[key]
            localizations = entry.get("localizations", {})
            english = ((localizations.get("en") or {}).get("stringUnit") or {}).get("value", key)
            source, translated = placeholders(english), placeholders(value)
            if translated is None:
                refused.append(f"{where}: {value!r} has a % that is not %%, %@ or %n$@")
                continue
            if source is not None and source[0] != translated[0]:
                refused.append(f"{where}: {value!r} refers to other arguments than {english!r}")
                continue
            if source is not None and source[1] != translated[1]:
                warnings.append(f"{where}: {translated[1]} %% for the English's {source[1]}")
            unit = {"state": "translated", "value": value}
            old = localizations.get(language)
            if old == {"stringUnit": unit}:
                counts[language, "same"] += 1
                continue
            counts[language, "new" if old is None else "changed"] += 1
            localizations = dict(localizations)
            localizations[language] = {"stringUnit": unit}
            entry["localizations"] = dict(sorted(localizations.items()))
            strings[key] = dict(sorted(entry.items()))

    for language in languages:
        print(f"{language}: {counts[language, 'new']} added, {counts[language, 'changed']} changed, "
              f"{counts[language, 'same']} already there")
    for warning in warnings:
        print(f"note: {warning}")
    for refusal in refused:
        print(f"refused: {refusal}")
    if not args.dry_run:
        for name, path in CATALOGS.items():
            write(catalogs[name], path)
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main())
