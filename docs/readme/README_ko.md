<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · [繁體中文](README_zh-TW.md) · [日本語](README_ja.md) · **한국어** · [Français](README_fr.md) · [Deutsch](README_de.md) · [Español](README_es.md) · [Português (Brasil)](README_pt-BR.md) · [Italiano](README_it.md) · [Русский](README_ru.md) · [Tiếng Việt](README_vi.md) · [ไทย](README_th.md) · [Bahasa Indonesia](README_id.md) · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · [Türkçe](README_tr.md)

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="AllInOneIME 아이콘">

# AllInOneIME

### Mac의 모든 텍스트 필드에서 AI 명령어를.

어떤 앱에서든 `@improve`, `@translate`, `@question`을 입력하고 ⏎를 누른 뒤 결과를 고르세요.<br>
채팅 창에 복사할 필요도, 앱을 전환할 필요도 없습니다. AI 제공업체도 키도 모두 여러분의 것을 씁니다.

[![Release](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#설치)
[![Apple 공증 완료](https://img.shields.io/badge/Apple-notarized-0a84ff?logo=apple&logoColor=white)](#설치)
[![Apple 실리콘 및 Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#설치)
[![라이선스: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![다운로드 수](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[다운로드](https://allinoneime.com/download)** · **[웹사이트](https://allinoneime.com)** · **[문서](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[확장 기능](../extensions.md)**

[사용 방법](#사용-방법) · [명령어](#-명령어-베타) · [나만의 명령어](#나만의-명령어) · [언어](#입력과-번역) · [음성](#음성-입력) · [설치](#설치) · [개인정보 보호](#개인정보-보호)

<br>

<img src="../en/demo.png" width="820" alt="@translate와 문장을 입력하고 ⏎: 스페인어, 프랑스어, 독일어 번역이 한 줄씩">

</div>

*이 문서는 영어 README의 번역본입니다. 두 문서의 내용이 다를 경우 영어 문서가 기준입니다.*

> [!NOTE]
> 0.6.3부터 AllInOneIME는 Developer ID로 서명되고 Apple의 공증을 받습니다. 이제 System Settings → Privacy & Security(시스템 설정 → 개인정보 보호 및 보안)에서 허용할 필요가 없습니다. 이전 버전에서 업데이트한 뒤에는 AllInOneIME가 키체인에 저장한 키마다 macOS가 로그인 암호를 한 번씩 묻습니다. 암호를 입력하고 "Always Allow"(항상 허용)를 클릭하세요. AllInOneIME는 [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) 또는 [allinoneime.com](https://allinoneime.com)에서만 내려받으세요.

모든 텍스트 필드에서 AI 명령어를 쓸 수 있는 macOS 입력기입니다. 문장을 `@`로 시작하고, 다 쓰면 ⏎를 누르세요. `@improve`는 쓴 글을 다듬고 몇 가지 다시 쓰기를 제안하고, `@translate`는 고른 언어로 번역하고, `@question`은 질문을 하고, `@claude`는 Claude Code에 넘기고, `@open`은 파일과 앱을 찾거나 웹 주소를 엽니다. 오른쪽 ⌥를 누른 채 말할 수도 있습니다. `@`가 없으면 키 입력은 평소처럼 앱으로 갑니다. 중국어(병음, Rime과 rime-ice 기반), 프랑스어, 한국어(한글), 힌디어(라틴 문자로 데바나가리 입력)도 입력할 수 있고, 직접 만든 스크립트를 @ 명령어로 실행할 수도 있습니다.

![@improve와 다듬지 않은 문장을 입력하고 ⏎: 다듬은 버전과 다시 쓰기](../en/improve.png)

자세한 내용(모든 명령어와 설정, 설치 문제 해결, 개인정보 보호)은 [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki)를 참고하세요. MicroZ LLC의 [Weijian Zhang](https://weijianz.com)이 만들었습니다.

## 사용 방법

`@`가 없으면 방해하지 않습니다. 영어에서는 글자가 그대로 입력되고 ⏎는 Return입니다. 아무것도 온라인으로 전송되지 않습니다. 새로 설치하면 영어만 입력합니다. 중국어(병음), 프랑스어, 한국어, 힌디어도 입력하려면 설정에서 추가하세요([입력과 번역](#입력과-번역) 참고).

| 키 | 동작 |
|---|---|
| 병음 입력, Space / 숫자 | 중국어 모드: 일반 병음 입력기처럼 단어를 고릅니다 |
| `@`(문장 맨 앞에서) | 명령어 목록을 엽니다. 최근에 많이 쓴 것이 먼저 나오고, 한 번에 5개씩, ↑↓, 스크롤 휠, 트랙패드로 스크롤합니다. 글자를 입력해 찾을 수도 있습니다(전부 입력한 이름이 먼저, 그다음 그 글자로 시작하는 이름, 그다음 그 글자를 포함하는 이름). ⏎, Tab, Space, 숫자 키로 선택합니다 |
| ⏎ | 명령어를 실행합니다. 병음을 아직 고르지 않았어도 됩니다. Space를 누를 때처럼 먼저 골라집니다 |
| Space, ⏎ / 숫자 | 결과가 나타나면: 강조된 결과 / 해당 번호의 결과를 삽입합니다. 0은 원문입니다 |
| ⌘C | 강조된 결과를 복사합니다(`@open`에서는 경로). 후보 패널은 열린 채로 있습니다 |
| ⌃V | 명령어 안에서(예: `@improve ` 뒤): 클립보드 텍스트를 앱에 붙여 넣는 대신, 입력한 내용 뒤에 덧붙입니다. 여러 줄은 한 줄로 합쳐지며, 한 번에 최대 2000자입니다(`@note`는 줄바꿈을 유지하며 최대 20000자). 어떤 앱에서든 작동하며, 명령어가 없으면 키는 평소처럼 앱으로 갑니다 |
| ⌘V | ⌃V와 같지만, ⌘V를 직접 처리하는 앱(Ghostty, iTerm2, Terminal 같은 터미널과 Notes)에서는 평소처럼 앱에 붙여 넣습니다. 그런 앱에서는 ⌃V를 쓰세요 |
| Esc, ⌫ | 문장으로 돌아가 계속 편집합니다. 결과가 나온 뒤 문장 부호나 숫자를 입력하면 문장을 이어 씁니다. 다듬은 뒤에는: 그 전의 결과로 돌아갑니다 |
| AI 결과가 나온 뒤 입력하는 글자 | `shorter` 같은 후속 지시입니다. ⏎를 누르면 결과를 다듬습니다([결과 다듬기](#결과-다듬기-신규) 참고) |
| 행 클릭 | 후보 패널에서: 그 행의 숫자 키를 누른 것처럼 선택합니다(단어, 목록의 명령어, 결과, `@open` 파일, 받는 사람, 확장의 행). 포인터 아래의 행이 강조됩니다. 텍스트 필드는 포커스를 유지합니다 |
| Shift 가볍게 누르기 | 입력 언어가 둘 이상일 때: 순서대로 다음 언어로 바꿉니다(영어 → 중국어 → 프랑스어 → …, 그다음 다시 처음으로) |
| 오른쪽 ⌥ 누르고 있기 | 말하고, 떼면 멈춥니다. 입력 중인 언어(영어, 중국어, 프랑스어, 한국어, 힌디어)로 인식합니다. 명령어 안에서는 텍스트가 그 뒤에 들어가고, 그렇지 않으면 바로 삽입됩니다 |

## @ 명령어 (베타)

| 명령어 | 동작 |
|---|---|
| `@improve` | 다듬기: 1–3은 문장 원래 언어로 된 세 가지 버전, 4부터는 다시 쓰기 스타일(설정에서 추가하고 순서를 정함), 0은 원문입니다. 번역은 하지 않습니다. "@improve also translates"(@improve에서도 번역)를 켜면 `@translate @improve`처럼 작동합니다 |
| `@translate` | 추가한 언어로 번역합니다(설정 → "Translate", 드래그로 순서 변경). 언어마다 한 줄이며, 언어가 하나뿐이면 세 가지 버전입니다. 문장 원래 언어는 건너뜁니다. `@translate @improve`를 함께 쓰면 한 번의 요청으로 번역과 다시 쓰기를 합니다 |
| `@question` | 질문합니다. 답은 후보에 나타나며, ⏎ 또는 Space로 삽입하고 ⌘C로 복사합니다. 뒤에 아무것도 입력하지 않으면 최근 질문 5개를 최신순으로 보여 줍니다. 입력하면 범위가 좁혀집니다(질문 안 어디에 있는 단어든, 대소문자 구분 없이, 중국어도). 숫자 키, ↑↓ 후 ⏎, 또는 클릭하면 그 질문의 저장된 답을 오프라인으로 바로 보여 주며, 평소처럼 삽입하거나 복사할 수 있습니다. 거기서 R을 누르면 다시 질문해 새 답을 받습니다. 일치하는 것이 없거나 아무것도 고르지 않으면 ⏎는 입력한 내용을 질문합니다 |
| `@claude` | 작업을 Claude Code에 넘깁니다. 기본적으로 백그라운드에서 실행되며, 끝나면 알림이 옵니다(클릭하면 Terminal에서 그 세션을 열어 이어서 할 수 있습니다). `@tasks`로 확인할 수도 있습니다. 여러분의 Claude Code(`claude` 명령어)를 그 자체의 로그인과 설정으로 사용합니다. 설정에서 "@claude runs in the background and notifies me"(@claude를 백그라운드에서 실행하고 끝나면 알림)를 끄면 예전처럼 Terminal에서 엽니다. 처음 Terminal을 열 때 macOS가 AllInOneIME가 Terminal을 제어하도록 허용할지 묻습니다. "OK"(확인)를 클릭하세요 |
| `@tasks` | 백그라운드 Claude 작업(진행 중 / 완료 / 응답 대기)과 각각의 마지막 답장을 나열합니다. ⏎는 Terminal에서 열고, ⌘C는 답장을 복사합니다 |
| `@settings` | 설정 창을 바로 엽니다(고르기만 하면 됩니다) |
| `@open` | 입력하는 대로 일치하는 파일, 폴더, 앱을 나열합니다(Spotlight). 공백으로 구분해 여러 키워드를 쓸 수 있습니다. 각 키워드는 경로에 있어야 하고, 적어도 하나는 이름에 있어야 합니다(표준 폴더의 이름은 그 안의 항목에도 적용됩니다. `downloads pdf`는 Downloads(다운로드) 안의 PDF를 찾습니다). 앱과 표준 폴더는 중국어 이름으로도 찾을 수 있고, 중국어 인터페이스에서는 그 이름으로 표시됩니다. `@open`으로 연 항목이 먼저 나오고, 그다음 앱과 그 폴더들, 그다음 최근에 사용하거나 변경한 파일이 나옵니다. 이름으로 찾은 파일이 두 개 이하이고 해당하는 앱이나 그 폴더가 없으면, 홈 폴더의 파일을 내용으로도 검색하며 그 행에는 "content"(내용)라고 표시됩니다. 그 밖에 아무것도 없으면, ⏎는 첫 항목을 여는 대신 그것들을 나열해 고를 수 있게 합니다. 웹 주소(`github.com`, `localhost:3000`, `https://…`)를 입력하면 첫 행은 "open in the browser"(브라우저에서 열기)이고 내용은 검색하지 않습니다. 정확히 그 이름의 파일(예: `MANIFEST.in`)이 있으면 그것이 먼저 나옵니다. `~/`나 `/`로 시작하는 텍스트는 경로입니다. Tab은 경로를 완성하며 폴더 안으로 들어가고, ⏎는 열고, ⌘C는 경로를 복사합니다 |
| `@note` | 텍스트를 Notes 앱의 AllInOneIME라는 폴더(없으면 만듦)에 저장합니다. 아무것도 삽입되지 않습니다. 붙여 넣은 텍스트는 줄바꿈을 유지하며 최대 20000자입니다 |
| `@reminder` | Reminders 앱의 AllInOneIME라는 목록에 미리 알림을 추가합니다. 시간은 텍스트 안에 쓰세요. 시간은 Mac에서 해석되며, 해석한 결과가 한 행에 표시됩니다. ⏎ 또는 Space로 추가하고, Esc로 편집으로 돌아갑니다. 시간이 있으면 그때 알림이 울리고, 날짜만 있으면 종일 일정이 됩니다 |
| `@calculate` | 이 Mac에서 계산합니다. 결과는 후보에 나타나며 ⏎ 또는 Space로 삽입합니다: `@calculate 23*17` → `391`. 문장 안에서도 쓸 수 있습니다: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Python 한 줄을 실행하고(Mac의 `python3`) 결과를 삽입합니다. 코드의 마지막 식의 값(예: `@py 2**100`, `@py import math; math.sqrt(2)`)이나, 그게 없으면 출력한 내용입니다. `python3`가 없으면 제공되지 않습니다(Xcode 명령줄 도구에 포함되어 있습니다) |
| `@js` | JavaScript 한 줄을 실행하고 같은 방식으로 삽입합니다. 마지막 식의 값이나 `console.log`가 출력한 내용입니다(예: `@js [1, 2, 3].map(x => x * 2)`). macOS 내장 JavaScriptCore를 사용하므로 설치할 것이 없습니다. 파일을 읽거나, 네트워크에 접근하거나, 다른 프로그램을 실행할 수 없습니다 |
| `@reportissue` | 문제를 보고합니다. 브라우저에서 GitHub의 새 issue 페이지를 열고, 명령어 뒤에 입력한 내용을 제목으로, 채워 넣을 "What happened / What you expected"(무슨 일이 있었는지 / 무엇을 기대했는지)를 붙입니다. 앱과 macOS 버전, Mac의 아키텍처, 인터페이스 언어와 입력 언어, 설치된 언어 팩, AI 제공업체의 종류(공개 모델이면 모델 이름도, 아니면 "custom"), 실행 키, 그리고 사용자 지정 명령어·플러그인·확장이 각각 몇 개인지를 덧붙이며, 그 이름이나 사용자의 텍스트, 경로, 키는 절대 넣지 않습니다. ⏎(또는 실행 키)를 누르면 먼저 이 모든 내용을 후보 패널에 보여 주고, ⏎를 한 번 더 누르거나 그 행을 클릭하면 페이지가 열립니다. 거기서 내용을 읽고 Submit을 클릭합니다(본인의 GitHub 계정으로). Esc는 뒤로 갑니다. 입력 메뉴("Report an Issue…")와 Settings → About에도 있습니다 |
| `@imessage` | iMessage를 보냅니다. 이름, 전화번호, 이메일을 입력하고(중국어 이름은 병음으로도, 전체 또는 첫 글자로) 후보 패널에서 받는 사람을 고른 다음(최근에 메시지를 보낸 사람이 먼저 나옵니다. 전체 번호나 주소도 됩니다), 메시지를 씁니다(그 안의 `@stock AAPL` 같은 명령어가 먼저 실행됩니다). ⏎를 누르면 패널에 "Send to Alex (…): message"가 표시되고, ⏎를 한 번 더 누르면 보내며, Esc는 편집으로 돌아갑니다. 텍스트 필드에는 아무것도 입력되지 않습니다. 처음에 macOS가 AllInOneIME가 Contacts(연락처)에 접근하고 Messages(메시지)를 제어하도록 허용할지 묻습니다. 둘 다 "OK"를 클릭하세요 |

예: `@q` ⏎, `what is quantum computing` 입력, ⏎. `@note books to read: The Three-Body Problem` ⏎는 메모를 저장합니다. `@reminder call Bob tomorrow at 3pm` ⏎ 후 해석된 시간을 확인하고, ⏎를 한 번 더 눌러 추가합니다. 명령어를 고른 뒤에는 오른쪽 ⌥를 누른 채 말할 수도 있습니다. 중국어 모드에서 `@open`과 `@calculate`는 잠시 영문 입력으로 바뀌었다가 끝나면 중국어로 돌아갑니다.

`@py`와 `@js`의 코드는 영문자로 입력하며, (중국어 모드에서 온) 전각 문장 부호는 ASCII로 바뀝니다. 코드는 한 줄로 쓰고, 문장 사이는 `;`로 구분하세요. 코드는 별도 프로세스에서 실행되며, 10초 후 또는 언제든 Esc로 멈춥니다. 오류가 나면 오류의 첫 줄이 표시됩니다(예: `ZeroDivisionError: division by zero`). 여러 줄의 출력은 출력된 그대로 삽입되지만, 터미널에서는 한 줄로 들어갑니다(터미널은 받은 모든 줄을 실행하기 때문입니다). 편집기 안의 터미널(VS Code, Cursor, JetBrains)은 편집기 자체와 구분할 수 없으므로, 그곳에서는 어떤 명령어의 여러 줄 출력이든 그대로 들어갑니다. 둘 다 다른 명령어의 문장 안에서도 작동합니다: `@reply the answer is @py 2**100`. 공백이 있는 코드는 따옴표로 묶으세요: `@question explain @py "sum(x * x for x in range(10))"`. 반대는 안 됩니다. `@py`와 `@js`의 코드는 항상 입력한 그대로 실행되며, 그 안의 `@commands`가 먼저 실행되지 않습니다.

![@를 입력하면 명령어 목록이 열림. @question과 질문을 입력하고 ⏎를 누르면 답이 나옴](../en/commands.png)

![@open은 입력하는 대로 앱을 찾음. /로 시작하면 경로: 폴더 내용이 나열되고 Tab으로 완성](../en/open.png)

`@john`처럼 `@` 뒤에 명령어가 오지 않으면 `@`가 평소처럼 입력되므로, 채팅 앱에서 사람을 @멘션하는 것도 그대로 됩니다. `@question`, `@improve`, `@translate`는 실행 키를 눌렀을 때만 여러분의 Bedrock으로 보냅니다. `@open`은 이 Mac에서만 검색합니다. `@note`와 `@reminder`는 이 Mac의 Notes와 Reminders로만 갑니다. `@claude`는 Mac에 설치된 Claude Code(`claude` 명령어)와 그 계정을 사용하며, 파일을 바꾸거나 명령어를 실행하기 전에 평소처럼 먼저 묻습니다. Claude Code가 설치되어 있지 않으면 `@claude`는 제공되지 않습니다. `@imessage`는 이 Mac의 Contacts(이름, 전화번호, 이메일)만 읽으며, AI를 거치지 않고, 메시지는 Messages가 보냅니다. Messages 앱이 없으면 제공되지 않습니다.

`@calculate`는 이 Mac에서 오프라인으로 작동합니다. `+ - * /`(`× ÷`도 가능), 거듭제곱의 `^` 또는 `**`, 괄호, 퍼센트(`50%`는 0.5, `200*5%`는 10. 계산기처럼 더하거나 빼는 퍼센트는 앞의 값에 대한 것입니다: `100+10%`는 110, `100-10%`는 90), 함수 `sqrt abs round floor ceil ln log exp sin cos tan min max pow`(`log`는 밑이 10, 각도는 라디안, `round(x, 2)`는 소수 둘째 자리까지), 상수 `pi`(`π`)와 `e`를 쓸 수 있습니다. 전각 숫자와 기호도 됩니다. 계산은 십진수로 정확하게 하므로 `0.1+0.2`는 `0.3`입니다. 결과는 유효 숫자 최대 15자리이며, 38자리까지의 정수는 생략 없이 표시됩니다(`2^100` → `1267650600228229401496703205376`).

### 선택한 텍스트에서 (신규)

아무 앱에서나 텍스트를 선택하고(메모의 한 문장, Mail의 한 단락), `@improve`, `@translate`, `@question` 또는 텍스트를 받는 다른 명령어를 입력한 뒤 ⏎를 누르세요. 명령어가 선택 영역을 대상으로 동작하고, 고른 결과가 선택 영역을 대체합니다. 입력하는 동안 선택 영역은 그대로, 선택된 채로 남습니다. 명령어는 후보 패널에 적히며, 첫 줄은 입력하는 내용이고 다음 줄은 "On the selection: “…” (N characters)"(선택 영역에 대해: N자)입니다. Esc, ⇧⏎, 다른 곳 클릭은 텍스트를 원래대로 둡니다. 그사이 선택 영역을 바꿔도 마찬가지이며, 명령어는 취소됩니다. 명령어 뒤에 입력한 텍스트는 `@improve`와 `@translate`에서는 지시(`@translate ja`, `@improve more formal`), `@question`에서는 선택 영역에 대한 질문(`@question what does this mean`)이 됩니다. `@open`, `@claude`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, 터미널 명령어, 스크립트 확장은 선택 영역을 쓰지 않습니다. 이들은 입력한 내용만 받고, 선택 영역은 그대로 남습니다. 최대 5000자이며, 보안 입력 중이거나 터미널에서는 절대 읽지 않습니다. 어떤 앱에서 제대로 동작하지 않으면 Settings → General → "Use the selected text"(선택한 텍스트 사용)에서 끄세요.

### 결과 다듬기 (신규)

`@improve`, `@translate`, `@question` 또는 프롬프트 명령어의 결과가 나와 있는 동안 바꿀 점을 입력하세요. 예를 들어 `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese`, `用更口语的说法` 같은 것입니다(병음도 되고, Shift를 가볍게 누르면 언어가 바뀝니다). ⏎를 누르면 결과가 지시와 함께 다시 AI로 가고, 새 결과가 같은 패널에서 기존 결과를 대체합니다. 원하는 만큼 다시 다듬을 수 있습니다. 패널 맨 위 줄에 단계가 나열되고("Refined: shorter · more formal"), 언제든 평소처럼 행을 고를 수 있습니다. 글자를 입력하면 지시가 시작됩니다(패널 위쪽에 "refine › …"로 표시). 지시가 비어 있는 동안에는 숫자 키, Space, ⏎가 전처럼 선택에 쓰입니다. 다듬기는 결과가 모두 나온 뒤에 시작됩니다. 첫 결과가 아직 들어오는 동안 입력하면 전처럼 문장을 이어 씁니다. 다듬기가 진행되는 동안에도 다음 지시를 미리 입력할 수 있습니다. 다듬기는 계속 진행되고, 그 결과가 들어오면 ⏎로 다음 다듬기를 실행합니다. Esc는 지시를 지우고, 그다음 마지막 다듬기 전의 결과로 한 단계 돌아가며(다듬기 중이면 멈추고), 그다음 문장으로 돌아갑니다. 빈 줄에서 ⌫를 눌러도 같은 방식으로 돌아갑니다. 선택한 텍스트에서는 고른 결과가 여전히 정확히 선택 영역만 대체하며, 그때까지 선택 영역은 건드리지 않습니다. 실패한(또는 보안 입력 중에 거부된) 다듬기는 결과를 그대로 두고, 그 지시는 ⏎로 다시 시도할 수 있게 남겨 둡니다. 같은 결과에 대한 같은 다듬기는 캐시에서 답합니다.

### 최근 질문 (신규)

뒤에 아무것도 입력하지 않은 `@question`은 최근 질문 5개를 최신순으로, 질문한 시각("3 hours ago")과 함께 보여 줍니다. 입력하면 범위가 좁혀집니다. 각 단어가 질문 안 어디에 있든, 대소문자 구분 없이 찾습니다(띄어쓰기 없는 중국어도). 숫자 키, ↑↓ 후 ⏎, 또는 클릭하면 그 질문의 저장된 답을 온라인에 접속하지 않고 바로 보여 줍니다. Space 또는 ⏎로 삽입, ⌘C로 복사, 0으로 질문 보기, R로 다시 질문해 새 답 받기, Esc로 목록으로 돌아갑니다. 일치하는 것이 없거나 아무것도 고르지 않으면 ⏎는 입력한 내용을 질문합니다. 같은 질문에 대한 새 답(다시 묻거나 다듬은 것)은 저장된 답을 대체합니다.

- 질문은 이 Mac에만 보관됩니다(개인정보 보호 참고). 보안 입력 중에는 보관하지 않고, 선택한 텍스트에 대한 질문은 절대 보관하지 않습니다.
- Settings → General → "Remember recent questions"(최근 질문 기억)로 끌 수 있으며, 끄면 삭제됩니다(설정 파일의 `rememberQuestions`). "Clear (N)"(지우기)는 질문을 삭제합니다.

### 메모와 미리 알림

`@note`는 새 메모를 만들며, 첫 줄이 제목이 됩니다. 텍스트를 복사한 뒤 `@note ` 다음에 ⌃V(터미널 밖에서는 ⌘V도 가능)를 누르면 줄바꿈까지 함께 저장되며, 줄바꿈은 명령어 안에서 ↵로 표시됩니다. 줄바꿈이 있는 메모를 저장하기 전에 텍스트 필드를 떠나거나(다른 곳을 클릭, 앱 전환) ⇧⏎(입력한 그대로 삽입)를 누르면, 그 텍스트는 앱에 입력되지 않고(터미널에서는 각 줄이 명령어로 실행될 것이므로) 대신 클립보드에 들어갑니다("The note wasn't saved; its text is on the clipboard"). 한 줄짜리 메모는 입력한 그대로 삽입됩니다.

`@reminder`는 `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month`(그달 1일), `end of the year` 같은 시간을 해석합니다(중국어 시간 표현도 됩니다). 날짜와 시간은 떨어져 있어도 됩니다(`tomorrow call Bob at 5`). 한 주는 월요일에 시작합니다. 오전/오후가 없는 시간(`at 5`)은 다음에 오는 그 시간이며, 자정부터 오전 6시 사이가 되는 일은 없습니다. 오늘 이미 지난 시간은 내일이 되지만, 아직 진행 중인 하루의 시간대(`this afternoon`, `tonight`)는 오늘의 종일 일정이 됩니다. 올해 이미 지난 날짜는 내년이 됩니다. 반복되도록 쓴 것(`standup every Monday at 9`)은 다음 한 번만 추가됩니다. 그 단어들은 제목에 남고, 행에는 "once only"(한 번만)라고 표시됩니다. 확인용 행에는 해석한 시간이 표시됩니다(예: "tomorrow 3:00 PM", Mac의 12/24시간제 설정을 따름). 틀렸다면 Esc로 텍스트로 돌아갑니다. 시간이나 날짜가 없으면 시간 없이 추가됩니다("no date").

이 두 명령어 안에서는 `@stock` 같은 명령어가 실행되지 않습니다. 텍스트는 쓴 그대로 저장됩니다(그 안에서 `@`를 입력해도 명령어 목록이 열리지 않습니다). 처음에 macOS가 AllInOneIME가 Notes를 제어(`@note`)하거나 Reminders에 접근(`@reminder`)하도록 허용할지 묻습니다. 허용하세요. 허용하지 않았다면 System Settings → Privacy & Security → Automation(시스템 설정 → 개인정보 보호 및 보안 → 자동화)(Notes) 또는 → Reminders에서 AllInOneIME를 허용하세요. 저장에 실패하면(예: 권한 없음) 알림에 이유가 표시되고, 텍스트가 명령어로 돌아와 고쳐서 다시 보낼 수 있습니다. 먼저 무언가를 고쳐야 할 때(권한, 계정)는 텍스트가 클립보드에도 들어갑니다(System Settings로 가면 텍스트 필드의 포커스가 사라지기 때문입니다). 이미 다른 텍스트 필드로 옮겼거나 다른 내용을 입력하고 있다면, 대신 클립보드에 들어갑니다("Not saved; the text is on the clipboard.").

### 나만의 명령어

설정의 "Custom @ Commands"(사용자 지정 @ 명령어)에서 "Add Command…"(명령어 추가…)를 클릭하세요. 이름을 정하고 동작(AI 지시문, 프로그램, Terminal에서 실행하는 프로그램, 웹 페이지)을 고르거나, 예제에서 시작합니다. 나만의 명령어는 내장 명령어 뒤에 나옵니다. 이름은 영문자만 쓸 수 있고 내장 명령어와 같을 수 없으며, 다음 문장부터 작동합니다. 명령어는 설정 파일(`~/.config/allinoneime/config.json`)의 `customCommands`에 저장되며, 직접 편집할 수도 있습니다:

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | 동작 |
|---|---|
| `prompt` | `prompt`를 지시문으로 삼아 AI에 보냅니다. 답은 후보에 나타나며 삽입하거나 복사(⌘C)할 수 있습니다 |
| `run` | `argv`를 백그라운드에서 실행합니다. 출력은 후보에 나타납니다(여러 줄은 출력된 그대로, 터미널에서는 한 줄로 삽입). 오류가 나면 마지막 줄이 표시됩니다 |
| `terminal` | `argv`를 새 Terminal 창에서 실행합니다. 아무것도 삽입되지 않습니다 |
| `link` | 텍스트를 웹 주소 `url`에 넣어 기본 브라우저에서 엽니다. 아무것도 삽입되지 않습니다 |

- `{input}`은 명령어 뒤에 쓴 내용으로 바뀌며, 항상 그것이 들어 있는 하나의 인수 안에 머뭅니다. 셸은 관여하지 않습니다. 셸이 필요하면 위의 `sh`(`zsh -c`)처럼 명시하세요.
- `stdin`: 프로그램의 표준 입력으로 보낼 내용이며, 여기서도 `{input}`이 바뀝니다.
- `link`의 `url`은 `https://`여야 하며, `{input}`은 한 번, `?` 또는 `#` 뒤에 있어야 합니다. 텍스트는 인코딩되며(공백은 `%20`, 줄바꿈은 `%0A`) 최대 4000자입니다.
- `run`과 `terminal`은 기본적으로 영문자를 입력합니다(`@open`처럼. 중국어 모드에서는 끝나면 중국어로 돌아옵니다). 전각 문장 부호는 ASCII로 바뀝니다. 입력한 그대로 두려면 `"ascii": false`를 설정하세요.
- 프로그램은 홈 폴더에서 로그인 셸의 PATH로 실행됩니다(그래서 Homebrew, pyenv, nvm으로 설치한 것도 찾습니다). `run`은 10초 후(`timeoutSeconds`) 또는 출력이 너무 많을 때 프로그램을 멈추며, Esc로 언제든 멈출 수 있습니다.
- `summary`는 명령어 목록에 표시되는 설명입니다(선택 사항).
- `argv`의 프로그램을 찾을 수 없으면(예: `python3` 없음) 그 명령어는 제공되지 않고 `@python …`이 텍스트로 입력됩니다. 프로그램을 설치하면 다음 텍스트 필드부터 명령어가 나타납니다.

`run`과 `terminal`은 Mac에서 코드를 실행합니다. 직접 작성했고 신뢰하는 명령어만 추가하세요. 이 명령어들도 실행 키를 눌렀을 때만 실행되며, 보안 입력 중에는 절대 실행되지 않습니다.

### 스크립트 확장

나만의 @ 명령어를 프로그램으로 추가할 수 있습니다. 어떤 언어로 된 스크립트든(bash, Python, Node, Swift 등) 주석에 몇 줄의 메타데이터를 넣으면 됩니다. `~/.config/allinoneime/extensions`에 두거나, "Settings → Custom Commands → Script Extensions"(설정 → 사용자 지정 명령어 → 스크립트 확장)에서 추가한 폴더에 두세요. Raycast Script Commands는 그대로 작동하며, 이미 그것들이 들어 있는 폴더는 Spotlight로 찾아냅니다.

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh`는 `@flights`가 됩니다. 인수는 그 뒤에 쉼표로 구분해 씁니다. `@flights beijing, new york`은 `beijing`과 `new york`을 `$1`과 `$2`로 하여 실행합니다(그 이상의 쉼표는 마지막 인수에 남습니다). 필수 인수가 비어 있으면 실행하지 않고 무엇이 빠졌는지 알려 줍니다. 출력은 `output` 설정에 따라 사용됩니다:

| `output` | 동작 |
|---|---|
| `insert`(기본값) | 출력 전체와 각 줄을 삽입할 수 있습니다 |
| `show` | 출력되는 대로 패널에 표시됩니다(진행 상황). 아무것도 삽입되지 않습니다. 필드를 떠나면 백그라운드에서 계속됩니다(동시에 최대 4개) |
| `list` | Alfred의 Script Filter JSON 형식 목록으로, 입력할 때마다 다시 실행됩니다. 행을 고르면 삽입, 열기(웹 주소, 파일, 폴더. 실행될 수 있는 것은 절대 열지 않음), 복사, 또는 두 번째 단계 실행을 합니다 |
| `silent` | 마지막 줄을 커서 근처에 표시합니다. 아무것도 삽입되지 않습니다 |

명령어는 입력을 받지 않을 수도 있고(`input none`: 이름에서 ⏎를 누르면 실행), 백그라운드(`background`)에서 실행되다가 끝나면 알려 줄 수도 있으며(그동안 메뉴 막대 패널에 표시됨), 명령어 목록에서 이름 옆에 상태(`status`)를 표시하거나, 먼저 확인(`confirm`)을 받을 수도 있습니다. 명령어는 자기 폴더에서 로그인 셸의 PATH와 `ALLINONEIME_*` 변수(인터페이스 언어와 입력 언어, 입력 중인 앱, 텍스트)로 실행됩니다. **번들**은 명령어를 나열한 `extension.json`이 있는 폴더입니다. 번들의 명령어들은 코드와 환경설정을 공유하며, 환경설정은 설정에 표시됩니다(비밀번호는 키체인에 저장). 설정에는 모든 명령어가 스위치와 함께 나열되고, 제외된 스크립트도 그 이유와 함께 나열됩니다.

Raycast의 모드는 다음과 같이 대응됩니다: `fullOutput` → `show`, `compact`와 `silent` → `silent`, `refreshTime`이 있는 `inline` → 상태. 전체 프로토콜은 [docs/extensions.md](../extensions.md)에 있으며, [Examples/extensions](../../Examples/extensions)에는 종류별 예제가 하나씩 있습니다. 확장 기능은 Mac에서 코드를 실행합니다. 신뢰하는 것만 쓰세요. 확장 기능은 실행할 때만 동작하고(상태나 목록은 입력하는 동안), 보안 입력 중에는 절대 동작하지 않으며, 입력기가 종료되면 멈춥니다.

### 플러그인

플러그인은 모든 사람에게 필요하지는 않은 기능을 위한 기성 `@` 명령어입니다. 예를 들어 `@stock AAPL 600519 700`은 주가를 보여 줍니다. 설치하면 다른 명령어처럼 작동합니다. 설정의 "Plugins"(플러그인)에서 설치된 플러그인과 각 플러그인이 텍스트를 어디로 보내는지 확인하고, 제거할 수 있습니다. 플러그인은 별도 프로세스에서 실행되는 JavaScript로, 선언한 웹사이트(HTTPS)에만 접속할 수 있고 파일을 읽거나 다른 프로그램을 실행할 수 없습니다. 설정의 "Plugins"에 있는 "Browse Library…"(라이브러리 둘러보기…)로 [플러그인 라이브러리](https://github.com/MicroZ-LLC/AllInOneIME-plugins)에서 설치합니다. 설치 전에 플러그인이 접속하는 웹사이트를 보여 주며, 라이브러리의 색인은 서명되어 있고 모든 파일이 색인과 일치해야 합니다. 새 버전이 있으면 "Update"(업데이트) 버튼이 나타나며, 저절로 업데이트되는 것은 없습니다. 직접 만든 플러그인은 `~/.config/allinoneime/plugins/`("Open Plugins Folder", 플러그인 폴더 열기)에 둡니다. 이것은 로컬 플러그인이며 라이브러리가 덮어쓰지 않습니다. "Link"(링크) 플러그인은 코드를 실행하지 않습니다. 텍스트를 웹 주소에 넣어 브라우저에서 열 뿐입니다. 예를 들어 `@x nice weather today`는 텍스트가 채워진 X의 작성 화면을 엽니다. 게시할지는 페이지에서 여러분이 정합니다. 라이브러리에는 네 개가 있습니다(`@x`, `@threads`, `@bsky`, `@weibo`). `@xe`는 통화를 환산합니다: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`. 결과는 환율 날짜와 함께 한 줄로 나옵니다(환율 제공: ExchangeRate-API). 플러그인 작성법: [docs/plugins.md](../plugins.md).

무언가를 가져오는 명령어(플러그인과 프로그램)는 문장 안에서도 작동합니다: `@reply tell her @stock AAPL is up today`. 안쪽 명령어가 먼저 실행되어 그 출력이 자리를 대신하고, 바깥 명령어가 그 결과를 처리합니다. 인수는 명령어 뒤의 단어와, 그 바로 뒤에 오는 대문자 코드나 숫자입니다(`@stock AAPL TSLA`, `@stock 600519 700`). 소문자 단어가 나오면 끝납니다(`@stock SNDK is good to buy`는 SNDK를 조회합니다). 따옴표로 정확히 지정할 수 있습니다: `@stock "aapl tsla"`. `@calculate`도 문장 안에서 작동하며, 그 인수는 뒤에 오는 식 전체로, 공백을 포함해 다른 텍스트가 나올 때까지입니다: `@reply the total is @calculate 23 * 17 dollars`. `@claude`와 터미널 명령어 안에서는 실행되지 않습니다. 그런 명령어는 쓴 그대로의 텍스트를 받습니다(그 안에서 `@`를 입력해도 명령어 목록이 열리지 않습니다).

### 실행 키

기본값은 ⏎입니다. 설정의 "Action key"(실행 키)에서 바꿀 수 있습니다(설정 파일의 `actionKey`): ⏎, "Tap ⌥"(⌥ 가볍게 누르기. 양쪽 모두 가능하며, 눌렀다가 바로 뗍니다. 오른쪽 ⌥를 누르고 있는 것은 여전히 말하기용입니다), ⌥Space, 또는 Space(단어를 고른 뒤 Space를 한 번 더. 영어 모드에서는 두 번). 실행 키가 무엇이든 @ 명령어는 ⏎로도 실행됩니다. ⌥Space가 이미 Alfred, Raycast 같은 앱의 단축키라면 그 앱이 먼저 받습니다.

### 결과를 타이핑해 넣기

Settings → General에서 "Type results out"(결과를 타이핑해 넣기)을 켜면(설정 파일의 `typeOut`), 명령어의 결과가 한 번에 들어가는 대신 사람이 타이핑하듯 한 글자씩 앱에 입력됩니다. 병음으로 고른 단어는 여전히 한 번에 들어갑니다. 슬라이더로 속도를 글자당 6초부터 초당 40글자까지 정하고(`typeOutRate`), "Speed up and slow down (like a person)"(사람처럼 빨라졌다 느려졌다)은 속도가 바뀌는 짧은 연타로 입력합니다(`typeOutVaries`). Esc는 그 자리에서 멈추고, 다른 키는 나머지를 한 번에 입력합니다.

"Make occasional typos and fix them"(가끔 오타를 내고 고치기, `typeOutMistakes`)은 훨씬 더 사람처럼 보이게 합니다. 가끔 올바른 키 옆의 키를 누르고 늦어도 세 글자 뒤에 알아채 지운 뒤 다시 입력하거나, 글자나 공백을 두 번 입력했다가 지우거나, 짧은 단어를 입력했다가 지우고 다시 입력합니다. 100글자에 몇 번 정도이며, 두 개가 붙어서 나오지 않고 줄 맨 앞에서는 절대 일어나지 않습니다. 코드, 웹 주소와 이메일 주소, 숫자 안에서는 오타가 틀린 글자나 숫자 하나뿐이고 바로 고칩니다(편집기가 짝을 맞추거나 들여쓰기하는 괄호, 따옴표, 공백은 절대 틀리지 않습니다). 틀린 글자는 사용하는 키보드 배열(QWERTY, AZERTY, QWERTZ…)에서 이웃한 키입니다. 중국어, 일본어, 한국어는 머뭇거리기만 하고(두 글자를 입력했다가 지우고 다시 입력), 틀린 글자는 절대 넣지 않습니다.

오타를 되돌릴 수 있는 필드(TextEdit과 메모 같은 Apple의 텍스트 뷰, 브라우저, 대부분의 편집기)에서는, 끝까지 입력하거나 다른 키를 눌러 나머지를 한 번에 입력하면 텍스트가 결과와 정확히 같습니다. 오타 도중에 Esc를 누르면(또는 필드를 떠나면) 먼저 오타를 빼므로, 필드에는 결과의 앞부분이 정확히 남습니다. 오타가 보이는 동안 커서가 움직이면(클릭 등) 오타는 원래 자리에서 빠지고, 나머지는 오타 없이 입력됩니다.

터미널이나 커서 위치를 입력기에 알려 주지 않는 앱에서는 절대 오타를 내지 않습니다. 매번 첫 오타는 단순한 것(틀린 글자 하나, 한 번에 수정)이며, 필드가 오타를 되돌릴 수 있음을 보여 줄 때까지 그렇습니다. 오타가 보이는 동안 입력기는 키를 누를 때마다 그 전에 필드에 자신이 입력한 내용이 그대로 있는지 확인합니다. 바꿀 위치를 무시하는 필드는 오타를 되돌릴 수 없어서, 그곳에는 첫 오타가 남고 텍스트는 한 글자 어긋난 채로 끝나며(Esc나 다른 키 뒤에도 마찬가지), 그 앱에서는 다시 오타를 내지 않습니다. Settings → General의 오타 스위치 아래에 그런 앱이 나열되며, "Forget apps where typos couldn't be fixed"(오타를 고치지 못한 앱 잊기)로 다시 시도하게 할 수 있습니다.

### 앱별 설정 (신규)

Settings → Apps에서 앱마다 자체 설정을 줄 수 있으며, 모두 선택 사항입니다. 앱이 정하지 않은 항목은 모든 앱에 공통인 설정을 따릅니다.

| 설정 | 예 | 설정 파일 |
| --- | --- | --- |
| 그 앱의 텍스트 필드가 시작하는 입력 언어 | Slack은 영어, WeChat은 병음 | `inputLanguage` |
| 그곳에서 `@improve`가 제공하는 다시 쓰기 스타일 | Mail은 격식 있고 정중하게, Slack은 편하게 | `rewriteStyles` |
| 결과를 타이핑해 넣을지 여부 | 채팅 앱에서는 켜고, Mail에서는 끄기 | `typeOut` |
| 이 앱에서는 AI 사용 안 함 | `@improve`, `@translate`, `@question`, `@claude`와 사용자의 프롬프트 명령어는 그곳에서 아무것도 보내지 않고 그렇다고 알립니다. 입력과 다른 명령어는 동작합니다 | `noAI` |

"Add App…"(앱 추가)은 최근 입력한 앱을 보여 주거나 /Applications에서 하나를 고릅니다. 입력 메뉴의 "This App: <이름>"에는 입력 중인 앱을 위한 빠른 스위치가 있습니다(No AI, Type Results Out, 시작 언어). 설정 파일에서는 번들 ID별로 `appProfiles` 아래에 있습니다: `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. 번들 ID는 대소문자를 구분하지 않고 맞춥니다(`com.apple.Mail`은 Mail의 `com.apple.mail`입니다). `@reportissue`는 무언가를 설정한 앱의 수만 세고, 이름은 절대 밝히지 않습니다.

- 시작 언어는 기본 입력 언어처럼 동작합니다. 텍스트 필드가 활성화될 때 그 언어로 시작하고, 이후 Shift로 바꾼 언어는 설정이 바뀔 때까지 그 앱의 필드에서 유지됩니다.
- No AI에서도 AI 명령어는 @ 목록에 남아 있습니다. 실행하면 알림이 나오고, 쓴 내용은 그대로 남습니다. 사용자의 터미널 명령어(`"type": "terminal"`)는 AI가 아니라 프로그램을 실행하므로 그곳에서도 계속 동작합니다.

## 메뉴 막대 패널

<img src="../en/panel-swipe.png" width="520" alt="메뉴 막대 패널: 반투명 유리 질감에 메모, 미리 알림, Claude 작업이 카드로 표시됨. 왼쪽으로 쓸어 넘긴 행에 Remove 버튼이 보임">

메뉴 막대의 AllInOneIME 아이콘(테두리 없는 ∞와 커서 모양. 테두리가 있는 것은 입력 소스입니다)을 클릭하면 그 아래로 패널이 열립니다. 다른 곳을 클릭하면 닫힙니다:

- Notes(메모): `@note`로 저장한 메모 중 최신 5개. 클릭하면 Notes에서 엽니다.
- Reminders(미리 알림): Reminders의 AllInOneIME 목록에 있는 아직 완료하지 않은 미리 알림(`@reminder`가 이 목록에 추가합니다). 마감이 가까운 순으로 8개를 표시합니다. 동그라미를 클릭하면 완료 처리하고, 제목을 클릭하면 Reminders를 엽니다.
- Claude Tasks(Claude 작업): `@tasks`처럼 백그라운드 Claude 작업(`@claude`가 넘긴 것)을 최대 30개, 한 번에 5개씩 표시합니다. 스크롤하면 더 볼 수 있고, 검색 상자에서 제목과 답장을 검색할 수도 있습니다. 진행 상황과 마지막 답장의 첫 줄도 함께 보입니다. 클릭하면 Terminal에서 열어 이어서 할 수 있습니다.

행(메모, 미리 알림, 작업)을 두 손가락으로 왼쪽으로 쓸어 넘기면 "Remove"(제거) 버튼이 나타나고, 끝까지 쓸어 넘기면 바로 제거됩니다. 마우스에서는 오른쪽 클릭하세요. 제거는 패널에서 빼는 것일 뿐입니다. 메모는 Notes에, 미리 알림은 Reminders에(완료되지 않은 채로), 작업은 Claude Code에 그대로 남습니다.

헤더에는 개수("2 reminders · 1 task running" 등. 응답을 기다리는 작업은 "1 waiting for you"처럼 따로 셉니다)와 새로 고침 버튼이 있습니다. 입력 중인 앱의 포커스를 절대 빼앗지 않습니다. 미리 알림을 완료하거나 새로 고침해도 그 앱이 앞에 그대로 있습니다. 키보드 입력을 받는 것은 클릭한 뒤의 Claude 작업 검색 상자뿐입니다. 아이콘은 기본적으로 표시되며, 설정의 "Menu Bar Panel"(메뉴 막대 패널)에서 끌 수 있습니다.

무엇을, 언제 읽는지:

- Notes: 목록은 패널 자체의 기록이며(패널이 닫혀 있을 때도 유지), Notes를 실행시키는 일은 없습니다. Notes가 이미 실행 중이고 AllInOneIME가 이전에 Notes 제어를 허용받은 경우에만, 패널이 바뀐 제목과 삭제된 메모를 확인합니다.
- Reminders: 패널이 열릴 때, 60초마다, 그리고 미리 알림이 바뀔 때 AllInOneIME 목록을 읽습니다. 패널이 스스로 macOS에 접근 권한을 묻게 하는 일은 없습니다. macOS가 아직 묻지 않았다면 "Allow Access to Reminders"(미리 알림 접근 허용)를 표시하며, 그 버튼만 권한을 요청합니다. 거부했다면 "Open System Settings"(시스템 설정 열기)를 표시합니다.
- Claude 작업: 패널은 열려 있는 동안에만 `claude agents`를 실행합니다. 열릴 때 한 번, 새로 고침할 때, `@claude`가 작업을 넘길 때, 그리고 아직 끝나지 않은 작업이 있는 동안 15초마다 실행하며, 모두 끝나면 더 이상 실행하지 않습니다. 마지막 답장은 이 Mac에 있는 Claude Code 대화 기록(`~/.claude/projects`)의 끝부분에서, 기록이 바뀌었을 때만 읽습니다.
- 패널이 닫혀 있는 동안에는 이 중 아무것도 실행되지 않습니다. `@note`가 저장한 메모의 기록만 남깁니다.

## 입력과 번역

설정에서:

- **Input languages**(입력 언어): 영어, 중국어(병음), 프랑스어, 한국어, 힌디어 중 한 개에서 다섯 개까지 +로 추가합니다(+는 항상 있으며, 다섯 개가 되면 흐리게 표시됨). 새로 설치하면 영어만으로 시작합니다. 새 텍스트 필드는 첫 번째 언어로 시작하며, Shift를 가볍게 누르면 순서대로 다음 언어로 바뀝니다. 언어가 하나면 Shift로 바뀌지 않습니다.
  - **프랑스어**는 전용 키보드 레이아웃으로 입력합니다. 카드에서 다른 것을 고르지 않으면 AZERTY입니다. 데드 키(^, ¨, `, ´, ~)도 그 레이아웃으로 조합됩니다.
  - **한국어**는 두벌식 자판으로 한글을 입력하며, 입력하는 대로 음절을 조합합니다(g k s → 한). Shift로 ㄲ ㄸ ㅃ ㅆ ㅉ와 ㅒ ㅖ를 입력합니다.
  - **힌디어**: 단어를 소리 나는 대로 라틴 문자로 입력하면 데바나가리가 됩니다(namaste → नमस्ते). 흔한 단어는 힌디어 표기대로 적힙니다. 그 밖에는 Space가 첫 번째 표기를, 숫자가 다른 표기를, ⏎가 입력한 그대로의 글자를 삽입하고, "."은 단다(।)를 삽입합니다.
  - 명령어 이름, `@open`의 텍스트, 코드(`@py`, `@js`)는 언어와 상관없이 영문자로 입력하며, 명령어가 끝나면 원래 언어로 돌아옵니다.
  - `@improve`는 한국어, 힌디어, 프랑스어 문장을 그 언어 그대로 다루고, `@translate`는 그것을 여러분의 언어로 번역합니다(프랑스어가 입력 언어 중 하나이면 프랑스어와 영어를 구분합니다).
- **Language packs**(언어 팩): 앱에는 영어(그리고 macOS의 레이아웃만 있으면 되는 프랑스어)가 들어 있습니다. 중국어, 한국어, 힌디어는 추가할 때 다운로드하는 팩입니다. 중국어(병음)를 추가하면 사전(약 34 MB, 압축 해제 시 125 MB)이 진행 막대와 함께 다운로드되며, 다 되면 재시작 없이 바로 병음을 쓸 수 있습니다. 한국어 팩(키 배열표와 자모로 음절을 만드는 방법)과 힌디어 팩(문자와 흔한 단어)은 몇 KB입니다. 팩은 데이터만 담으며(사전, 표, 스키마. 코드는 절대 없음), 서명된 색인에 올라 있고 사용 전에 SHA-256을 확인합니다. 플러그인과 같습니다. 각 언어의 카드에는 그 팩(버전, 크기, 출처)이 "Delete…"(삭제…)와 함께 표시되며, 언어를 제거하면 팩도 삭제할지 묻습니다. 0.6.1 이하에서 업데이트하면 중국어는 다운로드 없이 유지됩니다. 설치 프로그램이 이전 버전에 들어 있던 사전을 남겨 둡니다.
- **후보 배열**: 단어를 고를 때 병음과 힌디어 후보는 기본적으로 가로로 나란히 놓입니다(Horizontal). 시스템 기본 입력기처럼 ← →로 고르고 ↑↓(또는 - =)로 페이지를 넘깁니다. 위아래로 놓으려면(↑↓로 선택) Input 페이지의 입력 언어 아래에서 Vertical을 고르세요. @ 명령어 목록과 결과는 항상 세로입니다.
- **Fuzzy pinyin**(퍼지 병음, 중국어 입력 시): 구분하지 않는 소리를 어느 쪽으로 입력해도 됩니다(예: z ↔ zh, n ↔ l, in ↔ ing). "Input"(입력) 페이지의 입력 언어 막대에서 중국어(병음)를 고르고, "Fuzzy pinyin"을 켠 다음 쌍을 고르세요. 사전이 1~2초 안에 다시 배포됩니다. Rime 사용자 폴더에 `rime_ice.custom.yaml`을 쓰며, 그곳에 있는 여러분 자신의 파일을 덮어쓰지는 않습니다.
- **Translate (@translate)**(번역): 번역할 언어(스페인어, 프랑스어, 독일어, 일본어, 한국어, 중국어, 힌디어, 벵골어, 타밀어 및 기타 주요 인도 언어…)를 추가하고 드래그해 순서를 정합니다. 라틴 문자로 입력한 힌디어("aap kaise ho")는 데바나가리로 돌아옵니다. `@translate`는 이 순서대로 언어마다 한 줄씩 씁니다(언어가 하나면 세 가지 버전). 문장 원래 언어는 건너뜁니다. 새로 설치하면 Mac의 선호하는 언어 중 영어가 아닌 첫 번째 언어로 번역합니다. 영어만 있으면 `@translate`가 이 페이지를 열어 언어를 추가하게 합니다.
- **Keyboard layouts**(키보드 레이아웃): 프랑스어는 카드에서 고른 레이아웃으로 입력합니다(설정 파일의 `keyboardLayouts`). 다른 언어에서는 입력기 아래에서 macOS가 마지막으로 쓴 라틴 레이아웃(AZERTY, QWERTZ, 스페인어, US International…)을 유지하므로 평소처럼 입력할 수 있고, `@`도 레이아웃상 원래 자리에 있으며, 데드 키도 명령어의 텍스트 안에서 조합됩니다(⌥E 다음 E → é, ^ 다음 e → ê). 라틴 문자가 없는 레이아웃(러시아어, 힌디어 InScript)은 입력기 아래에서 쓸 수 없습니다. ⌃Space로 그 레이아웃으로 전환하거나, 텍스트를 명령어에 붙여 넣거나(⌃V) 받아쓰기로 입력하세요.
- `@improve`는 번역하지 않고 다듬고 다시 씁니다. `@translate @improve`를 함께 쓰면 한 번의 요청으로 번역과 다시 쓰기를 합니다. 설정에서 "@improve also translates"를 켜면 `@improve`가 항상 그렇게 합니다.

## 다시 쓰기 스타일

1–3번 줄 다음에 다시 쓰기가 나오며, **입력한 언어로** 작성됩니다. 영어는 영어로, 중국어는 중국어로 다시 씁니다. 설정에서 원하는 것을 고르세요:

- Polish(다듬기): 같은 어조로, 더 자연스럽게
- Concise(간결하게)
- Formal(격식 있게): 상사와 고객용
- Casual(편하게)
- Tactful(완곡하게)
- Jargon(업계 용어): 영어에서는 Amazon식 말투(bandwidth, circle back…), 중국어에서는 대형 IT 기업의 업계 용어. 나쁜 소식은 순화됩니다. 예: "this is a blocker bug"(이건 출시를 막는 버그다) → "Oh! Looks like your team has the bandwidth to fix this minor issue!"(오! 팀에 이 사소한 문제를 고칠 여력이 있어 보이네요!)

문장 부호만 바꾸거나 다른 줄과 같은 다시 쓰기는 표시되지 않습니다.

### Jargon 용어 목록 (나만의 용어)

Jargon에는 내장 용어 목록이 없습니다. 나만의 목록(예: 팀에서 쓰는 표현)을 준비하면, 모델이 그 용어를 우선해서 씁니다. 후보의 Jargon 줄에는 사용한 용어의 뜻이 함께 적힙니다.

목록은 한 줄에 용어 하나씩 쓰는 텍스트 파일이며, 필요하면 그 뒤에 "=", 콜론, Tab으로 구분해 뜻을 덧붙입니다(스프레드시트에서 두 열을 복사해 붙여 넣을 수 있습니다). `#`로 시작하는 줄은 주석입니다:

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

설정의 "Rewrite Styles → Jargon list"(다시 쓰기 스타일 → Jargon 목록)에서 "New"(새로 만들기)를 클릭하면 `~/.config/allinoneime/jargon.txt`에 빈 목록을 만들고 엽니다. 이미 목록 파일이 있다면 "Choose File…"(파일 선택…)을 클릭해 그 자리에서 그대로 쓸 수 있습니다(설정 파일의 `jargonFile`). 변경 사항은 바로 적용됩니다. 처음 150개 용어만 읽습니다. "Jargon"을 체크하면 목록이 각 요청과 함께 Bedrock으로 전송됩니다.

<img src="../en/panel-dark.png" width="420" alt="다크 모드의 후보 패널">

## 음성 입력

<img src="../en/voice.png" width="340" alt="오른쪽 ⌥를 누른 채 말하기">

오른쪽 ⌥를 누른 채 말하고, 떼면 텍스트가 삽입됩니다. 입력 중인 언어(영어, 중국어, 프랑스어, 한국어, 힌디어)로 인식합니다. 먼저 명령어를 입력하고(예: `@improve `, `@question `) 말하면 텍스트가 명령어 뒤에 들어가고 ⏎로 실행합니다. 오른쪽 ⌥를 떼지 않고 ⏎를 눌러 말이 끝나자마자 실행할 수도 있습니다. 음성은 macOS 내장 음성 인식(SpeechAnalyzer)이 Mac에서 인식하며, 오디오는 업로드되지 않습니다. macOS 26 이상이 필요합니다.

처음에는:

- macOS가 AllInOneIME가 마이크를 사용하도록 허용할지 묻습니다. 설정에서 미리 "Allow Microphone"(마이크 허용)을 클릭해 둘 수도 있습니다.
- 이 Mac에 해당 언어의 음성 모델이 아직 없으면 한 번 자동으로 다운로드됩니다. 설정에서 다운로드할 수도 있습니다.

녹음은 키를 약 0.2초 누르고 있어야 시작되므로, 오른쪽 ⌥를 가볍게 누르기만 해서는 마이크가 켜지지 않습니다(실행 키가 "Tap ⌥"로 설정되어 있으면 가볍게 누르기가 동작을 실행합니다). 누르고 있는 동안 다른 키를 누르면(⌥ 단축키, ⌥←) 단축키로 간주되어 역시 녹음되지 않습니다. 녹음 중에 다른 키를 누르면 녹음이 취소됩니다.

## 설치

실행하려면 macOS 14 이상, 음성 입력에는 macOS 26 이상이 필요합니다. 설치 프로그램은 유니버설이라 Apple 실리콘과 Intel Mac 모두에서 작동합니다. 지금까지는 Apple 실리콘의 macOS 27에서만 테스트했습니다(Intel 빌드는 Rosetta에서 자체 테스트만 거쳤습니다).

1. [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)에서 `AllInOneIME-<version>.dmg`를 다운로드해(반드시 이곳에서만) 엽니다.
2. 그 안의 "Install AllInOneIME"을 더블 클릭하고 "Install"(설치)을 클릭합니다. 입력기는 `~/Library/Input Methods`에, "AllInOneIME Settings"는 `~/Applications`에 설치됩니다. 현재 사용자 전용이며 관리자 암호는 필요 없습니다.
3. 설치 프로그램은 Developer ID로 서명되고 Apple의 공증을 받았기 때문에, 처음 열 때 macOS는 인터넷에서 내려받은 앱을 열지 여부만 묻습니다. "열기"를 클릭하세요. (0.6.3 이전 버전은 공증을 받지 않아, 버전마다 시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기에서 한 번씩 허용해야 했습니다.)

그러면 AllInOneIME가 활성화되어 입력 소스에 추가됩니다. Ctrl+Space로 전환하세요(🌐 키는 System Settings → Keyboard(시스템 설정 → 키보드)에서 "Press 🌐 key to"가 "Change Input Source"로 설정된 경우에만 전환합니다). 설치 프로그램이 직접 추가하라고 하면, 이 Mac은 프로그램이 입력기를 활성화하도록 허용하지 않는 것이므로 한 번 직접 추가하세요: System Settings → Keyboard → Text Input → Input Sources → Edit… → +(왼쪽 아래) → English → AllInOneIME(설정의 "Input"에서 중국어를 추가하면 병음도 입력합니다).

Ctrl+Space로 AllInOneIME에 가지 않거나, 얼마 후 U.S.로 되돌아간다면 설치 프로그램을 다시 실행하세요. AllInOneIME를 입력 소스에 다시 추가합니다.

업데이트: Settings → About → Check for Updates(업데이트 확인). 새 버전이 있으면 About에 새로운 내용과 함께 표시되고(메뉴 막대 패널에도 한 줄 나타납니다), "Update to <version>"(<버전>으로 업데이트)을 누르면 내려받아 AllInOneIME의 릴리스 키로 서명된 업데이트 정보와 대조하고, 설치한 뒤 입력기를 다시 시작합니다. 설정, 언어 팩, 학습한 단어, 확장은 그대로 남고, 도중에 문제가 생기면 쓰던 버전으로 되돌립니다. AllInOneIME는 하루에 한 번 백그라운드에서 스스로 확인합니다(About의 "Check for updates automatically"로 끌 수 있습니다). 클릭하기 전에는 아무것도 설치하지 않습니다. 이 기능은 0.6.3부터 동작합니다. 더 오래된 버전을 업데이트하거나 원한다면, 제거하지 말고 새 버전의 디스크 이미지를 그 위에 설치하세요. 업그레이드하기 전에 [변경 기록](../../CHANGELOG.md)을 읽어 보세요. 버전별 변경 사항과 업그레이드 참고 사항이 있습니다.

이전 버전에서 0.6.3으로 업데이트하는 경우: 0.6.3은 Developer ID로 서명된 첫 버전이라, 키체인은 아직 이 앱을 키를 저장한 앱으로 알아보지 못합니다. 저장된 각 키(API 키, AllInOneIME Cloud 로그인, 확장의 암호)가 처음 필요할 때 macOS가 로그인 암호를 묻습니다. 암호를 입력하고 "Always Allow"(항상 허용)를 클릭하세요. 그 뒤로는 이후 업데이트 후에도 다시 묻지 않습니다. Amazon Bedrock의 키는 `~/.aws/credentials`에 있어서 영향을 받지 않습니다.

AIPinyin(AllInOneIME의 이전 이름)을 설치했었다면 그냥 설치하세요. 이전 AIPinyin.app과 그 설정 실행기는 제거되고, 입력 소스의 항목은 새 이름으로 바뀌므로 다시 추가할 필요가 없습니다. 설정, Jargon 목록, 학습한 단어는 처음 실행할 때 새 폴더(`~/.config/allinoneime` 등)로 옮겨지며, 이전 폴더는 각각 새 폴더를 가리키는 링크로 남습니다.

제거하려면 "Install AllInOneIME"을 열고 "Uninstall…"(제거…)을 클릭하세요. 설정과 학습한 단어는 유지됩니다.

### 소스에서 빌드하기

음성 입력이 macOS 26 SDK를 사용하므로 빌드하려면 Xcode 26 이상이 필요합니다.

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install`은 librime과 rime-ice 사전을 다운로드해 검증하고, 빌드한 뒤 같은 위치에 설치하며, 같은 방식으로 입력 소스에 추가합니다. 설치되는 앱에는 중국어 사전이 없습니다(사전은 중국어 언어 팩입니다). 사전이 있던 설치에서는 그것을 팩으로 유지하고, 그렇지 않으면 `make install-pack`이 체크아웃의 사전에서 다운로드 없이 팩을 설치합니다. `make status`는 설치된 버전(`version:`)과 입력 소스에 있는지(`listed:`)를 보여 줍니다. 제거: `make uninstall`.

## AI 설정

번역과 다시 쓰기에는 여러분의 AI 제공업체를 사용하며, 비용은 여러분의 계정에 청구됩니다. 기본값은 AWS 계정의 Amazon Bedrock이며, Claude API, Gemini, OpenAI 호환 서비스도 쓸 수 있습니다(아래 "기타 AI 제공업체" 참고).

### Amazon Bedrock

1. AWS 콘솔에서 Bedrock을 활성화하고, 선택한 모델을 쓸 수 있는지 확인하세요. 기본값은 Claude Haiku 4.5입니다. Anthropic 모델을 처음 쓸 때는 사용 사례 양식을 한 번 작성합니다.
2. `bedrock:InvokeModelWithResponseStream` 권한이 있는 액세스 키를 만들어 `~/.aws/credentials`의 프로필에 넣으세요. 현재는 이런 정적 키만 지원하며, SSO나 assume-role은 지원하지 않습니다.
3. "AllInOneIME Settings"를 여세요. Spotlight나 응용 프로그램 폴더에서 찾거나, 메뉴 막대의 입력기 아이콘 → "Settings…"(설정…)에서 열 수 있습니다. 프로필, 리전, 모델을 고르고 "Test Connection"(연결 테스트)을 클릭하세요. 설정 창 맨 위의 "Language"(언어)는 영어 또는 중국어로 할 수 있으며, 기본값("System")은 시스템을 따릅니다(시스템의 선호하는 언어에서 중국어가 영어보다 앞이면 중국어, 아니면 영어). 설정 창, 후보 패널의 힌트, 입력 메뉴가 모두 이를 따릅니다.

<img src="../en/settings.png" width="420" alt="설정 창">

### 기타 AI 제공업체: Claude API, Gemini, OpenAI 호환 서비스

AWS가 없어도 됩니다. 설정의 "AI Provider"(AI 제공업체)에서 하나를 고르고, API 키를 붙여 넣은 뒤 "Save"(저장), 이어서 "Test Connection"을 클릭하세요.

| 제공업체 | 기본 모델 | API 키 |
|---|---|---|
| Claude API | `claude-haiku-5-5`(가장 빠르고 저렴함. Sonnet 5.5와 Opus 5.5는 더 신중하지만 느리고 비쌈) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| OpenAI 호환 | OpenAI의 `gpt-6-luna`(또는 `gpt-5.4-mini`). "Common Services…"(자주 쓰는 서비스…)에는 DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter, 이 Mac의 Ollama가 있으며, 하나를 고르면 Base URL이 채워지므로 이어서 모델을 입력합니다 | 해당 서비스의 키. Base URL을 그 주소로 설정합니다(예: `https://api.deepseek.com/v1`, 이 Mac의 Ollama는 `http://localhost:11434/v1`) |

- API 키는 시스템 키체인에 보관되며, 설정 파일에는 절대 저장되지 않습니다. 키체인에 키가 없으면 셸의 `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`(또는 `GOOGLE_API_KEY`), `OPENAI_API_KEY`를 사용합니다.
- "Thinking"(사고)은 기본값이 낮음입니다. 입력기는 문장마다 기다리므로, 사고가 적을수록 빠릅니다. 이를 지원하지 않는 모델에는 "Not set"(설정 안 함)을 고르세요.
- Claude Opus 5.5나 Sonnet 5.5를 고르면 요청에 Claude API의 거부 시 대체(`fallbacks: "default"`)가 포함됩니다. 안전 분류기가 거부하면 서버가 다른 모델로 다시 시도합니다.
- 설정 파일에서: `provider`(`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), 그리고 `anthropic`, `gemini`, `openai` 아래의 `model`, `baseURL`, `effort`, `temperature`(설정하지 않은 것은 기본값 사용).

### 이 Mac의 Apple Intelligence (macOS 26)

Apple Intelligence를 쓸 수 있는 Mac(Apple 실리콘, macOS 26 이상, 시스템 설정 → Apple Intelligence 및 Siri에서 켜짐)에서는 "AI Provider"에서 "Apple Intelligence (on this Mac)"를 고르세요. 키도 비용도 필요 없고, 입력한 내용이 Mac 밖으로 나가지 않습니다. macOS에 내장된 모델(Foundation Models 프레임워크)을 사용하며, 지시와 답의 형식은 다른 제공업체와 같지만 예시는 문장 자체의 언어로 쓰인 것만 넣습니다(작은 모델은 예시의 언어를 너무 쉽게 따라 합니다).

- 작은 모델입니다. 컨텍스트가 약 4K 토큰(macOS 27에서는 8K)이라 긴 단락은 너무 길 수 있고, 지원하는 언어도 더 적습니다(영어, 중국어, 일본어, 한국어, 프랑스어, 독일어, 스페인어와 몇 가지 더. 힌디어는 지원하지 않음). 두 경우 모두 그렇다고 알려 줍니다. 결과는 클라우드 모델에 못 미치며, 사실이나 코드에 대한 `@question` 답은 자주 틀립니다.
- 쓸 수 없는 곳에서는 이유(이 Mac에서 지원하지 않음, 꺼져 있음, 모델이 준비되지 않음)와 함께 회색으로 표시되고, 설정에서 시스템 설정 → Apple Intelligence 및 Siri로 연결됩니다. macOS 26 이전에는 목록에 나오지 않습니다.
- "Model Settings"의 "Output tokens", temperature, 시간 제한이 적용됩니다. 설정 파일에서는 `"provider": "apple"`입니다.

### 민감한 정보 숨기기 (신규)

Settings → AI Provider → Privacy → "Hide sensitive information before sending"(보내기 전에 민감한 정보 숨기기, 기본값은 끔): 요청이 AI로 가기 전에, 텍스트에서 찾은 내용을 Mac에서 `[EMAIL_1]` 같은 자리 표시자로 바꾸고(같은 값에는 같은 자리 표시자), 결과는 표시하거나 삽입하기 전에 실제 값을 되돌려 받습니다. 패널에는 "2 items hidden from the AI"(AI에게 2개 항목을 숨김)라고 표시됩니다. 종류마다 끌 수 있습니다.

| 종류 | 예 | 설정 파일 |
| --- | --- | --- |
| 이메일 주소 | `bob@example.com` | `emails` |
| 전화번호 | `+1 (555) 123-4567`, `138 0013 8000` | `phones` |
| 결제 카드 번호(Luhn 검사) | `4111 1111 1111 1111` | `cards` |
| API 키와 토큰 | `sk-`나 `ghp_` 같은 알려진 접두어, 긴 무작위 문자열 | `keys` |
| IP 주소 | `203.0.113.42`, `2001:db8::1` | `ips` |
| 직접 등록한 단어(대소문자 구분 없음) | `Project Atlas` 같은 코드명, 이름 | `customWords` |

- `@improve`, `@translate`, `@question`, 사용자의 프롬프트 명령어와 프롬프트 플러그인, 그리고 그 결과 다듬기(같은 자리 표시자)에 적용되며, AllInOneIME Cloud와 Apple Intelligence를 포함한 모든 제공업체에서 동작합니다. 숨길 값이 들어 있는 Jargon 용어 목록 항목은 보내지 않습니다.
- 형식이 있는 값은 알아보지만, 이름이나 주소는 알아보지 못하므로 그런 것은 직접 등록한 단어로 추가하세요. `@claude`, 웹사이트에서 데이터를 가져오거나(`@stock`) 웹사이트를 여는(`@x`) 플러그인, 스크립트 확장은 입력한 그대로 텍스트를 보냅니다. 자세한 내용은 개인정보 보호를 참고하세요.
- 설정 파일에서: `"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`.

모든 설정은 `~/.config/allinoneime/config.json`에 저장됩니다. 바꾸면 재시작 없이 다음 번역부터 새 설정이 쓰입니다. 새로 추가된 키:

| 키 | 동작 | 기본값 |
|---|---|---|
| `inputLanguages` | 입력 언어, 한 개에서 다섯 개, 첫 번째가 기본: `"en"` 영어, `"zh"` 중국어(병음), `"fr"` 프랑스어, `"ko"` 한국어, `"hi"` 힌디어. 예: `["en", "zh"]`, `["fr", "en", "ko"]`. 중국어, 한국어, 힌디어는 팩을 설치하면 작동합니다 | `["en"]`(새 설치) |
| `keyboardLayouts` | 입력 언어가 쓰는 키보드 레이아웃, 언어 코드로 지정(현재 프랑스어만): `{"fr": "com.apple.keylayout.French-PC"}` | 프랑스어: `com.apple.keylayout.French`(AZERTY) |
| `outputLanguages` | `@translate`가 번역할 언어, 순서대로: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | `@improve`에서도 번역(`@translate @improve`처럼) | `false` |
| `voiceInput` | 오른쪽 ⌥를 누른 채 말하기 | `true` |
| `actionKey` | 실행 키: `"enter"`(⏎), `"optionTap"`(Tap ⌥), `"optionSpace"`(⌥Space), `"space"`(Space) | `"enter"` |
| `uiLanguage` | 인터페이스 언어(설정 창, 후보 패널 힌트, 메뉴): `"zh"`, `"en"` | `null`(시스템 따름) |
| `rewriteStyles` | 다시 쓰기 스타일: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`. 예: `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | 나만의 Jargon 목록 파일 | `null`(즉 `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | 메뉴 막대 아이콘과 그 드롭다운 패널 | `true` |
| `candidateLayout` | 병음과 힌디어 후보: `"vertical"`(위아래로) 또는 `"horizontal"`(나란히; ← →로 선택, ↑↓로 페이지 넘김) | `"horizontal"` |
| `fuzzyPinyin` | 퍼지 병음 쌍: `["z-zh", "n-l", "in-ing"]`(z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | @ 명령어가 필드에서 선택한 텍스트를 대상으로 동작 ("선택한 텍스트에서" 참고) | `true` |
| `checkForUpdates` | 하루에 한 번 백그라운드에서 새 버전을 찾음. 클릭하기 전에는 아무것도 설치하지 않음 | `true` |
| `rememberQuestions` | 최근 `@question` 질문 5개와 답을 이 Mac에 보관하고 `@question` 아래에 표시 ("최근 질문" 참고) | `true` |
| `appProfiles` | 앱 하나의 설정, 번들 ID별, 모두 선택 사항: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI` ("앱별 설정" 참고) | `{}` |
| `redaction` | 민감한 정보를 AI에게 숨김 (개인정보 보호 참고): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`. 각 감지기(`emails`, `phones`, `cards`, `keys`, `ips`)는 `false`로 두지 않는 한 켜져 있음 | `enabled: false` |

## 개인정보 보호

- 타이핑(영어와 병음)과 `@calculate` 계산은 전적으로 로컬에서 이루어집니다. `@improve`, `@translate`, `@question`에서 실행 키를 눌렀을 때만 그 문장이 여러분이 고른 AI 제공업체(여러분의 Bedrock, 또는 키를 추가한 서비스)로 전송됩니다. "Jargon"을 체크하고 Jargon 목록을 설정했다면 목록도 함께 전송됩니다. 결과 다듬기(결과 뒤에 입력한 지시와 ⏎)는 표시된 결과와 지시를 붙여 같은 요청을 다시 보냅니다.
- AllInOneIME Cloud를 쓰면 문장은 개발자의 서버를 거쳐 모델 제공업체로 갑니다(현재는 OpenRouter를 거침). 서버는 횟수만 보관하며, 텍스트는 절대 보관하지 않습니다. 로그인 시에는 이메일 주소만 보관합니다.
- 민감한 정보 숨기기(Settings → AI Provider → Privacy, 기본값은 끔): 어떤 요청이든 나가기 전에(`@improve`, `@translate`, `@question`, 사용자의 프롬프트 명령어와 프롬프트 플러그인, AllInOneIME Cloud를 포함한 모든 제공업체), 이메일 주소, 전화번호, 결제 카드 번호(Luhn 검사), API 키와 토큰(`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…`, 긴 무작위 문자열), IP 주소, 직접 등록한 단어(코드명, 이름)를 Mac에서 `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]` 같은 자리 표시자로 바꿉니다. 같은 값에는 같은 자리 표시자가 붙습니다. 모델의 결과는 표시하거나 삽입하기 전에 실제 값을 되돌려 받으며, 패널에는 "2 items hidden from the AI"라고 표시됩니다. 모델이 자리 표시자를 알아볼 수 없을 만큼 바꾼 결과는 쓰인 그대로 보여 주고 "⚠ placeholder changed"로 표시합니다. 숨긴 값이 들어 있는 Jargon 용어 목록 항목은 보내지 않습니다. 종류마다 끌 수 있습니다. 전각 형태(`zhang＠example.com`, `１３８…`)도 찾아내며, 값이나 구절이 줄바꿈으로 나뉘어 있어도 됩니다. 이메일, 번호, 키처럼 형식이 있는 값은 알아보지만, 이름이나 주소(직접 등록한 단어로 추가하세요), 다른 문자 체계의 비슷하게 생긴 글자는 알아보지 못합니다. 사용자의 AI 서비스로 가는 요청에 적용됩니다. `@claude`, 웹사이트에서 데이터를 가져오거나(`@stock`) 웹사이트를 여는(`@x`) 플러그인, 스크립트 확장은 입력한 그대로 텍스트를 보냅니다. 설정 파일에서는 `redaction`(`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`)입니다.
- 음성은 오른쪽 ⌥를 누르고 있는 동안에만 녹음되며 Mac에서 인식됩니다. 인식된 텍스트는 위의 명령어에서 실행 키를 눌렀을 때만 전송됩니다.
- 입력기는 명령어 안에서 ⌃V나 ⌘V를 누를 때만 클립보드 텍스트를 한 번 읽습니다. 암호 관리자가 숨김으로 표시한 내용은 읽지 않습니다. 텍스트는 먼저 명령어 안에 표시되며, 역시 실행 키를 눌렀을 때만 전송됩니다. 최근 macOS 버전은 AllInOneIME가 클립보드를 읽도록 허용할지 묻습니다. 허용하세요. 매번 묻지 않게 하려면 System Settings → Privacy & Security에서 AllInOneIME의 붙여넣기 권한을 항상 허용으로 설정하세요.
- 암호 필드에서는 macOS가 자체 키보드(U.S. 또는 ABC)로 전환하고, 필드를 벗어나면 되돌립니다. 입력 중인 앱이 보안 입력을 유지하는 동안 AllInOneIME는 글자를 조합하지 않고 녹음도 할 수 없으며, 키는 입력한 그대로 들어갑니다. 또한 시스템이 보안 입력 상태인 동안(암호 필드, Terminal의 Secure Keyboard Entry(보안 키보드 입력) 등)에는 아무것도 AI로 전송되지 않습니다.
- `@note`와 `@reminder`는 AI로 가지 않습니다. AllInOneIME는 텍스트를 이 Mac의 Notes와 Reminders에만 넘기며, 미리 알림의 시간도 Mac에서 해석합니다(그 앱들이 다른 기기로 동기화하는지는 iCloud 같은 계정에 달려 있습니다). 그래서 보안 입력 중에도 작동합니다.
- `@reportissue`(와 "Report an Issue…")는 스스로 아무것도 보내지 않습니다. 브라우저에서 GitHub의 새 issue 페이지를 열고, 입력한 제목과 위에 나열한 버전, 언어, 제공업체 종류, 개수를 붙이며, 이 내용은 먼저 후보 패널에 표시됩니다. 거기서 Submit을 클릭하지 않으면 GitHub에는 아무것도 전달되지 않습니다.
- `@open`은 이 Mac에서만 검색합니다. 그것으로 연 항목(최근 200개)을 입력기 자체의 환경설정(config.json이 아님)에 기억해 두었다가 먼저 나열합니다.
- Settings → Apps의 "Add App…"을 위해 입력기는 최근 입력한 앱 12개의 번들 ID를 자체 환경설정에 보관합니다. 그 앱에 관한 다른 정보는 보관하지 않습니다.
- `@question`은 최근 질문 5개를 답과 질문한 시각과 함께 이 Mac의 `~/Library/Application Support/AllInOneIME/recent-questions.json`(사용자 계정만 읽을 수 있음)에만 기억해 두고 `@question` 아래에 보여 줍니다. 저장된 답은 온라인에 접속하지 않고 거기서 표시됩니다. 보안 입력 중에는 아무것도 보관하지 않으며, 선택한 텍스트에 대한 질문은 아예 보관하지 않습니다(그 답은 선택 영역에 관한 것이라, 보관하면 선택 영역이 디스크에 남게 됩니다). Settings → General → "Remember recent questions"로 끌 수 있으며, 끄면 삭제됩니다(설정 파일의 `rememberQuestions`). "Clear"는 질문을 삭제합니다.
- 메모를 나열하기 위해, 메뉴 막대 패널은 `@note`로 저장한 최근 30개 메모의 ID와 첫 줄(최대 80자)을 입력기 자체의 환경설정에 보관합니다. 패널이 꺼져 있을 때도 마찬가지입니다.
- `@py`와 `@js`는 실행 키를 눌렀을 때만, 그리고 여러분이 직접 입력하거나 붙여 넣은 코드만 실행합니다. AI의 답이나 다른 명령어의 출력은 절대 코드로 실행되지 않습니다. `@py`는 Mac의 `python3`를 사용하므로 Terminal에서처럼 파일을 읽고 쓰고 온라인에 접속할 수 있습니다. `@js`는 별도 프로세스에서 실행되어 파일을 읽거나, 네트워크에 접근하거나, 다른 프로그램을 실행할 수 없습니다. 둘 다 보안 입력 중에는 실행되지 않습니다.
- 업데이트 확인: 하루에 한 번("Check for updates automatically"가 꺼져 있지 않다면) AllInOneIME는 https://allinoneime.com/update.json과 그 서명을 내려받습니다. 요청에는 식별자도, 입력한 내용도 들어 있지 않습니다. 업데이트는 Update를 클릭했을 때만 GitHub 릴리스에서 내려받습니다.
- 로그에는 입력 내용이 기록되지 않습니다. macOS는 모든 타사 입력기에 대해 "The developer can access anything you type with this input source"(개발자가 이 입력 소스로 입력하는 모든 내용에 접근할 수 있습니다)라고 경고하는데, 이는 시스템의 일반적인 경고입니다.

## 개발

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

코드 구성:

- `Sources/AllInOneIMECore`: Bedrock 클라이언트, SigV4, 프롬프트, 2단계 입력 상태 머신(@ 명령어와 음성 제스처 포함). AppKit 의존성 없음
- `Sources/AllInOneIMERime`: librime 래퍼
- `Sources/AllInOneIME`: InputMethodKit 입력기, 후보 패널, 설정 창, 음성 인식
- `Sources/AllInOneIMESettings`: "AllInOneIME Settings" 실행기
- `Sources/AllInOneIMEInstaller`: 디스크 이미지의 "Install AllInOneIME". 설치, 업데이트, 제거를 담당

언어 팩은 플러그인과 별도로 자체 라이브러리가 있습니다. 저장소 [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages)이며, https://languages.allinoneime.com/ 에서 제공되고 자체 키로 서명됩니다. `make pack`이 아카이브를 빌드하면 그곳에 릴리스 애셋으로 게시되며(릴리스 `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json`이 그곳에 `packs.json`을 쓰고, 키체인에 있는 언어 팩 키(`allinoneime-languages-signing`)로 서명해 `packs.json.sig`를 만듭니다. 앱은 https://languages.allinoneime.com/packs.json 을 읽고 서명을 확인한 다음, 아카이브의 크기와 SHA-256을 확인합니다. 로컬 서버에서 팩을 시험하려면: `--test-key`로 테스트 키로 서명하고, `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`를 실행합니다.

버전 출시하기 (앱 내 업데이트는 릴리스 전용 키로 서명된 https://allinoneime.com/update.json을 읽습니다):

1. 버전을 올리고(`AppVersion.swift`와 Info.plist 세 개. `AppVersionTests`가 서로 일치하는지 확인합니다) 변경 기록을 갱신합니다.
2. `make dmg NOTARY_PROFILE=<profile>`: `build/AllInOneIME-<version>.dmg`와 그 `.sha256`, 그리고 `build/AllInOneIME-<version>-update.zip`(디스크 이미지의 설치 프로그램에 든 것과 같은 두 앱)을 만듭니다. 앱과 이미지는 키체인에 있는 Developer ID Application 인증서로 서명되고, 이미지는 그 `xcrun notarytool` 키체인 프로필로 공증된 뒤 스테이플(staple)됩니다.
3. 두 파일을 GitHub 릴리스 `v<version>`에 올리고 게시합니다.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"`(각각 한두 문장): `site/public/update.json`(앱에서 읽은 버전, 빌드, 최소 macOS, 파일의 주소, 크기, SHA-256, 릴리스 노트 주소와 요약)을 쓰고, 로그인 키체인의 키(`allinoneime-releases-signing`. macOS가 접근 허용을 물을 수 있습니다)로 서명해 `update.json.sig`를 만듭니다. 둘 다 커밋합니다.
5. 릴리스 파일을 내려받을 수 있게 된 뒤에만 사이트를 배포합니다(`cd site && npx wrangler@4 deploy`). 앱은 하루에 한 번 확인하며, `AllInOneIME --check-update`로 앱이 보는 내용을 확인할 수 있습니다.

앱은 매니페스트를 읽기 전에 내장된 공개 키로 서명을 확인하고, 더 새롭지 않은 버전은 절대 설치하지 않으며, https로 allinoneime.com 또는 이 저장소의 GitHub 릴리스 파일에서만 내려받고, 아카이브의 크기와 SHA-256이 매니페스트와 일치하고 두 앱의 번들 ID, 버전, 코드 서명이 확인되며 새 입력기가 시작될 때에만 설치합니다. 그런 다음 입력기는 자신의 실행 파일을 도우미로 넘겨(`--apply-update`) 작업을 맡깁니다. 도우미는 입력기가 종료되기를 기다렸다가 설치 프로그램과 같은 방식으로 앱을 바꾸고(이전 앱은 옆으로 옮겨 두고, 실패하면 되돌림) 새 앱을 등록합니다. 로컬 서버로 시험하려면: `make update-test`, 또는 `Scripts/build-update-manifest.swift`의 `--test-key`와 `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`를 사용합니다.

번들 ID는 여전히 `com.aipinyin.inputmethod.AIPinyin`입니다. macOS가 이것으로 추가된 입력 소스와 마이크 권한을 기억하므로, 바꾸면 입력기를 다시 추가하고 권한을 다시 허용해야 합니다.

## 라이선스

Copyright © 2026 MicroZ LLC. 소스는 [Functional Source License 1.1](../../LICENSE)(FSL-1.1-ALv2)에 따라 공개됩니다. 경쟁 제품을 제외한 모든 목적으로 사용하고, 읽고, 수정하고, 공유할 수 있습니다. 각 버전은 출시 2년 후 Apache-2.0이 됩니다. 0.6.1까지의 버전은 GPL-3.0으로 출시되었으며 계속 그 라이선스로 제공됩니다.

타사 구성 요소(librime과 그 플러그인은 BSD-3-Clause, rime-ice의 Lua 스크립트와 중국어 언어 팩은 GPL-3.0)는 [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)에 나와 있습니다.
