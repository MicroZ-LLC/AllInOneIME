# Changelog fragments

A change a user would notice writes its changelog entry here, as one file of its own, instead of in `CHANGELOG.md` and
`CHANGELOG.zh-CN.md` (AGENTS.md, rule 15): `changes/<slug>.md`, the slug unique to its branch (the agent pipeline's
`issue-N`; `caps-lock` for a branch `0.7.5/caps-lock`). Parallel pull requests then never edit the same lines. A
release writes the fragments into both changelogs and removes them.

```markdown
---
section: Fixed
---

## en

- With Caps Lock as the switch key, one press of it switches the input language once in Brave's page fields.

## zh-CN

- 切换键设为大写锁定键时，在 Brave 的网页输入框里按一下只切换一次输入语言。
```

- `section` is `Added`, `Changed` or `Fixed` (新增, 变更, 修复 in the Chinese changelog). A change with entries in two
  sections writes a fragment for each (`caps-lock.md`, `caps-lock-fixed.md`).
- Under `## en` and `## zh-CN`, the same entries, each a `- ` list item, written like the changelog's: what the user
  sees and does, keys, commands and config names in backticks. A long entry may go on in lines indented by two spaces.
- `python3 Scripts/changelog.py check` checks the fragments (`make lint` runs it, and fails a change that edits a
  changelog's unreleased section by hand); `python3 Scripts/changelog.py preview` prints the next release's notes with
  them in. An entry already in an unreleased section (written before fragments) is corrected in the release's pull
  request, which dates that section.
