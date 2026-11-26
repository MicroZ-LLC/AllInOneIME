#!/usr/bin/env python3
# The weekly code health report (.github/workflows/health.yml puts it in one issue): how the debt the quality gate
# holds back (AGENTS.md) is shrinking. Markdown on stdout: the files over the size limit and their trend
# (Scripts/oversized-files.txt now and 1, 4 and 12 weeks ago, from git history), SwiftLint's baseline and its trend
# (.swiftlint.baseline.json), duplicated code (a built-in detector: runs of 12 or more identical lines of code in
# two places), unused code (Periphery, pinned and checksummed like SwiftLint, when `--periphery` is given and it
# runs; skipped otherwise), and the tests the quality gate's runs found flaky (from the folder `--flaky` names: health.yml
# fills it with the test jobs' flaky-tests-* artifacts). Read-only: it changes nothing in the repository.
#
#   python3 Scripts/health-report.py [--periphery] [--flaky FOLDER] > report.md

from __future__ import annotations

import collections
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCOPE = ("Sources", "Core/Sources")
WINDOW = 12  # lines of code in a row that count as a duplicate
PERIPHERY = ("3.8.0", "07d4e286e31dd79164df39097e0b59f533c94badbe18158464a455ea88a166d7")
WEEKS = (1, 4, 12)
FLAKY_DAYS = 28   # the runs whose flaky tests are counted (health.yml downloads those)
FLAKY_OFTEN = 3   # runs a test was flaky in that make it worth reproducing


def git(*args: str, check: bool = True) -> str:
    result = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout if result.returncode == 0 else ""


def at(commit: str, path: str) -> str | None:
    """A file's text at a commit; None where it didn't exist."""
    result = subprocess.run(["git", "show", f"{commit}:{path}"], cwd=ROOT, text=True, capture_output=True)
    return result.stdout if result.returncode == 0 else None


def oversized(text: str | None) -> dict[str, int] | None:
    if text is None:
        return None
    return {line.split(" ", 1)[1]: int(line.split(" ", 1)[0]) for line in text.splitlines()
            if line.strip() and not line.startswith("#")}


def baseline(text: str | None) -> list[dict] | None:
    return None if text is None else json.loads(text)


def then() -> dict[int, str]:
    """The commit HEAD's history had N weeks ago, for each N in WEEKS (those it reaches)."""
    found = {}
    for weeks in WEEKS:
        commit = git("rev-list", "-1", f"--before={weeks} weeks ago", "HEAD", check=False).strip()
        if commit:
            found[weeks] = commit
    return found


def trend(now: float, past: dict[int, float | None]) -> str:
    cells = []
    for weeks in WEEKS:
        value = past.get(weeks)
        cells.append("—" if value is None else f"{value:g} ({now - value:+g})")
    return " | ".join(cells)


def sizes_section(past_commits: dict[int, str]) -> list[str]:
    report = subprocess.run([str(ROOT / "Scripts/check-ratchet.sh"), "--report"], cwd=ROOT, text=True,
                            capture_output=True, check=True).stdout
    rows = [line.split() for line in report.splitlines() if line.strip()]
    past = {weeks: oversized(at(commit, "Scripts/oversized-files.txt")) for weeks, commit in past_commits.items()}
    now_sizes = {path: int(current) for path, _, current in rows if current != "gone"}
    total = sum(now_sizes.values())
    lines = ["## Files over the size limit", "",
             "Lines of code (not blank, not only a comment) in the shipped Swift files over the limit "
             "(Scripts/check-ratchet.sh); none may grow. Trend: the value then (the change since).", "",
             "| | now | 1 week ago | 4 weeks ago | 12 weeks ago |", "|---|---|---|---|---|",
             f"| files | {len(now_sizes)} | " + trend(len(now_sizes), {w: len(p) if p is not None else None
                                                                    for w, p in past.items()}) + " |",
             f"| lines of code in them | {total} | " + trend(total, {w: sum(p.values()) if p is not None else None
                                                                      for w, p in past.items()}) + " |",
             "", "The largest:", "", "| file | now | recorded | 4 weeks ago |", "|---|---|---|---|"]
    month = past.get(4) or {}
    for path, recorded, current in sorted(rows, key=lambda r: -int(r[2]) if r[2] != "gone" else 0)[:20]:
        lines.append(f"| `{path}` | {current} | {recorded} | {month.get(path, '—')} |")
    return lines


def lint_section(past_commits: dict[int, str]) -> list[str]:
    now = baseline((ROOT / ".swiftlint.baseline.json").read_text())
    past = {weeks: baseline(at(commit, ".swiftlint.baseline.json")) for weeks, commit in past_commits.items()}
    by_rule = collections.Counter(entry["violation"]["ruleIdentifier"] for entry in now)
    by_file = collections.Counter(entry["violation"]["location"]["file"] for entry in now)
    return ["## SwiftLint baseline", "",
            "Violations of .swiftlint.yml's rules that predate the gate (.swiftlint.baseline.json); a new one fails "
            "`make lint`.", "",
            "| | now | 1 week ago | 4 weeks ago | 12 weeks ago |", "|---|---|---|---|---|",
            f"| violations | {len(now)} | " + trend(len(now), {w: len(p) if p is not None else None
                                                             for w, p in past.items()}) + " |",
            "", "By rule: " + ", ".join(f"{rule} {n}" for rule, n in by_rule.most_common()) + ".", "",
            "Most in one file: " + ", ".join(f"`{path}` {n}" for path, n in by_file.most_common(5)) + "."]


def code_lines(path: Path) -> list[tuple[int, str]]:
    """(line number, normalized text) for each line of code: not blank, not a comment, not only brackets."""
    found = []
    for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        text = re.sub(r"\s+", " ", line.strip())
        if text and not text.startswith(("//", "/*", "*", "import ")) and not re.fullmatch(r"[{}()\[\],;]*", text):
            found.append((number, text))
    return found


def duplicates_section() -> list[str]:
    files = sorted(p for scope in SCOPE for p in (ROOT / scope).rglob("*.swift"))
    seen: dict[str, tuple[str, int]] = {}  # a window's hash → where it was first
    matches = []  # (file, index, first file, first index) for each window seen before
    lines = {}
    for path in files:
        name = str(path.relative_to(ROOT))
        lines[name] = code_lines(path)
        texts = [text for _, text in lines[name]]
        for i in range(len(texts) - WINDOW + 1):
            key = hashlib.sha1("\n".join(texts[i:i + WINDOW]).encode()).hexdigest()
            if key in seen:
                matches.append((name, i) + seen[key])
            else:
                seen[key] = (name, i)
    # Runs of overlapping windows are one block: (file, start, end, other file, other start), in code lines.
    blocks, covered = [], set()
    for name, i, other, j in matches:
        covered.update((name, k) for k in range(i, i + WINDOW))
        last = blocks[-1] if blocks else None
        if last and last[0] == name and last[3] == other and i == last[2] - WINDOW + 1 and j - last[4] == i - last[1]:
            last[2] = i + WINDOW
        else:
            blocks.append([name, i, i + WINDOW, other, j])
    total = sum(len(v) for v in lines.values())
    out = ["## Duplicated code", "",
           f"Runs of {WINDOW} or more identical lines of code (whitespace and comments aside) in the shipped Swift "
           f"files: {len(blocks)} copies, {len(covered)} of {total} lines of code "
           f"({100 * len(covered) / max(total, 1):.1f}%) are a copy of code elsewhere.", ""]
    if blocks:
        out += ["The longest:", "", "| copy | of | lines of code |", "|---|---|---|"]
        for name, i, end, other, j in sorted(blocks, key=lambda b: b[1] - b[2])[:10]:
            first, line = lines[name][i][0], lines[other][j][0]
            out.append(f"| `{name}:{first}` | `{other}:{line}` | {end - i} |")
    return out


def periphery_section() -> list[str]:
    version, sha = PERIPHERY
    cache = Path(os.environ.get("ALLINONEIME_TOOL_CACHE") or Path.home() / ".cache/allinoneime") / f"periphery-{version}"
    binary = cache / "periphery"
    try:
        if not binary.exists():
            cache.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory() as tmp:
                archive = Path(tmp) / "periphery.zip"
                subprocess.run(["curl", "-fsSL", "-o", str(archive), "https://github.com/peripheryapp/periphery/"
                                f"releases/download/{version}/periphery-{version}.zip"], check=True)
                if hashlib.sha256(archive.read_bytes()).hexdigest() != sha:
                    raise RuntimeError("its download's SHA-256 doesn't match")
                subprocess.run(["unzip", "-q", "-o", str(archive), "-d", str(cache)], check=True)
        # Periphery reads the index the build leaves: SwiftPM's own build system's, or the newer one's (.build/out).
        subprocess.run(["swift", "build"], cwd=ROOT, capture_output=True, check=True, timeout=3600)
        store = next((path for path in (ROOT / ".build/debug/index/store", ROOT / ".build/out")
                      if (path / "v5").is_dir()), None)
        if store is None:
            raise RuntimeError("the build left no index store")
        scan = subprocess.run([str(binary), "scan", "--index-store-path", str(store), "--format", "csv",
                               "--relative-results", "--quiet", "--retain-public", "--exclude-tests",
                               "--disable-update-check"], cwd=ROOT, text=True, capture_output=True, timeout=3600)
        if scan.returncode:
            raise RuntimeError((scan.stderr or scan.stdout).strip()[-300:])
    except Exception as error:
        return ["## Unused code", "", f"Skipped: Periphery {version} couldn't run here ({error})."]
    # Its CSV doesn't quote a field with commas in it (an attribute's arguments): the last two are Location, Hints.
    rows = [line.rsplit(",", 2)[1:] for line in scan.stdout.splitlines()[1:] if line.count(",") >= 2]
    by_file = collections.Counter(location.rsplit(":", 2)[0] for location, _ in rows)
    by_kind = collections.Counter(hint or "unused" for _, hint in rows)
    return ["## Unused code", "",
            f"Periphery {version}, over the app's and the core's targets (public declarations kept, tests left "
            f"out): {len(rows)} declarations (" + ", ".join(f"{kind} {n}" for kind, n in by_kind.most_common()) +
            ").", "", "Most in one file: " +
            (", ".join(f"`{path}` {n}" for path, n in by_file.most_common(10)) or "none") + "."]


def flaky_section(folder: Path | None) -> list[str]:
    """The tests that failed under the machine's load and passed alone (Core/Scripts/retry-failed-tests.sh counts them
    as passed) in the quality gate's runs: `folder` holds a folder per test job (core-linux, core-macos, mac), in it one
    per run that had any, each with that run's flaky-tests.txt, a test a line; and unread.txt, an artifact a line, when
    some couldn't be downloaded (those runs are left out, so the section says it is partial, never "None")."""
    out = ["## Flaky tests", ""]
    if folder is None:
        return out + ["Skipped (run with --flaky FOLDER)."]
    if not folder.is_dir():
        return out + ["Skipped: the test jobs' flaky-tests-* artifacts couldn't be read (the workflow's log says why)."]
    unread = len((folder / "unread.txt").read_text(errors="replace").splitlines()) \
        if (folder / "unread.txt").is_file() else 0
    listings = list(folder.glob("*/*/flaky-tests.txt"))
    if unread and not listings:
        return out + [f"Skipped: none of the {unread} flaky-tests-* artifacts of the last {FLAKY_DAYS} days could be "
                      "downloaded (the workflow's log says why)."]
    runs: collections.Counter[str] = collections.Counter()
    jobs: dict[str, set[str]] = collections.defaultdict(set)
    for listing in listings:
        for test in {line.strip() for line in listing.read_text(errors="replace").splitlines() if line.strip()}:
            runs[test] += 1
            jobs[test].add(listing.parent.parent.name)
    out += [f"Tests that failed under load and passed when run again alone, in the quality gate's runs of the last "
            f"{FLAKY_DAYS} days; the run counted them as passed. One that keeps coming back ({FLAKY_OFTEN} runs or "
            "more, marked) may hide a race that only shows in parallel: reproduce it (AGENTS.md, Bugs) and fix it.", ""]
    if unread:
        out += [f"Partial: {unread} of the {unread + len(listings)} runs' flaky-tests-* artifacts couldn't be "
                "downloaded (the workflow's log says which); their tests aren't counted below.", ""]
    if not runs:
        return out + ["None in the runs that could be read." if unread else "None."]
    out += ["| test | runs | jobs |", "|---|---|---|"]
    for test, count in sorted(runs.items(), key=lambda item: (-item[1], item[0]))[:20]:
        mark = " ⚠" if count >= FLAKY_OFTEN else ""
        out.append(f"| `{test}` | {count}{mark} | {', '.join(sorted(jobs[test]))} |")
    if len(runs) > 20:
        out += ["", f"And {len(runs) - 20} more."]
    return out


def main(argv: list[str]) -> int:
    head = git("rev-parse", "--short", "HEAD").strip()
    branch = os.environ.get("REPORT_BRANCH") or git("rev-parse", "--abbrev-ref", "HEAD").strip()
    past = then()
    sections = [[f"Code health of `{branch}` at {head}, written every Monday by the Health report workflow "
                 "(Scripts/health-report.py). The gate keeps these from growing (AGENTS.md, `make lint`); this shows "
                 "whether they shrink."],
                sizes_section(past), lint_section(past), duplicates_section(),
                periphery_section() if "--periphery" in argv else
                ["## Unused code", "", "Skipped (run with --periphery)."],
                flaky_section(Path(argv[argv.index("--flaky") + 1]) if "--flaky" in argv[:-1] else None)]
    print("\n\n".join("\n".join(section) for section in sections))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
