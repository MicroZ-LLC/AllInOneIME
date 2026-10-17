#!/usr/bin/env python3
# Translates the wiki's English pages into its Chinese pages with Claude, so the wiki is written in English only.
#
#   python3 Scripts/translate-wiki.py WIKI_DIR [--page Commands] [--force] [--dry-run]
#
# WIKI_DIR is a clone of https://github.com/MicroZ-LLC/AllInOneIME.wiki.git. Run from this repository: the app's own
# Chinese UI wording (`tr("中文", "English")` in Sources) and the Chinese screenshots (docs/ beside docs/en/) come
# from it. Needs ANTHROPIC_API_KEY.
#
# Each Chinese page ends with a comment naming the SHA-256 of the English page it was translated from; a page whose
# English is unchanged is skipped. The previous translation goes along with the English, so wording that still fits
# is kept and a small change makes a small diff. .github/workflows/wiki-zh.yml runs this when the wiki is edited.

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

MODEL = "claude-opus-5-5"

# English page → Chinese page (file names without .md, as in wiki links).
PAGES = {
    "Home": "首页",
    "Installation-and-Troubleshooting": "安装与排查",
    "Commands": "@命令",
    "Settings-and-Configuration": "设置与配置",
    "Voice-Input": "语音输入",
    "Rewrite-Styles-and-Jargon": "改写风格与黑话库",
    "Privacy": "隐私",
    "Development": "开发",
    "FAQ": "常见问题",
}

MARKER = re.compile(r"\n*<!-- translated from (\S+)\.md sha256:([0-9a-f]{64}) -->\s*$")

SYSTEM = """You translate pages of the AllInOneIME wiki (a macOS input method with AI commands) from English into \
Simplified Chinese. Reply with the translated page only, in Markdown, with nothing before or after it.

- The English page is the source of truth: translate all of it, keeping its structure, headings, tables, lists, code \
blocks, examples and URLs. Code, commands (`@improve`), keys (⌥, ⏎), file paths and config keys stay as they are.
- The first line links back to the English page: `[English](<English page name>)`, in place of the English page's \
`[中文](…)` line.
- Links to other wiki pages use their Chinese names: {links}. Anchors follow the Chinese headings.
- A link to the README goes to the Chinese one: https://github.com/MicroZ-LLC/AllInOneIME/blob/mainline/README.zh-CN.md \
(with the same #anchor translated, if any). Keep image URLs exactly as they are; translate their alt text.
- Settings, menus, buttons and messages use the app's own Chinese wording (the glossary below), and macOS uses \
Apple's Simplified Chinese names (系统设置、隐私与安全性、键盘、输入法 …).
- Style: plain, clear, natural Chinese in short sentences. 「」 around UI names; a space between Chinese and Latin \
words or numbers; full-width Chinese punctuation outside code.
- If a previous translation is given, keep its wording wherever the English still says the same thing, and change \
only what the English changed."""


def ui_glossary(repo: Path, text: str) -> str:
    """The app's `tr("中文", "English")` pairs whose English appears on the page."""
    pairs = {}
    pattern = re.compile(r'tr\("((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)')
    for source in (repo / "Sources").rglob("*.swift"):
        for chinese, english in pattern.findall(source.read_text()):
            if "\\(" in english or len(english) < 3:
                continue
            if english in text:
                pairs[english] = chinese
    return "\n".join(f"{english} = {chinese}" for english, chinese in sorted(pairs.items()))


def chinese_screenshots(repo: Path, page: str) -> str:
    """docs/en/X → docs/X where the Chinese screenshot exists at the same commit."""
    def swap(match):
        sha, name = match.group(1), match.group(2)
        found = subprocess.run(["git", "-C", str(repo), "cat-file", "-e", f"{sha}:docs/{name}"],
                               capture_output=True).returncode == 0
        return match.group(0).replace(f"/docs/en/{name}", f"/docs/{name}") if found else match.group(0)
    return re.sub(r"raw\.githubusercontent\.com/MicroZ-LLC/AllInOneIME/([0-9a-f]{7,40})/docs/en/([\w.-]+)", swap, page)


def translate(english_name: str, english: str, previous: str | None, glossary: str) -> str:
    links = ", ".join(f"{en} → {zh}" for en, zh in PAGES.items())
    parts = [f"English page: {english_name}\n\n<english>\n{english}\n</english>"]
    if previous:
        parts.append(f"<previous_translation>\n{previous}\n</previous_translation>")
    if glossary:
        parts.append(f"<glossary>\n{glossary}\n</glossary>")
    # Claude Code with no tools: only the text goes in and only the page comes out.
    result = subprocess.run(
        ["claude", "-p", "--model", MODEL, "--system-prompt", SYSTEM.format(links=links), "--tools", "",
         "--output-format", "json", "--no-session-persistence"],
        input="\n\n".join(parts), capture_output=True, text=True, cwd=tempfile.gettempdir(), timeout=1800)
    try:
        reply = json.loads(result.stdout)
    except ValueError:
        reply = {}
    if result.returncode or reply.get("is_error") or reply.get("subtype") != "success":
        raise RuntimeError(f"{english_name}: {reply.get('result') or result.stderr.strip()[-1000:]}")
    return reply["result"].strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("wiki", type=Path)
    parser.add_argument("--page", action="append", help="only this English page (repeatable)")
    parser.add_argument("--force", action="store_true", help="translate even if the English is unchanged")
    parser.add_argument("--dry-run", action="store_true", help="only list the pages that would be translated")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent

    changed = 0
    for english_name, chinese_name in PAGES.items():
        if args.page and english_name not in args.page:
            continue
        english = (args.wiki / f"{english_name}.md").read_text()
        digest = hashlib.sha256(english.encode()).hexdigest()
        chinese_file = args.wiki / f"{chinese_name}.md"
        previous = chinese_file.read_text() if chinese_file.exists() else None
        mark = MARKER.search(previous) if previous else None
        if mark and mark.group(2) == digest and not args.force:
            continue
        print(f"{english_name} → {chinese_name}", flush=True)
        changed += 1
        if args.dry_run:
            continue
        previous_body = MARKER.sub("", previous) if previous else None
        page = translate(english_name, english, previous_body, ui_glossary(repo, english))
        page = chinese_screenshots(repo, page)
        chinese_file.write_text(f"{page}\n\n<!-- translated from {english_name}.md sha256:{digest} -->\n")
    print(f"{changed} page(s) {'to translate' if args.dry_run else 'translated'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
