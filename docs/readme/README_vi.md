<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · [繁體中文](README_zh-TW.md) · [日本語](README_ja.md) · [한국어](README_ko.md) · [Français](README_fr.md) · [Deutsch](README_de.md) · [Español](README_es.md) · [Português (Brasil)](README_pt-BR.md) · [Italiano](README_it.md) · [Русский](README_ru.md) · **Tiếng Việt** · [ไทย](README_th.md) · [Bahasa Indonesia](README_id.md) · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · [Türkçe](README_tr.md)

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="Biểu tượng AllInOneIME">

# AllInOneIME

### Lệnh AI trong mọi ô văn bản trên máy Mac của bạn.

Gõ `@improve`, `@translate` hoặc `@question` trong bất kỳ ứng dụng nào, nhấn ⏎ và chọn kết quả.<br>
Không phải sao chép vào cửa sổ chat, không phải chuyển ứng dụng. Nhà cung cấp AI của riêng bạn, khóa của riêng bạn.

[![Phiên bản phát hành](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14 trở lên](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#cài-đặt)
[![Đã được Apple notarize](https://img.shields.io/badge/Apple-notarized-0a84ff?logo=apple&logoColor=white)](#cài-đặt)
[![Apple silicon và Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#cài-đặt)
[![Giấy phép: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![Lượt tải](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[Tải về](https://allinoneime.com/download)** · **[Trang web](https://allinoneime.com)** · **[Tài liệu](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[Tiện ích mở rộng](../extensions.md)**

[Cách sử dụng](#cách-sử-dụng) · [Lệnh](#lệnh--beta) · [Lệnh của riêng bạn](#lệnh-của-riêng-bạn) · [Ngôn ngữ](#nhập-liệu-và-dịch) · [Giọng nói](#nhập-bằng-giọng-nói) · [Cài đặt](#cài-đặt) · [Quyền riêng tư](#quyền-riêng-tư)

<br>

<img src="../en/demo.png" width="820" alt="@translate và một câu, rồi ⏎: mỗi dòng một bản dịch tiếng Tây Ban Nha, tiếng Pháp và tiếng Đức">

</div>

*Đây là bản dịch của README tiếng Anh; nếu hai bản có chỗ khác nhau, bản tiếng Anh là bản đúng.*

> [!NOTE]
> Từ 0.6.3, AllInOneIME được ký bằng Developer ID và được Apple công chứng (notarize): không cần cho phép nó trong System Settings → Privacy & Security (Cài đặt hệ thống → Quyền riêng tư & Bảo mật) nữa. Sau khi cập nhật từ một phiên bản cũ hơn, macOS sẽ hỏi mật khẩu đăng nhập của bạn một lần cho mỗi khóa mà AllInOneIME đã lưu trong keychain: nhập mật khẩu rồi nhấp "Always Allow" (Luôn cho phép). Chỉ tải AllInOneIME từ [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) hoặc [allinoneime.com](https://allinoneime.com).

Một bộ gõ cho macOS mang các lệnh AI vào mọi ô văn bản. Bắt đầu câu bằng `@` và nhấn ⏎ khi viết xong: `@improve` trau chuốt những gì bạn viết và đưa ra vài cách viết lại, `@translate` dịch nó sang các ngôn ngữ bạn chọn, `@question` đặt một câu hỏi, `@claude` giao nó cho Claude Code, và `@open` tìm tệp và ứng dụng hoặc mở một địa chỉ web. Bạn cũng có thể giữ phím ⌥ bên phải và nói. Khi không có `@`, các phím bạn gõ vẫn đi vào ứng dụng như thường lệ. Nó còn gõ được tiếng Trung (pinyin, xây dựng trên Rime và rime-ice), tiếng Pháp, tiếng Hàn (Hangul) và tiếng Hindi (chữ Devanagari từ chữ cái Latin), và chạy các script của riêng bạn như những lệnh @.

![@improve và một câu viết vội, rồi ⏎: các phiên bản đã trau chuốt, cùng các bản viết lại](../en/improve.png)

Để biết thêm chi tiết (mọi lệnh và cài đặt, khắc phục sự cố khi cài đặt, quyền riêng tư), xem [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Được tạo bởi [Weijian Zhang](https://weijianz.com) tại MicroZ LLC.

## Cách sử dụng

Khi không có `@`, bộ gõ không can thiệp: ở chế độ tiếng Anh, chữ cái được gõ trực tiếp và ⏎ là phím Return; không có gì được gửi lên mạng. Bản cài mới gõ tiếng Anh; để gõ thêm tiếng Trung (pinyin), tiếng Pháp, tiếng Hàn hoặc tiếng Hindi, hãy thêm ngôn ngữ đó trong phần cài đặt (xem [Nhập liệu và dịch](#nhập-liệu-và-dịch)).

| Phím | Chức năng |
|---|---|
| Gõ pinyin, Space / chữ số | Ở chế độ tiếng Trung: chọn từ, như mọi bộ gõ pinyin khác |
| `@` (ở đầu câu) | Mở danh sách lệnh: các lệnh dùng nhiều gần đây đứng trước, mỗi lần 5 lệnh, cuộn bằng ↑↓, con lăn chuột hoặc trackpad; hoặc gõ chữ cái để tìm (tên được gõ đầy đủ đứng đầu, rồi đến các tên bắt đầu bằng các chữ đó, rồi các tên chứa chúng). ⏎, Tab, Space hoặc một chữ số để chọn |
| ⏎ | Chạy lệnh. Vẫn hoạt động khi pinyin chưa được chọn: pinyin sẽ được chọn trước, như khi nhấn Space |
| Space, ⏎ / chữ số | Khi kết quả đã hiện ra: chèn kết quả đang được tô sáng / kết quả mang số đó; 0 là bản gốc |
| ⌘C | Sao chép kết quả đang được tô sáng (với `@open` là đường dẫn); bảng ứng viên vẫn mở |
| ⌃V | Trong một lệnh (ví dụ sau `@improve `): nối văn bản trong bộ nhớ tạm (clipboard) vào sau những gì bạn đã gõ thay vì dán vào ứng dụng. Nhiều dòng được gộp thành một, tối đa 2000 ký tự mỗi lần (`@note` giữ nguyên ngắt dòng và nhận tối đa 20000). Hoạt động trong mọi ứng dụng; khi không có lệnh, phím được chuyển đến ứng dụng như thường lệ |
| ⌘V | Giống ⌃V, nhưng một số ứng dụng tự xử lý ⌘V (các terminal như Ghostty, iTerm2 và Terminal, cùng với Notes) và dán vào ứng dụng như thường lệ; ở những nơi đó hãy dùng ⌃V |
| Esc, ⌫ | Quay lại câu để tiếp tục sửa; gõ dấu câu hoặc chữ số sau khi có kết quả sẽ viết tiếp câu. Sau một lần tinh chỉnh: quay lại kết quả trước đó |
| Chữ cái, khi kết quả AI đã hiện | Một chỉ dẫn tiếp theo, như `shorter`: ⏎ tinh chỉnh kết quả (xem [Tinh chỉnh kết quả](#tinh-chỉnh-kết-quả-mới)) |
| Nhấp vào một dòng | Trong bảng ứng viên: chọn dòng đó, như chữ số của nó (một từ, một lệnh trong danh sách, một kết quả, một tệp của `@open`, một người nhận, một dòng của tiện ích mở rộng); dòng dưới con trỏ được tô sáng. Ô văn bản vẫn giữ tiêu điểm |
| Nhấn nhanh Shift | Khi có nhiều ngôn ngữ nhập: chuyển sang ngôn ngữ kế tiếp theo thứ tự của chúng (tiếng Anh → tiếng Trung → tiếng Pháp → …, rồi quay lại ngôn ngữ đầu tiên) |
| Giữ ⌥ bên phải | Nói, thả ra để dừng. Bằng ngôn ngữ bạn đang gõ (tiếng Anh, tiếng Trung, tiếng Pháp, tiếng Hàn hoặc tiếng Hindi). Trong một lệnh, văn bản được đặt sau lệnh; nếu không, văn bản được chèn trực tiếp |

## Lệnh @ (beta)

| Lệnh | Chức năng |
|---|---|
| `@improve` | Trau chuốt: 1–3 là ba phiên bản bằng chính ngôn ngữ của câu, từ 4 trở đi là các kiểu viết lại (thêm và sắp xếp trong phần cài đặt), 0 là bản gốc. Không dịch; khi bật "@improve also translates" (@improve kiêm dịch), lệnh hoạt động như `@translate @improve` |
| `@translate` | Dịch sang các ngôn ngữ bạn đã thêm (cài đặt → "Translate", kéo để sắp xếp lại), mỗi ngôn ngữ một dòng, ba phiên bản nếu chỉ có một ngôn ngữ; ngôn ngữ của chính câu đó được bỏ qua. `@translate @improve` dùng cùng nhau sẽ dịch và viết lại trong một yêu cầu |
| `@question` | Đặt câu hỏi; câu trả lời hiện trong danh sách ứng viên, ⏎ hoặc Space chèn nó, ⌘C sao chép nó. Khi không gõ gì sau lệnh, nó liệt kê 5 câu hỏi gần nhất của bạn, mới nhất đứng trước; gõ thêm để lọc (các từ ở bất kỳ đâu trong câu hỏi, không phân biệt hoa thường, cả tiếng Trung). Một chữ số, ↑↓ rồi ⏎, hoặc một cú nhấp sẽ hiện ngay câu trả lời đã lưu của câu hỏi, không cần mạng, để chèn hoặc sao chép như thường; ở đó R hỏi lại để lấy câu trả lời mới. Khi không có kết quả khớp, hoặc không chọn gì, ⏎ hỏi điều bạn đã gõ |
| `@claude` | Giao việc cho Claude Code: mặc định chạy nền, có thông báo khi xong (nhấp vào để mở phiên làm việc trong Terminal và làm tiếp), hoặc xem `@tasks`. Lệnh dùng Claude Code của chính bạn (lệnh `claude`) với đăng nhập và cài đặt riêng của nó. Tắt "@claude runs in the background and notifies me" (@claude chạy nền và báo cho tôi) trong phần cài đặt để mở nó trong Terminal như trước. Lần đầu mở Terminal, macOS hỏi AllInOneIME có được điều khiển Terminal không: nhấp OK |
| `@tasks` | Liệt kê các tác vụ Claude chạy nền (đang làm / đã xong / đang chờ bạn) cùng câu trả lời gần nhất của chúng; ⏎ mở một tác vụ trong Terminal, ⌘C sao chép câu trả lời |
| `@settings` | Mở ngay cửa sổ cài đặt (chỉ cần chọn lệnh là đủ) |
| `@open` | Liệt kê tệp, thư mục và ứng dụng khớp với những gì bạn gõ (Spotlight). Có thể dùng nhiều từ khóa, cách nhau bằng dấu cách: mỗi từ phải có trong đường dẫn, ít nhất một từ có trong tên (tên của một thư mục chuẩn được tính cho những gì nằm trong nó: `downloads pdf` tìm các tệp PDF trong Downloads). Ứng dụng và các thư mục chuẩn cũng tìm được bằng tên tiếng Trung, và giao diện tiếng Trung hiển thị chúng theo tên đó. Những gì bạn đã mở bằng `@open` xếp trước, sau đó đến ứng dụng và các thư mục kia, rồi đến các tệp được dùng hoặc thay đổi gần đây; khi tìm theo tên chỉ ra hai tệp trở xuống và không có ứng dụng hay thư mục nào thuộc loại kể trên, các tệp trong thư mục home của bạn cũng được tìm theo nội dung, những dòng đó được đánh dấu "content" (nội dung); khi không còn gì khác, ⏎ liệt kê chúng để chọn thay vì mở kết quả đầu tiên. Với một địa chỉ web (`github.com`, `localhost:3000`, `https://…`), dòng đầu tiên là "open in the browser" (mở trong trình duyệt) và nội dung tệp không được tìm; tệp có tên đúng như vậy (chẳng hạn `MANIFEST.in`) xếp trước. Văn bản bắt đầu bằng `~/` hoặc `/` là một đường dẫn: Tab hoàn thành nó và đi vào thư mục; ⏎ để mở, ⌘C sao chép đường dẫn |
| `@note` | Lưu văn bản vào ứng dụng Notes, trong thư mục tên AllInOneIME (tự tạo nếu chưa có); không chèn gì cả. Văn bản dán vào giữ nguyên ngắt dòng, tối đa 20000 ký tự |
| `@reminder` | Thêm một lời nhắc vào ứng dụng Reminders, trong danh sách tên AllInOneIME. Viết thời gian trong văn bản; thời gian được đọc ngay trên máy Mac, và một dòng hiển thị những gì đã đọc được: ⏎ hoặc Space để thêm, Esc quay lại chỉnh sửa. Có giờ thì lời nhắc sẽ báo vào giờ đó; chỉ có ngày thì là lời nhắc cả ngày |
| `@calculate` | Tính toán trên máy Mac này; kết quả hiện trong các ứng viên, ⏎ hoặc Space để chèn: `@calculate 23*17` → `391`. Lệnh cũng hoạt động bên trong một câu: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Chạy một dòng Python (`python3` của máy Mac) và chèn kết quả: giá trị của biểu thức cuối cùng trong mã, ví dụ `@py 2**100`, `@py import math; math.sqrt(2)`, nếu không có thì là những gì mã in ra. Không được cung cấp khi thiếu `python3` (bộ công cụ dòng lệnh của Xcode có sẵn nó) |
| `@js` | Chạy một dòng JavaScript và chèn theo cách tương tự: giá trị của biểu thức cuối cùng hoặc những gì `console.log` in ra, ví dụ `@js [1, 2, 3].map(x => x * 2)`. Lệnh dùng JavaScriptCore có sẵn trong macOS nên không cần cài gì; nó không thể đọc tệp, truy cập mạng hay chạy chương trình khác |
| `@reportissue` | Báo cáo sự cố: mở trang tạo issue mới của GitHub trong trình duyệt, với nội dung bạn gõ sau lệnh làm tiêu đề, cùng "What happened / What you expected" (chuyện gì đã xảy ra / bạn mong đợi điều gì) để điền. Nó thêm phiên bản ứng dụng và macOS, kiến trúc máy Mac, ngôn ngữ giao diện và ngôn ngữ nhập, các gói ngôn ngữ đã cài, loại nhà cung cấp AI (và mô hình, nếu là mô hình công khai; nếu không thì "custom"), phím thực thi, và số lượng lệnh tùy chỉnh, plugin và tiện ích mở rộng bạn có, không bao giờ kèm tên của chúng, văn bản, đường dẫn hay khóa của bạn. ⏎ (hoặc phím thực thi của bạn) trước tiên hiện tất cả trong bảng ứng viên; ⏎ lần nữa, hoặc nhấp vào dòng, sẽ mở trang, nơi bạn xem lại và nhấp Submit (bằng tài khoản GitHub của bạn); Esc quay lại. Cũng có trong menu nhập ("Report an Issue…") và Settings → About |
| `@imessage` | Gửi một iMessage: gõ tên, số điện thoại hoặc email (tên tiếng Trung cũng gõ được bằng pinyin, đầy đủ hoặc chữ cái đầu) và chọn người nhận trong bảng ứng viên (những người bạn nhắn tin gần đây xếp trước; số hoặc địa chỉ đầy đủ cũng được), rồi viết tin nhắn (các lệnh bên trong như `@stock AAPL` được chạy trước). ⏎ hiển thị "Send to Alex (…): message" trong bảng, ⏎ lần nữa để gửi, Esc quay lại chỉnh sửa; không có gì được gõ vào ô văn bản. Lần đầu, macOS hỏi AllInOneIME có được truy cập Contacts và điều khiển Messages không: nhấp OK cho cả hai |

Ví dụ: `@q` ⏎, gõ `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ lưu một ghi chú. `@reminder call Bob tomorrow at 3pm` ⏎, kiểm tra thời gian đã đọc được, rồi ⏎ lần nữa để thêm. Khi đã chọn lệnh, bạn cũng có thể giữ ⌥ bên phải và nói. Ở chế độ tiếng Trung, `@open` và `@calculate` tạm thời chuyển sang chữ cái tiếng Anh và trở lại tiếng Trung khi bạn xong.

Mã cho `@py` và `@js` được gõ bằng chữ cái tiếng Anh, và dấu câu toàn độ rộng (từ chế độ tiếng Trung) được đổi thành ASCII; hãy viết trên một dòng, với `;` giữa các câu lệnh. Mã chạy trong một tiến trình riêng, bị dừng sau 10 giây hoặc bằng Esc bất cứ lúc nào; khi có lỗi, dòng đầu tiên của lỗi được hiển thị, ví dụ `ZeroDivisionError: division by zero`. Đầu ra nhiều dòng được chèn đúng như khi in ra; trong terminal nó được đưa vào thành một dòng (terminal chạy mọi dòng nó nhận được). Terminal bên trong trình soạn thảo (VS Code, Cursor, JetBrains) không thể phân biệt được với chính trình soạn thảo, nên ở đó đầu ra nhiều dòng của bất kỳ lệnh nào cũng được đưa vào nguyên vẹn. Cả hai cũng hoạt động bên trong câu của một lệnh khác: `@reply the answer is @py 2**100`; đặt mã có dấu cách trong dấu ngoặc kép: `@question explain @py "sum(x * x for x in range(10))"`. Chiều ngược lại thì không: mã của `@py` và `@js` luôn chạy đúng như bạn đã gõ, và các `@commands` bên trong nó không được chạy trước.

![Gõ @ để mở danh sách lệnh; @question cùng một câu hỏi, rồi ⏎ để nhận câu trả lời](../en/commands.png)

![@open tìm ứng dụng khi bạn gõ; bắt đầu bằng / thì đó là đường dẫn: thư mục được liệt kê, Tab để hoàn thành](../en/open.png)

Khi `@` không đi kèm một lệnh, như `@john`, ký tự `@` được chèn như bình thường, nên việc @-nhắc tên người khác trong các ứng dụng chat vẫn hoạt động. `@question`, `@improve` và `@translate` chỉ gửi đến Bedrock của chính bạn khi bạn nhấn phím thực thi; `@open` chỉ tìm trên máy Mac này; `@note` và `@reminder` chỉ đi đến Notes và Reminders trên máy Mac này; `@claude` dùng Claude Code được cài trên máy Mac của bạn (lệnh `claude`) với tài khoản riêng của nó, và như thường lệ nó hỏi bạn trước khi thay đổi tệp hay chạy lệnh. Khi chưa cài Claude Code, `@claude` không được cung cấp. `@imessage` chỉ đọc Contacts trên máy Mac này (tên, số điện thoại, email), không bao giờ đi qua AI, và tin nhắn do Messages gửi; khi không có ứng dụng Messages, lệnh này không được cung cấp.

`@calculate` chạy trên máy Mac này, ngoại tuyến: `+ - * /` (cả `× ÷`), `^` hoặc `**` cho lũy thừa, dấu ngoặc, phần trăm (`50%` là 0.5, `200*5%` là 10; như trên máy tính bỏ túi, phần trăm được cộng hoặc trừ là phần trăm của số đứng trước: `100+10%` là 110, `100-10%` là 90), các hàm `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` là cơ số 10, góc tính bằng radian, `round(x, 2)` giữ hai chữ số thập phân) và các hằng số `pi` (`π`) và `e`. Chữ số và dấu toàn độ rộng cũng dùng được. Phép tính chính xác theo hệ thập phân, nên `0.1+0.2` là `0.3`; kết quả có tối đa 15 chữ số có nghĩa, và số nguyên có đến 38 chữ số được viết ra đầy đủ (`2^100` → `1267650600228229401496703205376`).

### Trên văn bản đang chọn (mới)

Chọn một đoạn văn bản trong bất kỳ ứng dụng nào (một câu trong Notes, một đoạn trong Mail), gõ `@improve`, `@translate`, `@question` hoặc lệnh khác nhận văn bản, rồi nhấn ⏎: lệnh xử lý vùng chọn, và kết quả bạn chọn sẽ thay thế nó. Trong lúc bạn gõ, vùng chọn vẫn giữ nguyên, vẫn được chọn: lệnh được viết trong bảng ứng viên, dòng đầu là những gì bạn gõ và dòng tiếp theo là "On the selection: “…” (N characters)" (trên vùng chọn: N ký tự). Esc, ⇧⏎ hoặc nhấp ra chỗ khác giữ nguyên văn bản; thay đổi vùng chọn giữa chừng cũng vậy, và lệnh bị hủy. Văn bản gõ sau lệnh là chỉ dẫn cho `@improve` và `@translate` (`@translate ja`, `@improve more formal`) và là câu hỏi cho `@question` (`@question what does this mean`), về vùng chọn. `@open`, `@claude`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, các lệnh terminal và tiện ích mở rộng dạng script không dùng nó: chúng lấy những gì bạn gõ, và vùng chọn vẫn giữ nguyên. Tối đa 5000 ký tự; không bao giờ được đọc khi ở chế độ nhập liệu bảo mật hay trong terminal. Tắt nó trong Settings → General → "Use the selected text" (dùng văn bản đang chọn) nếu nó hoạt động không đúng trong một ứng dụng.

### Tinh chỉnh kết quả (mới)

Khi kết quả của `@improve`, `@translate`, `@question` hoặc một lệnh chỉ dẫn đang hiện, hãy gõ điều cần thay đổi, như `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese` hoặc `用更口语的说法` (gõ pinyin được, và chạm Shift để đổi ngôn ngữ), rồi nhấn ⏎: kết quả được gửi lại cho AI kèm chỉ dẫn của bạn, và kết quả mới thay thế chúng trong cùng bảng. Tinh chỉnh bao nhiêu lần tùy thích; dòng trên cùng của bảng liệt kê các bước ("Refined: shorter · more formal"), và bạn có thể chọn một dòng bất cứ lúc nào như thường. Một chữ cái bắt đầu chỉ dẫn (hiện là "refine › …" ở đầu bảng); khi chỉ dẫn còn trống, chữ số, Space và ⏎ chọn như trước. Việc tinh chỉnh bắt đầu khi kết quả đã đầy đủ: gõ trong lúc kết quả đầu tiên vẫn đang đến sẽ viết tiếp câu, như trước. Trong lúc một lần tinh chỉnh đang chạy, bạn đã có thể gõ chỉ dẫn tiếp theo; lần tinh chỉnh vẫn tiếp tục, và ⏎ chạy lần tiếp theo ngay khi kết quả của nó về. Esc xóa chỉ dẫn, rồi lùi một bước về kết quả trước lần tinh chỉnh cuối (trong lúc tinh chỉnh: dừng nó), rồi về câu; ⌫ trên dòng trống cũng lùi lại như vậy. Trên văn bản đang chọn, kết quả bạn chọn vẫn thay thế đúng vùng chọn, vốn được giữ nguyên cho đến lúc đó. Lần tinh chỉnh thất bại (hoặc bị từ chối khi ở chế độ nhập liệu bảo mật) giữ nguyên kết quả, và chỉ dẫn của nó sẵn sàng để thử lại bằng ⏎. Cùng một lần tinh chỉnh trên cùng kết quả được trả lời từ bộ nhớ đệm.

### Câu hỏi gần đây (mới)

`@question` khi không gõ gì phía sau sẽ liệt kê 5 câu hỏi gần nhất của bạn, mới nhất đứng trước, kèm thời điểm hỏi ("3 hours ago"). Gõ thêm để lọc: mỗi từ ở bất kỳ đâu trong câu hỏi, không phân biệt hoa thường (cả tiếng Trung không có dấu cách). Một chữ số, ↑↓ rồi ⏎, hoặc một cú nhấp sẽ hiện ngay câu trả lời đã lưu, không cần lên mạng: Space hoặc ⏎ chèn nó, ⌘C sao chép nó, 0 hiện câu hỏi, R hỏi lại để có câu trả lời mới, Esc quay về danh sách. Khi không có kết quả khớp, hoặc không chọn gì, ⏎ hỏi điều bạn đã gõ. Câu trả lời mới cho cùng câu hỏi, khi hỏi lại hoặc tinh chỉnh, sẽ thay thế câu trả lời đã lưu.

- Chúng chỉ được lưu trên máy Mac này (xem Quyền riêng tư): không lưu khi ở chế độ nhập liệu bảo mật, và không bao giờ lưu câu hỏi về văn bản đang chọn.
- Settings → General → "Remember recent questions" (ghi nhớ câu hỏi gần đây) tắt tính năng và xóa chúng (`rememberQuestions` trong tệp cấu hình); "Clear (N)" (xóa) xóa chúng.

### Ghi chú và lời nhắc

`@note` tạo một ghi chú mới; dòng đầu tiên là tiêu đề. Sau khi sao chép một đoạn văn bản, ⌃V sau `@note ` (hoặc ⌘V, ngoài terminal) lưu nó cùng các ngắt dòng, được hiển thị là ↵ trong lệnh. Nếu bạn rời ô văn bản (nhấp chỗ khác, chuyển ứng dụng) hoặc nhấn ⇧⏎ (chèn nguyên văn) trước khi một ghi chú có ngắt dòng được lưu, nó không được gõ vào ứng dụng (trong terminal, mỗi dòng sẽ chạy như một lệnh): thay vào đó nó được đưa vào bộ nhớ tạm ("The note wasn't saved; its text is on the clipboard" – ghi chú chưa được lưu; văn bản của nó đang ở bộ nhớ tạm). Ghi chú chỉ có một dòng thì được chèn nguyên văn.

`@reminder` đọc được các mốc thời gian như `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (ngày 1 của tháng đó), `end of the year` (cả mốc thời gian tiếng Trung). Ngày và giờ có thể tách rời nhau (`tomorrow call Bob at 5`); tuần bắt đầu vào thứ Hai. Giờ không có am hay pm (`at 5`) là lần kế tiếp của giờ đó, không bao giờ rơi vào khoảng từ nửa đêm đến 6 giờ sáng; giờ đã qua trong hôm nay được hiểu là ngày mai, nhưng một buổi trong ngày vẫn đang diễn ra (`this afternoon`, `tonight`) là hôm nay, cả ngày; ngày đã qua trong năm nay được hiểu là của năm sau. Nếu được viết để lặp lại (`standup every Monday at 9`), lời nhắc chỉ được thêm một lần, cho lần kế tiếp: các từ đó vẫn nằm trong tiêu đề và dòng xác nhận ghi "once only" (chỉ một lần). Dòng xác nhận hiển thị thời gian đã đọc được, ví dụ "tomorrow 3:00 PM" (theo cài đặt 12/24 giờ của máy Mac); nếu sai, Esc quay lại văn bản. Khi không có giờ hay ngày nào, lời nhắc không có thời gian ("no date" – không có ngày).

`@stock` và các lệnh tương tự bên trong hai lệnh này không được chạy: văn bản được lưu đúng như đã viết (gõ `@` ở đó không mở danh sách lệnh). Lần đầu, macOS hỏi AllInOneIME có được điều khiển Notes (`@note`) hoặc truy cập Reminders (`@reminder`) không: hãy cho phép. Nếu bạn chưa cho phép, hãy cho phép AllInOneIME trong System Settings → Privacy & Security → Automation (Notes) hoặc → Reminders. Khi lưu thất bại (chẳng hạn do thiếu quyền), thông báo cho biết lý do và văn bản quay trở lại lệnh để bạn sửa và gửi lại; khi bạn phải sửa điều gì đó trước (một quyền, một tài khoản), văn bản cũng được đưa vào bộ nhớ tạm (vì việc mở System Settings lấy mất tiêu điểm khỏi ô văn bản). Nếu bạn đã chuyển sang ô văn bản khác hoặc đang gõ nội dung khác, thay vào đó văn bản được đưa vào bộ nhớ tạm ("Not saved; the text is on the clipboard." – chưa được lưu; văn bản đang ở bộ nhớ tạm).

### Lệnh của riêng bạn

Trong phần cài đặt, ở mục "Custom @ Commands" (lệnh @ tùy chỉnh), nhấp "Add Command…" (thêm lệnh): đặt tên và chọn việc lệnh sẽ làm (một chỉ dẫn cho AI, một chương trình, một chương trình trong Terminal, hoặc một trang web), hoặc bắt đầu từ một ví dụ. Lệnh của bạn xếp sau các lệnh có sẵn; tên chỉ gồm chữ cái tiếng Anh và không được trùng tên một lệnh có sẵn; lệnh có hiệu lực từ câu tiếp theo. Chúng được lưu trong `customCommands` trong tệp cấu hình (`~/.config/allinoneime/config.json`), bạn cũng có thể tự sửa tệp này:

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | Chức năng |
|---|---|
| `prompt` | Gửi đến AI với `prompt` làm chỉ dẫn; câu trả lời hiện trong các ứng viên, để chèn hoặc sao chép (⌘C) |
| `run` | Chạy `argv` ở chế độ nền; những gì nó in ra hiện trong các ứng viên (nhiều dòng được chèn đúng như khi in ra, trong terminal thì thành một dòng). Khi có lỗi, dòng cuối cùng của đầu ra được hiển thị |
| `terminal` | Chạy `argv` trong một cửa sổ Terminal mới; không chèn gì |
| `link` | Đưa văn bản vào địa chỉ web `url` và mở nó trong trình duyệt mặc định; không chèn gì |

- `{input}` được thay bằng những gì bạn viết sau lệnh, và nó luôn nằm trọn trong đúng một đối số chứa nó: không có shell nào tham gia. Nếu cần shell, hãy chỉ rõ, như `sh` ở trên (`zsh -c`).
- `stdin`: những gì được đưa vào đầu vào chuẩn của chương trình, trong đó `{input}` cũng được thay thế.
- `url` của một `link` phải là `https://`, chứa `{input}` đúng một lần, sau `?` hoặc `#`; văn bản được mã hóa (dấu cách là `%20`, xuống dòng là `%0A`), tối đa 4000 ký tự.
- `run` và `terminal` mặc định gõ chữ cái tiếng Anh (giống `@open`; ở chế độ tiếng Trung, tiếng Trung trở lại sau đó), và dấu câu toàn độ rộng được đổi thành ASCII. Đặt `"ascii": false` để giữ văn bản như đã gõ.
- Chương trình chạy trong thư mục home của bạn với PATH của login shell (nên các bản cài qua Homebrew, pyenv và nvm đều được tìm thấy). `run` dừng chương trình sau 10 giây (`timeoutSeconds`) hoặc khi nó in ra quá nhiều; Esc dừng nó bất cứ lúc nào.
- `summary` là phần mô tả trong danh sách lệnh (không bắt buộc).
- Khi không tìm thấy chương trình trong `argv` (chẳng hạn không có `python3`), lệnh không được cung cấp và `@python …` được chèn như văn bản thường; sau khi chương trình được cài, lệnh xuất hiện ở ô văn bản tiếp theo.

`run` và `terminal` chạy mã trên máy Mac của bạn: chỉ thêm những lệnh bạn tự viết và tin tưởng. Chúng cũng chỉ chạy khi bạn nhấn phím thực thi, và không bao giờ chạy khi đang ở chế độ nhập liệu bảo mật (secure input).

### Tiện ích mở rộng dạng script

Thêm lệnh @ của riêng bạn dưới dạng chương trình: một script bằng bất kỳ ngôn ngữ nào (bash, Python, Node, Swift, …) với vài dòng siêu dữ liệu trong phần chú thích. Đặt nó trong `~/.config/allinoneime/extensions`, hoặc trong một thư mục bạn thêm ở "Settings → Custom Commands → Script Extensions". Raycast Script Commands dùng được nguyên trạng, và các thư mục đã chứa chúng được tìm thấy bằng Spotlight.

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh` là `@flights`. Viết các đối số sau nó, cách nhau bằng dấu phẩy: `@flights beijing, new york` chạy nó với `beijing` và `new york` làm `$1` và `$2` (các dấu phẩy thừa nằm lại trong đối số cuối cùng); nếu một đối số bắt buộc bị để trống, lệnh báo còn thiếu gì thay vì chạy. Những gì nó in ra được dùng theo giá trị `output` của nó:

| `output` | Điều gì xảy ra |
|---|---|
| `insert` (mặc định) | Toàn bộ, và từng dòng, để chèn |
| `show` | Hiển thị trong bảng trong lúc in ra (tiến độ); không chèn gì. Rời ô văn bản thì nó tiếp tục chạy nền (tối đa bốn cái cùng lúc) |
| `list` | Một danh sách theo định dạng Script Filter JSON của Alfred, được chạy lại khi bạn gõ; chọn một dòng sẽ chèn, mở (một địa chỉ web, tệp hoặc thư mục; không bao giờ là thứ có thể chạy), sao chép hoặc chạy bước thứ hai |
| `silent` | Dòng cuối cùng của nó hiện gần con trỏ; không chèn gì |

Một lệnh cũng có thể không nhận đầu vào (`input none`: ⏎ trên tên của nó là chạy), chạy ở chế độ `background` và báo cho bạn khi xong (bảng trên thanh menu liệt kê nó trong lúc chạy), hiển thị một `status` bên cạnh tên trong danh sách lệnh, hoặc hỏi trước (`confirm`). Nó chạy trong thư mục riêng của nó với PATH của login shell và các biến `ALLINONEIME_*`: ngôn ngữ giao diện và ngôn ngữ nhập, ứng dụng bạn đang gõ, văn bản. Một **bundle** là một thư mục có `extension.json` liệt kê các lệnh của nó: chúng dùng chung mã và tùy chọn, được hiển thị trong Settings (mật khẩu được lưu vào keychain). Settings liệt kê mọi lệnh kèm một công tắc, và các script bị bỏ qua kèm lý do.

Các chế độ của Raycast tương ứng như sau: `fullOutput` → `show`, `compact` và `silent` → `silent`, `inline` có `refreshTime` → một status. Toàn bộ giao thức có trong [docs/extensions.md](../extensions.md); [Examples/extensions](../../Examples/extensions) có một ví dụ cho mỗi loại. Tiện ích mở rộng chạy mã trên máy Mac của bạn: hãy dùng những cái bạn tin tưởng. Chúng chỉ chạy khi bạn chạy chúng (status hoặc list thì chạy khi bạn gõ), không bao giờ chạy khi đang ở chế độ nhập liệu bảo mật, và dừng khi bộ gõ thoát.

### Plugin

Plugin là các lệnh `@` làm sẵn cho những việc không phải ai cũng cần, như `@stock AAPL 600519 700` để xem giá cổ phiếu. Sau khi cài, chúng hoạt động như mọi lệnh khác; mục "Plugins" trong phần cài đặt cho thấy những gì đã cài và nơi mỗi plugin gửi văn bản của bạn đến, và cho phép gỡ chúng. Plugin là JavaScript chạy trong một tiến trình riêng: chúng chỉ có thể truy cập các trang web mà chúng khai báo (HTTPS), và không thể đọc tệp hay chạy chương trình khác. "Browse Library…" (duyệt thư viện) ở mục Plugins trong phần cài đặt cài chúng từ [thư viện plugin](https://github.com/MicroZ-LLC/AllInOneIME-plugins): trước khi cài, nó cho biết plugin liên hệ với những trang web nào; chỉ mục của thư viện được ký và mọi tệp phải khớp với chỉ mục đó. Khi có phiên bản mới hơn, một nút "Update" sẽ hiện ra; không có gì tự cập nhật. Plugin của riêng bạn đặt trong `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): đó là plugin cục bộ, không bao giờ bị thư viện ghi đè. Plugin dạng "Link" không chạy mã: chúng đưa văn bản vào một địa chỉ web và mở nó trong trình duyệt, như `@x nice weather today`, mở khung soạn bài của X với văn bản đã điền sẵn; đăng hay không là do bạn quyết định trên trang đó. Thư viện có bốn plugin như vậy (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` quy đổi tiền tệ: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, một dòng kèm ngày của tỷ giá (tỷ giá từ ExchangeRate-API). Cách viết một plugin: [docs/plugins.md](../plugins.md).

Các lệnh lấy dữ liệu (plugin và chương trình) cũng hoạt động bên trong một câu: `@reply tell her @stock AAPL is up today`. Các lệnh bên trong chạy trước, đầu ra của chúng thế vào chỗ của chúng, và lệnh bên ngoài xử lý kết quả đó. Đối số là từ đứng sau lệnh, cộng với các mã viết hoa hoặc con số ngay sau đó (`@stock AAPL TSLA`, `@stock 600519 700`); một từ viết thường sẽ kết thúc đối số (`@stock SNDK is good to buy` tra cứu SNDK). Dấu ngoặc kép đánh dấu chính xác đối số: `@stock "aapl tsla"`. `@calculate` cũng hoạt động bên trong câu; đối số của nó là toàn bộ biểu thức phía sau, kể cả dấu cách, cho đến phần văn bản khác: `@reply the total is @calculate 23 * 17 dollars`. Bên trong `@claude` và các lệnh terminal, chúng không được chạy: các lệnh đó nhận văn bản đúng như đã viết (gõ `@` ở đó không mở danh sách lệnh).

### Phím thực thi

Mặc định là ⏎; thay đổi ở mục "Action key" (phím thực thi) trong phần cài đặt (`actionKey` trong tệp cấu hình): ⏎, "Tap ⌥" (nhấn nhanh ⌥, bên nào cũng được: nhấn và thả ngay; giữ ⌥ bên phải vẫn dùng để nói), ⌥Space, hoặc Space (nhấn Space thêm một lần sau khi đã chọn từ; hai lần ở chế độ tiếng Anh). Dù phím thực thi là gì, lệnh @ cũng chạy khi nhấn ⏎. Nếu ⌥Space đã là phím tắt của Alfred, Raycast hoặc ứng dụng tương tự, chúng sẽ nhận phím đó trước.

### Gõ từng ký tự kết quả

Bật "Type results out" (gõ ra kết quả) trong Settings → General (`typeOut` trong tệp cấu hình) và kết quả của lệnh được gõ vào ứng dụng từng ký tự một, như người đang gõ, thay vì vào một lần; các từ chọn bằng pinyin vẫn vào một lần. Thanh trượt đặt tốc độ, từ 6 giây một ký tự đến 40 ký tự một giây (`typeOutRate`), và "Speed up and slow down (like a person)" (lúc nhanh lúc chậm, như người thật) gõ theo từng đợt với tốc độ thay đổi (`typeOutVaries`). Esc dừng ngay tại chỗ; phím khác bất kỳ gõ phần còn lại một lần.

"Make occasional typos and fix them" (thỉnh thoảng gõ sai rồi sửa, `typeOutMistakes`) khiến nó càng giống người hơn: thỉnh thoảng gõ nhầm phím bên cạnh phím đúng, phát hiện ra muộn nhất ba chữ sau đó, xóa và gõ lại; một chữ cái hoặc dấu cách bị gõ hai lần rồi xóa; hoặc một từ ngắn được gõ, xóa rồi gõ lại. Vài lỗi trong 100 ký tự, không bao giờ hai lỗi sát nhau, và không bao giờ ở đầu dòng. Trong mã, địa chỉ web và email, và số, lỗi gõ chỉ là một chữ cái hoặc chữ số sai, được sửa ngay (không bao giờ là ngoặc, dấu nháy hay dấu cách sai, những thứ mà trình soạn thảo tự ghép cặp hoặc thụt lề). Các chữ sai là chữ kề bên trên bố cục bàn phím của bạn (QWERTY, AZERTY, QWERTZ…). Tiếng Trung, tiếng Nhật và tiếng Hàn chỉ ngập ngừng (hai ký tự được gõ, xóa rồi gõ lại), không bao giờ có ký tự sai.

Trong ô cho phép rút lại lỗi gõ (các khung văn bản của Apple như TextEdit và Notes, trình duyệt, hầu hết trình soạn thảo): khi gõ đến hết, hoặc khi nhấn phím khác để gõ phần còn lại một lần, văn bản đúng y như kết quả; Esc (hoặc rời khỏi ô) giữa lúc đang có lỗi gõ sẽ xóa lỗi đó trước, nên ô chứa phần đầu chính xác của kết quả. Nếu con trỏ di chuyển khi lỗi gõ đang hiện (một cú nhấp), lỗi được xóa tại chỗ của nó và phần còn lại được gõ không có lỗi.

Không bao giờ có lỗi gõ trong terminal, cũng như trong các ứng dụng không cho bộ gõ biết con trỏ ở đâu. Mỗi lần, lỗi gõ đầu tiên là lỗi đơn giản (một chữ sai, sửa trong một lần), cho đến khi ô đó cho thấy nó rút lại được lỗi gõ; trong lúc lỗi gõ đang hiện, bộ gõ kiểm tra trước mỗi phím rằng ô chứa đúng những gì nó đã gõ. Ô nào bỏ qua vị trí cần thay văn bản thì không rút lại được lỗi gõ: ở đó lỗi đầu tiên ấy còn lại, nên văn bản cuối cùng lệch một ký tự (kể cả sau Esc hoặc phím khác), và ứng dụng đó không bị gõ sai nữa. Settings → General liệt kê các ứng dụng đó dưới công tắc lỗi gõ; "Forget apps where typos couldn't be fixed" (quên các ứng dụng không sửa được lỗi gõ) cho chúng thử lại.

### Cài đặt theo ứng dụng (mới)

Settings → Apps cho một ứng dụng cài đặt riêng, mục nào cũng tùy chọn; những gì ứng dụng không đặt sẽ theo cài đặt chung cho mọi ứng dụng:

| Cài đặt | Ví dụ | Trong tệp cấu hình |
| --- | --- | --- |
| Ngôn ngữ nhập mà các ô văn bản của nó bắt đầu | Slack bằng tiếng Anh, WeChat bằng pinyin | `inputLanguage` |
| Các kiểu viết lại mà `@improve` đưa ra ở đó | Mail trang trọng và khéo léo, Slack thân mật | `rewriteStyles` |
| Gõ ra kết quả, hay không | bật trong ứng dụng chat, tắt trong Mail | `typeOut` |
| Không dùng AI trong ứng dụng này | `@improve`, `@translate`, `@question`, `@claude` và các lệnh chỉ dẫn của bạn không gửi gì ở đó và báo như vậy; gõ chữ và các lệnh khác vẫn hoạt động | `noAI` |

"Add App…" (thêm ứng dụng) liệt kê các ứng dụng bạn gõ gần đây, hoặc chọn một ứng dụng trong /Applications. Menu nhập, ở mục "This App: <tên>", có các công tắc nhanh cho ứng dụng bạn đang gõ (No AI, Type Results Out, ngôn ngữ khởi đầu). Trong tệp cấu hình, chúng nằm dưới `appProfiles`, theo bundle ID: `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. Bundle ID được so khớp không phân biệt hoa thường (`com.apple.Mail` chính là `com.apple.mail` của Mail). `@reportissue` đếm số ứng dụng có đặt gì đó, không bao giờ nêu tên chúng.

- Ngôn ngữ khởi đầu hoạt động như ngôn ngữ nhập mặc định: ô văn bản nhận nó khi trở nên hoạt động, và việc đổi bằng Shift sau đó được giữ cho các ô của ứng dụng ấy cho đến khi cài đặt thay đổi.
- Với No AI, các lệnh AI vẫn nằm trong danh sách @; chạy một lệnh sẽ hiện thông báo và giữ lại những gì bạn đã viết. Các lệnh terminal của riêng bạn (`"type": "terminal"`) chạy chương trình chứ không phải AI, nên vẫn hoạt động ở đó.

## Bảng trên thanh menu

<img src="../en/panel-swipe.png" width="520" alt="Bảng trên thanh menu: nền kính mờ, với ghi chú, lời nhắc và tác vụ Claude trên các thẻ; một dòng được vuốt sang trái hiện nút Remove">

Nhấp vào biểu tượng của AllInOneIME trên thanh menu (dấu ∞ kèm con trỏ, không có khung; biểu tượng có khung là nguồn nhập) và bảng sẽ thả xuống bên dưới nó; nhấp chỗ khác để đóng:

- Notes: các ghi chú đã lưu bằng `@note`, 5 ghi chú mới nhất; nhấp vào một ghi chú để mở nó trong Notes.
- Reminders: các lời nhắc chưa hoàn thành trong danh sách AllInOneIME của Reminders (`@reminder` thêm vào danh sách đó), cái đến hạn sớm nhất xếp trước, hiển thị 8 cái; nhấp vào vòng tròn để đánh dấu hoàn thành, hoặc vào tiêu đề để mở Reminders.
- Claude Tasks: giống `@tasks`, các tác vụ Claude chạy nền (những gì `@claude` giao đi), tối đa 30, mỗi lần hiển thị 5: cuộn để xem thêm, hoặc tìm theo tiêu đề và câu trả lời trong ô tìm kiếm; kèm tiến độ và dòng đầu tiên của câu trả lời gần nhất; nhấp vào một tác vụ để mở nó trong Terminal và làm tiếp.

Vuốt một dòng (ghi chú, lời nhắc hoặc tác vụ) sang trái bằng hai ngón tay để hiện nút "Remove" (gỡ), hoặc vuốt hết cỡ để gỡ ngay; với chuột, nhấp chuột phải vào dòng đó. Việc gỡ chỉ đưa nó ra khỏi bảng: ghi chú vẫn ở trong Notes, lời nhắc vẫn ở trong Reminders (chưa hoàn thành), tác vụ vẫn ở trong Claude Code.

Phần đầu bảng hiển thị số lượng (như "2 reminders · 1 task running"; tác vụ đang chờ bạn được đếm riêng, như "1 waiting for you") và một nút làm mới. Bảng không bao giờ lấy tiêu điểm khỏi ứng dụng bạn đang gõ: đánh dấu hoàn thành một lời nhắc hay làm mới đều để ứng dụng đó ở phía trước; chỉ ô tìm kiếm của tác vụ Claude, khi được nhấp vào, mới nhận bàn phím. Biểu tượng được hiển thị theo mặc định; tắt nó ở mục "Menu Bar Panel" trong phần cài đặt.

Bảng đọc những gì, và khi nào:

- Notes: danh sách là bản ghi riêng của bảng (được giữ cả khi bảng đóng), và Notes không bao giờ được khởi chạy: chỉ khi Notes đang chạy sẵn, và AllInOneIME trước đó đã được phép điều khiển nó, bảng mới kiểm tra Notes để cập nhật tiêu đề đã sửa và ghi chú đã xóa.
- Reminders: danh sách AllInOneIME được đọc khi bảng thả xuống, mỗi 60 giây và khi lời nhắc thay đổi. Bảng không bao giờ tự khiến macOS hỏi quyền truy cập: nếu macOS chưa hỏi bạn, bảng hiển thị "Allow Access to Reminders", và chỉ nút đó mới hỏi; nếu bạn đã từ chối, bảng hiển thị "Open System Settings".
- Tác vụ Claude: bảng chỉ chạy `claude agents` khi đang thả xuống: một lần khi thả xuống, khi nhấn Refresh, và khi `@claude` giao một tác vụ; và cứ 15 giây một lần khi còn tác vụ chưa xong, dừng lại khi tất cả đã xong. Câu trả lời gần nhất được đọc từ cuối các bản ghi hội thoại (transcript) của Claude Code trên máy Mac này (`~/.claude/projects`), và chỉ khi bản ghi đã thay đổi.
- Khi bảng đóng, không có việc nào trong số này chạy; nó chỉ lưu bản ghi các ghi chú mà `@note` lưu.

## Nhập liệu và dịch

Trong phần cài đặt:

- **Input languages** (ngôn ngữ nhập): từ một đến năm ngôn ngữ trong số tiếng Anh, tiếng Trung (pinyin), tiếng Pháp, tiếng Hàn và tiếng Hindi, thêm bằng nút + (luôn hiển thị; bị làm mờ khi đã đủ năm). Bản cài mới chỉ có tiếng Anh. Ô văn bản mới bắt đầu bằng ngôn ngữ đầu tiên; nhấn nhanh Shift để chuyển sang ngôn ngữ kế tiếp, theo thứ tự của chúng; khi chỉ có một ngôn ngữ, Shift không chuyển.
  - **Tiếng Pháp** gõ bằng bố cục bàn phím riêng: AZERTY trừ khi bạn chọn bố cục khác trên thẻ của nó. Các phím chết (dead key) của nó (^, ¨, `, ´, ~) cũng ghép dấu từ bố cục đó.
  - **Tiếng Hàn** gõ Hangul theo bố cục 2-set (Dubeolsik), mỗi âm tiết được ghép lại khi bạn gõ (g k s → 한); Shift cho ㄲ ㄸ ㅃ ㅆ ㅉ và ㅒ ㅖ.
  - **Tiếng Hindi**: gõ từ theo cách phát âm bằng chữ cái Latin và nhận được chữ Devanagari (namaste → नमस्ते). Các từ thông dụng được viết đúng như tiếng Hindi viết chúng; nếu không, Space chèn cách viết đầu tiên, một chữ số chèn cách viết khác, ⏎ chèn các chữ cái như đã gõ, và "." là dấu danda (।).
  - Tên lệnh, văn bản của `@open` và mã (`@py`, `@js`) được gõ bằng chữ cái Latin dù đang ở ngôn ngữ nào; ngôn ngữ đó trở lại sau lệnh.
  - `@improve` giữ câu tiếng Hàn, tiếng Hindi hoặc tiếng Pháp ở chính ngôn ngữ của nó, và `@translate` dịch nó sang các ngôn ngữ của bạn (tiếng Pháp được phân biệt với tiếng Anh khi nó là một trong các ngôn ngữ nhập của bạn).
- **Language packs** (gói ngôn ngữ): ứng dụng đi kèm tiếng Anh (và tiếng Pháp, vốn chỉ cần bố cục bàn phím của macOS). Tiếng Trung, tiếng Hàn và tiếng Hindi là các gói bạn tải về khi thêm chúng: thêm tiếng Trung (pinyin) sẽ tải các từ điển của nó (khoảng 34 MB, 125 MB sau khi giải nén) kèm thanh tiến độ, và pinyin hoạt động ngay khi tải xong, không cần khởi động lại; gói tiếng Hàn (bảng phím và cách các jamo ghép thành âm tiết) và gói tiếng Hindi (các chữ cái và từ thông dụng) chỉ vài kilobyte. Một gói chỉ chứa dữ liệu (từ điển, bảng và schema, không bao giờ có mã), được liệt kê trong một chỉ mục có chữ ký và được kiểm tra SHA-256 trước khi dùng, giống như plugin. Thẻ của mỗi ngôn ngữ hiển thị gói của nó (phiên bản, dung lượng, nguồn gốc) kèm nút "Delete…", và khi gỡ ngôn ngữ, ứng dụng đề nghị xóa gói của nó. Cập nhật từ 0.6.1 trở về trước vẫn giữ tiếng Trung mà không cần tải về: trình cài đặt giữ lại các từ điển đi kèm phiên bản cũ.
- **Bố cục ứng viên**: khi chọn từ, ứng viên pinyin và tiếng Hindi mặc định nằm ngang cạnh nhau (Horizontal), giống các bộ gõ có sẵn của hệ thống: ← → để chọn và ↑↓ (hoặc - =) để lật trang. Chọn Vertical ở trang Input, dưới các ngôn ngữ nhập, để xếp dọc từng dòng (↑↓ để chọn). Danh sách lệnh @ và kết quả luôn xếp dọc.
- **Fuzzy pinyin** (pinyin mờ, khi nhập tiếng Trung): những âm bạn không phân biệt thì gõ kiểu nào cũng được, ví dụ z ↔ zh, n ↔ l, in ↔ ing. Ở trang "Input", chọn "Chinese (pinyin)" trên thanh ngôn ngữ nhập, bật "Fuzzy pinyin" và chọn các cặp; các từ điển được triển khai lại trong một hai giây. Tính năng này ghi `rime_ice.custom.yaml` vào thư mục người dùng của Rime, và không bao giờ ghi đè lên tệp của riêng bạn ở đó.
- **Translate (@translate)**: thêm các ngôn ngữ cần dịch sang (tiếng Tây Ban Nha, tiếng Pháp, tiếng Đức, tiếng Nhật, tiếng Hàn, tiếng Trung, tiếng Hindi, tiếng Bengal, tiếng Tamil và các ngôn ngữ chính khác của Ấn Độ…) và kéo để sắp xếp thứ tự. Tiếng Hindi gõ bằng chữ Latin ("aap kaise ho") được trả về bằng chữ Devanagari. `@translate` viết một dòng cho mỗi ngôn ngữ, theo thứ tự này (ba phiên bản nếu chỉ có một ngôn ngữ); ngôn ngữ của chính câu đó được bỏ qua. Bản cài mới dịch sang ngôn ngữ đầu tiên trong danh sách ngôn ngữ ưu tiên của máy Mac mà không phải tiếng Anh; nếu chỉ có tiếng Anh, `@translate` mở trang này để bạn thêm một ngôn ngữ.
- **Keyboard layouts** (bố cục bàn phím): tiếng Pháp gõ bằng bố cục được chọn trên thẻ của nó (`keyboardLayouts` trong tệp cấu hình). Với các ngôn ngữ khác, khi dùng bộ gõ, macOS giữ bố cục Latin cuối cùng của bạn (AZERTY, QWERTZ, Spanish, US International…), nên bạn gõ như thường lệ, kể cả `@` ở bất cứ vị trí nào bố cục của bạn đặt nó, và phím chết cũng ghép dấu trong văn bản của lệnh (⌥E rồi E → é, ^ rồi e → ê). Các bố cục không có chữ Latin (tiếng Nga, Hindi InScript) không dùng được dưới một bộ gõ: hãy chuyển sang chúng bằng ⌃Space, hoặc dán (⌃V) hay đọc chính tả văn bản vào một lệnh.
- `@improve` trau chuốt và viết lại mà không dịch; `@translate @improve` dùng cùng nhau sẽ dịch và viết lại trong một yêu cầu. Bật "@improve also translates" trong phần cài đặt để `@improve` luôn làm như vậy.

## Kiểu viết lại

Sau các dòng 1–3 là các bản viết lại, **bằng ngôn ngữ bạn đã gõ**: bản viết lại tiếng Anh cho câu tiếng Anh, bản viết lại tiếng Trung cho câu tiếng Trung. Chọn bất kỳ kiểu nào trong phần cài đặt:

- Polish (trau chuốt): giữ nguyên giọng điệu, tự nhiên hơn
- Concise (ngắn gọn)
- Formal (trang trọng): dành cho cấp trên và khách hàng
- Casual (thân mật)
- Tactful (khéo léo)
- Jargon (biệt ngữ): kiểu nói của Amazon bằng tiếng Anh (bandwidth, circle back…), biệt ngữ của các công ty công nghệ lớn bằng tiếng Trung. Tin xấu được nói giảm nói tránh, ví dụ "this is a blocker bug" → "Oh! Looks like your team has the bandwidth to fix this minor issue!"

Những bản viết lại chỉ thay đổi dấu câu hoặc lặp lại một dòng khác sẽ không được hiển thị.

### Danh sách Jargon (thuật ngữ của riêng bạn)

Jargon không có danh sách thuật ngữ có sẵn. Bạn có thể tự chuẩn bị danh sách của mình (ví dụ, các cụm từ nhóm bạn hay dùng), và mô hình sẽ ưu tiên dùng các thuật ngữ trong đó. Trong các ứng viên, dòng Jargon ghi chú nghĩa của các thuật ngữ nó đã dùng.

Danh sách là một tệp văn bản, mỗi dòng một thuật ngữ, có thể kèm theo nghĩa của nó, phân cách bằng "=", dấu hai chấm hoặc Tab (bạn có thể sao chép hai cột từ bảng tính rồi dán vào). Các dòng bắt đầu bằng `#` là chú thích:

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

Ở mục "Rewrite Styles → Jargon list" trong phần cài đặt, nhấp "New" để tạo một danh sách trống tại `~/.config/allinoneime/jargon.txt` và mở nó; nếu bạn đã có sẵn tệp danh sách, nhấp "Choose File…" để dùng nó ngay tại vị trí hiện có (`jargonFile` trong tệp cấu hình). Thay đổi có hiệu lực ngay. Chỉ 150 thuật ngữ đầu tiên được đọc. Khi đánh dấu "Jargon", danh sách được gửi đến Bedrock cùng với mỗi yêu cầu.

<img src="../en/panel-dark.png" width="420" alt="Bảng ứng viên ở chế độ tối">

## Nhập bằng giọng nói

<img src="../en/voice.png" width="340" alt="Giữ ⌥ bên phải để nói">

Giữ ⌥ bên phải và nói; khi bạn thả ra, văn bản được chèn. Giọng nói được nhận dạng theo ngôn ngữ bạn đang gõ (tiếng Anh, tiếng Trung, tiếng Pháp, tiếng Hàn hoặc tiếng Hindi). Nếu bạn gõ một lệnh trước (ví dụ `@improve `, `@question `) rồi mới nói, văn bản được đặt sau lệnh và ⏎ sẽ chạy nó; bạn cũng có thể nhấn ⏎ mà không thả ⌥ bên phải để chạy ngay khi nói xong. Giọng nói được nhận dạng ngay trên máy Mac bằng tính năng nhận dạng giọng nói có sẵn của macOS (SpeechAnalyzer), và không có âm thanh nào được tải lên; tính năng này cần macOS 26 trở lên.

Lần đầu tiên:

- macOS hỏi AllInOneIME có được dùng micrô không. Bạn cũng có thể nhấp "Allow Microphone" trong phần cài đặt từ trước.
- Nếu máy Mac này chưa có mô hình giọng nói cho ngôn ngữ đó, mô hình sẽ được tự động tải về một lần. Bạn cũng có thể tải nó trong phần cài đặt.

Việc ghi âm chỉ bắt đầu sau khi bạn giữ phím khoảng 0,2 giây, nên nhấn nhanh ⌥ bên phải sẽ không bật micrô (khi phím thực thi được đặt là "Tap ⌥", một lần nhấn nhanh sẽ thực thi). Nếu bạn nhấn một phím khác trong khi đang giữ (một phím tắt với ⌥, ⌥←), thao tác đó được tính là phím tắt và cũng không có gì được ghi âm. Nhấn bất kỳ phím nào khác trong khi đang ghi âm sẽ hủy việc ghi âm.

## Cài đặt

Để chạy cần macOS 14 trở lên, nhập bằng giọng nói cần macOS 26 trở lên. Trình cài đặt là bản universal: hoạt động trên máy Mac dùng Apple silicon và Intel. Đến nay nó mới chỉ được kiểm thử trên macOS 27 với Apple silicon (bản Intel chỉ được kiểm thử qua bài tự kiểm tra dưới Rosetta).

1. Tải `AllInOneIME-<version>.dmg` từ [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) (chỉ từ đó) và mở nó.
2. Nhấp đúp vào "Install AllInOneIME" bên trong và nhấp "Install". Bộ gõ được đặt vào `~/Library/Input Methods` và "AllInOneIME Settings" vào `~/Applications`. Chỉ cho người dùng này; không cần mật khẩu quản trị viên.
3. Trình cài đặt được ký bằng Developer ID và được Apple công chứng, nên lần đầu macOS chỉ hỏi có mở một ứng dụng tải về từ internet hay không: nhấp Mở. (Các phiên bản trước 0.6.3 không được công chứng: mỗi phiên bản phải được cho phép một lần trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Vẫn mở.)

Sau đó, AllInOneIME được bật và có trong các nguồn nhập của bạn; chuyển sang nó bằng Ctrl+Space (phím 🌐 chỉ chuyển được nếu "Press 🌐 key to" được đặt là "Change Input Source" trong System Settings → Keyboard). Nếu trình cài đặt bảo bạn tự thêm, nghĩa là máy Mac này không cho phép chương trình bật nó, nên hãy tự thêm một lần: System Settings → Keyboard → Text Input → Input Sources → Edit… → + (dưới cùng bên trái) → English → AllInOneIME (nó cũng gõ được pinyin sau khi bạn thêm tiếng Trung ở mục "Input" trong phần cài đặt của nó).

Nếu Ctrl+Space không đưa bạn đến AllInOneIME, hoặc sau một lúc nó lại chuyển về U.S., hãy chạy lại trình cài đặt: nó sẽ thêm lại AllInOneIME vào các nguồn nhập của bạn.

Cập nhật: Settings → About → Check for Updates (kiểm tra cập nhật). Khi có phiên bản mới, About sẽ báo (cùng một dòng trong bảng trên thanh menu), kèm những điểm mới; "Update to <version>" (cập nhật lên <phiên bản>) tải nó về, đối chiếu với thông tin cập nhật được ký bằng khóa phát hành của AllInOneIME, cài đặt và khởi động lại bộ gõ. Cài đặt, gói ngôn ngữ, từ đã học và tiện ích mở rộng của bạn được giữ nguyên, và nếu có gì trục trặc, phiên bản bạn đang dùng sẽ được khôi phục. AllInOneIME tự kiểm tra mỗi ngày một lần, chạy nền (tắt bằng "Check for updates automatically" trong About); không có gì được cài cho đến khi bạn nhấp. Tính năng này có từ 0.6.3; để cập nhật phiên bản cũ hơn, hoặc nếu bạn thích, hãy cài ảnh đĩa của phiên bản mới đè lên, không cần gỡ cài đặt trước. Trước khi nâng cấp, hãy đọc [nhật ký thay đổi](../../CHANGELOG.md): trong đó có các thay đổi của từng phiên bản và ghi chú nâng cấp.

Cập nhật lên 0.6.3 từ phiên bản cũ hơn: 0.6.3 là phiên bản đầu tiên được ký bằng Developer ID, nên keychain chưa nhận ra nó là ứng dụng đã lưu các khóa của bạn. Lần đầu nó cần đến từng khóa đã lưu (một API key, phiên đăng nhập AllInOneIME Cloud, mật khẩu của một tiện ích mở rộng), macOS sẽ hỏi mật khẩu đăng nhập của bạn: nhập mật khẩu rồi nhấp "Always Allow" (Luôn cho phép). Sau đó nó không hỏi lại nữa, kể cả sau những lần cập nhật sau. Khóa của Amazon Bedrock nằm trong `~/.aws/credentials`, không bị ảnh hưởng.

Nếu bạn đã cài AIPinyin (tên cũ của AllInOneIME), chỉ cần cài: AIPinyin.app cũ và trình khởi chạy cài đặt của nó sẽ bị gỡ, và mục trong các nguồn nhập của bạn được đổi sang tên mới, không cần thêm lại. Cài đặt, danh sách jargon và các từ đã học được chuyển sang các thư mục mới (`~/.config/allinoneime` và các thư mục khác) ở lần khởi chạy đầu tiên, và mỗi thư mục cũ được để lại dưới dạng liên kết tới thư mục mới.

Để gỡ cài đặt, mở "Install AllInOneIME" và nhấp "Uninstall…". Cài đặt và các từ đã học được giữ lại.

### Biên dịch từ mã nguồn

Việc biên dịch cần Xcode 26 trở lên, vì nhập bằng giọng nói dùng SDK macOS 26.

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` tải librime và các từ điển rime-ice rồi xác minh chúng, biên dịch, và cài vào cùng các vị trí đó, thêm bộ gõ vào nguồn nhập của bạn theo cùng cách. Ứng dụng được cài không có từ điển tiếng Trung (chúng thuộc gói ngôn ngữ tiếng Trung): một bản cài đã có chúng sẽ giữ lại chúng dưới dạng gói; nếu không, `make install-pack` cài gói từ các từ điển trong bản checkout, không cần tải về. `make status` hiển thị phiên bản đã cài (`version:`) và liệu nó có trong nguồn nhập của bạn không (`listed:`). Để gỡ cài đặt: `make uninstall`.

## Thiết lập AI

Bản dịch và bản viết lại dùng nhà cung cấp AI của chính bạn, và chi phí tính vào tài khoản của bạn: mặc định là Amazon Bedrock trong tài khoản AWS của bạn, hoặc Claude API, Gemini hay một dịch vụ tương thích OpenAI (xem "Các nhà cung cấp AI khác" bên dưới).

### Amazon Bedrock

1. Bật Bedrock trong AWS console và đảm bảo bạn có thể dùng mô hình đã chọn. Mặc định là Claude Haiku 4.5; lần đầu dùng một mô hình của Anthropic, bạn điền một mẫu đơn về mục đích sử dụng, chỉ một lần.
2. Tạo một access key có quyền `bedrock:InvokeModelWithResponseStream` và đặt nó vào một profile trong `~/.aws/credentials`. Hiện chỉ hỗ trợ loại khóa tĩnh như vậy, chưa hỗ trợ SSO hay assume-role.
3. Mở "AllInOneIME Settings": bạn có thể tìm nó trong Spotlight hoặc trong Applications, hoặc mở từ biểu tượng của bộ gõ trên thanh menu → "Settings…". Chọn profile, region và mô hình, rồi nhấp "Test Connection" (kiểm tra kết nối). "Language" ở đầu cửa sổ cài đặt có thể là English hoặc Chinese; mặc định ("System") nó theo hệ thống (tiếng Trung nếu tiếng Trung đứng trước tiếng Anh trong các ngôn ngữ ưu tiên của hệ thống, ngược lại là tiếng Anh). Cửa sổ cài đặt, các gợi ý trong bảng ứng viên và menu nhập đều theo cài đặt này.

<img src="../en/settings.png" width="420" alt="Cửa sổ cài đặt">

### Các nhà cung cấp AI khác: Claude API, Gemini, dịch vụ tương thích OpenAI

Bạn không cần AWS: chọn một nhà cung cấp ở mục "AI Provider" trong phần cài đặt, dán API key, nhấp "Save", rồi "Test Connection".

| Nhà cung cấp | Mô hình mặc định | API key |
|---|---|---|
| Claude API | `claude-haiku-5-5` (nhanh nhất, rẻ nhất; Sonnet 5.5 và Opus 5.5 cẩn thận hơn nhưng chậm hơn và đắt hơn) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| Tương thích OpenAI | `gpt-6-luna` của OpenAI (hoặc `gpt-5.4-mini`); "Common Services…" có DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter và Ollama trên máy Mac này: chọn một dịch vụ sẽ điền sẵn base URL của nó, sau đó nhập mô hình của nó | Khóa của dịch vụ; đặt Base URL là địa chỉ của nó, ví dụ `https://api.deepseek.com/v1`, hoặc `http://localhost:11434/v1` cho Ollama trên máy Mac này |

- API key được lưu trong keychain của hệ thống, không bao giờ trong tệp cấu hình. Khi không có khóa ở đó, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (hoặc `GOOGLE_API_KEY`) và `OPENAI_API_KEY` từ shell của bạn sẽ được dùng.
- "Thinking" (suy luận) mặc định ở mức thấp: bộ gõ phải chờ ở mỗi câu, và suy luận ít hơn thì nhanh hơn. Chọn "Not set" cho các mô hình không hỗ trợ tùy chọn này.
- Khi chọn Claude Opus 5.5 hoặc Sonnet 5.5, các yêu cầu kèm cơ chế dự phòng khi bị từ chối của Claude API (`fallbacks: "default"`): khi một bộ phân loại an toàn từ chối, máy chủ thử lại bằng một mô hình khác.
- Trong tệp cấu hình: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), cùng `model`, `baseURL`, `effort` và `temperature` dưới `anthropic`, `gemini` và `openai` (những mục không đặt sẽ dùng giá trị mặc định).

### Apple Intelligence trên máy Mac này (macOS 26)

Trên máy Mac có Apple Intelligence (Apple silicon, macOS 26 trở lên, đã bật trong Cài đặt hệ thống → Apple Intelligence & Siri), hãy chọn "Apple Intelligence (on this Mac)" trong "AI Provider": không cần khóa, không tốn phí, và không gì bạn gõ rời khỏi máy Mac. Nó dùng mô hình tích hợp sẵn trong macOS (framework Foundation Models), với cùng chỉ dẫn và định dạng câu trả lời như các nhà cung cấp khác, nhưng chỉ dùng các ví dụ viết bằng chính ngôn ngữ của câu (mô hình nhỏ quá dễ bắt chước ngôn ngữ của ví dụ).

- Đây là mô hình nhỏ: ngữ cảnh khoảng 4K token (8K trên macOS 27), nên một đoạn văn dài có thể quá dài với nó, và nó biết ít ngôn ngữ hơn (tiếng Anh, Trung, Nhật, Hàn, Pháp, Đức, Tây Ban Nha và vài ngôn ngữ khác; không có tiếng Hindi). Trong cả hai trường hợp nó đều báo. Kết quả của nó kém các mô hình trên đám mây, và câu trả lời `@question` của nó về sự kiện và mã thường sai.
- Ở nơi không dùng được, nó hiện mờ kèm lý do (không hỗ trợ trên máy Mac này, đang tắt, mô hình chưa sẵn sàng), và phần cài đặt có liên kết đến Cài đặt hệ thống → Apple Intelligence & Siri. Trước macOS 26, nó không được liệt kê.
- "Output tokens", nhiệt độ (temperature) và thời gian chờ trong "Model Settings" áp dụng cho nó. Trong tệp cấu hình: `"provider": "apple"`.

### Ẩn thông tin nhạy cảm (mới)

Settings → AI Provider → Privacy → "Hide sensitive information before sending" (ẩn thông tin nhạy cảm trước khi gửi; mặc định tắt): trước khi yêu cầu được gửi đến AI, những gì nó tìm thấy trong văn bản của bạn được thay ngay trên máy Mac bằng các ký hiệu giữ chỗ như `[EMAIL_1]` (cùng giá trị, cùng ký hiệu), và kết quả được trả lại giá trị thật trước khi hiện hoặc chèn. Bảng hiện "2 items hidden from the AI" (đã ẩn 2 mục khỏi AI). Mỗi loại đều có thể tắt:

| Loại | Ví dụ | Trong tệp cấu hình |
| --- | --- | --- |
| Địa chỉ email | `bob@example.com` | `emails` |
| Số điện thoại | `+1 (555) 123-4567`, `138 0013 8000` | `phones` |
| Số thẻ thanh toán (kiểm tra Luhn) | `4111 1111 1111 1111` | `cards` |
| API key và token | các tiền tố đã biết như `sk-` hoặc `ghp_`, chuỗi ngẫu nhiên dài | `keys` |
| Địa chỉ IP | `203.0.113.42`, `2001:db8::1` | `ips` |
| Từ của riêng bạn, không phân biệt hoa thường | một mật danh như `Project Atlas`, một cái tên | `customWords` |

- Nó áp dụng cho `@improve`, `@translate`, `@question`, các lệnh chỉ dẫn và plugin chỉ dẫn của bạn, và việc tinh chỉnh kết quả của chúng (cùng ký hiệu giữ chỗ), với mọi nhà cung cấp, kể cả AllInOneIME Cloud và Apple Intelligence. Các mục trong danh sách Jargon chứa giá trị cần ẩn sẽ không được gửi.
- Nó nhận ra các giá trị có định dạng; nó không nhận ra tên người hay địa chỉ, nên hãy thêm chúng làm từ của riêng bạn. `@claude`, các plugin lấy dữ liệu từ một trang web (`@stock`) hoặc mở một trang (`@x`) và tiện ích mở rộng dạng script gửi văn bản đúng như đã gõ. Xem thêm ở phần Quyền riêng tư.
- Trong tệp cấu hình: `"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`.

Mọi cài đặt được lưu trong `~/.config/allinoneime/config.json`; sau khi thay đổi, lần dịch tiếp theo sẽ dùng cài đặt mới, không cần khởi động lại. Các khóa mới hơn:

| Khóa | Chức năng | Mặc định |
|---|---|---|
| `inputLanguages` | Ngôn ngữ nhập, từ một đến năm, ngôn ngữ đầu tiên là mặc định: `"en"` tiếng Anh, `"zh"` tiếng Trung (pinyin), `"fr"` tiếng Pháp, `"ko"` tiếng Hàn, `"hi"` tiếng Hindi, ví dụ `["en", "zh"]`, `["fr", "en", "ko"]`. Tiếng Trung, tiếng Hàn và tiếng Hindi hoạt động khi gói của chúng đã được cài | `["en"]` (bản cài mới) |
| `keyboardLayouts` | Bố cục bàn phím mà một ngôn ngữ nhập dùng, theo mã ngôn ngữ (hiện mới chỉ có tiếng Pháp): `{"fr": "com.apple.keylayout.French-PC"}` | Tiếng Pháp: `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | Các ngôn ngữ `@translate` dịch sang, theo thứ tự: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | `@improve` kiêm dịch (như `@translate @improve`) | `false` |
| `voiceInput` | Giữ ⌥ bên phải để nói | `true` |
| `actionKey` | Phím thực thi: `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Space), `"space"` (Space) | `"enter"` |
| `uiLanguage` | Ngôn ngữ giao diện (cửa sổ cài đặt, gợi ý trong bảng ứng viên, menu): `"zh"`, `"en"` | `null` (theo hệ thống) |
| `rewriteStyles` | Kiểu viết lại: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, ví dụ `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | Tệp danh sách jargon của riêng bạn | `null` (tức là `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | Biểu tượng trên thanh menu và bảng thả xuống của nó | `true` |
| `candidateLayout` | Ứng viên pinyin và tiếng Hindi: `"vertical"` (xếp dọc) hoặc `"horizontal"` (nằm ngang; ← → để chọn, ↑↓ để lật trang) | `"horizontal"` |
| `fuzzyPinyin` | Các cặp pinyin mờ: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | Lệnh @ xử lý văn bản đang chọn trong ô (xem Trên văn bản đang chọn) | `true` |
| `checkForUpdates` | Tìm phiên bản mới mỗi ngày một lần, chạy nền; không có gì được cài cho đến khi bạn nhấp | `true` |
| `rememberQuestions` | Lưu 5 câu hỏi `@question` gần nhất và câu trả lời trên máy Mac này, liệt kê dưới `@question` (xem Câu hỏi gần đây) | `true` |
| `appProfiles` | Cài đặt của một ứng dụng, theo bundle ID, mục nào cũng tùy chọn: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI` (xem Cài đặt theo ứng dụng) | `{}` |
| `redaction` | Ẩn thông tin nhạy cảm khỏi AI (xem Quyền riêng tư): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`; mỗi bộ phát hiện (`emails`, `phones`, `cards`, `keys`, `ips`) đều bật trừ khi đặt thành `false` | `enabled: false` |

## Quyền riêng tư

- Việc gõ (tiếng Anh và pinyin) và các phép tính `@calculate` hoàn toàn diễn ra cục bộ. Chỉ khi bạn nhấn phím thực thi với `@improve`, `@translate` hoặc `@question`, câu đó mới được gửi đến nhà cung cấp AI bạn đã chọn (Bedrock của chính bạn, hoặc dịch vụ mà bạn đã thêm khóa). Khi đánh dấu "Jargon" và đã đặt danh sách jargon, danh sách được gửi kèm theo. Tinh chỉnh kết quả (một chỉ dẫn gõ sau kết quả, rồi ⏎) gửi lại cùng yêu cầu kèm các kết quả đang hiện và chỉ dẫn của bạn.
- Với AllInOneIME Cloud, câu đi qua máy chủ của nhà phát triển đến một nhà cung cấp mô hình (hiện qua OpenRouter): máy chủ chỉ lưu số đếm, không bao giờ lưu văn bản. Việc đăng nhập chỉ lưu địa chỉ email của bạn.
- Ẩn thông tin nhạy cảm (Settings → AI Provider → Privacy, mặc định tắt): trước khi bất kỳ yêu cầu nào được gửi đi (`@improve`, `@translate`, `@question`, các lệnh chỉ dẫn và plugin chỉ dẫn của bạn, với mọi nhà cung cấp kể cả AllInOneIME Cloud), địa chỉ email, số điện thoại, số thẻ thanh toán (kiểm tra Luhn), API key và token (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…` và chuỗi ngẫu nhiên dài), địa chỉ IP và từ của riêng bạn (một mật danh, một cái tên) được thay ngay trên máy Mac bằng các ký hiệu giữ chỗ như `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]`; cùng một giá trị nhận cùng một ký hiệu. Kết quả của mô hình được trả lại giá trị thật trước khi hiện hoặc chèn, và bảng hiện "2 items hidden from the AI". Kết quả có ký hiệu giữ chỗ bị mô hình sửa đến mức không nhận ra được hiện đúng như đã viết, kèm dấu "⚠ placeholder changed". Các mục trong danh sách Jargon chứa giá trị bị ẩn sẽ không được gửi. Mỗi loại đều có thể tắt. Các dạng toàn độ rộng (`zhang＠example.com`, `１３８…`) cũng được tìm ra, và một giá trị hay cụm từ có thể bị ngắt bởi xuống dòng. Nó nhận ra các giá trị có định dạng như email, số và khóa; nó không nhận ra tên người hay địa chỉ (hãy thêm chúng làm từ của riêng bạn), cũng như các chữ cái trông giống nhau từ bảng chữ cái khác. Áp dụng cho các yêu cầu gửi đến dịch vụ AI của bạn; `@claude`, các plugin lấy dữ liệu từ một trang web (`@stock`) hoặc mở một trang (`@x`) và tiện ích mở rộng dạng script gửi văn bản đúng như đã gõ. Trong tệp cấu hình: `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- Giọng nói chỉ được ghi âm khi bạn giữ ⌥ bên phải và được nhận dạng ngay trên máy Mac; văn bản nhận dạng được chỉ được gửi đi trong các lệnh nêu trên, khi bạn nhấn phím thực thi.
- Bộ gõ đọc văn bản trong bộ nhớ tạm, một lần, chỉ khi bạn nhấn ⌃V hoặc ⌘V trong một lệnh; nội dung mà trình quản lý mật khẩu đánh dấu là ẩn sẽ không được đọc. Văn bản được hiển thị trong lệnh trước và, một lần nữa, chỉ được gửi đi khi bạn nhấn phím thực thi. Các phiên bản macOS gần đây hỏi AllInOneIME có được đọc bộ nhớ tạm không: hãy cho phép. Để không bị hỏi mỗi lần, hãy đặt quyền dán của AllInOneIME thành luôn cho phép trong System Settings → Privacy & Security.
- Trong ô mật khẩu, macOS chuyển sang bàn phím riêng của nó (U.S. hoặc ABC) và chuyển lại khi bạn rời ô đó. Bất cứ khi nào ứng dụng bạn đang gõ giữ chế độ nhập liệu bảo mật, AllInOneIME không soạn văn bản và không thể ghi âm: các phím được đưa vào đúng như đã gõ. Và trong khi hệ thống ở chế độ nhập liệu bảo mật (ô mật khẩu, Secure Keyboard Entry của Terminal, v.v.), không có gì được gửi đến AI.
- `@note` và `@reminder` không đi đến AI: AllInOneIME chỉ chuyển văn bản cho Notes và Reminders trên máy Mac này, và cũng đọc thời gian của lời nhắc ngay trên máy Mac (việc các ứng dụng đó có đồng bộ sang các thiết bị khác của bạn hay không tùy thuộc vào tài khoản của chúng, chẳng hạn iCloud). Vì vậy chúng cũng hoạt động khi đang ở chế độ nhập liệu bảo mật.
- `@reportissue` (và "Report an Issue…") tự nó không gửi gì: nó mở trang tạo issue mới của GitHub trong trình duyệt với tiêu đề bạn đã gõ cùng các phiên bản, ngôn ngữ, loại nhà cung cấp và số lượng nêu ở trên, hiện trước trong bảng ứng viên. Không có gì đến GitHub trừ khi bạn nhấp Submit ở đó.
- `@open` chỉ tìm trên máy Mac này. Nó ghi nhớ những gì bạn đã mở bằng nó (200 mục gần nhất), trong phần tùy chọn riêng của bộ gõ (không phải trong config.json), để liệt kê chúng trước.
- Để phục vụ "Add App…" trong Settings → Apps, bộ gõ lưu bundle ID của 12 ứng dụng gần nhất bạn đã gõ, trong tùy chọn riêng của nó; không lưu gì khác về chúng.
- `@question` ghi nhớ 5 câu hỏi gần nhất của bạn cùng câu trả lời và thời điểm hỏi, chỉ trên máy Mac này, trong `~/Library/Application Support/AllInOneIME/recent-questions.json` (chỉ tài khoản người dùng của bạn đọc được), để liệt kê chúng dưới `@question`; câu trả lời đã lưu được hiện từ đó mà không cần lên mạng. Không lưu gì khi đang ở chế độ nhập liệu bảo mật, và câu hỏi về văn bản đang chọn hoàn toàn không được lưu (câu trả lời của chúng nói về vùng chọn, vốn sẽ bị ghi xuống đĩa). Settings → General → "Remember recent questions" tắt tính năng và xóa chúng (`rememberQuestions` trong tệp cấu hình); "Clear" xóa chúng.
- Để liệt kê ghi chú của bạn, bảng trên thanh menu lưu id và dòng đầu tiên (tối đa 80 ký tự) của 30 ghi chú gần nhất được lưu bằng `@note`, trong phần tùy chọn riêng của bộ gõ, kể cả khi bảng đã tắt.
- `@py` và `@js` chỉ chạy khi bạn nhấn phím thực thi, và chỉ chạy mã do chính bạn gõ hoặc dán: câu trả lời của AI và đầu ra của các lệnh khác không bao giờ được chạy như mã. `@py` dùng `python3` của máy Mac, vốn có thể đọc, ghi tệp và truy cập mạng như khi chạy trong Terminal; `@js` chạy trong một tiến trình riêng không thể đọc tệp, truy cập mạng hay chạy chương trình khác. Cả hai đều không chạy khi đang ở chế độ nhập liệu bảo mật.
- Kiểm tra cập nhật: mỗi ngày một lần (trừ khi tắt "Check for updates automatically"), AllInOneIME tải https://allinoneime.com/update.json và chữ ký của nó; yêu cầu không mang định danh nào và không có gì bạn đã gõ. Bản cập nhật chỉ được tải về, từ bản phát hành trên GitHub, khi bạn nhấp Update.
- Nhật ký không ghi lại những gì bạn gõ. Với mọi bộ gõ của bên thứ ba, macOS đều cảnh báo "The developer can access anything you type with this input source" (nhà phát triển có thể truy cập mọi thứ bạn gõ bằng nguồn nhập này); đó là cảnh báo chung của hệ thống.

## Phát triển

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

Cấu trúc mã:

- `Sources/AllInOneIMECore`: client Bedrock, SigV4, các prompt, máy trạng thái nhập hai cấp (bao gồm lệnh @ và cử chỉ giọng nói); không phụ thuộc AppKit
- `Sources/AllInOneIMERime`: lớp bọc librime
- `Sources/AllInOneIME`: bộ gõ InputMethodKit, bảng ứng viên, cửa sổ cài đặt, nhận dạng giọng nói
- `Sources/AllInOneIMESettings`: trình khởi chạy "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: "Install AllInOneIME" trên ảnh đĩa: cài đặt, cập nhật và gỡ cài đặt

Các gói ngôn ngữ có thư viện riêng, tách biệt với plugin: kho mã [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), được phục vụ tại https://languages.allinoneime.com/, ký bằng khóa riêng. `make pack` tạo tệp nén; tệp này được phát hành dưới dạng release asset ở đó (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), và `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` ghi `packs.json` ở đó và ký nó thành `packs.json.sig` bằng khóa của các gói ngôn ngữ lấy từ keychain (`allinoneime-languages-signing`). Ứng dụng đọc https://languages.allinoneime.com/packs.json, kiểm tra chữ ký, rồi kiểm tra dung lượng và SHA-256 của tệp nén. Để thử một gói từ máy chủ cục bộ: `--test-key` ký bằng một khóa thử nghiệm, và `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Phát hành một phiên bản (trình cập nhật trong ứng dụng đọc https://allinoneime.com/update.json, được ký bằng khóa riêng dành cho các bản phát hành):

1. Tăng số phiên bản (`AppVersion.swift` và ba tệp Info.plist; `AppVersionTests` kiểm tra chúng khớp nhau) và cập nhật nhật ký thay đổi.
2. `make dmg NOTARY_PROFILE=<profile>`: `build/AllInOneIME-<version>.dmg` cùng `.sha256` của nó, và `build/AllInOneIME-<version>-update.zip` (cả hai ứng dụng, như trình cài đặt trong ảnh đĩa mang theo). Các ứng dụng và ảnh đĩa được ký bằng chứng chỉ Developer ID Application trong keychain, và ảnh đĩa được công chứng bằng hồ sơ keychain `xcrun notarytool` đó rồi được staple.
3. Tải cả hai lên bản phát hành GitHub `v<version>` và công bố nó.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"` (mỗi cái một hai câu): ghi `site/public/update.json` (phiên bản, bản dựng và macOS tối thiểu đọc từ các ứng dụng, địa chỉ, kích thước và SHA-256 của tệp, địa chỉ ghi chú phát hành và phần tóm tắt) rồi ký nó thành `update.json.sig` bằng khóa trong keychain đăng nhập (`allinoneime-releases-signing`; macOS có thể hỏi cho phép truy cập). Commit cả hai.
5. Triển khai trang web (`cd site && npx wrangler@4 deploy`), chỉ khi các tệp của bản phát hành đã tải về được: các ứng dụng kiểm tra mỗi ngày một lần, và `AllInOneIME --check-update` cho thấy những gì chúng thấy.

Ứng dụng kiểm tra chữ ký của manifest bằng khóa công khai tích hợp sẵn trước khi đọc nó, không bao giờ cài phiên bản không mới hơn, chỉ tải qua https từ allinoneime.com hoặc các tệp phát hành GitHub của kho mã, và chỉ cài gói lưu trữ khi kích thước và SHA-256 khớp với manifest, bundle ID, phiên bản và chữ ký mã của cả hai ứng dụng đều hợp lệ và bộ gõ mới khởi động được. Sau đó bộ gõ giao việc cho chính tệp thực thi của nó làm trình trợ giúp (`--apply-update`), trình này chờ bộ gõ thoát, hoán đổi các ứng dụng như trình cài đặt làm (bản cũ được để sang bên, đặt lại nếu có gì thất bại) và đăng ký bản mới. Để thử với máy chủ cục bộ: `make update-test`, hoặc `--test-key` với `Scripts/build-update-manifest.swift` và `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`.

Bundle ID vẫn là `com.aipinyin.inputmethod.AIPinyin`: macOS dùng nó để ghi nhớ nguồn nhập đã thêm và quyền dùng micrô, nên thay đổi nó đồng nghĩa với việc phải thêm lại bộ gõ và cấp lại quyền.

## Giấy phép

Copyright © 2026 MicroZ LLC. Mã nguồn được công khai theo [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): bạn có thể dùng, đọc, sửa đổi và chia sẻ nó cho mọi mục đích, trừ một sản phẩm cạnh tranh. Mỗi phiên bản chuyển sang Apache-2.0 hai năm sau khi phát hành. Các phiên bản đến 0.6.1 được phát hành theo GPL-3.0 và vẫn có thể dùng theo giấy phép đó.

Các thành phần của bên thứ ba (librime và các plugin của nó theo BSD-3-Clause; các script Lua của rime-ice và gói ngôn ngữ tiếng Trung theo GPL-3.0) được liệt kê trong [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
