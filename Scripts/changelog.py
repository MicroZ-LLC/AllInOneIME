#!/usr/bin/env python3
# The changelog, one fragment per change. CHANGELOG.md and CHANGELOG.zh-CN.md are the release notes, and when every
# change wrote its lines into their unreleased section, parallel PRs collided there more than anywhere else. So a change
# a user would notice adds one file of its own instead, changes/<slug>.md (the slug unique to its branch: the
# pipeline's issue-N, or a branch's name after its version, 0.7.5/caps-lock's changes/caps-lock.md):
#
#   ---
#   section: Fixed
#   ---
#
#   ## en
#
#   - What the user sees and does, as the changelog's entries say it.
#
#   ## zh-CN
#
#   - 同一条，用中文。
#
# section is Added, Changed or Fixed; both languages have the same entries, each a `- ` list item (a long one may go on
# in lines indented by two spaces). A release writes the fragments into both changelogs, after the entries their
# unreleased section already has (from before fragments), oldest commit first, and removes them. changes/README.md is
# the guide, not a fragment. Python 3.9 (macOS's), nothing to install.
#
#   Scripts/changelog.py check [--base REF]        the fragments are well formed; with REF (make lint's LINT_BASE, CI's:
#                                                  the PR's base), also that neither changelog's unreleased section
#                                                  changed since this branch left REF (their merge base)
#   Scripts/changelog.py preview                   what `release` would print: the next release's notes, unreleased
#                                                  entries and fragments together; it changes nothing
#   Scripts/changelog.py release X.Y.Z YYYY-MM-DD  dates the unreleased section X.Y.Z in both changelogs (adding one
#                                                  if there is none) with the fragments in it, git rm's the fragments,
#                                                  and prints the GitHub release's notes (Markdown, on stdout)

from __future__ import annotations

import argparse
import datetime as dt
import math
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parent.parent
FRAGMENTS = "changes"
GUIDE = "README.md"
SLUG = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\.md")
SECTIONS = ("Added", "Changed", "Fixed")
# Where a new subsection goes among a version's: in this order, and before any other (Development, Upgrading).
ORDER = ("Added", "Changed", "Removed", "Fixed")


class Language(NamedTuple):
    key: str  # the fragment's heading for it: ## en
    path: str
    unreleased: re.Pattern
    released: str
    names: dict


LANGUAGES = (
    Language("en", "CHANGELOG.md", re.compile(r"## (\d+(?:\.\d+)+) \(unreleased\)"), "## {} ({})",
             {"Added": "Added", "Changed": "Changed", "Removed": "Removed", "Fixed": "Fixed"}),
    Language("zh-CN", "CHANGELOG.zh-CN.md", re.compile(r"## (\d+(?:\.\d+)+)（未发布）"), "## {}（{}）",
             {"Added": "新增", "Changed": "变更", "Removed": "移除", "Fixed": "修复"}),
)


class Problem(Exception):
    """What stops the command, said for whoever runs it (several lines when there is more than one)."""


class Fragment(NamedTuple):
    name: str  # changes/<slug>.md
    section: str
    entries: dict  # a language's key → its entries, each a "- " item, its indented lines after "\n"


class Version(NamedTuple):
    """A version in a changelog: the text before its first subsection, and each subsection's title and lines."""
    preamble: list
    subsections: list  # [title, lines]


def git(root: Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(["git", *args], cwd=root, text=True, capture_output=True)
    if check and result.returncode:
        raise Problem(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout if result.returncode == 0 else ""


# MARK: fragments

def parse(name: str, text: str) -> Fragment:
    lines = text.split("\n")
    fences = [i for i, line in enumerate(lines) if line.rstrip() == "---"]
    if not fences or fences[0] != 0 or len(fences) < 2:
        raise Problem(f"{name}: starts with its front matter: a line ---, section: Added, Changed or Fixed, a line ---")
    end = fences[1]
    fields = {}
    for line in filter(str.strip, lines[1:end]):
        key, colon, value = line.partition(":")
        if not colon or key.strip() != "section":
            raise Problem(f"{name}: the front matter has section: and nothing else, not {line.strip()!r}")
        fields[key.strip()] = value.strip()
    section = fields.get("section")
    if section not in SECTIONS:
        raise Problem(f"{name}: section is Added, Changed or Fixed, not {section!r}")

    keys = [language.key for language in LANGUAGES]
    entries: dict = {}
    current, blank = None, False
    for number, line in enumerate(lines[end + 1:], end + 2):
        line = line.rstrip()
        if line.startswith("## "):
            current = line[3:].strip()
            if current not in keys or current in entries:
                raise Problem(f"{name}:{number}: the headings are ## en, then ## zh-CN, once each, not {line!r}")
            entries[current] = []
        elif not line:
            blank = True
            continue
        elif current is None:
            raise Problem(f"{name}:{number}: nothing goes between the front matter and ## en: {line!r}")
        elif line.startswith("- ") and line[2:].strip():
            entries[current].append(line)
        elif line[:1] in (" ", "\t") and entries[current]:
            entries[current][-1] += ("\n\n" if blank else "\n") + line
        else:
            raise Problem(f"{name}:{number}: under ## {current} go only `- ` list items (a long one may go on in "
                          f"indented lines), not {line!r}")
        blank = False
    if list(entries) != keys:
        raise Problem(f"{name}: has ## en, then ## zh-CN, each with its entries")
    for key, items in entries.items():
        if not items:
            raise Problem(f"{name}: ## {key} has no `- ` entry")
    if len(entries["en"]) != len(entries["zh-CN"]):
        raise Problem(f"{name}: ## en has {len(entries['en'])} entries and ## zh-CN {len(entries['zh-CN'])}: "
                      f"each entry is in both languages")
    return Fragment(name, section, entries)


def committed(root: Path) -> dict:
    """When each path under changes/ was last added, by its commit (Unix time): the order the fragments came in."""
    log = git(root, "log", "--no-renames", "--diff-filter=A", "--format=%x00%ct", "--name-only", "--", FRAGMENTS,
              check=False)
    when: dict = {}
    stamp = None
    for line in log.split("\n"):
        if line.startswith("\0"):
            stamp = int(line[1:])
        elif line and stamp is not None:
            when.setdefault(line, stamp)  # newest first: a slug used again in an earlier release keeps today's
    return when


def fragments(root: Path) -> tuple:
    """The fragments, in the order they were committed (uncommitted ones last), and what's wrong with any."""
    folder = root / FRAGMENTS
    if not folder.is_dir():
        return [], []
    found, problems = [], []
    for path in sorted(folder.iterdir()):
        name = f"{FRAGMENTS}/{path.name}"
        if path.name == GUIDE or path.name.startswith("."):  # .DS_Store
            continue
        if not path.is_file() or not SLUG.fullmatch(path.name):
            problems.append(f"{name}: {FRAGMENTS}/ holds only fragments, <slug>.md (letters, digits, . _ -)")
            continue
        try:
            found.append(parse(name, path.read_text(encoding="utf-8-sig")))
        except (Problem, UnicodeDecodeError) as error:
            problems.append(str(error) if isinstance(error, Problem) else f"{name}: not UTF-8 text")
    when = committed(root) if found else {}
    found.sort(key=lambda fragment: (when.get(fragment.name, math.inf), fragment.name))
    return found, problems


# MARK: the changelogs

def split(text: str, language: Language) -> tuple:
    """A changelog's lines before its unreleased section, that section (its version and lines, or None), and the rest.
    Without one, the rest starts at the newest version."""
    lines = text.split("\n")
    for start, line in enumerate(lines):
        if match := language.unreleased.fullmatch(line):
            end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
            return lines[:start], (match.group(1), lines[start + 1:end]), lines[end:]
    top = next((i for i, line in enumerate(lines) if line.startswith("## ")), len(lines))
    return lines[:top], None, lines[top:]


def trimmed(lines: list) -> list:
    start = next((i for i, line in enumerate(lines) if line.strip()), len(lines))
    end = next((i for i in range(len(lines), start, -1) if lines[i - 1].strip()), start)
    return lines[start:end]


def version(lines: list) -> Version:
    preamble, subsections = [], []
    for line in lines:
        if line.startswith("### "):
            subsections.append([line[4:].strip(), []])
        elif subsections:
            subsections[-1][1].append(line)
        else:
            preamble.append(line)
    return Version(trimmed(preamble), [[title, trimmed(body)] for title, body in subsections])


def rank(title: str, language: Language) -> int:
    return next((i for i, name in enumerate(ORDER) if language.names[name] == title), len(ORDER))


def with_fragments(entries: Version, language: Language, found: list) -> Version:
    """The version's entries with the fragments' after them, each in its subsection (added where missing). A list whose
    entries stand apart (a blank line between them) gets the new ones apart too."""
    subsections = [[title, list(body)] for title, body in entries.subsections]
    for section in SECTIONS:
        items = [item for fragment in found if fragment.section == section for item in fragment.entries[language.key]]
        if not items:
            continue
        title = language.names[section]
        existing = next((subsection for subsection in subsections if subsection[0] == title), None)
        if existing is None:
            at = next((i for i, (other, _) in enumerate(subsections) if rank(other, language) > ORDER.index(section)),
                      len(subsections))
            subsections.insert(at, [title, []])
            existing = subsections[at]
        body = existing[1]
        apart = any(not line.strip() and after.startswith("- ") for line, after in zip(body, body[1:]))
        for item in items:
            body += ([""] if body and apart else []) + item.split("\n")
    return Version(entries.preamble, subsections)


def rendered(entries: Version, heading: str, level: str) -> list:
    lines = ([heading, ""] if heading else []) + (entries.preamble + [""] if entries.preamble else [])
    for title, body in entries.subsections:
        lines += [f"{level} {title}", ""] + body + [""]
    return lines


def assembled(root: Path, found: list) -> list:
    """For each language: the parts of its changelog split() finds, and the next release's entries."""
    result = []
    for language in LANGUAGES:
        path = root / language.path
        if not path.is_file():
            raise Problem(f"{language.path}: not found")
        before, section, after = split(path.read_text(encoding="utf-8"), language)
        entries = version(section[1]) if section else Version([], [])
        result.append((language, (before, section, after), with_fragments(entries, language, found)))
    return result


def notes(versions: list) -> str:
    """The GitHub release's notes, as earlier releases have them: English, ---, Chinese, a version's subsections as ##
    headings. The summary atop each language and the disk image's line at the end are written at release time."""
    parts = ["\n".join(rendered(entries, "", "##")).strip() for entries in versions]
    return "\n\n---\n\n".join(parts) + "\n"


# MARK: commands

def check(root: Path, base: str | None) -> str:
    found, problems = fragments(root)
    said = f"{len(found)} fragment{'' if len(found) == 1 else 's'}, well formed"
    if base:
        fork = git(root, "merge-base", base, "HEAD", check=False).strip()
        if not fork:
            raise Problem(f"no commit {base} to compare the changelogs with")
        for language in LANGUAGES:
            was = git(root, "show", f"{fork}:{language.path}", check=False)
            path = root / language.path
            if not was or not path.is_file():
                continue
            before, now = split(was, language)[1], split(path.read_text(encoding="utf-8"), language)[1]
            # None now: released, the section dated (`release`).
            if now is not None and trimmed(now[1]) != (trimmed(before[1]) if before else []):
                problems.append(f"{language.path}: its unreleased section ({now[0]}) was edited since {base}: write "
                                f"the entry in a fragment instead, {FRAGMENTS}/<slug>.md ({FRAGMENTS}/{GUIDE} says "
                                f"how), and leave the changelogs to the release")
        said += f", and neither changelog's unreleased section edited since {base}"
    if problems:
        raise Problem("\n".join(problems))
    return said


def preview(root: Path) -> str:
    found, problems = fragments(root)
    if problems:
        raise Problem("\n".join(problems))
    versions = [entries for _, _, entries in assembled(root, found)]
    if not any(entries.subsections for entries in versions):
        return ""
    return notes(versions)


def release(root: Path, number: str, date: str) -> tuple:
    """The release notes, and how many fragments went into them."""
    if not re.fullmatch(r"\d+(?:\.\d+)+", number):
        raise Problem(f"the version is X.Y.Z, not {number!r}")
    try:
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
            raise ValueError
        dt.date.fromisoformat(date)
    except ValueError:
        raise Problem(f"the date is YYYY-MM-DD, not {date!r}") from None
    found, problems = fragments(root)
    if problems:
        raise Problem("\n".join(problems))
    if git(root, "status", "--porcelain", "--untracked-files=all", "--", FRAGMENTS).strip():
        raise Problem(f"{FRAGMENTS}/ has changes not committed: commit them (or remove them) first, so that the "
                      "release is what was committed")
    every = assembled(root, found)
    for language, (before, section, after), entries in every:
        if section and section[0] != number:
            raise Problem(f"{language.path}: its unreleased section is {section[0]}'s, not {number}'s")
        dated = language.released.format(number, "\0").split("\0")[0]  # "## 0.7.5 (", up to the date
        if any(line.startswith(dated) for line in before + after):
            raise Problem(f"{language.path}: {number} was released already")
        if not entries.subsections:
            raise Problem(f"{language.path}: nothing to release: no unreleased entries and no fragments")
    for language, (before, _, after), entries in every:
        lines = before + rendered(entries, language.released.format(number, date), "###") + after
        (root / language.path).write_text("\n".join(lines).rstrip("\n") + "\n", encoding="utf-8")
    if found:
        git(root, "rm", "-q", "--", *[fragment.name for fragment in found])
    return notes([entries for _, _, entries in every]), len(found)


def main(argv: list | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(prog="Scripts/changelog.py", description="The changelog's fragments (changes/).")
    commands = parser.add_subparsers(dest="command", required=True)
    checking = commands.add_parser("check", help="the fragments are well formed, and the changelogs not edited")
    checking.add_argument("--base", help="the commit or branch whose unreleased sections this change may not edit")
    commands.add_parser("preview", help="the next release's notes, from the unreleased entries and the fragments")
    releasing = commands.add_parser("release", help="the fragments into both changelogs, dated; prints the notes")
    releasing.add_argument("version", help="X.Y.Z")
    releasing.add_argument("date", help="YYYY-MM-DD")
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "check":
            print(f"changelog: {check(root, arguments.base)}")
        elif arguments.command == "preview":
            text = preview(root)
            sys.stdout.write(text)
            if not text:
                print("changelog: nothing to release yet: no unreleased entries and no fragments", file=sys.stderr)
        else:
            text, count = release(root, arguments.version, arguments.date)
            sys.stdout.write(text)
            print(f"changelog: {arguments.version} ({arguments.date}) written into both changelogs, with "
                  f"{count} fragment{'' if count == 1 else 's'} (removed with git rm); the release notes went to "
                  "stdout", file=sys.stderr)
    except Problem as problem:
        for line in str(problem).split("\n"):
            print(f"changelog: {line}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
