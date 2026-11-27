---
section: Fixed
---

## en

- What you're typing is no longer lost, or typed into the field, when the field loses the focus without a click (a
  notification or a dialog takes it, `⌘Tab`, the page moves it): the panel hides and the draft is kept for that field
  (pinyin not yet picked, the text typed in the `@` list, a command you haven't run), the same in every app. Back in
  the field, the panel and the draft are there again as they were and you go on typing (`⏎`, `Space` as before);
  another field taking the focus instead drops it and starts clean. It comes back only in the field it was typed in,
  told through macOS Accessibility: where the field can't be told again (Accessibility not allowed, a page that
  doesn't tell its fields apart) it is dropped as you leave, never shown in another field, and never in a password
  field. It is also dropped by a key pressed before it shows again (`Shift`, `Caps Lock` and the action key too: they
  act on nothing of it), when another input source is selected, when the screen locks or the Mac sleeps, and after
  ten minutes. A click still leaves as before; `@note` still goes in as typed. Before, `@q` was typed into the field in some
  apps and lost in others (Chrome, Electron apps, Safari), and pinyin was dropped everywhere.

## zh-CN

- 没有点鼠标而失去焦点时（通知或对话框抢走了焦点、`⌘Tab`、网页自己移走了焦点），正在打的内容不再丢失，也不再被打进输入框：
  面板隐藏，草稿（还没选的拼音、`@` 列表里打的字、还没执行的命令）为这个输入框留着，在所有 App 里都一样。回到这个输入框，
  面板和草稿原样回来，接着打（`⏎`、空格和原来一样）；焦点改到别的输入框，就丢掉它，新的输入框从头开始。草稿只回到原来打字的
  那个输入框，靠 macOS 的辅助功能认出它：认不出来的时候（没有辅助功能权限、网页没有区分它的输入框），离开时就丢掉，不会出现
  在别的输入框里，也不会出现在密码框里。草稿重新出现之前按了键（`Shift`、`Caps Lock`、动作键也算，它们不会对草稿起作用），草稿就丢掉；换到别的输入法、屏幕锁定或 Mac 睡眠时也丢掉，留了十分钟以后也丢掉。点鼠标离开和原来
  一样；`@note` 照旧原样上屏。以前 `@q` 在有的 App 里被打进输入框，在有的 App（Chrome、Electron
  App、Safari）里丢失，拼音则在哪里都丢掉。
