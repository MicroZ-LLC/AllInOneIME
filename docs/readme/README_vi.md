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

Một bộ gõ cho macOS mang các lệnh AI vào mọi ô văn bản. Bắt đầu câu bằng `@` và nhấn ⏎ khi viết xong: `@improve` trau chuốt những gì bạn viết và đưa ra vài cách viết lại, `@translate` dịch nó sang các ngôn ngữ bạn chọn, `@question` đặt một câu hỏi, `@agent` giao nó cho một coding agent (Claude Code, Gemini CLI, Kiro CLI …), và `@open` tìm tệp và ứng dụng hoặc mở một địa chỉ web. Bạn cũng có thể giữ phím ⌥ bên phải và nói. Khi không có `@`, các phím bạn gõ vẫn đi vào ứng dụng như thường lệ. Nó còn gõ được tiếng Trung (pinyin, xây dựng trên Rime và rime-ice), tiếng Pháp, tiếng Hàn (Hangul) và tiếng Hindi (chữ Devanagari từ chữ cái Latin), và chạy các script của riêng bạn như những lệnh @.

Ký hiệu mở lệnh mặc định là `@`. Trong Settings → General → Command trigger, bạn có thể chọn ký hiệu khác: `#`, `%`, `&`, `*`, `+`, `|` hoặc `~`; khi đó lệnh bắt đầu bằng ký hiệu đó (ví dụ `~translate`), còn `@` được gõ như bình thường. Chữ cái, chữ số, dấu cách và các ký hiệu cần cho việc gõ (các phím của bính âm như `'` `-` `=` `[` `]` `` ` ``, và những ký hiệu bính âm gõ thành dấu câu tiếng Trung như `,` `.` `?` `\`) không được chấp nhận, và phần cài đặt sẽ cho biết lý do. Trong tệp cấu hình: `"commandTrigger": "~"`.

![@improve và một câu viết vội, rồi ⏎: các phiên bản đã trau chuốt, cùng các bản viết lại](../en/improve.png)

Để biết thêm chi tiết (mọi lệnh và cài đặt, khắc phục sự cố khi cài đặt, quyền riêng tư), xem [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Được tạo bởi [Weijian Zhang](https://weijianz.com) tại MicroZ LLC.

## Cách sử dụng

Khi không có `@`, bộ gõ không can thiệp: ở chế độ tiếng Anh, chữ cái được gõ trực tiếp và ⏎ là phím Return; không có gì được gửi lên mạng. Bản cài mới gõ tiếng Anh; để gõ thêm tiếng Trung (pinyin), tiếng Pháp, tiếng Hàn hoặc tiếng Hindi, hãy thêm ngôn ngữ đó trong phần cài đặt (xem [Nhập liệu và dịch](#nhập-liệu-và-dịch)).

| Phím | Chức năng |
|---|---|
| Gõ pinyin, Space / chữ số | Ở chế độ tiếng Trung: chọn từ, như mọi bộ gõ pinyin khác |
| `@` (ở đầu câu) | Mở danh sách lệnh: các lệnh dùng nhiều gần đây đứng trước, mỗi lần 5 lệnh, cuộn bằng ↑↓, con lăn chuột hoặc trackpad; hoặc gõ chữ cái để tìm (tên được gõ đầy đủ đứng đầu, rồi đến các tên bắt đầu bằng các chữ đó, rồi các tên chứa chúng). ⏎, Tab, Space hoặc một chữ số để chọn |
| ⏎ | Chạy lệnh. Vẫn hoạt động khi pinyin chưa được chọn: pinyin sẽ được chọn trước, như khi nhấn Space |
| Space, ⏎ / chữ số | Khi kết quả đã hiện ra: chèn kết quả đang được tô sáng / kết quả mang số đó; 0 là bản gốc. ⏎ vẫn chèn dù một phần tiếp theo mới gõ dở (phần đó bị bỏ) |
| ⇧⏎ | Khi đã gõ phần tiếp theo sau kết quả AI: gửi nó đi (câu hỏi kế tiếp của một cuộc hội thoại `@question`, hoặc một lần tinh chỉnh). Khi đang gõ một lệnh, hoặc khi kết quả AI đang hiện mà chưa gõ gì: chèn nguyên văn những gì bạn đã gõ, kể cả `@command`. Với các kết quả khác (`@open`, một lời nhắc …) nó chèn dòng đang được tô sáng, như ⏎ |
| ⌘C | Sao chép kết quả đang được tô sáng (với `@open` là đường dẫn); bảng ứng viên vẫn mở |
| ⌃V | Trong một lệnh (ví dụ sau `@improve `): nối văn bản trong bộ nhớ tạm (clipboard) vào sau những gì bạn đã gõ thay vì dán vào ứng dụng. Nhiều dòng được gộp thành một, tối đa 2000 ký tự mỗi lần (`@note` giữ nguyên ngắt dòng và nhận tối đa 20000). Hoạt động trong mọi ứng dụng; khi không có lệnh, phím được chuyển đến ứng dụng như thường lệ |
| ⌘V | Giống ⌃V, nhưng một số ứng dụng tự xử lý ⌘V (các terminal như Ghostty, iTerm2 và Terminal, cùng với Notes) và dán vào ứng dụng như thường lệ; ở những nơi đó hãy dùng ⌃V |
| Esc, ⌫ | Quay lại câu để tiếp tục sửa; gõ dấu câu hoặc chữ số sau khi có kết quả sẽ viết tiếp câu. Sau một lần tinh chỉnh: quay lại kết quả trước đó |
| Chữ cái, khi kết quả AI đã hiện | Phần tiếp theo: sau `@question` là câu hỏi kế tiếp (xem [Hội thoại](#hội-thoại-với-question-mới)), sau `@improve` hoặc một lệnh chỉ dẫn là một chỉ dẫn như `shorter` (xem [Tinh chỉnh kết quả](#tinh-chỉnh-kết-quả-mới)); ⇧⏎ gửi nó đi. Sau `@translate`, chữ cái viết tiếp câu, và ⏎ dịch lại câu đó |
| ⌘⏎, ⌘1–⌘9 | Trong một cuộc hội thoại `@question`: hiện những nơi có thể tiếp tục nó (các coding agent đã cài, agent mà `@agent` giao việc tới đứng đầu; Claude, ChatGPT, Gemini; hoặc sao chép); ⌘1, ⌘2 … chọn một nơi |
| Nhấp vào một dòng | Trong bảng ứng viên: chọn dòng đó, như chữ số của nó (một từ, một lệnh trong danh sách, một kết quả, một tệp của `@open`, một người nhận, một dòng của tiện ích mở rộng); dòng dưới con trỏ được tô sáng. Ô văn bản vẫn giữ tiêu điểm |
| Nhấn nhanh Shift | Khi có nhiều ngôn ngữ nhập: chuyển sang ngôn ngữ kế tiếp theo thứ tự của chúng (tiếng Anh → tiếng Trung → tiếng Pháp → …, rồi quay lại ngôn ngữ đầu tiên) |
| Giữ ⌥ bên phải | Nói, thả ra để dừng. Bằng ngôn ngữ bạn đang gõ (tiếng Anh, tiếng Trung, tiếng Pháp, tiếng Hàn hoặc tiếng Hindi). Trong một lệnh, văn bản được đặt sau lệnh; nếu không, văn bản được chèn trực tiếp |

## Lệnh @ (beta)

| Lệnh | Chức năng |
|---|---|
| `@improve` | Trau chuốt: 1–3 là ba phiên bản bằng chính ngôn ngữ của câu, từ 4 trở đi là các kiểu viết lại (thêm và sắp xếp trong phần cài đặt), 0 là bản gốc. Không dịch; khi bật "@improve also translates" (@improve kiêm dịch), lệnh hoạt động như `@translate @improve` |
| `@translate` | Dịch sang các ngôn ngữ bạn đã thêm (cài đặt → "Translate", kéo để sắp xếp lại), mỗi ngôn ngữ một dòng, ba phiên bản nếu chỉ có một ngôn ngữ; ngôn ngữ của chính câu đó được bỏ qua. `@translate @improve` dùng cùng nhau sẽ dịch và viết lại trong một yêu cầu |
| `@question` | Đặt câu hỏi; câu trả lời hiện trong danh sách ứng viên, ⏎ hoặc Space chèn nó, ⌘C sao chép nó. Gõ tiếp rồi nhấn ⇧⏎ để hỏi thêm: bảng trở thành một cuộc hội thoại tối đa 5 lượt, sau đó đề nghị tiếp tục trong Claude hoặc một AI khác. Khi không gõ gì sau lệnh, nó liệt kê 5 câu hỏi gần nhất của bạn, mới nhất đứng trước; gõ thêm để lọc (các từ ở bất kỳ đâu trong câu hỏi, không phân biệt hoa thường, cả tiếng Trung). Một chữ số, ↑↓ rồi ⏎, hoặc một cú nhấp sẽ hiện ngay câu trả lời đã lưu của câu hỏi, không cần mạng, để chèn hoặc sao chép như thường; ở đó ⌘R hỏi lại để lấy câu trả lời mới. Khi không có kết quả khớp, hoặc không chọn gì, ⏎ hỏi điều bạn đã gõ |
| `@reply` | Viết ba câu trả lời cho tin nhắn bạn đang trả lời, bằng ngôn ngữ của người kia và theo giọng điệu của ứng dụng (kiểu viết lại đầu tiên của ứng dụng trong Settings → Apps; nếu không có thì thân mật trong ứng dụng chat, trang trọng trong ứng dụng email, nơi mỗi câu trả lời là trọn phần nội dung một email). Đưa tin nhắn cho nó theo một trong ba cách: chọn tin nhắn; sao chép tin nhắn rồi nhấn ⌃V trong bản nháp; hoặc chụp màn hình (⌃⇧⌘4, hoặc công cụ chụp màn hình của WeChat) rồi nhấn ⌃V. Những gì bạn gõ sau lệnh cho biết cần trả lời gì: `@reply politely decline`. ⌘R viết thêm ba câu nữa; xem [Trả lời bằng @reply](#trả-lời-bằng-reply-mới) |
| `@agent` | Giao việc cho một coding agent trên máy Mac của bạn, được chọn trong Settings → Agent: Claude Code (mặc định), Gemini CLI, Kiro CLI, hoặc một lệnh của riêng bạn (những gì bạn gõ được thêm vào làm đối số cuối cùng). Trang này cũng cho biết mỗi agent đã được cài chưa và khởi động như thế nào. Claude Code mặc định chạy nền, có thông báo khi xong (nhấp vào để mở phiên trong Terminal và làm tiếp), hoặc xem `@tasks`; tắt "Runs in the background and notifies me" (chạy nền và báo cho tôi) dưới mục Claude Code ở đó để mở nó trong Terminal. Các agent khác mở trong Terminal với những gì bạn gõ làm tin nhắn đầu tiên. Mỗi agent dùng phiên đăng nhập và cài đặt riêng của nó. Trong Google Chrome, nó mang theo trang đang mở: địa chỉ và tiêu đề, ô bạn đang gõ cùng biểu mẫu hoặc phần chứa ô đó (★ đánh dấu chỗ bạn đang ở), văn bản đang chọn và những gì đang hiện trong cửa sổ — không bao giờ có ô mật khẩu, không bao giờ là toàn bộ trang — nên `@agent why doesn't this work` trong ô tên người dùng của một biểu mẫu đăng nhập là hỏi về ô đó, còn `@agent why is this blocked` trên trang của một pipeline là hỏi về trang đó; agent tự phán đoán là cái nào. Văn bản của trang được đưa cho agent đúng như đã đọc, có đánh dấu là nội dung từ web (không phải chỉ dẫn của bạn). Tính năng này cần quyền Trợ năng; Chrome chỉ dựng cây trang cho nó trong lúc bạn đang viết `@agent` ở đó, rồi tắt lại sau đó (Settings → Agent → "@agent and @reply take the Chrome page along" (@agent và @reply mang theo trang Chrome) tắt toàn bộ việc này). Lần đầu mở Terminal, macOS hỏi AllInOneIME có được điều khiển Terminal không: nhấp OK. (Trước 0.6.4 lệnh này là `@claude`.) |
| `@tasks` | Liệt kê các tác vụ Claude chạy nền (đang làm / đã xong / đang chờ bạn) cùng câu trả lời gần nhất của chúng; ⏎ mở một tác vụ trong Terminal, ⌘C sao chép câu trả lời |
| `@settings` | Mở ngay cửa sổ cài đặt (chỉ cần chọn lệnh là đủ) |
| `@open` | Liệt kê tệp, thư mục và ứng dụng khớp với những gì bạn gõ (Spotlight). Có thể dùng nhiều từ khóa, cách nhau bằng dấu cách: mỗi từ phải có trong đường dẫn, ít nhất một từ có trong tên (tên của một thư mục chuẩn được tính cho những gì nằm trong nó: `downloads pdf` tìm các tệp PDF trong Downloads). Ứng dụng và các thư mục chuẩn cũng tìm được bằng tên tiếng Trung, và giao diện tiếng Trung hiển thị chúng theo tên đó. Những gì bạn đã mở bằng `@open` xếp trước, sau đó đến ứng dụng và các thư mục kia, rồi đến các tệp được dùng hoặc thay đổi gần đây; khi tìm theo tên chỉ ra hai tệp trở xuống và không có ứng dụng hay thư mục nào thuộc loại kể trên, các tệp trong thư mục home của bạn cũng được tìm theo nội dung, những dòng đó được đánh dấu "content" (nội dung); khi không còn gì khác, ⏎ liệt kê chúng để chọn thay vì mở kết quả đầu tiên. Với một địa chỉ web (`github.com`, `localhost:3000`, `https://…`), dòng đầu tiên là "open in the browser" (mở trong trình duyệt) và nội dung tệp không được tìm; tệp có tên đúng như vậy (chẳng hạn `MANIFEST.in`) xếp trước. Văn bản bắt đầu bằng `~/` hoặc `/` là một đường dẫn: Tab hoàn thành nó và đi vào thư mục; ⏎ để mở, ⌘C sao chép đường dẫn |
| `@note` | Lưu văn bản vào ứng dụng Notes, trong thư mục tên AllInOneIME (tự tạo nếu chưa có), hoặc vào nơi Settings → Plugins → Notes (@note) chỉ định: Notion, hoặc một thư mục chứa các tệp Markdown (một vault Obsidian hay thư mục bất kỳ); không chèn gì cả. Văn bản dán vào giữ nguyên ngắt dòng, tối đa 20000 ký tự |
| `@reminder` | Thêm một lời nhắc vào ứng dụng Reminders, trong danh sách tên AllInOneIME. Viết thời gian trong văn bản; thời gian được đọc ngay trên máy Mac, và một dòng hiển thị những gì đã đọc được: ⏎ hoặc Space để thêm, Esc quay lại chỉnh sửa. Có giờ thì lời nhắc sẽ báo vào giờ đó; chỉ có ngày thì là lời nhắc cả ngày |
| `@py` | Chạy một dòng Python (`python3` của máy Mac) và chèn kết quả: giá trị của biểu thức cuối cùng trong mã, ví dụ `@py 2**100`, `@py import math; math.sqrt(2)`, nếu không có thì là những gì mã in ra. Không được cung cấp khi thiếu `python3` (bộ công cụ dòng lệnh của Xcode có sẵn nó) |
| `@js` | Chạy một dòng JavaScript và chèn theo cách tương tự: giá trị của biểu thức cuối cùng hoặc những gì `console.log` in ra, ví dụ `@js [1, 2, 3].map(x => x * 2)`. Lệnh dùng JavaScriptCore có sẵn trong macOS nên không cần cài gì; nó không thể đọc tệp, truy cập mạng hay chạy chương trình khác |
| `@reportissue` | Báo cáo sự cố: mở trang tạo issue mới của GitHub trong trình duyệt, với nội dung bạn gõ sau lệnh làm tiêu đề, cùng "What happened / What you expected" (chuyện gì đã xảy ra / bạn mong đợi điều gì) để điền. Nó thêm phiên bản ứng dụng và macOS, kiến trúc máy Mac, ngôn ngữ giao diện và ngôn ngữ nhập, các gói ngôn ngữ đã cài, loại nhà cung cấp AI (và mô hình, nếu là mô hình công khai; nếu không thì "custom"), phím thực thi, và số lượng lệnh tùy chỉnh, plugin và tiện ích mở rộng bạn có, không bao giờ kèm tên của chúng, văn bản, đường dẫn hay khóa của bạn. ⏎ (hoặc phím thực thi của bạn) trước tiên hiện tất cả trong bảng ứng viên; ⏎ lần nữa, hoặc nhấp vào dòng, sẽ mở trang, nơi bạn xem lại và nhấp Submit (bằng tài khoản GitHub của bạn); Esc quay lại. Cũng có trong menu nhập ("Report an Issue…") và Settings → About |
| `@imessage` | Gửi một iMessage: gõ tên, số điện thoại hoặc email (tên tiếng Trung cũng gõ được bằng pinyin, đầy đủ hoặc chữ cái đầu) và chọn người nhận trong bảng ứng viên (những người bạn nhắn tin gần đây xếp trước; số hoặc địa chỉ đầy đủ cũng được), rồi viết tin nhắn (các lệnh bên trong như `@stock AAPL` được chạy trước). ⏎ hiển thị "Send to Alex (…): message" trong bảng, ⏎ lần nữa để gửi, Esc quay lại chỉnh sửa; không có gì được gõ vào ô văn bản. Lần đầu, macOS hỏi AllInOneIME có được truy cập Contacts và điều khiển Messages không: nhấp OK cho cả hai |

Ví dụ: `@q` ⏎, gõ `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ lưu một ghi chú. `@reminder call Bob tomorrow at 3pm` ⏎, kiểm tra thời gian đã đọc được, rồi ⏎ lần nữa để thêm. Khi đã chọn lệnh, bạn cũng có thể giữ ⌥ bên phải và nói. Ở chế độ tiếng Trung, `@open` tạm thời chuyển sang chữ cái tiếng Anh và trở lại tiếng Trung khi bạn xong.

Mã cho `@py` và `@js` được gõ bằng chữ cái tiếng Anh, và dấu câu toàn độ rộng (từ chế độ tiếng Trung) được đổi thành ASCII; hãy viết trên một dòng, với `;` giữa các câu lệnh. Mã chạy trong một tiến trình riêng, bị dừng sau 10 giây hoặc bằng Esc bất cứ lúc nào; khi có lỗi, dòng đầu tiên của lỗi được hiển thị, ví dụ `ZeroDivisionError: division by zero`. Đầu ra nhiều dòng được chèn đúng như khi in ra; trong terminal nó được đưa vào thành một dòng (terminal chạy mọi dòng nó nhận được). Terminal bên trong trình soạn thảo (VS Code, Cursor, JetBrains) không thể phân biệt được với chính trình soạn thảo, nên ở đó đầu ra nhiều dòng của bất kỳ lệnh nào cũng được đưa vào nguyên vẹn. Cả hai cũng hoạt động bên trong câu của một lệnh khác: `@reply the answer is @py 2**100`; đặt mã có dấu cách trong dấu ngoặc kép: `@question explain @py "sum(x * x for x in range(10))"`. Chiều ngược lại thì không: mã của `@py` và `@js` luôn chạy đúng như bạn đã gõ, và các `@commands` bên trong nó không được chạy trước.

![Gõ @ để mở danh sách lệnh; @question cùng một câu hỏi, rồi ⏎ để nhận câu trả lời](../en/commands.png)

![@open tìm ứng dụng khi bạn gõ; bắt đầu bằng / thì đó là đường dẫn: thư mục được liệt kê, Tab để hoàn thành](../en/open.png)

Khi `@` không đi kèm một lệnh, như `@john`, ký tự `@` được chèn như bình thường, nên việc @-nhắc tên người khác trong các ứng dụng chat vẫn hoạt động. Khi gõ ngay sau một chữ cái, một chữ số, `.`, `_` hoặc `-`, như trong `bob@example.com` hay `ssh user@host`, `@` chỉ là văn bản: không có danh sách nào mở ra, trong mọi ứng dụng, kể cả terminal. Khi danh sách đang mở, ← → hoặc một phím không thể nằm trong tên lệnh (`.`, `:`, `/`) sẽ đóng nó và giữ nguyên những gì bạn đã gõ (`@`, `@im`); trong terminal, lúc đó ← → chỉ đóng danh sách. `@question`, `@improve`, `@translate` và `@reply` chỉ gửi đến Bedrock của chính bạn khi bạn nhấn phím thực thi (ảnh chụp màn hình được đọc trên máy Mac này và chỉ văn bản của nó được gửi đi); `@open` chỉ tìm trên máy Mac này; `@note` và `@reminder` chỉ đi đến Notes và Reminders trên máy Mac này (`@note` thì vào một thư mục hoặc Notion, nếu bạn đã chọn như vậy); `@agent` dùng agent được cài trên máy Mac của bạn (mặc định là lệnh `claude` của Claude Code) với tài khoản riêng của nó, và như thường lệ nó hỏi bạn trước khi thay đổi tệp hay chạy lệnh. Khi chưa cài agent đó, `@agent` không được cung cấp. `@imessage` chỉ đọc Contacts trên máy Mac này (tên, số điện thoại, email), không bao giờ đi qua AI, và tin nhắn do Messages gửi; khi không có ứng dụng Messages, lệnh này không được cung cấp.

### Trên văn bản đang chọn (mới)

Chọn một đoạn văn bản trong bất kỳ ứng dụng nào (một câu trong Notes, một đoạn trong Mail), gõ `@improve`, `@translate`, `@question` hoặc lệnh khác nhận văn bản, rồi nhấn ⏎: lệnh xử lý vùng chọn, và kết quả bạn chọn sẽ thay thế nó. Trong lúc bạn gõ, vùng chọn vẫn giữ nguyên, vẫn được chọn: lệnh được viết trong bảng ứng viên, dòng đầu là những gì bạn gõ và dòng tiếp theo là "On the selection: “…” (N characters)" (trên vùng chọn: N ký tự). Esc, ⇧⏎ hoặc nhấp ra chỗ khác giữ nguyên văn bản; thay đổi vùng chọn giữa chừng cũng vậy, và lệnh bị hủy. Văn bản gõ sau lệnh là chỉ dẫn cho `@improve` và `@translate` (`@translate ja`, `@improve more formal`) và là câu hỏi cho `@question` (`@question what does this mean`), về vùng chọn. `@open`, `@agent`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, các lệnh terminal và tiện ích mở rộng dạng script không dùng nó: chúng lấy những gì bạn gõ, và vùng chọn vẫn giữ nguyên. Tối đa 5000 ký tự; không bao giờ được đọc khi ở chế độ nhập liệu bảo mật hay trong terminal. Tắt nó trong Settings → General → "Use the selected text" (dùng văn bản đang chọn) nếu nó hoạt động không đúng trong một ứng dụng.

### Trả lời bằng @reply (mới)

`@reply` viết ba câu trả lời mà bạn có thể gửi cho tin nhắn bạn đang trả lời. Đưa tin nhắn cho nó theo một trong các cách sau, rồi nhấn ⏎:

- **Chọn tin nhắn** trong ô, rồi gõ `@reply` (câu trả lời bạn chọn được chèn sau tin nhắn, trên một dòng riêng).
- **Sao chép tin nhắn**, gõ `@reply` rồi nhấn ⌃V: bảng hiện "Copied message · N characters" (tin nhắn đã sao chép · N ký tự), và bản nháp được giữ nguyên.
- **Chụp màn hình** vào bộ nhớ tạm (⌃⇧⌘4, hoặc công cụ chụp màn hình của WeChat), gõ `@reply` rồi nhấn ⌃V: bảng hiện "Screenshot · N lines (read on this Mac)" (ảnh chụp màn hình · N dòng, đọc trên máy Mac này). Ảnh chụp được đọc ngay trên máy Mac này (bằng Vision của Apple, lần đầu chậm hơn một chút) và chỉ văn bản của nó được gửi đi; hình ảnh không đi đâu cả và không được giữ lại. Các dòng bên trái là của người kia, bên phải là của bạn, đúng như các ứng dụng chat hiển thị; mốc thời gian giữa các tin nhắn được bỏ đi. Hãy dùng cách này cho WeChat, vì cửa sổ của nó không đọc được bằng cách nào khác.

Gõ điều bạn muốn nói sau lệnh (`@reply politely decline`, `@reply 委婉拒绝`), hoặc không gõ gì để nhận một câu trả lời hợp lý. Các câu trả lời bằng ngôn ngữ của người kia, trừ khi bạn yêu cầu ngôn ngữ khác, và theo giọng điệu của ứng dụng: kiểu viết lại đầu tiên trong hồ sơ của nó (Settings → Apps), nếu không có thì thân mật trong ứng dụng chat và trang trọng trong ứng dụng email, nơi mỗi câu trả lời là trọn phần nội dung một email. Văn bản quanh con trỏ cũng được gửi kèm. ⌫ khi chưa gõ gì sau `@reply` sẽ gỡ phần đã dán. ⏎ hoặc một chữ số chèn một câu trả lời; ⌘R viết thêm ba câu nữa (Esc đưa các câu trước quay lại), và gõ một chỉ dẫn sẽ tinh chỉnh chúng như với mọi kết quả AI. Trong Google Chrome, khi không có gì được chọn hay dán vào, nó mang theo trang đang mở giống như `@agent` (Settings → Agent → "@agent and @reply take the Chrome page along"). Khi không có gì để trả lời và bạn cũng chưa gõ gì, nó cho biết nó cần gì. Việc ẩn thông tin nhạy cảm cũng áp dụng cho văn bản của ảnh chụp màn hình; khi đang ở chế độ nhập liệu bảo mật, bộ nhớ tạm không được đọc và không có gì được gửi đi. Lệnh tùy chỉnh mà bạn từng đặt tên `reply` giờ là `@myreply`.

Ảnh chụp màn hình dán vào bất kỳ lệnh nào khác cũng dùng được: `@translate` ⌃V dịch nó (chèn tại con trỏ), `@question what does this say` ⌃V hỏi về nó, và các lệnh không dùng AI nhận văn bản của nó như thể văn bản đó được sao chép (`@note` giữ nguyên các dòng). Khi có văn bản đang chọn, `@improve` và `@translate` vẫn xử lý vùng chọn, và một thông báo cho biết ảnh chụp màn hình không được dùng.

### Tinh chỉnh kết quả (mới)

Khi kết quả của `@improve`, của một lệnh chỉ dẫn (của bạn hoặc của một plugin) hoặc của việc viết lại một vùng chọn đang hiện, hãy gõ điều cần thay đổi, như `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese` hoặc `用更口语的说法` (gõ pinyin được, và chạm Shift để đổi ngôn ngữ), rồi nhấn ⇧⏎: kết quả được gửi lại cho AI kèm chỉ dẫn của bạn, và kết quả mới thay thế chúng trong cùng bảng. ⏎ chèn kết quả đang chọn, kể cả khi chỉ dẫn mới gõ dở (phần đó bị bỏ). Tinh chỉnh bao nhiêu lần tùy thích; dòng trên cùng của bảng liệt kê các bước ("Refined: shorter · more formal"), và bạn có thể chọn một dòng bất cứ lúc nào như thường. Một chữ cái bắt đầu chỉ dẫn (hiện là "refine › …" ở đầu bảng); khi chỉ dẫn còn trống, chữ số, Space và ⏎ chọn như trước, còn ⇧⏎ chèn nguyên văn những gì bạn đã gõ. Việc tinh chỉnh bắt đầu khi kết quả đã đầy đủ: gõ trong lúc kết quả đầu tiên vẫn đang đến sẽ viết tiếp câu, như trước. Trong lúc một lần tinh chỉnh đang chạy, bạn đã có thể gõ chỉ dẫn tiếp theo; lần tinh chỉnh vẫn tiếp tục, và ⇧⏎ chạy lần tiếp theo ngay khi kết quả của nó về. Esc xóa chỉ dẫn, rồi lùi một bước về kết quả trước lần tinh chỉnh cuối (trong lúc tinh chỉnh: dừng nó), rồi về câu; ⌫ trên dòng trống cũng lùi lại như vậy. Trên văn bản đang chọn, kết quả bạn chọn vẫn thay thế đúng vùng chọn, vốn được giữ nguyên cho đến lúc đó. Lần tinh chỉnh thất bại (hoặc bị từ chối khi ở chế độ nhập liệu bảo mật) giữ nguyên kết quả, và chỉ dẫn của nó sẵn sàng để thử lại bằng ⇧⏎. Cùng một lần tinh chỉnh trên cùng kết quả được trả lời từ bộ nhớ đệm. `@translate` không có tinh chỉnh: gõ sau kết quả của nó sẽ viết tiếp câu, và ⏎ dịch lại câu đó.

### Hội thoại với @question (mới)

Khi `@question` đã trả lời, những gì bạn gõ tiếp là câu hỏi kế tiếp: ⇧⏎ hỏi nó, kèm các câu hỏi và câu trả lời trước đó, và bảng mở rộng thành cuộc hội thoại, các lượt trước được làm mờ thành các dòng Q / A, câu trả lời mới nhất nằm bên dưới. Dòng trên cùng cho biết lượt nào đến tiếp theo ("question 2/5 › …"). Câu trả lời nào cũng có thể chèn: bằng chữ số của nó (1–5), ↑↓ rồi ⏎, hoặc một cú nhấp; câu trả lời mới nhất được chọn sẵn, và ⌘C sao chép câu đang chọn. ⏎ vẫn chèn nó dù câu hỏi mới gõ dở (phần đó bị bỏ). Esc xóa những gì bạn đã gõ, rồi lùi lại một lượt; ở lượt đầu tiên, nó thoát ra như trước. Bảng mở rộng tới khoảng nửa màn hình, rồi cuộn, mục mới nhất ở dưới cùng.

Sau 5 lượt (`questionRounds` trong tệp cấu hình, 2–10), dòng của câu hỏi kế tiếp trở thành "5 rounds in: continue in Claude or another AI" (đã 5 lượt: tiếp tục trong Claude hoặc một AI khác), với các lựa chọn được đánh số ⌘1, ⌘2 …; ⌘⏎ hiện chúng ở bất kỳ lượt nào (khi câu trả lời vẫn đang đến thì nó không làm gì, và không bao giờ đi tới ứng dụng). Những gì bạn gõ lúc đó là tin nhắn đầu tiên ở nơi kia; chỉ ⌘1, ⌘2 … mới gửi nó (⇧⏎ không hỏi thêm gì và không mở gì). Một câu hỏi về văn bản đang chọn mang theo văn bản đó, được trích dẫn thành một khối riêng. Các lựa chọn:

- **Các coding agent đã cài** trên máy Mac này, mỗi agent hiện theo tên: agent mà `@agent` giao việc tới đứng đầu (⌘1), sau đó là các agent khác (Claude Code, Gemini CLI, Kiro CLI, lệnh của riêng bạn trong Settings → Agent). Mỗi agent mở một phiên tương tác trong Terminal, được khởi động giống như `@agent` khởi động nó, bắt đầu bằng cuộc hội thoại và "Let's continue this discussion". Agent chưa được cài sẽ không hiện.
- **Claude** hoặc **ChatGPT** trên web, cuộc hội thoại đã được điền sẵn (cuộc hội thoại dài sẽ được đưa vào clipboard: hãy dán nó).
- **Gemini** trên web, cuộc hội thoại nằm trong clipboard để dán.
- **Copy the conversation** (sao chép cuộc hội thoại), ở dạng Markdown (**Q:** / **A:**).

Những lựa chọn nào, theo thứ tự nào (lựa chọn đầu tiên là mặc định): Settings → General → "Continue a conversation in" (tiếp tục cuộc hội thoại ở; `questionContinueIn` trong tệp cấu hình); khi có hơn 5 nơi, ⌘6 … ⌘9 chọn các nơi còn lại. "@agent's agent" (agent của @agent) ở đó là agent mà Settings → Agent chọn, hiện theo tên của nó; một agent hiện chưa được cài vẫn giữ chỗ của nó trong danh sách khi bạn sửa danh sách. Với Apple Intelligence trên máy Mac này, một cuộc hội thoại dài không vừa ngữ cảnh nhỏ của nó: các câu trả lời cũ nhất được rút gọn, rồi các lượt cũ nhất bị bỏ ra, và bảng hiện "earlier rounds shortened" (các lượt trước đã được rút gọn). Một cuộc hội thoại được lưu dưới câu hỏi đầu tiên của nó trong các câu hỏi gần đây, và chọn nó sẽ hiện các lượt để bạn tiếp tục.

### Câu hỏi gần đây (mới)

`@question` khi không gõ gì phía sau sẽ liệt kê 5 câu hỏi gần nhất của bạn, mới nhất đứng trước, kèm thời điểm hỏi ("3 hours ago"). Gõ thêm để lọc: mỗi từ ở bất kỳ đâu trong câu hỏi, không phân biệt hoa thường (cả tiếng Trung không có dấu cách). Một chữ số, ↑↓ rồi ⏎, hoặc một cú nhấp sẽ hiện ngay câu trả lời đã lưu, không cần lên mạng: Space hoặc ⏎ chèn nó, ⌘C sao chép nó, ⌘R hỏi lại để có câu trả lời mới (với một cuộc hội thoại: câu hỏi mới nhất của nó), Esc quay về danh sách. Một cuộc hội thoại đã lưu hiện tất cả các lượt của nó: gõ để tiếp tục. Khi không có kết quả khớp, hoặc không chọn gì, ⏎ hỏi điều bạn đã gõ. Câu trả lời mới cho cùng câu hỏi, hoặc một cuộc hội thoại được tiếp tục, sẽ thay thế bản đã lưu.

- Chúng chỉ được lưu trên máy Mac này (xem Quyền riêng tư): không lưu khi ở chế độ nhập liệu bảo mật, và không bao giờ lưu câu hỏi về văn bản đang chọn.
- Settings → General → "Remember recent questions" (ghi nhớ câu hỏi gần đây) tắt tính năng (`rememberQuestions` trong tệp cấu hình); tắt ở đó thì cũng xóa chúng. Tắt bằng Settings → Assistant thì chúng được giữ lại, để khi hoàn tác sẽ trả lại đúng như cũ (bản xem trước của nó có ghi rõ); "Clear (N)" (xóa) xóa chúng.

### Ghi chú và lời nhắc

`@note` tạo một ghi chú mới; dòng đầu tiên là tiêu đề. Sau khi sao chép một đoạn văn bản, ⌃V sau `@note ` (hoặc ⌘V, ngoài terminal) lưu nó cùng các ngắt dòng, được hiển thị là ↵ trong lệnh. Nơi lưu do Settings → Plugins → Notes (@note) → Save to (lưu vào) quyết định:

- **Notes** (như trước): một ghi chú mới trong thư mục AllInOneIME.
- **Folder (Obsidian or any)** (thư mục, của Obsidian hoặc bất kỳ): mỗi ghi chú là một tệp Markdown mới trong thư mục bạn chọn, đặt tên theo dòng đầu tiên của nó (`/\:*?"<>|#^[]` được đổi thành `-`; tên đã có thì thêm " 2", " 3"). Tệp chứa phần front matter `created:`, rồi toàn bộ văn bản như đã gõ. Tệp không bao giờ bị ghi đè, và một thư mục không tồn tại (ổ đĩa chưa được gắn, vault đã bị chuyển đi) sẽ không được tạo: thay vào đó ghi chú quay trở lại lệnh. Trong một vault Obsidian (có thư mục `.obsidian` bên trong hoặc ở thư mục cấp trên), thông báo ghi "Saved to Obsidian" (đã lưu vào Obsidian), và bảng trên thanh menu mở ghi chú trong Obsidian.
- **Notion**: Create Integration… (tạo integration; New integration → Internal → sao chép token), dán token (được lưu trong keychain), rồi trong Notion mở trang hoặc cơ sở dữ liệu → ··· → Connections → thêm integration của bạn, và dán liên kết của trang hoặc cơ sở dữ liệu đó; Test hiện "✓ “Inbox” (database)". Một trang nhận thêm một trang con mới, một cơ sở dữ liệu nhận thêm một dòng mới (dòng đầu tiên làm tiêu đề); phần còn lại của ghi chú là nội dung, gửi trong một yêu cầu duy nhất. Khi ngoại tuyến hoặc bị từ chối, không có gì được giữ lại để gửi sau: ghi chú quay trở lại lệnh. Khi đang ở chế độ nhập liệu bảo mật, `@note` không gửi lên Notion.

Thông báo cho biết ghi chú đã được lưu vào đâu ("Saved to Notion", "Saved to “Inbox”"). Nếu bạn rời ô văn bản (nhấp chỗ khác, chuyển ứng dụng) hoặc nhấn ⇧⏎ (chèn nguyên văn) trước khi một ghi chú có ngắt dòng được lưu, nó không được gõ vào ứng dụng (trong terminal, mỗi dòng sẽ chạy như một lệnh): thay vào đó nó được đưa vào bộ nhớ tạm ("The note wasn't saved; its text is on the clipboard" – ghi chú chưa được lưu; văn bản của nó đang ở bộ nhớ tạm). Ghi chú chỉ có một dòng thì được chèn nguyên văn.

`@reminder` đọc được các mốc thời gian như `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (ngày 1 của tháng đó), `end of the year` (cả mốc thời gian tiếng Trung). Ngày và giờ có thể tách rời nhau (`tomorrow call Bob at 5`); tuần bắt đầu vào thứ Hai. Giờ không có am hay pm (`at 5`) là lần kế tiếp của giờ đó, không bao giờ rơi vào khoảng từ nửa đêm đến 6 giờ sáng; giờ đã qua trong hôm nay được hiểu là ngày mai, nhưng một buổi trong ngày vẫn đang diễn ra (`this afternoon`, `tonight`) là hôm nay, cả ngày; ngày đã qua trong năm nay được hiểu là của năm sau. Nếu được viết để lặp lại (`standup every Monday at 9`), lời nhắc chỉ được thêm một lần, cho lần kế tiếp: các từ đó vẫn nằm trong tiêu đề và dòng xác nhận ghi "once only" (chỉ một lần). Dòng xác nhận hiển thị thời gian đã đọc được, ví dụ "tomorrow 3:00 PM" (theo cài đặt 12/24 giờ của máy Mac); nếu sai, Esc quay lại văn bản. Khi không có giờ hay ngày nào, lời nhắc không có thời gian ("no date" – không có ngày).

`@stock` và các lệnh tương tự bên trong hai lệnh này không được chạy: văn bản được lưu đúng như đã viết (gõ `@` ở đó không mở danh sách lệnh). Lần đầu, macOS hỏi AllInOneIME có được điều khiển Notes (`@note`) hoặc truy cập Reminders (`@reminder`) không: hãy cho phép. Nếu bạn chưa cho phép, hãy cho phép AllInOneIME trong System Settings → Privacy & Security → Automation (Notes) hoặc → Reminders. Khi lưu thất bại (chẳng hạn do thiếu quyền), thông báo cho biết lý do và văn bản quay trở lại lệnh để bạn sửa và gửi lại; khi bạn phải sửa điều gì đó trước (một quyền, một tài khoản), văn bản cũng được đưa vào bộ nhớ tạm (vì việc mở System Settings lấy mất tiêu điểm khỏi ô văn bản). Nếu bạn đã chuyển sang ô văn bản khác hoặc đang gõ nội dung khác, thay vào đó văn bản được đưa vào bộ nhớ tạm ("Not saved; the text is on the clipboard." – chưa được lưu; văn bản đang ở bộ nhớ tạm).

### Lệnh của riêng bạn

Trong phần cài đặt, ở mục "Custom @ Commands" (lệnh @ tùy chỉnh), nhấp "Add Command…" (thêm lệnh): đặt tên và chọn việc lệnh sẽ làm (một chỉ dẫn cho AI, một chương trình, một chương trình trong Terminal, một trang web, hoặc một đoạn văn bản để chèn), hoặc bắt đầu từ một ví dụ. Lệnh của bạn xếp sau các lệnh có sẵn; tên chỉ gồm chữ cái tiếng Anh và không được trùng tên một lệnh có sẵn; lệnh có hiệu lực từ câu tiếp theo. Chúng được lưu trong `customCommands` trong tệp cấu hình (`~/.config/allinoneime/config.json`), bạn cũng có thể tự sửa tệp này:

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

| `type` | Chức năng |
|---|---|
| `prompt` | Gửi đến AI với `prompt` làm chỉ dẫn; câu trả lời hiện trong các ứng viên, để chèn hoặc sao chép (⌘C) |
| `run` | Chạy `argv` ở chế độ nền; những gì nó in ra hiện trong các ứng viên (nhiều dòng được chèn đúng như khi in ra, trong terminal thì thành một dòng). Khi có lỗi, dòng cuối cùng của đầu ra được hiển thị |
| `terminal` | Chạy `argv` trong một cửa sổ Terminal mới; không chèn gì |
| `link` | Đưa văn bản vào địa chỉ web `url` và mở nó trong trình duyệt mặc định; không chèn gì |
| `snippet` | Chèn `text` ngay lập tức, với các ký hiệu giữ chỗ đã được điền (xem bên dưới); không dùng AI, không chạy chương trình |

- `{input}` được thay bằng những gì bạn viết sau lệnh, và nó luôn nằm trọn trong đúng một đối số chứa nó: không có shell nào tham gia. Nếu cần shell, hãy chỉ rõ, như `sh` ở trên (`zsh -c`).
- `stdin`: những gì được đưa vào đầu vào chuẩn của chương trình, trong đó `{input}` cũng được thay thế.
- `url` của một `link` phải là `https://`, chứa `{input}` đúng một lần, sau `?` hoặc `#`; văn bản được mã hóa (dấu cách là `%20`, xuống dòng là `%0A`), tối đa 4000 ký tự.
- `run` và `terminal` mặc định gõ chữ cái tiếng Anh (giống `@open`; ở chế độ tiếng Trung, tiếng Trung trở lại sau đó), và dấu câu toàn độ rộng được đổi thành ASCII. Đặt `"ascii": false` để giữ văn bản như đã gõ.
- Chương trình chạy trong thư mục home của bạn với PATH của login shell (nên các bản cài qua Homebrew, pyenv và nvm đều được tìm thấy). `run` dừng chương trình sau 10 giây (`timeoutSeconds`) hoặc khi nó in ra quá nhiều; Esc dừng nó bất cứ lúc nào.
- `summary` là phần mô tả trong danh sách lệnh (không bắt buộc).
- Khi không tìm thấy chương trình trong `argv` (chẳng hạn không có `python3`), lệnh không được cung cấp và `@python …` được chèn như văn bản thường; sau khi chương trình được cài, lệnh xuất hiện ở ô văn bản tiếp theo.

`run` và `terminal` chạy mã trên máy Mac của bạn: chỉ thêm những lệnh bạn tự viết và tin tưởng. Chúng cũng chỉ chạy khi bạn nhấn phím thực thi, và không bao giờ chạy khi đang ở chế độ nhập liệu bảo mật (secure input).

#### Snippet: văn bản bạn hay chèn (mới)

Một lệnh `snippet` ("Insert text" – chèn văn bản – trong trình chỉnh sửa lệnh) chèn văn bản bạn đã lưu, chẳng hạn một chữ ký, một địa chỉ hay một liên kết cuộc họp: `@sig` ⏎ chèn nó ngay (Tab hoặc Space chỉ hoàn thành tên lệnh). `text` của nó có thể chứa các ký hiệu giữ chỗ:

| Ký hiệu giữ chỗ | Được thay bằng |
|---|---|
| `{input}` | mọi thứ bạn viết sau tên lệnh: `@tag foo bar` với `#{input}` chèn `#foo bar` |
| `{name?}` | một chỗ trống, được điền từ những gì bạn viết, cách nhau bằng dấu phẩy (`,` hoặc `，`), theo thứ tự: `Dear {name?}, see you {day?}.` với `@meet Bob, Friday`. Chỗ trống nào chưa được điền sẽ được nêu tên trong một thông báo, và không có gì được chèn |
| `{clipboard}` | văn bản trong bộ nhớ tạm (macOS có thể hỏi trước) |
| `{selection}` | văn bản đang được chọn khi bạn gõ `@` (nó bị thay thế, như với mọi lệnh trên vùng chọn) |
| `{date}`, `{time}` | ngày hôm nay dạng `2026-10-17`, giờ dạng `14:05`; `{date:EEEE, MMM d}` theo một [mẫu định dạng ngày](https://unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table), bằng ngôn ngữ giao diện |
| `{cursor}` | chỗ đặt con trỏ sau khi chèn xong (tối đa một lần; không áp dụng trong terminal) |

- `{{` viết ra `{`, và `}}` đóng nó viết ra `}` (`{{input}}` chèn `{input}`); mọi `}}` hay `{…}` khác được giữ nguyên, nên JSON hay mã trong snippet đều không sao: `{"a":{"b":1}}` được chèn đúng như đã viết.
- Khi không có `{input}` và không có chỗ trống nào, những gì bạn viết sau tên lệnh được chèn sau snippet, cách một dấu cách.
- Viết `@sig` bên trong văn bản của một lệnh khác để đưa snippet vào đó: `@question summarize this @zoom` gửi chính liên kết đó. Chỉ các snippet không có `{clipboard}`, `{selection}` hay chỗ trống mới dùng được như vậy; với `{input}`, đối số là một từ hoặc một cụm trong ngoặc kép: `@meet「Friday 3pm」`.
- Chỉ văn bản thuần (giữ ngắt dòng), tối đa 20000 ký tự. Snippet nằm trên máy Mac này, nên chúng hoạt động cả khi đang ở chế độ nhập liệu bảo mật và trong các ứng dụng đặt No AI. Bundle tiện ích mở rộng cũng có thể kèm snippet (`snippets` trong `extension.json`, xem [docs/extensions.md](../extensions.md)).

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

Các chế độ của Raycast tương ứng như sau: `fullOutput` → `show`, `compact` và `silent` → `silent`, `inline` có `refreshTime` → một status. Toàn bộ giao thức có trong [docs/extensions.md](../extensions.md); [Core/Examples/extensions](../../Core/Examples/extensions) có một ví dụ cho mỗi loại. Tiện ích mở rộng chạy mã trên máy Mac của bạn: hãy dùng những cái bạn tin tưởng. Chúng chỉ chạy khi bạn chạy chúng (status hoặc list thì chạy khi bạn gõ), không bao giờ chạy khi đang ở chế độ nhập liệu bảo mật, và dừng khi bộ gõ thoát.

#### Nguồn tiện ích mở rộng (mới)

Một bundle có thể đến từ một kho Git, của bạn hoặc của nhóm bạn, và được cập nhật từ đó. Settings → Custom Commands → Extension Sources → **Add from Link…** (thêm từ liên kết): dán địa chỉ của kho (`git@github.com:you/my-extensions.git`, `ssh://…`, `https://…`; tùy chọn thêm một nhánh, thư mục của bundle trong kho, và một tag hoặc commit để ghim vào). AllInOneIME clone nó bằng **thiết lập git và SSH của chính bạn** (khóa, agent, ~/.ssh/config, credential helper), nên một kho riêng tư hoạt động giống như trong Terminal; ứng dụng không bao giờ hỏi hay lưu mật khẩu. Bản clone được đặt vào `~/Library/Application Support/AllInOneIME/Sources/`: trước hết vào một thư mục tạm ẩn, không bao giờ đặt thẳng vào một thư mục tiện ích mở rộng. (Đừng đặt tên người dùng, mật khẩu hay token vào một địa chỉ https: credential helper của git sẽ giữ chúng.)

- **Xem xét trước.** Trước khi bất cứ thứ gì được nạp, bạn thấy bundle, mọi lệnh (tên, tiêu đề, mô tả, đầu ra), các chương trình chúng chạy, tùy chọn của nó, và commit, bên dưới cảnh báo "This source isn't signed: it will run programs from <address>" (nguồn này chưa được ký: nó sẽ chạy các chương trình từ địa chỉ đó). Chỉ **Enable** (bật) mới thêm nó; Cancel (hủy) xóa bản clone. Mỗi nguồn chỉ cần xem xét một lần.
- **Việc áp dụng cập nhật là do bạn.** Mỗi ngày một lần (và ngay sau khi bộ gõ khởi động) nguồn được fetch để xem có gì mới: Settings hiện "N updates" (N bản cập nhật) với các commit (tiêu đề, tác giả, ngày) và một huy hiệu trên trang. Không có gì thay đổi cho đến khi bạn nhấp **Update** (cập nhật), vốn chỉ fast-forward và không chạy hook nào. Một lần force push khiến nguồn cần được xem xét lại: **Re-clone** (clone lại) hiện nó, và chỉ Enable mới đưa lịch sử đã viết lại vào chỗ (cho đến lúc đó, phiên bản đã xem xét vẫn tiếp tục hoạt động). Nguồn được ghim vào một tag hoặc commit sẽ không được kiểm tra. Có thể tắt việc kiểm tra hằng ngày cho từng nguồn (`autoCheck`).
- **Lỗi** là nguyên văn lời của git, kèm "This uses your own git and SSH setup; check that `git ls-remote <url>` works in Terminal" (việc này dùng thiết lập git và SSH của chính bạn; hãy kiểm tra lệnh đó có chạy được trong Terminal không), và lời nhắc của riêng bạn bên dưới nếu bạn đã đặt (`authHint` trong tệp cấu hình).
- **Remove** (gỡ bỏ) chuyển bản clone vào Thùng rác; tùy chọn của bundle được giữ lại cho lần sau.
- Từ terminal: `AllInOneIME --add-source <url> [--path …] [--branch …] [--pin …]` (in phần xem xét và bật nguồn; chạy lại sau một lần force push), `--update-sources` (fast-forward mọi nguồn đã xem xét và không bị ghim), `--list-extensions` (trên `~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME`).
- Chỉ mã đã xem xét mới được nạp: một thư mục nguồn trong danh sách nạp mà chưa được xem xét trên máy Mac này (một tệp cấu hình sao chép từ nơi khác) sẽ bị bỏ ra. git không bao giờ chờ câu trả lời: không có terminal và không có lời nhắc, nên một khóa máy chủ lạ hoặc một yêu cầu mật khẩu sẽ thất bại ngay.

Tệp cấu hình lưu chúng dưới `extensionSources`; cấu trúc của kho có trong [docs/extensions.md](../extensions.md#10-extension-sources).

### Plugin

Plugin là các lệnh `@` làm sẵn cho những việc không phải ai cũng cần, như `@stock AAPL 600519 700` để xem giá cổ phiếu. Sau khi cài, chúng hoạt động như mọi lệnh khác; mục "Plugins" trong phần cài đặt cho thấy những gì đã cài và nơi mỗi plugin gửi văn bản của bạn đến, và cho phép gỡ chúng. Plugin là JavaScript chạy trong một tiến trình riêng: chúng chỉ có thể truy cập các trang web mà chúng khai báo (HTTPS), và không thể đọc tệp hay chạy chương trình khác. "Browse Library…" (duyệt thư viện) ở mục Plugins trong phần cài đặt cài chúng từ [thư viện plugin](https://github.com/MicroZ-LLC/AllInOneIME-plugins): trước khi cài, nó cho biết plugin liên hệ với những trang web nào; chỉ mục của thư viện được ký và mọi tệp phải khớp với chỉ mục đó. Khi có phiên bản mới hơn, một nút "Update" sẽ hiện ra; không có gì tự cập nhật. Plugin của riêng bạn đặt trong `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): đó là plugin cục bộ, không bao giờ bị thư viện ghi đè. Plugin dạng "Link" không chạy mã: chúng đưa văn bản vào một địa chỉ web và mở nó trong trình duyệt, như `@x nice weather today`, mở khung soạn bài của X với văn bản đã điền sẵn; đăng hay không là do bạn quyết định trên trang đó. Thư viện có bốn plugin như vậy (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` quy đổi tiền tệ: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, một dòng kèm ngày của tỷ giá (tỷ giá từ ExchangeRate-API). `@calculator` là máy tính bỏ túi hoạt động ngoại tuyến, `@calculator 23*17` → `391` (trước 0.6.5 là lệnh tích hợp `@calculate`), và `@calendar` tính ngày tháng: `@calendar +10` → "Tue, Oct 27 · in 10 days". Cách viết một plugin: [docs/plugins.md](../plugins.md).

Các lệnh lấy dữ liệu (plugin và chương trình) cũng hoạt động bên trong một câu: `@reply tell her @stock AAPL is up today`. Các lệnh bên trong chạy trước, đầu ra của chúng thế vào chỗ của chúng, và lệnh bên ngoài xử lý kết quả đó. Đối số là từ đứng sau lệnh, cộng với các mã viết hoa hoặc con số ngay sau đó (`@stock AAPL TSLA`, `@stock 600519 700`); một từ viết thường sẽ kết thúc đối số (`@stock SNDK is good to buy` tra cứu SNDK). Dấu ngoặc kép đánh dấu chính xác đối số: `@stock "aapl tsla"`. Plugin `@calculator` cũng hoạt động ở đó: `@reply the total is @calculator 23*17 dollars`. Bên trong `@agent` và các lệnh terminal, chúng không được chạy: các lệnh đó nhận văn bản đúng như đã viết (gõ `@` ở đó không mở danh sách lệnh).

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
| Không dùng AI trong ứng dụng này | `@improve`, `@translate`, `@question`, `@agent` và các lệnh chỉ dẫn của bạn không gửi gì ở đó và báo như vậy; gõ chữ và các lệnh khác vẫn hoạt động | `noAI` |
| Luôn dịch trong khi gõ | WeChat luôn bật dịch trong khi gõ (xem [Dịch trong khi gõ](#dịch-trong-khi-gõ)) | `translateAlways` |

"Add App…" (thêm ứng dụng) liệt kê các ứng dụng bạn gõ gần đây, hoặc chọn một ứng dụng trong /Applications. Menu nhập, ở mục "This App: <tên>", có các công tắc nhanh cho ứng dụng bạn đang gõ (No AI, Type Results Out, ngôn ngữ khởi đầu). Trong tệp cấu hình, chúng nằm dưới `appProfiles`, theo bundle ID: `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. Bundle ID được so khớp không phân biệt hoa thường (`com.apple.Mail` chính là `com.apple.mail` của Mail). `@reportissue` đếm số ứng dụng có đặt gì đó, không bao giờ nêu tên chúng.

- Ngôn ngữ khởi đầu hoạt động như ngôn ngữ nhập mặc định: ô văn bản nhận nó khi trở nên hoạt động, và việc đổi bằng Shift sau đó được giữ cho các ô của ứng dụng ấy cho đến khi cài đặt thay đổi.
- Với No AI, các lệnh AI vẫn nằm trong danh sách @; chạy một lệnh sẽ hiện thông báo và giữ lại những gì bạn đã viết. Các lệnh terminal của riêng bạn (`"type": "terminal"`) chạy chương trình chứ không phải AI, nên vẫn hoạt động ở đó.

### Settings → Assistant (mới)

Phần cài đặt mở ở **Assistant**, một trang có hai phần (trước 0.6.5, đó là các lệnh `@config` và `@doctor`).

**Đổi cài đặt bằng một câu** ("Change settings in a sentence"): viết điều bạn muốn ("translate into Japanese and English", "candidates in a column", "use Claude") rồi nhấn Preview (hoặc ⌘⏎). Mỗi thay đổi hiện dạng cũ → mới; Apply áp dụng chúng, và Undo hoàn tác trong vòng 10 phút. Nó cũng bật hoặc tắt được việc đồng bộ qua iCloud (còn đồng bộ những gì thì chỉ chọn được trong Settings). Khóa API, lệnh của riêng bạn, plugin và mọi thứ chạy chương trình không bao giờ bị đổi ở đó; nhà cung cấp chưa có khóa sẽ mở ô nhập khóa trong Settings → AI Provider, và Test Connection chạy sau khi đổi nhà cung cấp. Nó chạy trên Apple Intelligence nếu máy Mac này có, nếu không thì trên nhà cung cấp của bạn.

**Kiểm tra sự cố** ("Check for problems"): bộ gõ, nhà cung cấp AI, quyền, nhập an toàn, gói ngôn ngữ, `config.json`, tiện ích mở rộng, bản cập nhật, đồng bộ qua iCloud (bật hay tắt, lần đồng bộ gần nhất, lỗi gần nhất, iCloud Drive không khả dụng, cài đặt từ iCloud không dùng được ở đây) và lỗi gần đây được kiểm tra trên máy Mac này khi trang mở ra, sự cố trước (mọi thứ ổn: "Everything looks good"). Check kiểm tra lại cùng Test Connection; nếu có câu hỏi trong "What's wrong? (optional)", AI sẽ giải thích nguyên nhân có thể. Dòng nào sửa được có nút Fix: thay đổi cài đặt hiện trong bản xem trước phía trên, với Apply và Undo; các cách sửa khác thực hiện ngay.

### Đồng bộ qua iCloud (mới)

Settings → General → **Sync through iCloud** (đồng bộ qua iCloud; mặc định tắt) giữ cho cài đặt, danh sách jargon, lệnh tùy chỉnh và các từ mà pinyin đã học giống nhau trên mọi máy Mac của bạn, thông qua iCloud Drive của chính bạn: không phải đăng nhập thêm gì, không có gì đi qua máy chủ của chúng tôi. Tính năng này cần iCloud Drive (Cài đặt hệ thống → Tài khoản Apple → iCloud); nếu không có, công tắc vẫn tắt và báo như vậy, kèm một nút mở mục cài đặt đó.

| Công tắc | Những gì được đồng bộ | Mặc định |
| --- | --- | --- |
| Settings (cài đặt) | các cài đặt trong `config.json`: ngôn ngữ, kiểu viết lại, phím thực thi, gõ ra kết quả, cài đặt theo ứng dụng, ẩn thông tin nhạy cảm (các công tắc của nó), nhà cung cấp AI và mô hình (không bao giờ có khóa) … | bật |
| Jargon and custom commands (jargon và lệnh tùy chỉnh) | danh sách jargon và `customCommands` của bạn | bật |
| Learned words (từ đã học) | những gì pinyin học được từ các lựa chọn của bạn (từ điển người dùng của Rime, qua cơ chế đồng bộ từ điển người dùng của librime; các tệp Rime của riêng bạn, như cụm từ tùy chỉnh, vẫn ở lại trên máy Mac) | bật |
| Hidden words (từ bị ẩn) | các từ bạn ẩn khỏi AI ("iCloud Drive is end-to-end encrypted only with Advanced Data Protection" – iCloud Drive chỉ được mã hóa đầu cuối khi bật Bảo vệ dữ liệu nâng cao) | tắt |
| Recent questions (câu hỏi gần đây) | các câu hỏi gần đây của `@question` cùng câu trả lời (khi "Remember recent questions" đang bật) | tắt |
| API keys and passwords (API key và mật khẩu) | các API key của bạn và mật khẩu của tiện ích mở rộng, qua Chuỗi khóa iCloud (iCloud Keychain), vốn luôn được mã hóa đầu cuối (cần bật Mật khẩu & Chuỗi khóa trong Cài đặt hệ thống → Tài khoản Apple → iCloud) | tắt |

`iCloud Drive/AllInOneIME/settings.json` lưu từng cài đặt kèm thời điểm nó thay đổi và trên máy Mac nào (một id ngẫu nhiên), và với mỗi cài đặt, thay đổi mới nhất sẽ thắng: một danh sách (lệnh tùy chỉnh, kiểu viết lại) được tính là một giá trị, cài đặt theo ứng dụng được xét theo từng ứng dụng, và việc xóa cài đặt của một ứng dụng cũng là một thay đổi. Việc đồng bộ diễn ra khi bộ gõ khởi động, khoảng 5 giây sau khi bạn thay đổi gì đó, khi iCloud mang về một thay đổi từ máy Mac khác (và cứ 5 phút một lần), và khi nhấn **Sync Now** (đồng bộ ngay); riêng các từ đã học thì khi bộ gõ khởi động, cứ 30 phút một lần (sau một quãng ngừng gõ) và khi nhấn Sync Now. Dòng trạng thái ghi "Last synced 2 min ago" (đồng bộ lần cuối 2 phút trước), "Waiting for iCloud…" (đang chờ iCloud) hoặc lỗi.

- Khi bật tính năng, một máy Mac nhận các cài đặt đã có trong iCloud; cài đặt của chính nó chỉ điền vào những gì iCloud chưa có. Còn các danh sách của nó thì được gộp lại: câu hỏi gần đây (cả hai danh sách, mới nhất đứng trước, mỗi câu hỏi một lần), từ bị ẩn, lệnh tùy chỉnh (theo tên; trùng tên thì lấy bản trong iCloud) và các dòng của danh sách jargon. Điều tương tự xảy ra khi một công tắc bên dưới được bật lần đầu. Những gì bạn bỏ đi trên một máy Mac khác sau đó (một lệnh tùy chỉnh hay từ bị ẩn đã xóa) sẽ không quay lại. Ngoại lệ là nó quay lại một lần (xóa lần nữa thì mất hẳn) khi: nó đến từ máy Mac đầu tiên bật đồng bộ và máy đó đang ngủ trong lúc một máy Mac khác gộp danh sách của mình vào; nó bị xóa trên một máy Mac vẫn chạy 0.6.4; hoặc một máy Mac vẫn chạy 0.6.4 đưa nó trở lại. Một cài đặt được lưu trong Settings trong lúc một máy Mac đang bật đồng bộ sẽ được giữ lại, và được chuyển sang các máy Mac khác.
- Bật lại sau khi đã tắt: những gì iCloud thay đổi trong thời gian đó sẽ được đưa về (kể cả ở những chỗ máy Mac này cũng đã thay đổi), những gì chỉ máy Mac này thay đổi sẽ được đưa lên, và một danh sách mà máy này đã thêm vào trong thời gian đó sẽ được gộp, không bao giờ bị bỏ.
- Câu hỏi gần đây của hai máy Mac được gộp lại; "Clear" trên một máy Mac cũng xóa trên các máy khác mọi câu hỏi được hỏi trước thời điểm đó. Tắt "Remember recent questions" chỉ xóa chúng trên máy Mac đó, và khi bật lại, câu hỏi của các máy Mac khác quay về máy đó. Một lần Clear thực hiện trong lúc một máy Mac không đồng bộ câu hỏi gần đây (hoặc không ghi nhớ chúng) chỉ có tác dụng trên máy Mac đó.
- Tắt Hidden words hoặc Recent questions sẽ để nguyên những gì đã được đồng bộ trong iCloud: **Remove from iCloud…** (gỡ khỏi iCloud) dưới mỗi công tắc (có hỏi trước) sẽ gỡ chúng ra; các máy Mac khác vẫn giữ bản của mình, và máy nào vẫn đồng bộ chúng sẽ đưa bản của mình trở lại.
- Một giá trị từ máy Mac khác mà máy này không dùng được (một nhà cung cấp chưa có khóa ở đây, một AWS profile máy này không có, một giá trị ngoài phạm vi) sẽ không được áp dụng: dòng trạng thái và phần Check for problems của Settings → Assistant cho biết đó là giá trị nào.
- Một tệp iCloud chưa tải về sẽ được chờ, không bao giờ bị coi là rỗng; một `settings.json` không đọc được sẽ được để sang một bên thành `settings (unreadable …).json`, không bao giờ bị ghi đè. Cài đặt của một phiên bản mới hơn được giữ nguyên.
- API key và mật khẩu đi qua Chuỗi khóa iCloud, không qua iCloud Drive: khi bật "API keys and passwords" (trong lúc đồng bộ đang bật), một khóa được lưu hoặc thay trên một máy Mac sẽ có mặt trên các máy khác. Công tắc này mặc định tắt: chỉ bật đồng bộ thì không khóa nào được chuyển đi, và không có gì được chuyển cho đến khi bạn bật nó. Bật nó sẽ chuyển các khóa của máy Mac này từ keychain đăng nhập sang Chuỗi khóa iCloud (từ đó macOS không còn hỏi mật khẩu đăng nhập của bạn cho chúng sau mỗi lần cập nhật nữa); tắt nó sẽ chép chúng trở lại keychain đăng nhập và vẫn để chúng trong Chuỗi khóa iCloud cho các máy Mac khác của bạn. Các khóa không đồng bộ vẫn nằm trong keychain đăng nhập như trước, phiên đăng nhập AllInOneIME Cloud cũng vậy, và nó không bao giờ được đồng bộ: mỗi máy Mac tự đăng nhập. Khi hai máy Mac có khóa khác nhau, khóa được lưu sau cùng sẽ thắng (theo thời điểm lưu, mà mọi bản sao đều giữ). Khóa kia không bị xóa: nó được giữ trong keychain đăng nhập của máy Mac đó thành một bản bị thay thế (dưới mục "AllInOneIME replaced API key", tên kết thúc bằng "(replaced)"), và không bao giờ được dùng. Một khóa được chuyển vào Chuỗi khóa iCloud cũng giữ một bản như vậy, phòng khi một khóa khác từ máy Mac khác ghi đè lên nó. Trên mỗi máy Mac, mỗi khóa chỉ có một bản bị thay thế: bản sau thay cho bản trước. Gỡ một khóa trong lúc nó đang được đồng bộ sẽ gỡ nó trên mọi máy Mac có đồng bộ khóa (câu hỏi xác nhận ghi "all your Macs" – mọi máy Mac của bạn), cùng với bản bị thay thế của máy Mac này; một máy Mac tắt "API keys and passwords", hoặc vẫn chạy 0.6.4, giữ bản của riêng nó, và sẽ đưa nó trở lại nếu sau này bật đồng bộ khóa trên máy đó (câu hỏi cũng nói rõ điều này). Trên một máy Mac tắt công tắc này, Remove… chỉ gỡ khóa và bản bị thay thế của nó khỏi máy Mac đó (câu hỏi ghi "this Mac" – máy Mac này), còn bản trong Chuỗi khóa iCloud vẫn ở lại cho các máy Mac khác của bạn. Một khóa mà vào lúc cần chuyển, macOS không cho AllInOneIME đọc nếu không có mật khẩu đăng nhập của bạn, sẽ ở lại trong keychain đăng nhập cho đến lần dùng tiếp theo: khi đó nếu macOS hỏi và bạn cho phép, nó lại được dùng, kể cả khi nó đã bị gỡ trên một máy Mac khác. Mỗi khóa vẫn chỉ được gửi tới đúng máy chủ mà nó được lưu cho. Trong lúc khóa được đồng bộ, `allinoneime-cli` và các phiên bản trước 0.6.5 không thấy chúng trong keychain. Một bản dựng không có provisioning profile (bản dựng phát triển) giữ khóa trong keychain đăng nhập và không đồng bộ được chúng: công tắc báo như vậy.
- Không bao giờ được đồng bộ: phiên đăng nhập AllInOneIME Cloud, thông tin đăng nhập AWS (trong `~/.aws`), nguồn tiện ích mở rộng (chúng chạy mã: mỗi máy Mac tự quyết định), thư mục tiện ích mở rộng và plugin (đường dẫn trên từng máy Mac), danh sách ứng dụng không gõ sai và các ứng dụng gần đây, trạng thái cửa sổ, và chính các công tắc đồng bộ (mỗi máy Mac có công tắc riêng).
- Tắt tính năng sẽ dừng đồng bộ và để mọi thứ nguyên như cũ, trên máy Mac này và trong iCloud; **Remove from iCloud…** (có hỏi trước) chuyển thư mục vào Thùng rác và tắt đồng bộ trên máy Mac này.
- Settings → Assistant ("sync through iCloud") bật hoặc tắt tính năng; từ bị ẩn và câu hỏi gần đây chỉ chọn được trong Settings → General. Trong tệp cấu hình: `iCloudSync` (`enabled`, `settings`, `jargon`, `learnedWords`, `hiddenWords`, `recentQuestions`, `keys`).

## Bảng trên thanh menu

<img src="../en/panel-swipe.png" width="520" alt="Bảng trên thanh menu: nền kính mờ, với ghi chú, lời nhắc và tác vụ Claude trên các thẻ; một dòng được vuốt sang trái hiện nút Remove">

Nhấp vào biểu tượng của AllInOneIME trên thanh menu (dấu ∞ kèm con trỏ, không có khung; biểu tượng có khung là nguồn nhập) và bảng sẽ thả xuống bên dưới nó; nhấp chỗ khác để đóng:

- Notes: các ghi chú đã lưu bằng `@note`, 5 ghi chú mới nhất; nhấp vào một ghi chú để mở nó ở nơi nó được lưu: trong Notes, trong Obsidian hoặc ứng dụng mặc định của tệp, hoặc trang Notion. Tệp không còn nữa thì không được liệt kê.
- Reminders: các lời nhắc chưa hoàn thành trong danh sách AllInOneIME của Reminders (`@reminder` thêm vào danh sách đó), cái đến hạn sớm nhất xếp trước, hiển thị 8 cái; nhấp vào vòng tròn để đánh dấu hoàn thành, hoặc vào tiêu đề để mở Reminders.
- Claude Tasks: giống `@tasks`, các tác vụ Claude chạy nền (những gì `@agent` giao cho Claude Code), tối đa 30, mỗi lần hiển thị 5: cuộn để xem thêm, hoặc tìm theo tiêu đề và câu trả lời trong ô tìm kiếm; kèm tiến độ và dòng đầu tiên của câu trả lời gần nhất; nhấp vào một tác vụ để mở nó trong Terminal và làm tiếp.

Vuốt một dòng (ghi chú, lời nhắc hoặc tác vụ) sang trái bằng hai ngón tay để hiện nút "Remove" (gỡ), hoặc vuốt hết cỡ để gỡ ngay; với chuột, nhấp chuột phải vào dòng đó. Việc gỡ chỉ đưa nó ra khỏi bảng: ghi chú vẫn ở trong Notes, lời nhắc vẫn ở trong Reminders (chưa hoàn thành), tác vụ vẫn ở trong Claude Code.

Phần đầu bảng hiển thị số lượng (như "2 reminders · 1 task running"; tác vụ đang chờ bạn được đếm riêng, như "1 waiting for you") và một nút làm mới. Bảng không bao giờ lấy tiêu điểm khỏi ứng dụng bạn đang gõ: đánh dấu hoàn thành một lời nhắc hay làm mới đều để ứng dụng đó ở phía trước; chỉ ô tìm kiếm của tác vụ Claude, khi được nhấp vào, mới nhận bàn phím. Biểu tượng được hiển thị theo mặc định; tắt nó ở mục "Menu Bar Panel" trong phần cài đặt.

Bảng đọc những gì, và khi nào:

- Notes: danh sách là bản ghi riêng của bảng (được giữ cả khi bảng đóng), và Notes không bao giờ được khởi chạy: chỉ khi Notes đang chạy sẵn, và AllInOneIME trước đó đã được phép điều khiển nó, bảng mới kiểm tra Notes để cập nhật tiêu đề đã sửa và ghi chú đã xóa.
- Reminders: danh sách AllInOneIME được đọc khi bảng thả xuống, mỗi 60 giây và khi lời nhắc thay đổi. Bảng không bao giờ tự khiến macOS hỏi quyền truy cập: nếu macOS chưa hỏi bạn, bảng hiển thị "Allow Access to Reminders", và chỉ nút đó mới hỏi; nếu bạn đã từ chối, bảng hiển thị "Open System Settings".
- Tác vụ Claude: bảng chỉ chạy `claude agents` khi đang thả xuống: một lần khi thả xuống, khi nhấn Refresh, và khi `@agent` giao một tác vụ; và cứ 15 giây một lần khi còn tác vụ chưa xong, dừng lại khi tất cả đã xong. Câu trả lời gần nhất được đọc từ cuối các bản ghi hội thoại (transcript) của Claude Code trên máy Mac này (`~/.claude/projects`), và chỉ khi bản ghi đã thay đổi.
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
- **Personal Dictionaries** (từ điển cá nhân, khi nhập tiếng Trung): Settings → Input → Chinese (pinyin) → Personal Dictionaries → **Import or Update…** thêm một tệp từ vựng Rime UTF-8 (`.dict.yaml`) bên cạnh rime-ice (cần cài gói ngôn ngữ tiếng Trung trước). Danh sách hiển thị `name` của Rime, tên tệp và số mục của từng tệp; nhập lại cùng `name` sẽ thay bản sao đã lưu (chỉ sửa tệp gốc thì không). Mỗi lần nhập, cập nhật hoặc xóa đều biên dịch lại từ điển bính âm (toàn bộ từ của rime-ice cộng với của bạn), có thể mất khoảng một phút; trong lúc đó không gõ được tiếng Trung, và trang hiển thị tiến độ hoặc lỗi. Các bản sao nằm trên máy Mac này, ngoài đồng bộ iCloud và các yêu cầu gửi đến AI; nhưng từ bạn chọn từ chúng được học như mọi từ khác, vào từ điển người dùng của Rime, vốn được đồng bộ cùng các từ đã học khi bật và vẫn còn sau khi xóa từ điển. Nếu bạn có `rime_ice.custom.yaml` của riêng mình, việc nhập sẽ bị từ chối trước khi bất kỳ tệp nào thay đổi.
- **Translate (@translate)**: thêm các ngôn ngữ cần dịch sang (tiếng Tây Ban Nha, tiếng Pháp, tiếng Đức, tiếng Nhật, tiếng Hàn, tiếng Trung, tiếng Hindi, tiếng Bengal, tiếng Tamil và các ngôn ngữ chính khác của Ấn Độ…) và kéo để sắp xếp thứ tự. Tiếng Hindi gõ bằng chữ Latin ("aap kaise ho") được trả về bằng chữ Devanagari. `@translate` viết một dòng cho mỗi ngôn ngữ, theo thứ tự này (ba phiên bản nếu chỉ có một ngôn ngữ); ngôn ngữ của chính câu đó được bỏ qua. Bản cài mới dịch sang ngôn ngữ đầu tiên trong danh sách ngôn ngữ ưu tiên của máy Mac mà không phải tiếng Anh; nếu chỉ có tiếng Anh, `@translate` báo rằng chưa có ngôn ngữ nào để dịch sang, và nhấn ⏎ trên thông báo đó sẽ mở trang này với "Add…" (thêm…) được đóng khung (câu được chèn đúng như bạn đã gõ). Khi đó Dịch trong khi gõ cũng không bật, và cho biết nơi thêm một ngôn ngữ.
- **Keyboard layouts** (bố cục bàn phím): tiếng Pháp gõ bằng bố cục được chọn trên thẻ của nó (`keyboardLayouts` trong tệp cấu hình). Với các ngôn ngữ khác, khi dùng bộ gõ, macOS giữ bố cục Latin cuối cùng của bạn (AZERTY, QWERTZ, Spanish, US International…), nên bạn gõ như thường lệ, kể cả `@` ở bất cứ vị trí nào bố cục của bạn đặt nó, và phím chết cũng ghép dấu trong văn bản của lệnh (⌥E rồi E → é, ^ rồi e → ê). Các bố cục không có chữ Latin (tiếng Nga, Hindi InScript) không dùng được dưới một bộ gõ: hãy chuyển sang chúng bằng ⌃Space, hoặc dán (⌃V) hay đọc chính tả văn bản vào một lệnh.
- `@improve` trau chuốt và viết lại mà không dịch; `@translate @improve` dùng cùng nhau sẽ dịch và viết lại trong một yêu cầu. Bật "@improve also translates" trong phần cài đặt để `@improve` luôn làm như vậy.

Một từ điển cá nhân trông như sau (các trường của mỗi mục được ngăn cách bằng **tab**):

```yaml
---
name: my_vocabulary
version: "1"
columns: [text, code, weight]
...
星河项目	xing he xiang mu	100
蓝杉团队	lan shan tuan dui	200
```

Viết bính âm bằng chữ Latin thường, có dấu cách giữa các âm tiết và `v` thay cho `ü`; trọng số là tùy chọn (một số không âm). Không có `columns` thì thứ tự là `text`, `code`, `weight`. `name` có thể chứa chữ Latin, chữ số, `-`, `_` và `.`; mỗi tệp tối đa 32 MiB. Tệp phụ thuộc vào `import_tables` hoặc thiếu mã bính âm sẽ bị từ chối mà không thay đổi gì.

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

## Dịch trong khi gõ

Đây là một bản thử nghiệm (prototype) để bạn dùng thử. Giữ riêng phím Shift trong 1 giây để bật (hoặc tắt) "Translate as You Type" (dịch trong khi gõ); nhấn nhanh Shift vẫn chuyển ngôn ngữ nhập như trước. Đến 0,5 giây, một gợi ý gần con trỏ hiện "Keep holding → Translate as You Type" (giữ tiếp → dịch trong khi gõ), và đến 1 giây, "Translate as You Type on: Chinese → English · hold Shift again to turn off" (đã bật dịch trong khi gõ: tiếng Trung → tiếng Anh · giữ Shift lần nữa để tắt; có nêu ngôn ngữ đích) xác nhận trong khoảng 1,5 giây (khi tắt: "Keep holding → Translate as You Type off", rồi "Translate as You Type off"); thả phím ra trước lúc đó thì không có gì thay đổi. Shift cùng một chữ cái (để viết hoa) hoặc cùng một phím khác không bao giờ bật nó. Khi đang bật, biểu tượng trên thanh menu có thêm một chấm nhỏ. Không có lệnh nào cho tính năng này.

Khi đang bật, những gì bạn gõ được gom vào một bản nháp, kèm thẻ ngôn ngữ bên cạnh ("ZH → EN"; 「中 → 英」 trong giao diện tiếng Trung). Nó dịch sang ngôn ngữ bạn chọn gần nhất trên thẻ đó (xem bên dưới), trong mọi ứng dụng và cả sau khi khởi động lại; cho đến khi bạn chọn, nó dịch sang ngôn ngữ dịch đầu tiên của bạn trong Settings (và quay về ngôn ngữ đó khi ngôn ngữ đã chọn không còn trong danh sách). Nếu bạn chỉ gõ một ngôn ngữ, ngôn ngữ đó được bỏ qua: chỉ gõ tiếng Anh, với ngôn ngữ dịch là tiếng Anh rồi tiếng Pháp, thì nó dịch sang tiếng Pháp. Ngôn ngữ bạn đang gõ lúc bật không làm thay đổi điều này. ⏎ dịch bản nháp và bản dịch được chèn ngay, không có ứng viên để chọn: trong lúc đó bản nháp hiện "Translating…" (đang dịch), và chưa có gì được gửi đi (nhấn ⏎ lần nữa mới là phím ⏎ của ứng dụng). ⇧⏎ chèn bản nháp nguyên văn; Esc trong lúc đang dịch sẽ dừng việc dịch và giữ bản nháp (⌫ cũng dừng nó, và xóa một ký tự như khi trên bản nháp); nếu thất bại (lỗi mạng, bị từ chối, chế độ nhập liệu bảo mật), bản nháp vẫn còn kèm một thông báo một dòng và ⏎ sẽ thử lại. Văn bản gõ bằng chính ngôn ngữ đích (nhấn nhanh Shift để chuyển sang tiếng Anh) được chèn nguyên văn.

Khi đang bật, một thẻ nhỏ "ZH → EN" (「中 → 英」 trong giao diện tiếng Trung) hiện bên dưới dòng bạn đang gõ, trong bảng riêng của bộ gõ (bảng ứng viên: nằm trên các ứng viên khi bạn gõ pinyin), nên nó không bao giờ lấy tiêu điểm khỏi ứng dụng. Nhấp "ZH" để chuyển ngôn ngữ nhập, như khi nhấn nhanh Shift. Nhấp "EN" để mở một danh sách ngắn các ngôn ngữ dịch của bạn, ngôn ngữ hiện tại được đánh dấu, rồi nhấp chọn một ngôn ngữ: nó trở thành ngôn ngữ đích ngay lập tức (thẻ và lần dịch kế tiếp đổi theo) và từ đó về sau. Các phím vẫn hoạt động như trước; nhấn một phím sẽ đóng danh sách.

- **Giọng điệu**: theo ứng dụng: kiểu viết lại đầu tiên của ứng dụng trong Settings → Apps, nếu không có thì thân mật trong ứng dụng chat (WeChat, Slack, Messages, Telegram, Discord, Teams), trang trọng trong ứng dụng email (Mail, Outlook, Spark), tự nhiên ở những nơi khác.
- **Ứng dụng**: chuyển sang ứng dụng khác (kể cả ứng dụng không có ô văn bản) sẽ tắt nó, không có thông báo, và khi quay lại thì nó vẫn tắt, trừ khi ứng dụng đó bật "Always Translate as You Type" (luôn dịch trong khi gõ; 「总是边打边译」 trong giao diện tiếng Trung) trong Settings → Apps (`translateAlways` trong hồ sơ của nó): ở đó nó tự bật. Trong ứng dụng đặt No AI, nó không làm gì: văn bản được chèn nguyên văn, kèm một thông báo; những gì bạn gõ khi đang ở chế độ nhập liệu bảo mật (một ô mật khẩu) cũng vậy.
- **Quyền riêng tư**: như với `@translate`: chỉ được gửi khi bạn nhấn ⏎, đến nhà cung cấp AI của chính bạn, với thông tin nhạy cảm được ẩn nếu tính năng đó đang bật.

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

Cập nhật lên 0.6.3 từ phiên bản cũ hơn: 0.6.3 là phiên bản đầu tiên được ký bằng Developer ID, nên keychain chưa nhận ra nó là ứng dụng đã lưu các khóa của bạn. Lần đầu nó cần đến từng khóa đã lưu (một API key, phiên đăng nhập AllInOneIME Cloud, mật khẩu của một tiện ích mở rộng), macOS sẽ hỏi mật khẩu đăng nhập của bạn: nhập mật khẩu rồi nhấp "Always Allow" (Luôn cho phép). Sau đó nó không hỏi lại nữa, kể cả sau những lần cập nhật sau. Khóa của Amazon Bedrock nằm trong `~/.aws/credentials`, không bị ảnh hưởng. Trợ năng (Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng), thứ mà việc dán vào terminal và đọc vùng chọn sử dụng, cũng cần một bước: nếu AllInOneIME có trong danh sách, hãy gỡ nó ra rồi bật lại khi được hỏi.

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

Bản dịch và bản viết lại được gửi đến nhà cung cấp AI chọn trong Settings → AI Provider. Bản cài mới bắt đầu với AllInOneIME Cloud: đăng nhập là có 20 yêu cầu miễn phí mỗi ngày. Trên máy Mac có Apple Intelligence, mọi thứ có thể chạy ngay trên máy Mac này thay vào đó, không cần tài khoản (xem "Apple Intelligence trên máy Mac này" bên dưới). Hoặc dùng nhà cung cấp của riêng bạn, chi phí tính vào tài khoản của bạn: Amazon Bedrock trong tài khoản AWS của bạn, Claude API, Gemini hay một dịch vụ tương thích OpenAI (xem "Các nhà cung cấp AI khác" bên dưới).

### Amazon Bedrock

1. Bật Bedrock trong AWS console và đảm bảo bạn có thể dùng mô hình đã chọn. Mặc định là Claude Haiku 4.5; lần đầu dùng một mô hình của Anthropic, bạn điền một mẫu đơn về mục đích sử dụng, chỉ một lần.
2. Dùng một profile AWS được phép `bedrock:InvokeModelWithResponseStream`: khóa tĩnh trong `~/.aws/credentials`, hoặc một profile lấy thông tin đăng nhập tạm thời (`credential_process`, một role, SSO; xem "Profile AWS" bên dưới).
3. Mở "AllInOneIME Settings": bạn có thể tìm nó trong Spotlight hoặc trong Applications, hoặc mở từ biểu tượng của bộ gõ trên thanh menu → "Settings…". Chọn profile, region và mô hình, rồi nhấp "Test Connection" (kiểm tra kết nối). Giao diện có các ngôn ngữ English, 简体中文 (tiếng Trung giản thể), 繁體中文 (tiếng Trung phồn thể), 日本語, 한국어, Deutsch, Français, Español và Português (Brasil). Mặc định ("Follow the system" – theo hệ thống – trong Settings → General → "Interface language") nó theo các ngôn ngữ ưu tiên của hệ thống (Cài đặt hệ thống → Cài đặt chung → Ngôn ngữ & Vùng): ngôn ngữ đầu tiên trong số đó mà ứng dụng có; một biến thể vùng cũng được tính theo ngôn ngữ của nó (Deutsch cho de-AT, Español cho es-MX, Français cho fr-CA); tiếng Trung phồn thể cho zh-Hant, zh-TW và zh-HK, các dạng tiếng Trung khác thì giản thể; tiếng Bồ Đào Nha (Brasil) cho cả tiếng Bồ Đào Nha của Bồ Đào Nha (ở đó nó dễ đọc hơn tiếng Anh); tiếng Anh khi không có ngôn ngữ nào khớp. Hoặc chọn một ngôn ngữ ở đó, mỗi ngôn ngữ được ghi bằng chính ngôn ngữ ấy. Cửa sổ cài đặt, các gợi ý trong bảng ứng viên và menu nhập đều theo cài đặt này. Phần cài đặt mở ở trang Assistant: đổi cài đặt bằng cách mô tả, và kiểm tra sự cố với nút Fix cho từng sự cố (xem [Settings → Assistant](#settings--assistant-mới)).

<img src="../en/settings.png" width="420" alt="Cửa sổ cài đặt">

#### Profile AWS

Mọi profile mà AWS CLI có thể dùng mà không cần hỏi bạn gì đều hoạt động, từ `~/.aws/config` và `~/.aws/credentials` (hoặc các tệp mà `AWS_CONFIG_FILE` và `AWS_SHARED_CREDENTIALS_FILE` trong shell của bạn chỉ định). Trong một profile, nguồn đầu tiên mà nó có sẽ được dùng, theo thứ tự của AWS CLI (một profile có cả `role_arn` lẫn khóa được coi là role):

| Loại | Trong profile | Làm mới |
| --- | --- | --- |
| Role | `role_arn` kèm `source_profile` (ở đây loại nào cũng được, kể cả nối chuỗi; một profile trỏ tới chính nó dùng khóa của chính nó) hoặc `credential_source = Environment`; `role_session_name`, `external_id`, `duration_seconds` | lấy lại bằng STS `AssumeRole` (trong `region` của profile, nếu không thì us-east-1) 5 phút trước khi hết hạn |
| SSO | `sso_account_id`, `sso_role_name` kèm `sso_session` và mục `[sso-session …]` của nó (hoặc kiểu cũ `sso_start_url`, `sso_region`) | lấy lại bằng phiên đăng nhập đã lưu đệm 5 phút trước khi hết hạn |
| Khóa tĩnh | `aws_access_key_id`, `aws_secret_access_key` (và `aws_session_token`) trong `~/.aws/credentials` | đọc lại ở mỗi yêu cầu |
| `credential_process` | `credential_process = /usr/local/bin/my-creds --profile dev` (tách như một lệnh shell, chạy không qua shell, với PATH của login shell, trong thư mục nhà của bạn, tối đa 60 giây) | chạy lại 5 phút trước `Expiration` của nó; nếu không có, khi AWS từ chối thông tin đăng nhập |
| Khóa tĩnh | các khóa tương tự trong `~/.aws/config` | đọc lại ở mỗi yêu cầu |

Với profile "default" (hoặc khi chưa chọn profile nào), các khóa trong shell của bạn được ưu tiên, giống cách AWS CLI dùng chúng: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` và `AWS_SESSION_TOKEN`. Một profile bạn chỉ định tên không bao giờ bị trộn với chúng. `AWS_REGION` (hoặc `AWS_DEFAULT_REGION`) trong shell được ưu tiên hơn `region` của profile, như trong AWS CLI; ô Region trong Settings được ưu tiên hơn cả hai.

- **Tự động:** thông tin đăng nhập có hạn được giữ trong bộ nhớ (không bao giờ ghi xuống đĩa) và được lấy lại 5 phút trước khi hết hạn; khi còn chưa đến 10 phút, yêu cầu vẫn dùng chúng và lấy cái mới ở chế độ nền, nên việc gõ không phải chờ. Các yêu cầu cùng lúc chỉ chờ một lần lấy. Khi Bedrock trả lời rằng thông tin đăng nhập đã hết hạn (`ExpiredTokenException` …), chúng được lấy lại và yêu cầu được gửi lại, một lần.
- **SSO:** AllInOneIME dùng phiên đăng nhập mà AWS CLI lưu trong `~/.aws/sso/cache` (chỉ đọc) và không thể đăng nhập thay bạn, vì việc đó cần trình duyệt. Khi phiên đăng nhập hết hạn, bảng ứng viên hiện "SSO sign-in expired: run aws sso login --profile X" (phiên đăng nhập SSO đã hết hạn: hãy chạy aws sso login --profile X): chạy lệnh đó trong Terminal (Settings có Copy Command và Open in Terminal; Settings → Assistant đưa ra lệnh để sao chép), và AllInOneIME sẽ tự nhận phiên đăng nhập mới.
- **Không hỗ trợ:** `mfa_serial` (bộ gõ không thể hỏi bạn mã MFA: hãy dùng `credential_process` hoặc SSO, hoặc để CLI lưu đệm thông tin đăng nhập), `credential_source = Ec2InstanceMetadata` hoặc `EcsContainer` (không có trên Mac), và web identity.
- **Giới hạn đã biết:** chỉ PATH và các biến về tệp AWS (`AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`) được lấy từ login shell, cả với `credential_process` (không lấy phần còn lại của môi trường). AllInOneIME không gia hạn token của `sso_session` (không dùng refresh token của CLI: bộ nhớ đệm SSO chỉ được đọc), nên khi token đã lưu đệm hết hạn, hãy chạy `aws sso login` (AWS CLI cũng gia hạn nó mỗi khi bạn dùng).
- **Settings → AI Provider** liệt kê mọi profile kèm loại của nó ("dev — Role via base") và cho biết, với profile đang chọn, khi nào thông tin đăng nhập hết hạn ("Role via base: credentials expire at 15:30", "SSO (signed in until 18:00)") hoặc cần làm gì. Test Connection lấy thông tin đăng nhập mới qua toàn bộ chuỗi; Settings → Assistant báo cáo điều tương tự.
- Chương trình chỉ chạy và AWS chỉ được hỏi thông tin đăng nhập (`sts.<region>.amazonaws.com`, `portal.sso.<region>.amazonaws.com`) khi một yêu cầu hoặc Test Connection cần đến: không bao giờ để liệt kê profile, không bao giờ cho Settings → Assistant.

### Các nhà cung cấp AI khác: Claude API, Gemini, dịch vụ tương thích OpenAI

Bạn không cần AWS: chọn một nhà cung cấp ở mục "AI Provider" trong phần cài đặt, dán API key, nhấp "Save", rồi "Test Connection".

| Nhà cung cấp | Mô hình mặc định | API key |
|---|---|---|
| Claude API | `claude-haiku-5-5` (nhanh nhất, rẻ nhất; Sonnet 5.5 và Opus 5.5 cẩn thận hơn nhưng chậm hơn và đắt hơn) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| Tương thích OpenAI | `gpt-6-luna` của OpenAI (hoặc `gpt-5.4-mini`); "Common Services…" có DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter và Ollama trên máy Mac này: chọn một dịch vụ sẽ điền sẵn base URL của nó, sau đó nhập mô hình của nó | Khóa của dịch vụ; đặt Base URL là địa chỉ của nó, ví dụ `https://api.deepseek.com/v1`, hoặc `http://localhost:11434/v1` cho Ollama trên máy Mac này |

- API key được lưu trong keychain đăng nhập, không bao giờ trong tệp cấu hình; nếu bạn bật "API keys and passwords" trong Sync through iCloud thì thay vào đó là trong Chuỗi khóa iCloud, nơi `allinoneime-cli` và các phiên bản trước 0.6.5 không thấy chúng. Khi không có khóa ở đó, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (hoặc `GOOGLE_API_KEY`) và `OPENAI_API_KEY` từ shell của bạn sẽ được dùng.
- Dòng API key cho biết đã có khóa hay chưa: "✓ Saved · ends in a1b2" (đã lưu · kết thúc bằng a1b2: 4 ký tự cuối, được lưu cùng khóa để không phải đọc chính khóa khi hiển thị) kèm Replace… (thay thế) và Remove… (gỡ bỏ), "✓ From $OPENAI_API_KEY" (từ $OPENAI_API_KEY) với khóa lấy từ shell, hoặc "No API key yet" (chưa có API key) kèm ô để dán khóa.
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
- Nó nhận ra các giá trị có định dạng; nó không nhận ra tên người hay địa chỉ, nên hãy thêm chúng làm từ của riêng bạn. `@agent`, các plugin lấy dữ liệu từ một trang web (`@stock`) hoặc mở một trang (`@x`) và tiện ích mở rộng dạng script gửi văn bản đúng như đã gõ. Xem thêm ở phần Quyền riêng tư.
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
| `commandTrigger` | Ký hiệu mở đầu lệnh: một trong `"#"`, `"%"`, `"&"`, `"*"`, `"+"`, `"@"`, `"\|"`, `"~"`; giá trị khác được coi là `"@"` | `"@"` |
| `uiLanguage` | Ngôn ngữ giao diện (cửa sổ cài đặt, gợi ý trong bảng ứng viên, menu): `"zh"` (tiếng Trung giản thể), `"en"`, hoặc mã của một ngôn ngữ khác mà ứng dụng có: `"zh-Hant"`, `"ja"`, `"ko"`, `"de"`, `"fr"`, `"es"`, `"pt-BR"` | `null` (theo hệ thống) |
| `rewriteStyles` | Kiểu viết lại: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, ví dụ `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | Tệp danh sách jargon của riêng bạn | `null` (tức là `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | Biểu tượng trên thanh menu và bảng thả xuống của nó | `true` |
| `candidateLayout` | Ứng viên pinyin và tiếng Hindi: `"vertical"` (xếp dọc) hoặc `"horizontal"` (nằm ngang; ← → để chọn, ↑↓ để lật trang) | `"horizontal"` |
| `fuzzyPinyin` | Các cặp pinyin mờ: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | Lệnh @ xử lý văn bản đang chọn trong ô (xem Trên văn bản đang chọn) | `true` |
| `checkForUpdates` | Tìm phiên bản mới mỗi ngày một lần, chạy nền; không có gì được cài cho đến khi bạn nhấp | `true` |
| `agent` | Coding agent mà `@agent` giao văn bản tới (Settings → Agent): `claude` (Claude Code), `gemini` (Gemini CLI), `kiro` (Kiro CLI) hoặc `custom` | `claude` |
| `agentCommand` | Lệnh của agent tùy chỉnh, những gì bạn gõ được thêm vào làm đối số cuối, ví dụ `["muse", "--"]` | `[]` |
| `agentPageContext` | `@agent` trong Google Chrome mang theo trang đang mở (ô đang gõ, biểu mẫu hoặc phần chứa nó, vùng chọn, văn bản đang hiện; không bao giờ có mật khẩu) | `true` |
| `claudeInBackground` | `@agent` với Claude Code chạy nền và báo cho bạn (các agent khác luôn mở trong Terminal) | `true` |
| `rememberQuestions` | Lưu 5 câu hỏi `@question` gần nhất và câu trả lời trên máy Mac này, liệt kê dưới `@question` (xem Câu hỏi gần đây) | `true` |
| `questionRounds` | Số lượt của một cuộc hội thoại `@question` trong bảng trước khi nó đề nghị tiếp tục ở nơi khác, 2–10 | `5` |
| `questionContinueIn` | Những nơi một cuộc hội thoại `@question` có thể tiếp tục, theo thứ tự, nơi đầu tiên là mặc định: `agent` (agent mà `@agent` giao việc tới, thay cho mục riêng của agent đó), `claudeCode`, `geminiCLI`, `kiroCLI`, `customAgent` (các agent, mỗi agent chỉ khi đã cài), `claudeWeb`, `chatgpt`, `gemini`, `copy` | `agent`, các agent khác đã cài, Claude, ChatGPT, sao chép |
| `appProfiles` | Cài đặt của một ứng dụng, theo bundle ID, mục nào cũng tùy chọn: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI`, `translateAlways` (xem Cài đặt theo ứng dụng) | `{}` |
| `notes` | Nơi `@note` lưu (Settings → Plugins → Notes): `{"destination": "folder", "folder": "~/Vault/Inbox"}`, hoặc `"notion"` với trang hoặc cơ sở dữ liệu mà Test đã tìm thấy; không bao giờ được đồng bộ qua iCloud Drive (token nằm trong keychain, và chỉ đi qua Chuỗi khóa iCloud khi bật "API keys and passwords") | `destination: "notes"` |
| `redaction` | Ẩn thông tin nhạy cảm khỏi AI (xem Quyền riêng tư): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`; mỗi bộ phát hiện (`emails`, `phones`, `cards`, `keys`, `ips`) đều bật trừ khi đặt thành `false` | `enabled: false` |

## Quyền riêng tư

- Việc gõ (tiếng Anh và pinyin) và các phép tính của plugin `@calculator` hoàn toàn diễn ra cục bộ. Chỉ khi bạn nhấn phím thực thi với `@improve`, `@translate` hoặc `@question`, câu đó mới được gửi đến nhà cung cấp AI bạn đã chọn (Bedrock của chính bạn, hoặc dịch vụ mà bạn đã thêm khóa). Khi đánh dấu "Jargon" và đã đặt danh sách jargon, danh sách được gửi kèm theo. Tinh chỉnh kết quả (một chỉ dẫn gõ sau kết quả, rồi ⇧⏎) gửi lại cùng yêu cầu kèm các kết quả đang hiện và chỉ dẫn của bạn; một câu hỏi tiếp theo (⇧⏎) gửi kèm cuộc hội thoại cho đến lúc đó.
- Settings → Assistant chỉ gửi văn bản cho mô hình khi bạn nhấn Preview, hoặc Check kèm một câu hỏi: tới Apple Intelligence trên máy Mac này mỗi khi có (không gì rời khỏi máy Mac), nếu không thì tới nhà cung cấp của bạn. Một yêu cầu gửi câu của bạn (khóa gõ trong đó bị bỏ ra trước) cùng giá trị hiện tại của các cài đặt nó được đổi: không bao giờ gửi khóa, cũng không gửi các từ bạn giấu khỏi AI (chỉ số lượng), và tên các AWS profile chỉ khi câu nói về AWS hoặc Bedrock. Một câu hỏi được gửi cùng kết quả kiểm tra đã che: không có đường dẫn ngoài `~`, không có khóa, các dòng nhật ký thành cụm từ cố định. Việc ẩn thông tin nhạy cảm áp dụng cho cả hai. Riêng việc kiểm tra không gửi gì; Check gửi thêm yêu cầu Test Connection, và chỉ khi nhà cung cấp có khóa hoặc thông tin đăng nhập để thử.
- Tiếp tục một cuộc hội thoại `@question` ở nơi khác (⌘1 … sau lượt cuối, hoặc ⌘⏎) sẽ gửi nó, kèm những gì bạn đã gõ, đến dịch vụ bạn chọn: một coding agent trên máy Mac này (Claude Code, Gemini CLI, Kiro CLI hoặc của riêng bạn, mỗi agent với tài khoản và dịch vụ riêng), claude.ai, chatgpt.com hoặc gemini.google.com, qua địa chỉ web hoặc qua clipboard. Nó được gửi đúng như bạn đã thấy: các giá trị được ẩn khỏi yêu cầu gửi AI (xem bên dưới) vẫn nằm nguyên trong đó, vì chính bạn chọn gửi nó tới đó. Không có gì được gửi đi đâu cho đến khi bạn chọn một nơi; "Copy the conversation" chỉ đưa nó vào clipboard.
- Với AllInOneIME Cloud, câu đi qua máy chủ của nhà phát triển đến một nhà cung cấp mô hình (hiện qua OpenRouter): máy chủ chỉ lưu số đếm, không bao giờ lưu văn bản. Việc đăng nhập chỉ lưu địa chỉ email của bạn.
- Ẩn thông tin nhạy cảm (Settings → AI Provider → Privacy, mặc định tắt): trước khi bất kỳ yêu cầu nào được gửi đi (`@improve`, `@translate`, `@question`, các lệnh chỉ dẫn và plugin chỉ dẫn của bạn, với mọi nhà cung cấp kể cả AllInOneIME Cloud), địa chỉ email, số điện thoại, số thẻ thanh toán (kiểm tra Luhn), API key và token (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…` và chuỗi ngẫu nhiên dài), địa chỉ IP và từ của riêng bạn (một mật danh, một cái tên) được thay ngay trên máy Mac bằng các ký hiệu giữ chỗ như `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]`; cùng một giá trị nhận cùng một ký hiệu. Kết quả của mô hình được trả lại giá trị thật trước khi hiện hoặc chèn, và bảng hiện "2 items hidden from the AI". Kết quả có ký hiệu giữ chỗ bị mô hình sửa đến mức không nhận ra được hiện đúng như đã viết, kèm dấu "⚠ placeholder changed". Các mục trong danh sách Jargon chứa giá trị bị ẩn sẽ không được gửi. Mỗi loại đều có thể tắt. Các dạng toàn độ rộng (`zhang＠example.com`, `１３８…`) cũng được tìm ra, và một giá trị hay cụm từ có thể bị ngắt bởi xuống dòng. Nó nhận ra các giá trị có định dạng như email, số và khóa; nó không nhận ra tên người hay địa chỉ (hãy thêm chúng làm từ của riêng bạn), cũng như các chữ cái trông giống nhau từ bảng chữ cái khác. Áp dụng cho các yêu cầu gửi đến dịch vụ AI của bạn; `@agent` (cùng trang Chrome mà nó mang theo), các plugin lấy dữ liệu từ một trang web (`@stock`) hoặc mở một trang (`@x`) và tiện ích mở rộng dạng script gửi văn bản đúng như đã gõ. Trong tệp cấu hình: `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- Giọng nói chỉ được ghi âm khi bạn giữ ⌥ bên phải và được nhận dạng ngay trên máy Mac; văn bản nhận dạng được chỉ được gửi đi trong các lệnh nêu trên, khi bạn nhấn phím thực thi.
- Bộ gõ đọc văn bản trong bộ nhớ tạm, một lần, chỉ khi bạn nhấn ⌃V hoặc ⌘V trong một lệnh; nội dung mà trình quản lý mật khẩu đánh dấu là ẩn sẽ không được đọc. Văn bản được hiển thị trong lệnh trước và, một lần nữa, chỉ được gửi đi khi bạn nhấn phím thực thi. Các phiên bản macOS gần đây hỏi AllInOneIME có được đọc bộ nhớ tạm không: hãy cho phép. Để không bị hỏi mỗi lần, hãy đặt quyền dán của AllInOneIME thành luôn cho phép trong System Settings → Privacy & Security.
- Trong ô mật khẩu, macOS chuyển sang bàn phím riêng của nó (U.S. hoặc ABC) và chuyển lại khi bạn rời ô đó. Bất cứ khi nào ứng dụng bạn đang gõ giữ chế độ nhập liệu bảo mật, AllInOneIME không soạn văn bản và không thể ghi âm: các phím được đưa vào đúng như đã gõ. Và trong khi hệ thống ở chế độ nhập liệu bảo mật (ô mật khẩu, Secure Keyboard Entry của Terminal, v.v.), không có gì được gửi đến AI.
- `@note` và `@reminder` không đi đến AI: AllInOneIME chỉ chuyển văn bản cho Notes và Reminders trên máy Mac này, và cũng đọc thời gian của lời nhắc ngay trên máy Mac (việc các ứng dụng đó có đồng bộ sang các thiết bị khác của bạn hay không tùy thuộc vào tài khoản của chúng, chẳng hạn iCloud). Vì vậy chúng cũng hoạt động khi đang ở chế độ nhập liệu bảo mật. `@note` vào một thư mục sẽ ghi một tệp trên máy Mac này (tệp được đồng bộ nếu thư mục đó được đồng bộ, như một thư mục iCloud Drive hay Obsidian Sync). `@note` vào Notion sẽ gửi ghi chú đến Notion (api.notion.com, bằng token của integration, được lưu trong keychain), và chỉ vào lúc đó: không gửi khi đang ở chế độ nhập liệu bảo mật.
- `@reportissue` (và "Report an Issue…") tự nó không gửi gì: nó mở trang tạo issue mới của GitHub trong trình duyệt với tiêu đề bạn đã gõ cùng các phiên bản, ngôn ngữ, loại nhà cung cấp và số lượng nêu ở trên, hiện trước trong bảng ứng viên. Không có gì đến GitHub trừ khi bạn nhấp Submit ở đó.
- `@open` chỉ tìm trên máy Mac này. Nó ghi nhớ những gì bạn đã mở bằng nó (200 mục gần nhất), trong phần tùy chọn riêng của bộ gõ (không phải trong config.json), để liệt kê chúng trước.
- Để phục vụ "Add App…" trong Settings → Apps, bộ gõ lưu bundle ID của 12 ứng dụng gần nhất bạn đã gõ, trong tùy chọn riêng của nó; không lưu gì khác về chúng.
- `@question` ghi nhớ 5 câu hỏi gần nhất của bạn cùng câu trả lời và thời điểm hỏi, chỉ trên máy Mac này (trừ khi bạn chọn đồng bộ chúng qua iCloud, xem ở trên), trong `~/Library/Application Support/AllInOneIME/recent-questions.json` (chỉ tài khoản người dùng của bạn đọc được), để liệt kê chúng dưới `@question`; câu trả lời đã lưu được hiện từ đó mà không cần lên mạng. Không lưu gì khi đang ở chế độ nhập liệu bảo mật, và câu hỏi về văn bản đang chọn hoàn toàn không được lưu (câu trả lời của chúng nói về vùng chọn, vốn sẽ bị ghi xuống đĩa). Tắt "Remember recent questions" trong Settings → General cũng xóa chúng; tắt bằng Settings → Assistant (`rememberQuestions` trong tệp cấu hình) thì giữ lại chúng, để có thể hoàn tác chính xác. "Clear" xóa chúng.
- Để liệt kê ghi chú của bạn, bảng trên thanh menu lưu id (id của ghi chú trong Notes, đường dẫn của tệp, hoặc địa chỉ của trang Notion) và dòng đầu tiên (tối đa 80 ký tự) của 30 ghi chú gần nhất được lưu bằng `@note`, trong phần tùy chọn riêng của bộ gõ, kể cả khi bảng đã tắt. Mở bảng không bao giờ gửi yêu cầu nào đến Notion.
- `@py` và `@js` chỉ chạy khi bạn nhấn phím thực thi, và chỉ chạy mã do chính bạn gõ hoặc dán: câu trả lời của AI và đầu ra của các lệnh khác không bao giờ được chạy như mã. `@py` dùng `python3` của máy Mac, vốn có thể đọc, ghi tệp và truy cập mạng như khi chạy trong Terminal; `@js` chạy trong một tiến trình riêng không thể đọc tệp, truy cập mạng hay chạy chương trình khác. Cả hai đều không chạy khi đang ở chế độ nhập liệu bảo mật.
- Kiểm tra cập nhật: mỗi ngày một lần (trừ khi tắt "Check for updates automatically"), AllInOneIME tải https://allinoneime.com/update.json và chữ ký của nó; yêu cầu không mang định danh nào và không có gì bạn đã gõ. Bản cập nhật chỉ được tải về, từ bản phát hành trên GitHub, khi bạn nhấp Update.
- Nguồn tiện ích mở rộng: git chạy trên máy Mac của bạn, dưới tài khoản của bạn, chỉ cho các nguồn bạn đã thêm: một lần fetch mỗi ngày cho các nguồn tự kiểm tra (không có với nguồn bị ghim), và khi bạn nhấp Check Now, Update hoặc Re-clone. Nó chỉ liên lạc với máy chủ của kho, đăng nhập bằng thiết lập git và SSH của chính bạn; không có gì bạn gõ đi kèm theo.
- Đồng bộ qua iCloud (mặc định tắt): chỉ vào iCloud Drive của chính bạn, `~/Library/Mobile Documents/com~apple~CloudDocs/AllInOneIME/`, nơi Apple đồng bộ sang các máy Mac khác của bạn; không có gì đến máy chủ của nhà phát triển. Những gì được đưa lên đó: `settings.json` (các cài đặt được đồng bộ, mỗi cài đặt kèm thời điểm thay đổi và một id ngẫu nhiên cho mỗi máy Mac; các lệnh tùy chỉnh của bạn, kể cả những lệnh chạy chương trình, vốn vẫn chỉ chạy khi bạn chọn chúng), `jargon.txt` (danh sách jargon của bạn), `rime/` (bản chụp nhanh của từng máy Mac về những gì pinyin đã học, ngoài ra không có gì khác của thư mục Rime: cụm từ tùy chỉnh và cài đặt Rime của bạn vẫn ở lại trên máy Mac), và chỉ khi bạn bật chúng, các từ bạn ẩn khỏi AI (trong `settings.json`) và `questions.json` (câu hỏi gần đây và câu trả lời, chỉ tài khoản người dùng của bạn đọc được). Tắt hai mục đó vẫn để chúng lại trong iCloud cho đến khi bạn gỡ chúng ("Remove from iCloud…" dưới mỗi công tắc). Không bao giờ được đưa lên: API key, token hay mật khẩu, nguồn tiện ích mở rộng, thư mục tiện ích mở rộng và plugin, danh sách ứng dụng không gõ sai, các ứng dụng gần đây, trạng thái cửa sổ, các công tắc đồng bộ. iCloud Drive chỉ được mã hóa đầu cuối khi bật Bảo vệ dữ liệu nâng cao. Bản ghi riêng của máy Mac này về những gì nó đã đồng bộ nằm trong `~/Library/Application Support/AllInOneIME/iCloudSync/state.json`.
- Nhật ký không ghi lại những gì bạn gõ. Với mọi bộ gõ của bên thứ ba, macOS đều cảnh báo "The developer can access anything you type with this input source" (nhà phát triển có thể truy cập mọi thứ bạn gõ bằng nguồn nhập này); đó là cảnh báo chung của hệ thống.

## Phát triển

```sh
make test         # unit tests, plus tests that run the real Rime engine (and make strings-check)
make strings      # adds new interface text to Resources/Localizable.xcstrings, marks what's unused stale
make pack         # the Chinese language pack: build/packs/zh-pinyin-<version>.tar.xz, its sha256, its packs.json entry
make packs        # all the language packs: Chinese, and Korean and Hindi from Core/LanguagePacks/ (ko-hangul, hi-phonetic)
make selftest     # drives the input method through a simulated text field: real Bedrock calls, plus on-device recognition tested with synthesized speech
make realtest     # types into a real app's text field (needs the screen unlocked; takes over the foreground for about 1 minute)
make screenshots  # regenerates the screenshots in docs/
make cli && .build/release/allinoneime-cli --styles concise,jargon "this is a blocker bug your team need fix it asap"   # try polishing and rewrites in the terminal
make icon         # regenerates the app icon and the menu bar icon from Resources/AppIcon.png
make dmg          # the release installer, build/AllInOneIME-<version>.dmg (universal; needs the Developer ID certificate it's signed with and DIST_PROFILE, the provisioning profile; optionally notarized), and the in-app update, build/AllInOneIME-<version>-update.zip
make app PROFILE=<profile> SIGN_IDENTITY=<a certificate it lists>   # a build with the keychain entitlements: it can sync keys through iCloud Keychain
make update-test  # the in-app updater end to end: a temporary install, a test server on 127.0.0.1, a test key (never the installed app)
```

`make selftest` và `make realtest` không phụ thuộc vào cài đặt của bạn. Bài tự kiểm tra dùng một tệp cấu hình riêng (Amazon Bedrock với profile AWS và region lấy từ cấu hình của bạn, mọi thứ khác là mặc định); bài kiểm tra trên ứng dụng thật đặt nhà cung cấp thành Bedrock trong lúc chạy rồi trả lại nhà cung cấp của bạn. Những gì chúng không kiểm tra được vào lúc đó sẽ được bỏ qua chứ không tính là thất bại: các bước kiểm tra Bedrock trực tiếp khi không có thông tin đăng nhập cho profile đó, và mọi thứ cần gõ khi chế độ nhập liệu bảo mật đang bật (màn hình bị khóa, một ô mật khẩu). Dòng cuối đếm số bước kiểm tra đạt, thất bại và bị bỏ qua; chỉ các thất bại mới làm lần chạy thất bại, và một lần chạy có mục bị bỏ qua sẽ kết thúc bằng INCOMPLETE, hoặc SKIPPED khi không có gì cần gõ được chạy (BLOCKED: bài kiểm tra trên ứng dụng thật bắt đầu khi màn hình bị khóa), không bao giờ là PASSED.

Văn bản giao diện được viết dưới dạng `tr("中文", "English")`: tiếng Trung giản thể và tiếng Anh lấy từ mã, các ngôn ngữ khác lấy từ String Catalog, `Core/Resources/Localizable.xcstrings` cho văn bản của phần lõi và `Resources/Localizable.xcstrings` cho văn bản riêng của ứng dụng (được Makefile gộp và biên dịch vào từng ứng dụng bằng `xcstringstool` của Xcode), với khóa là văn bản tiếng Anh, mỗi chỗ nội suy là một `%@`. Sau khi thêm hoặc sửa văn bản, hãy chạy `make strings` (`make test` sẽ thất bại cho đến khi bạn chạy nó; văn bản của các bài tự kiểm tra, trong `*SelfTest.swift`, không dành cho người dịch). Khi cùng một văn bản tiếng Anh mang hai nghĩa (`make strings` báo các trường hợp đó, và `make strings-check` thất bại vì chúng), hãy cho một trong hai một khóa riêng, là một tên ngắn có dấu chấm cho biết nó được dùng ở đâu hoặc thế nào: `tr("删除", "Remove", key: "remove.delete")`; văn bản tiếng Anh của nó là giá trị tiếng Anh của khóa đó trong catalog. Thêm một ngôn ngữ là thêm cột của nó vào catalog: các bản dịch đã được duyệt, mỗi ngôn ngữ một tệp JSON (`"core\t<key>"` hoặc `"app\t<key>"` → bản dịch), được đưa vào bằng `Scripts/import-translations.py <folder>`; công cụ này không bao giờ đụng đến tiếng Anh và từ chối bản dịch có ký hiệu giữ chỗ không khớp với khóa của nó. Các văn bản riêng của phần lõi nhận mã ngôn ngữ giao diện và tra cứu theo cùng cách (`InterfaceText.lookup`, do từng ứng dụng thiết lập: trên macOS là các bundle `.lproj` của nó; ở nơi khác thì `StringCatalog` đọc các bảng của catalog).

Cấu trúc mã: thư mục gốc là ứng dụng macOS; `Core/` là phần lõi mà mọi nền tảng dùng chung, một Swift package riêng (tự biên dịch và chạy kiểm thử độc lập, trên macOS, Linux và Windows); `Windows/` là bước khởi đầu của ứng dụng Windows.

- `Core/Sources/AllInOneIMECore`: client Bedrock, SigV4, các prompt, máy trạng thái nhập hai cấp (bao gồm lệnh @ và cử chỉ giọng nói); không phụ thuộc AppKit
- `Core/Sources/AllInOneIMEText`: văn bản giao diện và ngôn ngữ của nó (`UIString`, `InterfaceText`, `InterfaceLanguage`, và `StringCatalog`, đọc catalog ở những nơi không có bundle `.lproj`); mọi liên kết mở các trang cài đặt (`AllInOneIMECore` re-export nó)
- `Core/Sources/AllInOneIMEQuickJS`: QuickJS-ng (mã nguồn C của nó nằm trong `Core/Sources/CQuickJS`), chạy JavaScript của plugin và `@js` ở những nơi không có JavaScriptCore (Windows, Linux, Android)
- `Core/Sources/AllInOneIMERime`: lớp bọc librime
- `Core/Sources/AllInOneIMECLI`: dòng lệnh, `allinoneime-cli` (`make cli`), được chạy bởi `main` riêng của từng nền tảng
- `Sources/AllInOneIMEMac`: những gì chỉ máy Mac có (bố cục phím, ký mã, Spotlight, AppleScript, bước cài đặt của trình cập nhật), và `Platform.mac`
- `Sources/AllInOneIME`: bộ gõ InputMethodKit, bảng ứng viên, cửa sổ cài đặt, nhận dạng giọng nói
- `Sources/AllInOneIMESettings`: trình khởi chạy "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: "Install AllInOneIME" trên ảnh đĩa: cài đặt, cập nhật và gỡ cài đặt

Các gói ngôn ngữ có thư viện riêng, tách biệt với plugin: kho mã [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), được phục vụ tại https://languages.allinoneime.com/, ký bằng khóa riêng. `make pack` tạo tệp nén; tệp này được phát hành dưới dạng release asset ở đó (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), và `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` ghi `packs.json` ở đó và ký nó thành `packs.json.sig` bằng khóa của các gói ngôn ngữ lấy từ keychain (`allinoneime-languages-signing`). Ứng dụng đọc https://languages.allinoneime.com/packs.json, kiểm tra chữ ký, rồi kiểm tra dung lượng và SHA-256 của tệp nén. Để thử một gói từ máy chủ cục bộ: `--test-key` ký bằng một khóa thử nghiệm, và `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Phát hành một phiên bản (trình cập nhật trong ứng dụng đọc https://allinoneime.com/update.json, được ký bằng khóa riêng dành cho các bản phát hành):

1. Tăng số phiên bản (`AppVersion.swift` và ba tệp Info.plist; `AppVersionTests` kiểm tra chúng khớp nhau) và cập nhật nhật ký thay đổi.
2. `make dmg NOTARY_PROFILE=<profile>`: `build/AllInOneIME-<version>.dmg` cùng `.sha256` của nó, và `build/AllInOneIME-<version>-update.zip` (cả hai ứng dụng, như trình cài đặt trong ảnh đĩa mang theo). Các ứng dụng và ảnh đĩa được ký bằng chứng chỉ Developer ID Application trong keychain, và ảnh đĩa được công chứng bằng hồ sơ keychain `xcrun notarytool` đó rồi được staple. Bộ gõ mang theo Developer ID provisioning profile (`Resources/Signing/AllInOneIME-DeveloperID.provisionprofile`, `DIST_PROFILE`), thứ cấp cho nó các entitlement keychain; quá trình dựng sẽ dừng nếu profile không liệt kê chứng chỉ ký, không áp dụng cho mọi thiết bị (provision all devices) hoặc còn chưa đến 30 ngày hiệu lực (`Scripts/profile-entitlements.sh`), hoặc nếu chữ ký thiếu các entitlement keychain, và nó chạy thử bộ gõ đã ký một lần (macOS sẽ buộc dừng bộ gõ có profile không khớp). Một `DIST_PROFILE` rỗng cũng làm nó dừng: một bản phát hành thiếu các entitlement đó sẽ không còn thấy bất kỳ khóa nào đã được chuyển vào Chuỗi khóa iCloud. Profile chỉ liệt kê hai chứng chỉ Developer ID G1: trước khi ký bằng một chứng chỉ khác (G2), hãy tạo trong developer portal một profile mới có liệt kê chứng chỉ đó (làm thủ công: việc ký của App ID không giao cho Xcode), rồi commit nó.
3. Tải cả hai lên bản phát hành GitHub `v<version>` và công bố nó.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"` (mỗi cái một hai câu): ghi `site/public/update.json` (phiên bản, bản dựng và macOS tối thiểu đọc từ các ứng dụng, địa chỉ, kích thước và SHA-256 của tệp, địa chỉ ghi chú phát hành và phần tóm tắt) rồi ký nó thành `update.json.sig` bằng khóa trong keychain đăng nhập (`allinoneime-releases-signing`; macOS có thể hỏi cho phép truy cập). Commit cả hai.
5. Triển khai trang web (`cd site && npx wrangler@4 deploy`), chỉ khi các tệp của bản phát hành đã tải về được: các ứng dụng kiểm tra mỗi ngày một lần, và `AllInOneIME --check-update` cho thấy những gì chúng thấy.

Ứng dụng kiểm tra chữ ký của manifest bằng khóa công khai tích hợp sẵn trước khi đọc nó, không bao giờ cài phiên bản không mới hơn, chỉ tải qua https từ allinoneime.com hoặc các tệp phát hành GitHub của kho mã, và chỉ cài gói lưu trữ khi kích thước và SHA-256 khớp với manifest, bundle ID, phiên bản và chữ ký mã của cả hai ứng dụng đều hợp lệ và bộ gõ mới khởi động được. Sau đó bộ gõ giao việc cho chính tệp thực thi của nó làm trình trợ giúp (`--apply-update`), trình này chờ bộ gõ thoát, hoán đổi các ứng dụng như trình cài đặt làm (bản cũ được để sang bên, đặt lại nếu có gì thất bại) và đăng ký bản mới. Để thử với máy chủ cục bộ: `make update-test`, hoặc `--test-key` với `Scripts/build-update-manifest.swift` và `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`.

Bundle ID vẫn là `com.aipinyin.inputmethod.AIPinyin`: macOS dùng nó để ghi nhớ nguồn nhập đã thêm và quyền dùng micrô, nên thay đổi nó đồng nghĩa với việc phải thêm lại bộ gõ và cấp lại quyền.

## Giấy phép

Copyright © 2026 MicroZ LLC. Mã nguồn được công khai theo [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): bạn có thể dùng, đọc, sửa đổi và chia sẻ nó cho mọi mục đích, trừ một sản phẩm cạnh tranh. Mỗi phiên bản chuyển sang Apache-2.0 hai năm sau khi phát hành. Các phiên bản đến 0.6.1 được phát hành theo GPL-3.0 và vẫn có thể dùng theo giấy phép đó.

Các thành phần của bên thứ ba (librime và các plugin của nó theo BSD-3-Clause; các script Lua của rime-ice và gói ngôn ngữ tiếng Trung theo GPL-3.0) được liệt kê trong [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
