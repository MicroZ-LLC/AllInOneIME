<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · [繁體中文](README_zh-TW.md) · [日本語](README_ja.md) · [한국어](README_ko.md) · [Français](README_fr.md) · **Deutsch** · [Español](README_es.md) · [Português (Brasil)](README_pt-BR.md) · [Italiano](README_it.md) · [Русский](README_ru.md) · [Tiếng Việt](README_vi.md) · [ไทย](README_th.md) · [Bahasa Indonesia](README_id.md) · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · [Türkçe](README_tr.md)

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="AllInOneIME-Symbol">

# AllInOneIME

### KI-Befehle in jedem Textfeld auf deinem Mac.

Tippe in einer beliebigen App `@improve`, `@translate` oder `@question`, drücke ⏎ und wähle das Ergebnis.<br>
Kein Kopieren in ein Chatfenster, kein App-Wechsel. Dein eigener KI-Anbieter, deine eigenen Schlüssel.

[![Release](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#installation)
[![Apple Silicon und Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#installation)
[![Lizenz: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![Downloads](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[Download](https://allinoneime.com/download)** · **[Website](https://allinoneime.com)** · **[Dokumentation](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[Erweiterungen](../extensions.md)**

[Verwendung](#verwendung) · [Befehle](#-befehle-beta) · [Eigene Befehle](#eigene-befehle) · [Sprachen](#eingabe-und-übersetzung) · [Spracheingabe](#spracheingabe) · [Installation](#installation) · [Datenschutz](#datenschutz)

<br>

<img src="../en/demo.png" width="820" alt="@translate und ein Satz, dann ⏎: je eine Zeile auf Spanisch, Französisch und Deutsch">

</div>

*Dies ist eine Übersetzung der englischen README; wo sie voneinander abweichen, gilt die englische Fassung.*

> [!NOTE]
> AllInOneIME ist noch nicht von Apple notarisiert: Erlaube es beim ersten Mal unter System Settings → Privacy & Security → Open Anyway (Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen). Lade es nur von den [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) oder von [allinoneime.com](https://allinoneime.com) herunter.

Eine Eingabemethode für macOS mit KI-Befehlen in jedem Textfeld. Beginne einen Satz mit `@` und drücke ⏎, wenn du fertig bist: `@improve` überarbeitet, was du geschrieben hast, und bietet einige Umformulierungen an, `@translate` übersetzt es in die Sprachen deiner Wahl, `@question` stellt eine Frage, `@claude` übergibt es an Claude Code, und `@open` findet Dateien und Apps oder öffnet eine Webadresse. Du kannst auch die rechte ⌥-Taste gedrückt halten und sprechen. Ohne `@` gehen deine Tastenanschläge wie gewohnt an die App. Außerdem tippt sie Chinesisch (Pinyin, auf Basis von Rime und rime-ice), Französisch, Koreanisch (Hangul) und Hindi (Devanagari aus lateinischen Buchstaben) und führt deine eigenen Skripte als @-Befehle aus.

![@improve und ein holpriger Satz, dann ⏎: überarbeitete Fassungen sowie Umformulierungen](../en/improve.png)

Mehr Details (jeder Befehl und jede Einstellung, Hilfe bei Installationsproblemen, Datenschutz) findest du im [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Entwickelt von [Weijian Zhang](https://weijianz.com) bei MicroZ LLC.

## Verwendung

Ohne `@` hält sie sich zurück: Auf Englisch werden Buchstaben direkt getippt und ⏎ ist der Zeilenschalter; nichts geht ins Netz. Eine Neuinstallation schreibt Englisch; um auch Chinesisch (Pinyin), Französisch, Koreanisch oder Hindi zu tippen, füge die Sprache in den Einstellungen hinzu (siehe [Eingabe und Übersetzung](#eingabe-und-übersetzung)).

| Taste | Was sie bewirkt |
|---|---|
| Pinyin tippen, Leertaste / Ziffern | Im chinesischen Modus: Wörter auswählen, wie in jeder Pinyin-Eingabemethode |
| `@` (am Satzanfang) | Öffnet die Befehlsliste: die zuletzt am häufigsten genutzten zuerst, 5 auf einmal, blätterbar mit ↑↓, dem Mausrad oder dem Trackpad; oder tippe Buchstaben, um einen zu finden (zuerst Namen, die damit beginnen, dann Namen, die sie enthalten). ⏎, Tab, Leertaste oder eine Ziffer wählt aus |
| ⏎ | Führt den Befehl aus. Funktioniert auch, wenn das Pinyin noch nicht ausgewählt ist: Es wird zuerst ausgewählt, wie mit der Leertaste |
| Leertaste, ⏎ / Ziffern | Sobald die Ergebnisse angezeigt werden: das hervorgehobene / nummerierte einfügen; 0 ist das Original |
| ⌘C | Kopiert das hervorgehobene Ergebnis (bei `@open` den Pfad); das Kandidatenfenster bleibt offen |
| ⌃V | In einem Befehl (z. B. nach `@improve `): hängt den Text aus der Zwischenablage an das Getippte an, statt ihn in die App einzufügen. Mehrere Zeilen werden zu einer, bis zu 2000 Zeichen auf einmal (`@note` behält die Zeilenumbrüche und nimmt bis zu 20000). Funktioniert in jeder App; ohne Befehl geht die Taste wie gewohnt an die App |
| ⌘V | Wie ⌃V, aber manche Apps verarbeiten ⌘V selbst (Terminals wie Ghostty, iTerm2 und Terminal sowie Notizen) und fügen wie gewohnt in die App ein; nutze dort ⌃V |
| Esc, ⌫ | Zurück zum Satz, um ihn weiter zu bearbeiten; einfach weitertippen setzt ihn fort |
| Umschalttaste kurz drücken | Bei mehreren Eingabesprachen: die nächste, in ihrer Reihenfolge (Englisch → Chinesisch → Französisch → …, dann zurück zur ersten) |
| Rechte ⌥ gedrückt halten | Sprechen, loslassen zum Beenden. In der Sprache, in der du tippst (Englisch, Chinesisch, Französisch, Koreanisch oder Hindi). In einem Befehl wird der Text dahinter angefügt; sonst wird er direkt eingefügt |

## @-Befehle (Beta)

| Befehl | Was er bewirkt |
|---|---|
| `@improve` | Überarbeiten: 1–3 sind drei Fassungen in der Sprache des Satzes, ab 4 die Umformulierungsstile (in den Einstellungen hinzugefügt und sortiert), 0 ist das Original. Keine Übersetzung; mit aktiviertem "@improve also translates" (@improve übersetzt auch) funktioniert er wie `@translate @improve` |
| `@translate` | Übersetzt in die Sprachen, die du hinzugefügt hast (Einstellungen → Translate, zum Umsortieren ziehen), je eine Zeile, drei Fassungen, wenn es nur eine ist; die Sprache des Satzes selbst wird übersprungen. `@translate @improve` zusammen übersetzt und formuliert in einer einzigen Anfrage um |
| `@question` | Stellt eine Frage; die Antwort erscheint in den Kandidaten, ⏎ oder Leertaste fügt sie ein, ⌘C kopiert sie |
| `@claude` | Übergibt die Aufgabe an Claude Code: standardmäßig im Hintergrund, mit einer Mitteilung, wenn sie fertig ist (klicke darauf, um die Sitzung im Terminal zu öffnen und weiterzumachen), oder sieh in `@tasks` nach. Er nutzt dein eigenes Claude Code (den Befehl `claude`) mit dessen eigener Anmeldung und eigenen Einstellungen. Schalte "@claude runs in the background" (@claude läuft im Hintergrund) in den Einstellungen aus, um es wie früher im Terminal zu öffnen. Wenn er zum ersten Mal das Terminal öffnet, fragt macOS, ob AllInOneIME das Terminal steuern darf: Klicke auf OK |
| `@tasks` | Listet die Claude-Aufgaben im Hintergrund (in Arbeit / fertig / wartet auf dich) mit ihren letzten Antworten auf; ⏎ öffnet eine im Terminal, ⌘C kopiert die Antwort |
| `@settings` | Öffnet sofort das Einstellungsfenster (Auswählen genügt) |
| `@open` | Listet passende Dateien, Ordner und Apps schon beim Tippen auf (Spotlight). Mehrere durch Leerzeichen getrennte Suchbegriffe funktionieren: Jeder muss im Pfad vorkommen, mindestens einer im Namen (der Name eines Standardordners gilt für seinen Inhalt: `downloads pdf` findet die PDFs in Downloads). Apps und die Standardordner werden auch über ihre chinesischen Namen gefunden, und eine chinesische Oberfläche zeigt sie so an. Was du mit `@open` geöffnet hast, kommt zuerst, dann Apps und diese Ordner, dann kürzlich genutzte oder geänderte Dateien; finden die Namen zwei Dateien oder weniger und keine App und keinen dieser Ordner, werden die Dateien in deinem Benutzerordner auch nach Inhalt durchsucht, diese Zeilen sind mit "content" (Inhalt) markiert; gibt es sonst nichts, listet ⏎ sie zur Auswahl auf, statt die erste zu öffnen. Bei einer Webadresse (`github.com`, `localhost:3000`, `https://…`) ist die erste Zeile "open in the browser" (im Browser öffnen), und Inhalte werden nicht durchsucht; eine Datei mit genau diesem Namen (etwa `MANIFEST.in`) kommt zuerst. Text, der mit `~/` oder `/` beginnt, ist ein Pfad: Tab vervollständigt ihn und wechselt in Ordner; ⏎ öffnet, ⌘C kopiert den Pfad |
| `@note` | Speichert den Text in der App Notizen, in einem Ordner namens AllInOneIME (wird angelegt, falls er fehlt); nichts wird eingefügt. Eingefügter Text behält seine Zeilenumbrüche, bis zu 20000 Zeichen |
| `@reminder` | Fügt eine Erinnerung zur App Erinnerungen hinzu, in einer Liste namens AllInOneIME. Schreibe die Zeit in den Text; sie wird auf dem Mac ausgewertet, und eine Zeile zeigt, was erkannt wurde: ⏎ oder Leertaste fügt sie hinzu, Esc geht zurück zum Bearbeiten. Mit Uhrzeit gibt es dann einen Alarm; nur mit Datum gilt sie ganztägig |
| `@calculate` | Rechnet auf diesem Mac; das Ergebnis erscheint in den Kandidaten, ⏎ oder Leertaste fügt es ein: `@calculate 23*17` → `391`. Funktioniert auch mitten im Satz: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Führt eine Zeile Python aus (das `python3` des Macs) und fügt das Ergebnis ein: den Wert des letzten Ausdrucks im Code, z. B. `@py 2**100`, `@py import math; math.sqrt(2)`, oder andernfalls die Ausgabe. Wird ohne `python3` nicht angeboten (die Befehlszeilenwerkzeuge von Xcode bringen es mit) |
| `@js` | Führt eine Zeile JavaScript aus und fügt dasselbe ein: den Wert des letzten Ausdrucks oder die Ausgabe von `console.log`, z. B. `@js [1, 2, 3].map(x => x * 2)`. Er nutzt das in macOS eingebaute JavaScriptCore, es muss also nichts installiert werden; er kann keine Dateien lesen, nicht aufs Netzwerk zugreifen und keine anderen Programme starten |
| `@imessage` | Sendet eine iMessage: Tippe einen Namen, eine Telefonnummer oder eine E-Mail-Adresse (einen chinesischen Namen auch per Pinyin, vollständig oder als Initialen) und wähle den Empfänger im Kandidatenfenster (wem du zuletzt geschrieben hast, steht oben; eine vollständige Nummer oder Adresse funktioniert auch), dann schreibe die Nachricht (Befehle darin wie `@stock AAPL` werden zuerst ausgeführt). ⏎ zeigt "Send to Alex (…): message" im Fenster, ein weiteres ⏎ sendet sie, Esc geht zurück zum Bearbeiten; ins Textfeld wird nichts getippt. Beim ersten Mal fragt macOS, ob AllInOneIME auf Kontakte zugreifen und Nachrichten steuern darf: Klicke bei beidem auf OK |

Beispiel: `@q` ⏎, `what is quantum computing` tippen, ⏎. `@note books to read: The Three-Body Problem` ⏎ speichert eine Notiz. `@reminder call Bob tomorrow at 3pm` ⏎, die erkannte Zeit prüfen, dann noch einmal ⏎, um sie hinzuzufügen. Sobald der Befehl gewählt ist, kannst du auch die rechte ⌥-Taste halten und sprechen. Im chinesischen Modus wechseln `@open` und `@calculate` vorübergehend zu lateinischen Buchstaben und kehren zum Chinesischen zurück, wenn du fertig bist.

Der Code für `@py` und `@js` wird in lateinischen Buchstaben getippt, und vollbreite Satzzeichen (aus dem chinesischen Modus) werden zu ASCII; schreibe ihn in eine Zeile, mit `;` zwischen den Anweisungen. Er läuft in einem eigenen Prozess, der nach 10 Sekunden oder jederzeit mit Esc beendet wird; bei einem Fehler wird dessen erste Zeile angezeigt, z. B. `ZeroDivisionError: division by zero`. Mehrzeilige Ausgabe wird so eingefügt, wie sie ausgegeben wurde; in einem Terminal als eine Zeile (ein Terminal führt jede Zeile aus, die es bekommt). Ein Terminal innerhalb eines Editors (VS Code, Cursor, JetBrains) lässt sich nicht vom Editor selbst unterscheiden, daher wird dort die mehrzeilige Ausgabe jedes Befehls unverändert eingefügt. Beide funktionieren auch im Satz eines anderen Befehls: `@reply the answer is @py 2**100`; setze Code mit Leerzeichen in Anführungszeichen: `@question explain @py "sum(x * x for x in range(10))"`. Umgekehrt nicht: Der Code von `@py` und `@js` läuft immer genau so, wie du ihn getippt hast, und `@commands` darin werden nicht zuerst ausgeführt.

![Ein getipptes @ öffnet die Befehlsliste; @question plus eine Frage, dann ⏎ für die Antwort](../en/commands.png)

![@open findet Apps schon beim Tippen; beginnt der Text mit /, ist er ein Pfad: Der Ordner wird aufgelistet, Tab vervollständigt](../en/open.png)

Folgt auf `@` kein Befehl, wie bei `@john`, wird das `@` wie gewohnt eingefügt, sodass @-Erwähnungen in Chat-Apps weiterhin funktionieren. `@question`, `@improve` und `@translate` senden nur dann an dein eigenes Bedrock, wenn du die Aktionstaste drückst; `@open` sucht nur auf diesem Mac; `@note` und `@reminder` gehen nur an Notizen und Erinnerungen auf diesem Mac; `@claude` nutzt das auf deinem Mac installierte Claude Code (den Befehl `claude`) und dessen eigenes Konto, und es fragt wie gewohnt zuerst nach, bevor es Dateien ändert oder Befehle ausführt. Ohne installiertes Claude Code wird `@claude` nicht angeboten. `@imessage` liest nur die Kontakte auf diesem Mac (Namen, Telefonnummern, E-Mail-Adressen), geht nie über die KI, und Nachrichten sendet die Nachricht; ohne die App Nachrichten wird er nicht angeboten.

`@calculate` arbeitet auf diesem Mac, offline: `+ - * /` (auch `× ÷`), `^` oder `**` für Potenzen, Klammern, Prozent (`50%` ist 0,5, `200*5%` ist 10; wie bei einem Taschenrechner bezieht sich ein addierter oder subtrahierter Prozentsatz auf das Vorhergehende: `100+10%` ist 110, `100-10%` ist 90), die Funktionen `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` ist zur Basis 10, Winkel sind im Bogenmaß, `round(x, 2)` behält zwei Nachkommastellen) und die Konstanten `pi` (`π`) und `e`. Vollbreite Ziffern und Zeichen funktionieren auch. Die Arithmetik ist dezimal exakt, also ergibt `0.1+0.2` genau `0.3`; Ergebnisse haben höchstens 15 signifikante Stellen, und ganze Zahlen mit bis zu 38 Stellen werden vollständig ausgeschrieben (`2^100` → `1267650600228229401496703205376`).

### Notizen und Erinnerungen

`@note` legt eine neue Notiz an; ihre erste Zeile ist der Titel. Nachdem du Text kopiert hast, speichert ⌃V nach `@note ` (oder ⌘V, außerhalb von Terminals) ihn mit seinen Zeilenumbrüchen, die im Befehl als ↵ angezeigt werden. Verlässt du das Textfeld (Klick woandershin, App-Wechsel) oder drückst ⇧⏎ (wie getippt einfügen), bevor eine Notiz mit Zeilenumbrüchen gespeichert ist, wird sie nicht in die App getippt (in einem Terminal würde jede Zeile als Befehl ausgeführt): Sie kommt stattdessen in die Zwischenablage ("The note wasn't saved; its text is on the clipboard"). Eine einzeilige Notiz wird wie getippt eingefügt.

`@reminder` versteht Zeitangaben wie `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (dessen 1.), `end of the year` (auch chinesische Zeitangaben). Tag und Uhrzeit können getrennt stehen (`tomorrow call Bob at 5`); Wochen beginnen am Montag. Eine Uhrzeit ohne am oder pm (`at 5`) ist die nächste, nie zwischen Mitternacht und 6 Uhr morgens; eine heute bereits vergangene Uhrzeit ist morgen, aber ein noch laufender Tagesabschnitt (`this afternoon`, `tonight`) ist heute, ganztägig; ein in diesem Jahr bereits vergangenes Datum ist das des nächsten Jahres. Als Wiederholung geschrieben (`standup every Monday at 9`), wird sie einmal hinzugefügt, für das nächste Mal: Die Wörter bleiben im Titel, und die Zeile zeigt "once only" (nur einmal). Die Bestätigungszeile zeigt die erkannte Zeit, z. B. "tomorrow 3:00 PM" (gemäß der 12/24-Stunden-Einstellung des Macs); ist sie falsch, geht Esc zurück zum Text. Enthält er weder Uhrzeit noch Datum, hat die Erinnerung keine ("no date").

`@stock` und Ähnliches innerhalb dieser beiden wird nicht ausgeführt: Der Text wird so gespeichert, wie er geschrieben ist (ein dort getipptes `@` öffnet die Befehlsliste nicht). Beim ersten Mal fragt macOS, ob AllInOneIME Notizen steuern (`@note`) oder auf Erinnerungen zugreifen (`@reminder`) darf: Erlaube es. Falls du es nicht getan hast, erlaube AllInOneIME unter Systemeinstellungen → Datenschutz & Sicherheit → Automation (Notizen) bzw. → Erinnerungen. Schlägt das Speichern fehl (etwa wegen fehlender Berechtigung), nennt die Mitteilung den Grund, und der Text kommt zurück in den Befehl, um ihn zu korrigieren und erneut zu senden; musst du zuerst etwas beheben (eine Berechtigung, ein Konto), kommt er außerdem in die Zwischenablage (der Wechsel in die Systemeinstellungen nimmt dem Textfeld den Fokus). Bist du in ein anderes Textfeld gewechselt oder tippst etwas anderes, kommt er stattdessen in die Zwischenablage ("Not saved; the text is on the clipboard.").

### Eigene Befehle

Klicke in den Einstellungen unter "Custom @ Commands" (eigene @-Befehle) auf "Add Command…" (Befehl hinzufügen): Gib ihm einen Namen und wähle, was er tut (eine Anweisung an die KI, ein Programm, ein Programm im Terminal oder eine Webseite), oder starte mit einem Beispiel. Deine Befehle stehen nach den eingebauten; Namen bestehen nur aus lateinischen Buchstaben und dürfen nicht wie ein eingebauter Befehl heißen; sie funktionieren ab dem nächsten Satz. Sie werden unter `customCommands` in der Konfigurationsdatei (`~/.config/allinoneime/config.json`) gespeichert, die du auch selbst bearbeiten kannst:

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | Was er bewirkt |
|---|---|
| `prompt` | Geht an die KI, mit `prompt` als Anweisung; die Antwort erscheint in den Kandidaten, zum Einfügen oder Kopieren (⌘C) |
| `run` | Führt `argv` im Hintergrund aus; die Ausgabe erscheint in den Kandidaten (mehrere Zeilen werden wie ausgegeben eingefügt, in einem Terminal als eine Zeile). Bei einem Fehler wird dessen letzte Zeile angezeigt |
| `terminal` | Führt `argv` in einem neuen Terminalfenster aus; nichts wird eingefügt |
| `link` | Setzt den Text in die Webadresse `url` ein und öffnet sie im Standardbrowser; nichts wird eingefügt |

- `{input}` wird zu dem, was du nach dem Befehl geschrieben hast, und bleibt immer innerhalb des einen Arguments, in dem es steht: Es ist keine Shell beteiligt. Für eine Shell gib das ausdrücklich an, wie bei `sh` oben (`zsh -c`).
- `stdin`: was an die Standardeingabe des Programms geht, wobei `{input}` ebenfalls ersetzt wird.
- Die `url` eines `link` muss mit `https://` beginnen, mit `{input}` genau einmal, nach dem `?` oder `#`; der Text wird kodiert (ein Leerzeichen wird zu `%20`, ein Zeilenumbruch zu `%0A`), höchstens 4000 Zeichen.
- `run` und `terminal` tippen standardmäßig lateinische Buchstaben (wie `@open`; im chinesischen Modus kehrt das Chinesische danach zurück), und vollbreite Satzzeichen werden zu ASCII. Setze `"ascii": false`, um den Text wie getippt zu behalten.
- Programme laufen in deinem Benutzerordner mit dem PATH deiner Login-Shell (so werden Installationen über Homebrew, pyenv und nvm gefunden). `run` beendet ein Programm nach 10 Sekunden (`timeoutSeconds`) oder wenn es zu viel ausgibt; Esc beendet es jederzeit.
- `summary` ist die Beschreibung in der Befehlsliste (optional).
- Wird das Programm in `argv` nicht gefunden (etwa kein `python3`), wird der Befehl nicht angeboten und `@python …` als Text eingefügt; sobald es installiert ist, erscheint der Befehl im nächsten Textfeld.

`run` und `terminal` führen Code auf deinem Mac aus: Füge nur Befehle hinzu, die du selbst geschrieben hast und denen du vertraust. Auch sie laufen nur, wenn du die Aktionstaste drückst, und nie während einer sicheren Eingabe.

### Skript-Erweiterungen

Füge eigene @-Befehle als Programme hinzu: ein Skript in einer beliebigen Sprache (bash, Python, Node, Swift, …) mit ein paar Zeilen Metadaten in seinen Kommentaren. Lege es in `~/.config/allinoneime/extensions` ab oder in einen Ordner, den du unter Settings → Custom Commands → Script Extensions hinzufügst. Raycast Script Commands funktionieren unverändert, und Ordner, die bereits welche enthalten, werden über Spotlight gefunden.

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh` wird zu `@flights`. Schreibe seine Argumente dahinter, durch Kommas getrennt: `@flights beijing, new york` führt es mit `beijing` und `new york` als `$1` und `$2` aus (weitere Kommas bleiben im letzten); bleibt ein Pflichtargument leer, wird statt der Ausführung angezeigt, was fehlt. Die Ausgabe wird so verwendet, wie sein `output` es angibt:

| `output` | Was passiert |
|---|---|
| `insert` (Standard) | Alles, und jede einzelne Zeile, zum Einfügen |
| `show` | Wird während der Ausgabe im Fenster angezeigt (Fortschritt); nichts wird eingefügt. Verlässt du das Feld, läuft es im Hintergrund weiter (bis zu vier gleichzeitig) |
| `list` | Eine Liste im Script-Filter-JSON von Alfred, die beim Tippen erneut ausgeführt wird; die Auswahl einer Zeile fügt ein, öffnet (eine Webadresse, Datei oder einen Ordner; nie etwas, das ausgeführt würde), kopiert oder startet einen zweiten Schritt |
| `silent` | Seine letzte Zeile neben dem Cursor; nichts wird eingefügt |

Ein Befehl kann auch ohne Eingabe auskommen (`input none`: ⏎ auf seinem Namen führt ihn aus), im Hintergrund laufen (`background`) und dich benachrichtigen, wenn er fertig ist (das Menüleistenfenster listet ihn währenddessen auf), einen `status` neben seinem Namen in der Befehlsliste anzeigen oder vorher nachfragen (`confirm`). Er läuft in seinem eigenen Ordner mit dem PATH deiner Login-Shell und `ALLINONEIME_*`-Variablen: Oberflächen- und Eingabesprache, die App, in der du tippst, der Text. Ein **Bundle** ist ein Ordner mit einer `extension.json`, die seine Befehle benennt: Sie teilen sich Code und Einstellungen, die in den Einstellungen angezeigt werden (Passwörter kommen in den Schlüsselbund). Die Einstellungen listen jeden Befehl mit einem Schalter auf, dazu die ausgelassenen Skripte mit Begründung.

Die Modi von Raycast werden so abgebildet: `fullOutput` → `show`, `compact` und `silent` → `silent`, `inline` mit `refreshTime` → ein Status. Das gesamte Protokoll steht in [docs/extensions.md](../extensions.md); [Examples/extensions](../../Examples/extensions) enthält eines jeder Art. Erweiterungen führen Code auf deinem Mac aus: Nutze nur solche, denen du vertraust. Sie laufen nur, wenn du sie ausführst (ein Status oder eine Liste beim Tippen), nie während einer sicheren Eingabe, und werden beendet, wenn die Eingabemethode beendet wird.

### Plugins

Plugins sind fertige `@`-Befehle für Dinge, die nicht jeder braucht, wie `@stock AAPL 600519 700` für Aktienkurse. Einmal installiert, funktionieren sie wie jeder andere Befehl; "Plugins" in den Einstellungen zeigt, was installiert ist und wohin jedes Plugin deinen Text sendet, und entfernt sie auch. Plugins sind JavaScript, das in einem eigenen Prozess läuft: Sie erreichen nur die Websites, die sie angeben (HTTPS), und können keine Dateien lesen und keine anderen Programme starten. "Browse Library…" (Bibliothek durchsuchen) unter Plugins in den Einstellungen installiert sie aus der [Plugin-Bibliothek](https://github.com/MicroZ-LLC/AllInOneIME-plugins): Sie zeigt vor der Installation, welche Websites ein Plugin kontaktiert; der Index der Bibliothek ist signiert, und jede Datei muss zu ihm passen. Bei einer neueren Version erscheint eine Schaltfläche "Update" (aktualisieren); nichts aktualisiert sich von selbst. Deine eigenen Plugins kommen nach `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): lokale Plugins, die von der Bibliothek nie überschrieben werden. "Link"-Plugins führen keinen Code aus: Sie setzen den Text in eine Webadresse ein und öffnen sie im Browser, wie `@x nice weather today`, das den Beitragseditor von X mit bereits eingesetztem Text öffnet; das Posten auf der Seite liegt bei dir. Die Bibliothek enthält vier davon (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` rechnet Währungen um: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, eine Zeile mit dem Datum des Kurses (Kurse von ExchangeRate-API). Ein eigenes schreiben: [docs/plugins.md](../plugins.md).

Befehle, die etwas abrufen (Plugins und Programme), funktionieren auch mitten im Satz: `@reply tell her @stock AAPL is up today`. Die inneren laufen zuerst, ihre Ausgabe tritt an ihre Stelle, und der äußere Befehl arbeitet mit dem Ergebnis. Das Argument ist das Wort nach dem Befehl plus die direkt folgenden Kürzel in Großbuchstaben oder Zahlen (`@stock AAPL TSLA`, `@stock 600519 700`); ein kleingeschriebenes Wort beendet es (`@stock SNDK is good to buy` fragt SNDK ab). Anführungszeichen grenzen es genau ab: `@stock "aapl tsla"`. `@calculate` funktioniert ebenfalls mitten im Satz; sein Argument ist der ganze Ausdruck danach, einschließlich Leerzeichen, bis zu anderem Text: `@reply the total is @calculate 23 * 17 dollars`. Innerhalb von `@claude` und Terminal-Befehlen werden sie nicht ausgeführt: Diese erhalten den Text so, wie er geschrieben ist (ein dort getipptes `@` öffnet die Befehlsliste nicht).

### Aktionstaste

Standardmäßig ⏎; ändere sie unter "Action key" (Aktionstaste) in den Einstellungen (`actionKey` in der Konfiguration): ⏎, Tap ⌥ (⌥ kurz antippen, auf beiden Seiten: drücken und sofort loslassen; das Halten der rechten ⌥-Taste bleibt fürs Sprechen), ⌥Leertaste oder Leertaste (drücke die Leertaste noch einmal, nachdem die Wörter ausgewählt sind; im englischen Modus zweimal). Unabhängig von der Aktionstaste laufen @-Befehle auch mit ⏎. Ist ⌥Leertaste bereits ein Kurzbefehl für Alfred, Raycast oder Ähnliches, bekommen diese ihn zuerst.

## Menüleistenfenster

<img src="../en/panel-swipe.png" width="520" alt="Das Menüleistenfenster: Milchglas, mit Notizen, Erinnerungen und Claude-Aufgaben auf Karten; eine nach links gewischte Zeile zeigt ihre Schaltfläche Remove">

Klicke auf das Symbol von AllInOneIME in der Menüleiste (das Zeichen aus ∞ und Cursor, ohne Rahmen; das umrahmte ist die Eingabequelle), und das Fenster klappt darunter auf; ein Klick woandershin schließt es:

- Notes (Notizen): die mit `@note` gespeicherten Notizen, die neuesten 5; klicke auf eine, um sie in Notizen zu öffnen.
- Reminders (Erinnerungen): die noch nicht erledigten Erinnerungen in der Liste AllInOneIME der App Erinnerungen (`@reminder` fügt sie dieser Liste hinzu), die am frühesten fälligen zuerst, 8 angezeigt; klicke auf den Kreis, um eine abzuhaken, oder auf den Titel, um Erinnerungen zu öffnen.
- Claude Tasks (Claude-Aufgaben): wie `@tasks` die Claude-Aufgaben im Hintergrund (was `@claude` übergibt), bis zu 30, 5 auf einmal angezeigt: scrolle für mehr, oder durchsuche ihre Titel und Antworten im Suchfeld; mit ihrem Fortschritt und der ersten Zeile der letzten Antwort; klicke auf eine, um sie im Terminal zu öffnen und weiterzumachen.

Wische eine Zeile (eine Notiz, eine Erinnerung oder eine Aufgabe) mit zwei Fingern nach links, um ihre Schaltfläche Remove (entfernen) anzuzeigen, oder ganz durch, um sie sofort zu entfernen; mit einer Maus klicke mit der rechten Maustaste darauf. Entfernen nimmt sie nur aus dem Fenster: Die Notiz bleibt in Notizen, die Erinnerung in Erinnerungen (nicht erledigt), die Aufgabe in Claude Code.

Die Kopfzeile zeigt die Anzahlen (etwa "2 reminders · 1 task running"; Aufgaben, die auf dich warten, werden getrennt gezählt, etwa "1 waiting for you") und eine Schaltfläche zum Aktualisieren. Es nimmt der App, in der du tippst, nie den Fokus: Das Abhaken einer Erinnerung oder das Aktualisieren lässt diese App im Vordergrund; nur das Suchfeld der Claude-Aufgaben übernimmt, sobald es angeklickt wird, die Tastatur. Das Symbol wird standardmäßig angezeigt; schalte es unter "Menu Bar Panel" in den Einstellungen aus.

Was es liest, und wann:

- Notizen: Die Liste ist die eigene Aufzeichnung des Fensters (die auch erhalten bleibt, während es geschlossen ist), und Notizen wird nie gestartet: Nur wenn Notizen bereits läuft und AllInOneIME zuvor erlaubt wurde, es zu steuern, prüft das Fenster dort auf geänderte Titel und gelöschte Notizen.
- Erinnerungen: Die Liste AllInOneIME wird gelesen, wenn das Fenster aufklappt, alle 60 Sekunden und wenn sich Erinnerungen ändern. Das Fenster bringt macOS nie von sich aus dazu, nach Zugriff zu fragen: Hat macOS dich noch nicht gefragt, zeigt es "Allow Access to Reminders" (Zugriff auf Erinnerungen erlauben), und nur diese Schaltfläche fragt; hast du abgelehnt, zeigt es "Open System Settings" (Systemeinstellungen öffnen).
- Claude-Aufgaben: Das Fenster führt `claude agents` nur aus, während es aufgeklappt ist: einmal beim Aufklappen, beim Aktualisieren und wenn `@claude` eine Aufgabe übergibt; und alle 15 Sekunden, solange eine Aufgabe noch nicht fertig ist, nicht mehr, sobald alle fertig sind. Die letzten Antworten werden vom Ende der Transkripte von Claude Code auf diesem Mac gelesen (`~/.claude/projects`), und nur, wenn sich ein Transkript geändert hat.
- Solange es geschlossen ist, läuft nichts davon; es führt nur eine Aufzeichnung der Notizen, die `@note` speichert.

## Eingabe und Übersetzung

In den Einstellungen:

- **Eingabesprachen**: eine bis fünf aus Englisch, Chinesisch (Pinyin), Französisch, Koreanisch und Hindi, hinzugefügt mit + (immer vorhanden; bei fünf ausgegraut). Eine Neuinstallation beginnt nur mit Englisch. Neue Textfelder beginnen in der ersten; tippe kurz auf die Umschalttaste für die nächste, in ihrer Reihenfolge; bei nur einer wechselt die Umschalttaste nicht.
  - **Französisch** tippt mit seinem eigenen Tastaturlayout: AZERTY, sofern du auf seiner Karte kein anderes wählst. Seine Tottasten (^, ¨, `, ´, ~) setzen ebenfalls darauf auf.
  - **Koreanisch** tippt Hangul im 2-Set-Layout (Dubeolsik), wobei jede Silbe beim Tippen zusammengesetzt wird (g k s → 한); die Umschalttaste ergibt ㄲ ㄸ ㅃ ㅆ ㅉ und ㅒ ㅖ.
  - **Hindi**: Tippe die Wörter so, wie sie klingen, in lateinischen Buchstaben und erhalte Devanagari (namaste → नमस्ते). Häufige Wörter werden so geschrieben, wie Hindi sie schreibt; ansonsten fügt die Leertaste die erste Schreibweise ein, eine Ziffer eine andere, ⏎ die Buchstaben wie getippt, und "." den Danda (।).
  - Der Name eines Befehls, der Text von `@open` und Code (`@py`, `@js`) werden unabhängig von der Sprache in lateinischen Buchstaben getippt; die Sprache kehrt nach dem Befehl zurück.
  - `@improve` belässt einen koreanischen, Hindi- oder französischen Satz in seiner eigenen Sprache, und `@translate` übersetzt ihn in deine Sprachen (Französisch wird von Englisch unterschieden, wenn es eine deiner Eingabesprachen ist).
- **Sprachpakete**: Die App enthält Englisch (und Französisch, das nur das Layout von macOS braucht). Chinesisch, Koreanisch und Hindi sind Pakete, die du beim Hinzufügen herunterlädst: Das Hinzufügen von Chinesisch (Pinyin) lädt seine Wörterbücher (etwa 34 MB, 125 MB entpackt) mit einem Fortschrittsbalken herunter, und Pinyin funktioniert, sobald das fertig ist, ohne Neustart; das Paket für Koreanisch (seine Tastentabelle und wie Jamo zu Silben werden) und das für Hindi (seine Buchstaben und häufigen Wörter) sind wenige Kilobyte groß. Ein Paket enthält nur Daten (Wörterbücher, Tabellen und Schemas, nie Code), ist in einem signierten Index aufgeführt und wird vor der Verwendung gegen seinen SHA-256 geprüft, wie Plugins. Die Karte jeder Sprache zeigt ihr Paket (Version, Größe, Herkunft) mit Delete… (löschen), und beim Entfernen der Sprache wird angeboten, ihr Paket zu löschen. Ein Update von 0.6.1 oder früher behält Chinesisch ohne Download: Das Installationsprogramm behält die Wörterbücher, die mit der alten Version kamen.
- **Unscharfes Pinyin** (bei chinesischer Eingabe): Laute, die du nicht unterscheidest, in beiden Varianten getippt, z. B. z ↔ zh, n ↔ l, in ↔ ing. Wähle auf der Seite Input in der Leiste der Eingabesprachen Chinese (pinyin), schalte "Fuzzy pinyin" ein und wähle die Paare; die Wörterbücher werden in ein, zwei Sekunden neu bereitgestellt. Dabei wird `rime_ice.custom.yaml` in den Benutzerordner von Rime geschrieben, und nie über eine eigene Datei von dir dort.
- **Übersetzen (@translate)**: Füge die Zielsprachen hinzu (Spanisch, Französisch, Deutsch, Japanisch, Koreanisch, Chinesisch, Hindi, Bengalisch, Tamil und die anderen großen indischen Sprachen …) und ziehe sie in die gewünschte Reihenfolge. In lateinischen Buchstaben getipptes Hindi ("aap kaise ho") kommt in Devanagari zurück. `@translate` schreibt eine Zeile in jeder, in dieser Reihenfolge (drei Fassungen, wenn es nur eine ist); die Sprache des Satzes selbst wird übersprungen. Eine Neuinstallation übersetzt in die erste Sprache unter den bevorzugten Sprachen deines Macs, die nicht Englisch ist; ist nur Englisch vorhanden, öffnet `@translate` diese Seite, um eine hinzuzufügen.
- **Tastaturlayouts**: Französisch tippt mit dem auf seiner Karte gewählten Layout (`keyboardLayouts` in der Konfiguration). Für die anderen Sprachen behält macOS unter der Eingabemethode dein letztes lateinisches Layout bei (AZERTY, QWERTZ, Spanisch, US International …), sodass du wie gewohnt tippst, `@` inbegriffen, wo immer dein Layout es hat, und Tottasten auch im Text eines Befehls funktionieren (⌥E, dann E → é, ^ dann e → ê). Layouts ohne lateinische Buchstaben (Russisch, Hindi InScript) lassen sich unter einer Eingabemethode nicht verwenden: Wechsle mit ⌃Leertaste zu ihnen, oder füge Text in einen Befehl ein (⌃V) oder diktiere ihn.
- `@improve` überarbeitet und formuliert um, ohne zu übersetzen; `@translate @improve` zusammen übersetzt und formuliert in einer einzigen Anfrage um. Schalte "@improve also translates" in den Einstellungen ein, damit `@improve` das immer tut.

## Umformulierungsstile

Nach den Zeilen 1–3 kommen die Umformulierungen, **in der Sprache, in der du getippt hast**: englische Umformulierungen für Englisch, chinesische für Chinesisch. Wähle in den Einstellungen beliebige davon aus:

- Polish (überarbeiten): gleicher Ton, natürlicher
- Concise (knapp)
- Formal (förmlich): für Vorgesetzte und Kunden
- Casual (locker)
- Tactful (taktvoll)
- Jargon: Amazon-Sprech auf Englisch (bandwidth, circle back …), Big-Tech-Jargon auf Chinesisch. Schlechte Nachrichten werden heruntergespielt, z. B. "this is a blocker bug" → "Oh! Looks like your team has the bandwidth to fix this minor issue!"

Umformulierungen, die nur die Zeichensetzung ändern oder eine andere Zeile wiederholen, werden nicht angezeigt.

### Jargon-Liste (eigene Begriffe)

Jargon hat keine eingebaute Begriffsliste. Du kannst deine eigene anlegen (zum Beispiel die Ausdrücke, die dein Team verwendet), und das Modell bevorzugt deren Begriffe. In den Kandidaten erklärt die Jargon-Zeile, was die verwendeten Begriffe bedeuten.

Die Liste ist eine Textdatei mit einem Begriff pro Zeile, optional gefolgt von seiner Bedeutung, getrennt durch "=", einen Doppelpunkt oder einen Tabulator (du kannst zwei Spalten aus einer Tabellenkalkulation kopieren und einfügen). Zeilen, die mit `#` beginnen, sind Kommentare:

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

Klicke in den Einstellungen unter "Rewrite Styles → Jargon list" auf "New" (neu), um eine leere Liste unter `~/.config/allinoneime/jargon.txt` anzulegen und zu öffnen; hast du bereits eine Listendatei, klicke auf "Choose File…" (Datei auswählen), um sie an ihrem Ort zu verwenden (`jargonFile` in der Konfiguration). Änderungen gelten sofort. Nur die ersten 150 Begriffe werden gelesen. Ist "Jargon" angehakt, wird die Liste mit jeder Anfrage an Bedrock gesendet.

<img src="../en/panel-dark.png" width="420" alt="Das Kandidatenfenster im dunklen Modus">

## Spracheingabe

<img src="../en/voice.png" width="340" alt="Rechte ⌥-Taste halten, um zu sprechen">

Halte die rechte ⌥-Taste gedrückt und sprich; wenn du loslässt, wird der Text eingefügt. Er wird in der Sprache erkannt, in der du tippst (Englisch, Chinesisch, Französisch, Koreanisch oder Hindi). Tippst du zuerst einen Befehl (z. B. `@improve `, `@question `) und sprichst dann, kommt der Text hinter den Befehl, und ⏎ führt ihn aus; du kannst auch ⏎ drücken, ohne die rechte ⌥-Taste loszulassen, um ihn auszuführen, sobald du fertig bist. Die Sprache wird auf dem Mac von der eingebauten Spracherkennung von macOS (SpeechAnalyzer) erkannt, und es wird kein Audio hochgeladen; dafür ist macOS 26 oder neuer nötig.

Beim ersten Mal:

- macOS fragt, ob AllInOneIME das Mikrofon verwenden darf. Du kannst auch vorab in den Einstellungen auf "Allow Microphone" (Mikrofon erlauben) klicken.
- Hat dieser Mac das Sprachmodell für diese Sprache noch nicht, wird es einmalig automatisch heruntergeladen. Du kannst es auch in den Einstellungen herunterladen.

Die Aufnahme beginnt erst, nachdem du die Taste etwa 0,2 s gehalten hast, sodass ein kurzes Antippen der rechten ⌥-Taste das Mikrofon nicht einschaltet (ist die Aktionstaste auf "Tap ⌥" gestellt, führt ein Antippen die Aktion aus). Drückst du beim Halten eine andere Taste (einen ⌥-Kurzbefehl, ⌥←), zählt das als Kurzbefehl, und es wird ebenfalls nichts aufgenommen. Das Drücken einer beliebigen anderen Taste während der Aufnahme bricht sie ab.

## Installation

Zum Ausführen ist macOS 14 oder neuer nötig, für die Spracheingabe macOS 26 oder neuer. Das Installationsprogramm ist universell: Es funktioniert auf Macs mit Apple Silicon und Intel. Bisher wurde es nur unter macOS 27 auf Apple Silicon getestet (der Intel-Build nur über seinen Selbsttest unter Rosetta).

1. Lade `AllInOneIME-<version>.dmg` von den [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) herunter (nur von dort) und öffne es.
2. Doppelklicke darin auf "Install AllInOneIME" und klicke auf Install. Die Eingabemethode kommt nach `~/Library/Input Methods` und "AllInOneIME Settings" nach `~/Applications`. Nur für diesen Benutzer; kein Administratorpasswort nötig.
3. Das Installationsprogramm ist noch nicht von Apple notarisiert, daher kann macOS nicht überprüfen, wer es erstellt hat, und meldet beim ersten Mal, dass es "Install AllInOneIME" nicht überprüfen kann: Klicke auf Fertig (Abbrechen unter macOS 14), öffne Systemeinstellungen → Datenschutz & Sicherheit, klicke unten auf Dennoch öffnen und bestätige. Das Installationsprogramm jeder neuen Version braucht das einmal.

Danach ist AllInOneIME aktiviert und in deinen Eingabequellen; wechsle mit Ctrl+Leertaste dorthin (die 🌐-Taste wechselt nur, wenn "Taste 🌐 drücken für" in Systemeinstellungen → Tastatur auf "Eingabequelle ändern" steht). Fordert dich das Installationsprogramm auf, sie von Hand hinzuzufügen, erlaubt dieser Mac Programmen nicht, sie zu aktivieren; füge sie also einmal selbst hinzu: Systemeinstellungen → Tastatur → Texteingabe → Eingabequellen → Bearbeiten … → + (unten links) → Englisch → AllInOneIME (sie tippt auch Pinyin, sobald du Chinesisch unter Input in ihren Einstellungen hinzufügst).

Wenn Ctrl+Leertaste dich nicht zu AllInOneIME bringt oder nach einer Weile zurück zu U.S. wechselt, führe das Installationsprogramm erneut aus: Es fügt AllInOneIME wieder zu deinen Eingabequellen hinzu.

Zum Aktualisieren installiere einfach erneut aus dem Disk-Image der neuen Version, ohne vorher zu deinstallieren; Einstellungen, die Jargon-Liste und gelernte Wörter bleiben erhalten. Lies vor dem Upgrade das [Änderungsprotokoll](../../CHANGELOG.md): Es enthält die Änderungen jeder Version und Hinweise zum Upgrade.

Hattest du AIPinyin installiert (den früheren Namen von AllInOneIME), installiere einfach: Die alte AIPinyin.app und ihr Einstellungs-Starter werden entfernt, und der Eintrag in deinen Eingabequellen erhält den neuen Namen, ohne dass du ihn neu hinzufügen musst. Einstellungen, die Jargon-Liste und gelernte Wörter werden beim ersten Start in die neuen Ordner (`~/.config/allinoneime` und andere) verschoben, und jeder alte Ordner bleibt als Verweis auf den neuen zurück.

Zum Deinstallieren öffne "Install AllInOneIME" und klicke auf Uninstall…. Einstellungen und gelernte Wörter bleiben erhalten.

### Aus dem Quellcode bauen

Zum Bauen ist Xcode 26 oder neuer nötig, da die Spracheingabe das SDK von macOS 26 verwendet.

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` lädt librime und die Wörterbücher von rime-ice herunter und prüft sie, baut und installiert an dieselben Orte und fügt es auf dieselbe Weise zu deinen Eingabequellen hinzu. Die so installierte App hat keine chinesischen Wörterbücher (sie bilden das chinesische Sprachpaket): Eine Installation, die sie hatte, behält sie als Paket; andernfalls installiert `make install-pack` das Paket aus den Wörterbüchern des Checkouts, ohne Download. `make status` zeigt die installierte Version (`version:`) und ob sie in deinen Eingabequellen ist (`listed:`). Zum Deinstallieren: `make uninstall`.

## KI einrichten

Übersetzungen und Umformulierungen nutzen deinen eigenen KI-Anbieter, und die Kosten gehen auf dein Konto: standardmäßig Amazon Bedrock in deinem AWS-Konto, oder die Claude API, Gemini oder ein OpenAI-kompatibler Dienst (siehe "Andere KI-Anbieter" unten).

### Amazon Bedrock

1. Aktiviere Bedrock in der AWS-Konsole und stelle sicher, dass du das gewählte Modell nutzen kannst. Standard ist Claude Haiku 4.5; wenn du zum ersten Mal ein Anthropic-Modell nutzt, füllst du einmalig ein Formular zum Anwendungsfall aus.
2. Erstelle einen Zugriffsschlüssel mit der Berechtigung `bedrock:InvokeModelWithResponseStream` und lege ihn in einem Profil in `~/.aws/credentials` ab. Derzeit werden nur solche statischen Schlüssel unterstützt, nicht SSO oder assume-role.
3. Öffne "AllInOneIME Settings": Du findest es über Spotlight oder unter Programme, oder öffne es über das Symbol der Eingabemethode in der Menüleiste → Settings…. Wähle Profil, Region und Modell und klicke auf "Test Connection" (Verbindung testen). "Language" (Sprache) oben im Einstellungsfenster kann English oder Chinese sein; standardmäßig ("System") folgt es dem System (Chinesisch, wenn Chinesisch in den bevorzugten Sprachen des Systems vor Englisch steht, sonst Englisch). Das Einstellungsfenster, die Hinweise im Kandidatenfenster und das Eingabemenü folgen alle dieser Einstellung.

<img src="../en/settings.png" width="420" alt="Das Einstellungsfenster">

### Andere KI-Anbieter: Claude API, Gemini, OpenAI-kompatible Dienste

Du brauchst kein AWS: Wähle unter "AI Provider" (KI-Anbieter) in den Einstellungen einen aus, füge einen API-Schlüssel ein, klicke auf "Save" (speichern) und dann auf "Test Connection".

| Anbieter | Standardmodell | API-Schlüssel |
|---|---|---|
| Claude API | `claude-haiku-5-5` (am schnellsten und günstigsten; Sonnet 5.5 und Opus 5.5 sind sorgfältiger, aber langsamer und teurer) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| OpenAI-kompatibel | `gpt-6-luna` von OpenAI (oder `gpt-5.4-mini`); "Common Services…" (gängige Dienste) enthält DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter und Ollama auf diesem Mac: Die Auswahl eines Dienstes trägt seine Basis-URL ein, dann gib sein Modell ein | Der Schlüssel des Dienstes; setze die Base URL auf seine Adresse, z. B. `https://api.deepseek.com/v1`, oder `http://localhost:11434/v1` für Ollama auf diesem Mac |

- API-Schlüssel werden im Schlüsselbund des Systems gespeichert, nie in der Konfigurationsdatei. Ist dort keiner, werden `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (oder `GOOGLE_API_KEY`) und `OPENAI_API_KEY` aus deiner Shell verwendet.
- "Thinking" (Nachdenken) steht standardmäßig auf niedrig: Die Eingabemethode wartet bei jedem Satz, und weniger Nachdenken ist schneller. Wähle "Not set" (nicht festgelegt) für Modelle, die es nicht unterstützen.
- Ist Claude Opus 5.5 oder Sonnet 5.5 gewählt, enthalten die Anfragen den Ablehnungs-Fallback der Claude API (`fallbacks: "default"`): Lehnt ein Sicherheitsklassifikator ab, versucht der Server es mit einem anderen Modell erneut.
- In der Konfigurationsdatei: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), sowie `model`, `baseURL`, `effort` und `temperature` unter `anthropic`, `gemini` und `openai` (nicht gesetzte verwenden die Standardwerte).

Alle Einstellungen werden in `~/.config/allinoneime/config.json` gespeichert; nach einer Änderung verwendet die nächste Übersetzung die neuen Einstellungen, ohne Neustart. Die neueren Schlüssel:

| Schlüssel | Was er bewirkt | Standard |
|---|---|---|
| `inputLanguages` | Eingabesprachen, eine bis fünf, die erste ist der Standard: `"en"` Englisch, `"zh"` Chinesisch (Pinyin), `"fr"` Französisch, `"ko"` Koreanisch, `"hi"` Hindi, z. B. `["en", "zh"]`, `["fr", "en", "ko"]`. Chinesisch, Koreanisch und Hindi funktionieren, sobald ihr Paket installiert ist | `["en"]` (Neuinstallation) |
| `keyboardLayouts` | Das Tastaturlayout, mit dem eine Eingabesprache tippt, nach ihrem Code (bisher nur Französisch): `{"fr": "com.apple.keylayout.French-PC"}` | Französisch: `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | Wohin `@translate` übersetzt, in Reihenfolge: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | `@improve` übersetzt auch (wie `@translate @improve`) | `false` |
| `voiceInput` | Rechte ⌥-Taste halten, um zu sprechen | `true` |
| `actionKey` | Aktionstaste: `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Leertaste), `"space"` (Leertaste) | `"enter"` |
| `uiLanguage` | Oberflächensprache (Einstellungsfenster, Hinweise im Kandidatenfenster, Menü): `"zh"`, `"en"` | `null` (folgt dem System) |
| `rewriteStyles` | Umformulierungsstile: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, z. B. `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | Deine eigene Jargon-Listendatei | `null` (d. h. `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | Das Menüleistensymbol und sein aufklappbares Fenster | `true` |
| `fuzzyPinyin` | Paare für unscharfes Pinyin: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |

## Datenschutz

- Tippen (Englisch und Pinyin) und Berechnungen mit `@calculate` sind vollständig lokal. Nur wenn du bei `@improve`, `@translate` oder `@question` die Aktionstaste drückst, wird dieser Satz an den von dir gewählten KI-Anbieter gesendet (dein eigenes Bedrock oder den Dienst, dessen Schlüssel du hinzugefügt hast). Ist "Jargon" angehakt und eine Jargon-Liste festgelegt, wird die Liste mitgesendet.
- Mit AllInOneIME Cloud geht der Satz über den Server des Entwicklers an einen Modellanbieter (derzeit über OpenRouter): Der Server speichert nur Zählwerte, nie den Text. Bei der Anmeldung wird nur deine E-Mail-Adresse gespeichert.
- Sprache wird nur aufgenommen, während du die rechte ⌥-Taste hältst, und auf dem Mac erkannt; der erkannte Text wird nur in den oben genannten Befehlen gesendet, wenn du die Aktionstaste drückst.
- Die Eingabemethode liest den Text der Zwischenablage einmal und nur dann, wenn du in einem Befehl ⌃V oder ⌘V drückst; Inhalte, die Passwortmanager als verborgen markieren, werden nicht gelesen. Der Text wird zuerst im Befehl angezeigt und, wie gesagt, nur gesendet, wenn du die Aktionstaste drückst. Neuere macOS-Versionen fragen, ob AllInOneIME die Zwischenablage lesen darf: Erlaube es. Damit du nicht jedes Mal gefragt wirst, stelle die Einfüge-Berechtigung von AllInOneIME unter Systemeinstellungen → Datenschutz & Sicherheit auf immer erlauben.
- In Passwortfeldern wechselt macOS zu seiner eigenen Tastatur (U.S. oder ABC) und zurück, wenn du sie verlässt. Immer wenn die App, in der du tippst, die sichere Eingabe hält, setzt AllInOneIME keinen Text zusammen und kann nicht aufnehmen: Tasten gehen so hinein, wie sie getippt werden. Und solange das System in sicherer Eingabe ist (Passwortfelder, Sichere Tastatureingabe im Terminal usw.), wird nichts an die KI gesendet.
- `@note` und `@reminder` gehen nicht an die KI: AllInOneIME übergibt den Text nur an Notizen und Erinnerungen auf diesem Mac und wertet auch die Zeit der Erinnerung auf dem Mac aus (ob diese Apps sie mit deinen anderen Geräten synchronisieren, hängt von deren Konten ab, etwa iCloud). Daher funktionieren sie auch während einer sicheren Eingabe.
- `@open` sucht nur auf diesem Mac. Es merkt sich, was du damit geöffnet hast (die letzten 200), in den eigenen Einstellungen der Eingabemethode (nicht in config.json), um diese zuerst aufzulisten.
- Um deine Notizen aufzulisten, speichert das Menüleistenfenster die ID und die erste Zeile (bis zu 80 Zeichen) der letzten 30 mit `@note` gespeicherten Notizen in den eigenen Einstellungen der Eingabemethode, auch während das Fenster ausgeschaltet ist.
- `@py` und `@js` laufen nur, wenn du die Aktionstaste drückst, und nur mit Code, den du selbst getippt oder eingefügt hast: Antworten der KI und die Ausgabe anderer Befehle werden nie als Code ausgeführt. `@py` nutzt das `python3` deines Macs, das Dateien lesen und schreiben und ins Netz gehen kann, wie es das im Terminal tut; `@js` läuft in einem eigenen Prozess, der keine Dateien lesen, nicht aufs Netzwerk zugreifen und keine anderen Programme starten kann. Keiner von beiden läuft während einer sicheren Eingabe.
- Protokolle zeichnen nicht auf, was du tippst. Bei jeder Eingabemethode von Drittanbietern warnt macOS, dass der Entwickler auf alles zugreifen kann, was du mit dieser Eingabequelle tippst; das ist eine allgemeine Systemwarnung.

## Entwicklung

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

Aufbau des Codes:

- `Sources/AllInOneIMECore`: Bedrock-Client, SigV4, Prompts, die zweistufige Zustandsmaschine der Eingabe (einschließlich @-Befehlen und der Sprachgeste); keine Abhängigkeit von AppKit
- `Sources/AllInOneIMERime`: Wrapper für librime
- `Sources/AllInOneIME`: die InputMethodKit-Eingabemethode, Kandidatenfenster, Einstellungsfenster, Spracherkennung
- `Sources/AllInOneIMESettings`: der Starter "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: "Install AllInOneIME" auf dem Disk-Image: installiert, aktualisiert und deinstalliert

Sprachpakete haben eine eigene Bibliothek, getrennt von den Plugins: das Repository [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), ausgeliefert unter https://languages.allinoneime.com/, signiert mit einem eigenen Schlüssel. `make pack` baut das Archiv; es wird dort als Release-Asset veröffentlicht (Release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), und `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` schreibt dort `packs.json` und signiert es in `packs.json.sig` mit dem Schlüssel der Sprachpakete aus dem Schlüsselbund (`allinoneime-languages-signing`). Die App liest https://languages.allinoneime.com/packs.json, prüft die Signatur, dann Größe und SHA-256 des Archivs. Um ein Paket von einem lokalen Server auszuprobieren: `--test-key` signiert mit einem Testschlüssel, und `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Die Bundle-ID ist weiterhin `com.aipinyin.inputmethod.AIPinyin`: macOS merkt sich damit die hinzugefügte Eingabequelle und die Mikrofonberechtigung, eine Änderung würde also bedeuten, die Eingabemethode erneut hinzuzufügen und die Berechtigung erneut zu erteilen.

## Lizenz

Copyright © 2026 MicroZ LLC. Quellcode verfügbar unter der [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): Du darfst ihn nutzen, lesen, ändern und weitergeben, für alles außer ein Konkurrenzprodukt. Jede Version wird zwei Jahre nach ihrer Veröffentlichung zu Apache-2.0. Versionen bis einschließlich 0.6.1 wurden unter der GPL-3.0 veröffentlicht und bleiben unter ihr verfügbar.

Komponenten von Drittanbietern (librime und seine Plugins unter BSD-3-Clause; die Lua-Skripte von rime-ice und das chinesische Sprachpaket unter GPL-3.0) sind in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) aufgeführt.
