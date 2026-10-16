Installing AllInOneIME

1. Double-click "Install AllInOneIME" and click Install.
   The input method goes into ~/Library/Input Methods and "AllInOneIME Settings" into
   ~/Applications, and it's added to your input sources. For this user only; no administrator
   password needed.
2. The installer is signed with a Developer ID and notarized by Apple: the first time, macOS only
   asks whether to open an app downloaded from the internet. Click Open. Only use an installer
   downloaded from GitHub Releases or allinoneime.com.
3. Then switch to AllInOneIME with Ctrl+Space. For @improve, @translate and @question, choose an AI
   provider in AllInOneIME Settings first (Amazon Bedrock, the Claude API, Gemini, an
   OpenAI-compatible service, or Apple Intelligence on this Mac).

To update: Settings → About → Check for Updates, or install again from the new disk image; there's
no need to uninstall first. Updating from 0.6.2 or earlier, macOS asks once for your login password
for each key AllInOneIME saved in the keychain: enter it and click "Always Allow".
To uninstall: open "Install AllInOneIME" and click Uninstall…. Settings and learned words are kept.
Needs macOS 14 or later; voice input needs macOS 26 or later.
Documentation: https://allinoneime.com/docs
Made by Weijian Zhang (https://weijianz.com). Source available under FSL-1.1-ALv2 (LICENSE.txt).


AllInOneIME 安装说明

1. 双击「安装 AllInOneIME」，点「安装」。
   输入法装到 ~/Library/Input Methods，「AllInOneIME 设置」装到 ~/Applications，
   并加进你的输入法列表。只装给当前用户，不需要管理员密码。
2. 安装程序用 Developer ID 签名并经过 Apple 公证：第一次打开时，macOS 只会问要不要打开
   这个从互联网下载的 App，点「打开」。只用从 GitHub Releases 或 allinoneime.com 下载的安装包。
3. 装好后用 Ctrl+空格 切换到 AllInOneIME。要用 @improve、@translate 和 @question，
   先在「AllInOneIME 设置」里选好 AI 服务（Amazon Bedrock、Claude API、Gemini、
   兼容 OpenAI 的服务，或本机的 Apple Intelligence）。

更新：设置 →「关于」→「检查更新」，或者用新版的磁盘映像再安装一次，不用先卸载。
从 0.6.2 或更早的版本更新后，AllInOneIME 存在钥匙串里的每个 key，macOS 都会问一次登录密码：
输入后点「始终允许」。
卸载：打开「安装 AllInOneIME」，点「卸载…」。设置和学到的词会保留。
需要 macOS 14 或更新版本；语音输入需要 macOS 26 或更新版本。
使用说明：https://allinoneime.com/docs
作者：Weijian Zhang（https://weijianz.com）。源码公开，采用 FSL-1.1-ALv2 许可（LICENSE.txt）。


Copyright © 2026 MicroZ LLC.
License: FSL-1.1-ALv2, source available (LICENSE.txt). Third-party components: THIRD_PARTY_NOTICES.md
(rime-ice's Lua scripts: GPL-3.0, LICENSE-rime-ice-GPL-3.0.txt).
Source code: https://github.com/MicroZ-LLC/AllInOneIME
