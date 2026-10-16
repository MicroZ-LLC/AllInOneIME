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
[![Apple 晶片與 Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#安裝)
[![授權：FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![下載次數](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[下載](https://allinoneime.com/download)** · **[網站](https://allinoneime.com)** · **[文件](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[擴充功能](../extensions.md)**

[使用方式](#使用方式) · [指令](#-指令測試版) · [自訂指令](#自訂指令) · [語言](#輸入與翻譯) · [語音](#語音輸入) · [安裝](#安裝) · [隱私](#隱私)

<br>

<img src="../en/demo.png" width="820" alt="@translate 加上一句話，再按 ⏎：西班牙文、法文和德文各一行">

</div>

*這是英文 README 的翻譯；兩者有出入時，以英文版為準。*

> [!NOTE]
> 從 0.6.3 起，AllInOneIME 以 Developer ID 簽署並經過 Apple 公證：不必再到 System Settings → Privacy & Security（系統設定 → 隱私權與安全性）中允許它。從較舊的版本更新後，對 AllInOneIME 存在鑰匙圈中的每把金鑰，macOS 都會詢問一次你的登入密碼：輸入後按一下「Always Allow」（永遠允許）。只從 [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) 或 [allinoneime.com](https://allinoneime.com) 下載 AllInOneIME。

一款在每個文字欄位都能使用 AI 指令的 macOS 輸入法。在句子開頭輸入 `@`，寫完後按 ⏎：`@improve` 潤飾你寫的內容並提供幾種改寫，`@translate` 把它翻譯成你選的語言，`@question` 提出問題，`@claude` 把它交給 Claude Code，`@open` 尋找檔案和 App，或開啟網址。你也可以按住右側 ⌥ 說話。不以 `@` 開頭時，按鍵照常送到 App。它也能輸入中文（拼音，以 Rime 和 rime-ice 為基礎）、法文、韓文（諺文）和印地文（以拉丁字母輸入天城文），並能把你自己的腳本當作 @ 指令執行。

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
| ⇧⏎ | AI 結果出現後又輸入了後續內容時：把它送出（`@question` 對話的下一個問題，或修改要求）。正在輸入指令時，或 AI 結果出現後什麼都沒輸入時：照你輸入的原樣插入，連同 `@command`。在其他結果上（`@open`、提醒事項…）插入反白的那一列，和 ⏎ 一樣。在 @config 和 @doctor 的結果上，什麼都沒輸入時按 ⇧⏎ 不做任何事 |
| ⌘C | 拷貝反白的結果（`@open` 則是路徑）；候選視窗保持開啟 |
| ⌃V | 在指令中（例如 `@improve ` 之後）：把剪貼簿的文字接在你輸入的內容後面，而不是貼到 App 裡。多行會合併成一行，每次最多 2000 個字元（`@note` 會保留換行，最多 20000 個）。在任何 App 中都可用；沒有指令時，按鍵照常送到 App |
| ⌘V | 和 ⌃V 一樣，但有些 App 會自行處理 ⌘V（Ghostty、iTerm2、Terminal 等終端機，以及 Notes），照常貼到 App 裡；在這些 App 中請用 ⌃V |
| Esc、⌫ | 回到句子繼續編輯；結果出現後輸入標點或數字就是接著寫。修改結果後：回到修改前的那一版 |
| AI 結果出現後輸入字母 | 後續內容：`@question` 之後是下一個問題（見[對話](#與-question-對話新)），`@improve` 或提示詞指令之後是修改要求，例如 `shorter`（見[修改結果](#修改結果新)）；按 ⇧⏎ 送出。`@translate` 之後輸入字母是接著寫這個句子，按 ⏎ 重新翻譯 |
| ⌘⏎、⌘1–⌘5 | 在 `@question` 對話中：列出可以接著聊的地方（Claude Code、Claude、ChatGPT、Gemini，或拷貝對話）；⌘1、⌘2… 選一個 |
| 按一下某一列 | 在候選視窗中：選取這一列，和按它的數字鍵一樣（字詞、清單中的指令、結果、`@open` 找到的檔案、收件人、擴充功能列出的列）；指標下方的那一列會反白。文字欄位保持焦點 |
| 輕按 Shift | 有多種輸入語言時：依序切換到下一種（英文 → 中文 → 法文 → …，然後回到第一種） |
| 按住右側 ⌥ | 說話，放開即停止。以你正在輸入的語言辨識（英文、中文、法文、韓文或印地文）。在指令中，文字會接在指令後面；否則直接插入 |

## @ 指令（測試版）

| 指令 | 作用 |
|---|---|
| `@improve` | 潤飾：1–3 是用句子本身語言寫的三個版本，4 之後是改寫風格（在設定中加入並排序），0 是原文。不會翻譯；開啟「@improve also translates」（@improve 同時翻譯）時，效果等同 `@translate @improve` |
| `@translate` | 翻譯成你加入的語言（設定 →「Translate」，拖曳可調整順序），每種一行；只有一種語言時提供三個版本；句子本身的語言會略過。`@translate @improve` 一起使用時，一次請求就能翻譯並改寫 |
| `@question` | 提出問題；答案會出現在候選中，按 ⏎ 或 Space 插入，⌘C 拷貝。接著輸入並按 ⇧⏎ 就是追問：候選視窗會變成最多 5 輪的對話，之後建議到 Claude 或其他 AI 接著聊。後面沒有輸入任何內容時，會列出你最近的 5 個問題，最新的在前；接著輸入就能篩選（問題中任何位置的字詞，不分大小寫，中文也可以）。按數字鍵、↑↓ 再按 ⏎，或按一下，會立刻顯示該問題已儲存的答案，不需連網，照常插入或拷貝；在那裡按 ⌘R 會重新提問以取得新的答案。沒有符合的項目，或沒有選取任何項目時，⏎ 會提出你輸入的問題 |
| `@claude` | 把任務交給 Claude Code：預設在背景執行，完成時會發出通知（按一下通知，即可在 Terminal 中開啟該工作階段繼續），或用 `@tasks` 查看。它使用你自己的 Claude Code（`claude` 指令），以及它自己的登入和設定。在設定中關閉「@claude runs in the background and notifies me」（@claude 在背景執行並在完成時通知我），就會像以前一樣在 Terminal 中開啟。第一次開啟 Terminal 時，macOS 會詢問是否允許 AllInOneIME 控制 Terminal：按一下「OK」（好） |
| `@tasks` | 列出背景中的 Claude 任務（進行中／已完成／等你回應），以及它們最後的回覆；按 ⏎ 在 Terminal 中開啟，⌘C 拷貝回覆 |
| `@settings` | 立即開啟設定視窗（選取它就夠了） |
| `@config` | 依你的描述修改設定：`@config output languages English and French`、`@config use Chinese in WeChat`、`@config candidates in a column`。按 ⏎ 顯示要改的地方（原本 → 改為）；⏎（或 1）套用，Esc 取消，接著輸入再按 ⇧⏎ 可以再調整；⌘Z 或 `@config undo` 會還原。見[用描述的方式修改設定](#用描述的方式修改設定新) |
| `@doctor` | 檢查這台 Mac 上的設定，能安全修好的就幫你修好：按 ⏎ 列出結果，問題在前；按數字修正那一項，按 ⏎ 修正可安全修正的幾項，都會先在 `@config` 的預覽中顯示。`@doctor why doesn't translate work` 還會讓 AI 解釋可能的原因。見[檢查你的設定](#檢查你的設定新) |
| `@open` | 邊輸入邊列出符合的檔案、資料夾和 App（Spotlight）。可以輸入多個關鍵字，以空格分隔：每個都必須出現在路徑中，且至少一個出現在名稱中（標準資料夾的名稱也適用於其中的項目：`downloads pdf` 會找到 Downloads（下載項目）中的 PDF）。App 和標準資料夾也能用中文名稱找到，中文介面下也以中文名稱顯示。用 `@open` 開啟過的項目排最前面，接著是 App 和那些資料夾，然後是最近使用或修改過的檔案；若名稱只找到兩個以下的檔案，且沒有符合的 App 或那些資料夾，也會依內容搜尋你個人專屬資料夾中的檔案，這些列標示為「content」（內容）；若沒有其他結果，按 ⏎ 會列出它們讓你挑選，而不是直接開啟第一個。輸入網址時（`github.com`、`localhost:3000`、`https://…`），第一列是「open in the browser」（在瀏覽器中開啟），且不搜尋內容；名稱與其完全相同的檔案（例如 `MANIFEST.in`）排在最前面。以 `~/` 或 `/` 開頭的文字是路徑：Tab 會補全並進入資料夾；⏎ 開啟，⌘C 拷貝路徑 |
| `@note` | 把文字存到 Notes App 中名為 AllInOneIME 的資料夾（不存在時會建立）；不會插入任何內容。貼上的文字保留換行，最多 20000 個字元 |
| `@reminder` | 在 Reminders App 名為 AllInOneIME 的列表中加入提醒事項。把時間寫在文字裡；時間在 Mac 上解析，並有一列顯示解析結果：按 ⏎ 或 Space 加入，Esc 返回編輯。有時間的話，會在那時響起提醒；只有日期的話，就是整天 |
| `@calculate` | 在這台 Mac 上計算；結果出現在候選中，按 ⏎ 或 Space 插入：`@calculate 23*17` → `391`。也能在句子中使用：`@reply the total is @calculate 23*17 dollars` |
| `@py` | 執行一行 Python（Mac 上的 `python3`）並插入結果：程式碼最後一個運算式的值，例如 `@py 2**100`、`@py import math; math.sqrt(2)`，否則就是它印出的內容。沒有 `python3` 時不提供（Xcode 的命令列工具內含） |
| `@js` | 執行一行 JavaScript 並同樣插入結果：最後一個運算式的值，或 `console.log` 印出的內容，例如 `@js [1, 2, 3].map(x => x * 2)`。它使用 macOS 內建的 JavaScriptCore，不需要安裝任何東西；它無法讀取檔案、連上網路或執行其他程式 |
| `@reportissue` | 回報問題：在瀏覽器中開啟 GitHub 的新 issue 頁面，把指令後面輸入的內容當作標題，並附上「What happened / What you expected」（發生了什麼／你預期的結果）讓你填寫。它會加上 App 和 macOS 的版本、Mac 的架構、介面與輸入語言、已安裝的語言包、AI 供應商的種類（若是公開模型則附上模型名稱，否則寫「custom」）、執行鍵，以及你有幾個自訂指令、外掛程式和擴充功能，但絕不包含它們的名稱、你的文字、路徑或金鑰。按 ⏎（或你的執行鍵）會先在候選視窗中顯示這些內容；再按一次 ⏎，或按一下那一列，才會開啟網頁，你在那裡看過後按一下 Submit（使用你的 GitHub 帳號）；Esc 返回。輸入選單（「Report an Issue…」）和 Settings → About 中也有 |
| `@imessage` | 傳送 iMessage：輸入姓名、電話號碼或電子郵件（中文姓名也可以用拼音，全拼或首字母皆可），在候選視窗中選擇收件人（最近傳過訊息的排在前面；完整的號碼或地址也可以），然後寫訊息（其中的指令如 `@stock AAPL` 會先執行）。按 ⏎ 會在視窗中顯示「Send to Alex (…): message」，再按一次 ⏎ 送出，Esc 返回編輯；不會在文字欄位中輸入任何內容。第一次使用時，macOS 會詢問是否允許 AllInOneIME 取用 Contacts（聯絡人）及控制 Messages（訊息）：兩個都按一下「OK」 |

範例：`@q` ⏎，輸入 `what is quantum computing`，⏎。`@note books to read: The Three-Body Problem` ⏎ 會儲存一則備忘錄。`@reminder call Bob tomorrow at 3pm` ⏎，確認它解析出的時間，再按一次 ⏎ 加入。選定指令後，也可以按住右側 ⌥ 說話。在中文模式下，`@open` 和 `@calculate` 會暫時切換為英文字母，完成後再回到中文。

`@py` 和 `@js` 的程式碼以英文字母輸入，全形標點（來自中文模式）會轉成 ASCII；請寫在同一行，敘述之間用 `;` 分隔。程式碼在獨立的行程中執行，10 秒後或隨時按 Esc 即停止；出錯時會顯示錯誤的第一行，例如 `ZeroDivisionError: division by zero`。多行輸出會照印出的樣子插入；在終端機中則合併成一行插入（終端機會執行收到的每一行）。編輯器內的終端機（VS Code、Cursor、JetBrains）無法與編輯器本身區分，因此在那裡，任何指令的多行輸出都會原樣插入。兩者也都能在其他指令的句子中使用：`@reply the answer is @py 2**100`；含空格的程式碼請加上引號：`@question explain @py "sum(x * x for x in range(10))"`。反過來則不行：`@py` 和 `@js` 的程式碼一定完全照你輸入的內容執行，其中的 `@commands` 不會先執行。

![輸入 @ 開啟指令清單；@question 加上問題，再按 ⏎ 取得答案](../en/commands.png)

![@open 邊輸入邊尋找 App；以 / 開頭則是路徑：列出資料夾內容，Tab 補全](../en/open.png)

`@` 後面接的不是指令時（例如 `@john`），`@` 會照常插入，所以在聊天 App 中 @ 提及別人仍然可用。`@question`、`@improve` 和 `@translate` 只在你按下執行鍵時才送到你自己的 Bedrock；`@open` 只在這台 Mac 上搜尋；`@note` 和 `@reminder` 只送到這台 Mac 上的 Notes 和 Reminders；`@claude` 使用安裝在你 Mac 上的 Claude Code（`claude` 指令）及其自己的帳號，並且和平常一樣，在修改檔案或執行指令前會先詢問你。沒有安裝 Claude Code 時，不提供 `@claude`。`@imessage` 只讀取這台 Mac 上的 Contacts（姓名、電話號碼、電子郵件），絕不經過 AI，訊息由 Messages 傳送；沒有 Messages App 時不提供。

`@calculate` 在這台 Mac 上離線計算：`+ - * /`（也可用 `× ÷`）、`^` 或 `**` 表示次方、括號、百分比（`50%` 是 0.5，`200*5%` 是 10；和計算機一樣，加上或減去的百分比是相對於前面的數：`100+10%` 是 110，`100-10%` 是 90）、函式 `sqrt abs round floor ceil ln log exp sin cos tan min max pow`（`log` 以 10 為底，角度單位為弧度，`round(x, 2)` 保留兩位小數），以及常數 `pi`（`π`）和 `e`。全形數字和符號也能用。運算以十進位精確計算，所以 `0.1+0.2` 是 `0.3`；結果最多 15 位有效數字，38 位以內的整數會完整寫出（`2^100` → `1267650600228229401496703205376`）。

### 對選取的文字使用指令（新）

在任何 App 中選取一段文字（Notes 裡的一句話、Mail 裡的一段），輸入 `@improve`、`@translate`、`@question` 或其他處理文字的指令，然後按 ⏎：指令會處理選取的文字，你挑選的結果會取代它。你輸入時，選取的文字保持原樣、維持選取狀態：指令寫在候選視窗中，第一行是你輸入的內容，下一行是「On the selection: “…” (N characters)」（針對選取範圍：N 個字元）。按 Esc、⇧⏎ 或按一下別處，文字都保持原樣；途中改變選取範圍也一樣，而且會取消指令。指令後面輸入的文字，對 `@improve` 和 `@translate` 是要求（`@translate ja`、`@improve more formal`），對 `@question` 則是關於這段選取文字的問題（`@question what does this mean`）。`@open`、`@claude`、`@tasks`、`@settings`、`@reminder`、`@imessage`、`@reportissue`、終端機指令和腳本擴充功能不使用它：它們只用你輸入的內容，選取的文字保持原樣。最多 5000 個字元；處於安全輸入狀態時或在終端機中絕不讀取。若在某個 App 中運作不正常，請到 Settings → General →「Use the selected text」（使用選取的文字）關閉。

### 修改結果（新）

`@improve`、提示詞指令（你自己的或外掛程式的）或改寫選取文字的結果出現時，直接輸入想怎麼改，例如 `shorter`、`warmer`、`more formal`、`add a joke`、`in Japanese` 或 `用更口语的说法`（可以打拼音，輕按 Shift 切換語言），然後按 ⇧⏎：結果會連同你的要求再次送給 AI，新的結果在同一個候選視窗中取代舊的。按 ⏎ 會插入選取的結果，要求只打了一半時也一樣（打的內容會捨棄）。想改幾次都可以；候選視窗最上面一行列出修改過的步驟（「Refined: shorter · more formal」），你隨時都能照常選取某一列。輸入一個字母就開始寫要求（在候選視窗頂端顯示為「refine › …」）；要求還是空的時候，數字鍵、Space 和 ⏎ 照常選取，⇧⏎ 則照你輸入的原樣插入。結果全部出現後才能修改：第一批結果還在陸續出現時輸入，和以前一樣是接著寫這個句子。修改進行中也可以先輸入下一個要求；修改會繼續進行，結果出來後按 ⇧⏎ 就執行下一個。Esc 會先清除要求，再退回上一步、回到最後一次修改之前的結果（修改進行中則是停止它），然後回到句子；在空白行上按 ⌫ 也會以同樣方式退回。對選取的文字使用時，你挑選的結果仍然只會取代選取的文字，在那之前文字保持不動。修改失敗（或在安全輸入狀態時被拒絕）時，結果保持原樣，要求也還在，按 ⇧⏎ 可再試一次。對同樣的結果做同樣的修改，會直接用快取回答。`@translate` 沒有修改功能：結果出現後輸入是接著寫這個句子，按 ⏎ 重新翻譯。

### 與 @question 對話（新）

`@question` 回答之後，你接著輸入的就是下一個問題：按 ⇧⏎ 會連同之前的問答一起提問，候選視窗隨之長成一段對話，前面幾輪以淡色的 Q / A 列顯示，最新的答案在它們下方。最上面一行顯示接下來是第幾輪（「question 2/5 › …」）。每個答案都能插入：按它的數字（1–5）、↑↓ 再按 ⏎，或按一下；預設選取最新的，⌘C 拷貝選取的那個。問題只打了一半時按 ⏎ 也會插入答案（打的內容會捨棄）。Esc 會先清除你輸入的內容，再退回上一輪；在第一輪時就和以前一樣離開。候選視窗最多長到約半個螢幕高，之後改為捲動，最新的在最下面。

5 輪之後（設定檔中的 `questionRounds`，2–10），下一個問題的那一行會變成「5 rounds in: continue in Claude or another AI」（已聊 5 輪：到 Claude 或其他 AI 接著聊），選項依 ⌘1、⌘2… 編號；任何一輪按 ⌘⏎ 都能顯示這些選項（答案還在出現時按它不做任何事，也絕不會傳給 App）。這時你輸入的內容就是到那邊的第一則訊息；只有 ⌘1、⌘2… 會送出它（⇧⏎ 不再提問，也不打開任何東西）。對選取文字提出的問題會把那段文字一起帶過去，作為獨立的引用區塊。可選的有：

- **Claude Code**（已安裝 `claude` 指令時）：在 Terminal 中開啟一個互動式工作階段，開頭是這段對話和「Let's continue this discussion」。
- 網頁版 **Claude** 或 **ChatGPT**，對話已經填好（太長時會放到剪貼簿：貼上即可）。
- 網頁版 **Gemini**，對話在剪貼簿中，貼上即可。
- **Copy the conversation**（拷貝對話），Markdown 格式（**Q:** / **A:**）。

要列出哪些、依什麼順序（第一個為預設）：Settings → General →「Continue a conversation in」（對話接著在哪裡聊；設定檔中的 `questionContinueIn`）。使用這台 Mac 的 Apple Intelligence 時，長對話放不進它很小的上下文：會先縮短最早的答案，再略去最早的幾輪，候選視窗會顯示「earlier rounds shortened」（前面幾輪已縮短）。對話會以第一個問題存在最近的問題中，選取它就會顯示各輪內容，讓你接著聊。

### 最近的問題（新）

`@question` 後面沒有輸入任何內容時，會列出你最近的 5 個問題，最新的在前，並註明提問時間（「3 hours ago」）。接著輸入就能篩選：每個字詞出現在問題中任何位置都算，不分大小寫（不含空格的中文也可以）。按數字鍵、↑↓ 再按 ⏎，或按一下，會立刻顯示該問題已儲存的答案，不需連網：Space 或 ⏎ 插入，⌘C 拷貝，⌘R 重新提問以取得新的答案（對話則是重新提出最後一個問題），Esc 回到清單。已儲存的對話會顯示所有輪次：接著輸入就能繼續聊。沒有符合的項目，或沒有選取任何項目時，⏎ 會提出你輸入的問題。同一個問題有了新答案，或對話又繼續聊下去，就會取代已儲存的那個。

- 它們只存放在這台 Mac 上（見「隱私」）：處於安全輸入狀態時不存，對選取文字提出的問題一律不存。
- Settings → General →「Remember recent questions」（記住最近的問題）可以關閉此功能並刪除它們（設定檔中的 `rememberQuestions`）；「Clear (N)」（清除）會刪除它們。在設定中關閉會刪除已儲存的問題；用 @config 關閉則會保留它們（Settings → General → Clear 會刪除它們）。

### 備忘錄與提醒事項

`@note` 會建立一則新備忘錄；第一行是標題。拷貝一段文字後，在 `@note ` 後面按 ⌃V（在終端機以外也可按 ⌘V），即可連同換行一起儲存，換行在指令中顯示為 ↵。如果含換行的備忘錄還沒儲存，你就離開了文字欄位（按一下其他地方、切換 App）或按了 ⇧⏎（照輸入內容插入），它不會被輸入到 App 中（在終端機裡，每一行都會被當成指令執行），而是放到剪貼簿（「The note wasn't saved; its text is on the clipboard」）。只有一行的備忘錄則照輸入內容插入。

`@reminder` 能解析 `tomorrow at 3pm`、`in 2 hours`、`in 3 days at 3pm`、`on the 15th`、`this weekend`、`in 1 month`、`next month`（該月 1 日）、`end of the year` 這類時間（中文的時間寫法也可以）。日期和時間可以分開寫（`tomorrow call Bob at 5`）；一週從星期一開始。沒寫上午或下午的時間（`at 5`）取接下來最近的那一個，且絕不會落在午夜到早上 6 點之間；今天已經過了的時間算明天，但仍在進行中的時段（`this afternoon`、`tonight`）算今天、整天；今年已經過了的日期算明年。寫成重複的（`standup every Monday at 9`）只會加入一次，設在下一次：這些字留在標題中，該列顯示「once only」（僅一次）。確認用的那一列會顯示解析出的時間，例如「tomorrow 3:00 PM」（依照 Mac 的 12／24 小時制設定）；若不對，按 Esc 回到文字。文字中沒有時間或日期時，就不設時間（「no date」）。

在這兩個指令中，`@stock` 之類的指令不會執行：文字照寫的內容儲存（在其中輸入 `@` 也不會開啟指令清單）。第一次使用時，macOS 會詢問是否允許 AllInOneIME 控制 Notes（`@note`）或取用 Reminders（`@reminder`）：請允許。如果當時沒有允許，請到 System Settings → Privacy & Security → Automation（系統設定 → 隱私權與安全性 → 自動化）（Notes）或 → Reminders 中允許 AllInOneIME。儲存失敗時（例如沒有權限），通知會說明原因，文字也會回到指令中，讓你修正後再送出；如果你得先處理某件事（權限、帳號），文字也會放到剪貼簿（前往 System Settings 會讓文字欄位失去焦點）。如果你已經移到另一個文字欄位，或正在輸入其他內容，文字則改為放到剪貼簿（「Not saved; the text is on the clipboard.」）。

### 自訂指令

在設定的「Custom @ Commands」（自訂 @ 指令）下，按一下「Add Command…」（新增指令…）：取個名稱並選擇它做什麼（AI 指示、程式、在 Terminal 中執行的程式，或網頁），或從範例開始。你的指令排在內建指令之後；名稱只能用英文字母，且不能和內建指令同名；從下一句起生效。它們存放在設定檔（`~/.config/allinoneime/config.json`）的 `customCommands` 中，你也可以直接編輯：

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | 作用 |
|---|---|
| `prompt` | 以 `prompt` 為指示送到 AI；答案出現在候選中，可插入或拷貝（⌘C） |
| `run` | 在背景執行 `argv`；它印出的內容出現在候選中（多行會照印出的樣子插入，在終端機中則合併成一行）。出錯時顯示它的最後一行 |
| `terminal` | 在新的 Terminal 視窗中執行 `argv`；不插入任何內容 |
| `link` | 把文字放進網址 `url`，並在預設瀏覽器中開啟；不插入任何內容 |

- `{input}` 會換成你在指令後面寫的內容，而且永遠只留在它所在的那一個引數裡：不經過 shell。需要 shell 時請明確指定，如上面的 `sh`（`zsh -c`）。
- `stdin`：送到程式標準輸入的內容，其中的 `{input}` 也會被替換。
- `link` 的 `url` 必須是 `https://`，`{input}` 只出現一次，且在 `?` 或 `#` 之後；文字會經過編碼（空格是 `%20`，換行是 `%0A`），最多 4000 個字元。
- `run` 和 `terminal` 預設以英文字母輸入（和 `@open` 一樣；在中文模式下，之後會切回中文），全形標點會轉成 ASCII。設定 `"ascii": false` 即可保留輸入的原樣。
- 程式在你的個人專屬資料夾中執行，使用你登入 shell 的 PATH（因此找得到透過 Homebrew、pyenv 和 nvm 安裝的程式）。`run` 會在 10 秒後（`timeoutSeconds`）或輸出過多時停止程式；隨時可按 Esc 停止。
- `summary` 是指令清單中的說明（選填）。
- 找不到 `argv` 中的程式時（例如沒有 `python3`），不會提供該指令，`@python …` 會當作文字插入；安裝之後，下一個文字欄位就會出現該指令。

`run` 和 `terminal` 會在你的 Mac 上執行程式碼：只加入你自己寫、且信任的指令。它們同樣只在你按下執行鍵時才執行，且絕不在安全輸入期間執行。

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

Raycast 的模式對應如下：`fullOutput` → `show`，`compact` 和 `silent` → `silent`，搭配 `refreshTime` 的 `inline` → 狀態。完整的協定請見 [docs/extensions.md](../extensions.md)；[Examples/extensions](../../Examples/extensions) 中每種各有一個範例。擴充功能會在你的 Mac 上執行程式碼：請使用你信任的。它們只在你執行時才執行（狀態或清單則在你輸入時執行），絕不在安全輸入期間執行，並會在輸入法結束時停止。

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

外掛程式是現成的 `@` 指令，用於不是每個人都需要的功能，例如用 `@stock AAPL 600519 700` 查詢股價。安裝後，它們和其他指令一樣使用；設定中的「Plugins」（外掛程式）會顯示已安裝的外掛程式、各自把你的文字送到哪裡，並可移除它們。外掛程式是在獨立行程中執行的 JavaScript：它們只能連到自己宣告的網站（HTTPS），無法讀取檔案或執行其他程式。設定中「Plugins」下的「Browse Library…」（瀏覽程式庫…）可從[外掛程式庫](https://github.com/MicroZ-LLC/AllInOneIME-plugins)安裝外掛程式：安裝前會顯示外掛程式會連到哪些網站；程式庫的索引經過簽署，每個檔案都必須與索引相符。有新版本時會顯示「Update」（更新）按鈕；不會自動更新任何東西。你自己的外掛程式放在 `~/.config/allinoneime/plugins/`（「Open Plugins Folder」，打開外掛程式資料夾）：這些是本機外掛程式，絕不會被程式庫覆寫。「Link」（連結）外掛程式不執行任何程式碼：它們把文字放進網址並在瀏覽器中開啟，例如 `@x nice weather today` 會開啟 X 的撰文畫面並填好文字；要不要發佈由你在頁面上決定。程式庫中有四個（`@x`、`@threads`、`@bsky`、`@weibo`）。`@xe` 換算貨幣：`@xe 100 USD CNY`、`@xe 1000 JPY EUR`，結果為一行，附上匯率日期（匯率來自 ExchangeRate-API）。撰寫外掛程式：[docs/plugins.md](../plugins.md)。

會擷取資料的指令（外掛程式和程式）也能在句子中使用：`@reply tell her @stock AAPL is up today`。內層的指令先執行，它們的輸出取代它們原本的位置，外層的指令再處理結果。引數是指令後面的那個詞，加上緊接其後的大寫代碼或數字（`@stock AAPL TSLA`、`@stock 600519 700`）；遇到小寫的詞就結束（`@stock SNDK is good to buy` 查詢的是 SNDK）。引號可以精確標出引數：`@stock "aapl tsla"`。`@calculate` 也能在句子中使用；它的引數是後面的整個運算式，包括空格，直到其他文字為止：`@reply the total is @calculate 23 * 17 dollars`。在 `@claude` 和終端機指令中，它們不會執行：這些指令收到的是照寫的文字（在其中輸入 `@` 也不會開啟指令清單）。

### 執行鍵

預設為 ⏎；可在設定的「Action key」（執行鍵）下更改（設定檔中的 `actionKey`）：⏎、「Tap ⌥」（輕按 ⌥，左右皆可：按下後立刻放開；按住右側 ⌥ 仍是用來說話）、⌥Space，或 Space（選好字詞後再按一次 Space；英文模式下按兩次）。無論執行鍵設為什麼，@ 指令也都能用 ⏎ 執行。如果 ⌥Space 已經是 Alfred、Raycast 之類工具的快速鍵，會先被它們接收。

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
| 這個 App 中不使用 AI | `@improve`、`@translate`、`@question`、`@claude` 和你的提示詞指令在那裡不送出任何內容，並會提示；打字和其他指令照常運作 | `noAI` |

「Add App…」（加入 App）會列出你最近打過字的 App，或在 /Applications 中挑選一個。輸入選單中的「This App: <名稱>」提供正在打字的 App 的快速開關（No AI、Type Results Out、一開始的語言）。設定檔中它們位於 `appProfiles` 之下，依 bundle ID 區分：`"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`。bundle ID 比對時不分大小寫（`com.apple.Mail` 就是 Mail 的 `com.apple.mail`）。`@reportissue` 只計算設定了內容的 App 數量，絕不寫出它們的名稱。

- 一開始的語言和預設輸入語言的運作方式一樣：文字欄位啟用時採用它，之後用 Shift 切換的語言會在該 App 的欄位中保持，直到設定改變為止。
- 開啟 No AI 時，AI 指令仍然留在 @ 清單中；執行時會顯示提示，並保留你寫的內容。你自己的終端機指令（`"type": "terminal"`）執行的是程式而不是 AI，所以在那裡照樣能用。

### 用描述的方式修改設定（新）

`@config` 把一句話變成設定：`@config output languages English and French`、`@config 微信里用中文，邮件里语气正式一点`、`@config candidates in a column`、`@config turn off the typos`、`@config use Claude`。按 ⏎ 會在候選視窗中列出要改的地方，一項一列，原本 → 改為，使用設定中的名稱（「Translation languages: English, Japanese → English, French」、「Apps · WeChat · Starts in: Same as everywhere → Chinese」）；這時還沒有改動或輸入任何東西。⏎（或 1）全部套用，Esc 取消，接著輸入再按 ⇧⏎ 可以調整提議（「也加德文」；什麼都沒輸入時按 ⇧⏎ 不做任何事，⏎ 則套用目前顯示的提議）。套用之後，在確認訊息還顯示時按 ⌘Z，或在接下來 10 分鐘內輸入 `@config undo`，就能把這些設定恢復成原本的值。

- **可以修改的：** 翻譯語言和輸入語言（以及預設的那一種）、改寫風格、候選排列、逐字輸出結果（開關、速度、時快時慢、打錯再改）、使用選取的文字、記住問題、隱藏敏感資訊（開關、隱藏哪些、要加入的詞）、檢查更新、依 App 設定（App 用你稱呼它的名字，依名稱或 bundle ID 在你的 App 中尋找），以及 AI 供應商：用哪一個、Bedrock 的設定檔（來自 `~/.aws`）和區域、App 知道適用於它的模型，以及相容 OpenAI 服務的 Base URL（僅限 `https://`）。
- **絕不碰的：** API 金鑰和鑰匙圈中的任何東西、自訂指令、擴充功能資料夾和來源、外掛程式、術語表、任何會執行程式的東西，以及其他所有設定。這些列會被拒絕並註明原因，其餘的仍可套用。
- **和設定中一樣檢查：** 不是語言的語言、超過 5 種翻譯語言、超出範圍的值、無法辨認的 App，或語言套件尚未安裝的語言（「needs the Korean language pack: download it in Settings → Input」，即需要韓文語言套件，請在 Settings → Input 中下載）都會逐列拒絕；絕不會寫入無效的設定檔。
- **金鑰：** 需要金鑰的供應商會多一列「API key: enter it in Settings (never sent to the AI)」（API 金鑰：請在設定中輸入，絕不會送給 AI）：套用時會打開 Settings → AI Provider 並停在金鑰欄位。句子中輸入的金鑰會在送出任何內容之前去除。換了供應商之後會執行 Test Connection，結果顯示在確認訊息下方。
- **先用本機：** 只要這台 Mac 有 Apple Intelligence（macOS 26）就使用它，不論你選了哪個供應商，甚至在還沒設定任何供應商之前也一樣；它只能提出允許的設定和值，並能查詢你的 App、AWS 設定檔和語言套件。沒有的話，由你的供應商回答。請求中只有允許的設定及其目前的值（絕不包含金鑰，也不包含你要隱藏的詞），隱藏敏感資訊也和其他請求一樣適用。

### 檢查你的設定（新）

`@doctor` 按 ⏎ 會在一兩秒內檢查這台 Mac 上的設定（執行時會顯示連線測試），並在候選視窗中列出結果，一項一列，✗ 問題在前，接著是 ⚠ 警告，最後是 ✓ 正常的項目，每項附上簡短的修正方式：輸入法（是否安裝、啟用、在你的輸入方式中）、AI 供應商（金鑰是否已儲存，或 Bedrock 設定檔的憑證是否找得到，絕不讀出或顯示；Test Connection；Apple Intelligence）、權限（輔助使用、你聽寫時用的麥克風、控制備忘錄、提醒事項、Terminal 和訊息，向 macOS 查詢時不會跳出詢問）、安全輸入、你的輸入語言的語言套件、`config.json`（能否讀取、不認得的鍵、超出範圍的值、重複的語言、超過 5 種翻譯語言）、沒有載入的擴充功能和外掛程式、更新，以及 App 自己記錄檔中最近的錯誤。

有修正方式的列會編號：按數字（或按一下）會在 `@config` 的預覽中顯示它要做什麼，按 ⏎ 套用；在清單上按 ⏎ 會一次修正所有可安全修正的項目（修復設定、移除重複的語言、重新啟用輸入法）。打開系統設定的某個面板、下載語言套件、Check for Updates（會打開設定）以及設定中的金鑰欄位，都要逐項選取。設定的變更可以像 `@config` 的一樣還原（⌘Z、`@config undo`）。任何修正都不會刪除你的資料，也不會碰金鑰。

`@doctor <question>`（`@doctor why doesn't translate work`）會先執行檢查，再由 AI 根據檢查結果解釋可能的原因，並標出它建議的修正（⏎ 仍然只套用可安全修正的項目；其他的按編號修正）。在設為 No AI 的 App 中，檢查照樣執行，只有提問會被拒絕。這台 Mac 有 Apple Intelligence 時就用它，它會把需要的檢查當作工具呼叫；否則用你的供應商，候選視窗會註明。送出的只有檢查結果（路徑只到 `~` 為止、沒有金鑰、沒有你輸入的文字）和你的問題；單獨執行檢查時，除了 Test Connection 的那一次請求（只在供應商有金鑰或憑證可測試時）之外，什麼都不送出。

## 選單列面板

<img src="../en/panel-swipe.png" width="520" alt="選單列面板：毛玻璃質感，備忘錄、提醒事項和 Claude 任務顯示在卡片上；向左滑動的一列顯示出「Remove」按鈕">

按一下選單列中的 AllInOneIME 圖像（∞ 加游標的標誌，沒有外框；有外框的那個是輸入方式），面板就會在它下方展開；按一下其他地方即可關閉：

- Notes（備忘錄）：用 `@note` 儲存的備忘錄，最新的 5 則；按一下即可在 Notes 中開啟。
- Reminders（提醒事項）：Reminders 中 AllInOneIME 列表裡尚未完成的提醒事項（`@reminder` 就是加到這個列表），最快到期的排在前面，顯示 8 則；按一下圓圈即可勾選完成，按一下標題則開啟 Reminders。
- Claude Tasks（Claude 任務）：和 `@tasks` 一樣，是背景中的 Claude 任務（`@claude` 交出去的工作），最多 30 個，一次顯示 5 個：捲動可看更多，或在搜尋框中搜尋它們的標題和回覆；附有進度，以及最後一則回覆的第一行；按一下即可在 Terminal 中開啟並繼續。

用兩指把某一列（備忘錄、提醒事項或任務）向左滑動，會顯示它的「Remove」（移除）按鈕，一路滑到底則直接移除；使用滑鼠時，按右鍵即可。移除只會把它從面板上拿掉：備忘錄仍留在 Notes 中，提醒事項仍在 Reminders 中（不會標為完成），任務仍在 Claude Code 中。

標題列顯示數量（例如「2 reminders · 1 task running」；等你回應的任務另外計算，例如「1 waiting for you」）和一個重新整理按鈕。它絕不會搶走你正在輸入的 App 的焦點：勾選提醒事項或重新整理時，那個 App 仍留在最前面；只有 Claude 任務的搜尋框在被按一下之後，才會接收鍵盤輸入。圖像預設會顯示；可在設定的「Menu Bar Panel」（選單列面板）下關閉。

它讀取什麼、何時讀取：

- Notes：清單是面板自己的紀錄（面板關閉時也會保留），而且絕不會啟動 Notes：只有在 Notes 已經在執行、且 AllInOneIME 先前已獲准控制它時，面板才會檢查其中被修改的標題和被刪除的備忘錄。
- Reminders：面板展開時、每 60 秒，以及提醒事項變更時，會讀取 AllInOneIME 列表。面板絕不會自行讓 macOS 要求存取權限：如果 macOS 還沒問過你，它會顯示「Allow Access to Reminders」（允許取用提醒事項），只有按下這個按鈕才會詢問；如果你拒絕了，它會顯示「Open System Settings」（打開系統設定）。
- Claude 任務：面板只在展開時執行 `claude agents`：展開時一次、按重新整理時、`@claude` 交出任務時；以及有任務尚未完成時每 15 秒一次，全部完成後就不再執行。最後的回覆讀取自這台 Mac 上 Claude Code 的對話紀錄結尾（`~/.claude/projects`），而且只在對話紀錄有變更時才讀取。
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
- **Translate (@translate)**（翻譯）：加入要翻譯成的語言（西班牙文、法文、德文、日文、韓文、中文、印地文、孟加拉文、坦米爾文及其他主要印度語言…），並拖曳排序。以拉丁字母輸入的印地文（「aap kaise ho」）會以天城文傳回。`@translate` 依這個順序，每種語言寫一行（只有一種時提供三個版本）；句子本身的語言會略過。新安裝時，會翻譯成 Mac 偏好語言中第一個不是英文的語言；如果只有英文，`@translate` 會開啟這個頁面讓你加入語言。
- **Keyboard layouts**（鍵盤配置）：法文以它卡片上選擇的配置輸入（設定檔中的 `keyboardLayouts`）。其他語言在輸入法之下，macOS 會沿用你最後使用的拉丁字母配置（AZERTY、QWERTZ、西班牙文、美式國際…），所以你可以照常打字，`@` 也在你的配置原本的位置，靜音鍵在指令的文字中同樣能組字（⌥E 再按 E → é，^ 再按 e → ê）。沒有拉丁字母的配置（俄文、印地文 InScript）無法在輸入法之下使用：請用 ⌃Space 切換過去，或把文字貼上（⌃V）或聽寫進指令中。
- `@improve` 只潤飾和改寫，不翻譯；`@translate @improve` 一起使用時，一次請求就能翻譯並改寫。在設定中開啟「@improve also translates」，`@improve` 就會一律這樣做。

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

## 語音輸入

<img src="../en/voice.png" width="340" alt="按住右側 ⌥ 說話">

按住右側 ⌥ 說話；放開後，文字就會插入。辨識的語言是你正在輸入的語言（英文、中文、法文、韓文或印地文）。如果你先輸入指令（例如 `@improve `、`@question `）再說話，文字會接在指令後面，按 ⏎ 即執行；你也可以不放開右側 ⌥ 直接按 ⏎，一說完就執行。語音由 macOS 內建的語音辨識（SpeechAnalyzer）在 Mac 上辨識，不會上傳任何音訊；需要 macOS 26 或更新版本。

第一次使用時：

- macOS 會詢問是否允許 AllInOneIME 使用麥克風。你也可以事先在設定中按一下「Allow Microphone」（允許麥克風）。
- 如果這台 Mac 還沒有該語言的語音模型，會自動下載一次。你也可以在設定中下載。

按住按鍵約 0.2 秒後才開始錄音，所以輕按一下右側 ⌥ 不會開啟麥克風（執行鍵設為「Tap ⌥」時，輕按會執行動作）。如果按住時又按了其他鍵（⌥ 快速鍵、⌥←），會被視為快速鍵，同樣不會錄音。錄音時按下任何其他鍵，都會取消錄音。

## 安裝

執行需要 macOS 14 或更新版本，語音輸入需要 macOS 26 或更新版本。安裝程式是通用版本：可在搭載 Apple 晶片和 Intel 的 Mac 上執行。目前只在搭載 Apple 晶片的 macOS 27 上測試過（Intel 版本只在 Rosetta 下通過了自我測試）。

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

建置需要 Xcode 26 或更新版本，因為語音輸入使用 macOS 26 SDK。

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` 會下載並驗證 librime 和 rime-ice 詞庫，進行建置，並安裝到相同的位置，同樣把它加入你的輸入方式。它安裝的 App 不含中文詞庫（詞庫屬於中文語言包）：原本裝有詞庫的安裝會把它們保留為語言包；否則 `make install-pack` 會從原始碼中的詞庫安裝語言包，不需要下載。`make status` 會顯示已安裝的版本（`version:`），以及它是否在你的輸入方式中（`listed:`）。解除安裝：`make uninstall`。

## 設定 AI

翻譯和改寫使用你自己的 AI 供應商，費用由你的帳號支付：預設是你 AWS 帳號中的 Amazon Bedrock，也可以用 Claude API、Gemini 或與 OpenAI 相容的服務（見下方「其他 AI 供應商」）。

### Amazon Bedrock

1. 在 AWS 主控台中啟用 Bedrock，並確認你能使用選定的模型。預設是 Claude Haiku 4.5；第一次使用 Anthropic 的模型時，需要填寫一次使用案例表單。
2. 建立一組具有 `bedrock:InvokeModelWithResponseStream` 權限的存取金鑰，並放進 `~/.aws/credentials` 中的某個設定檔（profile）。目前只支援這種靜態金鑰，不支援 SSO 或 assume-role。
3. 打開「AllInOneIME Settings」：你可以在 Spotlight 或「應用程式」中找到它，或從選單列中輸入法的圖像 →「Settings…」（設定…）打開。選擇設定檔、區域和模型，然後按一下「Test Connection」（測試連線）。設定視窗頂端的「Language」（語言）可以是英文或中文；預設（「System」）跟隨系統（系統偏好語言中中文排在英文前面時為中文，否則為英文）。設定視窗、候選視窗中的提示和輸入選單都會跟隨這項設定。

<img src="../en/settings.png" width="420" alt="設定視窗">

### 其他 AI 供應商：Claude API、Gemini、與 OpenAI 相容的服務

你不需要 AWS：在設定的「AI Provider」（AI 供應商）下選一個，貼上 API 金鑰，按一下「Save」（儲存），再按「Test Connection」。

| 供應商 | 預設模型 | API 金鑰 |
|---|---|---|
| Claude API | `claude-haiku-5-5`（最快、最便宜；Sonnet 5.5 和 Opus 5.5 較周到，但較慢也較貴） | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| 與 OpenAI 相容 | OpenAI 的 `gpt-6-luna`（或 `gpt-5.4-mini`）；「Common Services…」（常用服務…）中有 DeepSeek、Qwen、Kimi、Zhipu GLM、SiliconFlow、OpenRouter，以及這台 Mac 上的 Ollama：選擇其中一個會填入它的 Base URL，再輸入它的模型 | 該服務的金鑰；把 Base URL 設為它的位址，例如 `https://api.deepseek.com/v1`，或這台 Mac 上 Ollama 的 `http://localhost:11434/v1` |

- API 金鑰保存在系統鑰匙圈中，絕不會寫進設定檔。鑰匙圈中沒有金鑰時，會使用你 shell 中的 `ANTHROPIC_API_KEY`、`GEMINI_API_KEY`（或 `GOOGLE_API_KEY`）和 `OPENAI_API_KEY`。
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
- 它能辨識有固定格式的值；無法辨識人名或地址，請把它們加為你自己的字詞。`@claude`、從網站擷取資料（`@stock`）或開啟網站（`@x`）的外掛程式，以及腳本擴充功能，會照原樣送出文字。詳見「隱私」。
- 設定檔中：`"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`。

所有設定都存放在 `~/.config/allinoneime/config.json`；變更後，下一次翻譯就會使用新設定，不需要重新啟動。較新的鍵：

| 鍵 | 作用 | 預設值 |
|---|---|---|
| `inputLanguages` | 輸入語言，一到五種，第一種是預設：`"en"` 英文、`"zh"` 中文（拼音）、`"fr"` 法文、`"ko"` 韓文、`"hi"` 印地文，例如 `["en", "zh"]`、`["fr", "en", "ko"]`。中文、韓文和印地文要在安裝語言包後才能使用 | `["en"]`（新安裝） |
| `keyboardLayouts` | 輸入語言所用的鍵盤配置，以語言代碼指定（目前只有法文）：`{"fr": "com.apple.keylayout.French-PC"}` | 法文：`com.apple.keylayout.French`（AZERTY） |
| `outputLanguages` | `@translate` 要翻譯成的語言，依序排列：`["es", "fr", "de"]`… | `["en"]` |
| `improveTranslates` | `@improve` 同時翻譯（等同 `@translate @improve`） | `false` |
| `voiceInput` | 按住右側 ⌥ 說話 | `true` |
| `actionKey` | 執行鍵：`"enter"`（⏎）、`"optionTap"`（Tap ⌥）、`"optionSpace"`（⌥Space）、`"space"`（Space） | `"enter"` |
| `uiLanguage` | 介面語言（設定視窗、候選視窗提示、選單）：`"zh"`、`"en"` | `null`（跟隨系統） |
| `rewriteStyles` | 改寫風格：`polish`、`concise`、`formal`、`casual`、`tactful`、`jargon`，例如 `["polish", "concise", "jargon"]` | Polish、Concise、Formal |
| `jargonFile` | 你自己的 Jargon 術語表檔案 | `null`（即 `~/.config/allinoneime/jargon.txt`） |
| `menuBarIcon` | 選單列圖像及其下拉面板 | `true` |
| `candidateLayout` | 拼音和印地文的候選字詞：`"vertical"`（上下排列）或 `"horizontal"`（橫向並排；← → 選取，↑↓ 翻頁） | `"horizontal"` |
| `fuzzyPinyin` | 模糊拼音配對：`["z-zh", "n-l", "in-ing"]`（z-zh、c-ch、s-sh、n-l、f-h、r-l、an-ang、en-eng、in-ing、ian-iang、uan-uang） | `[]` |
| `useSelection` | @ 指令處理欄位中選取的文字（見「對選取的文字使用指令」） | `true` |
| `checkForUpdates` | 每天在背景檢查一次新版本；你沒按下之前不會安裝任何東西 | `true` |
| `rememberQuestions` | 在這台 Mac 上保留你最近 5 個 `@question` 問題和答案，列在 `@question` 下方（見「最近的問題」） | `true` |
| `questionRounds` | `@question` 對話在候選視窗中進行幾輪後，建議到別處接著聊，2–10 | `5` |
| `questionContinueIn` | `@question` 對話可以在哪裡接著聊，依序排列，第一個為預設：`claudeCode`、`claudeWeb`、`chatgpt`、`gemini`、`copy` | Claude Code（若已安裝）、Claude、ChatGPT、拷貝 |
| `appProfiles` | 單一 App 的設定，依 bundle ID，每一項都是選擇性的：`inputLanguage`、`rewriteStyles`、`typeOut`、`noAI`（見「依 App 設定」） | `{}` |
| `redaction` | 對 AI 隱藏敏感資訊（見「隱私」）：`{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`；每種偵測（`emails`、`phones`、`cards`、`keys`、`ips`）除非設為 `false`，否則都開啟 | `enabled: false` |

## 隱私

- 打字（英文和拼音）以及 `@calculate` 的計算完全在本機進行。只有在 `@improve`、`@translate` 或 `@question` 上按下執行鍵時，該句子才會送到你選擇的 AI 供應商（你自己的 Bedrock，或你加入金鑰的服務）。勾選「Jargon」並設定了術語表時，術語表會一併送出。修改結果（在結果出現後輸入要求，再按 ⇧⏎）會再次送出同樣的請求，並附上目前顯示的結果和你的要求；追問（⇧⏎）則會連同到目前為止的對話一起送出。
- `@config` 和 `@doctor <question>` 會把文字送給你的 AI 模型，優先使用裝置上的模型：@config 只送出允許清單中的目前設定（絕不包含金鑰或自訂的詞），@doctor 送出遮蔽過的檢查結果；單獨執行檢查時只送出 Test Connection 的請求。
- 把 `@question` 對話移到別處接著聊（最後一輪之後按 ⌘1…，或按 ⌘⏎）時，會把對話連同你輸入的內容，透過網址或剪貼簿送到你選的服務：這台 Mac 上的 Claude Code（Anthropic）、claude.ai、chatgpt.com 或 gemini.google.com。送出的內容就是你看到的樣子：對 AI 請求隱藏的值（見下文）會原樣包含在內，因為是你選擇把它送到那裡。在你選擇之前不會送到任何地方；「Copy the conversation」只會把它放到剪貼簿。
- 使用 AllInOneIME Cloud 時，句子會經由開發者的伺服器送到模型供應商（目前經由 OpenRouter）：伺服器只保留計數，絕不保留文字。登入只會保留你的電子郵件地址。
- 隱藏敏感資訊（Settings → AI Provider → Privacy，預設關閉）：任何請求送出之前（`@improve`、`@translate`、`@question`、你的提示詞指令和提示詞外掛程式，所有供應商皆然，包括 AllInOneIME Cloud），電子郵件地址、電話號碼、付款卡號（經 Luhn 檢查）、API 金鑰和權杖（`sk-`、`sk-ant-`、`AKIA…`、`ghp_`、`xox…` 和很長的隨機字串）、IP 位址以及你自己的字詞（代號、名字）會先在 Mac 上換成 `[EMAIL_1]`、`[PHONE_1]`、`[ITEM_1]` 這類預留位置；同一個值使用同一個預留位置。模型的結果在顯示或插入之前會換回真實內容，候選視窗會顯示「2 items hidden from the AI」。模型把預留位置改得無法辨認的結果，會照原樣顯示並標上「⚠ placeholder changed」。術語表中含有被隱藏內容的項目不會送出。每一類都能個別關閉。全形寫法（`zhang＠example.com`、`１３８…`）也找得到，值或片語中間換行也可以。它能辨識有固定格式的值，例如電子郵件、號碼和金鑰；無法辨識人名或地址（請把它們加為你自己的字詞），也無法辨識其他字母系統中外形相似的字母。只適用於送往你的 AI 服務的請求；`@claude`、從網站擷取資料（`@stock`）或開啟網站（`@x`）的外掛程式，以及腳本擴充功能，會照原樣送出文字。設定檔中為 `redaction`（`enabled`、`emails`、`phones`、`cards`、`keys`、`ips`、`customWords`）。
- 只有在你按住右側 ⌥ 時才會錄音，並在 Mac 上辨識；辨識出的文字只有在上述指令中、你按下執行鍵時才會送出。
- 輸入法只在你於指令中按 ⌃V 或 ⌘V 時讀取剪貼簿文字一次；密碼管理工具標示為隱藏的內容不會被讀取。文字會先顯示在指令中，同樣只在你按下執行鍵時才會送出。較新的 macOS 版本會詢問是否允許 AllInOneIME 讀取剪貼簿：請允許。若不想每次都被詢問，請在 System Settings → Privacy & Security 中把 AllInOneIME 的貼上權限設為一律允許。
- 在密碼欄位中，macOS 會切換到它自己的鍵盤（U.S. 或 ABC），離開時再切回來。只要你正在輸入的 App 處於安全輸入狀態，AllInOneIME 就不會組字，也無法錄音：按鍵照原樣輸入。而且當系統處於安全輸入狀態時（密碼欄位、Terminal 的 Secure Keyboard Entry（安全鍵盤輸入）等），不會有任何內容送到 AI。
- `@note` 和 `@reminder` 不經過 AI：AllInOneIME 只把文字交給這台 Mac 上的 Notes 和 Reminders，提醒事項的時間也在 Mac 上解析（這些 App 是否把它同步到你的其他裝置，取決於它們的帳號，例如 iCloud）。因此它們在安全輸入期間也能使用。
- `@reportissue`（以及「Report an Issue…」）本身不傳送任何內容：它在瀏覽器中開啟 GitHub 的新 issue 頁面，附上你輸入的標題，以及上面列出的版本、語言、供應商種類和數量，這些會先顯示在候選視窗中。除非你在那裡按一下 Submit，否則不會有任何內容送到 GitHub。
- `@open` 只在這台 Mac 上搜尋。它會記住你用它開啟過的項目（最近 200 個），存放在輸入法自己的偏好設定中（不在 config.json 中），以便把它們排在前面。
- 為了 Settings → Apps 中的「Add App…」，輸入法會在它自己的偏好設定中保留你最近打過字的 12 個 App 的 bundle ID；關於它們的其他資訊一概不保留。
- `@question` 會記住你最近的 5 個問題、答案和提問時間，只存放在這台 Mac 上的 `~/Library/Application Support/AllInOneIME/recent-questions.json`（只有你的使用者帳號能讀取），用來在 `@question` 下方列出；已儲存的答案會從那裡顯示，不需連網。處於安全輸入狀態時不會保留任何內容，對選取文字提出的問題也完全不保留（它們的答案講的是選取的文字，若保留就會把那段文字寫到磁碟上）。Settings → General →「Remember recent questions」可以關閉此功能並刪除它們（設定檔中的 `rememberQuestions`）；「Clear」會刪除它們。
- 為了列出你的備忘錄，選單列面板會在輸入法自己的偏好設定中，保存最近 30 則用 `@note` 儲存的備忘錄的 ID 和第一行（最多 80 個字元），面板關閉時也一樣。
- `@py` 和 `@js` 只在你按下執行鍵時才執行，而且只執行你自己輸入或貼上的程式碼：AI 的答案和其他指令的輸出絕不會被當作程式碼執行。`@py` 使用你 Mac 上的 `python3`，它能像在 Terminal 中一樣讀寫檔案和連上網路；`@js` 在獨立的行程中執行，無法讀取檔案、連上網路或執行其他程式。兩者都不會在安全輸入期間執行。
- 檢查更新：每天一次（除非關閉了「Check for updates automatically」），AllInOneIME 會下載 https://allinoneime.com/update.json 及其簽章；請求中沒有任何識別資訊，也沒有你輸入的內容。只有在你按一下 Update 時，才會從 GitHub release 下載更新。
- 擴充功能來源：git 以你的身分在你的 Mac 上執行，而且只針對你加入的來源：每天為會自動檢查的來源 fetch 一次（固定版本的來源不會），以及你按 Check Now、Update 或 Re-clone 時。它只和儲存庫的主機連線，以你自己的 git 和 SSH 設定登入；你輸入的任何內容都不會隨之送出。
- 記錄檔不會記錄你輸入的內容。對於每個第三方輸入法，macOS 都會警告「The developer can access anything you type with this input source」（開發者可以取用你使用此輸入方式輸入的任何內容）；這是系統的通用警告。

## 開發

```sh
make test         # unit tests, plus tests that run the real Rime engine
make pack         # the Chinese language pack: build/packs/zh-pinyin-<version>.tar.xz, its sha256, its packs.json entry
make packs        # all the language packs: Chinese, and Korean and Hindi from LanguagePacks/ (ko-hangul, hi-phonetic)
make selftest     # drives the input method through a simulated text field: real Bedrock calls, plus on-device recognition tested with synthesized speech
make realtest     # types into a real app's text field (needs the screen unlocked; takes over the foreground for about 1 minute)
make screenshots  # regenerates the screenshots in docs/
make cli && .build/release/allinoneime-cli --styles concise,jargon "this is a blocker bug your team need fix it asap"   # try polishing and rewrites in the terminal
make icon         # regenerates the app icon and the menu bar icon from Resources/AppIcon.png
make dmg          # the release installer, build/AllInOneIME-<version>.dmg (universal; signed if there's a Developer ID certificate, optionally notarized), and the in-app update, build/AllInOneIME-<version>-update.zip
make update-test  # the in-app updater end to end: a temporary install, a test server on 127.0.0.1, a test key (never the installed app)
```

`make selftest` 和 `make realtest` 不受你的設定影響。自我測試使用自己的設定（Amazon Bedrock，沿用你設定中的 AWS 設定檔和區域，其他一律使用預設值）；真實 App 測試在執行期間把供應商設為 Bedrock，結束後再改回你的設定。當下無法檢查的項目會略過，而不是算作失敗：沒有該設定檔憑證時的 Bedrock 即時檢查，以及安全輸入開啟時（螢幕鎖定、密碼欄位）要輸入的一切。最後一行會統計通過、失敗和略過的檢查；只有失敗會讓這次執行失敗，有略過項目的執行會以 INCOMPLETE 結束，若沒有任何會打字的檢查執行則以 SKIPPED 結束（BLOCKED：真實 App 測試在螢幕鎖定時開始），絕不會是 PASSED。

程式碼結構：

- `Sources/AllInOneIMECore`：Bedrock 用戶端、SigV4、提示詞、兩層式輸入狀態機（包括 @ 指令和語音手勢）；不依賴 AppKit
- `Sources/AllInOneIMERime`：librime 包裝層
- `Sources/AllInOneIME`：InputMethodKit 輸入法、候選視窗、設定視窗、語音辨識
- `Sources/AllInOneIMESettings`：「AllInOneIME Settings」啟動器
- `Sources/AllInOneIMEInstaller`：磁碟映像檔中的「Install AllInOneIME」：安裝、更新和解除安裝

語言包有自己的程式庫，與外掛程式分開：儲存庫 [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages)，透過 https://languages.allinoneime.com/ 提供，並以它們自己的金鑰簽署。`make pack` 建置封存檔；它會以發行資產的形式發佈在那裡（發行版本 `zh-pinyin-<version>`、`ko-hangul-<version>`、`hi-phonetic-<version>`），`swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` 會在那裡寫入 `packs.json`，並用鑰匙圈中語言包的金鑰（`allinoneime-languages-signing`）簽署成 `packs.json.sig`。App 會讀取 <https://languages.allinoneime.com/packs.json>，檢查簽章，再檢查封存檔的大小和 SHA-256。要從本機伺服器試用語言包：`--test-key` 會以測試金鑰簽署，再執行 `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`。

發佈新版本（App 內的更新程式會讀取 https://allinoneime.com/update.json，以發佈專用的金鑰簽署）：

1. 提高版本號（`AppVersion.swift` 和三個 Info.plist；`AppVersionTests` 會檢查它們是否一致）並更新更新日誌。
2. `make dmg NOTARY_PROFILE=<profile>`：產生 `build/AllInOneIME-<version>.dmg` 及其 `.sha256`，以及 `build/AllInOneIME-<version>-update.zip`（兩個 App，和磁碟映像檔中的安裝程式所帶的一樣）。App 和映像檔會以鑰匙圈中的 Developer ID Application 憑證簽署，映像檔再以該 `xcrun notarytool` 鑰匙圈設定檔進行公證並裝訂（staple）。
3. 把兩者上傳到 GitHub 的 `v<version>` release 並發佈。
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"`（各一兩句）：寫出 `site/public/update.json`（從 App 讀取的版本、build 和最低 macOS 版本，檔案的位址、大小和 SHA-256，發佈說明的位址和摘要），並用登入鑰匙圈中的金鑰（`allinoneime-releases-signing`；macOS 可能會詢問是否允許存取）簽署成 `update.json.sig`。兩個檔案都要提交。
5. 等 release 的檔案可以下載後，再部署網站（`cd site && npx wrangler@4 deploy`）：App 每天檢查一次，`AllInOneIME --check-update` 會顯示它們看到的內容。

App 在讀取 manifest 之前，會先用內建的公鑰核對它的簽章，絕不安裝不比現在新的版本，只透過 https 從 allinoneime.com 或本儲存庫的 GitHub release 檔案下載，而且只有在封存檔的大小和 SHA-256 與 manifest 相符、兩個 App 的 bundle ID、版本和程式碼簽章都通過檢查、新的輸入法能啟動時，才會安裝。之後輸入法會把工作交給自己的執行檔擔任輔助程式（`--apply-update`），它會等輸入法結束，像安裝程式一樣替換 App（舊的先移到一旁，出錯就放回去），再註冊新的。要用本機伺服器試試：`make update-test`，或使用 `Scripts/build-update-manifest.swift` 的 `--test-key`，再執行 `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`。

Bundle ID 仍是 `com.aipinyin.inputmethod.AIPinyin`：macOS 用它來記住已加入的輸入方式和麥克風權限，所以更改它就得重新加入輸入法並再次授予權限。

## 授權

Copyright © 2026 MicroZ LLC. 原始碼以 [Functional Source License 1.1](../../LICENSE)（FSL-1.1-ALv2）提供：除了開發競爭產品之外，你可以為任何目的使用、閱讀、修改和分享它。每個版本在發行兩年後改為 Apache-2.0。0.6.1 以前（含）的版本以 GPL-3.0 發行，並持續以該授權提供。

第三方元件（librime 及其外掛程式採用 BSD-3-Clause；rime-ice 的 Lua 腳本和中文語言包採用 GPL-3.0）列於 [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)。
