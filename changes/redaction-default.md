---
section: Changed
---

## en

- New installs hide sensitive information from the AI by default: email addresses, phone numbers, payment card numbers, API keys and tokens, and IP addresses are replaced on the Mac with placeholders such as `[EMAIL_1]` before a request is sent, and the answer gets the real values back before it's shown or inserted. An existing install keeps its setting (off unless you turned it on): Settings → More Settings → Privacy → "Hide sensitive information before sending", `redaction.enabled` in the config.

## zh-CN

- 新安装默认对 AI 隐藏敏感信息：邮箱、电话号码、银行卡号、API 密钥和令牌、IP 地址在请求发出前先在本机换成 `[EMAIL_1]` 这样的占位符，回答在显示和上屏前换回真实内容。已经装了的保持原来的设置（没打开过就还是关）：设置 →「更多设置」→「隐私」→「发送前隐藏敏感信息」，配置里是 `redaction.enabled`。
