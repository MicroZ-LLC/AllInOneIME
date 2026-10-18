<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · [繁體中文](README_zh-TW.md) · [日本語](README_ja.md) · [한국어](README_ko.md) · [Français](README_fr.md) · [Deutsch](README_de.md) · [Español](README_es.md) · [Português (Brasil)](README_pt-BR.md) · [Italiano](README_it.md) · [Русский](README_ru.md) · [Tiếng Việt](README_vi.md) · [ไทย](README_th.md) · [Bahasa Indonesia](README_id.md) · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · **Türkçe**

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="AllInOneIME simgesi">

# AllInOneIME

### Mac'inizdeki her metin alanında yapay zekâ komutları.

Herhangi bir uygulamada `@improve`, `@translate` veya `@question` yazın, ⏎ tuşuna basın ve sonucu seçin.<br>
Sohbet penceresine kopyalamak yok, uygulama değiştirmek yok. Kendi yapay zekâ sağlayıcınız, kendi anahtarlarınız.

[![Sürüm](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#kurulum)
[![Apple tarafından notarize edildi](https://img.shields.io/badge/Apple-notarized-0a84ff?logo=apple&logoColor=white)](#kurulum)
[![Apple silicon ve Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#kurulum)
[![Lisans: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![İndirmeler](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[İndir](https://allinoneime.com/download)** · **[Web sitesi](https://allinoneime.com)** · **[Belgeler](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[Uzantılar](../extensions.md)**

[Nasıl kullanılır](#nasıl-kullanılır) · [Komutlar](#-komutları-beta) · [Kendi komutlarınız](#kendi-komutlarınız) · [Diller](#giriş-ve-çeviri) · [Ses](#sesle-giriş) · [Kurulum](#kurulum) · [Gizlilik](#gizlilik)

<br>

<img src="../en/demo.png" width="820" alt="@translate ve bir cümle, ardından ⏎: İspanyolca, Fransızca ve Almanca birer satır">

</div>

*Bu, İngilizce README'nin bir çevirisidir; ikisi arasında fark olduğunda İngilizce olan esas alınır.*

> [!NOTE]
> 0.6.3'ten itibaren AllInOneIME bir Developer ID ile imzalanıyor ve Apple tarafından onaylanıyor (notarize): artık "System Settings → Privacy & Security" (Sistem Ayarları → Gizlilik ve Güvenlik) bölümünden izin vermeniz gerekmez. Daha eski bir sürümden güncelledikten sonra macOS, AllInOneIME'nin anahtar zincirine kaydettiği her anahtar için giriş parolanızı bir kez sorar: parolayı girin ve "Always Allow" (Her Zaman İzin Ver) düğmesine tıklayın. AllInOneIME'yi yalnızca [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) veya [allinoneime.com](https://allinoneime.com) üzerinden indirin.

Her metin alanında yapay zekâ komutları sunan bir macOS giriş yöntemi. Bir cümleye `@` ile başlayın ve bitince ⏎ tuşuna basın: `@improve` yazdığınızı düzeltip cilalar ve birkaç yeniden yazım önerir, `@translate` seçtiğiniz dillere çevirir, `@question` bir soru sorar, `@agent` işi bir kodlama ajanına (Claude Code, Gemini CLI, Kiro CLI …) devreder, `@open` ise dosya ve uygulama bulur ya da bir web adresi açar. Sağ ⌥ tuşunu basılı tutup konuşabilirsiniz de. `@` olmadan tuşlarınız her zamanki gibi uygulamaya gider. Ayrıca Çince (pinyin, Rime ve rime-ice üzerine kurulu), Fransızca, Korece (Hangul) ve Hintçe (Latin harflerinden Devanagari) yazar ve kendi betiklerinizi @ komutları olarak çalıştırır.

![@improve ve özensiz bir cümle, ardından ⏎: cilalanmış sürümler ve yeniden yazımlar](../en/improve.png)

Daha fazla ayrıntı için (tüm komutlar ve ayarlar, kurulum sorunlarını giderme, gizlilik) [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki)'ye bakın. [Weijian Zhang](https://weijianz.com) tarafından MicroZ LLC'de geliştirildi.

## Nasıl kullanılır

`@` olmadan araya girmez: İngilizcede harfler doğrudan yazılır ve ⏎ Return'dür; hiçbir şey internete gitmez. Yeni bir kurulum İngilizce yazar; Çince (pinyin), Fransızca, Korece veya Hintçe de yazmak için dili ayarlardan ekleyin (bkz. [Giriş ve çeviri](#giriş-ve-çeviri)).

| Tuş | Ne yapar |
|---|---|
| Pinyin yazma, Boşluk / rakamlar | Çince modunda: her pinyin giriş yönteminde olduğu gibi sözcük seçer |
| `@` (cümlenin başında) | Komut listesini açar: son zamanlarda en çok kullanılanlar önce, bir seferde 5 tane, ↑↓, kaydırma tekerleği veya izleme dörtgeniyle kaydırılır; ya da birini bulmak için harf yazın (önce tamamen yazılmış ad, sonra bu harflerle başlayan adlar, sonra bunları içeren adlar). ⏎, Tab, Boşluk veya bir rakam seçer |
| ⏎ | Komutu çalıştırır. Pinyin henüz seçilmemiş olsa da çalışır: Boşluk'ta olduğu gibi önce o seçilir |
| Boşluk, ⏎ / rakamlar | Sonuçlar göründüğünde: vurgulananı / o numaralıyı ekler; 0 orijinal metindir. Bir devam metni yarım yazılmış olsa bile ⏎ ekler (yazılan atılır) |
| ⇧⏎ | Yapay zekâ sonuçlarından sonra bir devam metni yazıldıysa: onu gönderir (bir `@question` sohbetinin sonraki sorusu ya da bir iyileştirme). Bir komut yazılırken veya hiçbir şey yazılmamış yapay zekâ sonuçlarında: yazdığınızı `@command` dahil olduğu gibi ekler. Diğer sonuçlarda (`@open`, bir anımsatıcı …) ⏎ gibi vurgulanan satırı ekler |
| ⌘C | Vurgulanan sonucu kopyalar (`@open` için yolu); aday paneli açık kalır |
| ⌃V | Bir komutta (ör. `@improve ` sonrasında): pano metnini uygulamaya yapıştırmak yerine yazdığınızın sonuna ekler. Birden çok satır tek satır olur, bir seferde en fazla 2000 karakter (`@note` satır sonlarını korur ve 20000'e kadar alır). Her uygulamada çalışır; komut yokken tuş her zamanki gibi uygulamaya gider |
| ⌘V | ⌃V gibidir, ancak bazı uygulamalar ⌘V'yi kendileri işler (Ghostty, iTerm2 ve Terminal gibi terminaller ile Notes) ve her zamanki gibi uygulamaya yapıştırır; oralarda ⌃V kullanın |
| Esc, ⌫ | Düzenlemeye devam etmek için cümleye döner; sonuçlardan sonra noktalama işareti veya rakam yazmak cümleyi sürdürür. Bir iyileştirmeden sonra: ondan önceki sonuçlara döner |
| Yapay zekâ sonuçları göründüğünde harfler | Bir devam metni: `@question` sonrasında sonraki soru (bkz. [Sohbetler](#question-ile-sohbetler-yeni)), `@improve` veya bir talimat komutu sonrasında `shorter` gibi bir talimat (bkz. [Sonuçları iyileştirme](#sonuçları-iyileştirme-yeni)); ⇧⏎ onu gönderir. `@translate` sonrasında harfler cümleyi sürdürür ve ⏎ onu yeniden çevirir |
| ⌘⏎, ⌘1–⌘9 | Bir `@question` sohbetinde: sohbetin nerede sürdürülebileceğini gösterir (kurulu kodlama ajanları, önce `@agent`'ın işi devrettiği; Claude, ChatGPT, Gemini; ya da kopyalamak); ⌘1, ⌘2 … birini seçer |
| Bir satıra tıklama | Aday panelinde: satırı, rakamı seçecekmiş gibi seçer (bir sözcük, listedeki bir komut, bir sonuç, bir `@open` dosyası, bir alıcı, bir uzantının satırı); işaretçinin altındaki satır vurgulanır. Metin alanı odağı korur |
| Shift'e dokunma | Birden fazla giriş dili varsa: sıralarına göre bir sonrakine geçer (İngilizce → Çince → Fransızca → …, sonra yeniden ilkine) |
| Sağ ⌥'yi basılı tutma | Konuşun, bitirmek için bırakın. Yazdığınız dilde (İngilizce, Çince, Fransızca, Korece veya Hintçe). Bir komutta metin komutun arkasına gelir; aksi hâlde doğrudan eklenir |

## @ komutları (beta)

| Komut | Ne yapar |
|---|---|
| `@improve` | Cilalar: 1–3 cümlenin kendi dilinde üç sürümdür, 4 ve sonrası yeniden yazım stilleridir (ayarlardan eklenir ve sıralanır), 0 orijinal metindir. Çeviri yapmaz; "@improve also translates" (@improve çeviri de yapar) açıkken `@translate @improve` gibi çalışır |
| `@translate` | Eklediğiniz dillere çevirir (ayarlar → "Translate", sıralamak için sürükleyin), her dil için bir satır, tek dil varsa üç sürüm; cümlenin kendi dili atlanır. `@translate @improve` birlikte tek istekte hem çevirir hem yeniden yazar |
| `@question` | Bir soru sorar; yanıt adaylarda görünür, ⏎ veya Boşluk ekler, ⌘C kopyalar. Yazmaya devam edip ⇧⏎'ye basınca bir ek soru sorulur: panel en fazla 5 turluk bir sohbete dönüşür, ardından sohbeti Claude'da veya başka bir yapay zekâda sürdürmeyi önerir. Ardından hiçbir şey yazılmazsa son 5 sorunuzu, en yenisi önce olmak üzere listeler; yazmak listeyi daraltır (sorunun herhangi bir yerindeki sözcükler, büyük/küçük harf fark etmez, Çince de). Bir rakam, ↑↓ ve ardından ⏎ ya da bir tıklama, bir sorunun kayıtlı yanıtını hemen, çevrimdışı gösterir; her zamanki gibi eklenebilir veya kopyalanabilir; orada ⌘R, yeni bir yanıt almak için soruyu yeniden sorar. Eşleşme yoksa ya da hiçbir şey seçilmediyse ⏎ yazdığınızı sorar |
| `@agent` | İşi Mac'inizdeki bir kodlama ajanına devreder; ajan Settings → Agent içinden seçilir: Claude Code (varsayılan), Gemini CLI, Kiro CLI ya da kendi komutunuz (yazdığınız, son argüman olarak eklenir). Sayfa ayrıca her birinin kurulu olup olmadığını ve nasıl başladığını gösterir. Claude Code varsayılan olarak arka planda çalışır ve bitince bildirim gönderir (oturumu Terminal'de açıp sürdürmek için bildirime tıklayın) ya da `@tasks`'a bakın; Terminal'de açmak için oradaki Claude Code altında "Runs in the background and notifies me" (arka planda çalışır ve bana bildirir) seçeneğini kapatın. Diğer ajanlar Terminal'de açılır ve yazdığınız onların ilk mesajı olur. Her biri kendi oturumunu ve ayarlarını kullanır. Terminal'i ilk kez açtığında macOS, AllInOneIME'nin Terminal'i denetleyip denetleyemeyeceğini sorar: OK'e tıklayın. (0.6.4'ten önce adı `@claude` idi.) |
| `@tasks` | Arka plandaki Claude görevlerini (çalışıyor / bitti / sizi bekliyor) son yanıtlarıyla listeler; ⏎ birini Terminal'de açar, ⌘C yanıtı kopyalar |
| `@settings` | Ayarlar penceresini hemen açar (seçmek yeterli) |
| `@open` | Siz yazdıkça eşleşen dosyaları, klasörleri ve uygulamaları listeler (Spotlight). Boşlukla ayrılmış birden fazla anahtar sözcük kullanılabilir: her biri yolda, en az biri adda geçmelidir (standart bir klasörün adı, içindekiler için de geçerlidir: `downloads pdf` İndirilenler'deki PDF'leri bulur). Uygulamalar ve standart klasörler Çince adlarıyla da bulunur ve Çince arayüz onları bu şekilde gösterir. Önce `@open` ile açtıklarınız gelir, sonra uygulamalar ve bu klasörler, sonra son kullanılan veya değiştirilen dosyalar; adlar iki veya daha az dosya bulduğunda ve bu türden hiçbir uygulama ya da klasör bulmadığında, ana klasörünüzdeki dosyalar içeriklerine göre de aranır ve bu satırlar "content" olarak işaretlenir; başka hiçbir şey yoksa ⏎ ilkini açmak yerine onları seçmeniz için listeler. Bir web adresiyle (`github.com`, `localhost:3000`, `https://…`) ilk satır "open in the browser" (tarayıcıda aç) olur ve içerikler aranmaz; tam olarak bu adı taşıyan bir dosya (örneğin `MANIFEST.in`) önce gelir. `~/` veya `/` ile başlayan metin bir yoldur: Tab onu tamamlar ve klasörlerin içine girer; ⏎ açar, ⌘C yolu kopyalar |
| `@note` | Metni Notes (Notlar) uygulamasına, AllInOneIME adlı bir klasöre (yoksa oluşturulur) kaydeder; hiçbir şey eklenmez. Yapıştırılan metin satır sonlarını korur, en fazla 20000 karakter |
| `@reminder` | Reminders (Anımsatıcılar) uygulamasına, AllInOneIME adlı bir listeye bir anımsatıcı ekler. Zamanı metne yazın; Mac'te okunur ve bir satır neyin okunduğunu gösterir: ⏎ veya Boşluk ekler, Esc düzenlemeye döner. Saat verilirse o anda bir alarm olur; yalnızca tarih verilirse tüm gün sürer |
| `@py` | Bir satır Python çalıştırır (Mac'in `python3`'ü) ve sonucu ekler: kodun son ifadesinin değeri, ör. `@py 2**100`, `@py import math; math.sqrt(2)`, ya da bu yoksa yazdırdığı çıktı. `python3` yoksa sunulmaz (Xcode'un komut satırı araçlarında vardır) |
| `@js` | Bir satır JavaScript çalıştırır ve aynısını ekler: son ifadenin değeri veya `console.log`'un yazdırdığı, ör. `@js [1, 2, 3].map(x => x * 2)`. macOS'un yerleşik JavaScriptCore'unu kullanır, bu yüzden kurulacak bir şey yoktur; dosya okuyamaz, ağa erişemez ve başka programlar çalıştıramaz |
| `@reportissue` | Bir sorun bildirir: tarayıcınızda GitHub'ın yeni issue sayfasını açar; komuttan sonra yazdığınız başlık olur, doldurmanız için de "What happened / What you expected" (ne oldu / ne bekliyordunuz) bölümleri gelir. Uygulama ve macOS sürümlerini, Mac'inizin mimarisini, arayüz ve giriş dillerini, kurulu dil paketlerini, yapay zekâ sağlayıcısının türünü (ve herkese açık bir modelse modeli; değilse "custom"), eylem tuşunu ve kaç özel komut, eklenti ve uzantınız olduğunu ekler; asla adlarını, metninizi, yolları veya anahtarları eklemez. ⏎ (veya eylem tuşunuz) önce bunların hepsini aday panelinde gösterir; tekrar ⏎ ya da satıra bir tıklama sayfayı açar, orada okuyup Submit düğmesine tıklarsınız (kendi GitHub hesabınızla); Esc geri döner. Giriş menüsünde ("Report an Issue…") ve Settings → About içinde de bulunur |
| `@imessage` | Bir iMessage gönderir: bir ad, telefon numarası veya e-posta yazın (Çince bir ad pinyin'iyle de, tam olarak ya da baş harfleriyle) ve alıcıyı aday panelinden seçin (son zamanlarda mesajlaştıklarınız önce gelir; tam bir numara veya adres de olur), ardından mesajı yazın (içindeki `@stock AAPL` gibi komutlar önce çalışır). ⏎ panelde "Send to Alex (…): message" gösterir, ⏎ tekrar gönderir, Esc düzenlemeye döner; metin alanına hiçbir şey yazılmaz. İlk seferde macOS, AllInOneIME'nin Contacts'a (Kişiler) erişip Messages'ı (Mesajlar) denetleyip denetleyemeyeceğini sorar: ikisinde de OK'e tıklayın |

Örnek: `@q` ⏎, `what is quantum computing` yazın, ⏎. `@note books to read: The Three-Body Problem` ⏎ bir not kaydeder. `@reminder call Bob tomorrow at 3pm` ⏎, okunan zamanı kontrol edin, sonra eklemek için yeniden ⏎. Komut seçildikten sonra sağ ⌥'yi basılı tutup konuşabilirsiniz de. Çince modunda `@open` o an için İngilizce harflere geçer ve işiniz bitince Çinceye döner.

`@py` ve `@js` kodu İngilizce harflerle yazılır ve tam genişlikli noktalama işaretleri (Çince modundan) ASCII'ye dönüşür; kodu tek satıra, deyimler arasına `;` koyarak yazın. Ayrı bir süreçte çalışır, 10 saniye sonra ya da herhangi bir anda Esc ile durdurulur; hata olursa hatanın ilk satırı gösterilir, ör. `ZeroDivisionError: division by zero`. Birden çok satırlı çıktı yazdırıldığı gibi eklenir; terminalde tek satır olarak girer (terminal kendisine verilen her satırı çalıştırır). Bir düzenleyicinin içindeki terminal (VS Code, Cursor, JetBrains) düzenleyicinin kendisinden ayırt edilemez, bu yüzden orada her komutun birden çok satırlı çıktısı olduğu gibi girer. İkisi de başka bir komutun cümlesinin içinde çalışır: `@reply the answer is @py 2**100`; boşluk içeren kodu tırnak içine alın: `@question explain @py "sum(x * x for x in range(10))"`. Tersi geçerli değildir: `@py` ve `@js` kodu her zaman tam yazdığınız gibi çalışır ve içindeki `@commands` önceden çalıştırılmaz.

![@ yazmak komut listesini açar; @question ve bir soru, ardından yanıt için ⏎](../en/commands.png)

![@open siz yazdıkça uygulamaları bulur; / ile başlıyorsa bir yoldur: klasör listelenir, Tab tamamlar](../en/open.png)

`@` bir komutla devam etmediğinde, `@john`'da olduğu gibi, `@` her zamanki gibi eklenir; böylece sohbet uygulamalarında kişileri @ ile anmak çalışmaya devam eder. Bir harfin, rakamın, `.`, `_` veya `-` işaretinin hemen ardından yazıldığında, `bob@example.com` ya da `ssh user@host` örneklerindeki gibi, `@` yalnızca metindir: terminaller dahil hiçbir uygulamada liste açılmaz. Liste açıkken ← → ya da bir komut adında bulunamayacak bir tuş (`.`, `:`, `/`) listeyi kapatır ve yazdığınızı (`@`, `@im`) olduğu gibi bırakır; terminalde ← → bu durumda yalnızca listeyi kapatır. `@question`, `@improve` ve `@translate` yalnızca eylem tuşuna bastığınızda kendi Bedrock'unuza gönderir; `@open` yalnızca bu Mac'te arar; `@note` ve `@reminder` yalnızca bu Mac'teki Notes ve Reminders'a gider; `@agent` Mac'inizde kurulu ajanı (varsayılan olarak Claude Code'un `claude` komutu) ve onun kendi hesabını kullanır ve dosyaları değiştirmeden veya komut çalıştırmadan önce her zamanki gibi size sorar. Ajan kurulu değilse `@agent` sunulmaz. `@imessage` Contacts'u yalnızca bu Mac'te okur (adlar, telefon numaraları, e-postalar), asla yapay zekâdan geçmez ve mesajı Messages gönderir; Messages uygulaması yoksa sunulmaz.

### Seçili metin üzerinde (yeni)

Herhangi bir uygulamada metin seçin (Notlar'da bir cümle, Mail'de bir paragraf), `@improve`, `@translate`, `@question` veya metin alan başka bir komut yazın ve ⏎'ye basın: komut seçim üzerinde çalışır ve seçtiğiniz sonuç onun yerini alır. Siz yazarken seçim olduğu gibi, seçili kalır: komut aday panelinde yazılır; panelin ilk satırı yazdığınız, sonraki satır "On the selection: “…” (N characters)" (seçim üzerinde: N karakter) olur. Esc, ⇧⏎ veya başka bir yere tıklamak metni olduğu gibi bırakır; bu arada seçimi değiştirmek de öyle yapar ve komutu iptal eder. Komuttan sonra yazılan metin, seçimle ilgili olarak `@improve` ve `@translate` için bir talimat (`@translate ja`, `@improve more formal`), `@question` için ise sorudur (`@question what does this mean`). `@open`, `@agent`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, terminal komutları ve betik uzantıları onu kullanmaz: yazdığınızı alırlar ve seçim olduğu gibi kalır. En fazla 5000 karakter; güvenli giriş sırasında veya bir terminalde asla okunmaz. Bir uygulamada düzgün çalışmıyorsa Settings → General → "Use the selected text" (seçili metni kullan) altından kapatın.

### Sonuçları iyileştirme (yeni)

`@improve`, bir talimat komutu (sizin ya da bir eklentinin) veya bir seçimin yeniden yazımının sonuçları görünürken neyin değişeceğini yazın, örneğin `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese` veya `用更口语的说法` (pinyin çalışır, Shift'e dokunmak dili değiştirir), ve ⇧⏎'ye basın: sonuçlar talimatınızla birlikte yeniden yapay zekâya gider ve yenileri aynı panelde onların yerini alır. ⏎ seçili sonucu ekler, talimat yarım yazılmış olsa bile (yazılan atılır). İstediğiniz kadar iyileştirin; panelin en üst satırı adımları listeler ("Refined: shorter · more formal") ve her zamanki gibi istediğiniz an bir satır seçebilirsiniz. Bir harf talimatı başlatır (panelin üstünde "refine › …" olarak gösterilir); talimat boşken rakamlar, Boşluk ve ⏎ eskisi gibi seçer, ⇧⏎ ise yazdığınızı olduğu gibi ekler. İyileştirme, sonuçlar tamamlandığında başlar: ilk sonuçlar hâlâ gelirken yazmak, eskisi gibi cümleyi sürdürür. Bir iyileştirme sürerken bir sonraki talimatı şimdiden yazabilirsiniz; iyileştirme devam eder ve ⇧⏎, sonuçları gelir gelmez bir sonrakini çalıştırır. Esc talimatı siler, ardından son iyileştirmeden önceki sonuçlara bir adım geri gider (bir iyileştirme sürerken: onu durdurur), sonra cümleye döner; boş bir satırda ⌫ aynı şekilde geri gider. Seçili metin üzerinde, seçtiğiniz sonuç yine tam olarak seçimin yerini alır; seçim o zamana kadar hiç değişmez. Başarısız olan (veya güvenli giriş sırasında reddedilen) bir iyileştirme sonuçları olduğu gibi bırakır, talimatı da ⇧⏎ ile yeniden denemeye hazır kalır. Aynı sonuçların aynı iyileştirmesi önbellekten yanıtlanır. `@translate` için iyileştirme yoktur: sonuçlarından sonra yazmak cümleyi sürdürür ve ⏎ onu yeniden çevirir.

### @question ile sohbetler (yeni)

`@question` yanıt verdikten sonra yazdığınız şey sonraki sorudur: ⇧⏎ onu o ana kadarki sorular ve yanıtlarla birlikte sorar ve panel bir sohbete dönüşerek büyür; önceki turlar soluk Q / A satırları olarak, en son yanıt da onların altında görünür. En üstteki satır sıradaki turun hangisi olduğunu söyler ("question 2/5 › …"). Her yanıt eklenebilir: rakamıyla (1–5), ↑↓ ve ardından ⏎ ile ya da bir tıklamayla; en son yanıt seçilidir ve ⌘C seçili olanı kopyalar. Bir soru yarım yazılmış olsa bile ⏎ yanıtı ekler (yazılan atılır). Esc yazdığınızı siler, ardından bir tur geri gider; ilk turda eskisi gibi çıkar. Panel ekranın yaklaşık yarısına kadar büyür, sonra kayar; en sonuncusu en altta olur.

5 turdan sonra (yapılandırmada `questionRounds`, 2–10) sonraki sorunun satırı "5 rounds in: continue in Claude or another AI" (5 tur oldu: Claude'da veya başka bir yapay zekâda sürdürün) olur ve seçenekler ⌘1, ⌘2 … diye numaralanır; ⌘⏎ bunları her turda gösterir (bir yanıt hâlâ gelirken hiçbir şey yapmaz ve uygulamaya asla ulaşmaz). O anda yazdığınız şey oradaki ilk mesaj olur; onu yalnızca ⌘1, ⌘2 … gönderir (⇧⏎ artık hiçbir şey sormaz ve hiçbir şey açmaz). Seçili metin hakkındaki bir soru o metni de, ayrı bir blok olarak alıntılanmış şekilde götürür. Seçenekler:

- Bu Mac'te **kurulu kodlama ajanları**, her biri kendi adıyla: önce `@agent`'ın işi devrettiği (⌘1), sonra diğerleri (Claude Code, Gemini CLI, Kiro CLI, Settings → Agent'taki kendi komutunuz). Her biri Terminal'de, `@agent`'ın başlattığı gibi başlatılan, sohbet ve "Let's continue this discussion" ile başlayan etkileşimli bir oturum açar. Kurulu olmayan gösterilmez.
- Web'de **Claude** veya **ChatGPT**, sohbet önceden doldurulmuş olarak (uzun bir sohbet panoya konur: yapıştırın).
- Web'de **Gemini**, sohbet yapıştırılmak üzere panoda.
- **Copy the conversation** (sohbeti kopyala), Markdown biçiminde (**Q:** / **A:**).

Hangileri ve hangi sırayla (ilki varsayılandır): Settings → General → "Continue a conversation in" (sohbeti şurada sürdür; yapılandırmada `questionContinueIn`); 5'ten fazlaysa kalanları ⌘6 … ⌘9 seçer. Oradaki "@agent's agent" (@agent'ın ajanı), Settings → Agent'ın seçtiği ajandır ve kendi adıyla görünür; şu an kurulu olmayan bir ajan, listeyi düzenlediğinizde listedeki yerini korur. Bu Mac'te Apple Intelligence ile uzun bir sohbet onun küçük bağlamına sığmaz: önce en eski yanıtlar kısaltılır, sonra en eski turlar dışarıda bırakılır ve panel "earlier rounds shortened" (önceki turlar kısaltıldı) der. Bir sohbet son sorular arasında ilk sorusunun altında kaydedilir; onu seçmek, sürdürmeniz için turları gösterir.

### Son sorular (yeni)

Ardından hiçbir şey yazılmamış `@question`, son 5 sorunuzu en yenisi önce olmak üzere, ne zaman sorulduklarıyla birlikte listeler ("3 hours ago"). Yazmak listeyi daraltır: sorunun herhangi bir yerindeki her sözcük, büyük/küçük harf fark etmeksizin (boşluksuz Çince de). Bir rakam, ↑↓ ve ardından ⏎ ya da bir tıklama, bir sorunun kayıtlı yanıtını hemen, internete çıkmadan gösterir: Boşluk veya ⏎ ekler, ⌘C kopyalar, ⌘R yeni bir yanıt için yeniden sorar (bir sohbette: son sorusunu), Esc listeye döner. Kayıtlı bir sohbet tüm turlarını gösterir: sürdürmek için yazın. Eşleşme yoksa ya da hiçbir şey seçilmediyse ⏎ yazdığınızı sorar. Aynı soruya gelen yeni bir yanıt ya da sürdürülen bir sohbet, kayıtlı olanın yerini alır.

- Yalnızca bu Mac'te saklanırlar (bkz. Gizlilik): güvenli giriş açıkken saklanmaz, seçili metin üzerine sorulan sorular için asla saklanmaz.
- Settings → General → "Remember recent questions" (son soruları hatırla) özelliği kapatır (yapılandırmada `rememberQuestions`); orada kapatılınca sorular da silinir. Settings → Assistant ile kapatılınca korunurlar, böylece geri almak her şeyi tam olarak eski hâline getirir (önizlemesi bunu belirtir); "Clear (N)" (temizle) onları siler.

### Notlar ve anımsatıcılar

`@note` yeni bir not oluşturur; ilk satırı başlıktır. Bir metni kopyaladıktan sonra `@note ` arkasından ⌃V (ya da terminaller dışında ⌘V) onu satır sonlarıyla kaydeder; satır sonları komutta ↵ olarak gösterilir. Satır sonları içeren bir not kaydedilmeden önce metin alanından ayrılırsanız (başka bir yere tıklarsanız, uygulama değiştirirseniz) veya ⇧⏎'ye (yazıldığı gibi ekle) basarsanız, not uygulamaya yazılmaz (terminalde her satır bir komut olarak çalışırdı): bunun yerine panoya gider ("The note wasn't saved; its text is on the clipboard" — not kaydedilmedi, metni panoda). Tek satırlık bir not yazıldığı gibi eklenir.

`@reminder`; `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (ayın 1'i), `end of the year` gibi zamanları okur (Çince zamanları da). Gün ve saat ayrı yerlerde olabilir (`tomorrow call Bob at 5`); haftalar pazartesi başlar. am veya pm olmadan verilen bir saat (`at 5`) bir sonraki o saattir, asla gece yarısı ile sabah 6 arasında değildir; bugün geçmiş bir saat yarına kalır, ama günün hâlâ süren bir bölümü (`this afternoon`, `tonight`) bugündür ve tüm gün sürer; bu yıl geçmiş bir tarih gelecek yılınkidir. Tekrarlanacak şekilde yazılmışsa (`standup every Monday at 9`), bir sonraki sefer için bir kez eklenir: sözcükler başlıkta kalır ve satırda "once only" (yalnızca bir kez) yazar. Onay satırı okunan zamanı gösterir, ör. "tomorrow 3:00 PM" (Mac'in 12/24 saat ayarına göre); yanlışsa Esc metne döner. İçinde saat veya tarih yoksa, anımsatıcının da yoktur ("no date").

Bu ikisinin içindeki `@stock` ve benzerleri çalıştırılmaz: metin yazıldığı gibi kaydedilir (orada `@` yazmak komut listesini açmaz). İlk seferde macOS, AllInOneIME'nin Notes'u denetlemesine (`@note`) veya Reminders'a erişmesine (`@reminder`) izin verilip verilmeyeceğini sorar: izin verin. Vermediyseniz, AllInOneIME'ye "System Settings → Privacy & Security → Automation" (Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon) (Notes) veya → "Reminders" bölümünden izin verin. Bir kaydetme başarısız olduğunda (örneğin izin yoksa), bildirim nedenini söyler ve metin, düzeltip yeniden göndermeniz için komuta geri gelir; önce bir şeyi düzeltmeniz gerekiyorsa (bir izin, bir hesap), metin panoya da konur (System Settings'e gitmek odağı metin alanından alır). Başka bir metin alanına geçtiyseniz veya başka bir şey yazıyorsanız, metin bunun yerine panoya gider ("Not saved; the text is on the clipboard.").

### Kendi komutlarınız

Ayarlarda, "Custom @ Commands" (özel @ komutları) altında "Add Command…" (komut ekle) düğmesine tıklayın: bir ad verin ve ne yapacağını seçin (bir yapay zekâ talimatı, bir program, Terminal'de bir program veya bir web sayfası) ya da bir örnekten başlayın. Komutlarınız yerleşik komutlardan sonra gelir; adlar yalnızca İngilizce harflerden oluşur ve yerleşik bir komutun adı olamaz; bir sonraki cümleden itibaren çalışırlar. Yapılandırma dosyasında (`~/.config/allinoneime/config.json`) `customCommands` içinde tutulurlar; bu dosyayı kendiniz de düzenleyebilirsiniz:

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | Ne yapar |
|---|---|
| `prompt` | Metni, talimat olarak `prompt` ile yapay zekâya gönderir; yanıt adaylarda görünür, eklenebilir veya kopyalanabilir (⌘C) |
| `run` | `argv`'yi arka planda çalıştırır; yazdırdığı çıktı adaylarda görünür (birden çok satır yazdırıldığı gibi, terminalde tek satır olarak eklenir). Hata olursa son satırı gösterilir |
| `terminal` | `argv`'yi yeni bir Terminal penceresinde çalıştırır; hiçbir şey eklenmez |
| `link` | Metni `url` web adresine yerleştirir ve varsayılan tarayıcıda açar; hiçbir şey eklenmez |

- `{input}` komuttan sonra yazdığınız metne dönüşür ve her zaman içinde bulunduğu tek argümanın içinde kalır: hiçbir kabuk (shell) devreye girmez. Kabuk istiyorsanız bunu açıkça belirtin, yukarıdaki `sh` gibi (`zsh -c`).
- `stdin`: programın standart girdisine gidecek olan; burada da `{input}` yerine metin konur.
- Bir `link`'in `url`'si `https://` olmalı ve `?` veya `#`'den sonra bir kez `{input}` içermelidir; metin kodlanır (boşluk `%20`, yeni satır `%0A` olur), en fazla 4000 karakter.
- `run` ve `terminal` varsayılan olarak İngilizce harf yazar (`@open` gibi; Çince modunda sonrasında Çinceye dönülür) ve tam genişlikli noktalama işaretleri ASCII'ye dönüşür. Metni yazıldığı gibi tutmak için `"ascii": false` ayarlayın.
- Programlar ana klasörünüzde, oturum açma kabuğunuzun PATH'iyle çalışır (böylece Homebrew, pyenv ve nvm kurulumları bulunur). `run` bir programı 10 saniye sonra (`timeoutSeconds`) veya çok fazla çıktı ürettiğinde durdurur; Esc onu her an durdurur.
- `summary` komut listesindeki açıklamadır (isteğe bağlı).
- `argv`'deki program bulunamadığında (örneğin `python3` yoksa) komut sunulmaz ve `@python …` metin olarak eklenir; program kurulduktan sonra komut bir sonraki metin alanında görünür.

`run` ve `terminal` Mac'inizde kod çalıştırır: yalnızca kendi yazdığınız ve güvendiğiniz komutları ekleyin. Bunlar da yalnızca eylem tuşuna bastığınızda çalışır ve güvenli giriş sırasında asla çalışmaz.

### Betik uzantıları

Kendi @ komutlarınızı program olarak ekleyin: yorumlarında birkaç satır meta veri bulunan, herhangi bir dilde (bash, Python, Node, Swift, …) bir betik. Onu `~/.config/allinoneime/extensions` içine ya da "Settings → Custom Commands → Script Extensions" altında eklediğiniz bir klasöre koyun. Raycast Script Commands olduğu gibi çalışır ve bunları zaten barındıran klasörler Spotlight ile bulunur.

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh`, `@flights` olur. Argümanlarını arkasına virgülle ayırarak yazın: `@flights beijing, new york` onu `$1` ve `$2` olarak `beijing` ve `new york` ile çalıştırır (fazladan virgüller sonuncuda kalır); zorunlu bir argüman boş bırakılırsa, çalıştırmak yerine neyin eksik olduğunu söyler. Yazdırdığı çıktı, `output` değerinin söylediği şekilde kullanılır:

| `output` | Ne olur |
|---|---|
| `insert` (varsayılan) | Tamamı ve her satırı ayrı ayrı, eklenmek üzere |
| `show` | Yazdırıldıkça panelde gösterilir (ilerleme); hiçbir şey eklenmez. Alandan ayrılırsanız arka planda devam eder (aynı anda en fazla dört) |
| `list` | Alfred'in Script Filter JSON biçiminde bir liste, siz yazdıkça yeniden çalıştırılır; bir satırı seçmek ekler, açar (bir web adresi, dosya veya klasör; asla çalıştırılacak bir şey değil), kopyalar veya ikinci bir adımı çalıştırır |
| `silent` | Son satırı imlecin yanında; hiçbir şey eklenmez |

Bir komut ayrıca hiç girdi almayabilir (`input none`: adının üzerinde ⏎ onu çalıştırır), arka planda (`background`) çalışıp bitince size bildirebilir (bu sırada menü çubuğu paneli onu listeler), komut listesinde adının yanında bir `status` gösterebilir ya da önce onay isteyebilir (`confirm`). Kendi klasöründe, oturum açma kabuğunuzun PATH'i ve `ALLINONEIME_*` değişkenleriyle çalışır: arayüz ve giriş dili, yazdığınız uygulama, metin. **Paket** (bundle), komutlarını adlandıran bir `extension.json` içeren bir klasördür: komutlar kodu ve tercihleri paylaşır, tercihleri ayarlar gösterir (parolalar anahtar zincirine gider). Ayarlar her komutu bir anahtarla, dışarıda bırakılan betikleri de nedeniyle listeler.

Raycast'in modları şöyle eşlenir: `fullOutput` → `show`, `compact` ve `silent` → `silent`, `refreshTime` ile `inline` → bir status. Protokolün tamamı [docs/extensions.md](../extensions.md) içindedir; [Core/Examples/extensions](../../Core/Examples/extensions) her türden birer örnek içerir. Uzantılar Mac'inizde kod çalıştırır: güvendiklerinizi kullanın. Yalnızca siz çalıştırdığınızda çalışırlar (status veya list, siz yazdıkça), güvenli giriş sırasında asla çalışmazlar ve giriş yöntemi kapandığında dururlar.

#### Uzantı kaynakları (yeni)

Bir paket, sizin ya da ekibinizin bir Git deposundan gelebilir ve oradan güncel kalabilir. Settings → Custom Commands → Extension Sources → **Add from Link…** (bağlantıdan ekle): deponun adresini yapıştırın (`git@github.com:you/my-extensions.git`, `ssh://…`, `https://…`; isteğe bağlı olarak bir dal, paketin depodaki klasörü ve sabitlemek için bir etiket veya commit). AllInOneIME onu **kendi git ve SSH kurulumunuzla** (anahtarlar, agent, ~/.ssh/config, kimlik bilgisi yardımcıları) klonlar, böylece özel bir depo Terminal'de olduğu gibi çalışır; uygulama asla parola istemez veya saklamaz. Klon `~/Library/Application Support/AllInOneIME/Sources/` içine gider: önce gizli bir hazırlık klasörüne, asla doğrudan bir uzantı klasörüne değil. (Bir https adresine ad, parola veya belirteç koymayın: bunları git'in kimlik bilgisi yardımcısı saklar.)

- **Önce inceleme.** Herhangi bir şey yüklenmeden önce paketi, her komutu (ad, başlık, açıklama, çıktı), çalıştırdıkları programları, tercihlerini ve commit'i "This source isn't signed: it will run programs from <address>" (bu kaynak imzalı değil: o adresten programlar çalıştıracak) uyarısının altında görürsünüz. Onu yalnızca **Enable** (etkinleştir) ekler; Cancel (iptal) klonu siler. Bir kaynağı bir kez incelersiniz.
- **Güncellemeleri uygulamak size kalmış.** Günde bir kez (ve giriş yöntemi başladıktan kısa süre sonra) bir kaynak, yenilikleri görmek için fetch edilir: ayarlar commit'lerle (konu, yazar, tarih) birlikte "N updates" (N güncelleme) ve sayfada bir rozet gösterir. Siz **Update**'e (güncelle) tıklayana kadar hiçbir şey değişmez; o da yalnızca fast-forward yapar ve hiçbir hook çalıştırmaz. Zorla push (force push) kaynağın yeniden incelenmesini gerektirir: **Re-clone** (yeniden klonla) onu gösterir ve yeniden yazılmış geçmişi yalnızca Enable yerine koyar (o zamana kadar incelenmiş sürüm çalışmaya devam eder). Bir etikete veya commit'e sabitlenmiş kaynak denetlenmez. Günlük denetim kaynak başına kapatılabilir (`autoCheck`).
- **Hatalar** git'in kendi sözleridir; yanlarında "This uses your own git and SSH setup; check that `git ls-remote <url>` works in Terminal" (bu, kendi git ve SSH kurulumunuzu kullanır; o komutun Terminal'de çalıştığını denetleyin) ve ayarladıysanız altında kendi hatırlatmanız (yapılandırmada `authHint`) yer alır.
- **Remove** (kaldır) klonu Çöp Sepeti'ne taşır; paketin tercihleri bir sonraki sefer için saklanır.
- Bir terminalden: `AllInOneIME --add-source <url> [--path …] [--branch …] [--pin …]` (incelemeyi yazdırır ve kaynağı etkinleştirir; zorla push'tan sonra yeniden), `--update-sources` (sabitlenmemiş, incelenmiş her kaynağı fast-forward eder), `--list-extensions` (`~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME` üzerinde).
- Yalnızca incelenmiş kod yüklenir: yükleme listesinde olup bu Mac'te incelenmemiş bir kaynak klasörü (kopyalanmış bir yapılandırma) dışarıda bırakılır. git asla bir yanıt beklemez: terminal ve istem yoktur, bu yüzden bilinmeyen bir ana makine anahtarı veya bir parola istemi hemen başarısız olur.

Yapılandırma bunları `extensionSources` olarak saklar; deponun düzeni [docs/extensions.md](../extensions.md#10-extension-sources) içindedir.

### Eklentiler

Eklentiler, herkesin ihtiyaç duymadığı şeyler için hazır `@` komutlarıdır; örneğin hisse senedi fiyatları için `@stock AAPL 600519 700`. Kurulduktan sonra her komut gibi çalışırlar; ayarlardaki "Plugins" bölümü neyin kurulu olduğunu ve her birinin metninizi nereye gönderdiğini gösterir ve onları kaldırır. Eklentiler ayrı bir süreçte çalıştırılan JavaScript'tir: yalnızca beyan ettikleri web sitelerine (HTTPS) erişebilirler, dosya okuyamaz ve başka programlar çalıştıramazlar. Ayarlarda "Plugins" altındaki "Browse Library…" (kitaplığa göz at) onları [eklenti kitaplığından](https://github.com/MicroZ-LLC/AllInOneIME-plugins) kurar: kurmadan önce bir eklentinin hangi web siteleriyle iletişim kurduğunu gösterir; kitaplığın dizini imzalıdır ve her dosya ona uymak zorundadır. Daha yeni bir sürüm "Update" (güncelle) düğmesi gösterir; hiçbir şey kendiliğinden güncellenmez. Kendi eklentileriniz `~/.config/allinoneime/plugins/` ("Open Plugins Folder") içine gider: bunlar yerel eklentilerdir ve kitaplık bunların üzerine asla yazmaz. "Bağlantı" (link) eklentileri kod çalıştırmaz: metni bir web adresine yerleştirip tarayıcıda açarlar; örneğin `@x nice weather today`, X'in gönderi oluşturucusunu metin doldurulmuş olarak açar; paylaşmak sayfada size kalır. Kitaplıkta dört tane vardır (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` döviz çevirir: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, kurun tarihiyle birlikte tek satır (kurlar ExchangeRate-API'den). `@calculator` çevrimdışı çalışan bir hesap makinesidir, `@calculator 23*17` → `391` (0.6.5'ten önce yerleşik `@calculate`); `@calendar` ise tarihleri hesaplar: `@calendar +10` → "Tue, Oct 27 · in 10 days". Eklenti yazmak için: [docs/plugins.md](../plugins.md).

Bir şey getiren komutlar (eklentiler ve programlar) bir cümlenin içinde de çalışır: `@reply tell her @stock AAPL is up today`. İçteki komutlar önce çalışır, çıktıları onların yerini alır ve dıştaki komut sonuç üzerinde çalışır. Argüman, komuttan sonraki sözcük ile hemen arkasından gelen büyük harfli kodlar veya sayılardır (`@stock AAPL TSLA`, `@stock 600519 700`); küçük harfli bir sözcük argümanı bitirir (`@stock SNDK is good to buy` SNDK'yi arar). Tırnaklar onu tam olarak belirler: `@stock "aapl tsla"`. `@calculator` eklentisi de orada çalışır: `@reply the total is @calculator 23*17 dollars`. `@agent` ve terminal komutlarının içinde çalıştırılmazlar: onlar metni yazıldığı gibi alır (orada `@` yazmak komut listesini açmaz).

### Eylem tuşu

Varsayılan ⏎; ayarlarda "Action key" (eylem tuşu) altından değiştirin (yapılandırmada `actionKey`): ⏎, "Tap ⌥" (⌥'ye dokunma, iki taraftan biri: basıp hemen bırakın; sağ ⌥'yi basılı tutmak yine konuşmak içindir), ⌥Space veya Space (sözcükler seçildikten sonra Boşluk'a bir kez daha basın; İngilizce modunda iki kez). Eylem tuşu ne olursa olsun, @ komutları ⏎ ile de çalışır. ⌥Space zaten Alfred, Raycast veya benzeri bir uygulamanın kısayoluysa, önce onlar alır.

### Sonuçları yazarak ekleme

Settings → General altında "Type results out" (sonuçları yazarak ekle) seçeneğini açın (yapılandırmada `typeOut`); bir komutun sonucu bir kerede girmek yerine, bir insan yazıyormuş gibi karakter karakter uygulamaya yazılır; pinyin seçimleri yine bir kerede girer. Kaydırıcı hızı belirler, karakter başına 6 saniyeden saniyede 40 karaktere kadar (`typeOutRate`); "Speed up and slow down (like a person)" (bir insan gibi hızlan ve yavaşla) değişen hızda kısa atışlarla yazar (`typeOutVaries`). Esc olduğu yerde durdurur; başka herhangi bir tuş kalanı bir kerede yazar.

"Make occasional typos and fix them" (arada bir yazım hatası yap ve düzelt, `typeOutMistakes`) daha da insan gibi görünmesini sağlar: arada bir doğru tuşun yanındaki tuşa basılır, en geç üç harf sonra fark edilir, silinir ve yeniden yazılır; bir harf veya boşluk iki kez yazılıp silinir; ya da kısa bir sözcük yazılır, silinir ve yeniden yazılır. 100 karakterde birkaç tane, asla ikisi yan yana değil ve asla satır başında değil. Kodda, web ve e-posta adreslerinde ve sayılarda bir yazım hatası yalnızca yanlış bir harf veya rakamdır ve hemen düzeltilir (asla yanlış bir parantez, tırnak veya boşluk değil; düzenleyiciler bunlarda eşleştirme veya girinti yapar). Yanlış harfler, klavye düzeninizde (QWERTY, AZERTY, QWERTZ…) komşu harflerdir. Çince, Japonca ve Korece yalnızca duraksar (iki karakter yazılır, silinir ve yeniden yazılır), asla yanlış bir karakterle değil.

Bir yazım hatasının geri alınabildiği bir alanda (TextEdit ve Notlar gibi Apple'ın metin görünümleri, tarayıcılar, çoğu düzenleyici): sonuna kadar yazıldığında ya da kalanı bir kerede yazmak için başka bir tuşa basıldığında metin tam olarak sonuçtur; bir yazım hatasının ortasında Esc (veya alandan çıkmak) önce hatayı çıkarır, böylece alanda sonucun tam bir başlangıcı kalır. Bir hata görünürken imleç hareket ederse (bir tıklama), hata bulunduğu yerden çıkarılır ve kalan kısım hatasız yazılır.

Terminallerde ve imlecin nerede olduğunu giriş yöntemine söylemeyen uygulamalarda asla yazım hatası yapılmaz. Her seferinde ilk hata basit bir hatadır (tek seferde düzeltilen yanlış bir harf), ta ki alan bir hatayı geri alabildiğini gösterene dek; bir hata görünürken giriş yöntemi her tuştan önce alanın kendi yazdığını içerip içermediğini denetler. Metnin nerede değiştirileceğini yok sayan bir alan bir hatayı geri alamaz: orada o ilk hata kalır, böylece metin bir karakter farklı biter (Esc veya başka bir tuştan sonra da) ve uygulama artık hiç hata almaz. Settings → General bu uygulamaları yazım hatası anahtarının altında listeler; "Forget apps where typos couldn't be fixed" (hataların düzeltilemediği uygulamaları unut) onlara yeniden deneme şansı verir.

### Uygulamaya özel ayarlar (yeni)

Settings → Apps bir uygulamaya kendi ayarlarını verir, her biri isteğe bağlıdır; bir uygulamanın belirlemediği şeyler tüm uygulamalar için olan ayarları izler:

| Ayar | Örneğin | Yapılandırmada |
| --- | --- | --- |
| Metin alanlarının başladığı giriş dili | Slack'te İngilizce, WeChat'te pinyin | `inputLanguage` |
| `@improve`'un orada sunduğu yeniden yazma stilleri | Mail'de resmî ve nazik, Slack'te gündelik | `rewriteStyles` |
| Sonuçları yazarak ekle, ya da ekleme | bir sohbet uygulamasında açık, Mail'de kapalı | `typeOut` |
| Bu uygulamada yapay zekâ yok | `@improve`, `@translate`, `@question`, `@agent` ve talimat komutlarınız orada hiçbir şey göndermez ve bunu söyler; yazma ve diğer komutlar çalışır | `noAI` |

"Add App…" (uygulama ekle) son zamanlarda yazdığınız uygulamaları listeler ya da /Applications içinden birini seçer. Giriş menüsündeki "This App: <ad>", yazdığınız uygulama için hızlı anahtarlar içerir (No AI, Type Results Out, başlangıç dili). Yapılandırmada bunlar `appProfiles` altında, paket kimliğine (bundle ID) göre bulunur: `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. Paket kimlikleri büyük/küçük harf fark etmeksizin eşleşir (`com.apple.Mail`, Mail'in `com.apple.mail` kimliğidir). `@reportissue` bir şey belirleyen uygulamaları sayar, adlarını asla vermez.

- Başlangıç dili varsayılan giriş dili gibi çalışır: bir metin alanı etkinleştiğinde onu alır ve Shift ile yapılan bir değişiklik, ayar değişene kadar o uygulamanın alanlarında kalır.
- No AI açıkken yapay zekâ komutları @ listesinde kalır; birini çalıştırmak bildirimi gösterir ve yazdığınızı korur. Kendi terminal komutlarınız (`"type": "terminal"`) yapay zekâyı değil programları çalıştırır, bu yüzden orada çalışmaya devam eder.

### Settings → Assistant (yeni)

Ayarlar, iki bölümlü bir sayfa olan **Assistant** ile açılır (0.6.5'ten önce bunlar `@config` ve `@doctor` komutlarıydı).

**Ayarları bir cümleyle değiştirme** ("Change settings in a sentence"): ne istediğinizi yazın ("translate into Japanese and English", "candidates in a column", "use Claude") ve Preview'a (ya da ⌘⏎) basın. Her değişiklik eski → yeni olarak gösterilir; Apply bunları uygular, Undo ise 10 dakika içinde geri alır. API anahtarları, kendi komutlarınız, eklentiler ve program çalıştıran hiçbir şey orada değiştirilmez; anahtarı olmayan bir sağlayıcı, Settings → AI Provider'da anahtar alanını açar ve sağlayıcı değişince Test Connection çalışır. Bu Mac'te Apple Intelligence varsa onunla, yoksa sağlayıcınızla çalışır.

**Sorunları denetleme** ("Check for problems"): giriş yöntemi, yapay zekâ sağlayıcısı, izinler, güvenli giriş, dil paketleri, `config.json`, uzantılar, güncellemeler ve son hatalar sayfa açılırken bu Mac'te denetlenir, önce sorunlar (her şey yolundaysa: "Everything looks good"). Check, Test Connection ile birlikte yeniden denetler; "What's wrong? (optional)" alanına bir soru yazarsanız yapay zekâ olası nedeni açıklar. Düzeltilebilen bir satırda Fix düğmesi vardır: ayar değişiklikleri üstteki önizlemede Apply ve Undo ile görünür; diğerleri hemen uygulanır.

## Menü çubuğu paneli

<img src="../en/panel-swipe.png" width="520" alt="Menü çubuğu paneli: buzlu cam, kartlarda notlar, anımsatıcılar ve Claude görevleri; sola kaydırılan bir satır Remove düğmesini gösteriyor">

Menü çubuğunda AllInOneIME'nin simgesine (çerçevesiz ∞ ve imleç işareti; çerçeveli olan giriş kaynağıdır) tıklayın, panel hemen altında açılır; başka bir yere tıklamak onu kapatır:

- "Notes" (notlar): `@note` ile kaydedilen notlar, en yeni 5 tanesi; Notes'ta açmak için birine tıklayın.
- "Reminders" (anımsatıcılar): Reminders'taki AllInOneIME listesinde henüz tamamlanmamış anımsatıcılar (`@reminder` bu listeye ekler), en yakın tarihli olanlar önce, 8 tanesi gösterilir; birini tamamlandı olarak işaretlemek için daireye, Reminders'ı açmak için başlığa tıklayın.
- "Claude Tasks" (Claude görevleri): `@tasks`'ta olduğu gibi arka plandaki Claude görevleri (`@agent`'ın Claude Code'a devrettikleri), en fazla 30, bir seferde 5 tanesi gösterilir: daha fazlası için kaydırın ya da arama kutusunda başlıklarında ve yanıtlarında arayın; ilerlemeleri ve son yanıtın ilk satırıyla birlikte; Terminal'de açıp devam etmek için birine tıklayın.

Bir satırı (bir not, bir anımsatıcı veya bir görev) "Remove" (kaldır) düğmesini göstermek için iki parmakla sola kaydırın ya da hemen kaldırmak için sonuna kadar kaydırın; fareyle sağ tıklayın. Kaldırmak onu yalnızca panelden çıkarır: not Notes'ta, anımsatıcı Reminders'ta (tamamlanmamış olarak), görev Claude Code'da kalır.

Başlıkta sayılar (ör. "2 reminders · 1 task running"; sizi bekleyen görevler ayrıca sayılır, ör. "1 waiting for you") ve bir yenile düğmesi bulunur. Panel, yazdığınız uygulamadan odağı asla almaz: bir anımsatıcıyı işaretlemek veya yenilemek o uygulamayı önde bırakır; yalnızca Claude görevlerinin arama kutusu, tıklandıktan sonra klavyeyi alır. Simge varsayılan olarak gösterilir; ayarlarda "Menu Bar Panel" altından kapatın.

Neyi ve ne zaman okuduğu:

- Notlar: liste panelin kendi kaydıdır (panel kapalıyken de tutulur) ve Notes asla başlatılmaz: panel, ancak Notes zaten çalışıyorsa ve AllInOneIME'ye daha önce onu denetleme izni verildiyse, düzenlenmiş başlıklar ve silinmiş notlar için onu kontrol eder.
- Anımsatıcılar: AllInOneIME listesi panel açıldığında, her 60 saniyede bir ve anımsatıcılar değiştiğinde okunur. Panel, macOS'un kendiliğinden erişim istemesine asla yol açmaz: macOS size henüz sormadıysa "Allow Access to Reminders" gösterir ve yalnızca bu düğme sorar; hayır dediyseniz "Open System Settings" gösterir.
- Claude görevleri: panel `claude agents`'ı yalnızca açıkken çalıştırır: açıldığında bir kez, yenilendiğinde ve `@agent` bir görev devrettiğinde; ayrıca bir görev henüz bitmemişken her 15 saniyede bir, hepsi bittiğinde artık değil. Son yanıtlar bu Mac'teki Claude Code dökümlerinin (`~/.claude/projects`) sonundan ve yalnızca bir döküm değiştiğinde okunur.
- Panel kapalıyken bunların hiçbiri çalışmaz; yalnızca `@note`'un kaydettiği notların kaydını tutar.

## Giriş ve çeviri

Ayarlarda:

- **Input languages** (giriş dilleri): İngilizce, Çince (pinyin), Fransızca, Korece ve Hintçe arasından birden beşe kadar dil, + ile eklenir (her zaman oradadır; beş dilde gri olur). Yeni bir kurulum yalnızca İngilizceyle başlar. Yeni metin alanları ilk dille başlar; sıradakine geçmek için Shift'e dokunun; tek dil varken Shift dil değiştirmez.
  - **Fransızca** kendi klavye düzeniyle yazar: kartında başka bir düzen seçmediyseniz AZERTY. Ölü tuşları (^, ¨, `, ´, ~) da bu düzene göre birleşir.
  - **Korece**, Hangul'u 2 setli (Dubeolsik) düzende yazar, her hece siz yazdıkça birleştirilir (g k s → 한); Shift ㄲ ㄸ ㅃ ㅆ ㅉ ve ㅒ ㅖ verir.
  - **Hintçe**: sözcükleri Latin harfleriyle okunduğu gibi yazın ve Devanagari elde edin (namaste → नमस्ते). Yaygın sözcükler Hintçede yazıldığı gibi yazılır; aksi hâlde Boşluk ilk yazımı, bir rakam başka bir yazımı, ⏎ harfleri yazıldığı gibi, "." ise danda'yı (।) ekler.
  - Bir komutun adı, `@open`'ın metni ve kod (`@py`, `@js`) dil ne olursa olsun Latin harfleriyle yazılır; dil komuttan sonra geri gelir.
  - `@improve` Korece, Hintçe veya Fransızca bir cümleyi kendi dilinde tutar, `@translate` ise onu dillerinize çevirir (Fransızca, giriş dillerinizden biriyse İngilizceden ayırt edilir).
- **Language packs** (dil paketleri): uygulama İngilizceyle (ve yalnızca macOS'un düzenine ihtiyaç duyan Fransızcayla) gelir. Çince, Korece ve Hintçe, eklediğinizde indirdiğiniz paketlerdir: Çince (pinyin) eklemek sözlüklerini bir ilerleme çubuğuyla indirir (yaklaşık 34 MB, açılmış hâlde 125 MB) ve pinyin, indirme biter bitmez yeniden başlatmaya gerek kalmadan çalışır; Korece paketi (tuş tablosu ve jamo'ların nasıl hece oluşturduğu) ve Hintçe paketi (harfleri ve yaygın sözcükleri) birkaç kilobayttır. Bir paket yalnızca veridir (sözlükler, tablolar ve şemalar, asla kod değil), imzalı bir dizinde listelenir ve kullanılmadan önce eklentiler gibi SHA-256'ya göre denetlenir. Her dilin kartı paketini (sürüm, boyut, nereden geldiği) "Delete…" ile birlikte gösterir ve dili kaldırmak paketini de silmeyi önerir. 0.6.1 veya daha eski bir sürümden güncellemek Çinceyi indirme olmadan korur: yükleyici eski sürümle gelen sözlükleri tutar.
- **Aday düzeni**: sözcük seçerken pinyin ve Hintçe adayları varsayılan olarak yan yanadır (Horizontal), sistemin kendi giriş yöntemlerindeki gibi: ← → seçer, ↑↓ (veya - =) sayfa çevirir. Alt alta dizilmeleri için (↑↓ seçer) Input sayfasında, giriş dillerinin altında Vertical'ı seçin. @ komut listesi ve sonuçlar her zaman dikeydir.
- **Fuzzy pinyin** (bulanık pinyin, Çince girişle): ayırt etmediğiniz sesler her iki şekilde de yazılabilir, ör. z ↔ zh, n ↔ l, in ↔ ing. "Input" sayfasında, giriş dilleri çubuğunda "Chinese (pinyin)" seçin, "Fuzzy pinyin"i açın ve çiftleri seçin; sözlükler bir iki saniye içinde yeniden dağıtılır. Rime kullanıcı klasörüne `rime_ice.custom.yaml` yazar ve oradaki kendi dosyanızın üzerine asla yazmaz.
- **Translate (@translate)**: çevrilecek dilleri ekleyin (İspanyolca, Fransızca, Almanca, Japonca, Korece, Çince, Hintçe, Bengalce, Tamilce ve diğer başlıca Hint dilleri…) ve sürükleyerek sıralayın. Latin harfleriyle yazılmış Hintçe ("aap kaise ho") Devanagari olarak döner. `@translate` her dilde, bu sırayla birer satır yazar (tek dil varsa üç sürüm); cümlenin kendi dili atlanır. Yeni bir kurulum, Mac'inizin tercih edilen dilleri arasında İngilizce olmayan ilk dile çevirir; yalnızca İngilizce varsa `@translate` bir dil eklemeniz için bu sayfayı açar.
- **Keyboard layouts** (klavye düzenleri): Fransızca, kartında seçilen düzenle yazar (yapılandırmada `keyboardLayouts`). Diğer diller için macOS giriş yönteminin altında son Latin düzeninizi (AZERTY, QWERTZ, İspanyolca, US International…) korur; böylece her zamanki gibi yazarsınız, düzeninizde nerede bulunuyorsa `@` da dahil, ve ölü tuşlar bir komutun metninde de birleşir (⌥E ardından E → é, ^ ardından e → ê). Latin harfi olmayan düzenler (Rusça, Hintçe InScript) bir giriş yöntemi altında kullanılamaz: onlara ⌃Space ile geçin ya da metni bir komuta yapıştırın (⌃V) veya dikte edin.
- `@improve` çevirmeden cilalar ve yeniden yazar; `@translate @improve` birlikte tek istekte çevirir ve yeniden yazar. `@improve`'un bunu her zaman yapması için ayarlarda "@improve also translates" seçeneğini açın.

## Yeniden yazma stilleri

1–3. satırlardan sonra yeniden yazımlar gelir, **yazdığınız dilde**: İngilizce için İngilizce, Çince için Çince yeniden yazımlar. Ayarlarda bunlardan istediklerinizi seçin:

- "Polish" (cilala): aynı ton, daha doğal
- "Concise" (kısa ve öz)
- "Formal" (resmî): yöneticiler ve müşteriler için
- "Casual" (gündelik)
- "Tactful" (nazik)
- "Jargon": İngilizcede Amazon ağzı (bandwidth, circle back…), Çincede büyük teknoloji şirketlerinin jargonu. Kötü haberler yumuşatılır, ör. "this is a blocker bug" → "Oh! Looks like your team has the bandwidth to fix this minor issue!"

Yalnızca noktalamayı değiştiren veya başka bir satırı tekrarlayan yeniden yazımlar gösterilmez.

### Jargon listesi (kendi terimleriniz)

Jargon'un yerleşik bir terim listesi yoktur. Kendi listenizi hazırlayabilirsiniz (örneğin ekibinizin kullandığı ifadeler) ve model bu terimleri tercih eder. Adaylarda Jargon satırı, kullandığı terimlerin ne anlama geldiğini not eder.

Liste, her satırda bir terim bulunan bir metin dosyasıdır; terimin ardından isteğe bağlı olarak "=", iki nokta üst üste veya Tab ile ayrılmış anlamı gelir (bir elektronik tablodan iki sütun kopyalayıp yapıştırabilirsiniz). `#` ile başlayan satırlar yorumdur:

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

Ayarlarda "Rewrite Styles → Jargon list" altında, `~/.config/allinoneime/jargon.txt` konumunda boş bir liste oluşturup açmak için "New"e tıklayın; zaten bir liste dosyanız varsa, onu bulunduğu yerde kullanmak için "Choose File…" düğmesine tıklayın (yapılandırmada `jargonFile`). Değişiklikler hemen uygulanır. Yalnızca ilk 150 terim okunur. "Jargon" işaretliyken liste her istekle birlikte Bedrock'a gönderilir.

<img src="../en/panel-dark.png" width="420" alt="Karanlık modda aday paneli">

## Sesle giriş

<img src="../en/voice.png" width="340" alt="Konuşmak için sağ ⌥'yi basılı tutun">

Sağ ⌥'yi basılı tutup konuşun; bıraktığınızda metin eklenir. Konuşma yazdığınız dilde tanınır (İngilizce, Çince, Fransızca, Korece veya Hintçe). Önce bir komut yazıp (ör. `@improve `, `@question `) sonra konuşursanız, metin komutun arkasına gelir ve ⏎ onu çalıştırır; bitirir bitirmez çalıştırmak için sağ ⌥'yi bırakmadan ⏎'ye de basabilirsiniz. Konuşma Mac'te, macOS'un yerleşik konuşma tanıması (SpeechAnalyzer) ile tanınır ve hiçbir ses yüklenmez; macOS 26 veya üstü gerekir.

İlk seferde:

- macOS, AllInOneIME'nin mikrofonu kullanıp kullanamayacağını sorar. Önceden ayarlarda "Allow Microphone" (mikrofona izin ver) düğmesine de tıklayabilirsiniz.
- Bu Mac'te o dil için konuşma modeli henüz yoksa, bir kez otomatik olarak indirilir. Onu ayarlardan da indirebilirsiniz.

Kayıt ancak tuşu yaklaşık 0,2 sn basılı tuttuktan sonra başlar; böylece sağ ⌥'ye kısa bir dokunuş mikrofonu açmaz (eylem tuşu "Tap ⌥" olarak ayarlıysa dokunuş eylemi çalıştırır). Basılı tutarken başka bir tuşa basarsanız (bir ⌥ kısayolu, ⌥←), bu bir kısayol sayılır ve yine hiçbir şey kaydedilmez. Kayıt sırasında başka herhangi bir tuşa basmak kaydı iptal eder.

## Kurulum

Çalıştırmak için macOS 14 veya üstü, sesle giriş için macOS 26 veya üstü gerekir. Yükleyici evrenseldir: Apple silicon ve Intel işlemcili Mac'lerde çalışır. Şimdiye kadar yalnızca Apple silicon üzerinde macOS 27'de test edildi (Intel derlemesi yalnızca Rosetta altında kendi öz testiyle).

1. `AllInOneIME-<version>.dmg` dosyasını [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) sayfasından (yalnızca oradan) indirip açın.
2. İçindeki "Install AllInOneIME" öğesine çift tıklayın ve "Install" düğmesine tıklayın. Giriş yöntemi `~/Library/Input Methods` içine, "AllInOneIME Settings" ise `~/Applications` içine gider. Yalnızca bu kullanıcı için; yönetici parolası gerekmez.
3. Yükleyici bir Developer ID ile imzalanmış ve Apple tarafından onaylanmıştır (notarize), bu yüzden macOS ilk seferde yalnızca internetten indirilmiş bir uygulamayı açmak isteyip istemediğinizi sorar: Aç'a tıklayın. (0.6.3'ten önceki sürümler onaylanmamıştı: her birine Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç bölümünden bir kez izin vermek gerekiyordu.)

Bundan sonra AllInOneIME etkinleşir ve giriş kaynaklarınızda yer alır; ona Ctrl+Boşluk ile geçin (🌐 tuşu yalnızca "System Settings → Keyboard" içinde "Press 🌐 key to" seçeneği "Change Input Source" olarak ayarlıysa geçiş yapar). Yükleyici onu elle eklemenizi söylerse, bu Mac programların onu etkinleştirmesine izin vermiyordur; o zaman bir kez kendiniz ekleyin: "System Settings → Keyboard → Text Input → Input Sources → Edit… → + (sol altta) → English → AllInOneIME" (Sistem Ayarları → Klavye → Metin Girişi → Giriş Kaynakları → Düzenle… → + → İngilizce → AllInOneIME) (ayarlarındaki "Input" altında Çince ekledikten sonra pinyin de yazar).

Ctrl+Boşluk sizi AllInOneIME'ye götürmüyorsa ya da bir süre sonra yeniden U.S.'ye dönüyorsa, yükleyiciyi yeniden çalıştırın: AllInOneIME'yi giriş kaynaklarınıza geri ekler.

Güncelleme: Settings → About → Check for Updates (güncellemeleri denetle). Yeni bir sürüm olduğunda About bunu, yeniliklerle birlikte söyler (menü çubuğu panelinde de bir satır görünür); "Update to <version>" (<sürüm> sürümüne güncelle) onu indirir, AllInOneIME'nin yayın anahtarıyla imzalanmış güncelleme bilgilerine göre doğrular, kurar ve giriş yöntemini yeniden başlatır. Ayarlarınız, dil paketleriniz, öğrenilmiş sözcükleriniz ve uzantılarınız kalır; bir şey ters giderse sahip olduğunuz sürüm geri yüklenir. AllInOneIME günde bir kez kendiliğinden, arka planda bakar (About altındaki "Check for updates automatically" ile kapatın); siz tıklamadıkça hiçbir şey kurulmaz. Bu, 0.6.3'ten itibaren çalışır; daha eski bir sürümü güncellemek için ya da isterseniz, yeni sürümün disk görüntüsünü önce kaldırmadan onun üzerine kurun. Yükseltmeden önce [değişiklik günlüğünü](../../CHANGELOG.md) okuyun: her sürümün değişikliklerini ve yükseltme notlarını içerir.

Daha eski bir sürümden 0.6.3'e güncelleme: 0.6.3, bir Developer ID ile imzalanan ilk sürümdür, bu yüzden anahtar zinciri onu henüz anahtarlarınızı kaydeden uygulama olarak tanımaz. Kaydettiği her anahtara ilk kez ihtiyaç duyduğunda (bir API anahtarı, AllInOneIME Cloud oturumu, bir uzantının parolası) macOS giriş parolanızı sorar: parolayı girin ve "Always Allow" (Her Zaman İzin Ver) düğmesine tıklayın. Sonraki güncellemelerden sonra da bir daha sormaz. Amazon Bedrock'un anahtarları `~/.aws/credentials` içindedir ve bundan etkilenmez. Terminallere yapıştırmanın ve seçimi okumanın kullandığı Erişilebilirlik (Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik) de bir adım gerektirir: AllInOneIME listedeyse onu kaldırın ve sorulduğunda yeniden açın.

AIPinyin kuruluysa (AllInOneIME'nin önceki adı), yalnızca kurun: eski AIPinyin.app ve ayarlar başlatıcısı kaldırılır, giriş kaynaklarınızdaki kayıt da yeni adı alır, yeniden eklemeniz gerekmez. Ayarlar, jargon listesi ve öğrenilen sözcükler ilk açılışta yeni klasörlere (`~/.config/allinoneime` ve diğerleri) taşınır ve her eski klasör yenisine bir bağlantı olarak bırakılır.

Kaldırmak için "Install AllInOneIME"ı açın ve "Uninstall…" düğmesine tıklayın. Ayarlar ve öğrenilen sözcükler korunur.

### Kaynaktan derleme

Sesle giriş macOS 26 SDK'sını kullandığı için derlemek Xcode 26 veya üstünü gerektirir.

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` librime'ı ve rime-ice sözlüklerini indirip doğrular, derler ve aynı yerlere kurar; giriş kaynaklarınıza da aynı şekilde ekler. Kurduğu uygulamada Çince sözlükler yoktur (onlar Çince dil paketidir): onlara sahip olan bir kurulum onları paket olarak tutar; aksi hâlde `make install-pack` paketi, çalışma kopyasındaki sözlüklerden indirme olmadan kurar. `make status` kurulu sürümü (`version:`) ve giriş kaynaklarınızda olup olmadığını (`listed:`) gösterir. Kaldırmak için: `make uninstall`.

## Yapay zekâyı ayarlama

Çeviriler ve yeniden yazımlar Settings → AI Provider içinde seçilen yapay zekâ sağlayıcısına gider. Yeni bir kurulum AllInOneIME Cloud ile başlar: oturum açın, günde 20 ücretsiz isteğiniz olur. Apple Intelligence'lı bir Mac'te bunun yerine bu Mac'te, hesap olmadan çalışabilir (aşağıdaki "Bu Mac'te Apple Intelligence" bölümüne bakın). Ya da maliyetleri sizin hesabınıza yansıyan kendi sağlayıcınızı kullanın: AWS hesabınızdaki Amazon Bedrock, Claude API, Gemini veya OpenAI uyumlu bir hizmet (aşağıdaki "Diğer yapay zekâ sağlayıcıları" bölümüne bakın).

### Amazon Bedrock

1. AWS konsolunda Bedrock'u etkinleştirin ve seçilen modeli kullanabildiğinizden emin olun. Varsayılan model Claude Haiku 4.5'tir; bir Anthropic modelini ilk kez kullandığınızda bir kereye mahsus bir kullanım amacı formu doldurursunuz.
2. `bedrock:InvokeModelWithResponseStream` izni verilmiş bir AWS profili kullanın: `~/.aws/credentials` içindeki statik anahtarlar ya da geçici kimlik bilgileri alan bir profil (`credential_process`, bir rol, SSO; aşağıdaki "AWS profilleri" bölümüne bakın).
3. "AllInOneIME Settings"i açın: onu Spotlight'ta veya Uygulamalar klasöründe bulabilir ya da menü çubuğundaki giriş yöntemi simgesi → "Settings…" yoluyla açabilirsiniz. Profili, bölgeyi ve modeli seçin ve "Test Connection" (bağlantıyı sına) düğmesine tıklayın. Ayarlar penceresinin üstündeki "Language" (dil) İngilizce veya Çince olabilir; varsayılan olarak ("System") sistemi izler (sistemin tercih edilen dillerinde Çince İngilizceden önce geliyorsa Çince, aksi hâlde İngilizce). Ayarlar penceresi, aday panelindeki ipuçları ve giriş menüsü buna uyar. Ayarlar Assistant sayfasında açılır: ayarları tarif ederek değiştirme ve sorunları denetleme (aşağıda Settings → Assistant'a bakın).

<img src="../en/settings.png" width="420" alt="Ayarlar penceresi">

#### AWS profilleri

AWS CLI'ın size bir şey sormadan kullanabildiği her profil çalışır; `~/.aws/config` ve `~/.aws/credentials` içinden (ya da kabuğunuzda `AWS_CONFIG_FILE` ve `AWS_SHARED_CREDENTIALS_FILE` değişkenlerinin gösterdiği dosyalardan). Bir profil içinde, AWS CLI'ın sırasıyla, profilde bulunan bu kaynaklardan ilki kullanılır (hem `role_arn` hem de anahtarları olan bir profil roldür):

| Tür | Profilde | Yenileme |
| --- | --- | --- |
| Rol | `source_profile` ile `role_arn` (burada her tür olabilir, zincirler de; kendini adlandıran bir profil kendi anahtarlarını kullanır) ya da `credential_source = Environment`; `role_session_name`, `external_id`, `duration_seconds` | süreleri dolmadan 5 dakika önce yeniden STS `AssumeRole` ile (profilin `region` değerinde, yoksa us-east-1) |
| SSO | `sso_session` ve onun `[sso-session …]` bölümüyle `sso_account_id`, `sso_role_name` (ya da eski `sso_start_url`, `sso_region`) | süreleri dolmadan 5 dakika önce önbellekteki oturum açmanızla yeniden alınır |
| Statik anahtarlar | `~/.aws/credentials` içinde `aws_access_key_id`, `aws_secret_access_key` (ve `aws_session_token`) | her istekte yeniden okunur |
| `credential_process` | `credential_process = /usr/local/bin/my-creds --profile dev` (bir kabuk komutu gibi bölünür, kabuk olmadan, oturum açma kabuğunuzun PATH'iyle, ana klasörünüzde, en fazla 60 sn çalıştırılır) | `Expiration` değerinden 5 dakika önce yeniden çalıştırılır; yoksa AWS kimlik bilgilerini reddettiğinde |
| Statik anahtarlar | `~/.aws/config` içindeki aynı anahtarlar | her istekte yeniden okunur |

"default" profiliyle (ya da hiçbiri seçili değilken) kabuğunuzdaki anahtarlar, AWS CLI'ın aldığı gibi önce gelir: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` ve `AWS_SESSION_TOKEN`. Adını verdiğiniz bir profil onlarla asla karıştırılmaz. Kabuğunuzdaki `AWS_REGION` (veya `AWS_DEFAULT_REGION`), AWS CLI'da olduğu gibi bir profilin `region` değerine üstün gelir; ayarlardaki Region alanı ikisine de üstün gelir.

- **Otomatik:** süresi dolan kimlik bilgileri bellekte tutulur (diske asla yazılmaz) ve süreleri dolmadan 5 dakika önce yeniden alınır; 10 dakikadan az kaldığında bir istek onları kullanır ve arka planda yenilerini alır, böylece yazma beklemez. Aynı anda gelen istekler tek bir alımı bekler. Bedrock kimlik bilgilerinin süresinin dolduğunu söylediğinde (`ExpiredTokenException` …), yeniden alınırlar ve istek bir kez daha gönderilir.
- **SSO:** AllInOneIME, AWS CLI'ın `~/.aws/sso/cache` içinde tuttuğu oturum açmayı kullanır (yalnızca okur) ve sizin yerinize oturum açamaz, çünkü bunun için bir tarayıcı gerekir. Oturumun süresi dolduğunda aday paneli "SSO sign-in expired: run aws sso login --profile X" (SSO oturumunun süresi doldu: aws sso login --profile X komutunu çalıştırın) der: bunu Terminal'de çalıştırın (ayarlarda Copy Command ve Open in Terminal vardır; Settings → Assistant komutu kopyalamanız için sunar), AllInOneIME yeni oturumu kendiliğinden alır.
- **Desteklenmeyenler:** `mfa_serial` (bir giriş yöntemi sizden MFA kodu isteyemez: `credential_process` veya SSO kullanın ya da CLI'ınızın kimlik bilgilerini önbelleğe almasını sağlayın), `credential_source = Ec2InstanceMetadata` veya `EcsContainer` (Mac'te yok) ve web identity.
- **Bilinen sınırlar:** oturum açma kabuğunuzdan yalnızca PATH ve AWS dosya değişkenleri (`AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`) gelir, `credential_process` için de (ortamının geri kalanı gelmez). AllInOneIME `sso_session` belirteçlerini yenilemez (CLI'ın yenileme belirteci kullanılmaz: SSO önbelleği yalnızca okunur), bu yüzden önbellekteki belirtecin süresi dolduğunda `aws sso login` çalıştırın (AWS CLI de onu her kullandığınızda yeniler).
- **Settings → AI Provider** her profili türüyle listeler ("dev — Role via base") ve seçili olan için kimlik bilgilerinin ne zaman dolacağını ("Role via base: credentials expire at 15:30", "SSO (signed in until 18:00)") ya da ne yapılması gerektiğini söyler. Test Connection tüm zincir boyunca taze kimlik bilgileri alır; Settings → Assistant da aynısını bildirir.
- Programlar yalnızca bir istek veya Test Connection gerektirdiğinde çalıştırılır ve AWS'den yalnızca o zaman kimlik bilgisi istenir (`sts.<region>.amazonaws.com`, `portal.sso.<region>.amazonaws.com`): profilleri listelemek için asla, Settings → Assistant için asla.

### Diğer yapay zekâ sağlayıcıları: Claude API, Gemini, OpenAI uyumlu hizmetler

AWS'ye ihtiyacınız yok: ayarlarda "AI Provider" altından birini seçin, bir API anahtarı yapıştırın, "Save" ve ardından "Test Connection" düğmesine tıklayın.

| Sağlayıcı | Varsayılan model | API anahtarı |
|---|---|---|
| Claude API | `claude-haiku-5-5` (en hızlı ve en ucuz; Sonnet 5.5 ve Opus 5.5 daha özenli ama daha yavaş ve daha pahalı) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| OpenAI uyumlu | OpenAI'ın `gpt-6-luna` modeli (veya `gpt-5.4-mini`); "Common Services…" (yaygın hizmetler) içinde DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter ve bu Mac'teki Ollama bulunur: birini seçmek temel URL'sini doldurur, ardından modelini girin | Hizmetin anahtarı; "Base URL"yi onun adresine ayarlayın, ör. `https://api.deepseek.com/v1` ya da bu Mac'teki Ollama için `http://localhost:11434/v1` |

- API anahtarları yapılandırma dosyasında değil, her zaman sistem anahtar zincirinde tutulur. Orada yoksa kabuğunuzdaki `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (veya `GOOGLE_API_KEY`) ve `OPENAI_API_KEY` kullanılır.
- API anahtarı satırı bir anahtarın ayarlı olup olmadığını söyler: "✓ Saved · ends in a1b2" (kaydedildi · a1b2 ile biter: son 4 karakteri, gösterilmek için anahtarın kendisi okunmasın diye onunla birlikte saklanır) yanında Replace… (değiştir) ve Remove… (kaldır), kabuğunuzdaki bir anahtar için "✓ From $OPENAI_API_KEY" ($OPENAI_API_KEY içinden) ya da yapıştırma alanıyla birlikte "No API key yet" (henüz API anahtarı yok).
- "Thinking" (düşünme) varsayılan olarak düşüktür: giriş yöntemi her cümlede bekler ve daha az düşünme daha hızlıdır. Bunu desteklemeyen modeller için "Not set" (ayarlanmamış) seçin.
- Claude Opus 5.5 veya Sonnet 5.5 seçiliyken istekler Claude API'nin ret yedeğini (`fallbacks: "default"`) taşır: bir güvenlik sınıflandırıcısı isteği reddettiğinde sunucu başka bir modelle yeniden dener.
- Yapılandırma dosyasında: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`) ve `anthropic`, `gemini` ve `openai` altında `model`, `baseURL`, `effort` ve `temperature` (ayarlanmamış olanlar varsayılanları kullanır).

### Bu Mac'te Apple Intelligence (macOS 26)

Apple Intelligence'ı olan bir Mac'te (Apple çip, macOS 26 veya üstü, Sistem Ayarları → Apple Intelligence ve Siri bölümünde açık), "AI Provider" altında "Apple Intelligence (on this Mac)" seçeneğini seçin: anahtar yok, ücret yok ve yazdığınız hiçbir şey Mac'ten çıkmaz. macOS'a yerleşik modeli (Foundation Models çerçevesi) kullanır; diğer sağlayıcılarla aynı talimatlar ve yanıt biçimiyle, ama yalnızca cümlenin kendi dilinde yazılmış örneklerle (küçük bir model bir örneğin dilini fazla kolay kopyalar).

- Küçük bir modeldir: bağlamı yaklaşık 4K token'dır (macOS 27'de 8K), bu yüzden uzun bir paragraf ona fazla gelebilir; ayrıca daha az dil konuşur (İngilizce, Çince, Japonca, Korece, Fransızca, Almanca, İspanyolca ve birkaç dil daha; Hintçe değil). Her iki durumda da bunu söyler. Sonuçları bulut modellerinin gerisindedir ve olgular ile kod hakkındaki `@question` yanıtları çoğu zaman yanlıştır.
- Kullanılamadığı yerde nedeniyle birlikte soluk gösterilir (bu Mac'te desteklenmiyor, kapalı, model hazır değil) ve ayarlar Sistem Ayarları → Apple Intelligence ve Siri bölümüne bağlantı verir. macOS 26'dan önce listede yer almaz.
- "Model Settings" altındaki "Output tokens", sıcaklık ve zaman aşımı ona da uygulanır. Yapılandırma dosyasında: `"provider": "apple"`.

### Hassas bilgileri gizleme (yeni)

Settings → AI Provider → Privacy → "Hide sensitive information before sending" (göndermeden önce hassas bilgileri gizle; varsayılan olarak kapalı): bir istek yapay zekâya gitmeden önce, metninizde bulduğu şeyler Mac'te `[EMAIL_1]` gibi yer tutucularla değiştirilir (aynı değer, aynı yer tutucu) ve sonuçlar gösterilmeden veya eklenmeden önce gerçek değerleri geri alır. Panel "2 items hidden from the AI" (2 öğe yapay zekâdan gizlendi) der. Her tür kapatılabilir:

| Tür | Örneğin | Yapılandırmada |
| --- | --- | --- |
| E-posta adresleri | `bob@example.com` | `emails` |
| Telefon numaraları | `+1 (555) 123-4567`, `138 0013 8000` | `phones` |
| Ödeme kartı numaraları (Luhn ile doğrulanmış) | `4111 1111 1111 1111` | `cards` |
| API anahtarları ve token'lar | `sk-` veya `ghp_` gibi bilinen önekler, uzun rastgele dizeler | `keys` |
| IP adresleri | `203.0.113.42`, `2001:db8::1` | `ips` |
| Kendi sözcükleriniz, büyük/küçük harf fark etmeksizin | `Project Atlas` gibi bir kod adı, bir ad | `customWords` |

- `@improve`, `@translate`, `@question`, talimat komutlarınız ve talimat eklentileriniz ile bunların sonuçlarının iyileştirilmesi (aynı yer tutucular) için, AllInOneIME Cloud ve Apple Intelligence dahil her sağlayıcıda geçerlidir. Gizlenecek bir değer içeren jargon listesi girdileri gönderilmez.
- Biçimli değerleri tanır; adları veya adresleri tanıyamaz, bu yüzden onları kendi sözcükleriniz olarak ekleyin. `@agent`, bir web sitesinden veri getiren (`@stock`) veya bir siteyi açan (`@x`) eklentiler ve betik uzantıları metni yazıldığı gibi gönderir. Daha fazlası Gizlilik bölümünde.
- Yapılandırmada: `"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`.

Tüm ayarlar `~/.config/allinoneime/config.json` içinde saklanır; bir değişiklikten sonra bir sonraki çeviri yeni ayarları kullanır, yeniden başlatma gerekmez. Daha yeni anahtarlar:

| Anahtar | Ne yapar | Varsayılan |
|---|---|---|
| `inputLanguages` | Giriş dilleri, birden beşe kadar, ilki varsayılandır: `"en"` İngilizce, `"zh"` Çince (pinyin), `"fr"` Fransızca, `"ko"` Korece, `"hi"` Hintçe, ör. `["en", "zh"]`, `["fr", "en", "ko"]`. Çince, Korece ve Hintçe, paketleri kurulduktan sonra çalışır | `["en"]` (yeni kurulum) |
| `keyboardLayouts` | Bir giriş dilinin yazdığı klavye düzeni, dil koduna göre (şimdilik yalnızca Fransızca): `{"fr": "com.apple.keylayout.French-PC"}` | Fransızca: `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | `@translate`'in sırayla çevirdiği diller: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | `@improve` çeviri de yapar (`@translate @improve` gibi) | `false` |
| `voiceInput` | Konuşmak için sağ ⌥'yi basılı tutma | `true` |
| `actionKey` | Eylem tuşu: `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Space), `"space"` (Space) | `"enter"` |
| `uiLanguage` | Arayüz dili (ayarlar penceresi, aday paneli ipuçları, menü): `"zh"`, `"en"` | `null` (sistemi izle) |
| `rewriteStyles` | Yeniden yazma stilleri: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, ör. `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | Kendi jargon listesi dosyanız | `null` (yani `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | Menü çubuğu simgesi ve açılır paneli | `true` |
| `candidateLayout` | Pinyin ve Hintçe adayları: `"vertical"` (alt alta) veya `"horizontal"` (yan yana; ← → seçer, ↑↓ sayfa çevirir) | `"horizontal"` |
| `fuzzyPinyin` | Bulanık pinyin çiftleri: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | @ komutları alanda seçili metin üzerinde çalışır (bkz. Seçili metin üzerinde) | `true` |
| `checkForUpdates` | Günde bir kez arka planda yeni sürüm arar; siz tıklamadıkça hiçbir şey kurulmaz | `true` |
| `agent` | `@agent`'ın metni devrettiği kodlama ajanı (Settings → Agent): `claude` (Claude Code), `gemini` (Gemini CLI), `kiro` (Kiro CLI) veya `custom` | `claude` |
| `agentCommand` | Özel ajanın komutu; yazdığınız son argüman olarak eklenir, örneğin `["muse", "--"]` | `[]` |
| `claudeInBackground` | Claude Code ile `@agent` arka planda çalışır ve size bildirir (diğer ajanlar her zaman Terminal'de açılır) | `true` |
| `rememberQuestions` | Son 5 `@question` sorunuzu ve yanıtlarını bu Mac'te saklar, `@question` altında listeler (bkz. Son sorular) | `true` |
| `questionRounds` | Bir `@question` sohbetinin, başka yerde sürdürmeyi önermeden önce panelde süreceği tur sayısı, 2–10 | `5` |
| `questionContinueIn` | Bir `@question` sohbetinin sürdürülebileceği yerler, sırayla, ilki varsayılan: `agent` (`@agent`'ın işi devrettiği ajan, o ajanın kendi girdisinin yerine), `claudeCode`, `geminiCLI`, `kiroCLI`, `customAgent` (ajanlar, her biri yalnızca kuruluysa), `claudeWeb`, `chatgpt`, `gemini`, `copy` | `agent`, kurulu diğer ajanlar, Claude, ChatGPT, kopyala |
| `appProfiles` | Bir uygulamanın ayarları, paket kimliğine göre, her biri isteğe bağlı: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI` (bkz. Uygulamaya özel ayarlar) | `{}` |
| `redaction` | Hassas bilgileri yapay zekâdan gizler (bkz. Gizlilik): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`; her algılayıcı (`emails`, `phones`, `cards`, `keys`, `ips`) `false` yapılmadıkça açıktır | `enabled: false` |

## Gizlilik

- Yazma (İngilizce ve pinyin) ve `@calculator` eklentisinin hesaplamaları tamamen yereldir. Yalnızca `@improve`, `@translate` veya `@question` üzerinde eylem tuşuna bastığınızda o cümle seçtiğiniz yapay zekâ sağlayıcısına (kendi Bedrock'unuz ya da anahtarını eklediğiniz hizmet) gönderilir. "Jargon" işaretliyse ve bir jargon listesi ayarlanmışsa, liste de onunla birlikte gönderilir. Sonuçları iyileştirmek (sonuçlardan sonra yazılan bir talimat, ardından ⇧⏎) aynı isteği gösterilen sonuçlar ve talimatınızla yeniden gönderir; bir ek soru (⇧⏎) o ana kadarki sohbeti de birlikte gönderir.
- Settings → Assistant, yalnızca Preview'a ya da bir soruyla Check'e bastığınızda bir modele metin gönderir: bu Mac'te mevcutsa Apple Intelligence'a (hiçbir şey Mac'ten çıkmaz), değilse sağlayıcınıza. Bir istek, cümlenizi (içine yazılmış bir anahtar önce çıkarılır) değiştirebileceği ayarların mevcut değerleriyle gönderir: asla bir anahtar ya da yapay zekâdan gizlediğiniz sözcükler değil (yalnızca sayıları), AWS profillerinizin adları da yalnızca cümle AWS ya da Bedrock hakkındaysa. Bir soru, maskelenmiş denetim sonuçlarıyla gönderilir: `~` ötesinde yol yok, anahtar yok, günlük satırları sabit ifadeler olarak. Hassas bilgileri gizleme ikisine de uygulanır. Denetimler tek başına hiçbir şey göndermez; Check ayrıca Test Connection isteğini gönderir, o da yalnızca sağlayıcının denenecek bir anahtarı ya da kimlik bilgileri varsa.
- Bir `@question` sohbetini başka bir yerde sürdürmek (son turdan sonra ⌘1 … ya da ⌘⏎) onu, yazdığınızla birlikte, seçtiğiniz hizmete gönderir: bu Mac'teki bir kodlama ajanı (Claude Code, Gemini CLI, Kiro CLI ya da kendinizinki; her biri kendi hesabı ve hizmetiyle), claude.ai, chatgpt.com veya gemini.google.com; web adresinde ya da pano üzerinden. Sohbet gördüğünüz gibi gider: yapay zekâ isteklerinden gizlenen değerler (aşağıya bakın) içinde olduğu gibi yer alır, çünkü onu oraya göndermeyi siz seçersiniz. Siz birini seçene kadar hiçbir şey hiçbir yere gitmez; "Copy the conversation" onu yalnızca panoya koyar.
- AllInOneIME Cloud ile cümle, geliştiricinin sunucusu üzerinden bir model sağlayıcısına (şu anda OpenRouter aracılığıyla) gider: sunucu yalnızca sayıları tutar, metni asla tutmaz. Oturum açmak yalnızca e-posta adresinizi saklar.
- Hassas bilgileri gizleme (Settings → AI Provider → Privacy, varsayılan olarak kapalı): herhangi bir istek çıkmadan önce (`@improve`, `@translate`, `@question`, talimat komutlarınız ve talimat eklentileriniz, AllInOneIME Cloud dahil her sağlayıcıda), e-posta adresleri, telefon numaraları, ödeme kartı numaraları (Luhn ile doğrulanmış), API anahtarları ve token'lar (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…` ve uzun rastgele dizeler), IP adresleri ve kendi sözcükleriniz (bir kod adı, bir ad) Mac'te `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]` gibi yer tutucularla değiştirilir; aynı değer aynı yer tutucuyu alır. Modelin sonuçları gösterilmeden veya eklenmeden önce gerçek değerleri geri alır ve panel "2 items hidden from the AI" der. Yer tutucusu model tarafından tanınmayacak kadar değiştirilmiş bir sonuç yazıldığı gibi gösterilir ve "⚠ placeholder changed" ile işaretlenir. Gizlenmiş bir değer içeren jargon listesi girdileri gönderilmez. Her tür kapatılabilir. Tam genişlikli biçimler (`zhang＠example.com`, `１３８…`) de bulunur ve bir değer veya ifade bir satır sonuyla bölünmüş olabilir. E-postalar, numaralar ve anahtarlar gibi biçimli değerleri tanır; adları veya adresleri (bunları kendi sözcükleriniz olarak ekleyin) ve başka alfabelerdeki benzer görünen harfleri tanıyamaz. Yapay zekâ hizmetinize giden isteklere uygulanır; `@agent`, bir web sitesinden veri getiren (`@stock`) veya bir siteyi açan (`@x`) eklentiler ve betik uzantıları metni yazıldığı gibi gönderir. Yapılandırmada: `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- Ses yalnızca sağ ⌥'yi basılı tuttuğunuz sürece kaydedilir ve Mac'te tanınır; tanınan metin yalnızca yukarıdaki komutlarda, eylem tuşuna bastığınızda gönderilir.
- Giriş yöntemi pano metnini yalnızca bir komutta ⌃V veya ⌘V'ye bastığınızda, bir kez okur; parola yöneticilerinin gizli olarak işaretlediği içerik okunmaz. Metin önce komutta gösterilir ve yine yalnızca eylem tuşuna bastığınızda gönderilir. Son macOS sürümleri, AllInOneIME'nin panoyu okuyup okuyamayacağını sorar: izin verin. Her seferinde sorulmasını önlemek için "System Settings → Privacy & Security" içinde AllInOneIME'nin yapıştırma iznini her zaman izin ver olarak ayarlayın.
- Parola alanlarında macOS kendi klavyesine (U.S. veya ABC) geçer ve alandan ayrıldığınızda geri döner. Yazdığınız uygulama güvenli girişi tuttuğu her durumda AllInOneIME metin oluşturmaz ve kayıt yapamaz: tuşlar yazıldığı gibi girer. Sistem güvenli giriş durumundayken de (parola alanları, Terminal'in "Secure Keyboard Entry" özelliği vb.) yapay zekâya hiçbir şey gönderilmez.
- `@note` ve `@reminder` yapay zekâya gitmez: AllInOneIME metni yalnızca bu Mac'teki Notes ve Reminders'a verir ve anımsatıcının zamanını da Mac'te okur (bu uygulamaların onu diğer aygıtlarınızla eşzamanlayıp eşzamanlamadığı, iCloud gibi hesaplarına bağlıdır). Bu yüzden güvenli giriş sırasında da çalışırlar.
- `@reportissue` (ve "Report an Issue…") kendisi hiçbir şey göndermez: tarayıcınızda GitHub'ın yeni issue sayfasını, yazdığınız başlık ve yukarıda listelenen sürümler, diller, sağlayıcı türü ve sayılarla açar; bunlar önce aday panelinde gösterilir. Orada Submit'e tıklamadıkça GitHub'a hiçbir şey ulaşmaz.
- `@open` yalnızca bu Mac'te arar. Onunla açtıklarınızı (son 200) önce listelemek için, giriş yönteminin kendi tercihlerinde (config.json'da değil) hatırlar.
- Settings → Apps içindeki "Add App…" için giriş yöntemi, yazdığınız son 12 uygulamanın paket kimliklerini kendi tercihlerinde saklar; onlarla ilgili başka hiçbir şeyi saklamaz.
- `@question`, son 5 sorunuzu yanıtları ve ne zaman sorulduklarıyla birlikte yalnızca bu Mac'te, `~/Library/Application Support/AllInOneIME/recent-questions.json` içinde (yalnızca kullanıcı hesabınız okuyabilir) hatırlar ve bunları `@question` altında listeler; kayıtlı bir yanıt oradan, internete çıkmadan gösterilir. Güvenli giriş açıkken hiçbir şey saklanmaz ve seçili metin üzerine sorulan sorular hiç saklanmaz (yanıtları seçimle ilgilidir ve seçim diske yazılmış olurdu). "Remember recent questions" özelliğini Settings → General içinden kapatmak soruları da siler; Settings → Assistant ile kapatmak (yapılandırmada `rememberQuestions`) onları korur, böylece tam olarak geri alınabilir. "Clear" onları siler.
- Notlarınızı listelemek için menü çubuğu paneli, `@note` ile kaydedilen son 30 notun kimliğini ve ilk satırını (en fazla 80 karakter) giriş yönteminin kendi tercihlerinde tutar; panel kapalıyken de.
- `@py` ve `@js` yalnızca eylem tuşuna bastığınızda ve yalnızca kendiniz yazdığınız veya yapıştırdığınız kodla çalışır: yapay zekânın yanıtları ve diğer komutların çıktısı asla kod olarak çalıştırılmaz. `@py`, Mac'inizin `python3`'ünü kullanır; bu, Terminal'de olduğu gibi dosya okuyup yazabilir ve internete çıkabilir; `@js` dosya okuyamayan, ağa erişemeyen ve başka programlar çalıştıramayan ayrı bir süreçte çalışır. İkisi de güvenli giriş sırasında çalışmaz.
- Güncelleme denetimi: günde bir kez ("Check for updates automatically" kapalı değilse) AllInOneIME https://allinoneime.com/update.json dosyasını ve imzasını indirir; istek hiçbir tanımlayıcı ve yazdığınız hiçbir şeyi içermez. Bir güncelleme, GitHub sürümünden, yalnızca Update'e tıkladığınızda indirilir.
- Uzantı kaynakları: git, Mac'inizde, sizin adınıza, yalnızca eklediğiniz kaynaklar için çalışır: kendi kendine denetlenen kaynaklar için günde bir kez fetch (sabitlenmiş bir kaynak için hiç), ve Check Now, Update veya Re-clone'a tıkladığınızda. Yalnızca deponun ana makinesiyle, kendi git ve SSH kurulumunuzla oturum açarak konuşur; yazdığınız hiçbir şey onunla birlikte gitmez.
- Günlükler yazdıklarınızı kaydetmez. macOS her üçüncü taraf giriş yöntemi için "The developer can access anything you type with this input source" (geliştirici, bu giriş kaynağıyla yazdığınız her şeye erişebilir) uyarısını gösterir; bu genel bir sistem uyarısıdır.

## Geliştirme

```sh
make test         # unit tests, plus tests that run the real Rime engine
make pack         # the Chinese language pack: build/packs/zh-pinyin-<version>.tar.xz, its sha256, its packs.json entry
make packs        # all the language packs: Chinese, and Korean and Hindi from Core/LanguagePacks/ (ko-hangul, hi-phonetic)
make selftest     # drives the input method through a simulated text field: real Bedrock calls, plus on-device recognition tested with synthesized speech
make realtest     # types into a real app's text field (needs the screen unlocked; takes over the foreground for about 1 minute)
make screenshots  # regenerates the screenshots in docs/
make cli && .build/release/allinoneime-cli --styles concise,jargon "this is a blocker bug your team need fix it asap"   # try polishing and rewrites in the terminal
make icon         # regenerates the app icon and the menu bar icon from Resources/AppIcon.png
make dmg          # the release installer, build/AllInOneIME-<version>.dmg (universal; signed if there's a Developer ID certificate, optionally notarized), and the in-app update, build/AllInOneIME-<version>-update.zip
make update-test  # the in-app updater end to end: a temporary install, a test server on 127.0.0.1, a test key (never the installed app)
```

`make selftest` ve `make realtest` ayarlarınıza bağlı değildir. Öz sınama kendi yapılandırmasını kullanır (AWS profili ve bölgesi sizinkinden alınan Amazon Bedrock, geri kalan her şey varsayılan); gerçek uygulama sınaması çalışırken sağlayıcıyı Bedrock'a ayarlar ve sonra sizinkini geri koyar. O an denetleyemedikleri başarısız sayılmaz, atlanır: o profil için kimlik bilgisi olmadan canlı Bedrock denetimleri ve güvenli giriş açıkken (ekran kilitli, bir parola alanı) yazılan her şey. Son satır geçen, başarısız olan ve atlanan denetimleri sayar; çalıştırmayı yalnızca başarısızlıklar başarısız kılar, atlananı olan bir çalıştırma INCOMPLETE ile, yazan hiçbir şey çalışmadıysa SKIPPED ile biter (BLOCKED: gerçek uygulama sınaması kilitli bir ekranda başladı), asla PASSED ile bitmez.

Kod düzeni:

- `Core/Sources/AllInOneIMECore`: Bedrock istemcisi, SigV4, istemler (prompt'lar), iki düzeyli giriş durum makinesi (@ komutları ve ses hareketi dahil); AppKit bağımlılığı yok
- `Core/Sources/AllInOneIMERime`: librime sarmalayıcısı
- `Sources/AllInOneIME`: InputMethodKit giriş yöntemi, aday paneli, ayarlar penceresi, konuşma tanıma
- `Sources/AllInOneIMESettings`: "AllInOneIME Settings" başlatıcısı
- `Sources/AllInOneIMEInstaller`: disk görüntüsündeki "Install AllInOneIME": kurar, günceller ve kaldırır

Dil paketlerinin eklentilerden ayrı kendi kitaplığı vardır: [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages) deposu; https://languages.allinoneime.com/ adresinden sunulur ve kendi anahtarıyla imzalanır. `make pack` arşivi oluşturur; arşiv orada bir sürüm dosyası (release asset) olarak yayımlanır (`zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>` sürümleri) ve `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` oraya `packs.json` yazar ve onu anahtar zincirindeki dil paketleri anahtarıyla (`allinoneime-languages-signing`) `packs.json.sig` olarak imzalar. Uygulama https://languages.allinoneime.com/packs.json dosyasını okur, imzayı, ardından arşivin boyutunu ve SHA-256'sını denetler. Bir paketi yerel bir sunucudan denemek için: `--test-key` bir test anahtarıyla imzalar ve `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Bir sürüm yayımlama (uygulama içi güncelleyici, yayınların kendi anahtarıyla imzalanmış https://allinoneime.com/update.json dosyasını okur):

1. Sürümü yükseltin (`AppVersion.swift` ve üç Info.plist; `AppVersionTests` bunların uyuştuğunu denetler) ve değişiklik günlüklerini güncelleyin.
2. `make dmg NOTARY_PROFILE=<profile>`: `.sha256` dosyasıyla birlikte `build/AllInOneIME-<version>.dmg` ve `build/AllInOneIME-<version>-update.zip` (disk görüntüsündeki yükleyicinin taşıdığı biçimde iki uygulama). Uygulamalar ve görüntü, anahtar zincirindeki Developer ID Application sertifikasıyla imzalanır; görüntü o `xcrun notarytool` anahtar zinciri profiliyle onaylanır ve zımbalanır (stapled).
3. İkisini de GitHub'daki `v<version>` sürümüne yükleyin ve yayımlayın.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"` (her biri bir iki cümle): `site/public/update.json` dosyasını yazar (uygulamalardan okunan sürüm, derleme ve en düşük macOS sürümü, dosyanın adresi, boyutu ve SHA-256'sı, sürüm notlarının adresi ve özet) ve onu giriş anahtar zincirindeki anahtarla `update.json.sig` olarak imzalar (`allinoneime-releases-signing`; macOS erişime izin vermenizi isteyebilir). İkisini de commit edin.
5. Siteyi yayına alın (`cd site && npx wrangler@4 deploy`), ancak sürümün dosyaları indirilebilir olduktan sonra: uygulamalar günde bir kez bakar ve `AllInOneIME --check-update` onların ne gördüğünü gösterir.

Uygulama, manifesti okumadan önce imzasını içine yerleşik açık anahtarla denetler, daha yeni olmayan bir sürümü asla kurmaz, yalnızca https üzerinden allinoneime.com'dan veya deponun GitHub sürüm dosyalarından indirir ve arşivi ancak boyutu ile SHA-256'sı manifestle eşleştiğinde, iki uygulamanın paket kimlikleri, sürümleri ve kod imzaları doğrulandığında ve yeni giriş yöntemi başladığında kurar. Ardından giriş yöntemi işi yardımcı olarak kendi çalıştırılabilir dosyasına devreder (`--apply-update`); yardımcı onun kapanmasını bekler, uygulamaları yükleyicinin yaptığı gibi değiştirir (eskiler kenara alınır, bir şey başarısız olursa geri konur) ve yenisini kaydeder. Yerel bir sunucuyla denemek için: `make update-test` ya da `Scripts/build-update-manifest.swift` ile `--test-key` ve `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`.

Paket kimliği (bundle ID) hâlâ `com.aipinyin.inputmethod.AIPinyin`: macOS onu eklenen giriş kaynağını ve mikrofon iznini hatırlamak için kullanır; bu yüzden değiştirmek, giriş yöntemini yeniden eklemek ve izni yeniden vermek anlamına gelir.

## Lisans

Copyright © 2026 MicroZ LLC. Kaynak kodu [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2) altında erişilebilirdir: rakip bir ürün dışında her amaçla kullanın, okuyun, değiştirin ve paylaşın. Her sürüm, yayımlanmasından iki yıl sonra Apache-2.0 olur. 0.6.1'e kadarki sürümler GPL-3.0 altında yayımlandı ve bu lisansla erişilebilir olmaya devam eder.

Üçüncü taraf bileşenler (BSD-3-Clause altındaki librime ve eklentileri; GPL-3.0 altındaki rime-ice'ın Lua betikleri ve Çince dil paketi) [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) dosyasında listelenmiştir.
