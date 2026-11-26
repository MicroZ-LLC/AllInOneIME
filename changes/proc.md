---
section: Fixed
---

## en

- `@agent`, `@imessage`, `@note` and `@open` no longer hang when what they ask doesn't answer: Terminal, Messages and
  Notes get 30 seconds (a Terminal tab with a long scrollback is read whole), the Contacts prompt a minute (left
  unanswered, `@imessage` goes on without the address book and asks again the next time), and the Spotlight search
  behind `@open` is stopped at the search's time limit even when it ignores the request to stop. Unpacking a language
  pack stops after 5 minutes, and a step of an update or of the installer that hangs is stopped, instead of waiting
  forever.

## zh-CN

- `@agent`、`@imessage`、`@note` 和 `@open` 在所询问的应用没有回应时不再卡住：终端、信息和备忘录各有 30 秒（滚动历史很长的终端标签也能完整读取），通讯录授权弹窗等一分钟（没有回应时 `@imessage` 不用通讯录继续，下次再询问），`@open` 背后的 Spotlight 搜索到了搜索时限一定会停止，即使它不理会停止请求。解压语言包最多 5 分钟，更新或安装程序中卡住的步骤会被停止，而不是一直等下去。
