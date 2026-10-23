<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · **繁體中文** · [日本語](README_ja.md) · [한국어](README_ko.md) · [Français](README_fr.md) · [Deutsch](README_de.md) · [Español](README_es.md) · [Português (Brasil)](README_pt-BR.md) · [Italiano](README_it.md) · [Русский](README_ru.md) · [Tiếng Việt](README_vi.md) · [ไทย](README_th.md) · [Bahasa Indonesia](README_id.md) · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · [Türkçe](README_tr.md)

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="AllInOneIME 圖示">

# AllInOneIME

### 在 Mac 的每個文字欄位中使用 AI 指令。

在任何 App 中輸入 `@improve`、`@translate` 或 `@question`，按 ⏎，然後挑選結果。<br>
不必複製到聊天視窗，也不必切換 App。用你自己的 AI 供應商、你自己的金鑰。

[![Release](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#安裝)
[![已通過 Apple 公證](https://img.shields.io/badge/Apple-notarized-0a84ff?logo=apple&logoColor=white)](#安裝)
[![Apple 晶片與 Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#安裝)
[![授權：FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![下載次數](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[下載](https://allinoneime.com/download)** · **[網站](https://allinoneime.com)** · **[文件](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[擴充功能](../extensions.md)**

[使用方式](#使用方式) · [指令](#-指令測試版) · [自訂指令](#自訂指令) · [語言](#輸入與翻譯) · [安裝](#安裝) · [隱私](#隱私)

<br>

<img src="../en/demo.png" width="820" alt="@translate 加上一句話，再按 ⏎：西班牙文、法文和德文各一行">

</div>

*這是英文 README 的翻譯；兩者有出入時，以英文版為準。*

> [!NOTE]
> 從 0.6.3 起，AllInOneIME 以 Developer ID 簽署並經過 Apple 公證：不必再到 System Settings → Privacy & Security（系統設定 → 隱私權與安全性）中允許它。從較舊的版本更新後，對 AllInOneIME 存在鑰匙圈中的每把金鑰，macOS 都會詢問一次你的登入密碼：輸入後按一下「Always Allow」（永遠允許）。只從 [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) 或 [allinoneime.com](https://allinoneime.com) 下載 AllInOneIME。

一款在每個文字欄位都能使用 AI 指令的 macOS 輸入法。在句子開頭輸入 `@`，寫完後按 ⏎：`@improve` 潤飾你寫的內容並提供幾種改寫，`@translate` 把它翻譯成你選的語言，`@question` 提出問題，`@agent` 把它交給 Claude Code、Gemini CLI、Kiro CLI 等程式設計 agent，`@open` 尋找檔案和 App，或開啟網址。不以 `@` 開頭時，按鍵照常送到 App。它也能輸入中文（拼音，以 Rime 和 rime-ice 為基礎）、法文、韓文（諺文）和印地文（以拉丁字母輸入天城文），並能把你自己的腳本當作 @ 指令執行。

指令觸發符預設是 `@`。在 Settings → General → Command trigger（命令觸發符）可以改成另一個符號：`#`、`%`、`&`、`*`、`+`、`|` 或 `~`；之後指令就用它開頭（例如 `~translate`），`@` 則照常輸入。字母、數字、空格和打字要用的符號（拼音的按鍵，如 `'` `-` `=` `[` `]` `` ` ``，以及拼音打成中文標點的，如 `,` `.` `?` `\`）不能用，設定裡會說明原因。設定檔裡寫 `"commandTrigger": "~"`。

![@improve 加上一句粗略的話，再按 ⏎：潤飾後的版本，以及改寫](../en/improve.png)

更多細節（每個指令和設定、安裝疑難排解、隱私）請見 [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki)。由 MicroZ LLC 的 [Weijian Zhang](https://weijianz.com) 製作。

## 使用方式

不以 `@` 開頭時，它不會干擾你：在英文模式下，字母直接輸入，⏎ 就是 Return；不會連上網路。新安裝的版本只輸入英文；若也要輸入中文（拼音）、法文、韓文或印地文，請在設定中加入（見[輸入與翻譯](#輸入與翻譯)）。

| 按鍵 | 作用 |
|---|---|
| 輸入拼音，Space／數字鍵 | 中文模式下：選詞，和一般拼音輸入法一樣 |
| `@`（在句子開頭） | 開啟指令清單：最近最常用的排在前面，一次 5 個，可用 ↑↓、滾輪或觸控式軌跡板捲動；或輸入字母來尋找（完整輸入的名稱優先，其次是以這些字母開頭的名稱，再其次是包含它們的）。按 ⏎、Tab、Space 或數字鍵選定 |
| ⏎ | 執行指令。拼音尚未選定時也可以：會先選定，就像按 Space 一樣 |
| Space、⏎／數字鍵 | 結果出現後：插入反白的／對應編號的那一項；0 是原文。後續內容只打了一半時按 ⏎ 也會插入（打的內容會捨棄） |
| ⇧⏎ | AI 結果出現後又輸入了後續內容時：把它送出（`@question` 對話的下一個問題，或修改要求）。正在輸入指令時，或 AI 結果出現後什麼都沒輸入時：照你輸入的原樣插入，連同 `@command`。在其他結果上（`@open`、提醒事項…）插入反白的那一列，和 ⏎ 一樣 |
| ⌘C | 拷貝反白的結果（`@open` 則是路徑）；候選視窗保持開啟 |
| ⌃V | 在指令中（例如 `@improve ` 之後）：把剪貼簿的文字接在你輸入的內容後面，而不是貼到 App 裡。多行會合併成一行，每次最多 2000 個字元（`@note` 會保留換行，最多 20000 個）。在任何 App 中都可用；沒有指令時，按鍵照常送到 App |
| ⌘V | 和 ⌃V 一樣，但有些 App 會自行處理 ⌘V（Ghostty、iTerm2、Terminal 等終端機，以及 Notes），照常貼到 App 裡；在這些 App 中請用 ⌃V |
| Esc、⌫ | 回到句子繼續編輯；結果出現後輸入標點或數字就是接著寫。修改結果後：回到修改前的那一版 |
| AI 結果出現後輸入字母 | 後續內容：`@question` 之後是下一個問題（見[對話](#與-question-對話新)），`@improve` 或提示詞指令之後是修改要求，例如 `shorter`（見[修改結果](#修改結果新)）；按 ⇧⏎ 送出。`@translate` 之後輸入字母是接著寫這個句子，按 ⏎ 重新翻譯 |
| ⌘⏎、⌘1–⌘9 | 在 `@question` 對話中：列出可以接著聊的地方（已安裝的程式設計 agent，`@agent` 所交給的那個排在最前；Claude、ChatGPT、Gemini；或拷貝對話）；⌘1、⌘2… 選一個 |
| 按一下某一列 | 在候選視窗中：選取這一列，和按它的數字鍵一樣（字詞、清單中的指令、結果、`@open` 找到的檔案、收件人、擴充功能列出的列）；指標下方的那一列會反白。文字欄位保持焦點 |
| 輕按 Shift | 有多種輸入語言時：依序切換到下一種（英文 → 中文 → 法文 → …，然後回到第一種） |

## @ 指令（測試版）

| 指令 | 作用 |
|---|---|
| `@improve` | 潤飾：1–3 是用句子本身語言寫的三個版本，4 之後是改寫風格（在設定中加入並排序），0 是原文。不會翻譯；開啟「@improve also translates」（@improve 同時翻譯）時，效果等同 `@translate @improve` |
| `@translate` | 翻譯成你加入的語言（設定 →「Translate」，拖曳可調整順序），每種一行；只有一種語言時提供三個版本；句子本身的語言會略過。`@translate @improve` 一起使用時，一次請求就能翻譯並改寫 |
| `@question` | 提出問題；答案會出現在候選中，按 ⏎ 或 Space 插入，⌘C 拷貝。接著輸入並按 ⇧⏎ 就是追問：候選視窗會變成最多 5 輪的對話，之後建議到 Claude 或其他 AI 接著聊。後面沒有輸入任何內容時，會列出你最近的 5 個問題，最新的在前；接著輸入就能篩選（問題中任何位置的字詞，不分大小寫，中文也可以）。按數字鍵、↑↓ 再按 ⏎，或按一下，會立刻顯示該問題已儲存的答案，不需連網，照常插入或拷貝；在那裡按 ⌘R 會重新提問以取得新的答案。沒有符合的項目，或沒有選取任何項目時，⏎ 會提出你輸入的問題 |
| `@reply` | 針對你要回覆的訊息寫出三則回覆，使用對方的語言和該 App 的語氣（Settings → Apps 中該 App 的第一種改寫風格；沒有的話，聊天 App 用口語，郵件用正式語氣，每則回覆都是完整的郵件內文）。把訊息交給它的方式：選取它；拷貝它，再在草稿中按 ⌃V；或截圖（⌃⇧⌘4，或 WeChat 自己的截圖）再按 ⌃V。它後面輸入的內容說明要怎麼回：`@reply politely decline`。⌘R 再寫三則；見[回覆訊息](#用-reply-回覆訊息新) |
| `@agent` | 把任務交給你 Mac 上的程式設計 agent，在 Settings → Agent 中選擇：Claude Code（預設）、Gemini CLI、Kiro CLI，或你自己的指令（你輸入的內容會作為最後一個引數加在後面）。這一頁也會顯示每個 agent 是否已安裝、如何啟動。Claude Code 預設在背景執行，完成時會發出通知（按一下通知即可在 Terminal 中打開該工作階段繼續），也可以用 `@tasks` 查看；關閉那裡 Claude Code 下方的「Runs in the background and notifies me」（在背景執行並在完成時通知我）就會改在 Terminal 中打開。其他 agent 會在 Terminal 中打開，你輸入的內容就是第一則訊息。每個 agent 都使用自己的登入和設定。在 Google Chrome 中，它會把網頁一起帶上：網址和標題、你輸入時所在的欄位及其表單或區段（以 ★ 標出你所在的位置）、選取的文字，以及視窗中看得到的內容（絕不包含密碼欄位，也絕不是整個網頁）。所以在登入表單的使用者名稱欄位中輸入 `@agent why doesn't this work`，問的是那個欄位；在 pipeline 頁面上輸入 `@agent why is this blocked`，問的是那個頁面；由 agent 判斷是哪一種。網頁的文字照讀到的原樣交給 agent，並標明來自網頁（而不是你下的指示）。這需要輔助使用權限；Chrome 只在 `@agent` 在那裡輸入時才為它建立頁面結構，之後就關閉（Settings → Agent →「@agent and @reply take the Chrome page along」（@agent 和 @reply 帶上 Chrome 網頁）可以全部關閉）。第一次打開 Terminal 時，macOS 會詢問是否允許 AllInOneIME 控制 Terminal：按一下「好」。（0.6.4 之前叫 `@claude`。） |
| `@tasks` | 列出背景中的 Claude 任務（進行中／已完成／等你回應），以及它們最後的回覆；按 ⏎ 在 Terminal 中開啟，⌘C 拷貝回覆 |
| `@settings` | 立即開啟設定視窗（選取它就夠了） |
| `@open` | 邊輸入邊列出符合的檔案、資料夾和 App（Spotlight）。可以輸入多個關鍵字，以空格分隔：每個都必須出現在路徑中，且至少一個出現在名稱中（標準資料夾的名稱也適用於其中的項目：`downloads pdf` 會找到 Downloads（下載項目）中的 PDF）。App 和標準資料夾也能用中文名稱找到，中文介面下也以中文名稱顯示。用 `@open` 開啟過的項目排最前面，接著是 App 和那些資料夾，然後是最近使用或修改過的檔案；若名稱只找到兩個以下的檔案，且沒有符合的 App 或那些資料夾，也會依內容搜尋你個人專屬資料夾中的檔案，這些列標示為「content」（內容）；若沒有其他結果，按 ⏎ 會列出它們讓你挑選，而不是直接開啟第一個。輸入網址時（`github.com`、`localhost:3000`、`https://…`），第一列是「open in the browser」（在瀏覽器中開啟），且不搜尋內容；名稱與其完全相同的檔案（例如 `MANIFEST.in`）排在最前面。以 `~/` 或 `/` 開頭的文字是路徑：Tab 會補全並進入資料夾；⏎ 開啟，⌘C 拷貝路徑 |
| `@note` | 把文字存到 Notes App 中名為 AllInOneIME 的資料夾（不存在時會建立），或存到 Settings → Plugins → Notes (@note) 中指定的地方：Notion，或一個存放 Markdown 檔案的資料夾（Obsidian vault 或任何資料夾）；不會插入任何內容。貼上的文字保留換行，最多 20000 個字元 |
| `@reminder` | 在 Reminders App 名為 AllInOneIME 的列表中加入提醒事項。把時間寫在文字裡；時間在 Mac 上解析，並有一列顯示解析結果：按 ⏎ 或 Space 加入，Esc 返回編輯。有時間的話，會在那時響起提醒；只有日期的話，就是整天 |
| `@py` | 執行一行 Python（Mac 上的 `python3`）並插入結果：程式碼最後一個運算式的值，例如 `@py 2**100`、`@py import math; math.sqrt(2)`，否則就是它印出的內容。沒有 `python3` 時不提供（Xcode 的命令列工具內含） |
| `@js` | 執行一行 JavaScript 並同樣插入結果：最後一個運算式的值，或 `console.log` 印出的內容，例如 `@js [1, 2, 3].map(x => x * 2)`。它使用 macOS 內建的 JavaScriptCore，不需要安裝任何東西；它無法讀取檔案、連上網路或執行其他程式 |
| `@reportissue` | 回報問題：在瀏覽器中開啟 GitHub 的新 issue 頁面，把指令後面輸入的內容當作標題，並附上「What happened / What you expected」（發生了什麼／你預期的結果）讓你填寫。它會加上 App 和 macOS 的版本、Mac 的架構、介面與輸入語言、已安裝的語言包、AI 供應商的種類（若是公開模型則附上模型名稱，否則寫「custom」）、執行鍵，以及你有幾個自訂指令、外掛程式和擴充功能，但絕不包含它們的名稱、你的文字、路徑或金鑰。按 ⏎（或你的執行鍵）會先在候選視窗中顯示這些內容；再按一次 ⏎，或按一下那一列，才會開啟網頁，你在那裡看過後按一下 Submit（使用你的 GitHub 帳號）；Esc 返回。輸入選單（「Report an Issue…」）和 Settings → About 中也有 |
| `@imessage` | 傳送 iMessage：輸入姓名、電話號碼或電子郵件（中文姓名也可以用拼音，全拼或首字母皆可），在候選視窗中選擇收件人（最近傳過訊息的排在前面；完整的號碼或地址也可以），然後寫訊息（其中的指令如 `@stock AAPL` 會先執行）。按 ⏎ 會在視窗中顯示「Send to Alex (…): message」，再按一次 ⏎ 送出，Esc 返回編輯；不會在文字欄位中輸入任何內容。第一次使用時，macOS 會詢問是否允許 AllInOneIME 取用 Contacts（聯絡人）及控制 Messages（訊息）：兩個都按一下「OK」 |

範例：`@q` ⏎，輸入 `what is quantum computing`，⏎。`@note books to read: The Three-Body Problem` ⏎ 會儲存一則備忘錄。`@reminder call Bob tomorrow at 3pm` ⏎，確認它解析出的時間，再按一次 ⏎ 加入。在中文模式下，`@open` 會暫時切換為英文字母，完成後再回到中文。

`@py` 和 `@js` 的程式碼以英文字母輸入，全形標點（來自中文模式）會轉成 ASCII；請寫在同一行，敘述之間用 `;` 分隔。程式碼在獨立的行程中執行，10 秒後或隨時按 Esc 即停止；出錯時會顯示錯誤的第一行，例如 `ZeroDivisionError: division by zero`。多行輸出會照印出的樣子插入；在終端機中則合併成一行插入（終端機會執行收到的每一行）。編輯器內的終端機（VS Code、Cursor、JetBrains）無法與編輯器本身區分，因此在那裡，任何指令的多行輸出都會原樣插入。兩者也都能在其他指令的句子中使用：`@reply the answer is @py 2**100`；含空格的程式碼請加上引號：`@question explain @py "sum(x * x for x in range(10))"`。反過來則不行：`@py` 和 `@js` 的程式碼一定完全照你輸入的內容執行，其中的 `@commands` 不會先執行。

![輸入 @ 開啟指令清單；@question 加上問題，再按 ⏎ 取得答案](../en/commands.png)

![@open 邊輸入邊尋找 App；以 / 開頭則是路徑：列出資料夾內容，Tab 補全](../en/open.png)

`@` 後面接的不是指令時（例如 `@john`），`@` 會照常插入，所以在聊天 App 中 @ 提及別人仍然可用。緊接在字母、數字、`.`、`_` 或 `-` 後面輸入時（例如 `bob@example.com`、`ssh user@host`），`@` 就只是普通文字：不會打開清單，在任何 App 中都一樣，終端機也是。清單打開時，按 ← → 或指令名稱中不可能出現的鍵（`.`、`:`、`/`）會關閉清單，並保留你輸入的內容（`@`、`@im`）原樣不動；在終端機中，← → 這時只會關閉清單。`@question`、`@improve`、`@translate` 和 `@reply` 只在你按下執行鍵時才送到你自己的 Bedrock（截圖在這台 Mac 上辨識，只送出其中的文字）；`@open` 只在這台 Mac 上搜尋；`@note` 和 `@reminder` 只送到這台 Mac 上的 Notes 和 Reminders（若你為 `@note` 選了資料夾或 Notion，則改存到那裡）；`@agent` 使用安裝在你 Mac 上的 agent（預設是 Claude Code 的 `claude` 指令）及其自己的帳號，並且和平常一樣，在修改檔案或執行指令前會先詢問你。沒有安裝該 agent 時，不提供 `@agent`。`@imessage` 只讀取這台 Mac 上的 Contacts（姓名、電話號碼、電子郵件），絕不經過 AI，訊息由 Messages 傳送；沒有 Messages App 時不提供。

### 對選取的文字使用指令（新）

在任何 App 中選取一段文字（Notes 裡的一句話、Mail 裡的一段），輸入 `@improve`、`@translate`、`@question` 或其他處理文字的指令，然後按 ⏎：指令會處理選取的文字，你挑選的結果會取代它。你輸入時，選取的文字保持原樣、維持選取狀態：指令寫在候選視窗中，第一行是你輸入的內容，下一行是「On the selection: “…” (N characters)」（針對選取範圍：N 個字元）。按 Esc、⇧⏎ 或按一下別處，文字都保持原樣；途中改變選取範圍也一樣，而且會取消指令。指令後面輸入的文字，對 `@improve` 和 `@translate` 是要求（`@translate ja`、`@improve more formal`），對 `@question` 則是關於這段選取文字的問題（`@question what does this mean`）。`@open`、`@agent`、`@tasks`、`@settings`、`@reminder`、`@imessage`、`@reportissue`、終端機指令和腳本擴充功能不使用它：它們只用你輸入的內容，選取的文字保持原樣。最多 5000 個字元；處於安全輸入狀態時或在終端機中絕不讀取。若在某個 App 中運作不正常，請到 Settings → General →「Use the selected text」（使用選取的文字）關閉。

### 用 @reply 回覆訊息（新）

`@reply` 會針對你要回覆的訊息，寫出三則可以直接送出的回覆。用下列任一種方式把訊息交給它，然後按 ⏎：

- **選取**欄位中的訊息，再輸入 `@reply`（你挑選的回覆會插在它後面，自成一行）。
- **拷貝**訊息，輸入 `@reply` 後按 ⌃V：候選視窗顯示「Copied message · N characters」（拷貝的訊息 · N 個字元），草稿保持原樣。
- **截圖**到剪貼簿（⌃⇧⌘4，或 WeChat 自己的截圖），輸入 `@reply` 後按 ⌃V：候選視窗顯示「Screenshot · N lines (read on this Mac)」（截圖 · N 行（在這台 Mac 上辨識））。截圖在這台 Mac 上辨識（Apple 的 Vision，第一次會稍慢），只送出其中的文字；圖片不會送到任何地方，也不會保留。和聊天 App 的顯示方式一樣，左邊的是對方說的，右邊的是你說的；訊息之間的時間會略去。WeChat 的視窗無法用其他方式讀取，就用這個方法。

在它後面寫你想怎麼回（`@reply politely decline`、`@reply 委婉拒绝`），或什麼都不寫，讓它給出合理的回答。回覆使用對方的語言（除非你要求其他語言），語氣則依 App 而定：Settings → Apps 中該 App 設定的第一種改寫風格；沒有的話，聊天 App 用口語，郵件 App 用正式語氣，每則回覆都是完整的郵件內文。游標前後的文字也會一併帶上。`@reply` 後面沒有輸入任何內容時按 ⌫，會移除貼上的內容。按 ⏎ 或數字鍵插入一則回覆；⌘R 再寫三則（Esc 回到這三則），輸入要求則和任何 AI 結果一樣可以修改它們。在 Google Chrome 中，沒有選取也沒有貼上任何內容時，它會和 `@agent` 一樣把網頁一起帶上（Settings → Agent →「@agent and @reply take the Chrome page along」）。沒有可回覆的訊息、也沒有輸入任何內容時，它會說明需要什麼。隱藏敏感資訊也適用於截圖中的文字；處於安全輸入狀態時，不會讀取剪貼簿，也不會送出任何內容。你先前自己建立、名為 `reply` 的自訂指令，現在改名為 `@myreply`。

截圖貼進其他指令也可以：`@translate` 按 ⌃V 會翻譯截圖（結果插入游標處），`@question what does this say` 按 ⌃V 會詢問截圖的內容，不使用 AI 的指令則會收到截圖中的文字，就像拷貝來的一樣（`@note` 會保留它的換行）。選取了文字時，`@improve` 和 `@translate` 仍然處理選取的文字，並提示截圖沒有用上。

### 修改結果（新）

`@improve`、提示詞指令（你自己的或外掛程式的）或改寫選取文字的結果出現時，直接輸入想怎麼改，例如 `shorter`、`warmer`、`more formal`、`add a joke`、`in Japanese` 或 `用更口语的说法`（可以打拼音，輕按 Shift 切換語言），然後按 ⇧⏎：結果會連同你的要求再次送給 AI，新的結果在同一個候選視窗中取代舊的。按 ⏎ 會插入選取的結果，要求只打了一半時也一樣（打的內容會捨棄）。想改幾次都可以；候選視窗最上面一行列出修改過的步驟（「Refined: shorter · more formal」），你隨時都能照常選取某一列。輸入一個字母就開始寫要求（在候選視窗頂端顯示為「refine › …」）；要求還是空的時候，數字鍵、Space 和 ⏎ 照常選取，⇧⏎ 則照你輸入的原樣插入。結果全部出現後才能修改：第一批結果還在陸續出現時輸入，和以前一樣是接著寫這個句子。修改進行中也可以先輸入下一個要求；修改會繼續進行，結果出來後按 ⇧⏎ 就執行下一個。Esc 會先清除要求，再退回上一步、回到最後一次修改之前的結果（修改進行中則是停止它），然後回到句子；在空白行上按 ⌫ 也會以同樣方式退回。對選取的文字使用時，你挑選的結果仍然只會取代選取的文字，在那之前文字保持不動。修改失敗（或在安全輸入狀態時被拒絕）時，結果保持原樣，要求也還在，按 ⇧⏎ 可再試一次。對同樣的結果做同樣的修改，會直接用快取回答。`@translate` 沒有修改功能：結果出現後輸入是接著寫這個句子，按 ⏎ 重新翻譯。

### 與 @question 對話（新）

`@question` 回答之後，你接著輸入的就是下一個問題：按 ⇧⏎ 會連同之前的問答一起提問，候選視窗隨之長成一段對話，前面幾輪以淡色的 Q / A 列顯示，最新的答案在它們下方。最上面一行顯示接下來是第幾輪（「question 2/5 › …」）。每個答案都能插入：按它的數字（1–5）、↑↓ 再按 ⏎，或按一下；預設選取最新的，⌘C 拷貝選取的那個。問題只打了一半時按 ⏎ 也會插入答案（打的內容會捨棄）。Esc 會先清除你輸入的內容，再退回上一輪；在第一輪時就和以前一樣離開。候選視窗最多長到約半個螢幕高，之後改為捲動，最新的在最下面。

5 輪之後（設定檔中的 `questionRounds`，2–10），下一個問題的那一行會變成「5 rounds in: continue in Claude or another AI」（已聊 5 輪：到 Claude 或其他 AI 接著聊），選項依 ⌘1、⌘2… 編號；任何一輪按 ⌘⏎ 都能顯示這些選項（答案還在出現時按它不做任何事，也絕不會傳給 App）。這時你輸入的內容就是到那邊的第一則訊息；只有 ⌘1、⌘2… 會送出它（⇧⏎ 不再提問，也不打開任何東西）。對選取文字提出的問題會把那段文字一起帶過去，作為獨立的引用區塊。可選的有：

- 這台 Mac 上**已安裝的程式設計 agent**，各自顯示名稱：`@agent` 所交給的那個排在最前（⌘1），接著是其他的（Claude Code、Gemini CLI、Kiro CLI、Settings → Agent 中你自己的指令）。每個都會在 Terminal 中開啟一個互動式工作階段，啟動方式和 `@agent` 相同，開頭是這段對話和「Let's continue this discussion」。沒有安裝的不會顯示。
- 網頁版 **Claude** 或 **ChatGPT**，對話已經填好（太長時會放到剪貼簿：貼上即可）。
- 網頁版 **Gemini**，對話在剪貼簿中，貼上即可。
- **Copy the conversation**（拷貝對話），Markdown 格式（**Q:** / **A:**）。

要列出哪些、依什麼順序（第一個為預設）：Settings → General →「Continue a conversation in」（對話接著在哪裡聊；設定檔中的 `questionContinueIn`）；超過 5 個時，用 ⌘6…⌘9 選擇其餘的。那裡的「@agent's agent」（@agent 的 agent）就是 Settings → Agent 中所選的那個 agent，並顯示它的名稱；目前沒有安裝的 agent，在你編輯清單時仍會保留原本的位置。使用這台 Mac 的 Apple Intelligence 時，長對話放不進它很小的上下文：會先縮短最早的答案，再略去最早的幾輪，候選視窗會顯示「earlier rounds shortened」（前面幾輪已縮短）。對話會以第一個問題存在最近的問題中，選取它就會顯示各輪內容，讓你接著聊。

### 最近的問題（新）

`@question` 後面沒有輸入任何內容時，會列出你最近的 5 個問題，最新的在前，並註明提問時間（「3 hours ago」）。接著輸入就能篩選：每個字詞出現在問題中任何位置都算，不分大小寫（不含空格的中文也可以）。按數字鍵、↑↓ 再按 ⏎，或按一下，會立刻顯示該問題已儲存的答案，不需連網：Space 或 ⏎ 插入，⌘C 拷貝，⌘R 重新提問以取得新的答案（對話則是重新提出最後一個問題），Esc 回到清單。已儲存的對話會顯示所有輪次：接著輸入就能繼續聊。沒有符合的項目，或沒有選取任何項目時，⏎ 會提出你輸入的問題。同一個問題有了新答案，或對話又繼續聊下去，就會取代已儲存的那個。

- 它們只存放在這台 Mac 上（見「隱私」）：處於安全輸入狀態時不存，對選取文字提出的問題一律不存。
- Settings → General →「Remember recent questions」（記住最近的問題）可以關閉此功能（設定檔中的 `rememberQuestions`）；在那裡關閉時也會刪除它們。透過 Settings → Assistant 關閉時則會保留它們，讓還原時能完全回到原本的狀態（它的預覽會說明這點）；「Clear (N)」（清除）會刪除它們。

### 備忘錄與提醒事項

`@note` 會建立一則新備忘錄；第一行是標題。拷貝一段文字後，在 `@note ` 後面按 ⌃V（在終端機以外也可按 ⌘V），即可連同換行一起儲存，換行在指令中顯示為 ↵。要存到哪裡，在 Settings → Plugins → Notes (@note) → Save to（儲存到）中選擇：

- **Notes**（和以前一樣）：在 AllInOneIME 資料夾中建立一則新備忘錄。
- **Folder (Obsidian or any)**（資料夾，Obsidian 或任何資料夾）：每則備忘錄在你選的資料夾中建立一個新的 Markdown 檔案，以第一行命名（`/\:*?"<>|#^[]` 會換成 `-`；名稱已被使用時加上「 2」、「 3」）。檔案開頭是 `created:` front matter，接著是照你輸入的完整文字。絕不覆寫現有的檔案，也不會建立不存在的資料夾（未裝載的磁碟、搬走的 vault）：備忘錄會回到指令中。在 Obsidian vault 中（它或它上層有 `.obsidian` 資料夾）時，通知會顯示「Saved to Obsidian」，選單列面板也會在 Obsidian 中打開這則備忘錄。
- **Notion**：按「Create Integration…」（New integration → Internal → 拷貝權杖），貼上權杖（存放在鑰匙圈中），然後在 Notion 中打開那個頁面或資料庫 → ··· → Connections → 加入你的 integration，再貼上它的連結；Test 會顯示「✓ “Inbox” (database)」。頁面會新增一個子頁面，資料庫會新增一列（以第一行為標題）；備忘錄的其餘部分是內文，一次請求送出。離線或被拒絕時，不會留著稍後再送：備忘錄會回到指令中。處於安全輸入狀態時，`@note` 不會送到 Notion。

通知會說明備忘錄存到哪裡（「Saved to Notion」、「Saved to “Inbox”」）。如果含換行的備忘錄還沒儲存，你就離開了文字欄位（按一下其他地方、切換 App）或按了 ⇧⏎（照輸入內容插入），它不會被輸入到 App 中（在終端機裡，每一行都會被當成指令執行），而是放到剪貼簿（「The note wasn't saved; its text is on the clipboard」）。只有一行的備忘錄則照輸入內容插入。

`@reminder` 能解析 `tomorrow at 3pm`、`in 2 hours`、`in 3 days at 3pm`、`on the 15th`、`this weekend`、`in 1 month`、`next month`（該月 1 日）、`end of the year` 這類時間（中文的時間寫法也可以）。日期和時間可以分開寫（`tomorrow call Bob at 5`）；一週從星期一開始。沒寫上午或下午的時間（`at 5`）取接下來最近的那一個，且絕不會落在午夜到早上 6 點之間；今天已經過了的時間算明天，但仍在進行中的時段（`this afternoon`、`tonight`）算今天、整天；今年已經過了的日期算明年。寫成重複的（`standup every Monday at 9`）只會加入一次，設在下一次：這些字留在標題中，該列顯示「once only」（僅一次）。確認用的那一列會顯示解析出的時間，例如「tomorrow 3:00 PM」（依照 Mac 的 12／24 小時制設定）；若不對，按 Esc 回到文字。文字中沒有時間或日期時，就不設時間（「no date」）。

在這兩個指令中，`@stock` 之類的指令不會執行：文字照寫的內容儲存（在其中輸入 `@` 也不會開啟指令清單）。第一次使用時，macOS 會詢問是否允許 AllInOneIME 控制 Notes（`@note`）或取用 Reminders（`@reminder`）：請允許。如果當時沒有允許，請到 System Settings → Privacy & Security → Automation（系統設定 → 隱私權與安全性 → 自動化）（Notes）或 → Reminders 中允許 AllInOneIME。儲存失敗時（例如沒有權限），通知會說明原因，文字也會回到指令中，讓你修正後再送出；如果你得先處理某件事（權限、帳號），文字也會放到剪貼簿（前往 System Settings 會讓文字欄位失去焦點）。如果你已經移到另一個文字欄位，或正在輸入其他內容，文字則改為放到剪貼簿（「Not saved; the text is on the clipboard.」）。

### 自訂指令

在設定的「Custom @ Commands」（自訂 @ 指令）下，按一下「Add Command…」（新增指令…）：取個名稱並選擇它做什麼（AI 指示、程式、在 Terminal 中執行的程式、網頁，或要插入的文字），或從範例開始。你的指令排在內建指令之後；名稱只能用英文字母，且不能和內建指令同名；從下一句起生效。它們存放在設定檔（`~/.config/allinoneime/config.json`）的 `customCommands` 中，你也可以直接編輯：

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" },
  { "name": "sig", "type": "snippet", "summary": "Email signature", "text": "Best,\nWei\n{cursor}" }
]
```

| `type` | 作用 |
|---|---|
| `prompt` | 以 `prompt` 為指示送到 AI；答案出現在候選中，可插入或拷貝（⌘C） |
| `run` | 在背景執行 `argv`；它印出的內容出現在候選中（多行會照印出的樣子插入，在終端機中則合併成一行）。出錯時顯示它的最後一行 |
| `terminal` | 在新的 Terminal 視窗中執行 `argv`；不插入任何內容 |
| `link` | 把文字放進網址 `url`，並在預設瀏覽器中開啟；不插入任何內容 |
| `snippet` | 立即插入 `text`，並填入其中的預留位置（見下文）；不用 AI，也不執行程式 |

- `{input}` 會換成你在指令後面寫的內容，而且永遠只留在它所在的那一個引數裡：不經過 shell。需要 shell 時請明確指定，如上面的 `sh`（`zsh -c`）。
- `stdin`：送到程式標準輸入的內容，其中的 `{input}` 也會被替換。
- `link` 的 `url` 必須是 `https://`，`{input}` 只出現一次，且在 `?` 或 `#` 之後；文字會經過編碼（空格是 `%20`，換行是 `%0A`），最多 4000 個字元。
- `run` 和 `terminal` 預設以英文字母輸入（和 `@open` 一樣；在中文模式下，之後會切回中文），全形標點會轉成 ASCII。設定 `"ascii": false` 即可保留輸入的原樣。
- 程式在你的個人專屬資料夾中執行，使用你登入 shell 的 PATH（因此找得到透過 Homebrew、pyenv 和 nvm 安裝的程式）。`run` 會在 10 秒後（`timeoutSeconds`）或輸出過多時停止程式；隨時可按 Esc 停止。
- `summary` 是指令清單中的說明（選填）。
- 找不到 `argv` 中的程式時（例如沒有 `python3`），不會提供該指令，`@python …` 會當作文字插入；安裝之後，下一個文字欄位就會出現該指令。

`run` 和 `terminal` 會在你的 Mac 上執行程式碼：只加入你自己寫、且信任的指令。它們同樣只在你按下執行鍵時才執行，且絕不在安全輸入期間執行。

#### 片段：常用的文字（新）

`snippet` 指令（編輯器中的「Insert text」，插入文字）會插入你存好的文字，例如簽名、地址或會議連結：`@sig` ⏎ 立即插入（Tab 或 Space 只補全名稱）。它的 `text` 中可以放預留位置：

| 預留位置 | 換成 |
|---|---|
| `{input}` | 你在名稱後面寫的全部內容：`#{input}` 搭配 `@tag foo bar` 會插入 `#foo bar` |
| `{name?}` | 填空：依序用你寫的內容填入，以逗號（`,` 或 `，`）分隔：`Dear {name?}, see you {day?}.` 搭配 `@meet Bob, Friday`。有填空沒填到時，通知會說明是哪一個，且不插入任何內容 |
| `{clipboard}` | 剪貼簿中的文字（macOS 可能會先詢問） |
| `{selection}` | 你輸入 `@` 時選取的文字（它會被取代，和任何對選取文字使用的指令一樣） |
| `{date}`、`{time}` | 今天，例如 `2026-10-17`；時間，例如 `14:05`；`{date:EEEE, MMM d}` 則依[日期格式](https://unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table)，以介面語言顯示 |
| `{cursor}` | 插入後游標停在這裡（最多一個；終端機中不適用） |

- `{{` 寫出 `{`，與它配對的 `}}` 寫出 `}`（`{{input}}` 會插入 `{input}`）；其他的 `}}` 或 `{…}` 保持原樣，所以片段中放 JSON 或程式碼都沒問題：`{"a":{"b":1}}` 會照原樣插入。
- 沒有 `{input}` 也沒有填空時，你在名稱後面寫的內容會接在片段後面，中間隔一個空格。
- 在其他指令的文字中寫 `@sig` 就能把片段帶進去：`@question summarize this @zoom` 送出的是連結本身。只有不含 `{clipboard}`、`{selection}` 或填空的片段能這樣用；含 `{input}` 的，引數是一個詞或加上引號的片語：`@meet「Friday 3pm」`。
- 只限純文字（保留換行），最多 20000 個字元。片段只留在這台 Mac 上，所以在安全輸入期間和設為 No AI 的 App 中也能用。擴充功能套件也可以附帶片段（`extension.json` 中的 `snippets`，見 [docs/extensions.md](../extensions.md)）。

### 腳本擴充功能

把你自己的 @ 指令寫成程式：任何語言的腳本（bash、Python、Node、Swift…），在註解中加上幾行中繼資料。放在 `~/.config/allinoneime/extensions`，或放在你從「Settings → Custom Commands → Script Extensions」（設定 → 自訂指令 → 腳本擴充功能）加入的資料夾中。Raycast Script Commands 可以直接使用，已經存放它們的資料夾會透過 Spotlight 找到。

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh` 就是 `@flights`。在它後面寫引數，以逗號分隔：`@flights beijing, new york` 會以 `beijing` 和 `new york` 作為 `$1` 和 `$2` 執行（多出的逗號留在最後一個引數中）；必要的引數留空時，會說明缺少什麼，而不會執行。它印出的內容依 `output` 的設定使用：

| `output` | 結果 |
|---|---|
| `insert`（預設） | 全部內容，以及每一行，都可以插入 |
| `show` | 邊印邊顯示在面板中（進度）；不插入任何內容。離開欄位後，它會在背景繼續執行（最多同時四個） |
| `list` | Alfred Script Filter JSON 格式的清單，隨你輸入重新執行；選取一列會插入、開啟（網址、檔案或資料夾；絕不開啟會執行的東西）、拷貝，或執行第二步 |
| `silent` | 在游標附近顯示最後一行；不插入任何內容 |

指令也可以不接收輸入（`input none`：在名稱上按 ⏎ 即執行）、在背景（`background`）執行並在完成時通知你（期間會列在選單列面板中）、在指令清單中的名稱旁顯示狀態（`status`），或先詢問（`confirm`）。它在自己的資料夾中執行，使用你登入 shell 的 PATH 以及 `ALLINONEIME_*` 變數：介面語言和輸入語言、你正在輸入的 App、文字。**套件**（bundle）是一個含有 `extension.json` 的資料夾，裡面列出它的指令：這些指令共用程式碼和偏好設定，偏好設定會顯示在設定中（密碼存到鑰匙圈）。設定會列出每個指令並附有開關，也會列出被略過的腳本及原因。

Raycast 的模式對應如下：`fullOutput` → `show`，`compact` 和 `silent` → `silent`，搭配 `refreshTime` 的 `inline` → 狀態。完整的協定請見 [docs/extensions.md](../extensions.md)；[Core/Examples/extensions](../../Core/Examples/extensions) 中每種各有一個範例。擴充功能會在你的 Mac 上執行程式碼：請使用你信任的。它們只在你執行時才執行（狀態或清單則在你輸入時執行），絕不在安全輸入期間執行，並會在輸入法結束時停止。

#### 擴充功能來源（新）

套件可以來自一個 Git 儲存庫（你自己的或團隊的），並從那裡保持更新。「Settings → Custom Commands → Extension Sources → **Add from Link…**」（設定 → 自訂指令 → 擴充功能來源 → 從連結加入…）：貼上儲存庫的位址（`git@github.com:you/my-extensions.git`、`ssh://…`、`https://…`；也可以另外指定分支、套件在儲存庫中的資料夾，以及要固定的標籤或提交）。AllInOneIME 用**你自己的 git 和 SSH 設定**（金鑰、agent、~/.ssh/config、憑證輔助程式）來 clone，所以私有儲存庫和在 Terminal 中一樣能用；App 從不詢問也不儲存密碼。clone 會放在 `~/Library/Application Support/AllInOneIME/Sources/`：先放進一個隱藏的暫存資料夾，絕不會直接放進擴充功能資料夾。（不要在 https 位址中寫入使用者名稱、密碼或權杖：交給 git 的憑證輔助程式保存。）

- **先審查。** 載入任何東西之前，你會看到套件、每個指令（名稱、標題、說明、輸出方式）、它們執行的程式、它的偏好設定和提交，上方有警告「This source isn't signed: it will run programs from <address>」（這個來源沒有簽署：它會執行來自該位址的程式）。只有按 **Enable**（啟用）才會加入；Cancel（取消）會刪除 clone。每個來源只需審查一次。
- **更新由你決定是否套用。** 每天一次（以及輸入法啟動後不久）會 fetch 來源，看看有什麼新內容：設定會顯示「N updates」（N 個更新）和這些提交（主旨、作者、日期），頁面上也會有標記。在你按 **Update**（更新）之前什麼都不會改變；更新只做 fast-forward，不執行任何 hook。強制推送（force push）之後，來源需要重新審查：**Re-clone**（重新 clone）會再顯示一次審查內容，只有按 Enable 才會換上改寫過的歷史（在那之前，審查過的版本照常運作）。固定到標籤或提交的來源不會檢查更新。每天的檢查可以針對個別來源關閉（`autoCheck`）。
- **錯誤**會照錄 git 自己的訊息，並加上「This uses your own git and SSH setup; check that `git ls-remote <url>` works in Terminal」（這裡使用的是你自己的 git 和 SSH 設定；請在 Terminal 中確認這個指令能正常執行），如果你設定了自己的提醒（設定檔中的 `authHint`），也會顯示在下方。
- **Remove**（移除）會把 clone 移到垃圾桶；套件的偏好設定會保留，下次還能用。
- 在終端機中：`AllInOneIME --add-source <url> [--path …] [--branch …] [--pin …]`（印出審查內容並啟用；強制推送之後再執行一次）、`--update-sources`（對每個已審查且未固定的來源做 fast-forward）、`--list-extensions`（執行檔為 `~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME`）。
- 只會載入審查過的程式碼：載入清單中的來源資料夾若沒有在這台 Mac 上審查過（例如複製過來的設定檔），就不會載入。git 從不等待回應：沒有終端機，也不會跳出詢問，所以遇到不認得的主機金鑰或要求輸入密碼時會立即失敗。

設定檔中以 `extensionSources` 保存它們；儲存庫的結構請見 [docs/extensions.md](../extensions.md#10-extension-sources)。

### 外掛程式

外掛程式是現成的 `@` 指令，用於不是每個人都需要的功能，例如用 `@stock AAPL 600519 700` 查詢股價。安裝後，它們和其他指令一樣使用；設定中的「Plugins」（外掛程式）會顯示已安裝的外掛程式、各自把你的文字送到哪裡，並可移除它們。外掛程式是在獨立行程中執行的 JavaScript：它們只能連到自己宣告的網站（HTTPS），無法讀取檔案或執行其他程式。設定中「Plugins」下的「Browse Library…」（瀏覽程式庫…）可從[外掛程式庫](https://github.com/MicroZ-LLC/AllInOneIME-plugins)安裝外掛程式：安裝前會顯示外掛程式會連到哪些網站；程式庫的索引經過簽署，每個檔案都必須與索引相符。有新版本時會顯示「Update」（更新）按鈕；不會自動更新任何東西。你自己的外掛程式放在 `~/.config/allinoneime/plugins/`（「Open Plugins Folder」，打開外掛程式資料夾）：這些是本機外掛程式，絕不會被程式庫覆寫。「Link」（連結）外掛程式不執行任何程式碼：它們把文字放進網址並在瀏覽器中開啟，例如 `@x nice weather today` 會開啟 X 的撰文畫面並填好文字；要不要發佈由你在頁面上決定。程式庫中有四個（`@x`、`@threads`、`@bsky`、`@weibo`）。`@xe` 換算貨幣：`@xe 100 USD CNY`、`@xe 1000 JPY EUR`，結果為一行，附上匯率日期（匯率來自 ExchangeRate-API）。`@calculator` 是離線也能用的計算機：`@calculator 23*17` → `391`（0.6.5 以前是內建的 `@calculate`）；`@calendar` 計算日期：`@calendar +10` → 「周二 10月27日 · 10天后」。撰寫外掛程式：[docs/plugins.md](../plugins.md)。

會擷取資料的指令（外掛程式和程式）也能在句子中使用：`@reply tell her @stock AAPL is up today`。內層的指令先執行，它們的輸出取代它們原本的位置，外層的指令再處理結果。引數是指令後面的那個詞，加上緊接其後的大寫代碼或數字（`@stock AAPL TSLA`、`@stock 600519 700`）；遇到小寫的詞就結束（`@stock SNDK is good to buy` 查詢的是 SNDK）。引號可以精確標出引數：`@stock "aapl tsla"`。`@calculator` 外掛程式也能在句子中使用：`@reply the total is @calculator 23*17 dollars`。在 `@agent` 和終端機指令中，它們不會執行：這些指令收到的是照寫的文字（在其中輸入 `@` 也不會開啟指令清單）。

### 執行鍵

預設為 ⏎；可在設定的「Action key」（執行鍵）下更改（設定檔中的 `actionKey`）：⏎、「Tap ⌥」（輕按 ⌥，左右皆可：按下後立刻放開）、⌥Space，或 Space（選好字詞後再按一次 Space；英文模式下按兩次）。無論執行鍵設為什麼，@ 指令也都能用 ⏎ 執行。如果 ⌥Space 已經是 Alfred、Raycast 之類工具的快速鍵，會先被它們接收。

### 逐字輸入結果

在 Settings → General 中開啟「Type results out」（逐字輸入結果）（設定檔中的 `typeOut`），指令的結果就會像真人打字一樣一個字元一個字元地輸入到 App 中，而不是一次全部插入；拼音選字仍然一次插入。滑桿調整速度，從每個字元 6 秒到每秒 40 個字元（`typeOutRate`）；「Speed up and slow down (like a person)」（像真人一樣忽快忽慢）會以速度變化的短促節奏輸入（`typeOutVaries`）。Esc 會停在目前位置；按其他任何鍵會一次輸入剩下的部分。

「Make occasional typos and fix them」（偶爾打錯再修正，`typeOutMistakes`）讓它看起來更像真人：偶爾按到正確按鍵旁邊的鍵，最多三個字母後才發現，刪掉再重打；一個字母或空格打了兩次再刪掉；或一個短字打了、刪掉再重打。每 100 個字元有幾處，絕不會兩處挨在一起，也絕不會出現在一行的開頭。在程式碼、網址、電子郵件地址和數字中，打錯只會是錯的字母或數字，並立刻修正（絕不會打錯括號、引號或空格，編輯器會針對這些自動配對或縮排）。打錯的字母是你的鍵盤配置（QWERTY、AZERTY、QWERTZ…）上相鄰的鍵。中文、日文和韓文只會「猶豫」（打兩個字元、刪掉再重打），絕不會打出錯字。

在能收回打錯的欄位中（Apple 的文字檢視，例如 TextEdit 和 Notes、瀏覽器、大多數編輯器）：打到最後，或按其他鍵一次輸入剩下的部分，文字就和結果完全相同；在打錯的當下按 Esc（或離開欄位），會先把打錯的部分刪掉，因此欄位中是結果開頭的一段，一字不差。若打錯的字還在畫面上時游標移動了（按了一下），打錯的部分會在原處刪掉，剩下的部分不再打錯。

在終端機中絕不打錯，在不告訴輸入法游標位置的 App 中也不會。每次第一處打錯都是簡單的一種（一個錯的字母，一次修正），直到該欄位表現出能收回打錯；打錯的字還在畫面上時，輸入法會在每按一個鍵之前核對欄位中是否是它打的內容。忽略替換位置的欄位無法收回打錯：在那裡第一處打錯會留下，最後的文字差一個字元（按 Esc 或其他鍵之後也一樣），而且這個 App 之後不再打錯。Settings → General 會在打錯開關下方列出這些 App；「Forget apps where typos couldn't be fixed」（忘記無法修正打錯的 App）讓它們再試一次。

### 依 App 設定（新）

Settings → Apps 可以為某個 App 提供自己的設定，每一項都是選擇性的；App 沒有設定的項目會沿用適用於所有 App 的設定：

| 設定 | 例如 | 設定檔中 |
| --- | --- | --- |
| 它的文字欄位一開始使用的輸入語言 | Slack 用英文，WeChat 用拼音 | `inputLanguage` |
| `@improve` 在那裡提供的改寫風格 | Mail 正式且委婉，Slack 口語 | `rewriteStyles` |
| 是否逐字輸入結果 | 聊天 App 中開啟，Mail 中關閉 | `typeOut` |
| 這個 App 中不使用 AI | `@improve`、`@translate`、`@question`、`@agent` 和你的提示詞指令在那裡不送出任何內容，並會提示；打字和其他指令照常運作 | `noAI` |
| 一律邊打邊譯 | WeChat 中一律使用邊打邊譯（見[邊打邊譯](#邊打邊譯)） | `translateAlways` |

「Add App…」（加入 App）會列出你最近打過字的 App，或在 /Applications 中挑選一個。輸入選單中的「This App: <名稱>」提供正在打字的 App 的快速開關（No AI、Type Results Out、一開始的語言）。設定檔中它們位於 `appProfiles` 之下，依 bundle ID 區分：`"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`。bundle ID 比對時不分大小寫（`com.apple.Mail` 就是 Mail 的 `com.apple.mail`）。`@reportissue` 只計算設定了內容的 App 數量，絕不寫出它們的名稱。

- 一開始的語言和預設輸入語言的運作方式一樣：文字欄位啟用時採用它，之後用 Shift 切換的語言會在該 App 的欄位中保持，直到設定改變為止。
- 開啟 No AI 時，AI 指令仍然留在 @ 清單中；執行時會顯示提示，並保留你寫的內容。你自己的終端機指令（`"type": "terminal"`）執行的是程式而不是 AI，所以在那裡照樣能用。

### Settings → Assistant（新）

設定視窗打開時會先顯示 **Assistant**，一頁分成兩部分（0.6.5 以前它們是 `@config` 和 `@doctor` 兩個指令）。

**用一句話修改設定**（「Change settings in a sentence」）：寫下你想怎麼改（「translate into Japanese and English」、「candidates in a column」、「use Claude」），按 Preview（或 ⌘⏎）。每項變更以原本 → 改為顯示；Apply 套用，Undo 在 10 分鐘內可以還原。它也能開關 iCloud 同步（要同步哪些項目只能在設定中選）。API 金鑰、自訂指令、外掛程式和任何會執行程式的東西在這裡都不會被修改；沒有金鑰的供應商會打開 Settings → AI Provider 中的金鑰欄位，更換供應商後會執行 Test Connection。這台 Mac 有 Apple Intelligence 時就用它，否則用你的供應商。

**檢查問題**（「Check for problems」）：頁面打開時會在這台 Mac 上檢查輸入法、AI 供應商、權限、安全輸入、語言包、`config.json`、擴充功能、更新、iCloud 同步（是否開啟、上次同步的時間、最後一次錯誤、iCloud 雲碟無法使用、來自 iCloud 的設定沒有在這裡使用）和最近的錯誤，問題在前（全都正常時顯示「Everything looks good」）。Check 會連同 Test Connection 再檢查一次；在「What's wrong? (optional)」中寫下問題的話，AI 會解釋可能的原因。可以修正的列有 Fix 按鈕：設定的變更會顯示在上方的預覽中，可以 Apply 和 Undo；其他的會立即執行（例如重新啟用輸入法、打開 System Settings 的某個面板，或拷貝要在 Terminal 中執行的指令）。

### 透過 iCloud 同步（新）

Settings → General → **Sync through iCloud**（透過 iCloud 同步，預設關閉）會透過你自己的 iCloud 雲碟，讓你所有 Mac 上的設定、Jargon 術語表、自訂指令和拼音學到的字詞保持一致：不必另外登入任何東西，也不經過我們的伺服器。它需要 iCloud 雲碟（System Settings → Apple Account → iCloud（系統設定 → Apple 帳號 → iCloud））；沒有的話，開關會保持關閉並說明原因，旁邊有按鈕可打開那個面板。

| 開關 | 同步的內容 | 預設 |
| --- | --- | --- |
| Settings（設定） | `config.json` 中的設定：語言、改寫風格、執行鍵、逐字輸入結果、依 App 設定、隱藏敏感資訊（它的開關）、AI 供應商和模型（絕不包含金鑰）… | 開啟 |
| Jargon and custom commands（Jargon 術語表和自訂指令） | 你的 Jargon 術語表和 `customCommands` | 開啟 |
| Learned words（學到的詞） | 拼音從你的選字中學到的字詞（Rime 的使用者詞典，透過 librime 的使用者詞典同步；你自己的 Rime 檔案，例如自訂短語，留在 Mac 上） | 開啟 |
| Hidden words（隱藏的詞） | 你對 AI 隱藏的字詞（「iCloud Drive is end-to-end encrypted only with Advanced Data Protection」：只有開啟「進階資料保護」時，iCloud 雲碟才是端對端加密） | 關閉 |
| Recent questions（最近的問題） | `@question` 最近的問題和答案（「Remember recent questions」開啟時） | 關閉 |
| API keys and passwords（API 金鑰和密碼） | 你的 API 金鑰和擴充功能的密碼，透過一律端對端加密的 iCloud 鑰匙圈同步（需要在 系統設定 → Apple 帳號 → iCloud 中開啟「密碼與鑰匙圈」） | 關閉 |

`iCloud Drive/AllInOneIME/settings.json` 保存每項設定，以及它在何時、在哪台 Mac（一個隨機 ID）上變更；每項設定以最新的變更為準：清單（你的自訂指令、改寫風格）算一個值，依 App 設定則逐個 App 處理，移除某個 App 的設定也算一次變更。同步的時機：輸入法啟動時、你變更設定約 5 秒後、iCloud 帶來另一台 Mac 的變更時（以及每 5 分鐘），以及按 **Sync Now**（立即同步）時；學到的字詞則在輸入法啟動時、每 30 分鐘（在打字暫停之後）和按 Sync Now 時同步。狀態那一行會顯示「Last synced 2 min ago」（2 分鐘前同步）、「Waiting for iCloud…」（正在等待 iCloud…）或錯誤。

- 開啟同步時，這台 Mac 會採用 iCloud 中已有的設定，它自己的設定只補上 iCloud 還沒有的部分。集合類的資料則會合併：最近的問題（兩邊的清單，最新的在前，同一個問題只留一次）、隱藏的字詞、自訂指令（依名稱；衝突時以 iCloud 的為準）和術語表的各行。底下的某個開關第一次開啟時也一樣。之後你在另一台 Mac 上拿掉的東西（刪除的自訂指令或隱藏的字詞）會保持刪除。以下情況它會回來一次，再刪一次就不會再回來：它來自第一台開啟同步的 Mac，而另一台 Mac 合併它的清單時那台 Mac 正在睡眠；它是在仍使用 0.6.4 的 Mac 上刪除的；或是仍使用 0.6.4 的 Mac 把它帶了回來。Mac 正在開啟同步時於設定中儲存的設定會保留，並送到其他 Mac。
- 關閉後再開啟：iCloud 在這段期間的變更會進來（這台 Mac 也改過的項目也一樣），只有這台 Mac 改過的會上傳，這段期間有新增內容的集合會合併，絕不會被捨棄。
- 兩台 Mac 的最近問題會合併；在一台 Mac 上按「Clear」，其他 Mac 上在那之前提出的問題也會一併清除。關閉「Remember recent questions」只會刪除那台 Mac 上的問題，再次開啟時，其他 Mac 的問題會回到它上面。Mac 沒有同步最近的問題（或沒有記住它們）時按的 Clear，只影響那台 Mac。
- 關閉「Hidden words」或「Recent questions」時，已同步的內容會留在 iCloud：每個開關下方的 **Remove from iCloud…**（從 iCloud 移除…，會先詢問）會把它們移除；其他 Mac 會保留自己的，仍在同步它們的 Mac 會把自己的放回去。
- 來自另一台 Mac、但這台無法使用的值（這裡沒有金鑰的供應商、這台沒有的 AWS 設定檔、超出範圍的值）不會套用：狀態那一行和 Settings → Assistant 的檢查問題會說明是哪些。
- iCloud 還沒下載的檔案會等它下載，絕不當作空的；無法讀取的 `settings.json` 會改名為 `settings (unreadable …).json` 放在一旁，絕不覆寫。較新版本的設定會原樣保留。
- API 金鑰和密碼透過 iCloud 鑰匙圈同步，而不是 iCloud 雲碟：「API keys and passwords」開啟時（同步也要開啟），在一台 Mac 上儲存或取代的金鑰，其他 Mac 上也會有。它預設關閉：只開啟同步不會移動任何金鑰，要等你開啟這一列才會移動。開啟時，這台 Mac 的金鑰會從登入鑰匙圈移到 iCloud 鑰匙圈（之後更新時，macOS 就不會再為它們詢問你的登入密碼）；關閉時，金鑰會拷貝回登入鑰匙圈，iCloud 鑰匙圈中的仍留給你的其他 Mac。不同步的金鑰和以前一樣留在登入鑰匙圈中，AllInOneIME Cloud 的登入也是，它絕不同步：每台 Mac 各自登入。兩台 Mac 的金鑰不同時，以最後儲存的為準（依儲存的時間，每份拷貝都會記下）。另一把不會被刪除：它會以「被取代的拷貝」留在它那台 Mac 的登入鑰匙圈中（在「AllInOneIME replaced API key」之下，名稱以「(replaced)」結尾），絕不會被使用。移到 iCloud 鑰匙圈的金鑰也會留一份這樣的拷貝，以防另一台 Mac 上不同的金鑰蓋過它。每台 Mac 上每把金鑰只有一份被取代的拷貝：較新的會取代它。在金鑰同步時移除某把金鑰，會把它從每台同步金鑰的 Mac 上移除（詢問中寫的是「all your Macs」：你所有的 Mac），連同這台 Mac 上被取代的拷貝；關閉「API keys and passwords」的 Mac，或仍使用 0.6.4 的 Mac，會保留自己的那份，日後那台 Mac 開啟金鑰同步時會把它放回去（詢問中也會說明）。在關閉這項同步的 Mac 上，Remove… 只會從那台 Mac 移除金鑰和它被取代的拷貝（詢問中寫的是「this Mac」：這台 Mac），iCloud 鑰匙圈中的拷貝仍留給你的其他 Mac。移動時，如果 macOS 要你的登入密碼才讓 AllInOneIME 讀取某把金鑰，那把金鑰會留在登入鑰匙圈中，直到下次使用：那時 macOS 若詢問而你允許了，它就會再次被使用，即使它已在另一台 Mac 上被移除。每把金鑰仍然只會送往儲存時對應的主機。金鑰同步期間，`allinoneime-cli` 和 0.6.5 以前的版本在鑰匙圈中看不到它們。沒有佈建描述檔的版本（開發版本）會把金鑰留在登入鑰匙圈中，無法同步：這一列會說明。
- 絕不同步：AllInOneIME Cloud 的登入、AWS 憑證（在 `~/.aws` 中）、擴充功能來源（它們會執行程式碼：由每台 Mac 自己決定）、擴充功能資料夾和外掛程式（每台 Mac 上的路徑）、不再打錯的 App 和最近的 App、視窗狀態，以及同步開關本身（每台 Mac 各自設定）。
- 關閉同步會停止同步，並讓這台 Mac 和 iCloud 上的一切都保持原樣；**Remove from iCloud…**（會先詢問）會把資料夾移到垃圾桶，並關閉這台 Mac 的同步。
- Settings → Assistant（「sync through iCloud」）可以開關同步；隱藏的字詞和最近的問題只能在 Settings → General 中選擇。設定檔中為 `iCloudSync`（`enabled`、`settings`、`jargon`、`learnedWords`、`hiddenWords`、`recentQuestions`、`keys`）。

## 選單列面板

<img src="../en/panel-swipe.png" width="520" alt="選單列面板：毛玻璃質感，備忘錄、提醒事項和 Claude 任務顯示在卡片上；向左滑動的一列顯示出「Remove」按鈕">

按一下選單列中的 AllInOneIME 圖像（∞ 加游標的標誌，沒有外框；有外框的那個是輸入方式），面板就會在它下方展開；按一下其他地方即可關閉：

- Notes（備忘錄）：用 `@note` 儲存的備忘錄，最新的 5 則；按一下即可在它存放的地方開啟：Notes、Obsidian 或該檔案的預設 App，或 Notion 頁面。已經不存在的檔案不再列出。
- Reminders（提醒事項）：Reminders 中 AllInOneIME 列表裡尚未完成的提醒事項（`@reminder` 就是加到這個列表），最快到期的排在前面，顯示 8 則；按一下圓圈即可勾選完成，按一下標題則開啟 Reminders。
- Claude Tasks（Claude 任務）：和 `@tasks` 一樣，是背景中的 Claude 任務（`@agent` 交給 Claude Code 的工作），最多 30 個，一次顯示 5 個：捲動可看更多，或在搜尋框中搜尋它們的標題和回覆；附有進度，以及最後一則回覆的第一行；按一下即可在 Terminal 中開啟並繼續。

用兩指把某一列（備忘錄、提醒事項或任務）向左滑動，會顯示它的「Remove」（移除）按鈕，一路滑到底則直接移除；使用滑鼠時，按右鍵即可。移除只會把它從面板上拿掉：備忘錄仍留在 Notes 中，提醒事項仍在 Reminders 中（不會標為完成），任務仍在 Claude Code 中。

標題列顯示數量（例如「2 reminders · 1 task running」；等你回應的任務另外計算，例如「1 waiting for you」）和一個重新整理按鈕。它絕不會搶走你正在輸入的 App 的焦點：勾選提醒事項或重新整理時，那個 App 仍留在最前面；只有 Claude 任務的搜尋框在被按一下之後，才會接收鍵盤輸入。圖像預設會顯示；可在設定的「Menu Bar Panel」（選單列面板）下關閉。

它讀取什麼、何時讀取：

- Notes：清單是面板自己的紀錄（面板關閉時也會保留），而且絕不會啟動 Notes：只有在 Notes 已經在執行、且 AllInOneIME 先前已獲准控制它時，面板才會檢查其中被修改的標題和被刪除的備忘錄。
- Reminders：面板展開時、每 60 秒，以及提醒事項變更時，會讀取 AllInOneIME 列表。面板絕不會自行讓 macOS 要求存取權限：如果 macOS 還沒問過你，它會顯示「Allow Access to Reminders」（允許取用提醒事項），只有按下這個按鈕才會詢問；如果你拒絕了，它會顯示「Open System Settings」（打開系統設定）。
- Claude 任務：面板只在展開時執行 `claude agents`：展開時一次、按重新整理時、`@agent` 交出任務時；以及有任務尚未完成時每 15 秒一次，全部完成後就不再執行。最後的回覆讀取自這台 Mac 上 Claude Code 的對話紀錄結尾（`~/.claude/projects`），而且只在對話紀錄有變更時才讀取。
- 面板關閉時，以上都不會執行；它只會記錄 `@note` 儲存的備忘錄。

## 輸入與翻譯

在設定中：

- **Input languages**（輸入語言）：從英文、中文（拼音）、法文、韓文和印地文中選一到五種，用 + 加入（一直都在；滿五種時變成灰色）。新安裝時只有英文。新的文字欄位從第一種開始；輕按 Shift 依序切換到下一種；只有一種時，Shift 不會切換。
  - **法文**以它自己的鍵盤配置輸入：除非你在它的卡片上選了其他配置，否則為 AZERTY。它的靜音鍵（^、¨、`、´、~）也會由它組字。
  - **韓文**以兩套式（Dubeolsik）配置輸入諺文，邊打邊組合每個音節（g k s → 한）；Shift 可輸入 ㄲ ㄸ ㅃ ㅆ ㅉ 和 ㅒ ㅖ。
  - **印地文**：用拉丁字母照發音輸入單字，就會得到天城文（namaste → नमस्ते）。常用字會照印地文的寫法拼出；其他情況下，Space 插入第一個拼法，數字鍵插入其他拼法，⏎ 插入照打的字母，「.」則是句號 danda（।）。
  - 無論是哪種語言，指令名稱、`@open` 的文字和程式碼（`@py`、`@js`）都以字母輸入；指令結束後會切回原本的語言。
  - `@improve` 會讓韓文、印地文或法文的句子維持原本的語言，`@translate` 則把它翻譯成你的語言（當法文是你的輸入語言之一時，會把法文和英文區分開來）。
- **Language packs**（語言包）：App 內建英文（以及法文，法文只需要 macOS 的鍵盤配置）。中文、韓文和印地文是加入時才下載的語言包：加入中文（拼音）時會下載它的詞庫（約 34 MB，解壓縮後 125 MB）並顯示進度列，下載完成後拼音立即可用，不需要重新啟動；韓文的語言包（它的按鍵表，以及字母如何組成音節）和印地文的語言包（它的字母和常用字）只有幾 KB。語言包只包含資料（詞庫、表格和綱要，絕無程式碼），列在經過簽署的索引中，使用前會核對 SHA-256，和外掛程式一樣。每種語言的卡片會顯示它的語言包（版本、大小、來源），並附有「Delete…」（刪除…）；移除語言時會詢問是否一併刪除它的語言包。從 0.6.1 或更早版本更新時，中文不需要下載：安裝程式會保留舊版本附帶的詞庫。
- **候選排列**：選字時，拼音和印地文的候選字詞預設橫向並排（Horizontal），就像系統內建的輸入法：← → 選取，↑↓（或 - =）翻頁。想要上下排列（↑↓ 選取），請在 Input 頁面、輸入語言下方選擇 Vertical。@ 指令清單和結果一律直向排列。
- **Fuzzy pinyin**（模糊拼音，搭配中文輸入）：你分不清的音，兩種打法都可以，例如 z ↔ zh、n ↔ l、in ↔ ing。在「Input」（輸入）頁面的輸入語言列中選擇中文（拼音），開啟「Fuzzy pinyin」並選擇要配對的音；詞庫會在一兩秒內重新部署。它會在 Rime 使用者資料夾中寫入 `rime_ice.custom.yaml`，而且絕不會覆寫你自己放在那裡的檔案。
- **Personal Dictionaries**（個人詞庫，搭配中文輸入）：Settings → Input → Chinese (pinyin) → Personal Dictionaries → **Import or Update…**（匯入或更新），可以把 UTF-8 的 Rime 詞庫（`.dict.yaml`）加在 rime-ice 之外（需要先裝好中文語言包）。列表顯示每個詞庫的 Rime `name`、原檔名和詞條數；再次匯入相同 `name` 會更新已存的副本（只修改原檔不會更新）。每次匯入、更新或移除都會重新編譯拼音詞庫（rime-ice 的全部詞條加上你的），可能要一分鐘左右，這段期間暫時打不了中文，頁面會顯示進度或錯誤。副本只留在這台 Mac 上，不透過 iCloud 同步，也不會發給 AI；不過從詞庫裡選過的詞和別的詞一樣會學進 Rime 的使用者詞典，開了學到的詞的同步時會同步到你的其他 Mac，移除詞庫後也還在。如果有你自己的 `rime_ice.custom.yaml`，會在改動任何檔案之前拒絕匯入。
- **Translate (@translate)**（翻譯）：加入要翻譯成的語言（西班牙文、法文、德文、日文、韓文、中文、印地文、孟加拉文、坦米爾文及其他主要印度語言…），並拖曳排序。以拉丁字母輸入的印地文（「aap kaise ho」）會以天城文傳回。`@translate` 依這個順序，每種語言寫一行（只有一種時提供三個版本）；句子本身的語言會略過。新安裝時，會翻譯成 Mac 偏好語言中第一個不是英文的語言；如果只有英文，`@translate` 會提示還沒有要翻譯成的語言，在提示上按 ⏎ 會開啟這個頁面，「Add…」（加入…）加上外框標示（句子照輸入的原樣插入）。這時邊打邊譯也不會開啟，並提示要到哪裡加入語言。
- **Keyboard layouts**（鍵盤配置）：法文以它卡片上選擇的配置輸入（設定檔中的 `keyboardLayouts`）。其他語言在輸入法之下，macOS 會沿用你最後使用的拉丁字母配置（AZERTY、QWERTZ、西班牙文、美式國際…），所以你可以照常打字，`@` 也在你的配置原本的位置，靜音鍵在指令的文字中同樣能組字（⌥E 再按 E → é，^ 再按 e → ê）。沒有拉丁字母的配置（俄文、印地文 InScript）無法在輸入法之下使用：請用 ⌃Space 切換過去，或把文字貼上（⌃V）到指令中。
- `@improve` 只潤飾和改寫，不翻譯；`@translate @improve` 一起使用時，一次請求就能翻譯並改寫。在設定中開啟「@improve also translates」，`@improve` 就會一律這樣做。

個人詞庫的格式像這樣（每個詞條的欄位用 **Tab** 分隔）：

```yaml
---
name: my_vocabulary
version: "1"
columns: [text, code, weight]
...
星河项目	xing he xiang mu	100
蓝杉团队	lan shan tuan dui	200
```

拼音用小寫拉丁字母，音節之間用空格，`ü` 寫作 `v`；權重（weight）可以省略（非負數）。沒有 `columns` 時順序是 `text`、`code`、`weight`。`name` 只能包含拉丁字母、數字、`-`、`_` 和 `.`；檔案最多 32 MiB。依賴 `import_tables` 或沒有拼音編碼的檔案會被拒絕，什麼都不改。

## 改寫風格

第 1–3 行之後是改寫，**使用你輸入時的語言**：英文得到英文的改寫，中文得到中文的改寫。可在設定中任意挑選：

- Polish（潤飾）：語氣不變，更自然
- Concise（精簡）
- Formal（正式）：給主管和客戶
- Casual（輕鬆）
- Tactful（委婉）
- Jargon（行話）：英文是 Amazon 式說法（bandwidth、circle back…），中文是大型科技公司的行話。壞消息會被輕描淡寫，例如「this is a blocker bug」（這是個阻斷性錯誤）→「Oh! Looks like your team has the bandwidth to fix this minor issue!」（喔！看來你們團隊有餘力修好這個小問題！）

只改了標點，或與其他行重複的改寫不會顯示。

### Jargon 術語表（你自己的術語）

Jargon 沒有內建的術語表。你可以準備自己的術語表（例如你團隊常用的說法），模型會優先使用其中的術語。在候選中，Jargon 那一行會註明它用到的術語是什麼意思。

術語表是一個文字檔，每行一個術語，後面可以加上它的意思，用「=」、冒號或 Tab 分隔（你可以從試算表拷貝兩欄後貼上）。以 `#` 開頭的行是註解：

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

在設定的「Rewrite Styles → Jargon list」（改寫風格 → Jargon 術語表）下，按一下「New」（新增）會在 `~/.config/allinoneime/jargon.txt` 建立一個空的術語表並開啟它；如果你已經有術語表檔案，按一下「Choose File…」（選擇檔案…）即可在原處使用它（設定檔中的 `jargonFile`）。變更會立即生效。只會讀取前 150 個術語。勾選「Jargon」時，術語表會隨每次請求一起送到 Bedrock。

<img src="../en/panel-dark.png" width="420" alt="深色模式下的候選視窗">

## 邊打邊譯

這是一個原型，歡迎試用。單獨按住 Shift 1 秒即可開啟（或關閉）「Translate as You Type」（邊打邊譯）；快速輕按 Shift 仍是切換輸入語言。按住 0.5 秒時，游標附近會提示「Keep holding → Translate as You Type」（繼續按住 → 邊打邊譯），到 1 秒時會顯示「Translate as You Type on: Chinese → English · hold Shift again to turn off」（邊打邊譯已開啟：中文 → 英文 · 再次長按 Shift 即可關閉；其中寫的是要翻譯成的語言）約 1.5 秒作為確認（關閉時則是「Keep holding → Translate as You Type off」，然後是「Translate as You Type off」）；在那之前放開就不會有任何改變。Shift 搭配字母（大寫）或其他按鍵絕不會開啟它。開啟期間，選單列圖像會帶一個小圓點。它沒有對應的指令。

開啟期間，你輸入的內容會先集中成一份草稿，旁邊的小標籤標出語言（「ZH → EN」；中文介面為「中 → 英」）。它會翻譯成你最後一次在小標籤上選的語言（見下文），在每個 App 中、重新啟動後都一樣；在你選擇之前，則翻譯成設定中的第一種翻譯語言（所選的語言不再是翻譯語言之一時，也會回到那一種）。只用一種輸入語言時會跳過它（只打英文、翻譯語言依序是英文和法文時，翻譯成法文）。開啟時你正在輸入哪種語言不影響它。按 ⏎ 會翻譯草稿，譯文立即插入，不必挑選候選：翻譯期間草稿顯示「Translating…」（正在翻譯…），插入後也不會替你送出（再按一次 ⏎ 才是 App 自己的 Return）。⇧⏎ 照草稿原樣插入；翻譯進行中按 Esc 會停止翻譯並保留草稿（按 ⌫ 也會停止，並和在草稿上一樣刪掉一個字元）；失敗時（網路問題、被拒絕、安全輸入），草稿會保留並附上一行通知，按 ⏎ 再試一次。以要翻譯成的語言輸入的文字（輕按 Shift 切到英文）會照輸入的原樣插入。

開啟期間，小標籤「ZH → EN」（中文介面為「中 → 英」）會顯示在你正在輸入的那一行下方，位於輸入法自己的面板中（也就是候選視窗：輸入拼音時在候選字詞上方），所以絕不會搶走 App 的焦點。按一下「ZH」會切換輸入語言，和輕按 Shift 一樣。按一下「EN」會列出你的翻譯語言，目前的那一種打勾；按一下其中一種，它就立即成為要翻譯成的語言（小標籤和下一次翻譯隨之改變），之後也一直沿用。按鍵照常運作；按任一個鍵都會關閉清單。

- **語氣**：依 App 而定：Settings → Apps 中該 App 的第一種改寫風格；沒有的話，聊天 App（WeChat、Slack、Messages、Telegram、Discord、Teams）用口語，郵件 App（Mail、Outlook、Spark）用正式語氣，其他地方則用自然的語氣。
- **App**：切換到其他 App（包括沒有文字欄位的 App）會關閉它，不另行通知，回來時也保持關閉；除非那個 App 在 Settings → Apps 中開啟了「Always Translate as You Type」（一律邊打邊譯；設定檔中該 App 的 `translateAlways`）：在那裡它會自動開啟。在設為 No AI 的 App 中它不起作用：文字照輸入的原樣插入，並顯示通知；處於安全輸入狀態時（密碼欄位）輸入的內容也一樣。
- **隱私**：和 `@translate` 一樣：只在你按 ⏎ 時才送到你自己的 AI 供應商；開啟隱藏敏感資訊時，敏感資訊會先隱藏。

## 安裝

執行需要 macOS 14 或更新版本。安裝程式是通用版本：可在搭載 Apple 晶片和 Intel 的 Mac 上執行。目前只在搭載 Apple 晶片的 macOS 27 上測試過（Intel 版本只在 Rosetta 下通過了自我測試）。

1. 從 [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) 下載 `AllInOneIME-<version>.dmg`（只從那裡下載）並打開它。
2. 按兩下其中的「Install AllInOneIME」，再按一下「Install」（安裝）。輸入法會安裝到 `~/Library/Input Methods`，「AllInOneIME Settings」則安裝到 `~/Applications`。只為目前的使用者安裝；不需要管理者密碼。
3. 安裝程式以 Developer ID 簽署並經過 Apple 公證，所以第一次時 macOS 只會詢問是否要打開從網際網路下載的 App：按一下「打開」。（0.6.3 之前的版本沒有公證：每個版本都要在 系統設定 → 隱私權與安全性 → 強制打開 中允許一次。）

完成後，AllInOneIME 就已啟用並出現在你的輸入方式中；用 Ctrl+Space 切換到它（只有在 System Settings → Keyboard（系統設定 → 鍵盤）中把「Press 🌐 key to」設為「Change Input Source」時，🌐 鍵才會切換）。如果安裝程式要你手動加入，代表這台 Mac 不允許程式啟用它，請自己加入一次：System Settings → Keyboard → Text Input → Input Sources → Edit… → +（左下角）→ English → AllInOneIME（在它設定的「Input」下加入中文後，它也能輸入拼音）。

如果用 Ctrl+Space 切換不到 AllInOneIME，或過一陣子又切回 U.S.，請再執行一次安裝程式：它會把 AllInOneIME 重新加回你的輸入方式。

更新：Settings → About → Check for Updates（檢查更新）。有新版本時，About 會告訴你（選單列面板中也有一行），並附上新功能；「Update to <version>」（更新到 <版本>）會下載它、以 AllInOneIME 發佈金鑰簽署的更新資訊核對、安裝，然後重新啟動輸入法。你的設定、語言包、學到的字詞和擴充功能都會保留，若中途出錯，會換回你原本的版本。AllInOneIME 每天會在背景自行檢查一次（可在 About 中用「Check for updates automatically」關閉）；你沒按下之前不會安裝任何東西。此功能從 0.6.3 起才有；要更新更舊的版本，或者你偏好這樣做，請直接把新版本的磁碟映像檔安裝在上面，不必先解除安裝。升級前請先閱讀[更新日誌](../../CHANGELOG.md)：其中有每個版本的變更和升級須知。

從較舊的版本更新到 0.6.3：0.6.3 是第一個以 Developer ID 簽署的版本，所以鑰匙圈還認不出它就是當初儲存你金鑰的那個 App。它第一次用到自己儲存的每把金鑰時（API 金鑰、AllInOneIME Cloud 的登入、擴充功能的密碼），macOS 會詢問你的登入密碼：輸入後按一下「Always Allow」（永遠允許）。之後不會再詢問，以後更新也不會。Amazon Bedrock 的金鑰在 `~/.aws/credentials` 中，不受影響。輔助使用（系統設定 → 隱私權與安全性 → 輔助使用）是貼到終端機和讀取選取文字時要用的，也需要一個步驟：如果 AllInOneIME 在列表中，請先移除，等系統詢問時再重新開啟。

如果你裝過 AIPinyin（AllInOneIME 先前的名稱），直接安裝即可：舊的 AIPinyin.app 及其設定啟動器會被移除，輸入方式中的項目會換成新名稱，不需要重新加入。設定、Jargon 術語表和學到的詞會在第一次啟動時移到新的資料夾（`~/.config/allinoneime` 等），每個舊資料夾都會留下一個指向新資料夾的連結。

解除安裝時，打開「Install AllInOneIME」並按一下「Uninstall…」（解除安裝…）。設定和學到的詞會保留。

### 從原始碼建置

建置需要 Xcode 26 或更新版本（macOS 26 SDK）。

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` 會下載並驗證 librime 和 rime-ice 詞庫，進行建置，並安裝到相同的位置，同樣把它加入你的輸入方式。它安裝的 App 不含中文詞庫（詞庫屬於中文語言包）：原本裝有詞庫的安裝會把它們保留為語言包；否則 `make install-pack` 會從原始碼中的詞庫安裝語言包，不需要下載。`make status` 會顯示已安裝的版本（`version:`），以及它是否在你的輸入方式中（`listed:`）。解除安裝：`make uninstall`。

## 設定 AI

翻譯和改寫會送到你在 Settings → AI Provider 中選擇的 AI 供應商。新安裝時預設使用 AllInOneIME Cloud：登入即可，每天有 20 次免費請求。在支援 Apple Intelligence 的 Mac 上，也可以改在這台 Mac 上執行，不需要帳號（見下方「這台 Mac 上的 Apple Intelligence」）。也可以使用你自己的供應商，費用由你的帳號支付：你 AWS 帳號中的 Amazon Bedrock、Claude API、Gemini 或與 OpenAI 相容的服務（見下方「其他 AI 供應商」）。

### Amazon Bedrock

1. 在 AWS 主控台中啟用 Bedrock，並確認你能使用選定的模型。預設是 Claude Haiku 4.5；第一次使用 Anthropic 的模型時，需要填寫一次使用案例表單。
2. 使用一個允許 `bedrock:InvokeModelWithResponseStream` 的 AWS 設定檔（profile）：`~/.aws/credentials` 中的靜態金鑰，或能取得臨時憑證的設定檔（`credential_process`、角色、SSO；見下方的「AWS 設定檔」）。
3. 打開「AllInOneIME Settings」：你可以在 Spotlight 或「應用程式」中找到它，或從選單列中輸入法的圖像 →「Settings…」（設定…）打開。選擇設定檔、區域和模型，然後按一下「Test Connection」（測試連線）。介面提供 English、简体中文（簡體中文）、繁體中文、日本語、한국어、Deutsch、Français、Español 和 Português (Brasil)。預設（Settings → General →「Interface language」（介面語言）中的「Follow the system」（跟隨系統））會依照系統的偏好語言（System Settings → General → Language & Region（系統設定 → 一般 → 語言與地區））：採用其中第一個 App 支援的語言，同一語言的其他地區也算（de-AT 用 Deutsch，es-MX 用 Español，fr-CA 用 Français）；zh-Hant、zh-TW 和 zh-HK 用繁體中文，其他中文用簡體中文，葡萄牙的葡萄牙文也用巴西葡萄牙文（在那裡讀起來比英文順），都沒有時用英文。也可以在那裡直接選擇其中一種，每種都以它自己的語言列出。設定視窗、候選視窗中的提示和輸入選單都會跟隨這項設定。設定視窗打開時會先顯示 Assistant 頁面：用描述的方式修改設定，以及檢查問題，每個問題都附有 Fix（見 [Settings → Assistant](#settings--assistant新)）。

<img src="../en/settings.png" width="420" alt="設定視窗">

#### AWS 設定檔

只要是 AWS CLI 不必詢問你就能使用的設定檔都可以，來自 `~/.aws/config` 和 `~/.aws/credentials`（或 shell 中 `AWS_CONFIG_FILE` 和 `AWS_SHARED_CREDENTIALS_FILE` 指定的檔案）。在一個設定檔中，會依 AWS CLI 的順序使用它所具備的第一種來源（同時有 `role_arn` 和金鑰的設定檔算作角色）：

| 種類 | 設定檔中的內容 | 何時更新 |
| --- | --- | --- |
| 角色 | `role_arn` 加上 `source_profile`（這裡可以是任何一種，也可以串接；指向自己的設定檔使用它自己的金鑰）或 `credential_source = Environment`；`role_session_name`、`external_id`、`duration_seconds` | 到期前 5 分鐘再次呼叫 STS `AssumeRole`（在設定檔的 `region`，沒有則為 us-east-1） |
| SSO | `sso_account_id`、`sso_role_name` 加上 `sso_session` 及其 `[sso-session …]` 區段（或舊式的 `sso_start_url`、`sso_region`） | 到期前 5 分鐘用你快取的登入再取一次 |
| 靜態金鑰 | `~/.aws/credentials` 中的 `aws_access_key_id`、`aws_secret_access_key`（以及 `aws_session_token`） | 每次請求都重新讀取 |
| `credential_process` | `credential_process = /usr/local/bin/my-creds --profile dev`（像 shell 指令一樣拆開，但不透過 shell 執行；使用登入 shell 的 PATH，在你的個人專屬資料夾中，最多 60 秒） | 在它給的 `Expiration` 前 5 分鐘再次執行；沒有到期時間時，則在 AWS 拒絕憑證時再執行 |
| 靜態金鑰 | `~/.aws/config` 中同樣的金鑰 | 每次請求都重新讀取 |

設定檔為「default」（或未選擇）時，會和 AWS CLI 一樣優先使用 shell 中的金鑰：`AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY` 和 `AWS_SESSION_TOKEN`。你指定名稱的設定檔絕不會和它們混用。shell 中的 `AWS_REGION`（或 `AWS_DEFAULT_REGION`）和 AWS CLI 一樣優先於設定檔的 `region`；設定中的「Region」欄位又優先於這兩者。

- **自動：** 會過期的憑證只保存在記憶體中（絕不寫入磁碟），並在到期前 5 分鐘重新取得；剩下不到 10 分鐘時，請求會先使用現有的憑證，同時在背景取得新的，所以打字不必等待。同時發出的請求只會等待同一次取得。Bedrock 回應憑證已過期（`ExpiredTokenException` 等）時，會重新取得憑證並再送出一次請求，只重試一次。
- **SSO：** AllInOneIME 使用 AWS CLI 存放在 `~/.aws/sso/cache` 中的登入（只讀取），無法替你登入，因為那需要瀏覽器。登入過期時，候選視窗會顯示「SSO sign-in expired: run aws sso login --profile X」（SSO 登入已過期：請執行 aws sso login --profile X）：在 Terminal 中執行它（設定中有「Copy Command」和「Open in Terminal」；Settings → Assistant 也會提供可拷貝的指令），之後 AllInOneIME 會自動使用新的登入。
- **不支援：** `mfa_serial`（輸入法無法向你要 MFA 驗證碼：請改用 `credential_process` 或 SSO，或讓你的 CLI 快取憑證）、`credential_source = Ec2InstanceMetadata` 或 `EcsContainer`（Mac 上沒有），以及 web identity。
- **已知限制：** 只有 PATH 和 AWS 檔案的變數（`AWS_CONFIG_FILE`、`AWS_SHARED_CREDENTIALS_FILE`）來自你的登入 shell，`credential_process` 也一樣（不帶入其他環境變數）。AllInOneIME 不會續期 `sso_session` 的權杖（不使用 CLI 的 refresh token：SSO 快取只讀不寫），所以快取的權杖過期後，請執行 `aws sso login`（平常使用 AWS CLI 時它也會自動續期）。
- **Settings → AI Provider** 會列出每個設定檔及其種類（「dev — Role via base」），並說明所選設定檔的憑證何時到期（「Role via base: credentials expire at 15:30」、「SSO (signed in until 18:00)」）或該怎麼做。Test Connection 會沿著整條鏈取得新的憑證；Settings → Assistant 也會回報同樣的內容。
- 只有在請求或 Test Connection 需要憑證時，才會執行程式、向 AWS 要求憑證（`sts.<region>.amazonaws.com`、`portal.sso.<region>.amazonaws.com`）：列出設定檔時絕不會，Settings → Assistant 也絕不會。

### 其他 AI 供應商：Claude API、Gemini、與 OpenAI 相容的服務

你不需要 AWS：在設定的「AI Provider」（AI 供應商）下選一個，貼上 API 金鑰，按一下「Save」（儲存），再按「Test Connection」。

| 供應商 | 預設模型 | API 金鑰 |
|---|---|---|
| Claude API | `claude-haiku-5-5`（最快、最便宜；Sonnet 5.5 和 Opus 5.5 較周到，但較慢也較貴） | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| 與 OpenAI 相容 | OpenAI 的 `gpt-6-luna`（或 `gpt-5.4-mini`）；「Common Services…」（常用服務…）中有 DeepSeek、Qwen、Kimi、Zhipu GLM、SiliconFlow、OpenRouter，以及這台 Mac 上的 Ollama：選擇其中一個會填入它的 Base URL，再輸入它的模型 | 該服務的金鑰；把 Base URL 設為它的位址，例如 `https://api.deepseek.com/v1`，或這台 Mac 上 Ollama 的 `http://localhost:11434/v1` |

- API 金鑰保存在登入鑰匙圈中，絕不會寫進設定檔；如果你在「透過 iCloud 同步」下開啟「API keys and passwords」，則改為保存在 iCloud 鑰匙圈中，`allinoneime-cli` 和 0.6.5 以前的版本在那裡看不到它們。鑰匙圈中沒有金鑰時，會使用你 shell 中的 `ANTHROPIC_API_KEY`、`GEMINI_API_KEY`（或 `GOOGLE_API_KEY`）和 `OPENAI_API_KEY`。
- API 金鑰那一列會顯示是否已設定金鑰：「✓ Saved · ends in a1b2」（已儲存 · 結尾為 a1b2：最後 4 個字元，儲存金鑰時一併記下，顯示時不必讀取金鑰本身），旁邊有「Replace…」（取代）和「Remove…」（移除）；來自 shell 的顯示「✓ From $OPENAI_API_KEY」（來自 $OPENAI_API_KEY）；沒有的話顯示「No API key yet」（尚未設定 API 金鑰），並直接提供貼上的欄位。
- 「Thinking」（思考）預設為低：輸入法每一句都要等待，思考越少越快。不支援這項設定的模型請選擇「Not set」（未設定）。
- 選擇 Claude Opus 5.5 或 Sonnet 5.5 時，請求會帶有 Claude API 的拒絕備援（`fallbacks: "default"`）：安全分類器拒絕時，伺服器會改用另一個模型重試。
- 設定檔中：`provider`（`"bedrock"`、`"anthropic"`、`"gemini"`、`"openai"`），以及 `anthropic`、`gemini` 和 `openai` 下的 `model`、`baseURL`、`effort` 和 `temperature`（未設定的使用預設值）。

### 這台 Mac 上的 Apple Intelligence（macOS 26）

在支援 Apple Intelligence 的 Mac 上（Apple 晶片、macOS 26 或以上，並已在 系統設定 → Apple Intelligence 與 Siri 中開啟），在「AI Provider」中選擇「Apple Intelligence (on this Mac)」：不需金鑰、不花錢，而且你輸入的內容不會離開這台 Mac。它使用 macOS 內建的模型（Foundation Models 框架），指令和回答格式與其他供應商相同，但只附上以句子本身語言撰寫的範例（小模型太容易照著範例的語言回答）。

- 它是小模型：上下文約 4K tokens（macOS 27 上為 8K），所以太長的段落可能放不下，支援的語言也較少（英文、中文、日文、韓文、法文、德文、西班牙文和另外幾種；不支援印地文）。遇到這兩種情況時它會直接說明。它的結果不如雲端模型，`@question` 對事實和程式碼的回答也常常出錯。
- 無法使用時，它在清單中顯示為灰色並附上原因（這台 Mac 不支援、未開啟、模型尚未就緒），設定中有連結可前往 系統設定 → Apple Intelligence 與 Siri。macOS 26 之前不會列出。
- 「Model Settings」中的「Output tokens」、temperature 和逾時都適用於它。設定檔中為 `"provider": "apple"`。

### 隱藏敏感資訊（新）

Settings → AI Provider → Privacy →「Hide sensitive information before sending」（傳送前隱藏敏感資訊，預設關閉）：請求送給 AI 之前，它在你的文字中找到的內容會先在 Mac 上換成 `[EMAIL_1]` 這類預留位置（同一個值用同一個預留位置），結果在顯示或插入之前會換回真實內容。候選視窗會顯示「2 items hidden from the AI」（已對 AI 隱藏 2 項）。每一類都能個別關閉：

| 類別 | 例如 | 設定檔中 |
| --- | --- | --- |
| 電子郵件地址 | `bob@example.com` | `emails` |
| 電話號碼 | `+1 (555) 123-4567`、`138 0013 8000` | `phones` |
| 付款卡號（經 Luhn 檢查） | `4111 1111 1111 1111` | `cards` |
| API 金鑰和權杖 | `sk-` 或 `ghp_` 這類已知前綴、很長的隨機字串 | `keys` |
| IP 位址 | `203.0.113.42`、`2001:db8::1` | `ips` |
| 你自己的字詞，不分大小寫 | 像 `Project Atlas` 這樣的代號、一個名字 | `customWords` |

- 它適用於 `@improve`、`@translate`、`@question`、你的提示詞指令和提示詞外掛程式，以及修改它們的結果（使用同樣的預留位置），所有供應商都一樣，包括 AllInOneIME Cloud 和 Apple Intelligence。術語表中含有要隱藏內容的項目不會送出。
- 它能辨識有固定格式的值；無法辨識人名或地址，請把它們加為你自己的字詞。`@agent`、從網站擷取資料（`@stock`）或開啟網站（`@x`）的外掛程式，以及腳本擴充功能，會照原樣送出文字。詳見「隱私」。
- 設定檔中：`"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`。

所有設定都存放在 `~/.config/allinoneime/config.json`；變更後，下一次翻譯就會使用新設定，不需要重新啟動。較新的鍵：

| 鍵 | 作用 | 預設值 |
|---|---|---|
| `inputLanguages` | 輸入語言，一到五種，第一種是預設：`"en"` 英文、`"zh"` 中文（拼音）、`"fr"` 法文、`"ko"` 韓文、`"hi"` 印地文，例如 `["en", "zh"]`、`["fr", "en", "ko"]`。中文、韓文和印地文要在安裝語言包後才能使用 | `["en"]`（新安裝） |
| `keyboardLayouts` | 輸入語言所用的鍵盤配置，以語言代碼指定（目前只有法文）：`{"fr": "com.apple.keylayout.French-PC"}` | 法文：`com.apple.keylayout.French`（AZERTY） |
| `outputLanguages` | `@translate` 要翻譯成的語言，依序排列：`["es", "fr", "de"]`… | `["en"]` |
| `improveTranslates` | `@improve` 同時翻譯（等同 `@translate @improve`） | `false` |
| `actionKey` | 執行鍵：`"enter"`（⏎）、`"optionTap"`（Tap ⌥）、`"optionSpace"`（⌥Space）、`"space"`（Space） | `"enter"` |
| `commandTrigger` | 開頭用來打開指令的符號：`"#"`、`"%"`、`"&"`、`"*"`、`"+"`、`"@"`、`"\|"`、`"~"` 之一；其他值都按 `"@"` | `"@"` |
| `uiLanguage` | 介面語言（設定視窗、候選視窗提示、選單）：`"zh"`（簡體中文）、`"en"`，或 App 附帶的其他語言代碼：`"zh-Hant"`、`"ja"`、`"ko"`、`"de"`、`"fr"`、`"es"`、`"pt-BR"` | `null`（跟隨系統） |
| `rewriteStyles` | 改寫風格：`polish`、`concise`、`formal`、`casual`、`tactful`、`jargon`，例如 `["polish", "concise", "jargon"]` | Polish、Concise、Formal |
| `jargonFile` | 你自己的 Jargon 術語表檔案 | `null`（即 `~/.config/allinoneime/jargon.txt`） |
| `menuBarIcon` | 選單列圖像及其下拉面板 | `true` |
| `candidateLayout` | 拼音和印地文的候選字詞：`"vertical"`（上下排列）或 `"horizontal"`（橫向並排；← → 選取，↑↓ 翻頁） | `"horizontal"` |
| `fuzzyPinyin` | 模糊拼音配對：`["z-zh", "n-l", "in-ing"]`（z-zh、c-ch、s-sh、n-l、f-h、r-l、an-ang、en-eng、in-ing、ian-iang、uan-uang） | `[]` |
| `useSelection` | @ 指令處理欄位中選取的文字（見「對選取的文字使用指令」） | `true` |
| `checkForUpdates` | 每天在背景檢查一次新版本；你沒按下之前不會安裝任何東西 | `true` |
| `agent` | `@agent` 要把文字交給哪個程式設計 agent（Settings → Agent）：`claude`（Claude Code）、`gemini`（Gemini CLI）、`kiro`（Kiro CLI）或 `custom` | `claude` |
| `agentCommand` | 自訂 agent 的指令，你輸入的內容會作為最後一個引數加在後面，例如 `["muse", "--"]` | `[]` |
| `agentPageContext` | `@agent` 在 Google Chrome 中把網頁一起帶上（欄位、它的表單或區段、選取的文字、看得到的文字；絕不包含密碼） | `true` |
| `claudeInBackground` | `@agent` 使用 Claude Code 時在背景執行，完成時通知你（其他 agent 一律在 Terminal 中打開） | `true` |
| `rememberQuestions` | 在這台 Mac 上保留你最近 5 個 `@question` 問題和答案，列在 `@question` 下方（見「最近的問題」） | `true` |
| `questionRounds` | `@question` 對話在候選視窗中進行幾輪後，建議到別處接著聊，2–10 | `5` |
| `questionContinueIn` | `@question` 對話可以在哪裡接著聊，依序排列，第一個為預設：`agent`（`@agent` 所交給的那個，取代該 agent 自己的項目）、`claudeCode`、`geminiCLI`、`kiroCLI`、`customAgent`（各個 agent，已安裝才有）、`claudeWeb`、`chatgpt`、`gemini`、`copy` | `agent`、其他已安裝的 agent、Claude、ChatGPT、拷貝 |
| `appProfiles` | 單一 App 的設定，依 bundle ID，每一項都是選擇性的：`inputLanguage`、`rewriteStyles`、`typeOut`、`noAI`、`translateAlways`（見「依 App 設定」） | `{}` |
| `notes` | `@note` 存到哪裡（Settings → Plugins → Notes）：`{"destination": "folder", "folder": "~/Vault/Inbox"}`，或 `"notion"` 加上 Test 找到的頁面或資料庫；絕不透過 iCloud 雲碟同步（權杖在鑰匙圈中，只有開啟「API keys and passwords」時才會透過 iCloud 鑰匙圈同步） | `destination: "notes"` |
| `redaction` | 對 AI 隱藏敏感資訊（見「隱私」）：`{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`；每種偵測（`emails`、`phones`、`cards`、`keys`、`ips`）除非設為 `false`，否則都開啟 | `enabled: false` |

## 隱私

- 打字（英文和拼音）以及 `@calculator` 外掛程式的計算完全在本機進行。只有在 `@improve`、`@translate` 或 `@question` 上按下執行鍵時，該句子才會送到你選擇的 AI 供應商（你自己的 Bedrock，或你加入金鑰的服務）。勾選「Jargon」並設定了術語表時，術語表會一併送出。修改結果（在結果出現後輸入要求，再按 ⇧⏎）會再次送出同樣的請求，並附上目前顯示的結果和你的要求；追問（⇧⏎）則會連同到目前為止的對話一起送出。
- Settings → Assistant 只有在你按 Preview，或寫了問題再按 Check 時，才會把文字送給模型：只要這台 Mac 能用 Apple Intelligence 就用它（不會有任何內容離開 Mac），否則用你的供應商。修改設定的請求會送出你的句子（句子中輸入的金鑰會先去除），以及它可以修改的那些設定的目前值：絕不包含金鑰，也不包含你對 AI 隱藏的詞（只送出有幾個），AWS 設定檔的名稱也只在句子與 AWS 或 Bedrock 有關時才送出。問題會連同遮蔽過的檢查結果一起送出：路徑只到 `~` 為止，沒有金鑰，記錄只留下固定的詞句。兩者都會套用隱藏敏感資訊的設定。單純檢查什麼都不送；Check 另外會送出 Test Connection 的那一次請求，而且只在供應商有金鑰或憑證可測試時才送。
- 把 `@question` 對話移到別處接著聊（最後一輪之後按 ⌘1…，或按 ⌘⏎）時，會把對話連同你輸入的內容，透過網址或剪貼簿送到你選的服務：這台 Mac 上的程式設計 agent（Claude Code、Gemini CLI、Kiro CLI 或你自己的，各自使用自己的帳號和服務）、claude.ai、chatgpt.com 或 gemini.google.com。送出的內容就是你看到的樣子：對 AI 請求隱藏的值（見下文）會原樣包含在內，因為是你選擇把它送到那裡。在你選擇之前不會送到任何地方；「Copy the conversation」只會把它放到剪貼簿。
- 使用 AllInOneIME Cloud 時，句子會經由開發者的伺服器送到模型供應商（目前經由 OpenRouter）：伺服器只保留計數，絕不保留文字。登入只會保留你的電子郵件地址。
- 隱藏敏感資訊（Settings → AI Provider → Privacy，預設關閉）：任何請求送出之前（`@improve`、`@translate`、`@question`、你的提示詞指令和提示詞外掛程式，所有供應商皆然，包括 AllInOneIME Cloud），電子郵件地址、電話號碼、付款卡號（經 Luhn 檢查）、API 金鑰和權杖（`sk-`、`sk-ant-`、`AKIA…`、`ghp_`、`xox…` 和很長的隨機字串）、IP 位址以及你自己的字詞（代號、名字）會先在 Mac 上換成 `[EMAIL_1]`、`[PHONE_1]`、`[ITEM_1]` 這類預留位置；同一個值使用同一個預留位置。模型的結果在顯示或插入之前會換回真實內容，候選視窗會顯示「2 items hidden from the AI」。模型把預留位置改得無法辨認的結果，會照原樣顯示並標上「⚠ placeholder changed」。術語表中含有被隱藏內容的項目不會送出。每一類都能個別關閉。全形寫法（`zhang＠example.com`、`１３８…`）也找得到，值或片語中間換行也可以。它能辨識有固定格式的值，例如電子郵件、號碼和金鑰；無法辨識人名或地址（請把它們加為你自己的字詞），也無法辨識其他字母系統中外形相似的字母。只適用於送往你的 AI 服務的請求；`@agent`（連同它帶上的 Chrome 網頁）、從網站擷取資料（`@stock`）或開啟網站（`@x`）的外掛程式，以及腳本擴充功能，會照原樣送出文字。設定檔中為 `redaction`（`enabled`、`emails`、`phones`、`cards`、`keys`、`ips`、`customWords`）。
- 輸入法只在你於指令中按 ⌃V 或 ⌘V 時讀取剪貼簿文字一次；密碼管理工具標示為隱藏的內容不會被讀取。文字會先顯示在指令中，同樣只在你按下執行鍵時才會送出。較新的 macOS 版本會詢問是否允許 AllInOneIME 讀取剪貼簿：請允許。若不想每次都被詢問，請在 System Settings → Privacy & Security 中把 AllInOneIME 的貼上權限設為一律允許。
- 在密碼欄位中，macOS 會切換到它自己的鍵盤（U.S. 或 ABC），離開時再切回來。只要你正在輸入的 App 處於安全輸入狀態，AllInOneIME 就不會組字：按鍵照原樣輸入。而且當系統處於安全輸入狀態時（密碼欄位、Terminal 的 Secure Keyboard Entry（安全鍵盤輸入）等），不會有任何內容送到 AI。
- `@note` 和 `@reminder` 不經過 AI：AllInOneIME 只把文字交給這台 Mac 上的 Notes 和 Reminders，提醒事項的時間也在 Mac 上解析（這些 App 是否把它同步到你的其他裝置，取決於它們的帳號，例如 iCloud）。因此它們在安全輸入期間也能使用。`@note` 存到資料夾時，會在這台 Mac 上寫入一個檔案（若該資料夾會同步，例如 iCloud 雲碟或 Obsidian Sync 的資料夾，檔案也會跟著同步）。`@note` 存到 Notion 時，會把備忘錄送到 Notion（api.notion.com，使用你 integration 的權杖，權杖存放在鑰匙圈中），而且只在那時送出：安全輸入期間不會送出。
- `@reportissue`（以及「Report an Issue…」）本身不傳送任何內容：它在瀏覽器中開啟 GitHub 的新 issue 頁面，附上你輸入的標題，以及上面列出的版本、語言、供應商種類和數量，這些會先顯示在候選視窗中。除非你在那裡按一下 Submit，否則不會有任何內容送到 GitHub。
- `@open` 只在這台 Mac 上搜尋。它會記住你用它開啟過的項目（最近 200 個），存放在輸入法自己的偏好設定中（不在 config.json 中），以便把它們排在前面。
- 為了 Settings → Apps 中的「Add App…」，輸入法會在它自己的偏好設定中保留你最近打過字的 12 個 App 的 bundle ID；關於它們的其他資訊一概不保留。
- `@question` 會記住你最近的 5 個問題、答案和提問時間，只存放在這台 Mac 上（除非你選擇透過 iCloud 同步它們，見上文）的 `~/Library/Application Support/AllInOneIME/recent-questions.json`（只有你的使用者帳號能讀取），用來在 `@question` 下方列出；已儲存的答案會從那裡顯示，不需連網。處於安全輸入狀態時不會保留任何內容，對選取文字提出的問題也完全不保留（它們的答案講的是選取的文字，若保留就會把那段文字寫到磁碟上）。在 Settings → General 關閉「Remember recent questions」也會刪除它們；透過 Settings → Assistant 關閉（設定檔中的 `rememberQuestions`）則會保留，以便能完全還原。「Clear」會刪除它們。
- 為了列出你的備忘錄，選單列面板會在輸入法自己的偏好設定中，保存最近 30 則用 `@note` 儲存的備忘錄的 ID（Notes 中備忘錄的 ID、檔案的路徑，或 Notion 頁面的位址）和第一行（最多 80 個字元），面板關閉時也一樣。打開面板絕不會向 Notion 查詢任何東西。
- `@py` 和 `@js` 只在你按下執行鍵時才執行，而且只執行你自己輸入或貼上的程式碼：AI 的答案和其他指令的輸出絕不會被當作程式碼執行。`@py` 使用你 Mac 上的 `python3`，它能像在 Terminal 中一樣讀寫檔案和連上網路；`@js` 在獨立的行程中執行，無法讀取檔案、連上網路或執行其他程式。兩者都不會在安全輸入期間執行。
- 檢查更新：每天一次（除非關閉了「Check for updates automatically」），AllInOneIME 會下載 https://allinoneime.com/update.json 及其簽章；請求中沒有任何識別資訊，也沒有你輸入的內容。只有在你按一下 Update 時，才會從 GitHub release 下載更新。
- 擴充功能來源：git 以你的身分在你的 Mac 上執行，而且只針對你加入的來源：每天為會自動檢查的來源 fetch 一次（固定版本的來源不會），以及你按 Check Now、Update 或 Re-clone 時。它只和儲存庫的主機連線，以你自己的 git 和 SSH 設定登入；你輸入的任何內容都不會隨之送出。
- 透過 iCloud 同步（預設關閉）：只存到你自己的 iCloud 雲碟 `~/Library/Mobile Documents/com~apple~CloudDocs/AllInOneIME/`，由 Apple 同步到你的其他 Mac；不會有任何內容送到開發者的伺服器。存到那裡的有：`settings.json`（同步的設定，各自附上變更時間和每台 Mac 的隨機 ID；你的自訂指令，包括會執行程式的那些，它們仍然只在你選取時才執行）、`jargon.txt`（你的 Jargon 術語表）、`rime/`（每台 Mac 拼音學到的字詞的快照，Rime 資料夾中的其他東西一概不放：你的自訂短語和 Rime 設定留在 Mac 上），以及只有在你開啟時才會存的你對 AI 隱藏的字詞（在 `settings.json` 中）和 `questions.json`（最近的問題和答案，只有你的使用者帳號能讀取）。關閉這兩項後，它們會留在 iCloud 中，直到你移除為止（每個開關下方的「Remove from iCloud…」）。絕不存放：API 金鑰、權杖或密碼、擴充功能來源、擴充功能資料夾和外掛程式、不再打錯的 App、最近的 App、視窗狀態、同步開關。只有開啟「進階資料保護」時，iCloud 雲碟才是端對端加密。這台 Mac 自己的同步紀錄存放在 `~/Library/Application Support/AllInOneIME/iCloudSync/state.json`。
- 記錄檔不會記錄你輸入的內容。對於每個第三方輸入法，macOS 都會警告「The developer can access anything you type with this input source」（開發者可以取用你使用此輸入方式輸入的任何內容）；這是系統的通用警告。

## 開發

```sh
make test         # unit tests, plus tests that run the real Rime engine (and make strings-check)
make strings      # adds new interface text to Resources/Localizable.xcstrings, marks what's unused stale
make pack         # the Chinese language pack: build/packs/zh-pinyin-<version>.tar.xz, its sha256, its packs.json entry
make packs        # all the language packs: Chinese, and Korean and Hindi from Core/LanguagePacks/ (ko-hangul, hi-phonetic)
make selftest     # drives the input method through a simulated text field: real Bedrock calls
make realtest     # types into a real app's text field (needs the screen unlocked; takes over the foreground for about 1 minute)
make screenshots  # regenerates the screenshots in docs/
make cli && .build/release/allinoneime-cli --styles concise,jargon "this is a blocker bug your team need fix it asap"   # try polishing and rewrites in the terminal
make icon         # regenerates the app icon and the menu bar icon from Resources/AppIcon.png
make dmg          # the release installer, build/AllInOneIME-<version>.dmg (universal; needs the Developer ID certificate it's signed with and DIST_PROFILE, the provisioning profile; optionally notarized), and the in-app update, build/AllInOneIME-<version>-update.zip
make app PROFILE=<profile> SIGN_IDENTITY=<a certificate it lists>   # a build with the keychain entitlements: it can sync keys through iCloud Keychain
make update-test  # the in-app updater end to end: a temporary install, a test server on 127.0.0.1, a test key (never the installed app)
```

`make selftest` 和 `make realtest` 不受你的設定影響。自我測試使用自己的設定（Amazon Bedrock，沿用你設定中的 AWS 設定檔和區域，其他一律使用預設值）；真實 App 測試在執行期間把供應商設為 Bedrock，結束後再改回你的設定。當下無法檢查的項目會略過，而不是算作失敗：沒有該設定檔憑證時的 Bedrock 即時檢查，以及安全輸入開啟時（螢幕鎖定、密碼欄位）要輸入的一切。最後一行會統計通過、失敗和略過的檢查；只有失敗會讓這次執行失敗，有略過項目的執行會以 INCOMPLETE 結束，若沒有任何會打字的檢查執行則以 SKIPPED 結束（BLOCKED：真實 App 測試在螢幕鎖定時開始），絕不會是 PASSED。

介面文字寫成 `tr("中文", "English")`：簡體中文和英文來自程式碼，其他語言來自 String Catalog：核心的文字在 `Core/Resources/Localizable.xcstrings`，App 自己的文字在 `Resources/Localizable.xcstrings`（由 Makefile 用 Xcode 的 `xcstringstool` 合併並編譯進每個 App），以英文文字為鍵，每個內插值寫成 `%@`。新增或修改文字後，請執行 `make strings`（在那之前 `make test` 會失敗；自我測試的文字在 `*SelfTest.swift` 中，不交給譯者翻譯）。同一段英文有兩種意思時（`make strings` 會列出它們，`make strings-check` 會因此失敗），請給其中一個專屬的鍵，用簡短的點分名稱說明它用在哪裡或怎麼用：`tr("删除", "Remove", key: "remove.delete")`；它的英文就是 catalog 中該鍵的英文值。新增一種語言，就是在 catalog 中加入它的一欄：審閱過的翻譯，每種語言一個 JSON 檔案（`"core\t<key>"` 或 `"app\t<key>"` → 它的翻譯），用 `Scripts/import-translations.py <folder>` 匯入；這個腳本絕不更動英文，並會拒絕預留位置與鍵不符的翻譯。核心自己的文字取用介面語言的代碼，以同樣的方式查詢（`InterfaceText.lookup`，由各個 App 設定：在 macOS 上是它的 `.lproj` 套件；在其他平台上由 `StringCatalog` 讀取 catalog 的表格）。

程式碼結構：根目錄是 macOS App；`Core/` 是各平台共用的核心，自成一個 Swift package（可以單獨建置和測試，在 macOS、Linux 和 Windows 上皆可）；`Windows/` 是 Windows App 的起步。

- `Core/Sources/AllInOneIMECore`：Bedrock 用戶端、SigV4、提示詞、兩層式輸入狀態機（包括 @ 指令）；不依賴 AppKit
- `Core/Sources/AllInOneIMEText`：介面文字及其語言（`UIString`、`InterfaceText`、`InterfaceLanguage`，以及在沒有 `.lproj` 套件的地方讀取 catalog 的 `StringCatalog`）；設定啟動器只連結這一個模組（`AllInOneIMECore` 會重新匯出它）
- `Core/Sources/AllInOneIMEQuickJS`：QuickJS-ng（它的 C 原始碼在 `Core/Sources/CQuickJS` 中），在沒有 JavaScriptCore 的地方（Windows、Linux、Android）執行外掛程式和 `@js` 的 JavaScript
- `Core/Sources/AllInOneIMERime`：librime 包裝層
- `Core/Sources/AllInOneIMECLI`：命令列工具 `allinoneime-cli`（`make cli`），由各平台自己的 `main` 執行
- `Sources/AllInOneIMEMac`：只有 Mac 才有的部分（鍵盤配置、程式碼簽署、Spotlight、AppleScript、更新程式的安裝步驟），以及 `Platform.mac`
- `Sources/AllInOneIME`：InputMethodKit 輸入法、候選視窗、設定視窗
- `Sources/AllInOneIMESettings`：「AllInOneIME Settings」啟動器
- `Sources/AllInOneIMEInstaller`：磁碟映像檔中的「Install AllInOneIME」：安裝、更新和解除安裝

語言包有自己的程式庫，與外掛程式分開：儲存庫 [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages)，透過 https://languages.allinoneime.com/ 提供，並以它們自己的金鑰簽署。`make pack` 建置封存檔；它會以發行資產的形式發佈在那裡（發行版本 `zh-pinyin-<version>`、`ko-hangul-<version>`、`hi-phonetic-<version>`），`swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` 會在那裡寫入 `packs.json`，並用鑰匙圈中語言包的金鑰（`allinoneime-languages-signing`）簽署成 `packs.json.sig`。App 會讀取 <https://languages.allinoneime.com/packs.json>，檢查簽章，再檢查封存檔的大小和 SHA-256。要從本機伺服器試用語言包：`--test-key` 會以測試金鑰簽署，再執行 `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`。

發佈新版本（App 內的更新程式會讀取 https://allinoneime.com/update.json，以發佈專用的金鑰簽署）：

1. 提高版本號（`AppVersion.swift` 和三個 Info.plist；`AppVersionTests` 會檢查它們是否一致）並更新更新日誌。
2. `make dmg NOTARY_PROFILE=<profile>`：產生 `build/AllInOneIME-<version>.dmg` 及其 `.sha256`，以及 `build/AllInOneIME-<version>-update.zip`（兩個 App，和磁碟映像檔中的安裝程式所帶的一樣）。App 和映像檔會以鑰匙圈中的 Developer ID Application 憑證簽署，映像檔再以該 `xcrun notarytool` 鑰匙圈設定檔進行公證並裝訂（staple）。輸入法帶有 Developer ID 佈建描述檔（`Resources/Signing/AllInOneIME-DeveloperID.provisionprofile`，`DIST_PROFILE`），由它授予輸入法的鑰匙圈權限（entitlements）；如果描述檔沒有列出簽署用的憑證、沒有佈建所有裝置或剩不到 30 天（`Scripts/profile-entitlements.sh`），或簽章缺少鑰匙圈權限，建置就會停止，它也會執行一次簽署好的輸入法（描述檔不相符的話，macOS 會終止它）。`DIST_PROFILE` 是空的也會讓建置停止：沒有這些權限的版本會看不到所有已移到 iCloud 鑰匙圈的金鑰。描述檔只列出兩張 Developer ID G1 憑證：改用另一張（G2）簽署之前，請在開發者網站上建立列出它的新描述檔（手動建立：這個 App ID 的簽署不交給 Xcode 管理），並提交它。
3. 把兩者上傳到 GitHub 的 `v<version>` release 並發佈。
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"`（各一兩句）：寫出 `site/public/update.json`（從 App 讀取的版本、build 和最低 macOS 版本，檔案的位址、大小和 SHA-256，發佈說明的位址和摘要），並用登入鑰匙圈中的金鑰（`allinoneime-releases-signing`；macOS 可能會詢問是否允許存取）簽署成 `update.json.sig`。兩個檔案都要提交。
5. 等 release 的檔案可以下載後，再部署網站（`cd site && npx wrangler@4 deploy`）：App 每天檢查一次，`AllInOneIME --check-update` 會顯示它們看到的內容。

App 在讀取 manifest 之前，會先用內建的公鑰核對它的簽章，絕不安裝不比現在新的版本，只透過 https 從 allinoneime.com 或本儲存庫的 GitHub release 檔案下載，而且只有在封存檔的大小和 SHA-256 與 manifest 相符、兩個 App 的 bundle ID、版本和程式碼簽章都通過檢查、新的輸入法能啟動時，才會安裝。之後輸入法會把工作交給自己的執行檔擔任輔助程式（`--apply-update`），它會等輸入法結束，像安裝程式一樣替換 App（舊的先移到一旁，出錯就放回去），再註冊新的。要用本機伺服器試試：`make update-test`，或使用 `Scripts/build-update-manifest.swift` 的 `--test-key`，再執行 `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`。

Bundle ID 仍是 `com.aipinyin.inputmethod.AIPinyin`：macOS 用它來記住已加入的輸入方式和授予它的權限，所以更改它就得重新加入輸入法並再次授予權限。

## 授權

Copyright © 2026 MicroZ LLC. 原始碼以 [Functional Source License 1.1](../../LICENSE)（FSL-1.1-ALv2）提供：除了開發競爭產品之外，你可以為任何目的使用、閱讀、修改和分享它。每個版本在發行兩年後改為 Apache-2.0。0.6.1 以前（含）的版本以 GPL-3.0 發行，並持續以該授權提供。

第三方元件（librime 及其外掛程式採用 BSD-3-Clause；rime-ice 的 Lua 腳本和中文語言包採用 GPL-3.0）列於 [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)。
