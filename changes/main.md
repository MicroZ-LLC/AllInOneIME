---
section: Fixed
---

## en

- Typing no longer stalls in an app that is slow to answer: the first key in a field no longer waits for macOS to say
  whether it is a password field (suggestions show once it has said, none until then), and the candidate box and
  autocomplete's gray text show at once and move to the caret when the app tells where it is.
- `⌃V` opens clipboard history at once: an image copied just before is no longer waited for, its row with its thumbnail
  comes in as soon as it is ready; the history is written to disk without holding up typing.
- Typing no longer stalls while a result being typed out stops, while iCloud sync moves keys or writes the config, or
  on the first key that offers English words among the pinyin candidates; a keyboard layout set for a language is no
  longer looked up again with every key.

## zh-CN

- 在响应慢的 App 里打字不再卡顿：在输入框按第一个键时不再等 macOS 回答它是不是密码框（回答之后才出联想，之前不出），候选框和自动补全的灰字立刻出现，App 告诉光标位置后再移过去。
- `⌃V` 立刻打开剪贴板历史：不再等刚复制的图片，图片准备好后它那一行和缩略图随即补上；写入历史文件也不再卡住打字。
- 逐字输出的结果停下来时、iCloud 同步迁移钥匙串或写配置时、拼音候选里第一次出英文单词时，打字都不再卡顿；按语言设置的键盘布局也不再每个键都重新查一次。
