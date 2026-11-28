---
section: Fixed
---

## en

- Settings no longer goes back to older values when the config file changes twice in quick succession, or when a
  switch is flipped while Settings is reading the file again: what was saved last stays shown.
- With a config file that can't be read, searching Settings for an AI (`kiro`) or a pointer from the start or the
  Doctor no longer opens Settings → AI's choices on a disabled page whose Cancel and `Esc` don't work.

## zh-CN

- 配置文件短时间内被连写两次，或设置窗口重新读配置时刚好拨了一个开关，设置不会再退回旧值：显示的是最后保存的。
- 配置文件读不出来时，在设置里搜某个 AI（`kiro`），或从开始引导、Doctor 指过去，不会再在已禁用的页面上打开「设置 → AI」的选项（那时「取消」和 `Esc` 都不起作用）。
