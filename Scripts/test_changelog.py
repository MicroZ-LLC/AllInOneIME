# Scripts/changelog.py's tests, each in a git repository of its own made in a temporary folder (offline, no setup):
#
#   python3 -B -m unittest Scripts/test_changelog.py     (from the repository's root; `make test` runs it)

from __future__ import annotations

import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import changelog  # noqa: E402

ENGLISH = """\
# Changelog

English | [中文](CHANGELOG.zh-CN.md)

## 0.7.5 (unreleased)

### Changed

- Settings is lighter.

### Fixed

- Clipboard history keeps less.

- Caps Lock switches once.
  Even when the Mac is busy.

## 0.7.4 (2026-11-14)

### Added

- Caps Lock can switch the input language.
"""

CHINESE = """\
# 更新日志

[English](CHANGELOG.md) | 中文

## 0.7.5（未发布）

### 变更

- 设置更轻了。

### 修复

- 剪贴板历史记得更少。

- 大写锁定键只切换一次。
  Mac 很忙时也一样。

## 0.7.4（2026-11-14）

### 新增

- 大写锁定键可以切换输入语言。
"""


def fragment(section: str, english: list, chinese: list) -> str:
    return (f"---\nsection: {section}\n---\n\n## en\n\n" + "\n".join(english)
            + "\n\n## zh-CN\n\n" + "\n".join(chinese) + "\n")


class ChangelogTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.git("init", "-q")
        self.write("CHANGELOG.md", ENGLISH)
        self.write("CHANGELOG.zh-CN.md", CHINESE)
        self.write("changes/README.md", "How to write a fragment: not one itself.\n")
        self.commit("start")
        self.base = self.git("rev-parse", "HEAD").strip()

    def git(self, *args: str, date: str = "2026-11-15T10:00:00") -> str:
        env = dict(os.environ, GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date, GIT_CONFIG_GLOBAL=os.devnull,
                   GIT_CONFIG_NOSYSTEM="1")
        return subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", *args],
                              cwd=self.root, env=env, text=True, capture_output=True, check=True).stdout

    def write(self, path: str, text: str):
        (self.root / path).parent.mkdir(parents=True, exist_ok=True)
        (self.root / path).write_text(text, encoding="utf-8")

    def read(self, path: str) -> str:
        return (self.root / path).read_text(encoding="utf-8")

    def commit(self, message: str, date: str = "2026-11-15T10:00:00"):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message, date=date)

    def run_script(self, *argv: str) -> tuple:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = changelog.main(list(argv), root=self.root)
        return status, out.getvalue(), err.getvalue()

    # MARK: check

    def test_well_formed_fragments_pass(self):
        self.write("changes/issue-120.md", fragment("Added", ["- `@demo` does a thing.", "  It goes on here."],
                                                    ["- `@demo` 做一件事。", "  接着说。"]))
        self.write("changes/caps.md", fragment("Fixed", ["- One.", "", "- Two."], ["- 一。", "- 二。"]))
        status, out, err = self.run_script("check", "--base", self.base)
        self.assertEqual((status, err), (0, ""))
        self.assertIn("2 fragments, well formed", out)

    def test_malformed_fragments_fail_each_with_its_reason(self):
        cases = {
            "no-front-matter.md": "## en\n\n- One.\n\n## zh-CN\n\n- 一。\n",
            "bad-section.md": fragment("Improved", ["- One."], ["- 一。"]),
            "no-chinese.md": "---\nsection: Fixed\n---\n\n## en\n\n- One.\n",
            "uneven.md": fragment("Fixed", ["- One.", "- Two."], ["- 一。"]),
            "stray.md": fragment("Fixed", ["Some words.", "- One."], ["- 一。"]),
            "Bad Name.md": fragment("Fixed", ["- One."], ["- 一。"]),
            "notes.txt": "a note\n",
        }
        for name, text in cases.items():
            self.write(f"changes/{name}", text)
        status, _, err = self.run_script("check")
        self.assertEqual(status, 1)
        for name, reason in {"no-front-matter.md": "front matter", "bad-section.md": "'Improved'",
                             "no-chinese.md": "## en, then ## zh-CN", "uneven.md": "each entry is in both",
                             "stray.md": "only `- ` list items", "Bad Name.md": "only fragments",
                             "notes.txt": "only fragments"}.items():
            self.assertRegex(err, f"changelog: changes/{name}.*{reason}".replace("(", r"\(").replace(")", r"\)"))

    def test_editing_an_unreleased_section_fails_against_the_base(self):
        self.write("CHANGELOG.zh-CN.md", CHINESE.replace("- 设置更轻了。", "- 设置更轻了。\n- 新的一条。"))
        status, _, err = self.run_script("check", "--base", self.base)
        self.assertEqual(status, 1)
        self.assertIn("CHANGELOG.zh-CN.md: its unreleased section (0.7.5) was edited", err)
        self.assertNotIn("CHANGELOG.md:", err)
        self.assertEqual(self.run_script("check")[0], 0)  # without a base, only the fragments are checked

    def test_a_new_unreleased_section_with_entries_fails(self):
        self.write("CHANGELOG.md", ENGLISH.replace("## 0.7.5 (unreleased)", "## 0.7.5 (2026-11-20)"))
        self.commit("released")
        base = self.git("rev-parse", "HEAD").strip()
        self.write("CHANGELOG.md", ENGLISH.replace("## 0.7.5 (unreleased)", "## 0.7.6 (unreleased)\n\n### Fixed\n\n"
                                                   "- New.\n\n## 0.7.5 (2026-11-20)"))
        self.assertEqual(self.run_script("check", "--base", base)[0], 1)

    def test_edits_elsewhere_and_on_the_base_since_the_branch_left_it_pass(self):
        self.git("checkout", "-q", "-b", "feature")
        self.write("CHANGELOG.md", ENGLISH.replace("- Caps Lock can switch", "- Caps Lock can now switch"))
        self.commit("fix a released entry's typo")
        self.git("checkout", "-q", "-")
        self.write("CHANGELOG.md", ENGLISH.replace("- Settings is lighter.", "- Settings is lighter still."))
        self.commit("the base moves on")
        base = self.git("rev-parse", "HEAD").strip()
        self.git("checkout", "-q", "feature")
        status, _, err = self.run_script("check", "--base", base)
        self.assertEqual((status, err), (0, ""))

    def test_a_release_passes_the_check(self):
        self.write("changes/issue-120.md", fragment("Added", ["- New."], ["- 新的。"]))
        self.commit("fragment")
        self.assertEqual(self.run_script("release", "0.7.5", "2026-11-20")[0], 0)
        status, _, err = self.run_script("check", "--base", self.base)
        self.assertEqual((status, err), (0, ""))

    def test_an_unknown_base_is_an_error(self):
        status, _, err = self.run_script("check", "--base", "no-such-branch")
        self.assertEqual(status, 1)
        self.assertIn("no commit no-such-branch", err)

    # MARK: release

    def test_release_dates_the_section_adds_the_fragments_and_removes_them(self):
        self.write("changes/issue-120.md", fragment("Added", ["- `@demo` does a thing.", "  It goes on."],
                                                    ["- `@demo` 做一件事。", "  接着说。"]))
        self.write("changes/settings.md", fragment("Changed", ["- Settings has a search."], ["- 设置可以搜索。"]))
        self.write("changes/caps.md", fragment("Fixed", ["- Caps Lock lights."], ["- 大写锁定灯亮。"]))
        self.commit("fragments")
        status, notes, err = self.run_script("release", "0.7.5", "2026-11-20")
        self.assertEqual(status, 0, err)
        self.assertIn("3 fragments", err)
        # Each fragment's entries at the end of its subsection, apart where the list's entries are, tight where they're
        # not; Added, which the section lacked, before Changed.
        self.assertEqual(self.read("CHANGELOG.md"), ENGLISH
                         .replace("## 0.7.5 (unreleased)\n", "## 0.7.5 (2026-11-20)\n\n### Added\n\n"
                                  "- `@demo` does a thing.\n  It goes on.\n")
                         .replace("- Settings is lighter.\n", "- Settings is lighter.\n- Settings has a search.\n")
                         .replace("  Even when the Mac is busy.\n",
                                  "  Even when the Mac is busy.\n\n- Caps Lock lights.\n"))
        chinese = self.read("CHANGELOG.zh-CN.md")
        self.assertTrue(chinese.startswith("# 更新日志\n\n[English](CHANGELOG.md) | 中文\n\n## 0.7.5（2026-11-20）\n\n"
                                           "### 新增\n\n- `@demo` 做一件事。\n  接着说。\n\n### 变更\n\n- 设置更轻了。\n"
                                           "- 设置可以搜索。\n\n### 修复\n"))
        self.assertIn("  Mac 很忙时也一样。\n\n- 大写锁定灯亮。\n\n## 0.7.4（2026-11-14）\n", chinese)
        self.assertFalse((self.root / "changes/caps.md").exists())
        self.assertEqual(sorted(self.git("diff", "--cached", "--name-status").split("\n")[:-1]),
                         ["D\tchanges/caps.md", "D\tchanges/issue-120.md", "D\tchanges/settings.md"])
        self.assertTrue((self.root / "changes/README.md").exists())
        # The notes: English, ---, Chinese, with ## headings, as the GitHub releases have them.
        english, chinese_notes = notes.split("\n\n---\n\n")
        self.assertTrue(english.startswith("## Added\n\n- `@demo` does a thing.\n  It goes on.\n\n## Changed\n"))
        self.assertTrue(chinese_notes.startswith("## 新增\n\n- `@demo` 做一件事。"))
        self.assertTrue(chinese_notes.endswith("- 大写锁定灯亮。\n"))
        self.assertNotIn("0.7.4", notes)

    def test_release_adds_a_section_when_there_is_no_unreleased_one(self):
        for path, text in (("CHANGELOG.md", ENGLISH), ("CHANGELOG.zh-CN.md", CHINESE)):
            head, rest = text.split("## 0.7.5", 1)
            self.write(path, head + rest[rest.index("## 0.7.4"):])
        self.write("changes/one.md", fragment("Fixed", ["- One."], ["- 一。"]))
        self.commit("released, then a fragment")
        self.assertEqual(self.run_script("release", "0.7.6", "2026-12-01")[0], 0)
        self.assertIn("zh-CN.md)\n\n## 0.7.6 (2026-12-01)\n\n### Fixed\n\n- One.\n\n## 0.7.4 (2026-11-14)\n",
                      self.read("CHANGELOG.md"))
        self.assertIn("中文\n\n## 0.7.6（2026-12-01）\n\n### 修复\n\n- 一。\n\n## 0.7.4（2026-11-14）\n",
                      self.read("CHANGELOG.zh-CN.md"))
        self.write("changes/two.md", fragment("Fixed", ["- Two."], ["- 二。"]))
        self.commit("another fragment")
        status, _, err = self.run_script("release", "0.7.4", "2026-12-02")
        self.assertEqual(status, 1)
        self.assertIn("CHANGELOG.md: 0.7.4 was released already", err)

    def test_fragments_go_in_in_the_order_they_were_committed(self):
        self.write("changes/zeta.md", fragment("Fixed", ["- First."], ["- 第一。"]))
        self.commit("zeta", date="2026-11-16T10:00:00")
        self.write("changes/alpha.md", fragment("Fixed", ["- Second."], ["- 第二。"]))
        self.commit("alpha", date="2026-11-17T10:00:00")
        _, notes, _ = self.run_script("preview")
        self.assertLess(notes.index("- First."), notes.index("- Second."))

    def test_release_refuses_what_it_shouldnt_write(self):
        self.write("changes/one.md", fragment("Fixed", ["- One."], ["- 一。"]))
        self.commit("fragment")
        for argv, reason in ((("0.7.6", "2026-11-20"), "unreleased section is 0.7.5's, not 0.7.6's"),
                             (("0.7.5", "2026-13-01"), "the date is YYYY-MM-DD"),
                             (("v0.7.5", "2026-11-20"), "the version is X.Y.Z")):
            status, _, err = self.run_script("release", *argv)
            self.assertEqual(status, 1, argv)
            self.assertIn(reason, err)
        self.write("changes/two.md", fragment("Fixed", ["- Two."], ["- 二。"]))
        status, _, err = self.run_script("release", "0.7.5", "2026-11-20")
        self.assertEqual(status, 1)
        self.assertIn("changes not committed", err)
        self.assertEqual((self.read("CHANGELOG.md"), self.read("CHANGELOG.zh-CN.md")), (ENGLISH, CHINESE))
        self.assertTrue((self.root / "changes/one.md").exists())

    def test_preview_prints_what_release_would_and_changes_nothing(self):
        self.write("changes/one.md", fragment("Added", ["- One."], ["- 一。"]))
        self.commit("fragment")
        status, preview, _ = self.run_script("preview")
        self.assertEqual(status, 0)
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertEqual(self.run_script("release", "0.7.5", "2026-11-20")[1], preview)


if __name__ == "__main__":
    unittest.main()
