<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · [繁體中文](README_zh-TW.md) · **日本語** · [한국어](README_ko.md) · [Français](README_fr.md) · [Deutsch](README_de.md) · [Español](README_es.md) · [Português (Brasil)](README_pt-BR.md) · [Italiano](README_it.md) · [Русский](README_ru.md) · [Tiếng Việt](README_vi.md) · [ไทย](README_th.md) · [Bahasa Indonesia](README_id.md) · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · [Türkçe](README_tr.md)

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="AllInOneIME のアイコン">

# AllInOneIME

### Mac のあらゆるテキスト欄で、AI コマンドを。

どのアプリでも `@improve`、`@translate`、`@question` と入力して ⏎ を押し、結果を選ぶだけ。<br>
チャット画面へのコピーも、アプリの切り替えも不要。AI プロバイダも API キーも、あなた自身のものを使います。

[![Release](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#インストール)
[![Apple シリコンと Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#インストール)
[![ライセンス：FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![ダウンロード数](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[ダウンロード](https://allinoneime.com/download)** · **[ウェブサイト](https://allinoneime.com)** · **[ドキュメント](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[拡張機能](../extensions.md)**

[使い方](#使い方) · [コマンド](#-コマンドベータ) · [独自のコマンド](#独自のコマンド) · [言語](#入力と翻訳) · [音声](#音声入力) · [インストール](#インストール) · [プライバシー](#プライバシー)

<br>

<img src="../en/demo.png" width="820" alt="@translate と文を入力して ⏎：スペイン語、フランス語、ドイツ語の訳が 1 行ずつ">

</div>

*これは英語版 README の翻訳です。内容に違いがある場合は、英語版が正しいものとします。*

> [!NOTE]
> AllInOneIME はまだ Apple の公証を受けていません。初回は System Settings → Privacy & Security → Open Anyway（システム設定 → プライバシーとセキュリティ → このまま開く）で許可してください。ダウンロードは [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) または [allinoneime.com](https://allinoneime.com) からのみ行ってください。

あらゆるテキスト欄で AI コマンドが使える macOS 用の入力メソッドです。文を `@` で始め、書き終えたら ⏎ を押します。`@improve` は書いた文を整えていくつかの書き換えを提案し、`@translate` は選んだ言語に翻訳し、`@question` は質問をし、`@claude` は Claude Code に引き渡し、`@open` はファイルやアプリを探したり Web アドレスを開いたりします。右 ⌥ を押したまま話すこともできます。`@` を付けなければ、キー入力はいつもどおりアプリに渡ります。中国語（ピンイン。Rime と rime-ice がベース）、フランス語、韓国語（ハングル）、ヒンディー語（ラテン文字からデーヴァナーガリー）も入力でき、自作のスクリプトを @ コマンドとして実行することもできます。

![@improve と大まかな文を入力して ⏎：整えた文と書き換え](../en/improve.png)

詳しい情報（すべてのコマンドと設定、インストール時のトラブルシューティング、プライバシー）は [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki) をご覧ください。作者は MicroZ LLC の [Weijian Zhang](https://weijianz.com) です。

## 使い方

`@` を付けなければ邪魔をしません。英語では文字がそのまま入力され、⏎ は通常の Return です。ネットワークには何も送られません。新規インストール時は英語のみです。中国語（ピンイン）、フランス語、韓国語、ヒンディー語も入力するには、設定で追加します（[入力と翻訳](#入力と翻訳)を参照）。

| キー | 動作 |
|---|---|
| ピンインを入力、Space／数字 | 中国語モード：一般的なピンイン入力メソッドと同じように語を選びます |
| `@`（文の先頭で） | コマンドリストを開きます。最近よく使ったものが先頭で、一度に 5 件、↑↓、ホイール、トラックパッドでスクロールします。文字を入力して探すこともできます（その文字で始まる名前が先、次にその文字を含む名前）。⏎、Tab、Space、数字で選択します |
| ⏎ | コマンドを実行します。ピンインがまだ確定していなくても使えます。Space と同じように先に確定されます |
| Space、⏎／数字 | 結果が表示されたら、ハイライトされた候補／その番号の候補を挿入します。0 は元の文です |
| ⌘C | ハイライトされた結果をコピーします（`@open` ではパス）。候補パネルは開いたままです |
| ⌃V | コマンド内（例：`@improve ` の後）で、クリップボードのテキストをアプリに貼り付ける代わりに、入力した内容の後ろに追加します。複数行は 1 行にまとめられ、一度に最大 2000 文字です（`@note` は改行を保持し、最大 20000 文字）。どのアプリでも使えます。コマンドがなければ、キーはいつもどおりアプリに渡ります |
| ⌘V | ⌃V と同じですが、⌘V を自分で処理するアプリ（Ghostty、iTerm2、Terminal などのターミナルと Notes）では、いつもどおりアプリに貼り付けられます。そうしたアプリでは ⌃V を使ってください |
| Esc、⌫ | 文に戻って編集を続けます。そのまま入力すれば続きを書けます |
| Shift を軽く押す | 入力言語が複数あるとき、順番に次の言語へ切り替えます（英語 → 中国語 → フランス語 → …、最後は最初に戻ります） |
| 右 ⌥ を押し続ける | 話して、離すと終了します。入力中の言語（英語、中国語、フランス語、韓国語、ヒンディー語）で認識されます。コマンド内ではテキストがその後ろに入り、それ以外では直接挿入されます |

## @ コマンド（ベータ）

| コマンド | 動作 |
|---|---|
| `@improve` | 推敲：1–3 は元の文と同じ言語の 3 つのバージョン、4 以降は書き換えスタイル（設定で追加・並べ替え）、0 は元の文です。翻訳はしません。「@improve also translates」（@improve でも翻訳する）をオンにすると、`@translate @improve` と同じ動作になります |
| `@translate` | 追加した言語に翻訳します（設定 →「Translate」、ドラッグで並べ替え）。言語ごとに 1 行、言語が 1 つだけなら 3 つのバージョンです。元の文と同じ言語はスキップされます。`@translate @improve` と続けると、1 回のリクエストで翻訳と書き換えを行います |
| `@question` | 質問します。答えは候補に表示され、⏎ または Space で挿入、⌘C でコピーします |
| `@claude` | タスクを Claude Code に引き渡します。デフォルトではバックグラウンドで実行され、終わると通知が届きます（クリックすると Terminal でそのセッションが開き、続きができます）。`@tasks` でも確認できます。あなた自身の Claude Code（`claude` コマンド）を、そのサインインと設定のまま使います。設定で「@claude runs in the background」（@claude をバックグラウンドで実行）をオフにすると、以前のように Terminal で開きます。初めて Terminal を開くとき、macOS が AllInOneIME による Terminal の制御を許可するか尋ねるので、「OK」をクリックしてください |
| `@tasks` | バックグラウンドの Claude タスク（作業中／完了／あなたの返答待ち）と、それぞれの最後の返信を一覧表示します。⏎ で Terminal で開き、⌘C で返信をコピーします |
| `@settings` | 設定ウインドウをすぐに開きます（選ぶだけで開きます） |
| `@open` | 入力に合わせて、一致するファイル、フォルダ、アプリを一覧表示します（Spotlight）。スペースで区切って複数のキーワードを使えます。それぞれがパスに含まれ、少なくとも 1 つが名前に含まれている必要があります（標準フォルダの名前はその中身にも当てはまります。`downloads pdf` で Downloads（ダウンロード）内の PDF が見つかります）。アプリと標準フォルダは中国語名でも見つかり、中国語インターフェイスではその名前で表示されます。`@open` で開いたものが先頭で、次にアプリとそれらのフォルダ、その次に最近使った、または変更したファイルが続きます。名前で見つかったファイルが 2 つ以下で、該当するアプリやそれらのフォルダがない場合は、ホームフォルダ内のファイルも内容で検索され、その行には「content」（内容）と表示されます。ほかに何もないときは、最初の項目を開く代わりに、⏎ でそれらが一覧表示されて選べます。Web アドレス（`github.com`、`localhost:3000`、`https://…`）を入力すると、最初の行は「open in the browser」（ブラウザで開く）になり、内容は検索されません。ちょうどその名前のファイル（たとえば `MANIFEST.in`）があれば、それが先頭に来ます。`~/` や `/` で始まるテキストはパスです。Tab で補完してフォルダの中へ進み、⏎ で開き、⌘C でパスをコピーします |
| `@note` | テキストを Notes アプリの AllInOneIME というフォルダ（なければ作成）に保存します。何も挿入されません。貼り付けたテキストは改行を保持し、最大 20000 文字です |
| `@reminder` | Reminders アプリの AllInOneIME というリストにリマインダーを追加します。日時はテキストの中に書きます。日時は Mac 上で読み取られ、読み取った結果が 1 行で表示されます。⏎ または Space で追加、Esc で編集に戻ります。時刻があればその時刻に通知され、日付だけなら終日になります |
| `@calculate` | この Mac 上で計算します。結果は候補に表示され、⏎ または Space で挿入します：`@calculate 23*17` → `391`。文の中でも使えます：`@reply the total is @calculate 23*17 dollars` |
| `@py` | Python を 1 行実行し（Mac の `python3`）、結果を挿入します。コードの最後の式の値（例：`@py 2**100`、`@py import math; math.sqrt(2)`）か、それがなければ出力した内容です。`python3` がない場合は表示されません（Xcode のコマンドラインツールに含まれています） |
| `@js` | JavaScript を 1 行実行し、同じように挿入します。最後の式の値か、`console.log` が出力した内容です（例：`@js [1, 2, 3].map(x => x * 2)`）。macOS 内蔵の JavaScriptCore を使うので、インストールは不要です。ファイルの読み取り、ネットワークへのアクセス、ほかのプログラムの実行はできません |
| `@imessage` | iMessage を送ります。名前、電話番号、メールアドレスを入力し（中国語の名前はピンインでも可。フルでも頭文字でも）、候補パネルで宛先を選び（最近メッセージを送った相手が先頭。番号やアドレスをすべて入力しても可）、メッセージを書きます（中に `@stock AAPL` などのコマンドがあれば先に実行されます）。⏎ でパネルに「Send to Alex (…): message」と表示され、もう一度 ⏎ で送信、Esc で編集に戻ります。テキスト欄には何も入力されません。初回は、macOS が AllInOneIME による Contacts（連絡先）へのアクセスと Messages（メッセージ）の制御を許可するか尋ねるので、両方とも「OK」をクリックしてください |

例：`@q` ⏎、`what is quantum computing` と入力して ⏎。`@note books to read: The Three-Body Problem` ⏎ でメモが保存されます。`@reminder call Bob tomorrow at 3pm` ⏎ で読み取った日時を確認し、もう一度 ⏎ で追加します。コマンドを選んだ後は、右 ⌥ を押したまま話すこともできます。中国語モードでは、`@open` と `@calculate` は一時的に英字入力に切り替わり、終わると中国語に戻ります。

`@py` と `@js` のコードは英字で入力し、全角の句読点（中国語モードからのもの）は ASCII になります。1 行で書き、文と文の間は `;` で区切ります。コードは別プロセスで実行され、10 秒で、または Esc でいつでも停止します。エラーのときは、エラーの最初の行が表示されます（例：`ZeroDivisionError: division by zero`）。複数行の出力は出力されたとおりに挿入されますが、ターミナルでは 1 行にまとめて入力されます（ターミナルは渡されたすべての行を実行するため）。エディタ内のターミナル（VS Code、Cursor、JetBrains）はエディタ本体と区別できないため、そこではどのコマンドの複数行の出力もそのまま入力されます。どちらもほかのコマンドの文の中で使えます：`@reply the answer is @py 2**100`。スペースを含むコードは引用符で囲みます：`@question explain @py "sum(x * x for x in range(10))"`。逆はできません。`@py` と `@js` のコードは常に入力したとおりに実行され、その中の `@commands` が先に実行されることはありません。

![@ を入力するとコマンドリストが開く。@question と質問を入力して ⏎ で答え](../en/commands.png)

![@open は入力に合わせてアプリを探す。/ で始めるとパスになり、フォルダの中身が表示され、Tab で補完](../en/open.png)

`@john` のように `@` の後がコマンドでない場合は、`@` がいつもどおり入力されるので、チャットアプリでの @ メンションもそのまま使えます。`@question`、`@improve`、`@translate` があなた自身の Bedrock に送信するのは、実行キーを押したときだけです。`@open` はこの Mac 上だけを検索します。`@note` と `@reminder` が送る先は、この Mac の Notes と Reminders だけです。`@claude` は Mac にインストールされた Claude Code（`claude` コマンド）とそのアカウントを使い、ファイルの変更やコマンドの実行の前には、いつもどおり確認を求めます。Claude Code がインストールされていなければ、`@claude` は表示されません。`@imessage` はこの Mac の Contacts（名前、電話番号、メールアドレス）だけを読み取り、AI を経由することはなく、メッセージは Messages が送信します。Messages アプリがなければ表示されません。

`@calculate` はこの Mac 上でオフラインで動作します。`+ - * /`（`× ÷` も可）、べき乗の `^` または `**`、括弧、パーセント（`50%` は 0.5、`200*5%` は 10。電卓と同じく、足したり引いたりするパーセントはその前の値に対するものです：`100+10%` は 110、`100-10%` は 90）、関数 `sqrt abs round floor ceil ln log exp sin cos tan min max pow`（`log` は常用対数、角度はラジアン、`round(x, 2)` は小数点以下 2 桁）、定数 `pi`（`π`）と `e` が使えます。全角の数字や記号も使えます。計算は 10 進数で正確に行われるので、`0.1+0.2` は `0.3` です。結果は最大 15 桁の有効数字で、38 桁までの整数は省略せずに表示されます（`2^100` → `1267650600228229401496703205376`）。

### メモとリマインダー

`@note` は新しいメモを作成し、最初の行がタイトルになります。テキストをコピーした後、`@note ` の後で ⌃V（ターミナル以外では ⌘V も可）を押すと、改行ごと保存されます。改行はコマンド内で ↵ と表示されます。改行を含むメモが保存される前にテキスト欄を離れたり（ほかの場所をクリック、アプリを切り替え）、⇧⏎（入力したまま挿入）を押したりした場合、そのテキストはアプリに入力されず（ターミナルでは各行がコマンドとして実行されてしまうため）、代わりにクリップボードに入ります（「The note wasn't saved; its text is on the clipboard」）。1 行だけのメモは入力したまま挿入されます。

`@reminder` は `tomorrow at 3pm`、`in 2 hours`、`in 3 days at 3pm`、`on the 15th`、`this weekend`、`in 1 month`、`next month`（その月の 1 日）、`end of the year` のような日時を読み取ります（中国語の日時表現も可）。日付と時刻は離れていてもかまいません（`tomorrow call Bob at 5`）。週は月曜日から始まります。午前・午後のない時刻（`at 5`）は次に来るその時刻で、午前 0 時から午前 6 時の間になることはありません。今日すでに過ぎた時刻は明日になりますが、まだ続いている時間帯（`this afternoon`、`tonight`）は今日の終日になります。今年すでに過ぎた日付は来年になります。繰り返しとして書いたもの（`standup every Monday at 9`）は、次の 1 回分だけ追加されます。その言葉はタイトルに残り、行には「once only」（1 回のみ）と表示されます。確認用の行には読み取った日時が表示されます（例：「tomorrow 3:00 PM」。Mac の 12／24 時間制の設定に従います）。間違っていれば、Esc でテキストに戻ります。日時も日付も含まれていなければ、日時なしになります（「no date」）。

この 2 つの中では、`@stock` などは実行されません。テキストは書いたとおりに保存されます（そこで `@` を入力してもコマンドリストは開きません）。初回は、macOS が AllInOneIME による Notes の制御（`@note`）または Reminders へのアクセス（`@reminder`）を許可するか尋ねるので、許可してください。許可しなかった場合は、System Settings → Privacy & Security → Automation（システム設定 → プライバシーとセキュリティ → オートメーション）（Notes）または → Reminders で AllInOneIME を許可してください。保存に失敗したとき（権限がないなど）は、通知に理由が表示され、テキストがコマンドに戻るので、直してからもう一度送信できます。先に何かを直す必要があるとき（権限、アカウント）は、テキストがクリップボードにも入ります（System Settings に移動するとテキスト欄からフォーカスが外れるため）。すでに別のテキスト欄に移っていたり、別の内容を入力していたりする場合は、代わりにクリップボードに入ります（「Not saved; the text is on the clipboard.」）。

### 独自のコマンド

設定の「Custom @ Commands」（カスタム @ コマンド）で「Add Command…」（コマンドを追加…）をクリックし、名前を付けて動作（AI への指示、プログラム、Terminal で実行するプログラム、Web ページ）を選ぶか、例から始めます。独自のコマンドは組み込みコマンドの後に並びます。名前は英字のみで、組み込みコマンドと同じ名前は使えません。次の文から使えるようになります。コマンドは設定ファイル（`~/.config/allinoneime/config.json`）の `customCommands` に保存され、直接編集することもできます：

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | 動作 |
|---|---|
| `prompt` | `prompt` を指示として AI に送ります。答えは候補に表示され、挿入またはコピー（⌘C）できます |
| `run` | `argv` をバックグラウンドで実行します。出力は候補に表示されます（複数行は出力されたとおりに、ターミナルでは 1 行で挿入）。エラーのときは最後の行が表示されます |
| `terminal` | `argv` を新しい Terminal ウインドウで実行します。何も挿入されません |
| `link` | テキストを Web アドレス `url` に入れて、デフォルトのブラウザで開きます。何も挿入されません |

- `{input}` はコマンドの後に書いた内容に置き換えられ、常にそれが含まれる 1 つの引数の中に収まります。シェルは介在しません。シェルを使う場合は、上の `sh`（`zsh -c`）のように明示します。
- `stdin`：プログラムの標準入力に渡す内容です。ここでも `{input}` が置き換えられます。
- `link` の `url` は `https://` で、`{input}` を 1 回だけ、`?` または `#` の後に含める必要があります。テキストはエンコードされ（スペースは `%20`、改行は `%0A`）、最大 4000 文字です。
- `run` と `terminal` はデフォルトで英字を入力します（`@open` と同じ。中国語モードでは、終わると中国語に戻ります）。全角の句読点は ASCII になります。入力したままにするには `"ascii": false` を設定します。
- プログラムはホームフォルダで、ログインシェルの PATH を使って実行されます（そのため Homebrew、pyenv、nvm でインストールしたものも見つかります）。`run` は 10 秒後（`timeoutSeconds`）、または出力が多すぎるときにプログラムを停止します。Esc でいつでも停止できます。
- `summary` はコマンドリストでの説明です（省略可）。
- `argv` のプログラムが見つからない場合（たとえば `python3` がない）、そのコマンドは表示されず、`@python …` はテキストとして入力されます。インストールすれば、次のテキスト欄からコマンドが表示されます。

`run` と `terminal` は Mac 上でコードを実行します。自分で書いて信頼できるコマンドだけを追加してください。これらも実行キーを押したときにだけ実行され、セキュア入力中には決して実行されません。

### スクリプト拡張機能

独自の @ コマンドをプログラムとして追加できます。どの言語のスクリプトでもよく（bash、Python、Node、Swift など）、コメントに数行のメタデータを書きます。`~/.config/allinoneime/extensions` に置くか、「Settings → Custom Commands → Script Extensions」（設定 → カスタムコマンド → スクリプト拡張機能）で追加したフォルダに置きます。Raycast Script Commands はそのまま動作し、すでにそれらを置いているフォルダは Spotlight で見つかります。

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh` は `@flights` になります。引数はその後にカンマで区切って書きます。`@flights beijing, new york` は `beijing` と `new york` を `$1` と `$2` として実行します（それ以上のカンマは最後の引数に含まれます）。必須の引数が空のときは、実行せずに何が足りないかを表示します。出力は `output` の指定に従って使われます：

| `output` | 動作 |
|---|---|
| `insert`（デフォルト） | 出力全体と、その各行を挿入できます |
| `show` | 出力されるそばからパネルに表示されます（進捗）。何も挿入されません。欄を離れてもバックグラウンドで続きます（同時に最大 4 つ） |
| `list` | Alfred の Script Filter JSON 形式のリストで、入力するたびに再実行されます。行を選ぶと、挿入、オープン（Web アドレス、ファイル、フォルダ。実行されるものは決して開きません）、コピー、または第 2 ステップの実行を行います |
| `silent` | 最後の行をカーソルの近くに表示します。何も挿入されません |

コマンドは、入力を取らない（`input none`：名前の上で ⏎ を押すと実行）、バックグラウンド（`background`）で実行して終わったら通知する（その間はメニューバーパネルに表示）、コマンドリストで名前の横にステータス（`status`）を表示する、先に確認する（`confirm`）こともできます。コマンドは自分のフォルダで、ログインシェルの PATH と `ALLINONEIME_*` 変数（インターフェイスと入力の言語、入力中のアプリ、テキスト）を使って実行されます。**バンドル**は、コマンドを列挙した `extension.json` を含むフォルダです。コマンドはコードと環境設定を共有し、環境設定は設定画面に表示されます（パスワードはキーチェーンに保存）。設定画面にはすべてのコマンドがスイッチ付きで表示され、除外されたスクリプトもその理由とともに表示されます。

Raycast のモードは次のように対応します：`fullOutput` → `show`、`compact` と `silent` → `silent`、`refreshTime` 付きの `inline` → ステータス。プロトコルの全体は [docs/extensions.md](../extensions.md) にあり、[Examples/extensions](../../Examples/extensions) には各種類の例が 1 つずつあります。拡張機能は Mac 上でコードを実行します。信頼できるものを使ってください。拡張機能は実行したときにだけ動き（ステータスやリストは入力中に動きます）、セキュア入力中には決して動かず、入力メソッドの終了とともに停止します。

### プラグイン

プラグインは、誰もが必要とするわけではない機能のための既製の `@` コマンドです。たとえば `@stock AAPL 600519 700` で株価を表示します。インストールすれば、ほかのコマンドと同じように使えます。設定の「Plugins」（プラグイン）には、インストール済みのプラグインと、それぞれがテキストをどこに送るかが表示され、削除もできます。プラグインは別プロセスで実行される JavaScript で、宣言した Web サイト（HTTPS）にしか接続できず、ファイルの読み取りやほかのプログラムの実行はできません。設定の「Plugins」にある「Browse Library…」（ライブラリを参照…）から、[プラグインライブラリ](https://github.com/MicroZ-LLC/AllInOneIME-plugins)のプラグインをインストールできます。インストール前に、プラグインが接続する Web サイトが表示されます。ライブラリのインデックスは署名されており、すべてのファイルがそれと一致する必要があります。新しいバージョンがあると「Update」（アップデート）ボタンが表示されます。自動でアップデートされるものはありません。自作のプラグインは `~/.config/allinoneime/plugins/`（「Open Plugins Folder」、プラグインフォルダを開く）に置きます。これはローカルプラグインで、ライブラリによって上書きされることはありません。「Link」（リンク）プラグインはコードを実行しません。テキストを Web アドレスに入れてブラウザで開くだけです。たとえば `@x nice weather today` は、テキストが入力された状態で X の投稿画面を開きます。投稿するかどうかはページ上であなたが決めます。ライブラリには 4 つあります（`@x`、`@threads`、`@bsky`、`@weibo`）。`@xe` は通貨を換算します：`@xe 100 USD CNY`、`@xe 1000 JPY EUR`。結果はレートの日付付きで 1 行です（レートは ExchangeRate-API による）。プラグインの書き方：[docs/plugins.md](../plugins.md)。

何かを取得するコマンド（プラグインとプログラム）は、文の中でも使えます：`@reply tell her @stock AAPL is up today`。内側のコマンドが先に実行されてその出力に置き換わり、外側のコマンドがその結果を処理します。引数は、コマンドの後の単語と、その直後に続く大文字のコードや数字です（`@stock AAPL TSLA`、`@stock 600519 700`）。小文字の単語で終わります（`@stock SNDK is good to buy` は SNDK を調べます）。引用符で正確に指定できます：`@stock "aapl tsla"`。`@calculate` も文の中で使えます。その引数は後に続く式全体で、スペースも含め、ほかのテキストまでです：`@reply the total is @calculate 23 * 17 dollars`。`@claude` とターミナルのコマンドの中では実行されません。それらには書いたままのテキストが渡ります（そこで `@` を入力してもコマンドリストは開きません）。

### 実行キー

デフォルトは ⏎ です。設定の「Action key」（実行キー）で変更できます（設定ファイルの `actionKey`）：⏎、「Tap ⌥」（⌥ を軽く押す。左右どちらでも可で、押してすぐ離します。右 ⌥ を押し続けるのは引き続き音声入力用です）、⌥Space、Space（語を確定した後にもう一度 Space。英語モードでは 2 回）。実行キーが何であっても、@ コマンドは ⏎ でも実行されます。⌥Space がすでに Alfred や Raycast などのショートカットになっている場合は、そちらが先に受け取ります。

## メニューバーパネル

<img src="../en/panel-swipe.png" width="520" alt="メニューバーパネル：すりガラス風で、メモ、リマインダー、Claude タスクがカードに並ぶ。左にスワイプした行には「Remove」ボタンが表示される">

メニューバーの AllInOneIME のアイコン（枠のない、∞ とカーソルのマーク。枠付きのほうは入力ソース）をクリックすると、その下にパネルが開きます。ほかの場所をクリックすると閉じます：

- Notes（メモ）：`@note` で保存したメモの最新 5 件。クリックすると Notes で開きます。
- Reminders（リマインダー）：Reminders の AllInOneIME リストにある未完了のリマインダー（`@reminder` はこのリストに追加します）。期限の近い順に 8 件表示されます。丸をクリックすると完了にし、タイトルをクリックすると Reminders を開きます。
- Claude Tasks（Claude タスク）：`@tasks` と同じく、バックグラウンドの Claude タスク（`@claude` が引き渡したもの）を最大 30 件、一度に 5 件表示します。スクロールすると続きが見られ、検索ボックスでタイトルと返信を検索することもできます。進捗と最後の返信の 1 行目も表示されます。クリックすると Terminal で開いて続きができます。

行（メモ、リマインダー、タスク）を 2 本指で左にスワイプすると「Remove」（削除）ボタンが表示され、最後までスワイプするとすぐに削除されます。マウスでは右クリックします。削除してもパネルから外れるだけです。メモは Notes に、リマインダーは Reminders に（未完了のまま）、タスクは Claude Code に残ります。

ヘッダには件数（「2 reminders · 1 task running」など。返答待ちのタスクは「1 waiting for you」のように別に数えます）と更新ボタンがあります。入力中のアプリからフォーカスを奪うことはありません。リマインダーを完了にしたり更新したりしても、そのアプリは前面のままです。キーボード入力を受け取るのは、クリックした後の Claude タスクの検索ボックスだけです。アイコンはデフォルトで表示されます。設定の「Menu Bar Panel」（メニューバーパネル）でオフにできます。

何を、いつ読み取るか：

- Notes：一覧はパネル自身の記録で（パネルを閉じている間も保持）、Notes が起動されることはありません。Notes がすでに起動していて、AllInOneIME に以前から Notes の制御が許可されている場合にのみ、パネルはタイトルの変更や削除されたメモを確認します。
- Reminders：パネルが開いたとき、60 秒ごと、リマインダーが変更されたときに、AllInOneIME リストを読み取ります。パネルが自分から macOS にアクセス許可を求めさせることはありません。macOS がまだ尋ねていなければ「Allow Access to Reminders」（リマインダーへのアクセスを許可）が表示され、そのボタンを押したときだけ尋ねられます。拒否した場合は「Open System Settings」（システム設定を開く）が表示されます。
- Claude タスク：パネルは開いている間だけ `claude agents` を実行します。開いたときに 1 回、更新時、`@claude` がタスクを引き渡したとき、そして未完了のタスクがある間は 15 秒ごと。すべて完了すれば止まります。最後の返信は、この Mac 上の Claude Code のトランスクリプト（`~/.claude/projects`）の末尾から、トランスクリプトが変更されたときにだけ読み取ります。
- パネルを閉じている間は、これらはどれも動きません。`@note` が保存したメモの記録を残すだけです。

## 入力と翻訳

設定で：

- **Input languages**（入力言語）：英語、中国語（ピンイン）、フランス語、韓国語、ヒンディー語から 1～5 つを + で追加します（+ は常に表示され、5 つになるとグレー表示）。新規インストールでは英語のみです。新しいテキスト欄は最初の言語で始まり、Shift を軽く押すと順番に次の言語になります。1 つだけなら Shift で切り替わりません。
  - **フランス語**は専用のキーボードレイアウトで入力します。カードで別のものを選ばない限り AZERTY です。デッドキー（^、¨、`、´、~）による合成もそのレイアウトで行われます。
  - **韓国語**は 2 ボル式（Dubeolsik）配列でハングルを入力し、入力しながら音節を組み立てます（g k s → 한）。Shift で ㄲ ㄸ ㅃ ㅆ ㅉ と ㅒ ㅖ が入力できます。
  - **ヒンディー語**：単語を発音どおりにラテン文字で入力すると、デーヴァナーガリーになります（namaste → नमस्ते）。よく使う単語はヒンディー語での綴りになります。それ以外は、Space で最初の綴り、数字で別の綴り、⏎ で入力したままの文字、「.」でダンダ（।）を挿入します。
  - コマンド名、`@open` のテキスト、コード（`@py`、`@js`）は、言語にかかわらず英字で入力されます。コマンドが終わると元の言語に戻ります。
  - `@improve` は韓国語、ヒンディー語、フランス語の文をその言語のまま扱い、`@translate` はそれをあなたの言語に翻訳します（フランス語が入力言語の 1 つであれば、フランス語は英語と区別されます）。
- **Language packs**（言語パック）：アプリには英語（と、macOS のレイアウトだけで済むフランス語）が含まれています。中国語、韓国語、ヒンディー語は、追加するときにダウンロードするパックです。中国語（ピンイン）を追加すると、その辞書（約 34 MB、展開後 125 MB）がプログレスバー付きでダウンロードされ、完了すれば再起動なしですぐにピンインが使えます。韓国語のパック（キー表と、字母から音節を組み立てる方法）とヒンディー語のパック（文字とよく使う単語）は数 KB です。パックはデータのみ（辞書、表、スキーマ。コードは決して含みません）で、署名されたインデックスに載っており、使う前に SHA-256 が照合されます。プラグインと同じです。各言語のカードにはそのパック（バージョン、サイズ、入手元）が「Delete…」（削除…）とともに表示され、言語を削除するとパックも削除するか尋ねられます。0.6.1 以前からアップデートした場合、中国語はダウンロードなしで使い続けられます。インストーラが旧バージョン付属の辞書を残します。
- **Fuzzy pinyin**（あいまいピンイン、中国語入力時）：区別しない音をどちらで入力してもよくなります（例：z ↔ zh、n ↔ l、in ↔ ing）。「Input」（入力）ページの入力言語バーで中国語（ピンイン）を選び、「Fuzzy pinyin」をオンにしてペアを選びます。辞書は 1～2 秒で再デプロイされます。Rime のユーザフォルダに `rime_ice.custom.yaml` を書き込みますが、そこにあるあなた自身のファイルを上書きすることはありません。
- **Translate (@translate)**（翻訳）：翻訳先の言語（スペイン語、フランス語、ドイツ語、日本語、韓国語、中国語、ヒンディー語、ベンガル語、タミル語、そのほかの主なインドの言語など）を追加し、ドラッグで並べ替えます。ラテン文字で入力したヒンディー語（「aap kaise ho」）はデーヴァナーガリーで返されます。`@translate` はこの順番で言語ごとに 1 行書きます（言語が 1 つなら 3 つのバージョン）。元の文と同じ言語はスキップされます。新規インストールでは、Mac の優先する言語のうち英語でない最初の言語に翻訳します。英語しかない場合、`@translate` はこのページを開いて言語を追加させます。
- **Keyboard layouts**（キーボードレイアウト）：フランス語はカードで選んだレイアウトで入力します（設定ファイルの `keyboardLayouts`）。ほかの言語では、入力メソッドの下で macOS が最後に使ったラテン文字レイアウト（AZERTY、QWERTZ、スペイン語、US International など）を保持するので、いつもどおりに入力でき、`@` もレイアウト上の本来の位置にあります。デッドキーもコマンドのテキスト内で合成されます（⌥E の後に E → é、^ の後に e → ê）。ラテン文字のないレイアウト（ロシア語、ヒンディー語 InScript）は入力メソッドの下では使えません。⌃Space でそちらに切り替えるか、テキストをコマンドに貼り付ける（⌃V）か音声入力してください。
- `@improve` は翻訳せずに推敲と書き換えを行います。`@translate @improve` と続けると、1 回のリクエストで翻訳と書き換えを行います。設定で「@improve also translates」をオンにすると、`@improve` が常にそのように動作します。

## 書き換えスタイル

1–3 行目の後に書き換えが続きます。書き換えは**入力した言語で**行われ、英語なら英語の書き換え、中国語なら中国語の書き換えになります。設定で好きなものを選べます：

- Polish（推敲）：同じトーンで、より自然に
- Concise（簡潔）
- Formal（フォーマル）：上司や顧客向け
- Casual（カジュアル）
- Tactful（婉曲）
- Jargon（業界用語）：英語では Amazon 風の言い回し（bandwidth、circle back…）、中国語では大手 IT 企業の業界用語。悪い知らせは控えめに言い換えられます。例：「this is a blocker bug」（これは致命的なバグだ）→「Oh! Looks like your team has the bandwidth to fix this minor issue!」（おや！ この小さな問題を直す余力がチームにありそうですね！）

句読点しか変わらない書き換えや、ほかの行と同じ書き換えは表示されません。

### Jargon 用語リスト（自分の用語）

Jargon には組み込みの用語リストはありません。自分用のリスト（たとえばチームでよく使う言い回し）を用意すると、モデルはその用語を優先して使います。候補の Jargon の行には、使った用語の意味が注記されます。

リストはテキストファイルで、1 行に 1 つの用語を書き、必要ならその意味を「=」、コロン、Tab で区切って続けます（スプレッドシートから 2 列をコピーして貼り付けることもできます）。`#` で始まる行はコメントです：

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

設定の「Rewrite Styles → Jargon list」（書き換えスタイル → Jargon 用語リスト）で「New」（新規）をクリックすると、`~/.config/allinoneime/jargon.txt` に空のリストが作成されて開きます。すでにリストのファイルがある場合は、「Choose File…」（ファイルを選択…）をクリックすると、その場所のまま使えます（設定ファイルの `jargonFile`）。変更はすぐに反映されます。読み込まれるのは最初の 150 語だけです。「Jargon」にチェックを入れると、リストは各リクエストとともに Bedrock に送られます。

<img src="../en/panel-dark.png" width="420" alt="ダークモードの候補パネル">

## 音声入力

<img src="../en/voice.png" width="340" alt="右 ⌥ を押したまま話す">

右 ⌥ を押したまま話し、離すとテキストが挿入されます。入力中の言語（英語、中国語、フランス語、韓国語、ヒンディー語）で認識されます。先にコマンドを入力してから（例：`@improve `、`@question `）話すと、テキストはコマンドの後ろに入り、⏎ で実行されます。右 ⌥ を離さずに ⏎ を押せば、話し終えるとすぐに実行することもできます。音声は macOS 内蔵の音声認識（SpeechAnalyzer）によって Mac 上で認識され、音声がアップロードされることはありません。macOS 26 以降が必要です。

初回は：

- macOS が AllInOneIME によるマイクの使用を許可するか尋ねます。事前に設定で「Allow Microphone」（マイクを許可）をクリックしておくこともできます。
- この Mac にその言語の音声モデルがまだない場合は、一度だけ自動でダウンロードされます。設定でダウンロードすることもできます。

録音はキーを約 0.2 秒押し続けてから始まるので、右 ⌥ を軽く押しただけではマイクはオンになりません（実行キーを「Tap ⌥」に設定している場合、軽く押すとアクションが実行されます）。押している間にほかのキーを押した場合（⌥ のショートカット、⌥← など）も、ショートカットとみなされて録音されません。録音中にほかのキーを押すと、録音はキャンセルされます。

## インストール

動作には macOS 14 以降、音声入力には macOS 26 以降が必要です。インストーラはユニバーサルで、Apple シリコンと Intel の両方の Mac で動作します。これまでのテストは Apple シリコン上の macOS 27 だけです（Intel ビルドは Rosetta 上でのセルフテストのみ）。

1. [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) から `AllInOneIME-<version>.dmg` をダウンロードして（ダウンロードはここからのみ）開きます。
2. その中の「Install AllInOneIME」をダブルクリックし、「Install」（インストール）をクリックします。入力メソッドは `~/Library/Input Methods` に、「AllInOneIME Settings」は `~/Applications` にインストールされます。このユーザ専用で、管理者パスワードは不要です。
3. インストーラはまだ Apple の公証を受けていないため、macOS は作成者を確認できず、初回は「Install AllInOneIME」を確認できないと表示されます。「Done」（完了。macOS 14 では「Cancel」、キャンセル）をクリックし、System Settings → Privacy & Security（システム設定 → プライバシーとセキュリティ）を開いて、下の方にある「Open Anyway」（このまま開く）をクリックし、確定します。新しいバージョンのインストーラごとに、一度この操作が必要です。

これで AllInOneIME が有効になり、入力ソースに加わります。Ctrl+Space で切り替えます（🌐 キーで切り替わるのは、System Settings → Keyboard（システム設定 → キーボード）で「Press 🌐 key to」が「Change Input Source」に設定されている場合だけです）。インストーラから手動で追加するよう言われた場合、この Mac ではプログラムが有効にすることを許可していないので、一度だけ自分で追加してください：System Settings → Keyboard → Text Input → Input Sources → Edit… → +（左下）→ English → AllInOneIME（設定の「Input」で中国語を追加すれば、ピンインも入力できます）。

Ctrl+Space で AllInOneIME に切り替わらない場合や、しばらくすると U.S. に戻ってしまう場合は、インストーラをもう一度実行してください。AllInOneIME が入力ソースに追加し直されます。

アップデートするには、アンインストールせずに新しいバージョンのディスクイメージからもう一度インストールします。設定、Jargon 用語リスト、学習した語は保持されます。アップグレードの前に[変更履歴](../../CHANGELOG.md)を読んでください。各バージョンの変更点とアップグレード時の注意が載っています。

AIPinyin（AllInOneIME の以前の名前）をインストールしていた場合は、そのままインストールしてください。古い AIPinyin.app とその設定ランチャーは削除され、入力ソースの項目は新しい名前になるので、追加し直す必要はありません。設定、Jargon 用語リスト、学習した語は初回起動時に新しいフォルダ（`~/.config/allinoneime` など）に移され、古いフォルダはそれぞれ新しいフォルダへのリンクとして残ります。

アンインストールするには、「Install AllInOneIME」を開いて「Uninstall…」（アンインストール…）をクリックします。設定と学習した語は保持されます。

### ソースからビルド

音声入力が macOS 26 SDK を使うため、ビルドには Xcode 26 以降が必要です。

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` は librime と rime-ice の辞書をダウンロードして検証し、ビルドして同じ場所にインストールし、同じように入力ソースに追加します。インストールされるアプリには中国語の辞書は含まれていません（辞書は中国語の言語パックです）。辞書があった環境では、それがパックとして保持されます。そうでなければ、`make install-pack` がチェックアウトの辞書からダウンロードなしでパックをインストールします。`make status` はインストールされているバージョン（`version:`）と、入力ソースに含まれているかどうか（`listed:`）を表示します。アンインストール：`make uninstall`。

## AI の設定

翻訳と書き換えにはあなた自身の AI プロバイダを使い、費用はあなたのアカウントに請求されます。デフォルトは AWS アカウントの Amazon Bedrock ですが、Claude API、Gemini、OpenAI 互換サービスも使えます（下の「その他の AI プロバイダ」を参照）。

### Amazon Bedrock

1. AWS コンソールで Bedrock を有効にし、選んだモデルが使えることを確認します。デフォルトは Claude Haiku 4.5 です。Anthropic のモデルを初めて使うときは、ユースケースのフォームに一度記入します。
2. `bedrock:InvokeModelWithResponseStream` 権限を持つアクセスキーを作成し、`~/.aws/credentials` のプロファイルに入れます。現在サポートしているのはこのような静的キーのみで、SSO や assume-role には対応していません。
3. 「AllInOneIME Settings」を開きます。Spotlight やアプリケーションフォルダで見つかるほか、メニューバーの入力メソッドのアイコン →「Settings…」（設定…）からも開けます。プロファイル、リージョン、モデルを選び、「Test Connection」（接続をテスト）をクリックします。設定ウインドウ上部の「Language」（言語）は英語か中国語にできます。デフォルト（「System」）ではシステムに従います（システムの優先する言語で中国語が英語より前にあれば中国語、そうでなければ英語）。設定ウインドウ、候補パネルのヒント、入力メニューはすべてこれに従います。

<img src="../en/settings.png" width="420" alt="設定ウインドウ">

### その他の AI プロバイダ：Claude API、Gemini、OpenAI 互換サービス

AWS は必須ではありません。設定の「AI Provider」（AI プロバイダ）で 1 つ選び、API キーを貼り付けて「Save」（保存）をクリックし、続けて「Test Connection」をクリックします。

| プロバイダ | デフォルトのモデル | API キー |
|---|---|---|
| Claude API | `claude-haiku-5-5`（最も速く、最も安価。Sonnet 5.5 と Opus 5.5 はより丁寧ですが、遅く高価です） | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| OpenAI 互換 | OpenAI の `gpt-6-luna`（または `gpt-5.4-mini`）。「Common Services…」（よく使うサービス…）には DeepSeek、Qwen、Kimi、Zhipu GLM、SiliconFlow、OpenRouter、この Mac の Ollama があり、選ぶとその Base URL が入力されるので、続けてモデルを入力します | そのサービスのキー。Base URL をそのアドレスに設定します（例：`https://api.deepseek.com/v1`、この Mac の Ollama なら `http://localhost:11434/v1`） |

- API キーはシステムのキーチェーンに保存され、設定ファイルには決して書き込まれません。キーチェーンにキーがない場合は、シェルの `ANTHROPIC_API_KEY`、`GEMINI_API_KEY`（または `GOOGLE_API_KEY`）、`OPENAI_API_KEY` が使われます。
- 「Thinking」（思考）はデフォルトで低です。入力メソッドは文ごとに応答を待つので、思考が少ないほうが速くなります。対応していないモデルでは「Not set」（未設定）を選んでください。
- Claude Opus 5.5 または Sonnet 5.5 を選んだ場合、リクエストには Claude API の拒否時フォールバック（`fallbacks: "default"`）が付きます。安全性の分類器が拒否すると、サーバが別のモデルで再試行します。
- 設定ファイルでは：`provider`（`"bedrock"`、`"anthropic"`、`"gemini"`、`"openai"`）と、`anthropic`、`gemini`、`openai` の下の `model`、`baseURL`、`effort`、`temperature`（未設定のものはデフォルト値）。

すべての設定は `~/.config/allinoneime/config.json` に保存されます。変更すると、再起動なしで次の翻訳から新しい設定が使われます。新しいキー：

| キー | 動作 | デフォルト |
|---|---|---|
| `inputLanguages` | 入力言語。1～5 つで、最初のものがデフォルトです：`"en"` 英語、`"zh"` 中国語（ピンイン）、`"fr"` フランス語、`"ko"` 韓国語、`"hi"` ヒンディー語。例：`["en", "zh"]`、`["fr", "en", "ko"]`。中国語、韓国語、ヒンディー語はパックをインストールすると使えます | `["en"]`（新規インストール） |
| `keyboardLayouts` | 入力言語が使うキーボードレイアウトを言語コードで指定（今のところフランス語のみ）：`{"fr": "com.apple.keylayout.French-PC"}` | フランス語：`com.apple.keylayout.French`（AZERTY） |
| `outputLanguages` | `@translate` の翻訳先を順番に：`["es", "fr", "de"]` など | `["en"]` |
| `improveTranslates` | `@improve` でも翻訳する（`@translate @improve` と同じ） | `false` |
| `voiceInput` | 右 ⌥ を押したまま話す | `true` |
| `actionKey` | 実行キー：`"enter"`（⏎）、`"optionTap"`（Tap ⌥）、`"optionSpace"`（⌥Space）、`"space"`（Space） | `"enter"` |
| `uiLanguage` | インターフェイスの言語（設定ウインドウ、候補パネルのヒント、メニュー）：`"zh"`、`"en"` | `null`（システムに従う） |
| `rewriteStyles` | 書き換えスタイル：`polish`、`concise`、`formal`、`casual`、`tactful`、`jargon`。例：`["polish", "concise", "jargon"]` | Polish、Concise、Formal |
| `jargonFile` | 自分の Jargon 用語リストのファイル | `null`（つまり `~/.config/allinoneime/jargon.txt`） |
| `menuBarIcon` | メニューバーのアイコンとそのドロップダウンパネル | `true` |
| `fuzzyPinyin` | あいまいピンインのペア：`["z-zh", "n-l", "in-ing"]`（z-zh、c-ch、s-sh、n-l、f-h、r-l、an-ang、en-eng、in-ing、ian-iang、uan-uang） | `[]` |

## プライバシー

- 入力（英語とピンイン）と `@calculate` の計算は、すべてローカルで行われます。`@improve`、`@translate`、`@question` で実行キーを押したときにだけ、その文が選んだ AI プロバイダ（あなた自身の Bedrock、またはキーを追加したサービス）に送られます。「Jargon」にチェックを入れて用語リストを設定している場合は、リストも一緒に送られます。
- AllInOneIME Cloud を使う場合、文は開発者のサーバを経由してモデルプロバイダに送られます（現在は OpenRouter 経由）。サーバが保持するのは件数だけで、テキストは決して保持しません。サインインで保持されるのはメールアドレスだけです。
- 音声は右 ⌥ を押している間だけ録音され、Mac 上で認識されます。認識されたテキストが送られるのは、上記のコマンドで実行キーを押したときだけです。
- 入力メソッドがクリップボードのテキストを読み取るのは、コマンド内で ⌃V または ⌘V を押したときに一度だけです。パスワードマネージャが非表示扱いにした内容は読み取りません。テキストはまずコマンド内に表示され、これも実行キーを押したときにだけ送られます。最近の macOS では、AllInOneIME によるクリップボードの読み取りを許可するか尋ねられるので、許可してください。毎回尋ねられないようにするには、System Settings → Privacy & Security で AllInOneIME のペースト権限を常に許可に設定します。
- パスワード欄では、macOS が独自のキーボード（U.S. または ABC）に切り替え、欄を離れると元に戻します。入力中のアプリがセキュア入力を保持している間、AllInOneIME は文字を合成せず、録音もできません。キーは入力したとおりに入ります。また、システムがセキュア入力の状態にある間（パスワード欄、Terminal の Secure Keyboard Entry（セキュアなキーボード入力）など）は、AI に何も送られません。
- `@note` と `@reminder` は AI に送られません。AllInOneIME はテキストをこの Mac の Notes と Reminders に渡すだけで、リマインダーの日時も Mac 上で読み取ります（それらのアプリがほかのデバイスに同期するかどうかは、iCloud などのアカウント次第です）。そのため、セキュア入力中でも使えます。
- `@open` はこの Mac 上だけを検索します。それで開いたもの（最新 200 件）を入力メソッド自身の環境設定（config.json ではなく）に記録し、先頭に表示するために使います。
- メモを一覧表示するため、メニューバーパネルは `@note` で保存した最新 30 件のメモの ID と最初の行（最大 80 文字）を、入力メソッド自身の環境設定に保存します。パネルがオフのときも同様です。
- `@py` と `@js` は実行キーを押したときにだけ、自分で入力または貼り付けたコードだけを実行します。AI の答えやほかのコマンドの出力がコードとして実行されることはありません。`@py` は Mac の `python3` を使うので、Terminal と同じようにファイルの読み書きやネットワークへのアクセスができます。`@js` は別プロセスで実行され、ファイルの読み取り、ネットワークへのアクセス、ほかのプログラムの実行はできません。どちらもセキュア入力中には実行されません。
- ログには入力内容は記録されません。macOS はすべてのサードパーティ製入力メソッドについて「The developer can access anything you type with this input source」（開発者はこの入力ソースで入力したすべての内容にアクセスできます）と警告しますが、これはシステムの一般的な警告です。

## 開発

```sh
make test         # unit tests, plus tests that run the real Rime engine
make pack         # the Chinese language pack: build/packs/zh-pinyin-<version>.tar.xz, its sha256, its packs.json entry
make packs        # all the language packs: Chinese, and Korean and Hindi from LanguagePacks/ (ko-hangul, hi-phonetic)
make selftest     # drives the input method through a simulated text field: real Bedrock calls, plus on-device recognition tested with synthesized speech
make realtest     # types into a real app's text field (needs the screen unlocked; takes over the foreground for about 1 minute)
make screenshots  # regenerates the screenshots in docs/
make cli && .build/release/allinoneime-cli --styles concise,jargon "this is a blocker bug your team need fix it asap"   # try polishing and rewrites in the terminal
make icon         # regenerates the app icon and the menu bar icon from Resources/AppIcon.png
make dmg          # the release installer, build/AllInOneIME-<version>.dmg (universal; signed if there's a Developer ID certificate, optionally notarized)
```

コードの構成：

- `Sources/AllInOneIMECore`：Bedrock クライアント、SigV4、プロンプト、2 階層の入力ステートマシン（@ コマンドと音声ジェスチャを含む）。AppKit には依存しません
- `Sources/AllInOneIMERime`：librime のラッパー
- `Sources/AllInOneIME`：InputMethodKit の入力メソッド、候補パネル、設定ウインドウ、音声認識
- `Sources/AllInOneIMESettings`：「AllInOneIME Settings」ランチャー
- `Sources/AllInOneIMEInstaller`：ディスクイメージ内の「Install AllInOneIME」。インストール、アップデート、アンインストールを行います

言語パックには、プラグインとは別の独自のライブラリがあります。リポジトリ [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages) で、https://languages.allinoneime.com/ から配信され、専用の鍵で署名されています。`make pack` がアーカイブをビルドし、それをそこにリリースアセットとして公開します（リリース `zh-pinyin-<version>`、`ko-hangul-<version>`、`hi-phonetic-<version>`）。`swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` がそこに `packs.json` を書き込み、キーチェーンにある言語パック用の鍵（`allinoneime-languages-signing`）で署名して `packs.json.sig` を作ります。アプリは https://languages.allinoneime.com/packs.json を読み取って署名を確認し、次にアーカイブのサイズと SHA-256 を確認します。ローカルサーバからパックを試すには：`--test-key` でテスト用の鍵で署名し、`AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>` を実行します。

バンドル ID は今も `com.aipinyin.inputmethod.AIPinyin` です。macOS はこれを使って追加済みの入力ソースとマイクの権限を記憶しているため、変更すると入力メソッドの追加と権限の付与をやり直す必要があります。

## ライセンス

Copyright © 2026 MicroZ LLC. ソースは [Functional Source License 1.1](../../LICENSE)（FSL-1.1-ALv2）のもとで公開されています。競合製品以外のあらゆる目的で、使用、閲覧、変更、共有ができます。各バージョンは、リリースから 2 年後に Apache-2.0 になります。0.6.1 までのバージョンは GPL-3.0 でリリースされており、引き続きそのライセンスで利用できます。

サードパーティのコンポーネント（librime とそのプラグインは BSD-3-Clause、rime-ice の Lua スクリプトと中国語の言語パックは GPL-3.0）は [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) に記載されています。
