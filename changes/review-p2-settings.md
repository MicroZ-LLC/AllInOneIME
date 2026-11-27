---
section: Fixed
---

## en

- Coming back to the start window, and opening Settings (also on an AI's card or a key's field: the start's "Use My
  Own AI…", the Doctor's, the Assistant's), no longer read `config.json` while your keys wait: it is read in the
  background, as it is when something else changes it while Settings is open.
- ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z work in the text field of the start window's step 3 before Settings has ever been opened.
- An API key removed in Settings right after the input method starts, with "API keys and passwords" sync turned off,
  no longer comes back from iCloud Keychain a moment later (the copy-back that was still waiting to run leaves it out,
  also when iCloud Keychain couldn't be listed the first time and it runs again later, for a key removed or saved in
  between too).
- `@agent` (and continuing a conversation in Terminal): when Terminal doesn't answer in time whether its new window is
  ready, the command is opened with Terminal directly instead of being dropped with nothing run.
- With a CLI chosen as the AI, the autocomplete switch in the input menu and the menu bar panel names the fast fallback
  you just changed to at once, not the one before; and a slow earlier look (a keychain item slow to answer) no longer
  replaces the newer answer, not even after you changed back to the same fallback. Until the new fallback has been
  checked (a key for it, Apple Intelligence available), the switch is shown off and can't be turned on.
- With a CLI chosen and autocomplete off, no API key is read at launch or when the input menu opens (only whether one is
  saved): macOS no longer asks for the login password there after an update.
- Settings no longer shows a saved API key as set, or its provider as the fast fallback, when the Base URL now points at
  another host than the one the key was saved for: requests already refused to send it there. The Settings Assistant,
  Check for problems, iCloud sync and `--status` count it the same way.

## zh-CN

- 回到开始引导窗口、打开设置（包括从「使用我自己的 AI…」、诊断或设置助手打开某个 AI 的卡片或密钥输入框）时，不会再让按键等着读 `config.json`：改在后台读；设置开着时别处改了配置也一样。
- 还没打开过设置时，开始引导第 3 步的输入框里 ⌘C、⌘V、⌘X、⌘A、⌘Z 也能用了。
- 关着「API 密钥和密码」同步时，输入法刚启动就在设置里删掉的 API 密钥，不会过一会儿又从 iCloud 钥匙串复制回来（还在排队的那次回拷会跳过它；第一次列不出 iCloud 钥匙串、稍后重试时也一样，这中间删掉或新保存的密钥同样不会被覆盖）。
- `@agent`（以及在终端里接着聊）：终端没有及时回答新窗口是否就绪时，改为直接用终端打开这条命令，不会再什么都没运行就悄悄丢掉。
- 选了 CLI 作为 AI 时，输入法菜单和菜单栏面板里的续写开关，会立刻写出刚换成的那个更快的 AI，而不是之前那个；较早发出、回来得晚的查询（钥匙串回答得慢）也不会再盖掉新的结果，换回同一个 AI 之后也不会。新换的 AI 还没查过能不能用（有没有密钥、Apple 智能是否可用）之前，开关显示为关、不能打开。
- 选了 CLI、续写关着时，启动和打开输入法菜单都不再读取 API 密钥（只看有没有保存）：更新之后 macOS 不会再在这时要登录密码。
- Base URL 改成了别的主机、而密钥是为原来的主机保存的时候，设置里不再把这个密钥显示成已设置，也不再把它当作更快的 AI：请求本来就不会把它发到那里。设置助手、检查问题、iCloud 同步和 `--status` 也按同样的规则算。
