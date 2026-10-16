<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · [繁體中文](README_zh-TW.md) · [日本語](README_ja.md) · [한국어](README_ko.md) · [Français](README_fr.md) · [Deutsch](README_de.md) · [Español](README_es.md) · [Português (Brasil)](README_pt-BR.md) · [Italiano](README_it.md) · [Русский](README_ru.md) · [Tiếng Việt](README_vi.md) · [ไทย](README_th.md) · **Bahasa Indonesia** · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · [Türkçe](README_tr.md)

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="Ikon AllInOneIME">

# AllInOneIME

### Perintah AI di setiap kolom teks di Mac Anda.

Ketik `@improve`, `@translate` atau `@question` di aplikasi apa pun, tekan ⏎, lalu pilih hasilnya.<br>
Tanpa menyalin ke jendela chat, tanpa berpindah aplikasi. Penyedia AI Anda sendiri, kunci Anda sendiri.

[![Rilis](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#instalasi)
[![Apple silicon dan Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#instalasi)
[![Lisensi: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![Unduhan](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[Unduh](https://allinoneime.com/download)** · **[Situs web](https://allinoneime.com)** · **[Dokumentasi](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[Ekstensi](../extensions.md)**

[Cara menggunakan](#cara-menggunakan) · [Perintah](#perintah--beta) · [Perintah buatan sendiri](#perintah-buatan-sendiri) · [Bahasa](#input-dan-terjemahan) · [Suara](#input-suara) · [Instalasi](#instalasi) · [Privasi](#privasi)

<br>

<img src="../en/demo.png" width="820" alt="@translate dan sebuah kalimat, lalu ⏎: satu baris masing-masing dalam bahasa Spanyol, Prancis, dan Jerman">

</div>

*Ini adalah terjemahan dari README berbahasa Inggris; jika keduanya berbeda, versi bahasa Inggris yang benar.*

> [!NOTE]
> Mulai 0.6.3, AllInOneIME ditandatangani dengan Developer ID dan dinotarisasi oleh Apple: tidak perlu lagi mengizinkannya di System Settings → Privacy & Security (Pengaturan Sistem → Privasi & Keamanan). Setelah memperbarui dari versi sebelumnya, macOS menanyakan kata sandi login Anda sekali untuk setiap kunci yang disimpan AllInOneIME di keychain: masukkan kata sandinya lalu klik "Always Allow" (Selalu Izinkan). Unduh AllInOneIME hanya dari [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) atau [allinoneime.com](https://allinoneime.com).

Metode input macOS dengan perintah AI di setiap kolom teks. Awali kalimat dengan `@` dan tekan ⏎ setelah selesai: `@improve` memoles tulisan Anda dan menawarkan beberapa versi tulis ulang, `@translate` menerjemahkannya ke bahasa-bahasa yang Anda pilih, `@question` mengajukan pertanyaan, `@agent` menyerahkannya ke coding agent (Claude Code, Gemini CLI, Kiro CLI …), dan `@open` menemukan file dan aplikasi atau membuka alamat web. Anda juga bisa menahan ⌥ kanan dan berbicara. Tanpa `@`, tombol yang Anda tekan diteruskan ke aplikasi seperti biasa. Metode input ini juga bisa mengetik bahasa Mandarin (pinyin, dibangun di atas Rime dan rime-ice), Prancis, Korea (Hangul), dan Hindi (Devanagari dari huruf Latin), serta menjalankan skrip Anda sendiri sebagai perintah @.

![@improve dan kalimat yang masih kasar, lalu ⏎: versi yang sudah dipoles, ditambah versi tulis ulang](../en/improve.png)

Untuk detail lebih lanjut (setiap perintah dan pengaturan, pemecahan masalah instalasi, privasi), lihat [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Dibuat oleh [Weijian Zhang](https://weijianz.com) di MicroZ LLC.

## Cara menggunakan

Tanpa `@`, metode input ini tidak mengganggu: dalam mode bahasa Inggris, huruf diketik langsung dan ⏎ adalah Return; tidak ada yang dikirim ke internet. Instalasi baru menulis bahasa Inggris; untuk juga mengetik bahasa Mandarin (pinyin), Prancis, Korea, atau Hindi, tambahkan bahasa tersebut di pengaturan (lihat [Input dan terjemahan](#input-dan-terjemahan)).

| Tombol | Fungsinya |
|---|---|
| Ketik pinyin, Space / angka | Dalam mode Mandarin: memilih kata, seperti di metode input pinyin mana pun |
| `@` (di awal kalimat) | Membuka daftar perintah: yang paling sering dipakai akhir-akhir ini lebih dulu, 5 sekaligus, digulir dengan ↑↓, roda tetikus, atau trackpad; atau ketik huruf untuk mencarinya (nama yang diketik lengkap lebih dulu, lalu nama yang diawali huruf itu, lalu nama yang mengandungnya). ⏎, Tab, Spasi, atau angka untuk memilih |
| ⏎ | Menjalankan perintah. Tetap berfungsi meski pinyin belum dipilih: pinyin dipilih lebih dulu, seperti dengan Space |
| Space, ⏎ / angka | Setelah hasil muncul: menyisipkan hasil yang disorot / yang bernomor itu; 0 adalah teks asli. ⏎ tetap menyisipkan meski lanjutan baru diketik setengah (lanjutan itu dibuang) |
| ⇧⏎ | Dengan lanjutan yang diketik setelah hasil AI: mengirimnya (pertanyaan berikutnya dalam percakapan `@question`, atau penyempurnaan). Saat perintah sedang diketik, atau pada hasil AI tanpa ketikan apa pun: menyisipkan apa yang Anda ketik apa adanya, termasuk `@command`. Pada hasil lain (`@open`, pengingat …) menyisipkan baris yang disorot, seperti ⏎. Pada hasil `@config` dan `@doctor`, ⇧⏎ tanpa ketikan apa pun tidak melakukan apa-apa |
| ⌘C | Menyalin hasil yang disorot (untuk `@open`, path-nya); panel kandidat tetap terbuka |
| ⌃V | Di dalam perintah (misalnya setelah `@improve `): menambahkan teks dari clipboard setelah yang sudah Anda ketik, alih-alih menempelkannya ke aplikasi. Beberapa baris digabung menjadi satu, maksimal 2000 karakter sekali tempel (`@note` mempertahankan jeda baris dan menerima hingga 20000). Berfungsi di aplikasi apa pun; tanpa perintah, tombol diteruskan ke aplikasi seperti biasa |
| ⌘V | Seperti ⌃V, tetapi beberapa aplikasi menangani ⌘V sendiri (terminal seperti Ghostty, iTerm2, dan Terminal, serta Notes) dan menempel ke aplikasi seperti biasa; di sana gunakan ⌃V |
| Esc, ⌫ | Kembali ke kalimat untuk melanjutkan penyuntingan; mengetik tanda baca atau angka setelah hasil muncul akan melanjutkannya. Setelah penyempurnaan: kembali ke hasil sebelumnya |
| Huruf, saat hasil AI sudah muncul | Lanjutan: setelah `@question` berarti pertanyaan berikutnya (lihat [Percakapan](#percakapan-dengan-question-baru)), setelah `@improve` atau perintah instruksi berarti instruksi seperti `shorter` (lihat [Menyempurnakan hasil](#menyempurnakan-hasil-baru)); ⇧⏎ mengirimnya. Setelah `@translate`, huruf melanjutkan kalimat, dan ⏎ menerjemahkannya lagi |
| ⌘⏎, ⌘1–⌘5 | Dalam percakapan `@question`: menampilkan tempat untuk melanjutkannya (Claude Code atau agent lain yang Anda pilih untuk `@agent`, Claude, ChatGPT, Gemini, atau menyalinnya); ⌘1, ⌘2 … memilih salah satunya |
| Klik sebuah baris | Di panel kandidat: memilihnya, seperti angkanya (sebuah kata, perintah di daftar, hasil, berkas `@open`, penerima, baris ekstensi); baris di bawah penunjuk disorot. Kolom teks tetap memegang fokus |
| Ketuk Shift | Jika ada lebih dari satu bahasa input: beralih ke bahasa berikutnya, sesuai urutannya (Inggris → Mandarin → Prancis → …, lalu kembali ke yang pertama) |
| Tahan ⌥ kanan | Berbicara, lepaskan untuk berhenti. Dalam bahasa yang sedang Anda ketik (Inggris, Mandarin, Prancis, Korea, atau Hindi). Di dalam perintah, teksnya ditaruh setelah perintah; jika tidak, teks langsung disisipkan |

## Perintah @ (beta)

| Perintah | Fungsinya |
|---|---|
| `@improve` | Memoles: 1–3 adalah tiga versi dalam bahasa kalimat itu sendiri, 4 dan seterusnya adalah gaya tulis ulang (ditambahkan dan diurutkan di pengaturan), 0 adalah teks asli. Tidak menerjemahkan; jika "@improve also translates" (@improve sekaligus menerjemahkan) diaktifkan, perintah ini bekerja seperti `@translate @improve` |
| `@translate` | Menerjemahkan ke bahasa-bahasa yang Anda tambahkan (pengaturan → "Translate", seret untuk mengubah urutan), satu baris per bahasa, tiga versi jika hanya ada satu bahasa; bahasa kalimat itu sendiri dilewati. `@translate @improve` bersama-sama menerjemahkan dan menulis ulang dalam satu permintaan |
| `@question` | Mengajukan pertanyaan; jawabannya muncul di kandidat, ⏎ atau Spasi menyisipkannya, ⌘C menyalinnya. Teruskan mengetik lalu ⇧⏎ mengajukan pertanyaan lanjutan: panel menjadi percakapan hingga 5 putaran, lalu menawarkan untuk melanjutkannya di Claude atau AI lain. Tanpa apa pun yang diketik setelahnya, perintah ini menampilkan 5 pertanyaan terakhir Anda, yang terbaru lebih dulu; mengetik akan menyaringnya (kata di bagian mana pun dari pertanyaan, tanpa membedakan huruf besar-kecil, termasuk bahasa Mandarin). Angka, ↑↓ lalu ⏎, atau klik langsung menampilkan jawaban tersimpan dari sebuah pertanyaan, secara offline, untuk disisipkan atau disalin seperti biasa; di sana ⌘R menanyakannya lagi untuk mendapatkan jawaban baru. Jika tidak ada yang cocok, atau tidak ada yang dipilih, ⏎ menanyakan apa yang Anda ketik |
| `@agent` | Menyerahkan tugas ke coding agent di Mac Anda, yang dipilih di Settings → General → "@agent hands it to" (@agent menyerahkannya ke): Claude Code (bawaan), Gemini CLI, Kiro CLI, atau perintah Anda sendiri (apa yang Anda ketik ditambahkan sebagai argumen terakhirnya). Claude Code secara bawaan berjalan di latar belakang, dengan notifikasi saat selesai (klik untuk membuka sesinya di Terminal dan melanjutkan), atau lihat `@tasks`; matikan "@agent runs in the background and notifies me" (@agent berjalan di latar belakang dan memberi tahu saya) untuk membukanya di Terminal. Agent lainnya terbuka di Terminal dengan apa yang Anda ketik sebagai pesan pertamanya. Masing-masing memakai login dan pengaturannya sendiri. Saat pertama kali membuka Terminal, macOS menanyakan apakah AllInOneIME boleh mengontrol Terminal: klik OK. (Sebelum 0.6.4 namanya `@claude`.) |
| `@tasks` | Menampilkan daftar tugas Claude di latar belakang (sedang dikerjakan / selesai / menunggu Anda) beserta balasan terakhirnya; ⏎ membuka salah satunya di Terminal, ⌘C menyalin balasannya |
| `@settings` | Langsung membuka jendela pengaturan (cukup dengan memilihnya) |
| `@config` | Mengubah pengaturan sesuai cara Anda menjelaskannya: `@config output languages English and French`, `@config use Chinese in WeChat`, `@config candidates in a column`. ⏎ menampilkan perubahannya, lama → baru; ⏎ (atau 1) menerapkannya, Esc membatalkan, ketik lagi lalu tekan ⇧⏎ untuk menyempurnakannya; ⌘Z atau `@config undo` mengembalikannya. Lihat [Mengubah pengaturan dengan menjelaskannya](#mengubah-pengaturan-dengan-menjelaskannya-baru) |
| `@doctor` | Memeriksa penyiapan Anda di Mac ini dan memperbaiki apa yang bisa diperbaiki dengan aman: ⏎ menampilkan hasilnya, masalah lebih dulu; angka memperbaiki yang itu, ⏎ memperbaiki yang aman, melalui pratinjau `@config`. `@doctor why doesn't translate work` juga meminta AI menjelaskan kemungkinan penyebabnya. Lihat [Memeriksa penyiapan Anda](#memeriksa-penyiapan-anda-baru) |
| `@open` | Menampilkan file, folder, dan aplikasi yang cocok sambil Anda mengetik (Spotlight). Beberapa kata kunci bisa dipakai, dipisahkan spasi: masing-masing harus ada di path, setidaknya satu di nama (nama folder standar berlaku untuk isinya: `downloads pdf` menemukan PDF di Downloads). Aplikasi dan folder standar juga bisa ditemukan dengan nama Mandarinnya, dan antarmuka berbahasa Mandarin menampilkannya dengan nama tersebut. Yang pernah Anda buka dengan `@open` muncul lebih dulu, lalu aplikasi dan folder-folder tadi, lalu file yang baru dipakai atau diubah; jika pencarian nama hanya menemukan dua file atau kurang dan tidak ada aplikasi atau folder seperti itu, file di folder home Anda juga dicari berdasarkan isinya, dan baris-baris tersebut ditandai "content" (isi); jika tidak ada hasil lain, ⏎ menampilkan daftarnya untuk dipilih alih-alih membuka yang pertama. Dengan alamat web (`github.com`, `localhost:3000`, `https://…`), baris pertama adalah "open in the browser" (buka di browser) dan isi file tidak dicari; file yang namanya persis seperti itu (misalnya `MANIFEST.in`) muncul lebih dulu. Teks yang diawali `~/` atau `/` adalah path: Tab melengkapinya dan masuk ke dalam folder; ⏎ membuka, ⌘C menyalin path-nya |
| `@note` | Menyimpan teks ke aplikasi Notes, di folder bernama AllInOneIME (dibuat jika belum ada); tidak ada yang disisipkan. Teks yang ditempel mempertahankan jeda barisnya, hingga 20000 karakter |
| `@reminder` | Menambahkan pengingat ke aplikasi Reminders, di daftar bernama AllInOneIME. Tulis waktunya di dalam teks; waktu dibaca di Mac, dan sebuah baris menampilkan apa yang terbaca: ⏎ atau Space menambahkannya, Esc kembali untuk menyunting. Jika ada jam, pengingat berbunyi pada jam itu; jika hanya tanggal, pengingat berlaku sepanjang hari |
| `@calculate` | Menghitung di Mac ini; hasilnya muncul di kandidat, ⏎ atau Space menyisipkannya: `@calculate 23*17` → `391`. Perintah ini juga berfungsi di dalam kalimat: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Menjalankan satu baris Python (`python3` milik Mac) dan menyisipkan hasilnya: nilai ekspresi terakhir dalam kode, misalnya `@py 2**100`, `@py import math; math.sqrt(2)`, atau jika tidak ada, apa yang dicetaknya. Tidak ditawarkan tanpa `python3` (command line tools Xcode menyertakannya) |
| `@js` | Menjalankan satu baris JavaScript dan menyisipkan hal yang sama: nilai ekspresi terakhir atau apa yang dicetak `console.log`, misalnya `@js [1, 2, 3].map(x => x * 2)`. Perintah ini memakai JavaScriptCore bawaan macOS, jadi tidak ada yang perlu diinstal; perintah ini tidak bisa membaca file, mengakses jaringan, atau menjalankan program lain |
| `@reportissue` | Melaporkan masalah: membuka halaman GitHub untuk issue baru di peramban Anda, dengan yang Anda ketik setelah perintah sebagai judulnya, serta "What happened / What you expected" (apa yang terjadi / apa yang Anda harapkan) untuk diisi. Perintah ini menambahkan versi aplikasi dan macOS, arsitektur Mac Anda, bahasa antarmuka dan input, paket bahasa yang terpasang, jenis penyedia AI (dan modelnya, jika model publik; jika tidak, "custom"), tombol aksi, serta berapa banyak perintah kustom, plugin, dan ekstensi yang Anda miliki, tidak pernah nama-namanya, teks Anda, path, atau kunci. ⏎ (atau tombol aksi Anda) lebih dulu menampilkan semuanya di panel kandidat; ⏎ lagi, atau klik pada barisnya, membuka halaman itu, tempat Anda membacanya dan mengeklik Submit (dengan akun GitHub Anda); Esc kembali. Juga ada di menu input ("Report an Issue…") dan Settings → About |
| `@imessage` | Mengirim iMessage: ketik nama, nomor telepon, atau email (nama Mandarin juga bisa lewat pinyin-nya, lengkap atau inisialnya) dan pilih penerima di panel kandidat (orang yang baru-baru ini Anda kirimi pesan muncul lebih dulu; nomor atau alamat lengkap juga bisa), lalu tulis pesannya (perintah di dalamnya seperti `@stock AAPL` dijalankan lebih dulu). ⏎ menampilkan "Send to Alex (…): message" di panel, ⏎ sekali lagi mengirimnya, Esc kembali ke penyuntingan; tidak ada yang diketik ke kolom teks. Saat pertama kali, macOS bertanya apakah AllInOneIME boleh mengakses Contacts dan mengontrol Messages: klik OK untuk keduanya |

Contoh: `@q` ⏎, ketik `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ menyimpan sebuah catatan. `@reminder call Bob tomorrow at 3pm` ⏎, periksa waktu yang terbaca, lalu ⏎ sekali lagi untuk menambahkannya. Setelah perintah dipilih, Anda juga bisa menahan ⌥ kanan dan berbicara. Dalam mode Mandarin, `@open` dan `@calculate` beralih sementara ke huruf Inggris dan kembali ke Mandarin setelah Anda selesai.

Kode untuk `@py` dan `@js` diketik dengan huruf Inggris, dan tanda baca lebar penuh (dari mode Mandarin) menjadi ASCII; tulis dalam satu baris, dengan `;` di antara pernyataan. Kode berjalan di proses terpisah, dihentikan setelah 10 detik atau dengan Esc kapan saja; jika terjadi error, baris pertama error ditampilkan, misalnya `ZeroDivisionError: division by zero`. Output dengan beberapa baris disisipkan sebagaimana dicetak; di terminal, output masuk sebagai satu baris (terminal menjalankan setiap baris yang diberikan kepadanya). Terminal di dalam editor (VS Code, Cursor, JetBrains) tidak bisa dibedakan dari editornya sendiri, jadi di sana output perintah apa pun yang memiliki beberapa baris masuk apa adanya. Keduanya juga berfungsi di dalam kalimat perintah lain: `@reply the answer is @py 2**100`; beri tanda kutip pada kode yang mengandung spasi: `@question explain @py "sum(x * x for x in range(10))"`. Tidak sebaliknya: kode `@py` dan `@js` selalu berjalan persis seperti yang Anda ketik, dan `@commands` di dalamnya tidak dijalankan lebih dulu.

![Mengetik @ membuka daftar perintah; @question ditambah pertanyaan, lalu ⏎ untuk jawabannya](../en/commands.png)

![@open menemukan aplikasi sambil Anda mengetik; jika diawali /, itu adalah path: isi folder ditampilkan, Tab melengkapi](../en/open.png)

Jika `@` tidak diikuti perintah, seperti `@john`, `@` disisipkan seperti biasa, sehingga menyebut orang dengan @ di aplikasi chat tetap berfungsi. Jika diketik tepat setelah huruf, angka, `.`, `_`, atau `-`, seperti pada `bob@example.com` atau `ssh user@host`, `@` hanyalah teks: tidak ada daftar yang terbuka, di aplikasi mana pun, termasuk terminal. Saat daftar terbuka, ← → atau tombol yang tidak mungkin ada di nama perintah (`.`, `:`, `/`) menutupnya dan membiarkan apa yang Anda ketik (`@`, `@im`) apa adanya; di terminal, ← → saat itu hanya menutup daftar. `@question`, `@improve`, dan `@translate` mengirim ke Bedrock milik Anda sendiri hanya ketika Anda menekan tombol aksi; `@open` hanya mencari di Mac ini; `@note` dan `@reminder` hanya masuk ke Notes dan Reminders di Mac ini; `@agent` memakai agent yang terinstal di Mac Anda (secara bawaan perintah `claude` milik Claude Code) dan akunnya sendiri, dan seperti biasa ia bertanya kepada Anda lebih dulu sebelum mengubah file atau menjalankan perintah. Tanpa agent itu terinstal, `@agent` tidak ditawarkan. `@imessage` hanya membaca Contacts di Mac ini (nama, nomor telepon, email), tidak pernah melewati AI, dan pesannya dikirim oleh Messages; tanpa aplikasi Messages, perintah ini tidak ditawarkan.

`@calculate` bekerja di Mac ini, secara offline: `+ - * /` (juga `× ÷`), `^` atau `**` untuk pangkat, tanda kurung, persen (`50%` adalah 0.5, `200*5%` adalah 10; seperti di kalkulator, persentase yang ditambahkan atau dikurangkan dihitung dari angka sebelumnya: `100+10%` adalah 110, `100-10%` adalah 90), fungsi `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` berbasis 10, sudut dalam radian, `round(x, 2)` mempertahankan dua desimal), serta konstanta `pi` (`π`) dan `e`. Angka dan tanda lebar penuh juga bisa dipakai. Aritmetika dihitung tepat dalam desimal, jadi `0.1+0.2` adalah `0.3`; hasil memiliki paling banyak 15 digit signifikan, dan bilangan bulat hingga 38 digit ditulis lengkap (`2^100` → `1267650600228229401496703205376`).

### Pada teks yang dipilih (baru)

Pilih teks di aplikasi mana pun (sebuah kalimat di Notes, sebuah paragraf di Mail), ketik `@improve`, `@translate`, `@question`, atau perintah lain yang menerima teks, lalu tekan ⏎: perintah bekerja pada pilihan itu, dan hasil yang Anda pilih menggantikannya. Pilihan tetap apa adanya, tetap terpilih, selama Anda mengetik: perintah ditulis di panel kandidat, yang baris pertamanya adalah yang Anda ketik dan baris berikutnya "On the selection: “…” (N characters)" (pada pilihan: N karakter). Esc, ⇧⏎, atau mengeklik di tempat lain membiarkan teks seperti semula; begitu pula jika Anda mengubah pilihan sementara itu, yang membatalkan perintah. Teks yang diketik setelah perintah adalah instruksi untuk `@improve` dan `@translate` (`@translate ja`, `@improve more formal`) dan pertanyaan untuk `@question` (`@question what does this mean`), tentang pilihan itu. `@open`, `@agent`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, perintah terminal, dan ekstensi skrip tidak memakainya: perintah-perintah itu mengambil apa yang Anda ketik, dan pilihan tetap apa adanya. Hingga 5000 karakter; tidak pernah dibaca selama input aman atau di terminal. Matikan di Settings → General → "Use the selected text" (gunakan teks yang dipilih) jika berperilaku aneh di suatu aplikasi.

### Menyempurnakan hasil (baru)

Selagi hasil `@improve`, perintah instruksi (milik Anda atau milik plugin), atau penulisan ulang teks yang dipilih ditampilkan, ketik apa yang ingin diubah, seperti `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese`, atau `用更口语的说法` (pinyin bisa dipakai, dan ketukan Shift berganti bahasa), lalu tekan ⇧⏎: hasil dikirim lagi ke AI bersama instruksi Anda, dan hasil baru menggantikannya di panel yang sama. ⏎ menyisipkan hasil yang dipilih, juga saat instruksi baru diketik setengah (instruksi itu dibuang). Sempurnakan lagi sesering yang Anda mau; baris teratas panel mencantumkan langkah-langkahnya ("Refined: shorter · more formal"), dan Anda bisa memilih baris kapan saja seperti biasa. Sebuah huruf memulai instruksi (ditampilkan sebagai "refine › …" di bagian atas panel); selama masih kosong, angka, Spasi, dan ⏎ memilih seperti sebelumnya, dan ⇧⏎ menyisipkan apa yang Anda ketik apa adanya. Penyempurnaan dimulai setelah hasil lengkap: mengetik saat hasil pertama masih mengalir akan melanjutkan kalimat, seperti sebelumnya. Selama penyempurnaan berjalan, Anda sudah bisa mengetik instruksi berikutnya; penyempurnaan tetap berjalan, dan ⇧⏎ menjalankan yang berikutnya begitu hasilnya masuk. Esc menghapus instruksi, lalu mundur satu langkah ke hasil sebelum penyempurnaan terakhir (selama penyempurnaan: menghentikannya), lalu kembali ke kalimat; ⌫ pada baris kosong mundur dengan cara yang sama. Pada teks yang dipilih, hasil yang Anda pilih tetap menggantikan tepat pilihan itu, yang tidak disentuh sampai saat itu. Penyempurnaan yang gagal (atau ditolak selama input aman) membiarkan hasil seperti semula, dengan instruksinya siap dicoba lagi dengan ⇧⏎. Penyempurnaan yang sama atas hasil yang sama dijawab dari cache. `@translate` tidak punya penyempurnaan: mengetik setelah hasilnya melanjutkan kalimat, dan ⏎ menerjemahkannya lagi.

### Percakapan dengan @question (baru)

Setelah `@question` menjawab, apa yang Anda ketik adalah pertanyaan berikutnya: ⇧⏎ mengajukannya, bersama pertanyaan dan jawaban sebelumnya, dan panel tumbuh menjadi percakapan, dengan putaran-putaran sebelumnya diredupkan sebagai baris Q / A dan jawaban terbaru di bawahnya. Baris teratas menunjukkan putaran mana yang berikutnya ("question 2/5 › …"). Setiap jawaban bisa disisipkan: dengan angkanya (1–5), ↑↓ lalu ⏎, atau klik; jawaban terbaru terpilih, dan ⌘C menyalin yang terpilih. ⏎ menyisipkannya meski pertanyaan baru diketik setengah (pertanyaan itu dibuang). Esc menghapus apa yang Anda ketik, lalu mundur satu putaran; di putaran pertama, keluar seperti sebelumnya. Panel membesar hingga sekitar setengah layar, lalu bergulir, dengan yang terbaru di bagian bawah.

Setelah 5 putaran (`questionRounds` di konfigurasi, 2–10), baris pertanyaan berikutnya menjadi "5 rounds in: continue in Claude or another AI" (sudah 5 putaran: lanjutkan di Claude atau AI lain), dengan pilihan bernomor ⌘1, ⌘2 …; ⌘⏎ menampilkannya di putaran mana pun (selagi jawaban masih masuk, tombol ini tidak melakukan apa-apa, dan tidak pernah sampai ke aplikasi). Apa yang Anda ketik saat itu menjadi pesan pertama di sana; hanya ⌘1, ⌘2 … yang mengirimnya (⇧⏎ tidak bertanya apa-apa lagi dan tidak membuka apa pun). Pertanyaan tentang teks yang dipilih membawa teks itu, dikutip sebagai blok tersendiri. Pilihannya:

- **Agent yang menerima tugas dari `@agent`**, dengan namanya (Claude Code secara bawaan, atau Gemini CLI, Kiro CLI, atau perintah Anda sendiri sesuai pilihan di Settings → General), jika terinstal: sesi interaktif di Terminal, dimulai dengan percakapan dan "Let's continue this discussion".
- **Claude** atau **ChatGPT** di web, dengan percakapan sudah terisi (percakapan panjang masuk ke papan klip: tempelkan).
- **Gemini** di web, dengan percakapan di papan klip untuk ditempelkan.
- **Copy the conversation** (salin percakapan), dalam Markdown (**Q:** / **A:**).

Mana saja, dan dalam urutan apa (yang pertama adalah bawaan): Settings → General → "Continue a conversation in" (lanjutkan percakapan di; `questionContinueIn` di konfigurasi). Dengan Apple Intelligence di Mac ini, percakapan panjang tidak muat di konteksnya yang kecil: jawaban tertua dipersingkat, lalu putaran tertua dihilangkan, dan panel menampilkan "earlier rounds shortened" (putaran sebelumnya dipersingkat). Percakapan disimpan di bawah pertanyaan pertamanya dalam pertanyaan terbaru, dan memilihnya menampilkan putaran-putarannya untuk dilanjutkan.

### Pertanyaan terbaru (baru)

`@question` tanpa apa pun yang diketik setelahnya menampilkan 5 pertanyaan terakhir Anda, yang terbaru lebih dulu, beserta kapan pertanyaan itu diajukan ("3 hours ago"). Mengetik akan menyaringnya: setiap kata di bagian mana pun dari pertanyaan, tanpa membedakan huruf besar-kecil (termasuk bahasa Mandarin tanpa spasi). Angka, ↑↓ lalu ⏎, atau klik langsung menampilkan jawaban tersimpan dari sebuah pertanyaan, tanpa online: Spasi atau ⏎ menyisipkannya, ⌘C menyalinnya, ⌘R menanyakannya lagi untuk jawaban baru (untuk percakapan: pertanyaan terakhirnya), Esc kembali ke daftar. Percakapan tersimpan menampilkan semua putarannya: ketik untuk melanjutkannya. Jika tidak ada yang cocok, atau tidak ada yang dipilih, ⏎ menanyakan apa yang Anda ketik. Jawaban baru untuk pertanyaan yang sama, atau percakapan yang berlanjut, menggantikan yang tersimpan.

- Pertanyaan hanya disimpan di Mac ini (lihat Privasi): tidak selama input aman, dan tidak pernah untuk pertanyaan tentang teks yang dipilih.
- Settings → General → "Remember recent questions" (ingat pertanyaan terbaru) mematikannya (`rememberQuestions` di konfigurasi); jika dimatikan di sana, pertanyaan juga dihapus. Jika dimatikan lewat `@config`, pertanyaan tetap disimpan, agar membatalkannya mengembalikan persis keadaan semula (pratinjaunya menyebutkan hal ini); "Clear (N)" (hapus) menghapusnya.

### Catatan dan pengingat

`@note` membuat catatan baru; baris pertamanya menjadi judul. Setelah menyalin teks, ⌃V setelah `@note ` (atau ⌘V, di luar terminal) menyimpannya beserta jeda barisnya, yang ditampilkan sebagai ↵ di dalam perintah. Jika Anda meninggalkan kolom teks (mengeklik tempat lain, berpindah aplikasi) atau menekan ⇧⏎ (sisipkan sebagaimana diketik) sebelum catatan yang memiliki jeda baris tersimpan, catatan itu tidak diketik ke aplikasi (di terminal, setiap baris akan dijalankan sebagai perintah): catatan itu justru ditaruh di clipboard ("The note wasn't saved; its text is on the clipboard" – catatan tidak tersimpan; teksnya ada di clipboard). Catatan satu baris disisipkan sebagaimana diketik.

`@reminder` membaca waktu seperti `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (tanggal 1-nya), `end of the year` (waktu dalam bahasa Mandarin juga). Hari dan jam boleh terpisah (`tomorrow call Bob at 5`); minggu dimulai pada hari Senin. Jam tanpa am atau pm (`at 5`) berarti jam berikutnya, tidak pernah antara tengah malam dan pukul 6 pagi; jam yang sudah lewat hari ini berarti besok, tetapi bagian hari yang masih berlangsung (`this afternoon`, `tonight`) berarti hari ini, sepanjang hari; tanggal yang sudah lewat tahun ini berarti tahun depan. Jika ditulis berulang (`standup every Monday at 9`), pengingat ditambahkan sekali saja, untuk kali berikutnya: kata-katanya tetap ada di judul dan barisnya bertuliskan "once only" (sekali saja). Baris konfirmasi menampilkan waktu yang terbaca, misalnya "tomorrow 3:00 PM" (mengikuti pengaturan 12/24 jam di Mac); jika salah, Esc kembali ke teks. Jika tidak ada jam atau tanggal, pengingat tidak memiliki waktu ("no date" – tanpa tanggal).

`@stock` dan sejenisnya di dalam kedua perintah ini tidak dijalankan: teks disimpan sebagaimana ditulis (mengetik `@` di sana tidak membuka daftar perintah). Saat pertama kali, macOS bertanya apakah AllInOneIME boleh mengontrol Notes (`@note`) atau mengakses Reminders (`@reminder`): izinkan. Jika belum Anda izinkan, izinkan AllInOneIME di System Settings → Privacy & Security → Automation (Notes) atau → Reminders. Jika penyimpanan gagal (misalnya karena tidak ada izin), pemberitahuannya menyebutkan alasannya dan teks kembali ke dalam perintah, untuk diperbaiki dan dikirim lagi; jika Anda harus memperbaiki sesuatu lebih dulu (izin, akun), teks juga ditaruh di clipboard (membuka System Settings mengambil fokus dari kolom teks). Jika Anda sudah pindah ke kolom teks lain atau sedang mengetik hal lain, teks justru ditaruh di clipboard ("Not saved; the text is on the clipboard." – tidak tersimpan; teksnya ada di clipboard).

### Perintah buatan sendiri

Di pengaturan, pada "Custom @ Commands" (perintah @ kustom), klik "Add Command…" (tambah perintah): beri nama dan pilih fungsinya (instruksi AI, program, program di Terminal, atau halaman web), atau mulai dari contoh. Perintah Anda muncul setelah perintah bawaan; nama hanya boleh berupa huruf Inggris dan tidak boleh sama dengan nama perintah bawaan; perintah berlaku mulai kalimat berikutnya. Perintah-perintah ini disimpan di `customCommands` dalam file konfigurasi (`~/.config/allinoneime/config.json`), yang juga bisa Anda sunting sendiri:

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | Fungsinya |
|---|---|
| `prompt` | Dikirim ke AI dengan `prompt` sebagai instruksinya; jawabannya muncul di kandidat, untuk disisipkan atau disalin (⌘C) |
| `run` | Menjalankan `argv` di latar belakang; apa yang dicetaknya muncul di kandidat (beberapa baris disisipkan sebagaimana dicetak, di terminal sebagai satu baris). Jika terjadi error, baris terakhirnya ditampilkan |
| `terminal` | Menjalankan `argv` di jendela Terminal baru; tidak ada yang disisipkan |
| `link` | Memasukkan teks ke alamat web `url` dan membukanya di browser default; tidak ada yang disisipkan |

- `{input}` diganti dengan apa yang Anda tulis setelah perintah, dan selalu tetap berada di dalam satu argumen tempatnya berada: tidak ada shell yang terlibat. Jika butuh shell, nyatakan secara eksplisit, seperti `sh` di atas (`zsh -c`).
- `stdin`: apa yang dikirim ke input standar program, dengan `{input}` juga diganti.
- `url` sebuah `link` harus `https://`, dengan `{input}` tepat satu kali, setelah `?` atau `#`; teksnya di-encode (spasi menjadi `%20`, baris baru `%0A`), paling banyak 4000 karakter.
- `run` dan `terminal` secara default mengetik huruf Inggris (seperti `@open`; dalam mode Mandarin, Mandarin kembali setelahnya), dan tanda baca lebar penuh menjadi ASCII. Atur `"ascii": false` untuk mempertahankan teks sebagaimana diketik.
- Program berjalan di folder home Anda dengan PATH dari login shell Anda (sehingga instalasi Homebrew, pyenv, dan nvm ditemukan). `run` menghentikan program setelah 10 detik (`timeoutSeconds`) atau jika outputnya terlalu banyak; Esc menghentikannya kapan saja.
- `summary` adalah deskripsi di daftar perintah (opsional).
- Jika program di `argv` tidak ditemukan (misalnya tidak ada `python3`), perintah tidak ditawarkan dan `@python …` disisipkan sebagai teks; setelah program diinstal, perintah muncul di kolom teks berikutnya.

`run` dan `terminal` menjalankan kode di Mac Anda: hanya tambahkan perintah yang Anda tulis sendiri dan Anda percayai. Perintah ini juga hanya berjalan ketika Anda menekan tombol aksi, dan tidak pernah selama input aman (secure input).

### Ekstensi skrip

Tambahkan perintah @ Anda sendiri sebagai program: skrip dalam bahasa apa pun (bash, Python, Node, Swift, …) dengan beberapa baris metadata di komentarnya. Taruh di `~/.config/allinoneime/extensions`, atau di folder yang Anda tambahkan di "Settings → Custom Commands → Script Extensions". Raycast Script Commands berfungsi apa adanya, dan folder yang sudah berisi skrip tersebut ditemukan lewat Spotlight.

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh` menjadi `@flights`. Tulis argumennya setelahnya, dipisahkan koma: `@flights beijing, new york` menjalankannya dengan `beijing` dan `new york` sebagai `$1` dan `$2` (koma tambahan tetap berada di argumen terakhir); argumen wajib yang dibiarkan kosong akan memberi tahu apa yang kurang alih-alih menjalankan skrip. Apa yang dicetaknya dipakai sesuai `output`-nya:

| `output` | Yang terjadi |
|---|---|
| `insert` (default) | Semuanya, dan setiap barisnya, untuk disisipkan |
| `show` | Ditampilkan di panel sambil dicetak (progres); tidak ada yang disisipkan. Tinggalkan kolom teks dan skrip tetap berjalan di latar belakang (hingga empat sekaligus) |
| `list` | Daftar dalam format Script Filter JSON milik Alfred, dijalankan ulang sambil Anda mengetik; memilih satu baris akan menyisipkan, membuka (alamat web, file, atau folder; tidak pernah sesuatu yang bisa dieksekusi), menyalin, atau menjalankan langkah kedua |
| `silent` | Baris terakhirnya ditampilkan dekat kursor; tidak ada yang disisipkan |

Sebuah perintah juga bisa tanpa input (`input none`: ⏎ pada namanya langsung menjalankannya), berjalan di `background` dan memberi tahu Anda saat selesai (panel bilah menu menampilkannya selama berjalan), menampilkan `status` di samping namanya di daftar perintah, atau bertanya lebih dulu (`confirm`). Perintah berjalan di foldernya sendiri dengan PATH dari login shell Anda dan variabel `ALLINONEIME_*`: bahasa antarmuka dan bahasa input, aplikasi tempat Anda mengetik, teksnya. Sebuah **bundle** adalah folder dengan `extension.json` yang menyebutkan perintah-perintahnya: perintah-perintah itu berbagi kode dan preferensi, yang ditampilkan di Settings (kata sandi disimpan di keychain). Settings menampilkan setiap perintah dengan sakelar, serta skrip yang tidak disertakan beserta alasannya.

Mode Raycast dipetakan sebagai berikut: `fullOutput` → `show`, `compact` dan `silent` → `silent`, `inline` dengan `refreshTime` → sebuah status. Protokol lengkapnya ada di [docs/extensions.md](../extensions.md); [Examples/extensions](../../Examples/extensions) berisi satu contoh untuk setiap jenis. Ekstensi menjalankan kode di Mac Anda: gunakan yang Anda percayai. Ekstensi hanya berjalan ketika Anda menjalankannya (status atau list sambil Anda mengetiknya), tidak pernah selama input aman, dan berhenti ketika metode input ditutup.

#### Sumber ekstensi (baru)

Sebuah bundle bisa berasal dari repositori Git, milik Anda atau tim Anda, dan tetap diperbarui dari sana. Settings → Custom Commands → Extension Sources → **Add from Link…** (tambahkan dari tautan): tempelkan alamat repositori (`git@github.com:you/my-extensions.git`, `ssh://…`, `https://…`; opsional sebuah branch, folder bundle di dalam repositori, dan tag atau commit untuk menyematkannya). AllInOneIME mengklonnya dengan **pengaturan git dan SSH Anda sendiri** (kunci, agent, ~/.ssh/config, credential helper), sehingga repositori privat berfungsi seperti di Terminal; aplikasi tidak pernah meminta atau menyimpan kata sandi. Hasil klon masuk ke `~/Library/Application Support/AllInOneIME/Sources/`: pertama ke folder persiapan tersembunyi, tidak pernah langsung ke folder ekstensi. (Jangan cantumkan nama, kata sandi, atau token di alamat https: credential helper milik git yang menyimpannya.)

- **Tinjau dulu.** Sebelum apa pun dimuat, Anda melihat bundle-nya, setiap perintah (nama, judul, deskripsi, keluaran), program yang dijalankannya, preferensinya, dan commit-nya, di bawah peringatan "This source isn't signed: it will run programs from <address>" (sumber ini tidak ditandatangani: sumber ini akan menjalankan program dari alamat tersebut). Hanya **Enable** (aktifkan) yang menambahkannya; Cancel (batal) menghapus hasil klon. Satu sumber cukup ditinjau sekali.
- **Pembaruan Anda yang menerapkan.** Sekali sehari (dan tidak lama setelah metode input dimulai) sumber di-fetch untuk melihat apa yang baru: Settings menampilkan "N updates" (N pembaruan) beserta commit-nya (subjek, penulis, tanggal) dan lencana di halaman. Tidak ada yang berubah sampai Anda mengeklik **Update** (perbarui), yang hanya melakukan fast-forward dan tidak menjalankan hook apa pun. Force push membuat sumber perlu ditinjau lagi: **Re-clone** (klon ulang) menampilkannya, dan hanya Enable yang memasang riwayat yang ditulis ulang (sampai saat itu versi yang sudah ditinjau tetap berjalan). Sumber yang disematkan ke tag atau commit tidak diperiksa. Pemeriksaan harian bisa dimatikan per sumber (`autoCheck`).
- **Galat** ditampilkan dengan kata-kata git sendiri, disertai "This uses your own git and SSH setup; check that `git ls-remote <url>` works in Terminal" (ini memakai pengaturan git dan SSH Anda sendiri; periksa apakah perintah itu berjalan di Terminal), dan pengingat Anda sendiri di bawahnya jika Anda mengaturnya (`authHint` di konfigurasi).
- **Remove** (hapus) memindahkan hasil klon ke Tong Sampah; preferensi bundle disimpan untuk lain kali.
- Dari terminal: `AllInOneIME --add-source <url> [--path …] [--branch …] [--pin …]` (mencetak tinjauan dan mengaktifkannya; jalankan lagi setelah force push), `--update-sources` (melakukan fast-forward pada setiap sumber yang sudah ditinjau dan tidak disematkan), `--list-extensions` (pada `~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME`).
- Hanya kode yang sudah ditinjau yang dimuat: folder sumber di daftar muat yang belum ditinjau di Mac ini (konfigurasi yang disalin) dilewati. git tidak pernah menunggu jawaban: tanpa terminal dan tanpa prompt, sehingga kunci host yang tidak dikenal atau permintaan kata sandi langsung gagal.

Konfigurasi menyimpannya sebagai `extensionSources`; struktur repositori ada di [docs/extensions.md](../extensions.md#10-extension-sources).

### Plugin

Plugin adalah perintah `@` siap pakai untuk hal-hal yang tidak dibutuhkan semua orang, seperti `@stock AAPL 600519 700` untuk harga saham. Setelah diinstal, plugin berfungsi seperti perintah lainnya; "Plugins" di pengaturan menampilkan apa yang terinstal dan ke mana masing-masing mengirim teks Anda, serta bisa menghapusnya. Plugin adalah JavaScript yang berjalan di proses terpisah: plugin hanya bisa menghubungi situs web yang dideklarasikannya (HTTPS), dan tidak bisa membaca file atau menjalankan program lain. "Browse Library…" (jelajahi pustaka) di bagian Plugins di pengaturan menginstalnya dari [pustaka plugin](https://github.com/MicroZ-LLC/AllInOneIME-plugins): sebelum menginstal, pustaka menampilkan situs web mana yang dihubungi sebuah plugin; indeks pustaka ditandatangani dan setiap file harus cocok dengannya. Versi yang lebih baru menampilkan tombol "Update"; tidak ada yang diperbarui secara otomatis. Plugin buatan Anda sendiri ditaruh di `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): ini plugin lokal, yang tidak pernah ditimpa oleh pustaka. Plugin "Link" tidak menjalankan kode: plugin ini memasukkan teks ke alamat web dan membukanya di browser, seperti `@x nice weather today`, yang membuka jendela penulisan X dengan teks yang sudah terisi; mengunggahnya atau tidak terserah Anda di halaman tersebut. Pustaka memiliki empat plugin seperti ini (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` mengonversi mata uang: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, satu baris dengan tanggal kursnya (kurs dari ExchangeRate-API). Cara menulis plugin: [docs/plugins.md](../plugins.md).

Perintah yang mengambil sesuatu (plugin dan program) juga berfungsi di dalam kalimat: `@reply tell her @stock AAPL is up today`. Perintah di dalam berjalan lebih dulu, outputnya menggantikan posisinya, dan perintah luar bekerja pada hasilnya. Argumennya adalah kata setelah perintah, ditambah kode huruf kapital atau angka tepat setelahnya (`@stock AAPL TSLA`, `@stock 600519 700`); kata berhuruf kecil mengakhirinya (`@stock SNDK is good to buy` mencari SNDK). Tanda kutip menandainya secara persis: `@stock "aapl tsla"`. `@calculate` juga berfungsi di dalam kalimat; argumennya adalah seluruh ekspresi setelahnya, termasuk spasi, sampai teks lain: `@reply the total is @calculate 23 * 17 dollars`. Di dalam `@agent` dan perintah terminal, perintah-perintah ini tidak dijalankan: keduanya menerima teks sebagaimana ditulis (mengetik `@` di sana tidak membuka daftar perintah).

### Tombol aksi

Secara default ⏎; ubah di "Action key" (tombol aksi) di pengaturan (`actionKey` di konfigurasi): ⏎, "Tap ⌥" (ketuk ⌥, kiri atau kanan: tekan dan langsung lepaskan; menahan ⌥ kanan tetap untuk berbicara), ⌥Space, atau Space (tekan Space sekali lagi setelah kata-kata dipilih; dua kali dalam mode bahasa Inggris). Apa pun tombol aksinya, perintah @ juga berjalan dengan ⏎. Jika ⌥Space sudah menjadi pintasan untuk Alfred, Raycast, atau sejenisnya, aplikasi itu yang menerimanya lebih dulu.

### Mengetikkan hasil

Nyalakan "Type results out" (ketikkan hasil) di Settings → General (`typeOut` di konfigurasi) dan hasil sebuah perintah diketikkan ke aplikasi karakter demi karakter, seperti orang mengetik, alih-alih masuk sekaligus; pilihan pinyin tetap masuk sekaligus. Penggeser mengatur kecepatannya, dari 6 detik per karakter hingga 40 per detik (`typeOutRate`), dan "Speed up and slow down (like a person)" (mempercepat dan memperlambat, seperti orang) mengetik dalam semburan dengan kecepatan yang berubah-ubah (`typeOutVaries`). Esc menghentikannya di tempat; tombol lain mana pun mengetik sisanya sekaligus.

"Make occasional typos and fix them" (sesekali salah ketik lalu memperbaikinya, `typeOutMistakes`) membuatnya tampak lebih seperti manusia: sesekali tombol di sebelah tombol yang benar, disadari paling lambat tiga huruf kemudian, dihapus, lalu diketik ulang; sebuah huruf atau spasi diketik dua kali lalu dihapus; atau sebuah kata pendek diketik, dihapus, lalu diketik ulang. Beberapa per 100 karakter, tidak pernah dua berdekatan, dan tidak pernah di awal baris. Dalam kode, alamat web dan email, serta angka, salah ketik hanya berupa huruf atau angka yang salah, langsung diperbaiki (tidak pernah tanda kurung, tanda kutip, atau spasi yang salah, yang dipasangkan atau dijadikan inden oleh editor). Huruf yang salah adalah tetangga pada tata letak papan ketik Anda (QWERTY, AZERTY, QWERTZ…). Bahasa Mandarin, Jepang, dan Korea hanya ragu-ragu (dua karakter diketik, dihapus, lalu diketik ulang), tidak pernah dengan karakter yang salah.

Di kolom yang bisa menarik kembali salah ketik (tampilan teks Apple seperti TextEdit dan Notes, peramban, sebagian besar editor): jika diketik sampai akhir, atau dengan menekan tombol lain untuk mengetik sisanya sekaligus, teksnya persis hasilnya; Esc (atau meninggalkan kolom) di tengah salah ketik lebih dulu menghapus salah ketik itu, sehingga kolom berisi awal hasil yang persis. Jika kursor berpindah saat salah ketik terlihat (sebuah klik), salah ketik dihapus di tempatnya dan sisanya diketik tanpa salah ketik.

Salah ketik tidak pernah dibuat di terminal, maupun di aplikasi yang tidak memberi tahu metode input letak kursornya. Setiap kali, salah ketik pertama adalah yang sederhana (huruf yang salah, diperbaiki sekaligus), sampai kolom itu menunjukkan bahwa ia bisa menarik kembali salah ketik; selama salah ketik terlihat, metode input memeriksa sebelum setiap tombol bahwa kolom berisi apa yang diketiknya. Kolom yang mengabaikan di mana teks harus diganti tidak bisa menarik kembali salah ketik: di sana salah ketik pertama itu tetap ada, sehingga teks berakhir dengan selisih satu karakter (juga setelah Esc atau tombol lain), dan aplikasi itu tidak lagi mendapat salah ketik. Settings → General mencantumkan aplikasi-aplikasi itu di bawah sakelar salah ketik; "Forget apps where typos couldn't be fixed" (lupakan aplikasi yang salah ketiknya tidak bisa diperbaiki) membiarkan mereka mencoba lagi.

### Pengaturan per aplikasi (baru)

Settings → Apps memberi sebuah aplikasi pengaturannya sendiri, masing-masing opsional; yang tidak diatur sebuah aplikasi mengikuti pengaturan untuk semua aplikasi:

| Pengaturan | Contohnya | Di konfigurasi |
| --- | --- | --- |
| Bahasa input yang dipakai kolom teksnya saat mulai | Slack dalam bahasa Inggris, WeChat dalam pinyin | `inputLanguage` |
| Gaya tulis ulang yang ditawarkan `@improve` di sana | Mail formal dan bijaksana, Slack santai | `rewriteStyles` |
| Mengetikkan hasil, atau tidak | aktif di aplikasi chat, nonaktif di Mail | `typeOut` |
| Tanpa AI di aplikasi ini | `@improve`, `@translate`, `@question`, `@agent`, dan perintah instruksi Anda tidak mengirim apa pun di sana dan memberitahukannya; mengetik dan perintah lain tetap berfungsi | `noAI` |

"Add App…" (tambah aplikasi) menampilkan aplikasi yang baru-baru ini Anda ketik, atau memilih satu di /Applications. Menu input, lewat "This App: <nama>", punya sakelar cepat untuk aplikasi yang sedang Anda ketik (No AI, Type Results Out, bahasa awalnya). Di konfigurasi, semuanya ada di bawah `appProfiles`, menurut ID bundle: `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. ID bundle dicocokkan tanpa membedakan huruf besar-kecil (`com.apple.Mail` adalah `com.apple.mail` milik Mail). `@reportissue` menghitung aplikasi yang mengatur sesuatu, tanpa pernah menyebut namanya.

- Bahasa awal bekerja seperti bahasa input bawaan: kolom teks memakainya saat menjadi aktif, dan pergantian dengan Shift kemudian tetap berlaku untuk kolom-kolom aplikasi itu sampai pengaturannya berubah.
- Dengan No AI, perintah AI tetap ada di daftar @; menjalankan salah satunya menampilkan pemberitahuan dan menyimpan apa yang Anda tulis. Perintah terminal Anda sendiri (`"type": "terminal"`) menjalankan program, bukan AI, jadi tetap berfungsi di sana.

### Mengubah pengaturan dengan menjelaskannya (baru)

`@config` mengubah sebuah kalimat menjadi pengaturan: `@config output languages English and French`, `@config 微信里用中文，邮件里语气正式一点`, `@config candidates in a column`, `@config turn off the typos`, `@config use Claude`. ⏎ menampilkan perubahannya di panel kandidat, satu per baris, lama → baru, dengan label yang dipakai Settings ("Translation languages: English, Japanese → English, French", "Apps · WeChat · Starts in: Same as everywhere → Chinese"); belum ada yang diubah atau diketik. ⏎ (atau 1) menerapkan semuanya, Esc membatalkan, dan mengetik lagi lalu ⇧⏎ menyempurnakan usulan itu ("bahasa Jerman juga"; ⇧⏎ tanpa ketikan apa pun tidak melakukan apa-apa, dan ⏎ menerapkan usulan yang ditampilkan). Setelah diterapkan, ⌘Z selagi konfirmasi masih tampil, atau `@config undo` dalam 10 menit berikutnya, mengembalikan persis nilai yang dimiliki pengaturan-pengaturan itu sebelumnya.

- **Yang bisa diubahnya:** bahasa terjemahan dan bahasa input (dan bahasa bawaannya), gaya penulisan ulang, tata letak kandidat, mengetikkan hasil (aktif/nonaktif, kecepatan, mempercepat dan memperlambat, salah ketik), penggunaan teks yang dipilih, mengingat pertanyaan, menyembunyikan informasi sensitif (aktif/nonaktif, apa yang disembunyikan, kata yang ditambahkan), pemeriksaan pembaruan, pengaturan per aplikasi (aplikasi yang disebut sesuai cara Anda menyebutnya, dicari di antara aplikasi Anda berdasarkan nama atau bundle ID), dan penyedia AI: yang mana, profile Bedrock (dari `~/.aws`) dan region, model yang dikenal aplikasi untuk penyedia itu, dan base URL yang kompatibel dengan OpenAI (hanya `https://`).
- **Yang tidak pernah disentuhnya:** kunci API dan apa pun di keychain, perintah kustom, folder dan sumber ekstensi, plugin, daftar jargon, apa pun yang menjalankan program, dan semua pengaturan lainnya. Baris-baris itu ditolak, beserta alasannya, dan sisanya tetap bisa diterapkan.
- **Diperiksa seperti di Settings:** bahasa yang bukan bahasa, lebih dari 5 bahasa terjemahan, nilai di luar rentang, aplikasi yang tidak bisa dikenalinya, atau bahasa yang paketnya belum terpasang ("needs the Korean language pack: download it in Settings → Input", artinya perlu paket bahasa Korea: unduh di Settings → Input) ditolak baris demi baris; konfigurasi yang tidak valid tidak pernah ditulis.
- **Kunci:** fitur ini tidak pernah beralih ke penyedia yang tidak punya kunci (tidak ada di keychain maupun di shell Anda): barisnya berbunyi "Gemini API needs an API key: ⏎ opens Settings to add it (never sent to the AI); you can switch to it there" (Gemini API memerlukan kunci API: ⏎ membuka Settings untuk menambahkannya, tidak pernah dikirim ke AI; Anda bisa beralih ke sana di situ), dan menerapkannya membuka Settings → AI Provider dengan lembar kecil untuk kunci itu (Save untuk menyimpan, atau Save and Use untuk menyimpan sekaligus beralih), sementara baris lainnya tetap diterapkan. Jika ada kunci, penyedia berganti, Test Connection dijalankan dan hasilnya tampil di bawah konfirmasi. Kunci yang diketik di dalam kalimat dibuang sebelum apa pun dikirim.
- **Di Mac ini lebih dulu:** fitur ini memakai Apple Intelligence setiap kali Mac ini memilikinya (macOS 26), apa pun penyedia yang Anda pilih dan bahkan sebelum ada yang disiapkan, terbatas pada pengaturan dan nilai yang diizinkan, dengan pencarian di antara aplikasi, profile AWS, dan paket bahasa Anda. Tanpanya, penyedia Anda yang menjawab. Permintaan hanya berisi pengaturan yang diizinkan dan nilainya saat ini (tidak pernah kunci, juga tidak kata-kata yang Anda sembunyikan), dan penyembunyian informasi sensitif berlaku seperti untuk permintaan apa pun.

### Memeriksa penyiapan Anda (baru)

`@doctor` ⏎ memeriksa penyiapan di Mac ini dalam satu atau dua detik (uji koneksi tampil selama berjalan) dan menampilkan hasilnya di panel kandidat, satu per baris, ✗ masalah lebih dulu, lalu ⚠ peringatan, lalu ✓ yang sudah beres, masing-masing dengan perbaikan singkat: metode input (terpasang, aktif, ada di sumber input Anda), penyedia AI (kuncinya tersimpan atau kredensial profile Bedrock ditemukan, tidak pernah dibaca atau ditampilkan; Test Connection; Apple Intelligence), izin (Aksesibilitas, mikrofon jika Anda mendikte, mengontrol Catatan, Pengingat, Terminal, dan Pesan, ditanyakan ke macOS tanpa memunculkan dialog), input aman, paket bahasa dari bahasa input Anda, `config.json` (bisa dibaca, kunci yang tidak dikenal, nilai di luar rentang, bahasa yang tercantum dua kali, lebih dari 5 bahasa terjemahan), ekstensi dan plugin yang gagal dimuat, pembaruan, dan galat terbaru di log aplikasi itu sendiri.

Baris yang punya perbaikan diberi nomor: angka (atau klik) menampilkan apa yang dilakukannya di pratinjau `@config`, dan ⏎ menerapkannya; ⏎ pada daftar memperbaiki semua yang aman sekaligus (pengaturan diperbaiki, bahasa ganda dihapus, metode input diaktifkan lagi). Membuka panel Pengaturan Sistem, mengunduh paket bahasa, Check for Updates (membuka Settings), dan kolom kunci di Settings dipilih satu per satu. Perubahan pengaturan bisa diurungkan seperti milik `@config` (⌘Z, `@config undo`). Tidak ada perbaikan yang menghapus data Anda atau menyentuh kunci.

`@doctor <question>` (`@doctor why doesn't translate work`) menjalankan pemeriksaan, lalu AI menjelaskan kemungkinan penyebab dari hasilnya dan menandai perbaikan yang disarankannya (⏎ tetap hanya menerapkan yang aman; yang lain lewat nomornya). Di aplikasi dengan No AI, pemeriksaan tetap berjalan dan hanya pertanyaannya yang ditolak. Memakai Apple Intelligence jika Mac ini memilikinya, yang memanggil pemeriksaan yang dibutuhkannya sebagai alat; jika tidak, penyedia Anda, dan panel menyebutkannya. Hanya hasil pemeriksaan (tanpa path di luar `~`, tanpa kunci, tanpa teks Anda) dan pertanyaan Anda yang dikirim; pemeriksaan itu sendiri tidak mengirim apa pun selain permintaan Test Connection (hanya jika penyedia punya kunci atau kredensial untuk diuji).

## Panel bilah menu

<img src="../en/panel-swipe.png" width="520" alt="Panel bilah menu: kaca buram, dengan catatan, pengingat, dan tugas Claude di kartu-kartu; sebuah baris yang digeser ke kiri menampilkan tombol Remove">

Klik ikon AllInOneIME di bilah menu (tanda ∞ dan kursor, tanpa kotak; yang berkotak adalah sumber input) dan panel akan turun di bawahnya; klik di tempat lain untuk menutupnya:

- Notes: catatan yang disimpan dengan `@note`, 5 yang terbaru; klik salah satunya untuk membukanya di Notes.
- Reminders: pengingat yang belum selesai di daftar AllInOneIME di Reminders (`@reminder` menambahkan ke daftar itu), yang jatuh tempo paling cepat lebih dulu, 8 ditampilkan; klik lingkarannya untuk mencentangnya, atau judulnya untuk membuka Reminders.
- Claude Tasks: seperti `@tasks`, tugas-tugas Claude di latar belakang (yang diserahkan `@agent` ke Claude Code), hingga 30, 5 ditampilkan sekaligus: gulir untuk melihat lebih banyak, atau cari judul dan balasannya di kotak pencarian; dengan progresnya dan baris pertama balasan terakhir; klik salah satunya untuk membukanya di Terminal dan melanjutkan.

Geser sebuah baris (catatan, pengingat, atau tugas) ke kiri dengan dua jari untuk menampilkan tombol "Remove" (hapus), atau geser sampai habis untuk langsung menghapusnya; dengan mouse, klik kanan baris tersebut. Menghapus hanya menghilangkannya dari panel: catatan tetap ada di Notes, pengingat di Reminders (tidak diselesaikan), tugas di Claude Code.

Bagian atas panel menampilkan jumlahnya (seperti "2 reminders · 1 task running"; tugas yang menunggu Anda dihitung terpisah, seperti "1 waiting for you") dan tombol muat ulang. Panel tidak pernah mengambil fokus dari aplikasi tempat Anda mengetik: mencentang pengingat atau memuat ulang membiarkan aplikasi itu tetap di depan; hanya kotak pencarian tugas Claude, setelah diklik, yang mengambil keyboard. Ikonnya ditampilkan secara default; matikan di "Menu Bar Panel" di pengaturan.

Apa yang dibacanya, dan kapan:

- Notes: daftarnya adalah catatan milik panel sendiri (tetap disimpan meski panel tertutup), dan Notes tidak pernah dijalankan: hanya jika Notes sudah berjalan, dan AllInOneIME sebelumnya sudah diizinkan mengontrolnya, panel memeriksanya untuk judul yang diubah dan catatan yang dihapus.
- Reminders: daftar AllInOneIME dibaca saat panel turun, setiap 60 detik, dan saat pengingat berubah. Panel tidak pernah membuat macOS meminta akses dengan sendirinya: jika macOS belum menanyakannya kepada Anda, panel menampilkan "Allow Access to Reminders", dan hanya tombol itu yang meminta; jika Anda menolak, panel menampilkan "Open System Settings".
- Tugas Claude: panel menjalankan `claude agents` hanya selama panel terbuka: sekali saat turun, saat Refresh, dan saat `@agent` menyerahkan tugas; serta setiap 15 detik selama masih ada tugas yang belum selesai, tidak lagi setelah semuanya selesai. Balasan terakhir dibaca dari bagian akhir transkrip Claude Code di Mac ini (`~/.claude/projects`), dan hanya jika transkripnya berubah.
- Selama panel tertutup, semua ini tidak berjalan; panel hanya mencatat catatan yang disimpan `@note`.

## Input dan terjemahan

Di pengaturan:

- **Input languages** (bahasa input): satu sampai lima dari Inggris, Mandarin (pinyin), Prancis, Korea, dan Hindi, ditambahkan dengan + (selalu ada; berwarna abu-abu jika sudah lima). Instalasi baru dimulai hanya dengan bahasa Inggris. Kolom teks baru dimulai dengan bahasa pertama; ketuk Shift untuk bahasa berikutnya, sesuai urutannya; jika hanya ada satu, Shift tidak beralih.
  - **Prancis** diketik dengan tata letak keyboard-nya sendiri: AZERTY kecuali Anda memilih yang lain di kartunya. Tombol mati (dead key)-nya (^, ¨, `, ´, ~) juga menyusun huruf dari tata letak itu.
  - **Korea** mengetik Hangul dengan tata letak 2-set (Dubeolsik), setiap suku kata disusun sambil Anda mengetik (g k s → 한); Shift menghasilkan ㄲ ㄸ ㅃ ㅆ ㅉ dan ㅒ ㅖ.
  - **Hindi**: ketik kata-kata sesuai bunyinya dengan huruf Latin dan dapatkan Devanagari (namaste → नमस्ते). Kata-kata umum dieja seperti cara bahasa Hindi menuliskannya; selain itu, Space menyisipkan ejaan pertama, angka memilih ejaan lain, ⏎ menyisipkan huruf sebagaimana diketik, dan "." menjadi danda (।).
  - Nama perintah, teks `@open`, dan kode (`@py`, `@js`) diketik dengan huruf Latin apa pun bahasanya; bahasa itu kembali setelah perintah.
  - `@improve` mempertahankan kalimat Korea, Hindi, atau Prancis dalam bahasanya sendiri, dan `@translate` menerjemahkannya ke bahasa-bahasa Anda (Prancis dibedakan dari Inggris jika Prancis termasuk bahasa input Anda).
- **Language packs** (paket bahasa): aplikasi sudah dilengkapi bahasa Inggris (dan Prancis, yang hanya membutuhkan tata letak macOS). Mandarin, Korea, dan Hindi adalah paket yang Anda unduh saat menambahkannya: menambahkan Mandarin (pinyin) mengunduh kamusnya (sekitar 34 MB, 125 MB setelah diekstrak) dengan bilah progres, dan pinyin langsung berfungsi setelah selesai, tanpa memulai ulang; paket Korea (tabel tombol dan cara jamo membentuk suku kata) dan paket Hindi (huruf dan kata-kata umum) hanya beberapa kilobyte. Paket hanya berisi data (kamus, tabel, dan skema, tidak pernah kode), tercantum di indeks yang ditandatangani dan diperiksa terhadap SHA-256-nya sebelum dipakai, seperti plugin. Kartu setiap bahasa menampilkan paketnya (versi, ukuran, asalnya) dengan "Delete…", dan menghapus bahasa akan menawarkan untuk menghapus paketnya. Memperbarui dari 0.6.1 atau sebelumnya mempertahankan Mandarin tanpa unduhan: penginstal mempertahankan kamus yang disertakan versi lama.
- **Tata letak kandidat**: untuk memilih kata, kandidat pinyin dan Hindi secara bawaan berjajar ke samping (Horizontal), seperti metode input bawaan sistem: ← → memilih dan ↑↓ (atau - =) berganti halaman. Pilih Vertical di halaman Input, di bawah bahasa input, agar tersusun ke bawah (↑↓ memilih). Daftar perintah @ dan hasilnya selalu vertikal.
- **Fuzzy pinyin** (pinyin samar, dengan input Mandarin): bunyi yang tidak Anda bedakan bisa diketik dengan cara mana pun, misalnya z ↔ zh, n ↔ l, in ↔ ing. Di halaman "Input", pilih "Chinese (pinyin)" di bilah bahasa input, aktifkan "Fuzzy pinyin", dan pilih pasangannya; kamus di-deploy ulang dalam satu atau dua detik. Fitur ini menulis `rime_ice.custom.yaml` di folder pengguna Rime, dan tidak pernah menimpa file milik Anda sendiri di sana.
- **Translate (@translate)**: tambahkan bahasa-bahasa tujuan terjemahan (Spanyol, Prancis, Jerman, Jepang, Korea, Mandarin, Hindi, Bengali, Tamil, dan bahasa-bahasa utama India lainnya…) dan seret untuk mengurutkannya. Bahasa Hindi yang diketik dengan huruf Latin ("aap kaise ho") kembali dalam Devanagari. `@translate` menulis satu baris untuk setiap bahasa, dalam urutan ini (tiga versi jika hanya ada satu bahasa); bahasa kalimat itu sendiri dilewati. Instalasi baru menerjemahkan ke bahasa pertama dalam daftar bahasa pilihan Mac Anda yang bukan bahasa Inggris; jika hanya ada bahasa Inggris, `@translate` membuka halaman ini untuk menambahkan satu bahasa.
- **Keyboard layouts** (tata letak keyboard): bahasa Prancis diketik dengan tata letak yang dipilih di kartunya (`keyboardLayouts` di konfigurasi). Untuk bahasa lainnya, di bawah metode input, macOS mempertahankan tata letak Latin terakhir Anda (AZERTY, QWERTZ, Spanish, US International…), jadi Anda mengetik seperti biasa, termasuk `@` di mana pun letaknya di tata letak Anda, dan tombol mati juga menyusun huruf di teks perintah (⌥E lalu E → é, ^ lalu e → ê). Tata letak tanpa huruf Latin (Rusia, Hindi InScript) tidak bisa dipakai di bawah metode input: beralihlah ke tata letak itu dengan ⌃Space, atau tempel (⌃V) atau diktekan teks ke dalam perintah.
- `@improve` memoles dan menulis ulang tanpa menerjemahkan; `@translate @improve` bersama-sama menerjemahkan dan menulis ulang dalam satu permintaan. Aktifkan "@improve also translates" di pengaturan agar `@improve` selalu melakukannya.

## Gaya tulis ulang

Setelah baris 1–3 muncul versi tulis ulang, **dalam bahasa yang Anda ketik**: tulis ulang bahasa Inggris untuk bahasa Inggris, tulis ulang bahasa Mandarin untuk bahasa Mandarin. Pilih yang mana saja di pengaturan:

- Polish (poles): nada yang sama, lebih alami
- Concise (ringkas)
- Formal (formal): untuk atasan dan klien
- Casual (santai)
- Tactful (bijaksana)
- Jargon (jargon): bahasa khas Amazon dalam bahasa Inggris (bandwidth, circle back…), jargon perusahaan teknologi besar dalam bahasa Mandarin. Kabar buruk diperhalus, misalnya "this is a blocker bug" → "Oh! Looks like your team has the bandwidth to fix this minor issue!"

Versi tulis ulang yang hanya mengubah tanda baca atau mengulang baris lain tidak ditampilkan.

### Daftar jargon (istilah Anda sendiri)

Jargon tidak memiliki daftar istilah bawaan. Anda bisa menyiapkan daftar sendiri (misalnya, frasa-frasa yang dipakai tim Anda), dan model akan mengutamakan istilah-istilah tersebut. Di kandidat, baris Jargon mencatat arti istilah-istilah yang dipakainya.

Daftar ini adalah file teks dengan satu istilah per baris, opsional diikuti artinya, dipisahkan dengan "=", titik dua, atau Tab (Anda bisa menyalin dua kolom dari spreadsheet lalu menempelkannya). Baris yang diawali `#` adalah komentar:

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

Di "Rewrite Styles → Jargon list" di pengaturan, klik "New" untuk membuat daftar kosong di `~/.config/allinoneime/jargon.txt` dan membukanya; jika Anda sudah punya file daftar, klik "Choose File…" untuk memakainya di lokasinya sekarang (`jargonFile` di konfigurasi). Perubahan langsung berlaku. Hanya 150 istilah pertama yang dibaca. Jika "Jargon" dicentang, daftar ini dikirim ke Bedrock bersama setiap permintaan.

<img src="../en/panel-dark.png" width="420" alt="Panel kandidat dalam mode gelap">

## Input suara

<img src="../en/voice.png" width="340" alt="Tahan ⌥ kanan untuk berbicara">

Tahan ⌥ kanan dan berbicaralah; saat Anda melepaskannya, teks disisipkan. Suara dikenali dalam bahasa yang sedang Anda ketik (Inggris, Mandarin, Prancis, Korea, atau Hindi). Jika Anda mengetik perintah lebih dulu (misalnya `@improve `, `@question `) lalu berbicara, teks ditaruh setelah perintah dan ⏎ menjalankannya; Anda juga bisa menekan ⏎ tanpa melepaskan ⌥ kanan untuk menjalankannya begitu Anda selesai. Suara dikenali di Mac oleh pengenalan suara bawaan macOS (SpeechAnalyzer), dan tidak ada audio yang diunggah; fitur ini membutuhkan macOS 26 atau yang lebih baru.

Pertama kali:

- macOS bertanya apakah AllInOneIME boleh menggunakan mikrofon. Anda juga bisa mengeklik "Allow Microphone" di pengaturan sebelumnya.
- Jika Mac ini belum memiliki model suara untuk bahasa tersebut, model itu diunduh sekali, secara otomatis. Anda juga bisa mengunduhnya di pengaturan.

Perekaman baru dimulai setelah Anda menahan tombol sekitar 0,2 detik, jadi ketukan cepat pada ⌥ kanan tidak menyalakan mikrofon (jika tombol aksi diatur ke "Tap ⌥", ketukan menjalankan aksi). Jika Anda menekan tombol lain sambil menahannya (pintasan ⌥, ⌥←), itu dianggap pintasan dan tidak ada yang direkam juga. Menekan tombol lain apa pun saat sedang merekam akan membatalkan perekaman.

## Instalasi

Untuk menjalankannya dibutuhkan macOS 14 atau yang lebih baru, untuk input suara macOS 26 atau yang lebih baru. Penginstalnya universal: berfungsi di Mac dengan Apple silicon maupun Intel. Sejauh ini baru diuji di macOS 27 pada Apple silicon (build Intel hanya lewat uji mandirinya di bawah Rosetta).

1. Unduh `AllInOneIME-<version>.dmg` dari [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) (hanya dari sana) dan buka.
2. Klik dua kali "Install AllInOneIME" di dalamnya dan klik "Install". Metode input dipasang ke `~/Library/Input Methods` dan "AllInOneIME Settings" ke `~/Applications`. Hanya untuk pengguna ini; tidak perlu kata sandi administrator.
3. Penginstal ditandatangani dengan Developer ID dan dinotarisasi oleh Apple, sehingga pada kali pertama macOS hanya bertanya apakah akan membuka aplikasi yang diunduh dari internet: klik Buka. (Versi sebelum 0.6.3 tidak dinotarisasi: masing-masing harus diizinkan sekali di Pengaturan Sistem → Privasi & Keamanan → Tetap Buka.)

Setelah itu, AllInOneIME aktif dan ada di sumber input Anda; beralih ke sana dengan Ctrl+Space (tombol 🌐 hanya beralih jika "Press 🌐 key to" diatur ke "Change Input Source" di System Settings → Keyboard). Jika penginstal meminta Anda menambahkannya secara manual, berarti Mac ini tidak mengizinkan program mengaktifkannya, jadi tambahkan sendiri sekali: System Settings → Keyboard → Text Input → Input Sources → Edit… → + (kiri bawah) → English → AllInOneIME (metode input ini juga mengetik pinyin setelah Anda menambahkan bahasa Mandarin di bagian "Input" di pengaturannya).

Jika Ctrl+Space tidak membawa Anda ke AllInOneIME, atau beralih kembali ke U.S. setelah beberapa saat, jalankan penginstal lagi: penginstal akan menambahkan AllInOneIME kembali ke sumber input Anda.

Memperbarui: Settings → About → Check for Updates (periksa pembaruan). Saat ada versi baru, About memberitahukannya (juga satu baris di panel bilah menu), beserta yang baru; "Update to <version>" (perbarui ke <versi>) mengunduhnya, memeriksanya terhadap informasi pembaruan yang ditandatangani dengan kunci rilis AllInOneIME, memasangnya, lalu memulai ulang metode input. Pengaturan, paket bahasa, kata yang dipelajari, dan ekstensi Anda tetap ada, dan jika ada yang salah, versi yang Anda miliki dikembalikan. AllInOneIME memeriksa sendiri sekali sehari, di latar belakang (matikan dengan "Check for updates automatically" di About); tidak ada yang dipasang sampai Anda mengeklik. Ini berfungsi mulai 0.6.3; untuk memperbarui versi yang lebih lama, atau jika Anda lebih suka, pasang image disk versi baru di atasnya, tanpa mencopot pemasangan lebih dulu. Sebelum meningkatkan versi, baca [catatan perubahan](../../CHANGELOG.md): isinya perubahan setiap versi dan catatan peningkatan.

Memperbarui ke 0.6.3 dari versi sebelumnya: 0.6.3 adalah versi pertama yang ditandatangani dengan Developer ID, sehingga keychain belum mengenalinya sebagai aplikasi yang menyimpan kunci Anda. Saat pertama kali membutuhkan setiap kunci yang disimpannya (kunci API, login AllInOneIME Cloud, kata sandi ekstensi), macOS menanyakan kata sandi login Anda: masukkan lalu klik "Always Allow" (Selalu Izinkan). Setelah itu tidak ditanyakan lagi, juga setelah pembaruan berikutnya. Kunci Amazon Bedrock ada di `~/.aws/credentials`, yang tidak terpengaruh. Aksesibilitas (Pengaturan Sistem → Privasi & Keamanan → Aksesibilitas), yang dipakai untuk menempel ke terminal dan membaca teks yang dipilih, juga perlu satu langkah: jika AllInOneIME tercantum, hapus lalu aktifkan lagi saat diminta.

Jika Anda pernah menginstal AIPinyin (nama lama AllInOneIME), cukup instal: AIPinyin.app lama dan peluncur pengaturannya dihapus, dan entri di sumber input Anda mendapat nama baru, tanpa perlu menambahkannya lagi. Pengaturan, daftar jargon, dan kata-kata yang dipelajari dipindahkan ke folder baru (`~/.config/allinoneime` dan lainnya) saat pertama kali dijalankan, dan setiap folder lama dibiarkan sebagai tautan ke folder baru.

Untuk menghapus instalasi, buka "Install AllInOneIME" dan klik "Uninstall…". Pengaturan dan kata-kata yang dipelajari tetap disimpan.

### Membangun dari kode sumber

Membangun membutuhkan Xcode 26 atau yang lebih baru, karena input suara memakai SDK macOS 26.

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` mengunduh librime dan kamus rime-ice lalu memverifikasinya, melakukan build, dan menginstal ke lokasi yang sama, menambahkannya ke sumber input Anda dengan cara yang sama. Aplikasi yang diinstalnya tidak memiliki kamus Mandarin (kamus itu adalah paket bahasa Mandarin): instalasi yang sudah memilikinya mempertahankannya sebagai paket; jika tidak, `make install-pack` menginstal paket dari kamus di checkout, tanpa unduhan. `make status` menampilkan versi yang terinstal (`version:`) dan apakah metode input ada di sumber input Anda (`listed:`). Untuk menghapus instalasi: `make uninstall`.

## Menyiapkan AI

Terjemahan dan tulis ulang memakai penyedia AI Anda sendiri, dan biayanya masuk ke akun Anda: secara default Amazon Bedrock di akun AWS Anda, atau Claude API, Gemini, atau layanan yang kompatibel dengan OpenAI (lihat "Penyedia AI lain" di bawah).

### Amazon Bedrock

1. Aktifkan Bedrock di AWS console dan pastikan Anda bisa memakai model yang dipilih. Defaultnya adalah Claude Haiku 4.5; saat pertama kali memakai model Anthropic, Anda mengisi formulir kasus penggunaan sekali.
2. Gunakan profile AWS yang diizinkan `bedrock:InvokeModelWithResponseStream`: kunci statis di `~/.aws/credentials`, atau profile yang mendapatkan kredensial sementara (`credential_process`, sebuah role, SSO; lihat "Profile AWS" di bawah).
3. Buka "AllInOneIME Settings": Anda bisa menemukannya di Spotlight atau di Applications, atau membukanya dari ikon metode input di bilah menu → "Settings…". Pilih profile, region, dan model, lalu klik "Test Connection" (uji koneksi). "Language" di bagian atas jendela pengaturan bisa English atau Chinese; secara default ("System") mengikuti sistem (Mandarin jika bahasa Mandarin berada di atas bahasa Inggris dalam bahasa pilihan sistem, selain itu bahasa Inggris). Jendela pengaturan, petunjuk di panel kandidat, dan menu input semuanya mengikutinya.

<img src="../en/settings.png" width="420" alt="Jendela pengaturan">

#### Profile AWS

Profile apa pun yang bisa dipakai AWS CLI tanpa menanyakan apa pun kepada Anda akan berfungsi, dari `~/.aws/config` dan `~/.aws/credentials` (atau file yang ditunjuk `AWS_CONFIG_FILE` dan `AWS_SHARED_CREDENTIALS_FILE` di shell Anda). Di dalam satu profile, sumber pertama yang dimilikinya yang dipakai, sesuai urutan AWS CLI (profile yang memiliki `role_arn` sekaligus kunci dianggap role):

| Jenis | Di dalam profile | Diperbarui |
| --- | --- | --- |
| Role | `role_arn` dengan `source_profile` (jenis apa pun, termasuk berantai; profile yang menunjuk dirinya sendiri memakai kuncinya sendiri) atau `credential_source = Environment`; `role_session_name`, `external_id`, `duration_seconds` | diminta lagi lewat STS `AssumeRole` (di `region` profile, jika tidak ada us-east-1) 5 menit sebelum kedaluwarsa |
| SSO | `sso_account_id`, `sso_role_name` dengan `sso_session` dan bagian `[sso-session …]`-nya (atau `sso_start_url`, `sso_region` yang lama) | diambil lagi dengan login Anda yang tersimpan di cache 5 menit sebelum kedaluwarsa |
| Kunci statis | `aws_access_key_id`, `aws_secret_access_key` (dan `aws_session_token`) di `~/.aws/credentials` | dibaca ulang setiap permintaan |
| `credential_process` | `credential_process = /usr/local/bin/my-creds --profile dev` (dipecah seperti perintah shell, dijalankan tanpa shell, dengan PATH dari login shell Anda, di folder rumah Anda, paling lama 60 detik) | dijalankan lagi 5 menit sebelum `Expiration`-nya; jika tidak ada, saat AWS menolak kredensialnya |
| Kunci statis | kunci yang sama di `~/.aws/config` | dibaca ulang setiap permintaan |

Dengan profile "default" (atau tanpa profile yang dipilih), kunci di shell Anda didahulukan, seperti cara AWS CLI memakainya: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, dan `AWS_SESSION_TOKEN`. Profile yang Anda sebut namanya tidak pernah dicampur dengannya. `AWS_REGION` (atau `AWS_DEFAULT_REGION`) di shell Anda mengalahkan `region` milik profile, seperti di AWS CLI; kolom Region di Settings mengalahkan keduanya.

- **Otomatis:** kredensial yang punya masa berlaku disimpan di memori (tidak pernah ditulis ke disk) dan diambil lagi 5 menit sebelum kedaluwarsa; jika tersisa kurang dari 10 menit, permintaan tetap memakainya sambil mengambil yang baru di latar belakang, sehingga mengetik tidak perlu menunggu. Permintaan yang bersamaan menunggu satu pengambilan saja. Saat Bedrock menjawab bahwa kredensial sudah kedaluwarsa (`ExpiredTokenException` …), kredensial diambil lagi dan permintaan dikirim ulang, sekali saja.
- **SSO:** AllInOneIME memakai login yang disimpan AWS CLI di `~/.aws/sso/cache` (hanya membacanya) dan tidak bisa login untuk Anda, karena itu memerlukan browser. Saat login berakhir, panel kandidat menampilkan "SSO sign-in expired: run aws sso login --profile X" (login SSO kedaluwarsa: jalankan aws sso login --profile X): jalankan perintah itu di Terminal (Settings menyediakan Copy Command dan Open in Terminal; `@doctor` menawarkan perintahnya untuk disalin), dan AllInOneIME akan memakai login baru itu dengan sendirinya.
- **Tidak didukung:** `mfa_serial` (metode input tidak bisa meminta kode MFA kepada Anda: gunakan `credential_process` atau SSO, atau biarkan CLI Anda menyimpan kredensial di cache), `credential_source = Ec2InstanceMetadata` atau `EcsContainer` (tidak ada di Mac), dan web identity.
- **Batasan yang diketahui:** hanya PATH dan variabel file AWS (`AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`) yang diambil dari login shell Anda, juga untuk `credential_process` (bukan sisa lingkungannya). AllInOneIME tidak memperbarui token `sso_session` (refresh token CLI tidak dipakai: cache SSO hanya dibaca), jadi saat token di cache habis, jalankan `aws sso login` (AWS CLI juga memperbaruinya setiap kali Anda memakainya).
- **Settings → AI Provider** menampilkan setiap profile beserta jenisnya ("dev — Role via base") dan menyebutkan, untuk profile yang dipilih, kapan kredensialnya kedaluwarsa ("Role via base: credentials expire at 15:30", "SSO (signed in until 18:00)") atau apa yang harus dilakukan. Test Connection mengambil kredensial baru melalui seluruh rantai; `@doctor` melaporkan hal yang sama.
- Program dijalankan dan kredensial diminta dari AWS (`sts.<region>.amazonaws.com`, `portal.sso.<region>.amazonaws.com`) hanya saat sebuah permintaan atau Test Connection membutuhkannya: tidak pernah untuk menampilkan daftar profile, tidak pernah untuk `@config`.

### Penyedia AI lain: Claude API, Gemini, layanan yang kompatibel dengan OpenAI

Anda tidak memerlukan AWS: pilih salah satu di "AI Provider" di pengaturan, tempel API key, klik "Save", lalu "Test Connection".

| Penyedia | Model default | API key |
|---|---|---|
| Claude API | `claude-haiku-5-5` (tercepat, termurah; Sonnet 5.5 dan Opus 5.5 lebih cermat tetapi lebih lambat dan lebih mahal) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| Kompatibel dengan OpenAI | `gpt-6-luna` milik OpenAI (atau `gpt-5.4-mini`); "Common Services…" berisi DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter, dan Ollama di Mac ini: memilih salah satunya mengisi base URL-nya, lalu masukkan modelnya | Kunci layanan tersebut; atur Base URL ke alamatnya, misalnya `https://api.deepseek.com/v1`, atau `http://localhost:11434/v1` untuk Ollama di Mac ini |

- API key disimpan di keychain sistem, tidak pernah di file konfigurasi. Jika tidak ada di sana, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (atau `GOOGLE_API_KEY`), dan `OPENAI_API_KEY` dari shell Anda yang dipakai.
- Baris kunci API menunjukkan apakah kunci sudah diatur: "✓ Saved · ends in a1b2" (tersimpan · berakhiran a1b2: 4 karakter terakhirnya, disimpan bersama kunci agar kunci itu sendiri tidak perlu dibaca untuk menampilkannya) dengan Replace… (ganti) dan Remove… (hapus), "✓ From $OPENAI_API_KEY" (dari $OPENAI_API_KEY) untuk kunci dari shell Anda, atau "No API key yet" (belum ada kunci API) dengan kolom untuk menempelkannya.
- "Thinking" (penalaran) secara default rendah: metode input menunggu di setiap kalimat, dan penalaran yang lebih sedikit lebih cepat. Pilih "Not set" untuk model yang tidak mendukungnya.
- Jika Claude Opus 5.5 atau Sonnet 5.5 dipilih, permintaan menyertakan fallback penolakan dari Claude API (`fallbacks: "default"`): ketika classifier keamanan menolak, server mencoba ulang dengan model lain.
- Di file konfigurasi: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), serta `model`, `baseURL`, `effort`, dan `temperature` di bawah `anthropic`, `gemini`, dan `openai` (yang tidak diatur memakai nilai default).

### Apple Intelligence di Mac ini (macOS 26)

Di Mac dengan Apple Intelligence (Apple silicon, macOS 26 atau lebih baru, dinyalakan di Pengaturan Sistem → Apple Intelligence & Siri), pilih "Apple Intelligence (on this Mac)" di "AI Provider": tanpa kunci, tanpa biaya, dan tidak ada yang Anda ketik yang meninggalkan Mac. Ini memakai model bawaan macOS (framework Foundation Models), dengan instruksi dan format jawaban yang sama seperti penyedia lain, tetapi hanya contoh yang ditulis dalam bahasa kalimat itu sendiri (model kecil terlalu mudah meniru bahasa sebuah contoh).

- Ini model kecil: konteksnya sekitar 4K token (8K di macOS 27), sehingga paragraf panjang mungkin terlalu panjang untuknya, dan ia menguasai lebih sedikit bahasa (Inggris, Mandarin, Jepang, Korea, Prancis, Jerman, Spanyol, dan beberapa lainnya; tidak termasuk Hindi). Dalam kedua kasus itu ia memberitahukannya. Hasilnya di bawah model cloud, dan jawaban `@question`-nya tentang fakta dan kode sering salah.
- Di tempat yang tidak bisa memakainya, ia ditampilkan redup beserta alasannya (tidak didukung di Mac ini, dimatikan, model belum siap), dan pengaturan menautkan ke Pengaturan Sistem → Apple Intelligence & Siri. Sebelum macOS 26, ia tidak ditampilkan.
- "Output tokens", temperatur, dan batas waktu di "Model Settings" berlaku untuknya. Di berkas konfigurasi: `"provider": "apple"`.

### Menyembunyikan informasi sensitif (baru)

Settings → AI Provider → Privacy → "Hide sensitive information before sending" (sembunyikan informasi sensitif sebelum mengirim; nonaktif secara bawaan): sebelum permintaan dikirim ke AI, apa yang ditemukannya di teks Anda diganti di Mac dengan placeholder seperti `[EMAIL_1]` (nilai yang sama, placeholder yang sama), dan hasilnya mendapatkan kembali nilai aslinya sebelum ditampilkan atau disisipkan. Panel menampilkan "2 items hidden from the AI" (2 item disembunyikan dari AI). Setiap jenis bisa dimatikan:

| Jenis | Contohnya | Di konfigurasi |
| --- | --- | --- |
| Alamat email | `bob@example.com` | `emails` |
| Nomor telepon | `+1 (555) 123-4567`, `138 0013 8000` | `phones` |
| Nomor kartu pembayaran (diperiksa dengan Luhn) | `4111 1111 1111 1111` | `cards` |
| Kunci API dan token | awalan yang dikenal seperti `sk-` atau `ghp_`, string acak yang panjang | `keys` |
| Alamat IP | `203.0.113.42`, `2001:db8::1` | `ips` |
| Kata-kata Anda sendiri, tanpa membedakan huruf besar-kecil | nama sandi seperti `Project Atlas`, sebuah nama | `customWords` |

- Ini berlaku untuk `@improve`, `@translate`, `@question`, perintah instruksi dan plugin instruksi Anda, serta penyempurnaan hasilnya (placeholder yang sama), dengan semua penyedia, termasuk AllInOneIME Cloud dan Apple Intelligence. Entri daftar jargon yang berisi nilai yang harus disembunyikan tidak dikirim.
- Ia mengenali nilai yang berformat; ia tidak bisa mengenali nama atau alamat, jadi tambahkan itu sebagai kata-kata Anda sendiri. `@agent`, plugin yang mengambil data dari situs web (`@stock`) atau membukanya (`@x`), dan ekstensi skrip mengirim teks apa adanya. Selengkapnya di Privasi.
- Di konfigurasi: `"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`.

Semua pengaturan disimpan di `~/.config/allinoneime/config.json`; setelah ada perubahan, terjemahan berikutnya memakai pengaturan baru, tanpa memulai ulang. Kunci-kunci yang lebih baru:

| Kunci | Fungsinya | Default |
|---|---|---|
| `inputLanguages` | Bahasa input, satu sampai lima, yang pertama adalah default: `"en"` Inggris, `"zh"` Mandarin (pinyin), `"fr"` Prancis, `"ko"` Korea, `"hi"` Hindi, misalnya `["en", "zh"]`, `["fr", "en", "ko"]`. Mandarin, Korea, dan Hindi berfungsi setelah paketnya terinstal | `["en"]` (instalasi baru) |
| `keyboardLayouts` | Tata letak keyboard yang dipakai sebuah bahasa input, berdasarkan kodenya (sejauh ini hanya Prancis): `{"fr": "com.apple.keylayout.French-PC"}` | Prancis: `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | Bahasa tujuan `@translate`, secara berurutan: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | `@improve` juga menerjemahkan (seperti `@translate @improve`) | `false` |
| `voiceInput` | Tahan ⌥ kanan untuk berbicara | `true` |
| `actionKey` | Tombol aksi: `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Space), `"space"` (Space) | `"enter"` |
| `uiLanguage` | Bahasa antarmuka (jendela pengaturan, petunjuk panel kandidat, menu): `"zh"`, `"en"` | `null` (mengikuti sistem) |
| `rewriteStyles` | Gaya tulis ulang: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, misalnya `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | File daftar jargon Anda sendiri | `null` (yaitu `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | Ikon bilah menu dan panel dropdown-nya | `true` |
| `candidateLayout` | Kandidat pinyin dan Hindi: `"vertical"` (tersusun ke bawah) atau `"horizontal"` (berjajar ke samping; ← → memilih, ↑↓ berganti halaman) | `"horizontal"` |
| `fuzzyPinyin` | Pasangan pinyin samar: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | Perintah @ bekerja pada teks yang dipilih di kolom (lihat Pada teks yang dipilih) | `true` |
| `checkForUpdates` | Mencari versi baru sekali sehari, di latar belakang; tidak ada yang dipasang sampai Anda mengeklik | `true` |
| `agent` | Coding agent yang menerima teks dari `@agent`: `claude` (Claude Code), `gemini` (Gemini CLI), `kiro` (Kiro CLI), atau `custom` | `claude` |
| `agentCommand` | Perintah agent kustom, dengan apa yang Anda ketik ditambahkan sebagai argumen terakhir, misalnya `["muse", "--"]` | `[]` |
| `claudeInBackground` | `@agent` dengan Claude Code berjalan di latar belakang dan memberi tahu Anda (agent lain selalu terbuka di Terminal) | `true` |
| `rememberQuestions` | Menyimpan 5 pertanyaan `@question` terakhir Anda beserta jawabannya di Mac ini, ditampilkan di bawah `@question` (lihat Pertanyaan terbaru) | `true` |
| `questionRounds` | Jumlah putaran percakapan `@question` di panel sebelum menyarankan untuk melanjutkan di tempat lain, 2–10 | `5` |
| `questionContinueIn` | Tempat percakapan `@question` bisa dilanjutkan, berurutan, yang pertama adalah bawaan: `claudeCode` (agent yang menerima tugas dari `@agent`), `claudeWeb`, `chatgpt`, `gemini`, `copy` | agent milik `@agent` (jika terpasang), Claude, ChatGPT, salin |
| `appProfiles` | Pengaturan satu aplikasi, menurut ID bundle, masing-masing opsional: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI` (lihat Pengaturan per aplikasi) | `{}` |
| `redaction` | Menyembunyikan informasi sensitif dari AI (lihat Privasi): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`; setiap detektor (`emails`, `phones`, `cards`, `keys`, `ips`) aktif kecuali diatur ke `false` | `enabled: false` |

## Privasi

- Mengetik (bahasa Inggris dan pinyin) dan perhitungan `@calculate` sepenuhnya lokal. Hanya ketika Anda menekan tombol aksi pada `@improve`, `@translate`, atau `@question`, kalimat tersebut dikirim ke penyedia AI yang Anda pilih (Bedrock milik Anda sendiri, atau layanan yang kuncinya Anda tambahkan). Jika "Jargon" dicentang dan daftar jargon sudah diatur, daftarnya ikut dikirim. Menyempurnakan hasil (instruksi yang diketik setelahnya, lalu ⇧⏎) mengirim permintaan yang sama lagi beserta hasil yang ditampilkan dan instruksi Anda; pertanyaan lanjutan (⇧⏎) ikut mengirim percakapan sejauh ini.
- `@config` dan `@doctor <question>` mengirim teks ke sebuah model saat Anda menekan ⏎: ke Apple Intelligence di Mac ini setiap kali tersedia (tidak ada yang keluar dari Mac), jika tidak, ke penyedia Anda. `@config` mengirim kalimat Anda (kunci yang diketik di dalamnya dibuang lebih dulu) beserta nilai saat ini dari pengaturan yang boleh diubahnya: tidak pernah kunci, juga tidak kata-kata yang Anda sembunyikan dari AI (hanya jumlahnya), dan nama profile AWS Anda hanya jika kalimatnya tentang AWS atau Bedrock. `@doctor <question>` mengirim pertanyaan Anda beserta hasil pemeriksaan yang disamarkan: tanpa path di luar `~`, tanpa kunci, baris log diganti frasa tetap. Penyembunyian informasi sensitif berlaku untuk keduanya, seperti untuk permintaan apa pun. Pemeriksaan saja (`@doctor` tanpa apa pun setelahnya) tidak mengirim apa pun selain permintaan Test Connection, dan itu pun hanya jika penyedia punya kunci atau kredensial untuk diuji.
- Melanjutkan percakapan `@question` di tempat lain (⌘1 … setelah putaran terakhir, atau ⌘⏎) mengirimnya, beserta apa yang Anda ketik, ke layanan yang Anda pilih: agent yang menerima tugas dari `@agent` di Mac ini (secara bawaan Claude Code, milik Anthropic), claude.ai, chatgpt.com, atau gemini.google.com, lewat alamat web atau papan klip. Percakapan dikirim seperti yang Anda lihat: nilai yang disembunyikan dari permintaan ke AI (lihat di bawah) tetap ada apa adanya, karena Anda sendiri yang memilih mengirimnya ke sana. Tidak ada yang dikirim ke mana pun sampai Anda memilih salah satunya; "Copy the conversation" hanya menaruhnya di papan klip.
- Dengan AllInOneIME Cloud, kalimat melewati server pengembang menuju penyedia model (saat ini melalui OpenRouter): server hanya menyimpan hitungan, tidak pernah teksnya. Masuk (sign in) hanya menyimpan alamat email Anda.
- Menyembunyikan informasi sensitif (Settings → AI Provider → Privacy, nonaktif secara bawaan): sebelum permintaan apa pun dikirim (`@improve`, `@translate`, `@question`, perintah instruksi dan plugin instruksi Anda, dengan semua penyedia termasuk AllInOneIME Cloud), alamat email, nomor telepon, nomor kartu pembayaran (diperiksa dengan Luhn), kunci API dan token (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…`, dan string acak yang panjang), alamat IP, dan kata-kata Anda sendiri (nama sandi, sebuah nama) diganti di Mac dengan placeholder seperti `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]`; nilai yang sama mendapat placeholder yang sama. Hasil model mendapatkan kembali nilai aslinya sebelum ditampilkan atau disisipkan, dan panel menampilkan "2 items hidden from the AI". Hasil yang placeholder-nya diubah model hingga tak dikenali ditampilkan apa adanya, ditandai "⚠ placeholder changed". Entri daftar jargon yang berisi nilai tersembunyi tidak dikirim. Setiap jenis bisa dimatikan. Bentuk lebar penuh (`zhang＠example.com`, `１３８…`) juga ditemukan, dan sebuah nilai atau frasa boleh terpotong oleh baris baru. Ia mengenali nilai berformat seperti email, nomor, dan kunci; ia tidak bisa mengenali nama atau alamat (tambahkan itu sebagai kata-kata Anda sendiri), maupun huruf mirip dari abjad lain. Berlaku untuk permintaan ke layanan AI Anda; `@agent`, plugin yang mengambil data dari situs web (`@stock`) atau membukanya (`@x`), dan ekstensi skrip mengirim teks apa adanya. Di konfigurasi: `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- Suara hanya direkam selama Anda menahan ⌥ kanan dan dikenali di Mac; teks hasil pengenalan hanya dikirim dalam perintah-perintah di atas, ketika Anda menekan tombol aksi.
- Metode input membaca teks clipboard, sekali, hanya ketika Anda menekan ⌃V atau ⌘V di dalam perintah; konten yang ditandai tersembunyi oleh pengelola kata sandi tidak dibaca. Teks ditampilkan di perintah lebih dulu dan, sekali lagi, hanya dikirim ketika Anda menekan tombol aksi. Versi macOS terbaru bertanya apakah AllInOneIME boleh membaca clipboard: izinkan. Agar tidak ditanya setiap kali, atur izin tempel AllInOneIME ke selalu izinkan di System Settings → Privacy & Security.
- Di kolom kata sandi, macOS beralih ke keyboard-nya sendiri (U.S. atau ABC) dan kembali saat Anda meninggalkannya. Setiap kali aplikasi tempat Anda mengetik memegang input aman, AllInOneIME tidak menyusun teks dan tidak bisa merekam: tombol masuk sebagaimana diketik. Dan selama sistem berada dalam input aman (kolom kata sandi, Secure Keyboard Entry di Terminal, dll.), tidak ada yang dikirim ke AI.
- `@note` dan `@reminder` tidak dikirim ke AI: AllInOneIME hanya menyerahkan teks ke Notes dan Reminders di Mac ini, dan membaca waktu pengingat di Mac juga (apakah aplikasi-aplikasi itu menyinkronkannya ke perangkat Anda yang lain bergantung pada akunnya, seperti iCloud). Jadi keduanya juga berfungsi selama input aman.
- `@reportissue` (dan "Report an Issue…") tidak mengirim apa pun sendiri: ia membuka halaman issue baru GitHub di peramban Anda dengan judul yang Anda ketik serta versi, bahasa, jenis penyedia, dan jumlah yang disebutkan di atas, yang lebih dulu ditampilkan di panel kandidat. Tidak ada yang sampai ke GitHub kecuali Anda mengeklik Submit di sana.
- `@open` hanya mencari di Mac ini. Perintah ini mengingat apa yang Anda buka dengannya (200 terakhir), di preferensi milik metode input sendiri (bukan di config.json), untuk menampilkannya lebih dulu.
- Untuk "Add App…" di Settings → Apps, metode input menyimpan ID bundle dari 12 aplikasi terakhir yang Anda ketik, di preferensinya sendiri; tidak ada hal lain tentang aplikasi itu.
- `@question` mengingat 5 pertanyaan terakhir Anda beserta jawabannya dan kapan pertanyaan itu diajukan, hanya di Mac ini, di `~/Library/Application Support/AllInOneIME/recent-questions.json` (hanya bisa dibaca oleh akun pengguna Anda), untuk menampilkannya di bawah `@question`; jawaban tersimpan ditampilkan dari sana tanpa online. Tidak ada yang disimpan selama input aman, dan pertanyaan tentang teks yang dipilih sama sekali tidak disimpan (jawabannya tentang pilihan itu, yang akan ikut tersimpan di disk). Mematikan "Remember recent questions" di Settings → General juga menghapusnya; mematikannya lewat `@config` (`rememberQuestions` di konfigurasi) tetap menyimpannya, agar bisa dibatalkan dengan tepat. "Clear" menghapusnya.
- Untuk menampilkan catatan Anda, panel bilah menu menyimpan id dan baris pertama (hingga 80 karakter) dari 30 catatan terakhir yang disimpan dengan `@note`, di preferensi milik metode input sendiri, juga saat panel dimatikan.
- `@py` dan `@js` hanya berjalan ketika Anda menekan tombol aksi, dan hanya kode yang Anda ketik atau tempel sendiri: jawaban AI dan output perintah lain tidak pernah dijalankan sebagai kode. `@py` memakai `python3` milik Mac Anda, yang bisa membaca dan menulis file serta mengakses internet seperti di Terminal; `@js` berjalan di proses terpisah yang tidak bisa membaca file, mengakses jaringan, atau menjalankan program lain. Keduanya tidak berjalan selama input aman.
- Pemeriksaan pembaruan: sekali sehari (kecuali "Check for updates automatically" dimatikan), AllInOneIME mengunduh https://allinoneime.com/update.json beserta tanda tangannya; permintaan itu tidak membawa pengenal apa pun dan tidak ada yang Anda ketik. Pembaruan hanya diunduh, dari rilis GitHub, saat Anda mengeklik Update.
- Sumber ekstensi: git berjalan di Mac Anda, sebagai Anda, hanya untuk sumber yang Anda tambahkan: fetch sekali sehari untuk sumber yang memeriksa sendiri (tidak ada untuk sumber yang disematkan), dan saat Anda mengeklik Check Now, Update, atau Re-clone. git hanya berkomunikasi dengan host repositori, masuk dengan pengaturan git dan SSH Anda sendiri; tidak ada yang Anda ketik ikut terkirim.
- Log tidak mencatat apa yang Anda ketik. Untuk setiap metode input pihak ketiga, macOS memperingatkan "The developer can access anything you type with this input source" (pengembang dapat mengakses apa pun yang Anda ketik dengan sumber input ini); itu peringatan umum dari sistem.

## Pengembangan

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

`make selftest` dan `make realtest` tidak bergantung pada pengaturan Anda. Uji mandiri memakai konfigurasinya sendiri (Amazon Bedrock dengan profile AWS dan region dari milik Anda, selebihnya bawaan); uji di aplikasi sungguhan menyetel penyedia ke Bedrock selama berjalan lalu mengembalikan milik Anda. Apa yang tidak bisa mereka periksa saat itu dilewati, bukan dianggap gagal: pemeriksaan Bedrock langsung tanpa kredensial untuk profile itu, dan apa pun yang diketik selagi input aman aktif (layar terkunci, kolom kata sandi). Baris terakhir menghitung pemeriksaan yang lulus, gagal, dan dilewati; hanya kegagalan yang membuat proses gagal, dan proses yang ada lewatannya berakhir dengan INCOMPLETE, atau SKIPPED jika tidak ada yang mengetik yang berjalan (BLOCKED: uji di aplikasi sungguhan dimulai di layar terkunci), tidak pernah PASSED.

Struktur kode:

- `Sources/AllInOneIMECore`: klien Bedrock, SigV4, prompt, state machine input dua tingkat (termasuk perintah @ dan gestur suara); tanpa ketergantungan pada AppKit
- `Sources/AllInOneIMERime`: wrapper librime
- `Sources/AllInOneIME`: metode input InputMethodKit, panel kandidat, jendela pengaturan, pengenalan suara
- `Sources/AllInOneIMESettings`: peluncur "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: "Install AllInOneIME" di disk image: menginstal, memperbarui, dan menghapus instalasi

Paket bahasa memiliki pustakanya sendiri, terpisah dari plugin: repositori [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), disajikan di https://languages.allinoneime.com/, ditandatangani dengan kuncinya sendiri. `make pack` membangun arsipnya; arsip itu dipublikasikan sebagai release asset di sana (rilis `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), dan `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` menulis `packs.json` di sana dan menandatanganinya menjadi `packs.json.sig` dengan kunci paket bahasa dari keychain (`allinoneime-languages-signing`). Aplikasi membaca https://languages.allinoneime.com/packs.json, memeriksa tanda tangannya, lalu ukuran dan SHA-256 arsipnya. Untuk mencoba paket dari server lokal: `--test-key` menandatangani dengan kunci uji, dan `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Merilis versi (pembaru bawaan aplikasi membaca https://allinoneime.com/update.json, yang ditandatangani dengan kunci khusus rilis):

1. Naikkan versinya (`AppVersion.swift` dan tiga Info.plist; `AppVersionTests` memeriksa bahwa semuanya sesuai) dan perbarui catatan perubahan.
2. `make dmg NOTARY_PROFILE=<profile>`: `build/AllInOneIME-<version>.dmg` beserta `.sha256`-nya, dan `build/AllInOneIME-<version>-update.zip` (kedua aplikasi, seperti yang dibawa penginstal di image disk). Aplikasi dan image ditandatangani dengan sertifikat Developer ID Application di keychain, dan image dinotarisasi dengan profil keychain `xcrun notarytool` itu lalu di-staple.
3. Unggah keduanya ke rilis GitHub `v<version>` lalu terbitkan.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"` (masing-masing satu atau dua kalimat): menulis `site/public/update.json` (versi, build, dan macOS minimum yang dibaca dari aplikasi, alamat, ukuran, dan SHA-256 berkasnya, alamat catatan rilis, dan ringkasannya) lalu menandatanganinya menjadi `update.json.sig` dengan kunci dari keychain login (`allinoneime-releases-signing`; macOS mungkin meminta izin akses). Commit keduanya.
5. Terapkan situsnya (`cd site && npx wrangler@4 deploy`), hanya setelah berkas rilis bisa diunduh: aplikasi memeriksa sekali sehari, dan `AllInOneIME --check-update` menunjukkan apa yang mereka lihat.

Aplikasi memeriksa tanda tangan manifes dengan kunci publik bawaannya sebelum membacanya, tidak pernah memasang versi yang tidak lebih baru, hanya mengunduh lewat https dari allinoneime.com atau berkas rilis GitHub repositori, dan memasang arsipnya hanya setelah ukuran dan SHA-256-nya cocok dengan manifes, ID bundle, versi, dan tanda tangan kode kedua aplikasi lolos pemeriksaan, dan metode input baru berhasil dijalankan. Metode input lalu menyerahkan tugas kepada berkas eksekusinya sendiri sebagai pembantu (`--apply-update`), yang menunggunya keluar, menukar aplikasi seperti yang dilakukan penginstal (yang lama disisihkan, dikembalikan jika ada yang gagal), dan mendaftarkan yang baru. Untuk mencobanya dengan server lokal: `make update-test`, atau `--test-key` dengan `Scripts/build-update-manifest.swift` dan `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`.

Bundle ID masih `com.aipinyin.inputmethod.AIPinyin`: macOS memakainya untuk mengingat sumber input yang sudah ditambahkan dan izin mikrofon, jadi mengubahnya berarti harus menambahkan metode input dan memberikan izin itu lagi.

## Lisensi

Copyright © 2026 MicroZ LLC. Kode sumber tersedia di bawah [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): Anda boleh memakainya, membacanya, mengubahnya, dan membagikannya untuk keperluan apa pun kecuali produk pesaing. Setiap versi menjadi Apache-2.0 dua tahun setelah dirilis. Versi hingga 0.6.1 dirilis di bawah GPL-3.0 dan tetap tersedia di bawah lisensi tersebut.

Komponen pihak ketiga (librime dan plugin-pluginnya di bawah BSD-3-Clause; skrip Lua rime-ice dan paket bahasa Mandarin di bawah GPL-3.0) tercantum di [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
