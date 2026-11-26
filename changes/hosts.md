---
section: Fixed
---

## en

- In Chinese mode, `.` `,` and `:` read only the character before the caret to tell whether they follow a digit, no
  longer the text around it: in a slow page (a busy web app, an Electron app) these keys no longer wait on it for many
  reads.

## zh-CN

- 中文模式下，`.` `,` `:` 只读光标前一个字符来判断是否跟在数字后面，不再读光标周围的文字：在反应慢的网页（繁忙的网页应用、Electron 应用）里，按这几个键不再要等它读好几次。
