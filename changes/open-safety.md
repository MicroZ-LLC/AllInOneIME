---
section: Fixed
---

## en

- `@open`: after Tab goes into a folder, ⏎ without moving the highlight opens the folder itself, listed first above
  what is in it. A script or program (a `.command`, `.tool`, `.sh` or `.terminal` file, or one with an execute bit) is
  shown in Finder instead of run, and its row says "Show in Finder". File names with control or bidi characters show
  without them.
- `@open` shows Finder aliases to scripts and executable files in Finder instead of opening what they point to.
- `@open` lists app bundles ending in `.APP` or `.App` as apps, not folders.
- After using Tab to enter an `@open` folder and pressing Esc, typing that path again lists its contents first.
- An `@open` folder named like a script, such as `foo.command`, now opens as its row says.
- `@open` recognizes web addresses with uppercase `LOCALHOST` and opens them in the browser.

## zh-CN

- `@open`：Tab 进入文件夹后，不移动高亮直接按 ⏎ 打开这个文件夹本身（它排在里面的内容前面）。脚本和程序（`.command`、`.tool`、`.sh`、`.terminal` 文件，或有执行权限的文件）在访达中显示而不是运行，这一行写着「在访达中显示」。文件名里的控制字符和双向文字控制字符不再显示。
- `@open` 遇到指向脚本或可执行文件的访达替身时，会在访达中显示它，不再打开它所指的文件。
- `@open` 会把以 `.APP` 或 `.App` 结尾的 App 包列为 App，不再列为文件夹。
- 用 Tab 进入 `@open` 的文件夹再按 Esc 后，重新输入该路径会先列出文件夹里的内容。
- 名字像脚本的 `@open` 文件夹（例如 `foo.command`）现在会像候选行写的那样打开。
- `@open` 现在能识别大写 `LOCALHOST` 的网址，并在浏览器中打开。
