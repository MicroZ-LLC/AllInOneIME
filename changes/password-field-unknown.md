---
section: Changed
---

## en

- Until the Mac has told that a field is no password field, commands no longer read the field, as in a password field:
  `@` doesn't take the selected text and `@reply` doesn't take the text around the cursor. That holds where the Mac can't
  tell (Accessibility not allowed, or no answer in time) and until it has answered: the Mac is now asked in the
  background as soon as a field gets the focus (once per field, never during secure input), so the answer is usually
  in before the first key and `@` takes the selected text as before; an `@` pressed before the answer is in starts
  without it (Esc and `@` again takes it). What you type after a command is still sent when you run it.
- `@` and `@reply` read the selected text or the text around the caret only once macOS has said that this very field is not a password field: an answer for the field you just left no longer counts for the next one, a field left or a key in another app starts unknown again, and a tap of Option that runs `@reply` (`actionKey` set to `"optionTap"`) follows the same rule as ⏎.
- While macOS is still checking whether a field is a password field, `@reply` does not read its surrounding text or send it to AI.

## zh-CN

- 在 Mac 确认输入框不是密码框之前，命令不再读取输入框，和在密码框里一样：`@` 不取选中的文字，`@reply`
  不带光标前后的文字。Mac 判断不出来时（没给「辅助功能」权限，或没有及时得到结果）是这样，结果还没返回时也是这样：现在输入框一获得焦点，输入法就在后台去问（每个输入框只问一次，安全输入时不问），所以结果通常在第一个键之前就回来了，`@`
  照常带上选中的文字；结果回来之前按的 `@` 不带（按 Esc 再按一次 `@` 就带上了）。你在命令后面打的内容，执行时照样发送。
- 只有在 macOS 确认当前这个输入框不是密码框之后，`@` 和 `@reply` 才会读取选中的文字或光标周围的文字：上一个输入框的判断结果不再算到下一个输入框上，离开输入框或在另一个 App 里按键后会重新判断，轻点 Option 运行 `@reply`（`actionKey` 设为 `"optionTap"`）时与按 ⏎ 遵守同一规则。
- macOS 还在判断输入框是否为密码框时，`@reply` 不再读取光标周围的文字，也不会把它发给 AI。
