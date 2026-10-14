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
> AllInOneIME henüz Apple tarafından onaylanmadı (notarize edilmedi): ilk seferde "System Settings → Privacy & Security → Open Anyway" (Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç) bölümünden izin verin. Yalnızca [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) veya [allinoneime.com](https://allinoneime.com) üzerinden indirin.

Her metin alanında yapay zekâ komutları sunan bir macOS giriş yöntemi. Bir cümleye `@` ile başlayın ve bitince ⏎ tuşuna basın: `@improve` yazdığınızı düzeltip cilalar ve birkaç yeniden yazım önerir, `@translate` seçtiğiniz dillere çevirir, `@question` bir soru sorar, `@claude` işi Claude Code'a devreder, `@open` ise dosya ve uygulama bulur ya da bir web adresi açar. Sağ ⌥ tuşunu basılı tutup konuşabilirsiniz de. `@` olmadan tuşlarınız her zamanki gibi uygulamaya gider. Ayrıca Çince (pinyin, Rime ve rime-ice üzerine kurulu), Fransızca, Korece (Hangul) ve Hintçe (Latin harflerinden Devanagari) yazar ve kendi betiklerinizi @ komutları olarak çalıştırır.

![@improve ve özensiz bir cümle, ardından ⏎: cilalanmış sürümler ve yeniden yazımlar](../en/improve.png)

Daha fazla ayrıntı için (tüm komutlar ve ayarlar, kurulum sorunlarını giderme, gizlilik) [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki)'ye bakın. [Weijian Zhang](https://weijianz.com) tarafından MicroZ LLC'de geliştirildi.

## Nasıl kullanılır

`@` olmadan araya girmez: İngilizcede harfler doğrudan yazılır ve ⏎ Return'dür; hiçbir şey internete gitmez. Yeni bir kurulum İngilizce yazar; Çince (pinyin), Fransızca, Korece veya Hintçe de yazmak için dili ayarlardan ekleyin (bkz. [Giriş ve çeviri](#giriş-ve-çeviri)).

| Tuş | Ne yapar |
|---|---|
| Pinyin yazma, Boşluk / rakamlar | Çince modunda: her pinyin giriş yönteminde olduğu gibi sözcük seçer |
| `@` (cümlenin başında) | Komut listesini açar: son zamanlarda en çok kullanılanlar önce, bir seferde 5 tane, ↑↓, fare tekerleği veya izleme dörtgeniyle kaydırılır; ya da birini bulmak için harf yazın (önce bu harflerle başlayan adlar, sonra bunları içerenler). ⏎, Tab, Boşluk veya bir rakam seçer |
| ⏎ | Komutu çalıştırır. Pinyin henüz seçilmemiş olsa da çalışır: Boşluk'ta olduğu gibi önce o seçilir |
| Boşluk, ⏎ / rakamlar | Sonuçlar göründüğünde: vurgulananı / o numaralıyı ekler; 0 orijinal metindir |
| ⌘C | Vurgulanan sonucu kopyalar (`@open` için yolu); aday paneli açık kalır |
| ⌃V | Bir komutta (ör. `@improve ` sonrasında): pano metnini uygulamaya yapıştırmak yerine yazdığınızın sonuna ekler. Birden çok satır tek satır olur, bir seferde en fazla 2000 karakter (`@note` satır sonlarını korur ve 20000'e kadar alır). Her uygulamada çalışır; komut yokken tuş her zamanki gibi uygulamaya gider |
| ⌘V | ⌃V gibidir, ancak bazı uygulamalar ⌘V'yi kendileri işler (Ghostty, iTerm2 ve Terminal gibi terminaller ile Notes) ve her zamanki gibi uygulamaya yapıştırır; oralarda ⌃V kullanın |
| Esc, ⌫ | Düzenlemeye devam etmek için cümleye döner; yazmaya devam etmek cümleyi sürdürür |
| Shift'e dokunma | Birden fazla giriş dili varsa: sıralarına göre bir sonrakine geçer (İngilizce → Çince → Fransızca → …, sonra yeniden ilkine) |
| Sağ ⌥'yi basılı tutma | Konuşun, bitirmek için bırakın. Yazdığınız dilde (İngilizce, Çince, Fransızca, Korece veya Hintçe). Bir komutta metin komutun arkasına gelir; aksi hâlde doğrudan eklenir |

## @ komutları (beta)

| Komut | Ne yapar |
|---|---|
| `@improve` | Cilalar: 1–3 cümlenin kendi dilinde üç sürümdür, 4 ve sonrası yeniden yazım stilleridir (ayarlardan eklenir ve sıralanır), 0 orijinal metindir. Çeviri yapmaz; "@improve also translates" (@improve çeviri de yapar) açıkken `@translate @improve` gibi çalışır |
| `@translate` | Eklediğiniz dillere çevirir (ayarlar → "Translate", sıralamak için sürükleyin), her dil için bir satır, tek dil varsa üç sürüm; cümlenin kendi dili atlanır. `@translate @improve` birlikte tek istekte hem çevirir hem yeniden yazar |
| `@question` | Bir soru sorar; yanıt adaylarda görünür, ⏎ veya Boşluk ekler, ⌘C kopyalar |
| `@claude` | Görevi Claude Code'a devreder: varsayılan olarak arka planda, bitince bir bildirimle (oturumu Terminal'de açıp devam etmek için bildirime tıklayın), ya da `@tasks`'a bakın. Kendi Claude Code'unuzu (`claude` komutu) kendi oturum açma bilgileri ve ayarlarıyla kullanır. Eskisi gibi Terminal'de açılması için ayarlarda "@claude runs in the background" (@claude arka planda çalışır) seçeneğini kapatın. Terminal'i ilk kez açtığında macOS, AllInOneIME'nin Terminal'i denetleyip denetleyemeyeceğini sorar: OK'e tıklayın |
| `@tasks` | Arka plandaki Claude görevlerini (çalışıyor / bitti / sizi bekliyor) son yanıtlarıyla listeler; ⏎ birini Terminal'de açar, ⌘C yanıtı kopyalar |
| `@settings` | Ayarlar penceresini hemen açar (seçmek yeterli) |
| `@open` | Siz yazdıkça eşleşen dosyaları, klasörleri ve uygulamaları listeler (Spotlight). Boşlukla ayrılmış birden fazla anahtar sözcük kullanılabilir: her biri yolda, en az biri adda geçmelidir (standart bir klasörün adı, içindekiler için de geçerlidir: `downloads pdf` İndirilenler'deki PDF'leri bulur). Uygulamalar ve standart klasörler Çince adlarıyla da bulunur ve Çince arayüz onları bu şekilde gösterir. Önce `@open` ile açtıklarınız gelir, sonra uygulamalar ve bu klasörler, sonra son kullanılan veya değiştirilen dosyalar; adlar iki veya daha az dosya bulduğunda ve bu türden hiçbir uygulama ya da klasör bulmadığında, ana klasörünüzdeki dosyalar içeriklerine göre de aranır ve bu satırlar "content" olarak işaretlenir; başka hiçbir şey yoksa ⏎ ilkini açmak yerine onları seçmeniz için listeler. Bir web adresiyle (`github.com`, `localhost:3000`, `https://…`) ilk satır "open in the browser" (tarayıcıda aç) olur ve içerikler aranmaz; tam olarak bu adı taşıyan bir dosya (örneğin `MANIFEST.in`) önce gelir. `~/` veya `/` ile başlayan metin bir yoldur: Tab onu tamamlar ve klasörlerin içine girer; ⏎ açar, ⌘C yolu kopyalar |
| `@note` | Metni Notes (Notlar) uygulamasına, AllInOneIME adlı bir klasöre (yoksa oluşturulur) kaydeder; hiçbir şey eklenmez. Yapıştırılan metin satır sonlarını korur, en fazla 20000 karakter |
| `@reminder` | Reminders (Anımsatıcılar) uygulamasına, AllInOneIME adlı bir listeye bir anımsatıcı ekler. Zamanı metne yazın; Mac'te okunur ve bir satır neyin okunduğunu gösterir: ⏎ veya Boşluk ekler, Esc düzenlemeye döner. Saat verilirse o anda bir alarm olur; yalnızca tarih verilirse tüm gün sürer |
| `@calculate` | Bu Mac'te hesaplar; sonuç adaylarda görünür, ⏎ veya Boşluk ekler: `@calculate 23*17` → `391`. Bir cümlenin içinde de çalışır: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Bir satır Python çalıştırır (Mac'in `python3`'ü) ve sonucu ekler: kodun son ifadesinin değeri, ör. `@py 2**100`, `@py import math; math.sqrt(2)`, ya da bu yoksa yazdırdığı çıktı. `python3` yoksa sunulmaz (Xcode'un komut satırı araçlarında vardır) |
| `@js` | Bir satır JavaScript çalıştırır ve aynısını ekler: son ifadenin değeri veya `console.log`'un yazdırdığı, ör. `@js [1, 2, 3].map(x => x * 2)`. macOS'un yerleşik JavaScriptCore'unu kullanır, bu yüzden kurulacak bir şey yoktur; dosya okuyamaz, ağa erişemez ve başka programlar çalıştıramaz |
| `@imessage` | Bir iMessage gönderir: bir ad, telefon numarası veya e-posta yazın (Çince bir ad pinyin'iyle de, tam olarak ya da baş harfleriyle) ve alıcıyı aday panelinden seçin (son zamanlarda mesajlaştıklarınız önce gelir; tam bir numara veya adres de olur), ardından mesajı yazın (içindeki `@stock AAPL` gibi komutlar önce çalışır). ⏎ panelde "Send to Alex (…): message" gösterir, ⏎ tekrar gönderir, Esc düzenlemeye döner; metin alanına hiçbir şey yazılmaz. İlk seferde macOS, AllInOneIME'nin Contacts'a (Kişiler) erişip Messages'ı (Mesajlar) denetleyip denetleyemeyeceğini sorar: ikisinde de OK'e tıklayın |

Örnek: `@q` ⏎, `what is quantum computing` yazın, ⏎. `@note books to read: The Three-Body Problem` ⏎ bir not kaydeder. `@reminder call Bob tomorrow at 3pm` ⏎, okunan zamanı kontrol edin, sonra eklemek için yeniden ⏎. Komut seçildikten sonra sağ ⌥'yi basılı tutup konuşabilirsiniz de. Çince modunda `@open` ve `@calculate` o an için İngilizce harflere geçer ve işiniz bitince Çinceye döner.

`@py` ve `@js` kodu İngilizce harflerle yazılır ve tam genişlikli noktalama işaretleri (Çince modundan) ASCII'ye dönüşür; kodu tek satıra, deyimler arasına `;` koyarak yazın. Ayrı bir süreçte çalışır, 10 saniye sonra ya da herhangi bir anda Esc ile durdurulur; hata olursa hatanın ilk satırı gösterilir, ör. `ZeroDivisionError: division by zero`. Birden çok satırlı çıktı yazdırıldığı gibi eklenir; terminalde tek satır olarak girer (terminal kendisine verilen her satırı çalıştırır). Bir düzenleyicinin içindeki terminal (VS Code, Cursor, JetBrains) düzenleyicinin kendisinden ayırt edilemez, bu yüzden orada her komutun birden çok satırlı çıktısı olduğu gibi girer. İkisi de başka bir komutun cümlesinin içinde çalışır: `@reply the answer is @py 2**100`; boşluk içeren kodu tırnak içine alın: `@question explain @py "sum(x * x for x in range(10))"`. Tersi geçerli değildir: `@py` ve `@js` kodu her zaman tam yazdığınız gibi çalışır ve içindeki `@commands` önceden çalıştırılmaz.

![@ yazmak komut listesini açar; @question ve bir soru, ardından yanıt için ⏎](../en/commands.png)

![@open siz yazdıkça uygulamaları bulur; / ile başlıyorsa bir yoldur: klasör listelenir, Tab tamamlar](../en/open.png)

`@` bir komutla devam etmediğinde, `@john`'da olduğu gibi, `@` her zamanki gibi eklenir; böylece sohbet uygulamalarında kişileri @ ile anmak çalışmaya devam eder. `@question`, `@improve` ve `@translate` yalnızca eylem tuşuna bastığınızda kendi Bedrock'unuza gönderir; `@open` yalnızca bu Mac'te arar; `@note` ve `@reminder` yalnızca bu Mac'teki Notes ve Reminders'a gider; `@claude` Mac'inizde kurulu Claude Code'u (`claude` komutu) ve onun kendi hesabını kullanır ve dosyaları değiştirmeden veya komut çalıştırmadan önce her zamanki gibi size sorar. Claude Code kurulu değilse `@claude` sunulmaz. `@imessage` Contacts'u yalnızca bu Mac'te okur (adlar, telefon numaraları, e-postalar), asla yapay zekâdan geçmez ve mesajı Messages gönderir; Messages uygulaması yoksa sunulmaz.

`@calculate` bu Mac'te, çevrimdışı çalışır: `+ - * /` (ayrıca `× ÷`), üs için `^` veya `**`, parantezler, yüzde (`50%` 0.5'tir, `200*5%` 10'dur; hesap makinesinde olduğu gibi, eklenen veya çıkarılan bir yüzde kendinden öncekinin yüzdesidir: `100+10%` 110, `100-10%` 90'dır), `sqrt abs round floor ceil ln log exp sin cos tan min max pow` fonksiyonları (`log` 10 tabanlıdır, açılar radyandır, `round(x, 2)` iki ondalık basamak tutar) ve `pi` (`π`) ile `e` sabitleri. Tam genişlikli rakamlar ve işaretler de çalışır. Aritmetik ondalık olarak kesindir, bu yüzden `0.1+0.2` `0.3` eder; sonuçlar en fazla 15 anlamlı basamak içerir ve 38 basamağa kadar tam sayılar eksiksiz yazılır (`2^100` → `1267650600228229401496703205376`).

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

Raycast'in modları şöyle eşlenir: `fullOutput` → `show`, `compact` ve `silent` → `silent`, `refreshTime` ile `inline` → bir status. Protokolün tamamı [docs/extensions.md](../extensions.md) içindedir; [Examples/extensions](../../Examples/extensions) her türden birer örnek içerir. Uzantılar Mac'inizde kod çalıştırır: güvendiklerinizi kullanın. Yalnızca siz çalıştırdığınızda çalışırlar (status veya list, siz yazdıkça), güvenli giriş sırasında asla çalışmazlar ve giriş yöntemi kapandığında dururlar.

### Eklentiler

Eklentiler, herkesin ihtiyaç duymadığı şeyler için hazır `@` komutlarıdır; örneğin hisse senedi fiyatları için `@stock AAPL 600519 700`. Kurulduktan sonra her komut gibi çalışırlar; ayarlardaki "Plugins" bölümü neyin kurulu olduğunu ve her birinin metninizi nereye gönderdiğini gösterir ve onları kaldırır. Eklentiler ayrı bir süreçte çalıştırılan JavaScript'tir: yalnızca beyan ettikleri web sitelerine (HTTPS) erişebilirler, dosya okuyamaz ve başka programlar çalıştıramazlar. Ayarlarda "Plugins" altındaki "Browse Library…" (kitaplığa göz at) onları [eklenti kitaplığından](https://github.com/MicroZ-LLC/AllInOneIME-plugins) kurar: kurmadan önce bir eklentinin hangi web siteleriyle iletişim kurduğunu gösterir; kitaplığın dizini imzalıdır ve her dosya ona uymak zorundadır. Daha yeni bir sürüm "Update" (güncelle) düğmesi gösterir; hiçbir şey kendiliğinden güncellenmez. Kendi eklentileriniz `~/.config/allinoneime/plugins/` ("Open Plugins Folder") içine gider: bunlar yerel eklentilerdir ve kitaplık bunların üzerine asla yazmaz. "Bağlantı" (link) eklentileri kod çalıştırmaz: metni bir web adresine yerleştirip tarayıcıda açarlar; örneğin `@x nice weather today`, X'in gönderi oluşturucusunu metin doldurulmuş olarak açar; paylaşmak sayfada size kalır. Kitaplıkta dört tane vardır (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` döviz çevirir: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, kurun tarihiyle birlikte tek satır (kurlar ExchangeRate-API'den). Eklenti yazmak için: [docs/plugins.md](../plugins.md).

Bir şey getiren komutlar (eklentiler ve programlar) bir cümlenin içinde de çalışır: `@reply tell her @stock AAPL is up today`. İçteki komutlar önce çalışır, çıktıları onların yerini alır ve dıştaki komut sonuç üzerinde çalışır. Argüman, komuttan sonraki sözcük ile hemen arkasından gelen büyük harfli kodlar veya sayılardır (`@stock AAPL TSLA`, `@stock 600519 700`); küçük harfli bir sözcük argümanı bitirir (`@stock SNDK is good to buy` SNDK'yi arar). Tırnaklar onu tam olarak belirler: `@stock "aapl tsla"`. `@calculate` da bir cümlenin içinde çalışır; argümanı, boşluklar dahil, arkasından gelen ifadenin tamamıdır, başka metne kadar: `@reply the total is @calculate 23 * 17 dollars`. `@claude` ve terminal komutlarının içinde çalıştırılmazlar: onlar metni yazıldığı gibi alır (orada `@` yazmak komut listesini açmaz).

### Eylem tuşu

Varsayılan ⏎; ayarlarda "Action key" (eylem tuşu) altından değiştirin (yapılandırmada `actionKey`): ⏎, "Tap ⌥" (⌥'ye dokunma, iki taraftan biri: basıp hemen bırakın; sağ ⌥'yi basılı tutmak yine konuşmak içindir), ⌥Space veya Space (sözcükler seçildikten sonra Boşluk'a bir kez daha basın; İngilizce modunda iki kez). Eylem tuşu ne olursa olsun, @ komutları ⏎ ile de çalışır. ⌥Space zaten Alfred, Raycast veya benzeri bir uygulamanın kısayoluysa, önce onlar alır.

## Menü çubuğu paneli

<img src="../en/panel-swipe.png" width="520" alt="Menü çubuğu paneli: buzlu cam, kartlarda notlar, anımsatıcılar ve Claude görevleri; sola kaydırılan bir satır Remove düğmesini gösteriyor">

Menü çubuğunda AllInOneIME'nin simgesine (çerçevesiz ∞ ve imleç işareti; çerçeveli olan giriş kaynağıdır) tıklayın, panel hemen altında açılır; başka bir yere tıklamak onu kapatır:

- "Notes" (notlar): `@note` ile kaydedilen notlar, en yeni 5 tanesi; Notes'ta açmak için birine tıklayın.
- "Reminders" (anımsatıcılar): Reminders'taki AllInOneIME listesinde henüz tamamlanmamış anımsatıcılar (`@reminder` bu listeye ekler), en yakın tarihli olanlar önce, 8 tanesi gösterilir; birini tamamlandı olarak işaretlemek için daireye, Reminders'ı açmak için başlığa tıklayın.
- "Claude Tasks" (Claude görevleri): `@tasks`'ta olduğu gibi arka plandaki Claude görevleri (`@claude`'un devrettikleri), en fazla 30, bir seferde 5 tanesi gösterilir: daha fazlası için kaydırın ya da arama kutusunda başlıklarında ve yanıtlarında arayın; ilerlemeleri ve son yanıtın ilk satırıyla birlikte; Terminal'de açıp devam etmek için birine tıklayın.

Bir satırı (bir not, bir anımsatıcı veya bir görev) "Remove" (kaldır) düğmesini göstermek için iki parmakla sola kaydırın ya da hemen kaldırmak için sonuna kadar kaydırın; fareyle sağ tıklayın. Kaldırmak onu yalnızca panelden çıkarır: not Notes'ta, anımsatıcı Reminders'ta (tamamlanmamış olarak), görev Claude Code'da kalır.

Başlıkta sayılar (ör. "2 reminders · 1 task running"; sizi bekleyen görevler ayrıca sayılır, ör. "1 waiting for you") ve bir yenile düğmesi bulunur. Panel, yazdığınız uygulamadan odağı asla almaz: bir anımsatıcıyı işaretlemek veya yenilemek o uygulamayı önde bırakır; yalnızca Claude görevlerinin arama kutusu, tıklandıktan sonra klavyeyi alır. Simge varsayılan olarak gösterilir; ayarlarda "Menu Bar Panel" altından kapatın.

Neyi ve ne zaman okuduğu:

- Notlar: liste panelin kendi kaydıdır (panel kapalıyken de tutulur) ve Notes asla başlatılmaz: panel, ancak Notes zaten çalışıyorsa ve AllInOneIME'ye daha önce onu denetleme izni verildiyse, düzenlenmiş başlıklar ve silinmiş notlar için onu kontrol eder.
- Anımsatıcılar: AllInOneIME listesi panel açıldığında, her 60 saniyede bir ve anımsatıcılar değiştiğinde okunur. Panel, macOS'un kendiliğinden erişim istemesine asla yol açmaz: macOS size henüz sormadıysa "Allow Access to Reminders" gösterir ve yalnızca bu düğme sorar; hayır dediyseniz "Open System Settings" gösterir.
- Claude görevleri: panel `claude agents`'ı yalnızca açıkken çalıştırır: açıldığında bir kez, yenilendiğinde ve `@claude` bir görev devrettiğinde; ayrıca bir görev henüz bitmemişken her 15 saniyede bir, hepsi bittiğinde artık değil. Son yanıtlar bu Mac'teki Claude Code dökümlerinin (`~/.claude/projects`) sonundan ve yalnızca bir döküm değiştiğinde okunur.
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
3. Yükleyici henüz Apple tarafından onaylanmadığı (notarize edilmediği) için macOS onu kimin yaptığını doğrulayamaz ve ilk seferde "Install AllInOneIME"ı doğrulayamadığını söyler: "Done" (Bitti) düğmesine tıklayın (macOS 14'te "Cancel"), "System Settings → Privacy & Security" bölümünü açın, en alta yakın "Open Anyway" (Yine de Aç) düğmesine tıklayın ve onaylayın. Her yeni sürümün yükleyicisi bunu bir kez gerektirir.

Bundan sonra AllInOneIME etkinleşir ve giriş kaynaklarınızda yer alır; ona Ctrl+Boşluk ile geçin (🌐 tuşu yalnızca "System Settings → Keyboard" içinde "Press 🌐 key to" seçeneği "Change Input Source" olarak ayarlıysa geçiş yapar). Yükleyici onu elle eklemenizi söylerse, bu Mac programların onu etkinleştirmesine izin vermiyordur; o zaman bir kez kendiniz ekleyin: "System Settings → Keyboard → Text Input → Input Sources → Edit… → + (sol altta) → English → AllInOneIME" (Sistem Ayarları → Klavye → Metin Girişi → Giriş Kaynakları → Düzenle… → + → İngilizce → AllInOneIME) (ayarlarındaki "Input" altında Çince ekledikten sonra pinyin de yazar).

Ctrl+Boşluk sizi AllInOneIME'ye götürmüyorsa ya da bir süre sonra yeniden U.S.'ye dönüyorsa, yükleyiciyi yeniden çalıştırın: AllInOneIME'yi giriş kaynaklarınıza geri ekler.

Güncellemek için önce kaldırmadan yeni sürümün disk görüntüsünden yeniden kurun; ayarlar, jargon listesi ve öğrenilen sözcükler korunur. Yükseltmeden önce [değişiklik günlüğünü](../../CHANGELOG.md) okuyun: her sürümün değişikliklerini ve yükseltme notlarını içerir.

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

Çeviriler ve yeniden yazımlar kendi yapay zekâ sağlayıcınızı kullanır ve maliyetler sizin hesabınıza yansır: varsayılan olarak AWS hesabınızdaki Amazon Bedrock, ya da Claude API, Gemini veya OpenAI uyumlu bir hizmet (aşağıdaki "Diğer yapay zekâ sağlayıcıları" bölümüne bakın).

### Amazon Bedrock

1. AWS konsolunda Bedrock'u etkinleştirin ve seçilen modeli kullanabildiğinizden emin olun. Varsayılan model Claude Haiku 4.5'tir; bir Anthropic modelini ilk kez kullandığınızda bir kereye mahsus bir kullanım amacı formu doldurursunuz.
2. `bedrock:InvokeModelWithResponseStream` iznine sahip bir erişim anahtarı oluşturun ve onu `~/.aws/credentials` içindeki bir profile koyun. Şimdilik yalnızca bu tür statik anahtarlar desteklenir; SSO veya assume-role desteklenmez.
3. "AllInOneIME Settings"i açın: onu Spotlight'ta veya Uygulamalar klasöründe bulabilir ya da menü çubuğundaki giriş yöntemi simgesi → "Settings…" yoluyla açabilirsiniz. Profili, bölgeyi ve modeli seçin ve "Test Connection" (bağlantıyı sına) düğmesine tıklayın. Ayarlar penceresinin üstündeki "Language" (dil) İngilizce veya Çince olabilir; varsayılan olarak ("System") sistemi izler (sistemin tercih edilen dillerinde Çince İngilizceden önce geliyorsa Çince, aksi hâlde İngilizce). Ayarlar penceresi, aday panelindeki ipuçları ve giriş menüsü buna uyar.

<img src="../en/settings.png" width="420" alt="Ayarlar penceresi">

### Diğer yapay zekâ sağlayıcıları: Claude API, Gemini, OpenAI uyumlu hizmetler

AWS'ye ihtiyacınız yok: ayarlarda "AI Provider" altından birini seçin, bir API anahtarı yapıştırın, "Save" ve ardından "Test Connection" düğmesine tıklayın.

| Sağlayıcı | Varsayılan model | API anahtarı |
|---|---|---|
| Claude API | `claude-haiku-5-5` (en hızlı ve en ucuz; Sonnet 5.5 ve Opus 5.5 daha özenli ama daha yavaş ve daha pahalı) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| OpenAI uyumlu | OpenAI'ın `gpt-6-luna` modeli (veya `gpt-5.4-mini`); "Common Services…" (yaygın hizmetler) içinde DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter ve bu Mac'teki Ollama bulunur: birini seçmek temel URL'sini doldurur, ardından modelini girin | Hizmetin anahtarı; "Base URL"yi onun adresine ayarlayın, ör. `https://api.deepseek.com/v1` ya da bu Mac'teki Ollama için `http://localhost:11434/v1` |

- API anahtarları yapılandırma dosyasında değil, her zaman sistem anahtar zincirinde tutulur. Orada yoksa kabuğunuzdaki `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (veya `GOOGLE_API_KEY`) ve `OPENAI_API_KEY` kullanılır.
- "Thinking" (düşünme) varsayılan olarak düşüktür: giriş yöntemi her cümlede bekler ve daha az düşünme daha hızlıdır. Bunu desteklemeyen modeller için "Not set" (ayarlanmamış) seçin.
- Claude Opus 5.5 veya Sonnet 5.5 seçiliyken istekler Claude API'nin ret yedeğini (`fallbacks: "default"`) taşır: bir güvenlik sınıflandırıcısı isteği reddettiğinde sunucu başka bir modelle yeniden dener.
- Yapılandırma dosyasında: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`) ve `anthropic`, `gemini` ve `openai` altında `model`, `baseURL`, `effort` ve `temperature` (ayarlanmamış olanlar varsayılanları kullanır).

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
| `fuzzyPinyin` | Bulanık pinyin çiftleri: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |

## Gizlilik

- Yazma (İngilizce ve pinyin) ve `@calculate` hesaplamaları tamamen yereldir. Yalnızca `@improve`, `@translate` veya `@question` üzerinde eylem tuşuna bastığınızda o cümle seçtiğiniz yapay zekâ sağlayıcısına (kendi Bedrock'unuz ya da anahtarını eklediğiniz hizmet) gönderilir. "Jargon" işaretliyse ve bir jargon listesi ayarlanmışsa, liste de onunla birlikte gönderilir.
- AllInOneIME Cloud ile cümle, geliştiricinin sunucusu üzerinden bir model sağlayıcısına (şu anda OpenRouter aracılığıyla) gider: sunucu yalnızca sayıları tutar, metni asla tutmaz. Oturum açmak yalnızca e-posta adresinizi saklar.
- Ses yalnızca sağ ⌥'yi basılı tuttuğunuz sürece kaydedilir ve Mac'te tanınır; tanınan metin yalnızca yukarıdaki komutlarda, eylem tuşuna bastığınızda gönderilir.
- Giriş yöntemi pano metnini yalnızca bir komutta ⌃V veya ⌘V'ye bastığınızda, bir kez okur; parola yöneticilerinin gizli olarak işaretlediği içerik okunmaz. Metin önce komutta gösterilir ve yine yalnızca eylem tuşuna bastığınızda gönderilir. Son macOS sürümleri, AllInOneIME'nin panoyu okuyup okuyamayacağını sorar: izin verin. Her seferinde sorulmasını önlemek için "System Settings → Privacy & Security" içinde AllInOneIME'nin yapıştırma iznini her zaman izin ver olarak ayarlayın.
- Parola alanlarında macOS kendi klavyesine (U.S. veya ABC) geçer ve alandan ayrıldığınızda geri döner. Yazdığınız uygulama güvenli girişi tuttuğu her durumda AllInOneIME metin oluşturmaz ve kayıt yapamaz: tuşlar yazıldığı gibi girer. Sistem güvenli giriş durumundayken de (parola alanları, Terminal'in "Secure Keyboard Entry" özelliği vb.) yapay zekâya hiçbir şey gönderilmez.
- `@note` ve `@reminder` yapay zekâya gitmez: AllInOneIME metni yalnızca bu Mac'teki Notes ve Reminders'a verir ve anımsatıcının zamanını da Mac'te okur (bu uygulamaların onu diğer aygıtlarınızla eşzamanlayıp eşzamanlamadığı, iCloud gibi hesaplarına bağlıdır). Bu yüzden güvenli giriş sırasında da çalışırlar.
- `@open` yalnızca bu Mac'te arar. Onunla açtıklarınızı (son 200) önce listelemek için, giriş yönteminin kendi tercihlerinde (config.json'da değil) hatırlar.
- Notlarınızı listelemek için menü çubuğu paneli, `@note` ile kaydedilen son 30 notun kimliğini ve ilk satırını (en fazla 80 karakter) giriş yönteminin kendi tercihlerinde tutar; panel kapalıyken de.
- `@py` ve `@js` yalnızca eylem tuşuna bastığınızda ve yalnızca kendiniz yazdığınız veya yapıştırdığınız kodla çalışır: yapay zekânın yanıtları ve diğer komutların çıktısı asla kod olarak çalıştırılmaz. `@py`, Mac'inizin `python3`'ünü kullanır; bu, Terminal'de olduğu gibi dosya okuyup yazabilir ve internete çıkabilir; `@js` dosya okuyamayan, ağa erişemeyen ve başka programlar çalıştıramayan ayrı bir süreçte çalışır. İkisi de güvenli giriş sırasında çalışmaz.
- Günlükler yazdıklarınızı kaydetmez. macOS her üçüncü taraf giriş yöntemi için "The developer can access anything you type with this input source" (geliştirici, bu giriş kaynağıyla yazdığınız her şeye erişebilir) uyarısını gösterir; bu genel bir sistem uyarısıdır.

## Geliştirme

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

Kod düzeni:

- `Sources/AllInOneIMECore`: Bedrock istemcisi, SigV4, istemler (prompt'lar), iki düzeyli giriş durum makinesi (@ komutları ve ses hareketi dahil); AppKit bağımlılığı yok
- `Sources/AllInOneIMERime`: librime sarmalayıcısı
- `Sources/AllInOneIME`: InputMethodKit giriş yöntemi, aday paneli, ayarlar penceresi, konuşma tanıma
- `Sources/AllInOneIMESettings`: "AllInOneIME Settings" başlatıcısı
- `Sources/AllInOneIMEInstaller`: disk görüntüsündeki "Install AllInOneIME": kurar, günceller ve kaldırır

Dil paketlerinin eklentilerden ayrı kendi kitaplığı vardır: [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages) deposu; https://languages.allinoneime.com/ adresinden sunulur ve kendi anahtarıyla imzalanır. `make pack` arşivi oluşturur; arşiv orada bir sürüm dosyası (release asset) olarak yayımlanır (`zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>` sürümleri) ve `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` oraya `packs.json` yazar ve onu anahtar zincirindeki dil paketleri anahtarıyla (`allinoneime-languages-signing`) `packs.json.sig` olarak imzalar. Uygulama https://languages.allinoneime.com/packs.json dosyasını okur, imzayı, ardından arşivin boyutunu ve SHA-256'sını denetler. Bir paketi yerel bir sunucudan denemek için: `--test-key` bir test anahtarıyla imzalar ve `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Paket kimliği (bundle ID) hâlâ `com.aipinyin.inputmethod.AIPinyin`: macOS onu eklenen giriş kaynağını ve mikrofon iznini hatırlamak için kullanır; bu yüzden değiştirmek, giriş yöntemini yeniden eklemek ve izni yeniden vermek anlamına gelir.

## Lisans

Copyright © 2026 MicroZ LLC. Kaynak kodu [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2) altında erişilebilirdir: rakip bir ürün dışında her amaçla kullanın, okuyun, değiştirin ve paylaşın. Her sürüm, yayımlanmasından iki yıl sonra Apache-2.0 olur. 0.6.1'e kadarki sürümler GPL-3.0 altında yayımlandı ve bu lisansla erişilebilir olmaya devam eder.

Üçüncü taraf bileşenler (BSD-3-Clause altındaki librime ve eklentileri; GPL-3.0 altındaki rime-ice'ın Lua betikleri ve Çince dil paketi) [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) dosyasında listelenmiştir.
