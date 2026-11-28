---
section: Added
---

## en

- Wubi 86: Settings → Input → Chinese → Typing → Wubi 86 types Chinese by the characters' shapes (`g` 一, `gggg` 王,
  `wqvb` 你好) with Rime's own Wubi (rime-wubi, which the app carries). Its candidates are in the panel as every way's:
  the first row chosen, Space or a digit puts one in, and a code left with one candidate still waits for you (nothing
  goes in by itself at four codes). `z` then pinyin looks a character up and shows its code. Your characters
  (Simplified or Traditional), removed candidates and a tap of Shift (it puts in what is composed) work as with Zhuyin,
  punctuation as with pinyin; fuzzy pinyin, personal dictionaries, shape codes and English words don't apply to it,
  and the words it learns stay in Wubi's own. `@` commands, clipboard history and the AI's features work as with
  pinyin. Settings search finds it as wubi, 五笔 or 86; in `config.json`, `"pinyinScheme": "wubi86"`.

## zh-CN

- 五笔 86：设置 →「输入」→「中文」→「输入方式」→「五笔 86」用 Rime 自己的五笔（rime-wubi，随 App 带着）按字形打中文（`g` 一、`gggg` 王、`wqvb` 你好）。候选和其他输入方式一样在候选框里：默认选中第一行，按空格或数字上屏，一个码只剩一个候选时也等你选（四码不会自动上屏）。打 `z` 再打拼音可以反查一个字并显示它的五笔码。字形（简体或繁体）、删掉的候选和单按 Shift（把正在打的字上屏）和注音一样，标点和拼音一样；模糊音、个人词库、辅助码和英文词不用于五笔，五笔学到的词记在它自己的词库里。`@` 命令、剪贴板历史和 AI 功能和拼音时一样。设置搜索 wubi、五笔、86 都能找到它；`config.json` 里是 `"pinyinScheme": "wubi86"`。
