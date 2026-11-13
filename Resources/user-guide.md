# AllInOneIME user guide / 使用指南

Short answers about AllInOneIME's own setup: where a setting is, what it does, how to change it. Each topic in English, then in Chinese. 每个主题先英文，后中文。

## About AllInOneIME and its Settings / 关于 AllInOneIME 和设置
AllInOneIME is a macOS input method: type English, Chinese, French, Korean, Hindi or code, and run @ commands where you type. Open Settings with the "AllInOneIME Settings" app (~/Applications or Spotlight), the input menu's Settings…, or @settings. Pages: This Week, General, Input, AI, Privacy, Commands, Advanced, About. The search field at the top of the sidebar finds any setting; its last row, Change: …, changes settings from a sentence you type. Everything is also in the Config file, ~/.config/allinoneime/config.json (Settings → Advanced → Config file → Open); edits apply right away.

AllInOneIME 是 macOS 输入法：打英文、中文、法语、韩语、印地语或代码，在打字的地方用 @ 命令。打开设置：「AllInOneIME 设置」App（~/Applications 或聚焦搜索）、输入法菜单里的「设置…」，或 @settings。页面：本周、通用、输入、AI、隐私、命令、高级、关于。侧栏顶部的搜索能找到任何设置，最后一行「修改：…」用一句话改设置。所有设置也在「配置文件」~/.config/allinoneime/config.json 里（设置 →「高级」→「配置文件」→「打开」），改了马上生效。

## Setup: add it in Input Sources, under Chinese, Simplified / 安装：在输入法的「简体中文」下添加
Run "Install AllInOneIME" from the .dmg (from GitHub Releases or allinoneime.com); no admin password. Then add it yourself, since macOS doesn't let an app do it: System Settings → Keyboard → Text Input → Input Sources → Edit… → + → Chinese, Simplified → AllInOneIME. Switch to it with ⌃Space, or Caps Lock with "Use the Caps Lock key to switch to and from ABC" on. To type Chinese, add it in Settings → Input → Add… → Chinese: its language pack downloads (about 34 MB), no restart. Not listed there: log out and in, then add it again. ⌃Space doesn't reach it: run the installer again. Settings → About shows this step until it's done.

用 .dmg 里的「安装 AllInOneIME」安装（从 GitHub Releases 或 allinoneime.com 下载），不要管理员密码。然后自己添加（macOS 不让 App 代劳）：系统设置 → 键盘 → 文字输入 → 输入法 →「编辑…」→ + →「简体中文」→ AllInOneIME。用 ⌃空格 切换，开了「使用大写锁定键切换“ABC”输入法」也能用大写锁定键。要打中文：设置 →「输入」→「添加…」→「中文」，会下载语言包（约 34 MB），不用重启。找不到它：注销再登录后重新添加；⌃空格 切不到它：重新运行安装程序。

## Accessibility and other permissions / 辅助功能和其他权限
Allow AllInOneIME in System Settings → Privacy & Security → Accessibility. It is needed to keep a panel's keys (↑ ↓ → Esc ⏎ Tab, ⌃V) from the app, to read the selected text, to paste into terminals, to tell password fields apart (learning English words, Autocomplete) and for "@agent and @reply take the Chrome page along". Clipboard history needs Privacy & Security → Paste from Other Apps → Allow. macOS asks once for Terminal (@agent), Notes (@note), Reminders (@reminder) and Contacts (@imessage). Settings → About → Troubleshoot… shows what's missing.

在 系统设置 → 隐私与安全性 →「辅助功能」里允许 AllInOneIME：面板的按键（↑ ↓ → Esc ⏎ Tab、⌃V）不漏给 App、读选中的文字、往终端里粘贴、认出密码框（学英文词、续写），以及「@agent 和 @reply 带上 Chrome 里的网页」都要用它。剪贴板历史要在「隐私与安全性」→「从其他 App 粘贴」里选「允许」。终端（@agent）、备忘录（@note）、提醒事项（@reminder）、通讯录（@imessage）第一次用时 macOS 会问。缺了什么，设置 →「关于」→「排查问题…」会列出来。

## Input languages and switching / 输入语言和切换
Settings → Input → Input languages: the inputs you type in, as chips (English, Chinese, French, Korean, Hindi, and Code after them). Add… adds one (Chinese, Korean and Hindi download a language pack), drag to reorder, ⊗ removes. The first chip is the default: new text fields start in it. Tap Shift to go to the next input (Chinese → English → Code). An app learns where it starts when you switch with Shift before typing, in two of its fields in a row; forget it in the input menu's This App or Privacy → Learned…. Candidate layout (Settings → Advanced): Horizontal (default: ← → choose, ↑↓ or - = turn the page) or Vertical (↑↓ choose, ← → or - = turn the page).

设置 →「输入」→「输入语言」：你用的输入（英文、中文、法语、韩语、印地语，代码排在后面）。「添加…」添加（中文、韩语、印地语会下载语言包），拖动排序，⊗ 移除。第一个是默认：新的输入框从它开始。单按 Shift 换到下一个（中文 → 英文 → 代码）。在一个 App 里连续两个输入框都先按 Shift 再打字，它就记住从那个输入开始；在输入法菜单的「这个 App」或「隐私」→「学到的内容…」里忘掉。「候选排列」（设置 →「高级」）：横排（默认，← → 选，↑↓ 或 - = 翻页）或竖排（↑↓ 选，← → 或 - = 翻页）。

## Chinese: characters, fuzzy pinyin, dictionaries / 中文：字形（简体、繁体）、模糊音、词库
In Settings → Input → Chinese: Characters: Simplified, Traditional (Taiwan) or Traditional (Hong Kong); until you pick, it follows the Mac's preferred languages. Fuzzy pinyin: turn it on and tick the sounds you don't tell apart (z/zh, n/l, in/ing…). Personal Dictionaries → Import or Update…: a UTF-8 Rime .dict.yaml (up to 32 MiB); Chinese pauses about a minute while it builds. Removed candidates: right-click a candidate while typing pinyin (or ⌃⌦ on the highlighted one) to remove it for good; ✕ in this list brings it back. Your own Rime files are in the Rime user folder (Settings → Advanced).

在 设置 →「输入」→「中文」里：「字形」：简体，或繁体：繁體（台灣）、繁體（香港），没选时跟着 Mac 的首选语言。「模糊音」：打开后勾选分不清的音（z/zh、n/l、in/ing…）。「个人词库」→「导入或更新…」：UTF-8 的 Rime .dict.yaml（最大 32 MiB），编译约一分钟，期间中文暂停。「删掉的候选词」：打拼音时右键点候选（或对选中的按 ⌃⌦）就永久删掉，在这个列表里点 ✕ 恢复。自己的 Rime 文件在「Rime 用户目录」（设置 →「高级」）。

## Shuangpin (double pinyin) / 双拼
Shuangpin types each syllable with two keys. Choose it in Settings → Input → Chinese → Typing, above Characters: Full pinyin (the default) or Shuangpin – Xiaohe, Ziranma, Microsoft, Sogou, Zhineng ABC, Pinyin Jiajia or Ziguang (rime-ice's schemes, in the Chinese pack: nothing to download). With Xiaohe, nihc gives 你好. Picking one deploys it beside full pinyin, a second or two (a moment more the first time); then the next key types with it, in every app, no restart. Learned words, fuzzy pinyin, Characters and English words work as before. It syncs with your other settings (`pinyinScheme` in the config). To go back, pick Full pinyin.

双拼：每个音节打两个键。在 设置 →「输入」→「中文」→「输入方式」（「字形」上面）里选：全拼（默认）或双拼 – 小鹤、自然码、微软、搜狗、智能ABC、拼音加加、紫光（rime-ice 自带的方案，随中文语言包装好，不用下载）。用小鹤时打 nihc 出「你好」。选了就和全拼一起部署，一两秒（第一次稍久一点），之后下一个键就按它打，所有 App 都一样，不用重启。学过的词、模糊音、字形和英文词照样能用。和别的设置一起同步（配置里的 `pinyinScheme`）。改回全拼：在那里选全拼。

## Zhuyin (Bopomofo) / 注音
Settings → Input → Chinese → Typing → Zhuyin (Bopomofo) – Standard: the Standard (Daqian) keys macOS's own Zhuyin uses (1 ㄅ, q ㄆ, a ㄇ…; Space is the first tone, 6 ˊ, 3 ˇ, 4 ˋ, 7 ˙): su3cl3 gives 你好. Digits and , . / ; - are Zhuyin keys while you type; ↑↓ (← → in a row) move, Space (after a tone) or ⇧1–⇧0 pick, ⏎ inserts. Picked first, it sets Characters to Traditional (Taiwan); change it any time. No fuzzy pinyin, personal dictionaries or English words in Zhuyin; A tap of Shift inserts what you're typing, converted (你好, not su3cl3), and goes to English; every command works. One @ takes Latin letters (no Zhuyin in it yet).

在 设置 →「输入」→「中文」→「输入方式」里选「注音 – 標準/大千」：和 macOS 自带注音一样的大千键位（1 ㄅ、q ㄆ、a ㄇ…；空格是一声，6 ˊ、3 ˇ、4 ˋ、7 ˙），打 su3cl3 出「你好」。打字时数字和 , . / ; - 都是注音键；↑↓（横排 ← →）移动，空格（声调之后）或 ⇧1–⇧0 选字，⏎ 上屏。第一次选注音时字形设为繁體（台灣），随时可改。注音没有模糊音、个人词库和英文词；单按 Shift 把正在打的转换好上屏（你好，不是 su3cl3），再进英文模式；所有命令照常。一个 @ 里打拉丁字母（暂不能打注音）。

## English words / 英文词
With Chinese input, a few letters bring up English words among the candidates (bedr → Bedrock). Your English words (Settings → Input, in English's section, or in Chinese's without English): type a word and Add, ✕ removes one. Learn English words (Settings → Privacy, on by default): letters put in as typed twice (bedrock ⏎), or a word typed twice in English mode, become candidates; never in password fields, terminals or apps without AI, and it needs Accessibility. They are kept as `englishWords` in the config.

用中文输入时，打几个字母，候选里就有以它开头的英文词（bedr → Bedrock）。「你的英文词」（设置 →「输入」的英文部分；没有英文输入时在中文部分）：打一个词点「添加」，✕ 删除。「学习英文词」（设置 →「隐私」，默认开）：打拼音时原样上屏两次的字母（bedrock ⏎），或英文模式下打了两次的词，以后会出现在候选里；密码框、终端和不用 AI 的 App 里不学，需要辅助功能权限。

## Magic key and action key / 魔法键和执行键
Magic key (Settings → General): typed at the start of a sentence, it opens the command list. @ by default, or # % & * + | ~ (pick another if you @-mention people in chat; the commands become ~improve and so on). An @ right after a letter, digit, . _ or - (an email) is plain text. Action key (Settings → General): the key that runs a command, ⏎ by default. Click it, then press Tap ⌥, ⌥Space, Space or a shortcut with ⌃, ⌥ or ⌘; Use ⏎ resets it. ⏎ always works too. If Alfred or Raycast takes ⌥Space, pick Tap ⌥.

「魔法键」（设置 →「通用」）：打在句首就打开命令列表。默认 @，也可选 # % & * + | ~（常在聊天里 @ 人就换一个，命令随之变成 ~improve 这样）。紧跟在字母、数字、. _ - 后面的 @（邮箱）照常上屏。「执行键」（设置 →「通用」）：执行命令的键，默认 ⏎。点它，再按单按 ⌥、⌥空格、空格或带 ⌃ ⌥ ⌘ 的快捷键；「恢复 ⏎」还原。⏎ 始终也能用。

## Panels and their keys / 面板和按键
Every panel works the same way: the command list, suggestions and clipboard history. The first row is chosen, ↑↓ move, ⏎ or Tab inserts (or runs) it, → or Esc close it and give the keys back. A command's list (@open, @tasks, an extension's) and clipboard history: 5 rows a page, ← → turn it. On results, Space or ⏎ inserts the highlighted one (@question: ⇧⏎), a digit that one (0 the original), ⇧⏎ with nothing typed what you typed, ⌘C copies. To refine, type an instruction ("shorter") and press ⇧⏎; Esc steps back. Use the selected text (Settings → Advanced): a command works on the selection, the result replaces it. Type results out types it letter by letter (Esc stops).

所有面板用法一样：命令列表、建议、剪贴板历史。第一行默认选中，↑↓ 移动，⏎ 或 Tab 上屏（或执行），→ 或 Esc 关掉并把按键还给 App。命令列出的结果（@open、@tasks、扩展的列表）和剪贴板历史一页 5 行，← → 翻页。结果出来后，空格或 ⏎ 上屏选中的（@question 用 ⇧⏎），数字上屏那一条（0 是原文），什么都没打时 ⇧⏎ 原样上屏，⌘C 复制。要改结果：打一句要求（「短一点」）再按 ⇧⏎，Esc 退一步。「使用选中的文字」（设置 →「高级」）：命令处理选中的文字，结果替换它。「逐字上屏」逐字打进去，Esc 停下。

## Commands / 命令
At the start of a sentence type the magic key, a command and its text, then ⏎: @improve polishes and rewrites; @translate translates into your Translate to languages; @question asks the AI; @reply writes three replies to a message; @agent hands the text to a coding agent; @tasks lists background Claude Code tasks; @open opens files, apps and web addresses; @note saves a note; @reminder adds a reminder; @py and @js run a line of Python or JavaScript; @imessage sends a message; @settings opens Settings; @reportissue opens a prefilled GitHub issue. @search and @read are off for now. Anything else after @: the list says what it can do.

在句首打魔法键、命令和文字，按 ⏎：@improve 润色和改写；@translate 翻译成「翻译成」里的语言；@question 问 AI；@reply 给一条消息写三条回复；@agent 交给编程 agent；@tasks 列出后台的 Claude Code 任务；@open 打开文件、App 和网址；@note 存笔记；@reminder 加提醒；@py、@js 运行一行 Python 或 JavaScript；@imessage 发信息；@settings 打开设置；@reportissue 打开填好的 GitHub issue。@search 和 @read 这一版关着。@ 后面打别的，列表会说能拿它做什么。

## @question: asking and its keys / @question：提问和按键
Type @question and your question, then ⏎: the answer shows in the panel. Type a follow-up and ⏎ asks it (⏎ with nothing typed does nothing). ⇧⏎ inserts the highlighted answer (so do its digit, a click, or Space with nothing typed); ⌘C copies it; Esc clears what you typed, then goes back a round. After 5 rounds (`questionRounds`, 2–10), or at any round with ⌘⏎, ⌘1–⌘9 continue it in a coding agent, Claude, ChatGPT, Gemini, or copy it: Settings → Commands → Continue a conversation in. @question with nothing typed lists your last 5 questions; pick one for its saved answer, ⌘R asks again. Remember recent questions is in Settings → Privacy.

打 @question 和问题，按 ⏎，答案出现在面板里。接着打追问，按 ⏎ 就问（什么都没打时 ⏎ 不做事）。⇧⏎ 上屏选中的答案（按数字、点一下、没打字时按空格也行）；⌘C 复制；Esc 先清掉打的字，再退回上一轮。聊满 5 轮（配置里的 `questionRounds`，2–10）或随时按 ⌘⏎，用 ⌘1–⌘9 到编程 agent、Claude、ChatGPT、Gemini 接着聊，或复制对话：设置 →「命令」→「对话接着在哪里聊」。@question 后面不打字时列出最近 5 个问题，选一个看保存的答案，⌘R 重新问。「记住最近的问题」在 设置 →「隐私」。

## Translate and rewrite settings / 翻译和改写设置
In Settings → General: Translate to: the languages @translate writes a line in, in this order (Add…, drag to reorder); the sentence's own language is skipped. Rewrite styles: the lines @improve writes after its three polished ones (concise, formal, casual, tactful, jargon…). @improve also translates: @improve translates too, as @translate @improve does. Jargon list: your team's terms, one per line with an optional meaning, for the jargon style (shown once that style is on).

在 设置 →「通用」里：「翻译成」：@translate 按顺序翻译成的语言（「添加…」，拖动排序），句子本身的语言跳过。「改写风格」：@improve 在三条润色之后多写的风格（简洁、正式、口语、委婉、黑话…）。「@improve 同时翻译」：@improve 也一起翻译，和 @translate @improve 一样。「黑话库」：团队的术语，每行一个，可加解释，给「黑话」风格用（打开这个风格后才显示）。

## Translate as You Type / 边打边译
Hold Shift alone for 1 second to turn it on or off; a quick tap still switches the input. While it's on, what you type collects in a draft beside a chip such as "ZH → EN": ⏎ translates the draft and inserts the translation, ⇧⏎ inserts the draft as typed, Esc stops a translation. Click the target language on the chip to pick another; it's remembered. It uses your AI provider, turns off when you switch apps, and does nothing in Code, in apps without AI or in password fields. The menu bar icon has a dot while it's on. There is no setting or command for it.

单独按住 Shift 1 秒打开或关闭；快速按一下还是切换输入。打开后打的字先攒成草稿，旁边有「中 → 英」这样的标签：⏎ 翻译草稿并上屏译文，⇧⏎ 原样上屏草稿，Esc 停止翻译。点标签上的目标语言换一种，会记住。它用你的 AI 服务，换 App 就关掉，在代码输入、不用 AI 的 App 和密码框里不起作用。打开时菜单栏图标上有个小点。它没有设置项，也没有命令。

## Autocomplete / 续写（自动补全）
Autocomplete (Beta) is off by default: turn it on in Settings → General, the input menu or the menu bar panel. When you pause, the rest of the sentence shows in gray after the caret: Tab takes it, Esc dismisses it, ⌘Z right after Tab takes it back. It uses the AI provider in Settings → AI (with Apple Intelligence it stays on the Mac). It stops by itself in an app where you took none of its last 30 suggestions (turn it off and on to reset), and never runs in code editors, terminals, password fields, password managers or apps without AI.

「续写（Beta）」默认关：在 设置 →「通用」、输入法菜单或菜单栏面板里打开。停一下，光标后面出现灰字的后半句：Tab 接受，Esc 不要，接受后马上 ⌘Z 撤回。它用 设置 →「AI」里的服务（选 Apple Intelligence 时不出这台 Mac）。在一个 App 里最近 30 条都没接受，它就在那里自己停下（关了再开重新开始）；代码编辑器、终端、密码框、密码管理器和不用 AI 的 App 里不运行。

## Suggestions and Code / 建议和代码
Suggestions (Settings → General, on by default): rows under the caret from plugins, script extensions, your suggestions commands and Code; ⏎ or Tab inserts, ↑↓ move, → or Esc hide them. Insert: what a row inserts (default, with title, with title and link, Markdown link). In these apps: an app's own choice, or Off for none there. Code is an input for writing code: Settings → Input → Add… → Code, then the coding language (Python, Java, Go, TypeScript, JavaScript, C, C++); its section has the Installed coding languages and the Coding language library. From two letters on, rows offer keywords and snippets.

「建议」（设置 →「通用」，默认开）：光标下面的几行，来自插件、脚本扩展、你的建议命令和代码输入；⏎ 或 Tab 插入，↑↓ 移动，→ 或 Esc 收起。「插入」：一行插入什么（默认、带标题、带标题和链接、Markdown 链接）。「在这些 App 里」：某个 App 自己的选择，选「关闭」就不显示。代码是写代码用的输入：设置 →「输入」→「添加…」→「代码」，再选编程语言（Python、Java、Go、TypeScript、JavaScript、C、C++）；它那部分有「已安装的编程语言」和「编程语言库」。从第二个字母起给出关键字和代码片段。

## Clipboard history (⌃V) / 剪贴板历史（⌃V）
⌃V shows what you copied lately, newest first, the first row chosen (⌃V ⏎ is the paste you had): ⏎ or Tab inserts, ↑↓ choose, ⇧↑ ⇧↓ several, ← → turn the page, Esc closes (→ too on one page); ⌃V twice pastes as the app does; in a command it's added after your text. Outside a command, typing filters the rows (Chinese by pinyin or initials too). Settings → General → Clipboard history: on by default; Keep the last 20 (5–100); Clear History. It records only with Privacy & Security → Paste from Other Apps → Allow. Text and images up to 10 MB; not password manager items or secure input. It stays on this Mac, never synced or sent; off deletes it.

⌃V 显示最近复制的内容，最新的在前，第一行默认选中（⌃V ⏎ 就是原来的粘贴）：⏎ 或 Tab 上屏，↑↓ 选，⇧↑ ⇧↓ 多选，← → 翻页，Esc 关掉（只有一页时 → 也关）；连按两次 ⌃V 照 App 原来的方式粘贴；在命令里接在你打的字后面。不在命令里时打字就筛选（中文也认拼音和首字母）。设置 →「通用」→「剪贴板历史」：默认开；「保留最近几条」默认 20（5–100）；「清除历史」。要在「隐私与安全性」→「从其他 App 粘贴」选「允许」才会记录。文字和 10 MB 以内的图片；不记密码管理器隐藏的内容和安全输入时复制的。只存在这台 Mac 上，不同步、不发送；关掉就删除。

## AI provider and model / AI 服务和模型
Settings → AI → Provider: AllInOneIME Cloud (sign in, free requests each day), Amazon Bedrock (an AWS Profile from ~/.aws and a Region), Claude API, Gemini API or an OpenAI-compatible API (paste the API key, kept in the keychain; Base URL for another service), or Apple Intelligence on this Mac (macOS 26, no key, nothing leaves the Mac). Model: the model's id. Thinking: how much the model thinks. Test Connection checks that it works. Model Settings show once one is changed: Up to 2000 output tokens, `temperature` and Stop after (seconds).

设置 →「AI」→「服务」：AllInOneIME 云（登录即用，每天有免费次数）、Amazon Bedrock（~/.aws 里的 AWS Profile 和「区域」）、Claude API、Gemini API 或 OpenAI 兼容的 API（粘贴 API key，存在钥匙串里；别的服务填 Base URL），或本机的 Apple Intelligence（macOS 26，不用 key，不出这台 Mac）。「模型」：模型 ID。「思考」：模型想多少。「测试连接」检查能不能用。「模型参数」改过才显示：「最多输出 2000 tokens」、temperature 和「最多运行（秒）」。

## Questions in a Claude Code, Codex, Gemini CLI or Kiro CLI session / 用 Claude Code、Codex、Gemini CLI 或 Kiro CLI 会话回答提问
Settings → AI → Questions (@question): Automatic, a Claude Code, Codex, Gemini CLI or Kiro CLI session, or The AI provider. A session is AllInOneIME's own one of these CLIs, signed in with its own account. Each @question conversation is a new one there, follow-ups in it; earlier ones aren't remembered. Automatic uses @agent's agent's session when ready, else another, else the provider. No round limit; ⌘⏎ continues it in Terminal; Start Over begins a new one. The footer says who answered, "new conversation" and the tokens used. Rewriting, translating and autocomplete use the provider.

设置 →「AI」→「提问（@question）」：自动、Claude Code、Codex、Gemini CLI 或 Kiro CLI 会话，或 AI 服务。会话是 AllInOneIME 自己的这样一个 CLI，用它自己的账号登录。每个 @question 对话在那里都是新对话，追问留在里面，不记得以前的对话。「自动」先用 @agent 的 agent 的会话，不行用另一个，再不行用 AI 服务。没有轮数限制；⌘⏎ 在终端里接着聊；「重新开始」开一个新对话。底部写着谁回答的、「新对话」和用了多少 token。改写、翻译和续写用 AI 服务。

## Opening the AllInOneIME session yourself / 自己打开 AllInOneIME 会话
In Terminal, to read the session's history (its folder is in ~/Library/Application Support/AllInOneIME): Claude Code: `claude --resume AllInOneIME` in claude-session (each conversation is named AllInOneIME). Codex: `codex resume AllInOneIME` (each conversation's thread is named AllInOneIME). Gemini CLI: `gemini --resume latest` in gemini-session. Kiro CLI: `kiro-cli chat --resume` in kiro-session. Gemini CLI and Kiro CLI can't name a session: the ones in that folder are the input method's.

在终端里看会话的记录（文件夹在 ~/Library/Application Support/AllInOneIME 里）：Claude Code：在 claude-session 里 `claude --resume AllInOneIME`（每个对话都叫 AllInOneIME）。Codex：`codex resume AllInOneIME`（每个对话的 thread 都叫 AllInOneIME）。Gemini CLI：在 gemini-session 里 `gemini --resume latest`。Kiro CLI：在 kiro-session 里 `kiro-cli chat --resume`。Gemini CLI 和 Kiro CLI 不能给会话起名：那个文件夹里的都是输入法的。

## Question sessions read the web, not your files / 提问会话只读网页，不碰文件
Whichever CLI answers @question in a session, the session may only read the web: search it and open pages. It can't touch files on this Mac, run commands, use the CLI's MCP servers, extensions or plugins, or start other agents. With text you didn't type in the question (a selection, a screenshot's text, a page), it may open only addresses you typed; with none, it has no web tools. Continued in Terminal with ⌘⏎, it is the CLI as you set it up, with its own tools and prompts.

不管 @question 用哪个 CLI 的会话回答，会话都只能读网页：搜索、打开网页。它不碰这台 Mac 上的文件，不运行命令，不用那个 CLI 的 MCP 服务器、扩展或插件，也不启动别的 agent。问题里有不是你打的文字（选中的文字、截图的文字、网页）时，只能打开你自己打的网址，一个都没打就没有网页工具。用 ⌘⏎ 在终端里接着聊时，就是你自己设置的那个 CLI，用它自己的工具和权限提示。

## Privacy: what is sent / 隐私：什么会发出去
Typing stays on the Mac. Text goes to your AI provider only when you press the action key on an AI command (@improve, @translate, @question, @reply…), or with Autocomplete on. Settings → Privacy: Hide sensitive information before sending replaces emails, numbers, keys and your Words to hide with placeholders such as [EMAIL_1] and puts them back in the results; Apps without AI send nothing to the AI; Remember recent questions keeps your last 5 @question questions on this Mac; Learned… lists what was learned, with Forget. A question about AllInOneIME also sends a few excerpts of this guide: the app's own documentation, never your settings or keys.

打字只在这台 Mac 上。只有在 AI 命令（@improve、@translate、@question、@reply…）上按执行键，或开了续写，文字才发给你的 AI 服务。设置 →「隐私」：「发送前隐藏敏感信息」把邮箱、号码、密钥和「要隐藏的词」换成 [EMAIL_1] 这样的占位符，结果里再换回来；「不用 AI 的 App」里什么都不发给 AI；「记住最近的问题」在本机保存最近 5 个 @question 问题；「学到的内容…」列出学到的东西，可以忘掉。问 AllInOneIME 本身的问题时，还会带上这份指南的几段：App 自己的说明，不含你的设置或密钥。

## @agent and @note settings / @agent 和 @note 的设置
Settings → Commands → Agent (@agent): @agent hands it to Claude Code (default), Gemini CLI, Kiro CLI or your own command; On this Mac says which are installed. Claude Code runs in the background and notifies me (default): @tasks lists it, the notification opens it in Terminal. @agent and @reply take the Chrome page along (Settings → Privacy): in Chrome they also send the address, your field and what's on screen, never a password field; needs Accessibility. Notes (@note) → Save to: Notes (folder "AllInOneIME"), Notion or a Folder (Obsidian or any) of Markdown files.

设置 →「命令」→「Agent（@agent）」：「@agent 交给」Claude Code（默认）、Gemini CLI、Kiro CLI 或你自己的命令；「在这台 Mac 上」显示装了哪些。「Claude Code 在后台运行，做完通知我」（默认开）：@tasks 能看到，点通知在终端打开。「@agent 和 @reply 带上 Chrome 里的网页」（设置 →「隐私」）：在 Chrome 里还会带上网址、你的输入框和屏幕上的内容，不读密码框，需要辅助功能。「笔记（@note）」→「存到」：备忘录（「AllInOneIME」文件夹）、Notion 或 Markdown 文件夹（Obsidian 等）。

## Your own commands / 自己的命令（自定义命令）
Settings → Commands → Your Commands → Add Command… (Custom @ Commands, `customCommands` in the config): a Name, a Description, an Icon (an SF Symbol, one emoji or Default), a Color, and What it does: an AI instruction (sent to your provider), a program (Command; Standard input if it reads stdin), a program in Terminal, a web page (Address), Insert text (a snippet), or suggestions from a program (Prefix; Look up as you type, `query`; Look up from character; Refresh). Test run: a Sample input, run once; nothing is inserted, an AI instruction asks first. Type English letters (for code and paths). Programs run on your Mac, never in password fields: add only ones you trust.

设置 →「命令」→「你的命令」→「添加命令…」：「名字」「说明」「图标」（SF Symbols 符号、一个表情符号或默认）「颜色」和「做什么」：「AI 指令」（发给你的 AI 服务）、程序（「命令」，可选「标准输入」）、在终端里运行的程序、网页（「网址」）、「插入文字」，或程序给的建议（「前缀」「边打边查」「从第几个字开始查」「刷新」）。「试运行」：用「样例输入」运行一次，不上屏，AI 指令会先问你。「用英文字母输入（写代码、路径时）」。程序在你的 Mac 上运行，密码框里不运行：只加你信得过的。

## Plugins and script extensions / 插件和脚本扩展
Settings → Commands → Plugins: the plugins installed (each adds an @ command or suggestions); Browse Library… opens the Plugin Library; your own go in ~/.config/allinoneime/plugins/ (Open Plugins Folder, Refresh). Script Extensions: Raycast-style scripts that run as @ commands; Find Raycast scripts automatically, or add Folders with Add Folder… (~/.config/allinoneime/extensions by default). Extension Sources → Add from Link…: a Git repository of extensions, reviewed before it's added, updated when you choose.

设置 →「命令」→「插件」：装了的插件（每个加一个 @ 命令或建议）；「浏览插件库…」打开「插件库」；自己写的放在 ~/.config/allinoneime/plugins/（「打开插件文件夹」「刷新」）。「脚本扩展」：Raycast 风格的脚本，作为 @ 命令运行；「自动查找 Raycast 脚本」，或用「添加文件夹…」加「文件夹」（默认 ~/.config/allinoneime/extensions）。「扩展来源」→「从链接添加…」：放扩展的 Git 仓库，添加前先审查，你决定什么时候更新。

## Per-app settings / 按 App 设置
Everything works the same way in every app. An app has two settings of its own (Per-App Settings, `appProfiles` in the config): what a suggestion row inserts there, or Off (Settings → General → Suggestions → In these apps), and No AI (Settings → Privacy → Apps without AI). The input menu's This App has both for the app you're typing in. Where an app starts is learned (see Input languages). Previous per-app settings (Settings → General, shown only while an app has one) lists what an earlier version set for an app, with Remove.

每个 App 里用法都一样。一个 App 只有两项自己的设置（「按 App 设置」，配置里的 `appProfiles`）：建议行在那里插入什么，或「关闭」（设置 →「通用」→「建议」→「在这些 App 里」），以及不用 AI（设置 →「隐私」→「不用 AI 的 App」）。输入法菜单里的「这个 App」对你正在打字的 App 有这两项。App 从哪个输入开始是学来的（见「输入语言」）。「以前的按 App 设置」（设置 →「通用」，有才显示）列出旧版本给 App 设的，可以「移除」。

## This week's stats (@stats) / 本周统计（@stats）
Settings → This Week shows this week (Monday–Sunday): commands run (vs. last week), days and apps, characters typed, the top 5 commands, yours/built-in/plugins, how many with AI, clipboard history pastes. Last Week: the week before. Copy Image, Save as Image…: a picture to share; "Hide my command names in the image" shows yours as "My command 1". @stats: ⏎ opens it, ⌘C copies the picture; also atop the menu bar panel. Counts and command names only, never what you type (characters: a number a day; none in password fields); yours lose their names if deleted or renamed. Kept 8 weeks on this Mac, never synced or sent; Privacy → Learned… → Forget All deletes them.

设置 →「本周」显示这周（周一到周日）用了几次指令、比上周同期多还是少、几天和几个 App、打了多少字、最常用的 5 个指令、来自我的命令/内置/插件、几次用到 AI、剪贴板历史粘贴几次。「上周」看上一周。「复制图片」「存为图片…」生成分享的图；「复制时隐藏我的命令名」让你的命令显示成「我的命令 1」。@stats：⏎ 打开这一页，⌘C 复制图片。菜单栏面板顶上也有。只记次数和命令名，不记你打的字（打的字每天一个数；密码框里不算）；自己的命令删掉或改名后不留名字。在这台 Mac 上留 8 周，不同步，不上传；「隐私」→「学到的内容…」→「全部忘掉」会删掉。

## Menu bar, interface language and iCloud sync / 菜单栏、界面语言和 iCloud 同步
Settings → General: Show in Menu Bar: the icon whose panel lists your notes, reminders, Claude tasks and the Autocomplete switch. Interface language: Follow the system, or a language. Sync through iCloud (off by default): your settings, custom commands and learned words, the same on all your Macs, through your own iCloud Drive only; hidden words and recent questions only if you turn them on; Sync Now is in its ⋯ menu. Settings → Advanced: Type results out, Candidate layout, Use the selected text, Config file and Rime user folder (Open).

设置 →「通用」：「在菜单栏显示图标」：点图标下拉出笔记、提醒、Claude 任务和续写开关。「界面语言」：跟随系统，或选一种语言。「通过 iCloud 同步」（默认关）：设置、自定义命令和学到的词在你所有的 Mac 上都一样，只经过你自己的 iCloud 云盘；隐藏的词和最近的问题要你打开才同步；⋯ 菜单里有「立即同步」。设置 →「高级」：「逐字上屏」「候选排列」「使用选中的文字」「配置文件」和「Rime 用户目录」（「打开」）。

## Updates / 更新
Settings → About → Updates: Check for updates automatically (once a day, on by default; nothing installs until you click), Notify me when a new version is out, and Check for Updates. Update to X downloads the signed release, checks it, installs it and restarts the input method, keeping your settings and data; a failed update rolls back. The update check sends nothing you typed; its request carries one identifier, a random install ID made on this Mac (never synced), so installs can be counted. Settings → Privacy → Send an anonymous install ID with the daily update check: off stops it and deletes the ID.

设置 →「关于」→「更新」：「自动检查更新」（每天一次，默认开；你点之前什么都不装）、「有新版本时通知我」和「检查更新」。「更新到 X」下载签过名的版本，检查后安装并重启输入法，设置和数据都保留；更新失败会退回原来的版本。检查更新不发送你打的字；请求里只带一个标识：本机随机生成的匿名安装 ID（不同步），用来统计安装数。设置 →「隐私」→「每日检查更新时附带匿名安装 ID」：关掉就不再发送，并删掉这个 ID。

## Troubleshooting / 排查问题
Settings → About → Troubleshoot… checks the setup on this Mac and offers fixes; describe a problem there and the AI can look at it too. Report an Issue… (About, the input menu, or @reportissue) opens a prefilled GitHub issue. Not under Chinese, Simplified in Input Sources: log out and in, then add it. A panel's keys reach the app: allow Accessibility. ⌥Space taken by Alfred or Raycast: pick Tap ⌥ as the action key. In terminals use ⌃V, not ⌘V. Selected text misbehaves in an app: turn off Use the selected text. In password fields (secure input) keys go in as typed and nothing goes to the AI.

设置 →「关于」→「排查问题…」检查这台 Mac 上的设置并给出修复；也可以在那里描述问题让 AI 帮你看。「报告问题…」（「关于」、输入法菜单或 @reportissue）打开填好的 GitHub issue。「简体中文」下没有它：注销再登录后添加。面板的按键漏给了 App：允许辅助功能。⌥空格 被 Alfred 或 Raycast 占用：执行键选单按 ⌥。终端里用 ⌃V，不用 ⌘V。选中文字时某个 App 不正常：关掉「使用选中的文字」。密码框（安全输入）里按键原样输入，什么都不发给 AI。
