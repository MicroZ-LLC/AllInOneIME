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
> 0.6.3'ten itibaren AllInOneIME bir Developer ID ile imzalanıyor ve Apple tarafından onaylanıyor (notarize): artık "System Settings → Privacy & Security" (Sistem Ayarları → Gizlilik ve Güvenlik) bölümünden izin vermeniz gerekmez. Daha eski bir sürümden güncelledikten sonra macOS, AllInOneIME'nin anahtar zincirine kaydettiği her anahtar için giriş parolanızı bir kez sorar: parolayı girin ve "Always Allow" (Her Zaman İzin Ver) düğmesine tıklayın. AllInOneIME'yi yalnızca [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) veya [allinoneime.com](https://allinoneime.com) üzerinden indirin.

Her metin alanında yapay zekâ komutları sunan bir macOS giriş yöntemi. Bir cümleye `@` ile başlayın ve bitince ⏎ tuşuna basın: `@improve` yazdığınızı düzeltip cilalar ve birkaç yeniden yazım önerir, `@translate` seçtiğiniz dillere çevirir, `@question` bir soru sorar, `@claude` işi Claude Code'a devreder, `@open` ise dosya ve uygulama bulur ya da bir web adresi açar. Sağ ⌥ tuşunu basılı tutup konuşabilirsiniz de. `@` olmadan tuşlarınız her zamanki gibi uygulamaya gider. Ayrıca Çince (pinyin, Rime ve rime-ice üzerine kurulu), Fransızca, Korece (Hangul) ve Hintçe (Latin harflerinden Devanagari) yazar ve kendi betiklerinizi @ komutları olarak çalıştırır.

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
| ⇧⏎ | Yapay zekâ sonuçlarından sonra bir devam metni yazıldıysa: onu gönderir (bir `@question` sohbetinin sonraki sorusu ya da bir iyileştirme). Bir komut yazılırken veya hiçbir şey yazılmamış yapay zekâ sonuçlarında: yazdığınızı `@command` dahil olduğu gibi ekler. Diğer sonuçlarda (`@open`, bir anımsatıcı …) ⏎ gibi vurgulanan satırı ekler. `@config` ve `@doctor` sonuçlarında, hiçbir şey yazılmamışken ⇧⏎ hiçbir şey yapmaz |
| ⌘C | Vurgulanan sonucu kopyalar (`@open` için yolu); aday paneli açık kalır |
| ⌃V | Bir komutta (ör. `@improve ` sonrasında): pano metnini uygulamaya yapıştırmak yerine yazdığınızın sonuna ekler. Birden çok satır tek satır olur, bir seferde en fazla 2000 karakter (`@note` satır sonlarını korur ve 20000'e kadar alır). Her uygulamada çalışır; komut yokken tuş her zamanki gibi uygulamaya gider |
| ⌘V | ⌃V gibidir, ancak bazı uygulamalar ⌘V'yi kendileri işler (Ghostty, iTerm2 ve Terminal gibi terminaller ile Notes) ve her zamanki gibi uygulamaya yapıştırır; oralarda ⌃V kullanın |
| Esc, ⌫ | Düzenlemeye devam etmek için cümleye döner; sonuçlardan sonra noktalama işareti veya rakam yazmak cümleyi sürdürür. Bir iyileştirmeden sonra: ondan önceki sonuçlara döner |
| Yapay zekâ sonuçları göründüğünde harfler | Bir devam metni: `@question` sonrasında sonraki soru (bkz. [Sohbetler](#question-ile-sohbetler-yeni)), `@improve` veya bir talimat komutu sonrasında `shorter` gibi bir talimat (bkz. [Sonuçları iyileştirme](#sonuçları-iyileştirme-yeni)); ⇧⏎ onu gönderir. `@translate` sonrasında harfler cümleyi sürdürür ve ⏎ onu yeniden çevirir |
| ⌘⏎, ⌘1–⌘5 | Bir `@question` sohbetinde: sohbetin nerede sürdürülebileceğini gösterir (Claude Code, Claude, ChatGPT, Gemini ya da kopyalamak); ⌘1, ⌘2 … birini seçer |
| Bir satıra tıklama | Aday panelinde: satırı, rakamı seçecekmiş gibi seçer (bir sözcük, listedeki bir komut, bir sonuç, bir `@open` dosyası, bir alıcı, bir uzantının satırı); işaretçinin altındaki satır vurgulanır. Metin alanı odağı korur |
| Shift'e dokunma | Birden fazla giriş dili varsa: sıralarına göre bir sonrakine geçer (İngilizce → Çince → Fransızca → …, sonra yeniden ilkine) |
| Sağ ⌥'yi basılı tutma | Konuşun, bitirmek için bırakın. Yazdığınız dilde (İngilizce, Çince, Fransızca, Korece veya Hintçe). Bir komutta metin komutun arkasına gelir; aksi hâlde doğrudan eklenir |

## @ komutları (beta)

| Komut | Ne yapar |
|---|---|
| `@improve` | Cilalar: 1–3 cümlenin kendi dilinde üç sürümdür, 4 ve sonrası yeniden yazım stilleridir (ayarlardan eklenir ve sıralanır), 0 orijinal metindir. Çeviri yapmaz; "@improve also translates" (@improve çeviri de yapar) açıkken `@translate @improve` gibi çalışır |
| `@translate` | Eklediğiniz dillere çevirir (ayarlar → "Translate", sıralamak için sürükleyin), her dil için bir satır, tek dil varsa üç sürüm; cümlenin kendi dili atlanır. `@translate @improve` birlikte tek istekte hem çevirir hem yeniden yazar |
| `@question` | Bir soru sorar; yanıt adaylarda görünür, ⏎ veya Boşluk ekler, ⌘C kopyalar. Yazmaya devam edip ⇧⏎'ye basınca bir ek soru sorulur: panel en fazla 5 turluk bir sohbete dönüşür, ardından sohbeti Claude'da veya başka bir yapay zekâda sürdürmeyi önerir. Ardından hiçbir şey yazılmazsa son 5 sorunuzu, en yenisi önce olmak üzere listeler; yazmak listeyi daraltır (sorunun herhangi bir yerindeki sözcükler, büyük/küçük harf fark etmez, Çince de). Bir rakam, ↑↓ ve ardından ⏎ ya da bir tıklama, bir sorunun kayıtlı yanıtını hemen, çevrimdışı gösterir; her zamanki gibi eklenebilir veya kopyalanabilir; orada ⌘R, yeni bir yanıt almak için soruyu yeniden sorar. Eşleşme yoksa ya da hiçbir şey seçilmediyse ⏎ yazdığınızı sorar |
| `@claude` | Görevi Claude Code'a devreder: varsayılan olarak arka planda, bitince bir bildirimle (oturumu Terminal'de açıp devam etmek için bildirime tıklayın), ya da `@tasks`'a bakın. Kendi Claude Code'unuzu (`claude` komutu) kendi oturum açma bilgileri ve ayarlarıyla kullanır. Eskisi gibi Terminal'de açılması için ayarlarda "@claude runs in the background and notifies me" (@claude arka planda çalışır ve bana bildirir) seçeneğini kapatın. Terminal'i ilk kez açtığında macOS, AllInOneIME'nin Terminal'i denetleyip denetleyemeyeceğini sorar: OK'e tıklayın |
| `@tasks` | Arka plandaki Claude görevlerini (çalışıyor / bitti / sizi bekliyor) son yanıtlarıyla listeler; ⏎ birini Terminal'de açar, ⌘C yanıtı kopyalar |
| `@settings` | Ayarlar penceresini hemen açar (seçmek yeterli) |
| `@config` | Ayarları tarif ettiğiniz gibi değiştirir: `@config output languages English and French`, `@config use Chinese in WeChat`, `@config candidates in a column`. ⏎ değişiklikleri eski → yeni olarak gösterir; ⏎ (veya 1) uygular, Esc iptal eder, daha fazla yazıp ⇧⏎'ye basmak onları iyileştirir; ⌘Z veya `@config undo` geri alır. Bkz. [Ayarları tarif ederek değiştirme](#ayarları-tarif-ederek-değiştirme-yeni) |
| `@doctor` | Bu Mac'teki kurulumunuzu denetler ve güvenle düzeltebileceklerini düzeltir: ⏎ sonuçları listeler, önce sorunlar; bir rakam o sorunu, ⏎ güvenli olanları `@config` önizlemesi üzerinden düzeltir. `@doctor why doesn't translate work` ayrıca yapay zekâya olası nedeni açıklatır. Bkz. [Kurulumunuzu denetleme](#kurulumunuzu-denetleme-yeni) |
| `@open` | Siz yazdıkça eşleşen dosyaları, klasörleri ve uygulamaları listeler (Spotlight). Boşlukla ayrılmış birden fazla anahtar sözcük kullanılabilir: her biri yolda, en az biri adda geçmelidir (standart bir klasörün adı, içindekiler için de geçerlidir: `downloads pdf` İndirilenler'deki PDF'leri bulur). Uygulamalar ve standart klasörler Çince adlarıyla da bulunur ve Çince arayüz onları bu şekilde gösterir. Önce `@open` ile açtıklarınız gelir, sonra uygulamalar ve bu klasörler, sonra son kullanılan veya değiştirilen dosyalar; adlar iki veya daha az dosya bulduğunda ve bu türden hiçbir uygulama ya da klasör bulmadığında, ana klasörünüzdeki dosyalar içeriklerine göre de aranır ve bu satırlar "content" olarak işaretlenir; başka hiçbir şey yoksa ⏎ ilkini açmak yerine onları seçmeniz için listeler. Bir web adresiyle (`github.com`, `localhost:3000`, `https://…`) ilk satır "open in the browser" (tarayıcıda aç) olur ve içerikler aranmaz; tam olarak bu adı taşıyan bir dosya (örneğin `MANIFEST.in`) önce gelir. `~/` veya `/` ile başlayan metin bir yoldur: Tab onu tamamlar ve klasörlerin içine girer; ⏎ açar, ⌘C yolu kopyalar |
| `@note` | Metni Notes (Notlar) uygulamasına, AllInOneIME adlı bir klasöre (yoksa oluşturulur) kaydeder; hiçbir şey eklenmez. Yapıştırılan metin satır sonlarını korur, en fazla 20000 karakter |
| `@reminder` | Reminders (Anımsatıcılar) uygulamasına, AllInOneIME adlı bir listeye bir anımsatıcı ekler. Zamanı metne yazın; Mac'te okunur ve bir satır neyin okunduğunu gösterir: ⏎ veya Boşluk ekler, Esc düzenlemeye döner. Saat verilirse o anda bir alarm olur; yalnızca tarih verilirse tüm gün sürer |
| `@calculate` | Bu Mac'te hesaplar; sonuç adaylarda görünür, ⏎ veya Boşluk ekler: `@calculate 23*17` → `391`. Bir cümlenin içinde de çalışır: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Bir satır Python çalıştırır (Mac'in `python3`'ü) ve sonucu ekler: kodun son ifadesinin değeri, ör. `@py 2**100`, `@py import math; math.sqrt(2)`, ya da bu yoksa yazdırdığı çıktı. `python3` yoksa sunulmaz (Xcode'un komut satırı araçlarında vardır) |
| `@js` | Bir satır JavaScript çalıştırır ve aynısını ekler: son ifadenin değeri veya `console.log`'un yazdırdığı, ör. `@js [1, 2, 3].map(x => x * 2)`. macOS'un yerleşik JavaScriptCore'unu kullanır, bu yüzden kurulacak bir şey yoktur; dosya okuyamaz, ağa erişemez ve başka programlar çalıştıramaz |
| `@reportissue` | Bir sorun bildirir: tarayıcınızda GitHub'ın yeni issue sayfasını açar; komuttan sonra yazdığınız başlık olur, doldurmanız için de "What happened / What you expected" (ne oldu / ne bekliyordunuz) bölümleri gelir. Uygulama ve macOS sürümlerini, Mac'inizin mimarisini, arayüz ve giriş dillerini, kurulu dil paketlerini, yapay zekâ sağlayıcısının türünü (ve herkese açık bir modelse modeli; değilse "custom"), eylem tuşunu ve kaç özel komut, eklenti ve uzantınız olduğunu ekler; asla adlarını, metninizi, yolları veya anahtarları eklemez. ⏎ (veya eylem tuşunuz) önce bunların hepsini aday panelinde gösterir; tekrar ⏎ ya da satıra bir tıklama sayfayı açar, orada okuyup Submit düğmesine tıklarsınız (kendi GitHub hesabınızla); Esc geri döner. Giriş menüsünde ("Report an Issue…") ve Settings → About içinde de bulunur |
| `@imessage` | Bir iMessage gönderir: bir ad, telefon numarası veya e-posta yazın (Çince bir ad pinyin'iyle de, tam olarak ya da baş harfleriyle) ve alıcıyı aday panelinden seçin (son zamanlarda mesajlaştıklarınız önce gelir; tam bir numara veya adres de olur), ardından mesajı yazın (içindeki `@stock AAPL` gibi komutlar önce çalışır). ⏎ panelde "Send to Alex (…): message" gösterir, ⏎ tekrar gönderir, Esc düzenlemeye döner; metin alanına hiçbir şey yazılmaz. İlk seferde macOS, AllInOneIME'nin Contacts'a (Kişiler) erişip Messages'ı (Mesajlar) denetleyip denetleyemeyeceğini sorar: ikisinde de OK'e tıklayın |

Örnek: `@q` ⏎, `what is quantum computing` yazın, ⏎. `@note books to read: The Three-Body Problem` ⏎ bir not kaydeder. `@reminder call Bob tomorrow at 3pm` ⏎, okunan zamanı kontrol edin, sonra eklemek için yeniden ⏎. Komut seçildikten sonra sağ ⌥'yi basılı tutup konuşabilirsiniz de. Çince modunda `@open` ve `@calculate` o an için İngilizce harflere geçer ve işiniz bitince Çinceye döner.

`@py` ve `@js` kodu İngilizce harflerle yazılır ve tam genişlikli noktalama işaretleri (Çince modundan) ASCII'ye dönüşür; kodu tek satıra, deyimler arasına `;` koyarak yazın. Ayrı bir süreçte çalışır, 10 saniye sonra ya da herhangi bir anda Esc ile durdurulur; hata olursa hatanın ilk satırı gösterilir, ör. `ZeroDivisionError: division by zero`. Birden çok satırlı çıktı yazdırıldığı gibi eklenir; terminalde tek satır olarak girer (terminal kendisine verilen her satırı çalıştırır). Bir düzenleyicinin içindeki terminal (VS Code, Cursor, JetBrains) düzenleyicinin kendisinden ayırt edilemez, bu yüzden orada her komutun birden çok satırlı çıktısı olduğu gibi girer. İkisi de başka bir komutun cümlesinin içinde çalışır: `@reply the answer is @py 2**100`; boşluk içeren kodu tırnak içine alın: `@question explain @py "sum(x * x for x in range(10))"`. Tersi geçerli değildir: `@py` ve `@js` kodu her zaman tam yazdığınız gibi çalışır ve içindeki `@commands` önceden çalıştırılmaz.

![@ yazmak komut listesini açar; @question ve bir soru, ardından yanıt için ⏎](../en/commands.png)

![@open siz yazdıkça uygulamaları bulur; / ile başlıyorsa bir yoldur: klasör listelenir, Tab tamamlar](../en/open.png)

`@` bir komutla devam etmediğinde, `@john`'da olduğu gibi, `@` her zamanki gibi eklenir; böylece sohbet uygulamalarında kişileri @ ile anmak çalışmaya devam eder. `@question`, `@improve` ve `@translate` yalnızca eylem tuşuna bastığınızda kendi Bedrock'unuza gönderir; `@open` yalnızca bu Mac'te arar; `@note` ve `@reminder` yalnızca bu Mac'teki Notes ve Reminders'a gider; `@claude` Mac'inizde kurulu Claude Code'u (`claude` komutu) ve onun kendi hesabını kullanır ve dosyaları değiştirmeden veya komut çalıştırmadan önce her zamanki gibi size sorar. Claude Code kurulu değilse `@claude` sunulmaz. `@imessage` Contacts'u yalnızca bu Mac'te okur (adlar, telefon numaraları, e-postalar), asla yapay zekâdan geçmez ve mesajı Messages gönderir; Messages uygulaması yoksa sunulmaz.

`@calculate` bu Mac'te, çevrimdışı çalışır: `+ - * /` (ayrıca `× ÷`), üs için `^` veya `**`, parantezler, yüzde (`50%` 0.5'tir, `200*5%` 10'dur; hesap makinesinde olduğu gibi, eklenen veya çıkarılan bir yüzde kendinden öncekinin yüzdesidir: `100+10%` 110, `100-10%` 90'dır), `sqrt abs round floor ceil ln log exp sin cos tan min max pow` fonksiyonları (`log` 10 tabanlıdır, açılar radyandır, `round(x, 2)` iki ondalık basamak tutar) ve `pi` (`π`) ile `e` sabitleri. Tam genişlikli rakamlar ve işaretler de çalışır. Aritmetik ondalık olarak kesindir, bu yüzden `0.1+0.2` `0.3` eder; sonuçlar en fazla 15 anlamlı basamak içerir ve 38 basamağa kadar tam sayılar eksiksiz yazılır (`2^100` → `1267650600228229401496703205376`).

### Seçili metin üzerinde (yeni)

Herhangi bir uygulamada metin seçin (Notlar'da bir cümle, Mail'de bir paragraf), `@improve`, `@translate`, `@question` veya metin alan başka bir komut yazın ve ⏎'ye basın: komut seçim üzerinde çalışır ve seçtiğiniz sonuç onun yerini alır. Siz yazarken seçim olduğu gibi, seçili kalır: komut aday panelinde yazılır; panelin ilk satırı yazdığınız, sonraki satır "On the selection: “…” (N characters)" (seçim üzerinde: N karakter) olur. Esc, ⇧⏎ veya başka bir yere tıklamak metni olduğu gibi bırakır; bu arada seçimi değiştirmek de öyle yapar ve komutu iptal eder. Komuttan sonra yazılan metin, seçimle ilgili olarak `@improve` ve `@translate` için bir talimat (`@translate ja`, `@improve more formal`), `@question` için ise sorudur (`@question what does this mean`). `@open`, `@claude`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, terminal komutları ve betik uzantıları onu kullanmaz: yazdığınızı alırlar ve seçim olduğu gibi kalır. En fazla 5000 karakter; güvenli giriş sırasında veya bir terminalde asla okunmaz. Bir uygulamada düzgün çalışmıyorsa Settings → General → "Use the selected text" (seçili metni kullan) altından kapatın.

### Sonuçları iyileştirme (yeni)

`@improve`, bir talimat komutu (sizin ya da bir eklentinin) veya bir seçimin yeniden yazımının sonuçları görünürken neyin değişeceğini yazın, örneğin `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese` veya `用更口语的说法` (pinyin çalışır, Shift'e dokunmak dili değiştirir), ve ⇧⏎'ye basın: sonuçlar talimatınızla birlikte yeniden yapay zekâya gider ve yenileri aynı panelde onların yerini alır. ⏎ seçili sonucu ekler, talimat yarım yazılmış olsa bile (yazılan atılır). İstediğiniz kadar iyileştirin; panelin en üst satırı adımları listeler ("Refined: shorter · more formal") ve her zamanki gibi istediğiniz an bir satır seçebilirsiniz. Bir harf talimatı başlatır (panelin üstünde "refine › …" olarak gösterilir); talimat boşken rakamlar, Boşluk ve ⏎ eskisi gibi seçer, ⇧⏎ ise yazdığınızı olduğu gibi ekler. İyileştirme, sonuçlar tamamlandığında başlar: ilk sonuçlar hâlâ gelirken yazmak, eskisi gibi cümleyi sürdürür. Bir iyileştirme sürerken bir sonraki talimatı şimdiden yazabilirsiniz; iyileştirme devam eder ve ⇧⏎, sonuçları gelir gelmez bir sonrakini çalıştırır. Esc talimatı siler, ardından son iyileştirmeden önceki sonuçlara bir adım geri gider (bir iyileştirme sürerken: onu durdurur), sonra cümleye döner; boş bir satırda ⌫ aynı şekilde geri gider. Seçili metin üzerinde, seçtiğiniz sonuç yine tam olarak seçimin yerini alır; seçim o zamana kadar hiç değişmez. Başarısız olan (veya güvenli giriş sırasında reddedilen) bir iyileştirme sonuçları olduğu gibi bırakır, talimatı da ⇧⏎ ile yeniden denemeye hazır kalır. Aynı sonuçların aynı iyileştirmesi önbellekten yanıtlanır. `@translate` için iyileştirme yoktur: sonuçlarından sonra yazmak cümleyi sürdürür ve ⏎ onu yeniden çevirir.

### @question ile sohbetler (yeni)

`@question` yanıt verdikten sonra yazdığınız şey sonraki sorudur: ⇧⏎ onu o ana kadarki sorular ve yanıtlarla birlikte sorar ve panel bir sohbete dönüşerek büyür; önceki turlar soluk Q / A satırları olarak, en son yanıt da onların altında görünür. En üstteki satır sıradaki turun hangisi olduğunu söyler ("question 2/5 › …"). Her yanıt eklenebilir: rakamıyla (1–5), ↑↓ ve ardından ⏎ ile ya da bir tıklamayla; en son yanıt seçilidir ve ⌘C seçili olanı kopyalar. Bir soru yarım yazılmış olsa bile ⏎ yanıtı ekler (yazılan atılır). Esc yazdığınızı siler, ardından bir tur geri gider; ilk turda eskisi gibi çıkar. Panel ekranın yaklaşık yarısına kadar büyür, sonra kayar; en sonuncusu en altta olur.

5 turdan sonra (yapılandırmada `questionRounds`, 2–10) sonraki sorunun satırı "5 rounds in: continue in Claude or another AI" (5 tur oldu: Claude'da veya başka bir yapay zekâda sürdürün) olur ve seçenekler ⌘1, ⌘2 … diye numaralanır; ⌘⏎ bunları her turda gösterir (bir yanıt hâlâ gelirken hiçbir şey yapmaz ve uygulamaya asla ulaşmaz). O anda yazdığınız şey oradaki ilk mesaj olur; onu yalnızca ⌘1, ⌘2 … gönderir (⇧⏎ artık hiçbir şey sormaz ve hiçbir şey açmaz). Seçili metin hakkındaki bir soru o metni de, ayrı bir blok olarak alıntılanmış şekilde götürür. Seçenekler:

- **Claude Code**, `claude` komutu yüklüyse: Terminal'de sohbet ve "Let's continue this discussion" ile başlayan etkileşimli bir oturum.
- Web'de **Claude** veya **ChatGPT**, sohbet önceden doldurulmuş olarak (uzun bir sohbet panoya konur: yapıştırın).
- Web'de **Gemini**, sohbet yapıştırılmak üzere panoda.
- **Copy the conversation** (sohbeti kopyala), Markdown biçiminde (**Q:** / **A:**).

Hangileri ve hangi sırayla (ilki varsayılandır): Settings → General → "Continue a conversation in" (sohbeti şurada sürdür; yapılandırmada `questionContinueIn`). Bu Mac'te Apple Intelligence ile uzun bir sohbet onun küçük bağlamına sığmaz: önce en eski yanıtlar kısaltılır, sonra en eski turlar dışarıda bırakılır ve panel "earlier rounds shortened" (önceki turlar kısaltıldı) der. Bir sohbet son sorular arasında ilk sorusunun altında kaydedilir; onu seçmek, sürdürmeniz için turları gösterir.

### Son sorular (yeni)

Ardından hiçbir şey yazılmamış `@question`, son 5 sorunuzu en yenisi önce olmak üzere, ne zaman sorulduklarıyla birlikte listeler ("3 hours ago"). Yazmak listeyi daraltır: sorunun herhangi bir yerindeki her sözcük, büyük/küçük harf fark etmeksizin (boşluksuz Çince de). Bir rakam, ↑↓ ve ardından ⏎ ya da bir tıklama, bir sorunun kayıtlı yanıtını hemen, internete çıkmadan gösterir: Boşluk veya ⏎ ekler, ⌘C kopyalar, ⌘R yeni bir yanıt için yeniden sorar (bir sohbette: son sorusunu), Esc listeye döner. Kayıtlı bir sohbet tüm turlarını gösterir: sürdürmek için yazın. Eşleşme yoksa ya da hiçbir şey seçilmediyse ⏎ yazdığınızı sorar. Aynı soruya gelen yeni bir yanıt ya da sürdürülen bir sohbet, kayıtlı olanın yerini alır.

- Yalnızca bu Mac'te saklanırlar (bkz. Gizlilik): güvenli giriş açıkken saklanmaz, seçili metin üzerine sorulan sorular için asla saklanmaz.
- Settings → General → "Remember recent questions" (son soruları hatırla) özelliği kapatır (yapılandırmada `rememberQuestions`); orada kapatılınca sorular da silinir. `@config` ile kapatılınca korunurlar, böylece geri almak her şeyi tam olarak eski hâline getirir (önizlemesi bunu belirtir); "Clear (N)" (temizle) onları siler.

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

Eklentiler, herkesin ihtiyaç duymadığı şeyler için hazır `@` komutlarıdır; örneğin hisse senedi fiyatları için `@stock AAPL 600519 700`. Kurulduktan sonra her komut gibi çalışırlar; ayarlardaki "Plugins" bölümü neyin kurulu olduğunu ve her birinin metninizi nereye gönderdiğini gösterir ve onları kaldırır. Eklentiler ayrı bir süreçte çalıştırılan JavaScript'tir: yalnızca beyan ettikleri web sitelerine (HTTPS) erişebilirler, dosya okuyamaz ve başka programlar çalıştıramazlar. Ayarlarda "Plugins" altındaki "Browse Library…" (kitaplığa göz at) onları [eklenti kitaplığından](https://github.com/MicroZ-LLC/AllInOneIME-plugins) kurar: kurmadan önce bir eklentinin hangi web siteleriyle iletişim kurduğunu gösterir; kitaplığın dizini imzalıdır ve her dosya ona uymak zorundadır. Daha yeni bir sürüm "Update" (güncelle) düğmesi gösterir; hiçbir şey kendiliğinden güncellenmez. Kendi eklentileriniz `~/.config/allinoneime/plugins/` ("Open Plugins Folder") içine gider: bunlar yerel eklentilerdir ve kitaplık bunların üzerine asla yazmaz. "Bağlantı" (link) eklentileri kod çalıştırmaz: metni bir web adresine yerleştirip tarayıcıda açarlar; örneğin `@x nice weather today`, X'in gönderi oluşturucusunu metin doldurulmuş olarak açar; paylaşmak sayfada size kalır. Kitaplıkta dört tane vardır (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` döviz çevirir: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, kurun tarihiyle birlikte tek satır (kurlar ExchangeRate-API'den). Eklenti yazmak için: [docs/plugins.md](../plugins.md).

Bir şey getiren komutlar (eklentiler ve programlar) bir cümlenin içinde de çalışır: `@reply tell her @stock AAPL is up today`. İçteki komutlar önce çalışır, çıktıları onların yerini alır ve dıştaki komut sonuç üzerinde çalışır. Argüman, komuttan sonraki sözcük ile hemen arkasından gelen büyük harfli kodlar veya sayılardır (`@stock AAPL TSLA`, `@stock 600519 700`); küçük harfli bir sözcük argümanı bitirir (`@stock SNDK is good to buy` SNDK'yi arar). Tırnaklar onu tam olarak belirler: `@stock "aapl tsla"`. `@calculate` da bir cümlenin içinde çalışır; argümanı, boşluklar dahil, arkasından gelen ifadenin tamamıdır, başka metne kadar: `@reply the total is @calculate 23 * 17 dollars`. `@claude` ve terminal komutlarının içinde çalıştırılmazlar: onlar metni yazıldığı gibi alır (orada `@` yazmak komut listesini açmaz).

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
| Bu uygulamada yapay zekâ yok | `@improve`, `@translate`, `@question`, `@claude` ve talimat komutlarınız orada hiçbir şey göndermez ve bunu söyler; yazma ve diğer komutlar çalışır | `noAI` |

"Add App…" (uygulama ekle) son zamanlarda yazdığınız uygulamaları listeler ya da /Applications içinden birini seçer. Giriş menüsündeki "This App: <ad>", yazdığınız uygulama için hızlı anahtarlar içerir (No AI, Type Results Out, başlangıç dili). Yapılandırmada bunlar `appProfiles` altında, paket kimliğine (bundle ID) göre bulunur: `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. Paket kimlikleri büyük/küçük harf fark etmeksizin eşleşir (`com.apple.Mail`, Mail'in `com.apple.mail` kimliğidir). `@reportissue` bir şey belirleyen uygulamaları sayar, adlarını asla vermez.

- Başlangıç dili varsayılan giriş dili gibi çalışır: bir metin alanı etkinleştiğinde onu alır ve Shift ile yapılan bir değişiklik, ayar değişene kadar o uygulamanın alanlarında kalır.
- No AI açıkken yapay zekâ komutları @ listesinde kalır; birini çalıştırmak bildirimi gösterir ve yazdığınızı korur. Kendi terminal komutlarınız (`"type": "terminal"`) yapay zekâyı değil programları çalıştırır, bu yüzden orada çalışmaya devam eder.

### Ayarları tarif ederek değiştirme (yeni)

`@config` bir cümleyi ayarlara dönüştürür: `@config output languages English and French`, `@config 微信里用中文，邮件里语气正式一点`, `@config candidates in a column`, `@config turn off the typos`, `@config use Claude`. ⏎ değişiklikleri aday panelinde, her biri bir satırda, eski → yeni olarak, ayarların kullandığı etiketlerle gösterir ("Translation languages: English, Japanese → English, French", "Apps · WeChat · Starts in: Same as everywhere → Chinese"); henüz hiçbir şey değişmez veya yazılmaz. ⏎ (veya 1) hepsini uygular, Esc iptal eder; daha fazla yazıp ⇧⏎'ye basmak öneriyi iyileştirir ("Almanca da"; hiçbir şey yazılmamışken ⇧⏎ hiçbir şey yapmaz, ⏎ ise gösterilen öneriyi uygular). Uygulandıktan sonra, onay görünürken ⌘Z veya sonraki 10 dakika içinde `@config undo`, bu ayarların önceki değerlerini aynen geri getirir.

- **Neyi değiştirebilir:** çeviri ve giriş dilleri (ve varsayılan dil), yeniden yazma stilleri, aday düzeni, sonuçları yazarak ekleme (açık/kapalı, hız, hızlanıp yavaşlama, yazım hataları), seçimin kullanılması, soruların hatırlanması, hassas bilgilerin gizlenmesi (açık/kapalı, neyin gizlendiği, eklenecek sözcükler), güncelleme denetimi, uygulamaya özel ayarlar (sizin adlandırdığınız şekliyle bir uygulama; uygulamalarınız arasında adına veya paket kimliğine göre bulunur) ve yapay zekâ sağlayıcısı: hangisi, Bedrock profili (`~/.aws` içinden) ve bölge, uygulamanın o sağlayıcı için bildiği bir model ve OpenAI uyumlu bir temel URL (yalnızca `https://`).
- **Neye asla dokunmaz:** API anahtarları ve anahtar zincirindeki her şey, özel komutlar, uzantı klasörleri ve kaynakları, eklentiler, jargon listesi, program çalıştıran her şey ve diğer tüm ayarlar. Bu satırlar nedeniyle birlikte reddedilir, geri kalanı yine de uygulanabilir.
- **Ayarlardaki gibi denetlenir:** dil olmayan bir dil, 5'ten fazla çeviri dili, aralık dışı bir değer, ayırt edemediği bir uygulama ya da paketi yüklü olmayan bir dil ("needs the Korean language pack: download it in Settings → Input", yani Korece dil paketi gerekiyor: onu Settings → Input içinden indirin) satır satır reddedilir; geçersiz bir yapılandırma asla yazılmaz.
- **Anahtarlar:** anahtar gerektiren bir sağlayıcı "API key: enter it in Settings (never sent to the AI)" (API anahtarı: ayarlardan girin, yapay zekâya asla gönderilmez) satırını alır: bunu uygulamak Settings → AI Provider'ı anahtar alanında açar. Cümleye yazılmış bir anahtar, herhangi bir şey gönderilmeden önce çıkarılır. Sağlayıcı değiştikten sonra Test Connection çalışır ve sonucu onayın altında görünür.
- **Önce bu Mac'te:** bu Mac'te Apple Intelligence varsa (macOS 26), hangi sağlayıcıyı seçmiş olursanız olun ve hatta bir sağlayıcı kurulmadan önce bile her zaman onu kullanır; izin verilen ayarlar ve değerlerle sınırlıdır, uygulamalarınızı, AWS profillerinizi ve dil paketlerinizi sorgulayabilir. O yoksa sağlayıcınız yanıt verir. İstek yalnızca izin verilen ayarları ve bunların güncel değerlerini içerir (asla bir anahtar ya da gizlediğiniz sözcükler değil) ve hassas bilgilerin gizlenmesi her istekte olduğu gibi uygulanır.

### Kurulumunuzu denetleme (yeni)

`@doctor` ⏎ bu Mac'teki kurulumu bir iki saniyede denetler (çalışırken bağlantı testi görünür) ve sonuçları aday panelinde, her biri bir satırda, önce ✗ sorunlar, sonra ⚠ uyarılar, sonra ✓ yolunda olanlar şeklinde, her birini kısa bir düzeltmeyle listeler: giriş yöntemi (yüklü, etkin, giriş kaynaklarınızda), yapay zekâ sağlayıcısı (anahtarı kayıtlı mı ya da Bedrock profilinin kimlik bilgileri bulunuyor mu; bunlar asla okunmaz veya gösterilmez; Test Connection; Apple Intelligence), izinler (Erişilebilirlik, dikte ediyorsanız mikrofon, Notlar, Anımsatıcılar, Terminal ve Mesajlar'ın denetimi; macOS'e bir istem göstermeden sorulur), güvenli giriş, giriş dillerinizin dil paketleri, `config.json` (okunabilir mi, bilinmeyen anahtarlar, aralık dışı değerler, iki kez geçen bir dil, 5'ten fazla çeviri dili), yüklenmeyen uzantılar ve eklentiler, güncellemeler ve uygulamanın kendi günlüklerindeki son hatalar.

Düzeltmesi olan satırlar numaralıdır: bir rakam (veya bir tıklama) düzeltmenin ne yapacağını `@config` önizlemesinde gösterir, ⏎ da onu uygular; listede ⏎ tüm güvenli düzeltmeleri bir kerede yapar (ayarlar onarılır, yinelenen diller kaldırılır, giriş yöntemi yeniden etkinleştirilir). Bir Sistem Ayarları bölmesini açmak, bir dil paketi indirmek, Check for Updates (ayarları açar) ve ayarlardaki anahtar alanı tek tek seçilir. Ayar değişiklikleri `@config` değişiklikleri gibi geri alınır (⌘Z, `@config undo`). Hiçbir düzeltme verilerinizi silmez veya bir anahtara dokunmaz.

`@doctor <question>` (`@doctor why doesn't translate work`) denetimleri çalıştırır, ardından yapay zekâ olası nedeni sonuçlardan açıklar ve önerdiği düzeltmeleri işaretler (⏎ yine yalnızca güvenli olanları uygular; diğerleri numarasıyla). No AI ayarlı bir uygulamada denetimler yine çalışır ve yalnızca soru reddedilir. Bu Mac'te varsa Apple Intelligence kullanılır ve gereken denetimleri araç olarak çağırır; yoksa sağlayıcınız, ve panel bunu belirtir. Yalnızca denetim sonuçları (`~` ötesinde yol yok, anahtar yok, metninizden hiçbir şey yok) ve sorunuz gönderilir; denetimler kendi başlarına Test Connection isteği dışında hiçbir şey göndermez (o da yalnızca sağlayıcının sınanacak bir anahtarı veya kimlik bilgisi varsa).

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
- Biçimli değerleri tanır; adları veya adresleri tanıyamaz, bu yüzden onları kendi sözcükleriniz olarak ekleyin. `@claude`, bir web sitesinden veri getiren (`@stock`) veya bir siteyi açan (`@x`) eklentiler ve betik uzantıları metni yazıldığı gibi gönderir. Daha fazlası Gizlilik bölümünde.
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
| `rememberQuestions` | Son 5 `@question` sorunuzu ve yanıtlarını bu Mac'te saklar, `@question` altında listeler (bkz. Son sorular) | `true` |
| `questionRounds` | Bir `@question` sohbetinin, başka yerde sürdürmeyi önermeden önce panelde süreceği tur sayısı, 2–10 | `5` |
| `questionContinueIn` | Bir `@question` sohbetinin sürdürülebileceği yerler, sırayla, ilki varsayılan: `claudeCode`, `claudeWeb`, `chatgpt`, `gemini`, `copy` | Claude Code (yüklüyse), Claude, ChatGPT, kopyala |
| `appProfiles` | Bir uygulamanın ayarları, paket kimliğine göre, her biri isteğe bağlı: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI` (bkz. Uygulamaya özel ayarlar) | `{}` |
| `redaction` | Hassas bilgileri yapay zekâdan gizler (bkz. Gizlilik): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`; her algılayıcı (`emails`, `phones`, `cards`, `keys`, `ips`) `false` yapılmadıkça açıktır | `enabled: false` |

## Gizlilik

- Yazma (İngilizce ve pinyin) ve `@calculate` hesaplamaları tamamen yereldir. Yalnızca `@improve`, `@translate` veya `@question` üzerinde eylem tuşuna bastığınızda o cümle seçtiğiniz yapay zekâ sağlayıcısına (kendi Bedrock'unuz ya da anahtarını eklediğiniz hizmet) gönderilir. "Jargon" işaretliyse ve bir jargon listesi ayarlanmışsa, liste de onunla birlikte gönderilir. Sonuçları iyileştirmek (sonuçlardan sonra yazılan bir talimat, ardından ⇧⏎) aynı isteği gösterilen sonuçlar ve talimatınızla yeniden gönderir; bir ek soru (⇧⏎) o ana kadarki sohbeti de birlikte gönderir.
- `@config` ve `@doctor <question>`, ⏎'ye bastığınızda bir modele metin gönderir: bu Mac'te Apple Intelligence kullanılabildiği her zaman ona (hiçbir şey Mac'ten çıkmaz), yoksa sağlayıcınıza. `@config` cümlenizi (içine yazılmış bir anahtar önce çıkarılır) değiştirebileceği ayarların güncel değerleriyle birlikte gönderir: asla bir anahtarı ya da yapay zekâdan gizlediğiniz sözcükleri değil (yalnızca kaç tane olduklarını), AWS profillerinizin adlarını da yalnızca cümle AWS veya Bedrock ile ilgiliyse. `@doctor <question>` sorunuzu denetim sonuçlarıyla birlikte, maskelenmiş olarak gönderir: `~` ötesinde yol yok, anahtar yok, günlük satırları sabit ifadeler olarak. Hassas bilgilerin gizlenmesi, her istekte olduğu gibi ikisine de uygulanır. Denetimler tek başına (ardından hiçbir şey olmayan `@doctor`) Test Connection isteği dışında hiçbir şey göndermez, o da yalnızca sağlayıcının sınanacak bir anahtarı veya kimlik bilgisi varsa.
- Bir `@question` sohbetini başka bir yerde sürdürmek (son turdan sonra ⌘1 … ya da ⌘⏎) onu, yazdığınızla birlikte, seçtiğiniz hizmete gönderir: bu Mac'teki Claude Code (Anthropic), claude.ai, chatgpt.com veya gemini.google.com; web adresinde ya da pano üzerinden. Sohbet gördüğünüz gibi gider: yapay zekâ isteklerinden gizlenen değerler (aşağıya bakın) içinde olduğu gibi yer alır, çünkü onu oraya göndermeyi siz seçersiniz. Siz birini seçene kadar hiçbir şey hiçbir yere gitmez; "Copy the conversation" onu yalnızca panoya koyar.
- AllInOneIME Cloud ile cümle, geliştiricinin sunucusu üzerinden bir model sağlayıcısına (şu anda OpenRouter aracılığıyla) gider: sunucu yalnızca sayıları tutar, metni asla tutmaz. Oturum açmak yalnızca e-posta adresinizi saklar.
- Hassas bilgileri gizleme (Settings → AI Provider → Privacy, varsayılan olarak kapalı): herhangi bir istek çıkmadan önce (`@improve`, `@translate`, `@question`, talimat komutlarınız ve talimat eklentileriniz, AllInOneIME Cloud dahil her sağlayıcıda), e-posta adresleri, telefon numaraları, ödeme kartı numaraları (Luhn ile doğrulanmış), API anahtarları ve token'lar (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…` ve uzun rastgele dizeler), IP adresleri ve kendi sözcükleriniz (bir kod adı, bir ad) Mac'te `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]` gibi yer tutucularla değiştirilir; aynı değer aynı yer tutucuyu alır. Modelin sonuçları gösterilmeden veya eklenmeden önce gerçek değerleri geri alır ve panel "2 items hidden from the AI" der. Yer tutucusu model tarafından tanınmayacak kadar değiştirilmiş bir sonuç yazıldığı gibi gösterilir ve "⚠ placeholder changed" ile işaretlenir. Gizlenmiş bir değer içeren jargon listesi girdileri gönderilmez. Her tür kapatılabilir. Tam genişlikli biçimler (`zhang＠example.com`, `１３８…`) de bulunur ve bir değer veya ifade bir satır sonuyla bölünmüş olabilir. E-postalar, numaralar ve anahtarlar gibi biçimli değerleri tanır; adları veya adresleri (bunları kendi sözcükleriniz olarak ekleyin) ve başka alfabelerdeki benzer görünen harfleri tanıyamaz. Yapay zekâ hizmetinize giden isteklere uygulanır; `@claude`, bir web sitesinden veri getiren (`@stock`) veya bir siteyi açan (`@x`) eklentiler ve betik uzantıları metni yazıldığı gibi gönderir. Yapılandırmada: `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- Ses yalnızca sağ ⌥'yi basılı tuttuğunuz sürece kaydedilir ve Mac'te tanınır; tanınan metin yalnızca yukarıdaki komutlarda, eylem tuşuna bastığınızda gönderilir.
- Giriş yöntemi pano metnini yalnızca bir komutta ⌃V veya ⌘V'ye bastığınızda, bir kez okur; parola yöneticilerinin gizli olarak işaretlediği içerik okunmaz. Metin önce komutta gösterilir ve yine yalnızca eylem tuşuna bastığınızda gönderilir. Son macOS sürümleri, AllInOneIME'nin panoyu okuyup okuyamayacağını sorar: izin verin. Her seferinde sorulmasını önlemek için "System Settings → Privacy & Security" içinde AllInOneIME'nin yapıştırma iznini her zaman izin ver olarak ayarlayın.
- Parola alanlarında macOS kendi klavyesine (U.S. veya ABC) geçer ve alandan ayrıldığınızda geri döner. Yazdığınız uygulama güvenli girişi tuttuğu her durumda AllInOneIME metin oluşturmaz ve kayıt yapamaz: tuşlar yazıldığı gibi girer. Sistem güvenli giriş durumundayken de (parola alanları, Terminal'in "Secure Keyboard Entry" özelliği vb.) yapay zekâya hiçbir şey gönderilmez.
- `@note` ve `@reminder` yapay zekâya gitmez: AllInOneIME metni yalnızca bu Mac'teki Notes ve Reminders'a verir ve anımsatıcının zamanını da Mac'te okur (bu uygulamaların onu diğer aygıtlarınızla eşzamanlayıp eşzamanlamadığı, iCloud gibi hesaplarına bağlıdır). Bu yüzden güvenli giriş sırasında da çalışırlar.
- `@reportissue` (ve "Report an Issue…") kendisi hiçbir şey göndermez: tarayıcınızda GitHub'ın yeni issue sayfasını, yazdığınız başlık ve yukarıda listelenen sürümler, diller, sağlayıcı türü ve sayılarla açar; bunlar önce aday panelinde gösterilir. Orada Submit'e tıklamadıkça GitHub'a hiçbir şey ulaşmaz.
- `@open` yalnızca bu Mac'te arar. Onunla açtıklarınızı (son 200) önce listelemek için, giriş yönteminin kendi tercihlerinde (config.json'da değil) hatırlar.
- Settings → Apps içindeki "Add App…" için giriş yöntemi, yazdığınız son 12 uygulamanın paket kimliklerini kendi tercihlerinde saklar; onlarla ilgili başka hiçbir şeyi saklamaz.
- `@question`, son 5 sorunuzu yanıtları ve ne zaman sorulduklarıyla birlikte yalnızca bu Mac'te, `~/Library/Application Support/AllInOneIME/recent-questions.json` içinde (yalnızca kullanıcı hesabınız okuyabilir) hatırlar ve bunları `@question` altında listeler; kayıtlı bir yanıt oradan, internete çıkmadan gösterilir. Güvenli giriş açıkken hiçbir şey saklanmaz ve seçili metin üzerine sorulan sorular hiç saklanmaz (yanıtları seçimle ilgilidir ve seçim diske yazılmış olurdu). "Remember recent questions" özelliğini Settings → General içinden kapatmak soruları da siler; `@config` ile kapatmak (yapılandırmada `rememberQuestions`) onları korur, böylece tam olarak geri alınabilir. "Clear" onları siler.
- Notlarınızı listelemek için menü çubuğu paneli, `@note` ile kaydedilen son 30 notun kimliğini ve ilk satırını (en fazla 80 karakter) giriş yönteminin kendi tercihlerinde tutar; panel kapalıyken de.
- `@py` ve `@js` yalnızca eylem tuşuna bastığınızda ve yalnızca kendiniz yazdığınız veya yapıştırdığınız kodla çalışır: yapay zekânın yanıtları ve diğer komutların çıktısı asla kod olarak çalıştırılmaz. `@py`, Mac'inizin `python3`'ünü kullanır; bu, Terminal'de olduğu gibi dosya okuyup yazabilir ve internete çıkabilir; `@js` dosya okuyamayan, ağa erişemeyen ve başka programlar çalıştıramayan ayrı bir süreçte çalışır. İkisi de güvenli giriş sırasında çalışmaz.
- Güncelleme denetimi: günde bir kez ("Check for updates automatically" kapalı değilse) AllInOneIME https://allinoneime.com/update.json dosyasını ve imzasını indirir; istek hiçbir tanımlayıcı ve yazdığınız hiçbir şeyi içermez. Bir güncelleme, GitHub sürümünden, yalnızca Update'e tıkladığınızda indirilir.
- Uzantı kaynakları: git, Mac'inizde, sizin adınıza, yalnızca eklediğiniz kaynaklar için çalışır: kendi kendine denetlenen kaynaklar için günde bir kez fetch (sabitlenmiş bir kaynak için hiç), ve Check Now, Update veya Re-clone'a tıkladığınızda. Yalnızca deponun ana makinesiyle, kendi git ve SSH kurulumunuzla oturum açarak konuşur; yazdığınız hiçbir şey onunla birlikte gitmez.
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
make dmg          # the release installer, build/AllInOneIME-<version>.dmg (universal; signed if there's a Developer ID certificate, optionally notarized), and the in-app update, build/AllInOneIME-<version>-update.zip
make update-test  # the in-app updater end to end: a temporary install, a test server on 127.0.0.1, a test key (never the installed app)
```

`make selftest` ve `make realtest` ayarlarınıza bağlı değildir. Öz sınama kendi yapılandırmasını kullanır (AWS profili ve bölgesi sizinkinden alınan Amazon Bedrock, geri kalan her şey varsayılan); gerçek uygulama sınaması çalışırken sağlayıcıyı Bedrock'a ayarlar ve sonra sizinkini geri koyar. O an denetleyemedikleri başarısız sayılmaz, atlanır: o profil için kimlik bilgisi olmadan canlı Bedrock denetimleri ve güvenli giriş açıkken (ekran kilitli, bir parola alanı) yazılan her şey. Son satır geçen, başarısız olan ve atlanan denetimleri sayar; çalıştırmayı yalnızca başarısızlıklar başarısız kılar, atlananı olan bir çalıştırma INCOMPLETE ile, yazan hiçbir şey çalışmadıysa SKIPPED ile biter (BLOCKED: gerçek uygulama sınaması kilitli bir ekranda başladı), asla PASSED ile bitmez.

Kod düzeni:

- `Sources/AllInOneIMECore`: Bedrock istemcisi, SigV4, istemler (prompt'lar), iki düzeyli giriş durum makinesi (@ komutları ve ses hareketi dahil); AppKit bağımlılığı yok
- `Sources/AllInOneIMERime`: librime sarmalayıcısı
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
