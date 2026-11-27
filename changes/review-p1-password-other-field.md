---
section: Fixed
---

## en

- `@` and `@reply` read the selected text or the text around the caret only once macOS has said that this very field is not a password field: an answer for the field you just left no longer counts for the next one, a field left or a key in another app starts unknown again, and a tap of Option that runs `@reply` (`actionKey` set to `"optionTap"`) follows the same rule as ⏎.

## zh-CN

- 只有在 macOS 确认当前这个输入框不是密码框之后，`@` 和 `@reply` 才会读取选中的文字或光标周围的文字：上一个输入框的判断结果不再算到下一个输入框上，离开输入框或在另一个 App 里按键后会重新判断，轻点 Option 运行 `@reply`（`actionKey` 设为 `"optionTap"`）时与按 ⏎ 遵守同一规则。
