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
> Ab 0.6.3 ist AllInOneIME mit einer Developer ID signiert und von Apple notarisiert: Du musst es nicht mehr unter System Settings → Privacy & Security (Systemeinstellungen → Datenschutz & Sicherheit) erlauben. Nach dem Update von einer früheren Version fragt macOS einmal pro Schlüssel, den AllInOneIME im Schlüsselbund gespeichert hat, nach deinem Anmeldepasswort: Gib es ein und klicke auf "Always Allow" (Immer erlauben). Lade AllInOneIME nur von den [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) oder von [allinoneime.com](https://allinoneime.com) herunter.

Eine Eingabemethode für macOS mit KI-Befehlen in jedem Textfeld. Beginne einen Satz mit `@` und drücke ⏎, wenn du fertig bist: `@improve` überarbeitet, was du geschrieben hast, und bietet einige Umformulierungen an, `@translate` übersetzt es in die Sprachen deiner Wahl, `@question` stellt eine Frage, `@agent` übergibt es an einen Coding-Agenten (Claude Code, Gemini CLI, Kiro CLI …), und `@open` findet Dateien und Apps oder öffnet eine Webadresse. Du kannst auch die rechte ⌥-Taste gedrückt halten und sprechen. Ohne `@` gehen deine Tastenanschläge wie gewohnt an die App. Außerdem tippt sie Chinesisch (Pinyin, auf Basis von Rime und rime-ice), Französisch, Koreanisch (Hangul) und Hindi (Devanagari aus lateinischen Buchstaben) und führt deine eigenen Skripte als @-Befehle aus.

![@improve und ein holpriger Satz, dann ⏎: überarbeitete Fassungen sowie Umformulierungen](../en/improve.png)

Mehr Details (jeder Befehl und jede Einstellung, Hilfe bei Installationsproblemen, Datenschutz) findest du im [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Entwickelt von [Weijian Zhang](https://weijianz.com) bei MicroZ LLC.

## Verwendung

Ohne `@` hält sie sich zurück: Auf Englisch werden Buchstaben direkt getippt und ⏎ ist der Zeilenschalter; nichts geht ins Netz. Eine Neuinstallation schreibt Englisch; um auch Chinesisch (Pinyin), Französisch, Koreanisch oder Hindi zu tippen, füge die Sprache in den Einstellungen hinzu (siehe [Eingabe und Übersetzung](#eingabe-und-übersetzung)).

| Taste | Was sie bewirkt |
|---|---|
| Pinyin tippen, Leertaste / Ziffern | Im chinesischen Modus: Wörter auswählen, wie in jeder Pinyin-Eingabemethode |
| `@` (am Satzanfang) | Öffnet die Befehlsliste: die zuletzt am häufigsten genutzten zuerst, 5 auf einmal, blätterbar mit ↑↓, dem Mausrad oder dem Trackpad; oder tippe Buchstaben, um einen zu finden (zuerst ein vollständig getippter Name, dann Namen, die damit beginnen, dann Namen, die sie enthalten). ⏎, Tab, Leertaste oder eine Ziffer wählt aus |
| ⏎ | Führt den Befehl aus. Funktioniert auch, wenn das Pinyin noch nicht ausgewählt ist: Es wird zuerst ausgewählt, wie mit der Leertaste |
| Leertaste, ⏎ / Ziffern | Sobald die Ergebnisse angezeigt werden: das hervorgehobene / nummerierte einfügen; 0 ist das Original. ⏎ fügt auch dann ein, wenn eine Nachfrage halb getippt ist (sie wird verworfen) |
| ⇧⏎ | Mit einer nach KI-Ergebnissen getippten Nachfrage: sendet sie (die nächste Frage einer `@question`-Unterhaltung oder eine Verfeinerung). Während ein Befehl getippt wird oder bei KI-Ergebnissen ohne Getipptes: fügt das Getippte unverändert ein, einschließlich `@command`. Bei anderen Ergebnissen (`@open`, eine Erinnerung …) fügt es die hervorgehobene Zeile ein, wie ⏎. Bei Ergebnissen von `@config` und `@doctor` bewirkt ⇧⏎ ohne Getipptes nichts |
| ⌘C | Kopiert das hervorgehobene Ergebnis (bei `@open` den Pfad); das Kandidatenfenster bleibt offen |
| ⌃V | In einem Befehl (z. B. nach `@improve `): hängt den Text aus der Zwischenablage an das Getippte an, statt ihn in die App einzufügen. Mehrere Zeilen werden zu einer, bis zu 2000 Zeichen auf einmal (`@note` behält die Zeilenumbrüche und nimmt bis zu 20000). Funktioniert in jeder App; ohne Befehl geht die Taste wie gewohnt an die App |
| ⌘V | Wie ⌃V, aber manche Apps verarbeiten ⌘V selbst (Terminals wie Ghostty, iTerm2 und Terminal sowie Notizen) und fügen wie gewohnt in die App ein; nutze dort ⌃V |
| Esc, ⌫ | Zurück zum Satz, um ihn weiter zu bearbeiten; Satzzeichen oder Ziffern nach den Ergebnissen setzen ihn fort. Nach einer Verfeinerung: zurück zu den Ergebnissen davor |
| Buchstaben, sobald KI-Ergebnisse angezeigt werden | Eine Nachfrage: nach `@question` die nächste Frage (siehe [Unterhaltungen](#unterhaltungen-mit-question-neu)), nach `@improve` oder einem Prompt-Befehl eine Anweisung wie `shorter` (siehe [Ergebnisse verfeinern](#ergebnisse-verfeinern-neu)); ⇧⏎ sendet sie. Nach `@translate` setzen Buchstaben den Satz fort, und ⏎ übersetzt ihn erneut |
| ⌘⏎, ⌘1–⌘5 | In einer `@question`-Unterhaltung: zeigt, wo sie sich fortsetzen lässt (Claude Code oder der andere Agent, den du für `@agent` gewählt hast, Claude, ChatGPT, Gemini oder kopieren); ⌘1, ⌘2 … wählen eines aus |
| Klick auf eine Zeile | Im Kandidatenfenster: wählt sie aus, wie es ihre Ziffer täte (ein Wort, ein Befehl in der Liste, ein Ergebnis, eine `@open`-Datei, ein Empfänger, die Zeile einer Erweiterung); die Zeile unter dem Zeiger wird hervorgehoben. Das Textfeld behält den Fokus |
| Umschalttaste kurz drücken | Bei mehreren Eingabesprachen: die nächste, in ihrer Reihenfolge (Englisch → Chinesisch → Französisch → …, dann zurück zur ersten) |
| Rechte ⌥ gedrückt halten | Sprechen, loslassen zum Beenden. In der Sprache, in der du tippst (Englisch, Chinesisch, Französisch, Koreanisch oder Hindi). In einem Befehl wird der Text dahinter angefügt; sonst wird er direkt eingefügt |

## @-Befehle (Beta)

| Befehl | Was er bewirkt |
|---|---|
| `@improve` | Überarbeiten: 1–3 sind drei Fassungen in der Sprache des Satzes, ab 4 die Umformulierungsstile (in den Einstellungen hinzugefügt und sortiert), 0 ist das Original. Keine Übersetzung; mit aktiviertem "@improve also translates" (@improve übersetzt auch) funktioniert er wie `@translate @improve` |
| `@translate` | Übersetzt in die Sprachen, die du hinzugefügt hast (Einstellungen → Translate, zum Umsortieren ziehen), je eine Zeile, drei Fassungen, wenn es nur eine ist; die Sprache des Satzes selbst wird übersprungen. `@translate @improve` zusammen übersetzt und formuliert in einer einzigen Anfrage um |
| `@question` | Stellt eine Frage; die Antwort erscheint in den Kandidaten, ⏎ oder die Leertaste fügt sie ein, ⌘C kopiert sie. Tippe weiter, und ⇧⏎ stellt eine Nachfrage: Das Fenster wird zu einer Unterhaltung mit bis zu 5 Runden und bietet danach an, sie in Claude oder einer anderen KI fortzusetzen. Ohne etwas dahinter listet es deine letzten 5 Fragen auf, die neueste zuerst; Tippen grenzt sie ein (Wörter an beliebiger Stelle der Frage, ohne Rücksicht auf Groß- und Kleinschreibung, auch Chinesisch). Eine Ziffer, ↑↓ und dann ⏎ oder ein Klick zeigt sofort die gespeicherte Antwort einer Frage, offline, zum Einfügen oder Kopieren wie gewohnt; ⌘R stellt sie dort erneut für eine frische Antwort. Ohne Treffer oder wenn nichts ausgewählt ist, fragt ⏎, was du getippt hast |
| `@agent` | Übergibt die Aufgabe an einen Coding-Agenten auf deinem Mac, gewählt unter Settings → General → "@agent hands it to" (@agent übergibt an): Claude Code (Standard), Gemini CLI, Kiro CLI oder ein eigener Befehl (das Getippte wird als letztes Argument angehängt). Claude Code läuft standardmäßig im Hintergrund, mit einer Benachrichtigung, wenn es fertig ist (klicke darauf, um die Sitzung im Terminal zu öffnen und weiterzumachen), oder sieh in `@tasks` nach; schalte "@agent runs in the background and notifies me" (@agent läuft im Hintergrund und benachrichtigt mich) aus, um es im Terminal zu öffnen. Die anderen Agenten öffnen sich im Terminal, mit dem Getippten als erster Nachricht. Jeder verwendet seine eigene Anmeldung und seine eigenen Einstellungen. Beim ersten Öffnen des Terminals fragt macOS, ob AllInOneIME Terminal steuern darf: Klicke auf OK. (Vor 0.6.4 hieß es `@claude`.) |
| `@tasks` | Listet die Claude-Aufgaben im Hintergrund (in Arbeit / fertig / wartet auf dich) mit ihren letzten Antworten auf; ⏎ öffnet eine im Terminal, ⌘C kopiert die Antwort |
| `@settings` | Öffnet sofort das Einstellungsfenster (Auswählen genügt) |
| `@config` | Ändert Einstellungen so, wie du sie beschreibst: `@config output languages English and French`, `@config use Chinese in WeChat`, `@config candidates in a column`. ⏎ zeigt die Änderungen, alt → neu; ⏎ (oder 1) übernimmt sie, Esc bricht ab, weitertippen und ⇧⏎ verfeinert sie; ⌘Z oder `@config undo` macht sie rückgängig. Siehe [Einstellungen durch Beschreiben ändern](#einstellungen-durch-beschreiben-ändern-neu) |
| `@doctor` | Prüft deine Einrichtung auf diesem Mac und behebt, was sich gefahrlos beheben lässt: ⏎ listet die Ergebnisse auf, Probleme zuerst; eine Ziffer behebt das jeweilige, ⏎ die gefahrlosen, über die Vorschau von `@config`. `@doctor why doesn't translate work` lässt außerdem die KI die wahrscheinliche Ursache erklären. Siehe [Die Einrichtung prüfen](#die-einrichtung-prüfen-neu) |
| `@open` | Listet passende Dateien, Ordner und Apps schon beim Tippen auf (Spotlight). Mehrere durch Leerzeichen getrennte Suchbegriffe funktionieren: Jeder muss im Pfad vorkommen, mindestens einer im Namen (der Name eines Standardordners gilt für seinen Inhalt: `downloads pdf` findet die PDFs in Downloads). Apps und die Standardordner werden auch über ihre chinesischen Namen gefunden, und eine chinesische Oberfläche zeigt sie so an. Was du mit `@open` geöffnet hast, kommt zuerst, dann Apps und diese Ordner, dann kürzlich genutzte oder geänderte Dateien; finden die Namen zwei Dateien oder weniger und keine App und keinen dieser Ordner, werden die Dateien in deinem Benutzerordner auch nach Inhalt durchsucht, diese Zeilen sind mit "content" (Inhalt) markiert; gibt es sonst nichts, listet ⏎ sie zur Auswahl auf, statt die erste zu öffnen. Bei einer Webadresse (`github.com`, `localhost:3000`, `https://…`) ist die erste Zeile "open in the browser" (im Browser öffnen), und Inhalte werden nicht durchsucht; eine Datei mit genau diesem Namen (etwa `MANIFEST.in`) kommt zuerst. Text, der mit `~/` oder `/` beginnt, ist ein Pfad: Tab vervollständigt ihn und wechselt in Ordner; ⏎ öffnet, ⌘C kopiert den Pfad |
| `@note` | Speichert den Text in der App Notizen, in einem Ordner namens AllInOneIME (wird angelegt, falls er fehlt); nichts wird eingefügt. Eingefügter Text behält seine Zeilenumbrüche, bis zu 20000 Zeichen |
| `@reminder` | Fügt eine Erinnerung zur App Erinnerungen hinzu, in einer Liste namens AllInOneIME. Schreibe die Zeit in den Text; sie wird auf dem Mac ausgewertet, und eine Zeile zeigt, was erkannt wurde: ⏎ oder Leertaste fügt sie hinzu, Esc geht zurück zum Bearbeiten. Mit Uhrzeit gibt es dann einen Alarm; nur mit Datum gilt sie ganztägig |
| `@calculate` | Rechnet auf diesem Mac; das Ergebnis erscheint in den Kandidaten, ⏎ oder Leertaste fügt es ein: `@calculate 23*17` → `391`. Funktioniert auch mitten im Satz: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Führt eine Zeile Python aus (das `python3` des Macs) und fügt das Ergebnis ein: den Wert des letzten Ausdrucks im Code, z. B. `@py 2**100`, `@py import math; math.sqrt(2)`, oder andernfalls die Ausgabe. Wird ohne `python3` nicht angeboten (die Befehlszeilenwerkzeuge von Xcode bringen es mit) |
| `@js` | Führt eine Zeile JavaScript aus und fügt dasselbe ein: den Wert des letzten Ausdrucks oder die Ausgabe von `console.log`, z. B. `@js [1, 2, 3].map(x => x * 2)`. Er nutzt das in macOS eingebaute JavaScriptCore, es muss also nichts installiert werden; er kann keine Dateien lesen, nicht aufs Netzwerk zugreifen und keine anderen Programme starten |
| `@reportissue` | Meldet ein Problem: öffnet in deinem Browser die GitHub-Seite für ein neues Issue, mit dem, was du nach dem Befehl getippt hast, als Titel und "What happened / What you expected" (Was ist passiert / Was hast du erwartet) zum Ausfüllen. Es fügt die Versionen der App und von macOS hinzu, die Architektur deines Macs, die Oberflächen- und Eingabesprachen, die installierten Sprachpakete, die Art des KI-Anbieters (und das Modell, wenn es ein öffentliches ist; sonst "custom"), die Aktionstaste und wie viele eigene Befehle, Plugins und Erweiterungen du hast, nie deren Namen, deinen Text, Pfade oder Schlüssel. ⏎ (oder deine Aktionstaste) zeigt zuerst alles im Kandidatenfenster; ⏎ erneut oder ein Klick auf die Zeile öffnet die Seite, wo du es liest und auf Submit klickst (mit deinem GitHub-Konto); Esc geht zurück. Auch im Eingabemenü ("Report an Issue…") und unter Settings → About |
| `@imessage` | Sendet eine iMessage: Tippe einen Namen, eine Telefonnummer oder eine E-Mail-Adresse (einen chinesischen Namen auch per Pinyin, vollständig oder als Initialen) und wähle den Empfänger im Kandidatenfenster (wem du zuletzt geschrieben hast, steht oben; eine vollständige Nummer oder Adresse funktioniert auch), dann schreibe die Nachricht (Befehle darin wie `@stock AAPL` werden zuerst ausgeführt). ⏎ zeigt "Send to Alex (…): message" im Fenster, ein weiteres ⏎ sendet sie, Esc geht zurück zum Bearbeiten; ins Textfeld wird nichts getippt. Beim ersten Mal fragt macOS, ob AllInOneIME auf Kontakte zugreifen und Nachrichten steuern darf: Klicke bei beidem auf OK |

Beispiel: `@q` ⏎, `what is quantum computing` tippen, ⏎. `@note books to read: The Three-Body Problem` ⏎ speichert eine Notiz. `@reminder call Bob tomorrow at 3pm` ⏎, die erkannte Zeit prüfen, dann noch einmal ⏎, um sie hinzuzufügen. Sobald der Befehl gewählt ist, kannst du auch die rechte ⌥-Taste halten und sprechen. Im chinesischen Modus wechseln `@open` und `@calculate` vorübergehend zu lateinischen Buchstaben und kehren zum Chinesischen zurück, wenn du fertig bist.

Der Code für `@py` und `@js` wird in lateinischen Buchstaben getippt, und vollbreite Satzzeichen (aus dem chinesischen Modus) werden zu ASCII; schreibe ihn in eine Zeile, mit `;` zwischen den Anweisungen. Er läuft in einem eigenen Prozess, der nach 10 Sekunden oder jederzeit mit Esc beendet wird; bei einem Fehler wird dessen erste Zeile angezeigt, z. B. `ZeroDivisionError: division by zero`. Mehrzeilige Ausgabe wird so eingefügt, wie sie ausgegeben wurde; in einem Terminal als eine Zeile (ein Terminal führt jede Zeile aus, die es bekommt). Ein Terminal innerhalb eines Editors (VS Code, Cursor, JetBrains) lässt sich nicht vom Editor selbst unterscheiden, daher wird dort die mehrzeilige Ausgabe jedes Befehls unverändert eingefügt. Beide funktionieren auch im Satz eines anderen Befehls: `@reply the answer is @py 2**100`; setze Code mit Leerzeichen in Anführungszeichen: `@question explain @py "sum(x * x for x in range(10))"`. Umgekehrt nicht: Der Code von `@py` und `@js` läuft immer genau so, wie du ihn getippt hast, und `@commands` darin werden nicht zuerst ausgeführt.

![Ein getipptes @ öffnet die Befehlsliste; @question plus eine Frage, dann ⏎ für die Antwort](../en/commands.png)

![@open findet Apps schon beim Tippen; beginnt der Text mit /, ist er ein Pfad: Der Ordner wird aufgelistet, Tab vervollständigt](../en/open.png)

Folgt auf `@` kein Befehl, wie bei `@john`, wird das `@` wie gewohnt eingefügt, sodass @-Erwähnungen in Chat-Apps weiterhin funktionieren. Direkt nach einem Buchstaben, einer Ziffer, `.`, `_` oder `-` getippt, wie in `bob@example.com` oder `ssh user@host`, ist `@` einfach Text: Es öffnet sich keine Liste, in keiner App, Terminals eingeschlossen. Ist die Liste offen, schließen ← → oder eine Taste, die in keinem Befehlsnamen vorkommen kann (`.`, `:`, `/`), sie und lassen das Getippte (`@`, `@im`) unverändert; in einem Terminal schließen ← → dann nur die Liste. `@question`, `@improve` und `@translate` senden nur dann an dein eigenes Bedrock, wenn du die Aktionstaste drückst; `@open` sucht nur auf diesem Mac; `@note` und `@reminder` gehen nur an Notizen und Erinnerungen auf diesem Mac; `@agent` nutzt den auf deinem Mac installierten Agenten (standardmäßig den Befehl `claude` von Claude Code) und dessen eigenes Konto, und er fragt wie gewohnt zuerst nach, bevor er Dateien ändert oder Befehle ausführt. Ohne installierten Agenten wird `@agent` nicht angeboten. `@imessage` liest nur die Kontakte auf diesem Mac (Namen, Telefonnummern, E-Mail-Adressen), geht nie über die KI, und Nachrichten sendet die Nachricht; ohne die App Nachrichten wird er nicht angeboten.

`@calculate` arbeitet auf diesem Mac, offline: `+ - * /` (auch `× ÷`), `^` oder `**` für Potenzen, Klammern, Prozent (`50%` ist 0,5, `200*5%` ist 10; wie bei einem Taschenrechner bezieht sich ein addierter oder subtrahierter Prozentsatz auf das Vorhergehende: `100+10%` ist 110, `100-10%` ist 90), die Funktionen `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` ist zur Basis 10, Winkel sind im Bogenmaß, `round(x, 2)` behält zwei Nachkommastellen) und die Konstanten `pi` (`π`) und `e`. Vollbreite Ziffern und Zeichen funktionieren auch. Die Arithmetik ist dezimal exakt, also ergibt `0.1+0.2` genau `0.3`; Ergebnisse haben höchstens 15 signifikante Stellen, und ganze Zahlen mit bis zu 38 Stellen werden vollständig ausgeschrieben (`2^100` → `1267650600228229401496703205376`).

### Auf dem markierten Text (neu)

Markiere Text in einer beliebigen App (einen Satz in Notizen, einen Absatz in Mail), tippe `@improve`, `@translate`, `@question` oder einen anderen Befehl, der Text nimmt, und drücke ⏎: Der Befehl arbeitet mit der Markierung, und das Ergebnis, das du auswählst, ersetzt sie. Die Markierung bleibt, wie sie ist, markiert, während du tippst: Der Befehl wird im Kandidatenfenster geschrieben, dessen erste Zeile das ist, was du tippst, und die nächste "On the selection: “…” (N characters)" (auf der Markierung: N Zeichen). Esc, ⇧⏎ oder ein Klick woandershin lassen den Text, wie er war; ebenso eine Markierung, die du inzwischen änderst, was den Befehl abbricht. Text, der nach dem Befehl getippt wird, ist eine Anweisung für `@improve` und `@translate` (`@translate ja`, `@improve more formal`) und die Frage für `@question` (`@question what does this mean`), jeweils zur Markierung. `@open`, `@agent`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, Terminal-Befehle und Skript-Erweiterungen nutzen sie nicht: Sie nehmen, was du tippst, und die Markierung bleibt, wie sie ist. Bis zu 5000 Zeichen; nie gelesen während sicherer Eingabe oder in einem Terminal. Schalte es unter Settings → General → "Use the selected text" (den markierten Text verwenden) aus, wenn es sich in einer App falsch verhält.

### Ergebnisse verfeinern (neu)

Während die Ergebnisse von `@improve`, einem Prompt-Befehl (einem eigenen oder dem eines Plugins) oder der Umformulierung einer Markierung angezeigt werden, tippe, was sich ändern soll, etwa `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese` oder `用更口语的说法` (Pinyin funktioniert, und ein kurzer Druck auf die Umschalttaste wechselt die Sprache), und drücke ⇧⏎: Die Ergebnisse gehen mit deiner Anweisung erneut an die KI, und die neuen ersetzen sie im selben Fenster. ⏎ fügt das ausgewählte Ergebnis ein, auch wenn eine Anweisung halb getippt ist (sie wird verworfen). Verfeinere so oft du willst; die oberste Zeile des Fensters listet die Schritte auf ("Refined: shorter · more formal"), und du kannst jederzeit wie gewohnt eine Zeile auswählen. Ein Buchstabe beginnt die Anweisung (oben im Fenster als "refine › …" angezeigt); solange sie leer ist, wählen Ziffern, Leertaste und ⏎ wie bisher aus, und ⇧⏎ fügt das Getippte unverändert ein. Das Verfeinern beginnt, sobald die Ergebnisse vollständig sind: Tippen, während die ersten Ergebnisse noch eintreffen, setzt den Satz fort, wie bisher. Während eine Verfeinerung läuft, kannst du schon die nächste Anweisung tippen; die Verfeinerung läuft weiter, und ⇧⏎ startet die nächste, sobald ihre Ergebnisse da sind. Esc löscht die Anweisung, geht dann einen Schritt zurück zu den Ergebnissen vor der letzten Verfeinerung (während einer Verfeinerung: stoppt sie), dann zurück zum Satz; ⌫ in einer leeren Zeile geht auf dieselbe Weise zurück. Bei markiertem Text ersetzt das gewählte Ergebnis weiterhin genau die Markierung, die bis dahin unverändert bleibt. Eine Verfeinerung, die fehlschlägt (oder während sicherer Eingabe abgelehnt wird), lässt die Ergebnisse, wie sie waren, mit ihrer Anweisung bereit für einen neuen Versuch mit ⇧⏎. Dieselbe Verfeinerung derselben Ergebnisse wird aus dem Cache beantwortet. `@translate` hat keine Verfeinerung: Tippen nach seinen Ergebnissen setzt den Satz fort, und ⏎ übersetzt ihn erneut.

### Unterhaltungen mit @question (neu)

Sobald `@question` geantwortet hat, ist das, was du tippst, die nächste Frage: ⇧⏎ stellt sie, zusammen mit den bisherigen Fragen und Antworten, und das Fenster wächst zur Unterhaltung, die früheren Runden abgeblendet als Q- / A-Zeilen, die neueste Antwort darunter. Die oberste Zeile sagt, welche Runde als Nächstes kommt ("question 2/5 › …"). Jede Antwort lässt sich einfügen: mit ihrer Ziffer (1–5), mit ↑↓ und dann ⏎ oder per Klick; die neueste ist ausgewählt, und ⌘C kopiert die ausgewählte. ⏎ fügt sie auch dann ein, wenn eine Frage halb getippt ist (sie wird verworfen). Esc löscht das Getippte und geht dann eine Runde zurück; bei der ersten verlässt es die Unterhaltung wie bisher. Das Fenster wächst bis auf etwa die halbe Bildschirmhöhe und scrollt dann, das Neueste unten.

Nach 5 Runden (`questionRounds` in der Konfiguration, 2–10) wird die Zeile der nächsten Frage zu "5 rounds in: continue in Claude or another AI" (5 Runden: in Claude oder einer anderen KI fortsetzen), mit den Möglichkeiten nummeriert als ⌘1, ⌘2 …; ⌘⏎ zeigt sie in jeder Runde (solange noch eine Antwort eintrifft, bewirkt es nichts und erreicht nie die App). Was du dann tippst, ist die erste Nachricht dort; nur ⌘1, ⌘2 … senden sie (⇧⏎ fragt nichts mehr und öffnet nichts). Eine Frage zu markiertem Text nimmt diesen Text mit, als eigener Block zitiert. Die Möglichkeiten:

- **Der Agent, an den `@agent` übergibt**, mit seinem Namen (standardmäßig Claude Code, oder Gemini CLI, Kiro CLI oder dein eigener Befehl, wie unter Settings → General gewählt), wenn er installiert ist: eine interaktive Sitzung im Terminal, die mit der Unterhaltung und "Let's continue this discussion" beginnt.
- **Claude** oder **ChatGPT** im Web, mit bereits eingefüllter Unterhaltung (eine lange kommt in die Zwischenablage: einsetzen).
- **Gemini** im Web, die Unterhaltung in der Zwischenablage zum Einsetzen.
- **Copy the conversation** (Unterhaltung kopieren), in Markdown (**Q:** / **A:**).

Welche davon und in welcher Reihenfolge (die erste ist die Standardwahl): Settings → General → "Continue a conversation in" (Unterhaltung fortsetzen in; `questionContinueIn` in der Konfiguration). Mit Apple Intelligence auf diesem Mac passt eine lange Unterhaltung nicht in dessen kleinen Kontext: Die ältesten Antworten werden gekürzt, dann die ältesten Runden weggelassen, und das Fenster zeigt "earlier rounds shortened" (frühere Runden gekürzt). Eine Unterhaltung wird unter ihrer ersten Frage bei den letzten Fragen gespeichert, und wenn du sie auswählst, siehst du die Runden, um weiterzumachen.

### Letzte Fragen (neu)

`@question` ohne etwas dahinter listet deine letzten 5 Fragen auf, die neueste zuerst, mit dem Zeitpunkt, zu dem sie gestellt wurden ("3 hours ago"). Tippen grenzt sie ein: jedes Wort an beliebiger Stelle der Frage, ohne Rücksicht auf Groß- und Kleinschreibung (auch Chinesisch ohne Leerzeichen). Eine Ziffer, ↑↓ und dann ⏎ oder ein Klick zeigt sofort die gespeicherte Antwort einer Frage, ohne online zu gehen: Leertaste oder ⏎ fügt sie ein, ⌘C kopiert sie, ⌘R stellt sie erneut für eine frische Antwort (bei einer Unterhaltung: deren letzte Frage), Esc geht zurück zur Liste. Eine gespeicherte Unterhaltung zeigt alle ihre Runden: Tippe, um sie fortzusetzen. Ohne Treffer oder wenn nichts ausgewählt ist, fragt ⏎, was du getippt hast. Eine neue Antwort auf dieselbe Frage oder eine Unterhaltung, die weitergeht, ersetzt die gespeicherte.

- Sie werden nur auf diesem Mac gespeichert (siehe Datenschutz): nicht während sicherer Eingabe, und nie für Fragen zu markiertem Text.
- Settings → General → "Remember recent questions" (letzte Fragen merken) schaltet es aus (`rememberQuestions` in der Konfiguration); dort ausgeschaltet, löscht es sie auch. Mit `@config` ausgeschaltet, bleiben sie erhalten, damit Rückgängigmachen genau den vorherigen Zustand wiederherstellt (die Vorschau sagt das); "Clear (N)" (Löschen) löscht sie.

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

#### Erweiterungsquellen (neu)

Ein Bundle kann aus einem Git-Repository kommen, deinem eigenen oder dem deines Teams, und von dort aktuell bleiben. Settings → Custom Commands → Extension Sources → **Add from Link…** (aus Link hinzufügen): Füge die Adresse des Repositorys ein (`git@github.com:you/my-extensions.git`, `ssh://…`, `https://…`; optional einen Branch, den Ordner des Bundles im Repository und einen Tag oder Commit, auf den es festgelegt wird). AllInOneIME klont es mit **deiner eigenen Git- und SSH-Einrichtung** (Schlüssel, Agent, ~/.ssh/config, Credential Helper), sodass ein privates Repository so funktioniert wie im Terminal; die App fragt nie nach einem Passwort und speichert keines. Der Klon kommt nach `~/Library/Application Support/AllInOneIME/Sources/`: zuerst in einen versteckten Bereitstellungsordner, nie direkt in einen Erweiterungsordner. (Schreibe keinen Namen, kein Passwort und kein Token in eine https-Adresse: Der Credential Helper von git verwahrt sie.)

- **Erst prüfen.** Bevor irgendetwas geladen wird, siehst du das Bundle, jeden Befehl (Name, Titel, Beschreibung, Ausgabe), die Programme, die sie ausführen, seine Einstellungen und den Commit, unter der Warnung "This source isn't signed: it will run programs from <address>" (diese Quelle ist nicht signiert: Sie wird Programme von dieser Adresse ausführen). Nur **Enable** (aktivieren) fügt es hinzu; Cancel (abbrechen) löscht den Klon. Eine Quelle prüfst du einmal.
- **Updates übernimmst du selbst.** Einmal am Tag (und kurz nach dem Start der Eingabemethode) wird eine Quelle abgerufen (fetch), um zu sehen, was neu ist: Die Einstellungen zeigen "N updates" (N Updates) mit den Commits (Betreff, Autor, Datum) und ein Badge auf der Seite. Nichts ändert sich, bis du auf **Update** (aktualisieren) klickst, das nur vorspult (fast-forward) und keine Hooks ausführt. Nach einem Force-Push muss die Quelle erneut geprüft werden: **Re-clone** (neu klonen) zeigt sie, und erst Enable setzt die umgeschriebene Historie ein (bis dahin funktioniert die geprüfte Version weiter). Eine auf einen Tag oder Commit festgelegte Quelle wird nicht geprüft. Die tägliche Prüfung lässt sich pro Quelle ausschalten (`autoCheck`).
- **Fehler** sind die eigenen Worte von git, mit "This uses your own git and SSH setup; check that `git ls-remote <url>` works in Terminal" (hier wird deine eigene Git- und SSH-Einrichtung verwendet; prüfe, ob dieser Befehl im Terminal funktioniert), und darunter deine eigene Erinnerung, falls du eine festgelegt hast (`authHint` in der Konfiguration).
- **Remove** (entfernen) legt den Klon in den Papierkorb; die Einstellungen des Bundles bleiben für das nächste Mal erhalten.
- Aus einem Terminal: `AllInOneIME --add-source <url> [--path …] [--branch …] [--pin …]` (gibt die Prüfung aus und aktiviert die Quelle; nach einem Force-Push erneut), `--update-sources` (spult jede geprüfte, nicht festgelegte Quelle vor), `--list-extensions` (auf `~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME`).
- Nur geprüfter Code wird geladen: Ein Quellordner in der Ladeliste, der nicht auf diesem Mac geprüft wurde (eine kopierte Konfiguration), bleibt außen vor. git wartet nie auf eine Antwort: kein Terminal und keine Abfragen, daher schlagen ein unbekannter Host-Schlüssel oder eine Passwortabfrage sofort fehl.

Die Konfiguration speichert sie als `extensionSources`; der Aufbau des Repositorys steht in [docs/extensions.md](../extensions.md#10-extension-sources).

### Plugins

Plugins sind fertige `@`-Befehle für Dinge, die nicht jeder braucht, wie `@stock AAPL 600519 700` für Aktienkurse. Einmal installiert, funktionieren sie wie jeder andere Befehl; "Plugins" in den Einstellungen zeigt, was installiert ist und wohin jedes Plugin deinen Text sendet, und entfernt sie auch. Plugins sind JavaScript, das in einem eigenen Prozess läuft: Sie erreichen nur die Websites, die sie angeben (HTTPS), und können keine Dateien lesen und keine anderen Programme starten. "Browse Library…" (Bibliothek durchsuchen) unter Plugins in den Einstellungen installiert sie aus der [Plugin-Bibliothek](https://github.com/MicroZ-LLC/AllInOneIME-plugins): Sie zeigt vor der Installation, welche Websites ein Plugin kontaktiert; der Index der Bibliothek ist signiert, und jede Datei muss zu ihm passen. Bei einer neueren Version erscheint eine Schaltfläche "Update" (aktualisieren); nichts aktualisiert sich von selbst. Deine eigenen Plugins kommen nach `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): lokale Plugins, die von der Bibliothek nie überschrieben werden. "Link"-Plugins führen keinen Code aus: Sie setzen den Text in eine Webadresse ein und öffnen sie im Browser, wie `@x nice weather today`, das den Beitragseditor von X mit bereits eingesetztem Text öffnet; das Posten auf der Seite liegt bei dir. Die Bibliothek enthält vier davon (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` rechnet Währungen um: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, eine Zeile mit dem Datum des Kurses (Kurse von ExchangeRate-API). Ein eigenes schreiben: [docs/plugins.md](../plugins.md).

Befehle, die etwas abrufen (Plugins und Programme), funktionieren auch mitten im Satz: `@reply tell her @stock AAPL is up today`. Die inneren laufen zuerst, ihre Ausgabe tritt an ihre Stelle, und der äußere Befehl arbeitet mit dem Ergebnis. Das Argument ist das Wort nach dem Befehl plus die direkt folgenden Kürzel in Großbuchstaben oder Zahlen (`@stock AAPL TSLA`, `@stock 600519 700`); ein kleingeschriebenes Wort beendet es (`@stock SNDK is good to buy` fragt SNDK ab). Anführungszeichen grenzen es genau ab: `@stock "aapl tsla"`. `@calculate` funktioniert ebenfalls mitten im Satz; sein Argument ist der ganze Ausdruck danach, einschließlich Leerzeichen, bis zu anderem Text: `@reply the total is @calculate 23 * 17 dollars`. Innerhalb von `@agent` und Terminal-Befehlen werden sie nicht ausgeführt: Diese erhalten den Text so, wie er geschrieben ist (ein dort getipptes `@` öffnet die Befehlsliste nicht).

### Aktionstaste

Standardmäßig ⏎; ändere sie unter "Action key" (Aktionstaste) in den Einstellungen (`actionKey` in der Konfiguration): ⏎, Tap ⌥ (⌥ kurz antippen, auf beiden Seiten: drücken und sofort loslassen; das Halten der rechten ⌥-Taste bleibt fürs Sprechen), ⌥Leertaste oder Leertaste (drücke die Leertaste noch einmal, nachdem die Wörter ausgewählt sind; im englischen Modus zweimal). Unabhängig von der Aktionstaste laufen @-Befehle auch mit ⏎. Ist ⌥Leertaste bereits ein Kurzbefehl für Alfred, Raycast oder Ähnliches, bekommen diese ihn zuerst.

### Ergebnisse eintippen

Schalte "Type results out" (Ergebnisse eintippen) unter Settings → General ein (`typeOut` in der Konfiguration), und das Ergebnis eines Befehls wird Zeichen für Zeichen in die App getippt, wie von einem Menschen, statt auf einmal eingefügt zu werden; Pinyin-Auswahlen gehen weiterhin auf einmal hinein. Der Schieberegler stellt das Tempo ein, von 6 Sekunden pro Zeichen bis 40 pro Sekunde (`typeOutRate`), und "Speed up and slow down (like a person)" (schneller und langsamer werden, wie ein Mensch) tippt in Schüben mit wechselndem Tempo (`typeOutVaries`). Esc stoppt es, wo es gerade ist; jede andere Taste tippt den Rest auf einmal.

"Make occasional typos and fix them" (ab und zu vertippen und korrigieren, `typeOutMistakes`) lässt es noch menschlicher wirken: hin und wieder die Taste neben der richtigen, bis zu drei Buchstaben später bemerkt, gelöscht und neu getippt; ein Buchstabe oder ein Leerzeichen doppelt getippt und gelöscht; oder ein kurzes Wort getippt, gelöscht und neu getippt. Ein paar auf 100 Zeichen, nie zwei dicht beieinander und nie am Zeilenanfang. In Code, Web- und E-Mail-Adressen und Zahlen ist ein Tippfehler nur ein falscher Buchstabe oder eine falsche Ziffer, sofort korrigiert (nie eine falsche Klammer, ein Anführungszeichen oder ein Leerzeichen, bei denen Editoren Paare bilden oder einrücken). Die falschen Buchstaben sind Nachbarn auf deinem Tastaturlayout (QWERTY, AZERTY, QWERTZ…). Chinesisch, Japanisch und Koreanisch zögern nur (zwei Zeichen getippt, gelöscht und neu getippt), nie mit einem falschen Zeichen.

In einem Feld, das Tippfehler zurücknimmt (Apples Textansichten wie TextEdit und Notizen, Browser, die meisten Editoren): Bis zum Ende getippt oder mit einer anderen Taste, die den Rest auf einmal tippt, ist der Text genau das Ergebnis; Esc (oder das Verlassen des Felds) mitten in einem Tippfehler nimmt den Tippfehler zuerst heraus, sodass das Feld einen exakten Anfang des Ergebnisses enthält. Bewegt sich der Cursor, während ein Tippfehler zu sehen ist (ein Klick), wird der Tippfehler dort herausgenommen, wo er war, und der Rest ohne Tippfehler getippt.

Tippfehler werden nie in Terminals gemacht, auch nicht in Apps, die der Eingabemethode nicht sagen, wo der Cursor ist. Jedes Mal ist der erste Tippfehler ein einfacher (ein falscher Buchstabe, in einem Zug korrigiert), bis das Feld gezeigt hat, dass es einen Tippfehler zurücknimmt; solange ein Tippfehler zu sehen ist, prüft die Eingabemethode vor jeder Taste, ob das Feld enthält, was sie getippt hat. Ein Feld, das ignoriert, wo Text ersetzt werden soll, kann keinen Tippfehler zurücknehmen: Dort bleibt dieser erste Tippfehler stehen, der Text ist also um ein Zeichen falsch (auch nach Esc oder einer anderen Taste), und die App bekommt keine Tippfehler mehr. Settings → General listet diese Apps unter dem Tippfehler-Schalter auf; "Forget apps where typos couldn't be fixed" (Apps vergessen, in denen Tippfehler nicht korrigiert werden konnten) lässt sie es erneut versuchen.

### Einstellungen pro App (neu)

Settings → Apps gibt einer App eigene Einstellungen, jede optional; was eine App nicht festlegt, folgt den Einstellungen für alle Apps:

| Einstellung | Zum Beispiel | In der Konfiguration |
| --- | --- | --- |
| Die Eingabesprache, in der ihre Textfelder beginnen | Slack auf Englisch, WeChat in Pinyin | `inputLanguage` |
| Die Umformulierungsstile, die `@improve` dort anbietet | Mail förmlich und taktvoll, Slack locker | `rewriteStyles` |
| Ergebnisse eintippen oder nicht | an in einer Chat-App, aus in Mail | `typeOut` |
| Keine KI in dieser App | `@improve`, `@translate`, `@question`, `@agent` und deine Prompt-Befehle senden dort nichts und sagen das; Tippen und die anderen Befehle funktionieren | `noAI` |

"Add App…" (App hinzufügen) listet die Apps auf, in denen du zuletzt getippt hast, oder wählt eine in /Applications. Das Eingabemenü hat mit "This App: <Name>" schnelle Schalter für die App, in der du tippst (No AI, Type Results Out, die Startsprache). In der Konfiguration stehen sie unter `appProfiles`, nach Bundle-ID: `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. Bundle-IDs werden ohne Rücksicht auf Groß- und Kleinschreibung verglichen (`com.apple.Mail` ist die `com.apple.mail` von Mail). `@reportissue` zählt die Apps, die etwas festlegen, ohne sie je zu nennen.

- Die Startsprache funktioniert wie die Standard-Eingabesprache: Ein Textfeld übernimmt sie, wenn es aktiv wird, und ein Wechsel mit der Umschalttaste bleibt dann für die Felder dieser App bestehen, bis sich die Einstellung ändert.
- Mit No AI bleiben die KI-Befehle in der @-Liste; wer einen ausführt, sieht den Hinweis, und das Geschriebene bleibt erhalten. Deine eigenen Terminal-Befehle (`"type": "terminal"`) führen Programme aus, nicht die KI, und funktionieren dort daher weiterhin.

### Einstellungen durch Beschreiben ändern (neu)

`@config` macht aus einem Satz Einstellungen: `@config output languages English and French`, `@config 微信里用中文，邮件里语气正式一点`, `@config candidates in a column`, `@config turn off the typos`, `@config use Claude`. ⏎ zeigt die Änderungen im Kandidatenfenster, jede in einer Zeile, alt → neu, mit den Bezeichnungen der Einstellungen ("Translation languages: English, Japanese → English, French", "Apps · WeChat · Starts in: Same as everywhere → Chinese"); noch ist nichts geändert oder getippt. ⏎ (oder 1) übernimmt alle, Esc bricht ab, und weitertippen und dann ⇧⏎ verfeinert den Vorschlag ("auch Deutsch"; ⇧⏎ ohne Getipptes bewirkt nichts, und ⏎ übernimmt den angezeigten Vorschlag). Nach dem Übernehmen stellt ⌘Z, solange die Bestätigung angezeigt wird, oder `@config undo` innerhalb der nächsten 10 Minuten genau die Werte wieder her, die diese Einstellungen vorher hatten.

- **Was es ändern kann:** die Übersetzungs- und Eingabesprachen (und die Standardsprache), die Umformulierungsstile, die Kandidatenanordnung, das Abtippen der Ergebnisse (an/aus, Tempo, Beschleunigen und Verlangsamen, Tippfehler), die Verwendung der Markierung, das Merken von Fragen, das Verbergen sensibler Informationen (an/aus, was verborgen wird, hinzuzufügende Wörter), die Suche nach Updates, Einstellungen pro App (eine App so benannt, wie du sie nennst, unter deinen Apps nach Name oder Bundle-ID gefunden) und den KI-Anbieter: welcher, das Bedrock-Profil (aus `~/.aws`) und die Region, ein Modell, das die App für ihn kennt, und eine OpenAI-kompatible Basis-URL (nur `https://`).
- **Was es nie anfasst:** API-Schlüssel und alles im Schlüsselbund, eigene Befehle, Erweiterungsordner und -quellen, Plugins, die Jargon-Liste, alles, was Programme ausführt, und jede andere Einstellung. Solche Zeilen werden mit Begründung abgelehnt, und der Rest lässt sich trotzdem übernehmen.
- **Geprüft wie in den Einstellungen:** eine Sprache, die keine ist, mehr als 5 Übersetzungssprachen, ein Wert außerhalb des Bereichs, eine App, die es nicht zuordnen kann, oder eine Sprache, deren Paket nicht installiert ist ("needs the Korean language pack: download it in Settings → Input", also: Das koreanische Sprachpaket wird benötigt, lade es unter Settings → Input herunter), wird Zeile für Zeile abgelehnt; eine ungültige Konfiguration wird nie geschrieben.
- **Schlüssel:** Es wechselt nie zu einem Anbieter ohne Schlüssel (weder im Schlüsselbund noch in deiner Shell): Die Zeile lautet "Gemini API needs an API key: ⏎ opens Settings to add it (never sent to the AI); you can switch to it there" (die Gemini-API braucht einen API-Schlüssel: ⏎ öffnet die Einstellungen, um ihn hinzuzufügen, er wird nie an die KI gesendet; dort kannst du zu ihr wechseln), und Übernehmen öffnet Settings → AI Provider mit einem kleinen Fenster für diesen Schlüssel (Save zum Sichern oder Save and Use zum Sichern und Wechseln), während die anderen Zeilen trotzdem übernommen werden. Mit einem Schlüssel wechselt der Anbieter, Test Connection läuft, und das Ergebnis erscheint unter der Bestätigung. Ein in den Satz getippter Schlüssel wird entfernt, bevor irgendetwas gesendet wird.
- **Zuerst auf diesem Mac:** Es verwendet Apple Intelligence, wann immer dieser Mac sie hat (macOS 26), unabhängig vom gewählten Anbieter und sogar bevor einer eingerichtet ist, beschränkt auf die erlaubten Einstellungen und Werte, mit Abfragen deiner Apps, AWS-Profile und Sprachpakete. Ohne sie antwortet dein Anbieter. Die Anfrage enthält nur die erlaubten Einstellungen und ihre aktuellen Werte (nie einen Schlüssel und nicht die Wörter, die du verbirgst), und das Verbergen sensibler Informationen gilt wie für jede Anfrage.

### Die Einrichtung prüfen (neu)

`@doctor` ⏎ prüft die Einrichtung auf diesem Mac in ein, zwei Sekunden (währenddessen wird der Verbindungstest angezeigt) und listet die Ergebnisse im Kandidatenfenster auf, jedes in einer Zeile, ✗ Probleme zuerst, dann ⚠ Warnungen, dann ✓ was in Ordnung ist, jeweils mit einer kurzen Abhilfe: die Eingabemethode (installiert, aktiviert, in deinen Eingabequellen), der KI-Anbieter (sein Schlüssel gespeichert oder die Zugangsdaten des Bedrock-Profils gefunden, nie gelesen oder angezeigt; Test Connection; Apple Intelligence), die Berechtigungen (Bedienungshilfen, das Mikrofon, falls du diktierst, die Steuerung von Notizen, Erinnerungen, Terminal und Nachrichten, bei macOS ohne Abfrage erfragt), die sichere Eingabe, die Sprachpakete deiner Eingabesprachen, `config.json` (lesbar, unbekannte Schlüssel, Werte außerhalb des Bereichs, eine doppelte Sprache, mehr als 5 Übersetzungssprachen), Erweiterungen und Plugins, die nicht geladen wurden, Updates und aktuelle Fehler in den eigenen Protokollen der App.

Die Zeilen mit einer Abhilfe sind nummeriert: Eine Ziffer (oder ein Klick) zeigt in der Vorschau von `@config`, was sie bewirkt, und ⏎ übernimmt sie; ⏎ auf der Liste behebt alle gefahrlosen auf einmal (Einstellungen repariert, doppelte Sprachen entfernt, die Eingabemethode wieder aktiviert). Das Öffnen eines Bereichs der Systemeinstellungen, das Herunterladen eines Sprachpakets, Check for Updates (öffnet die Einstellungen) und das Schlüsselfeld der Einstellungen werden einzeln ausgewählt. Änderungen an Einstellungen lassen sich wie die von `@config` rückgängig machen (⌘Z, `@config undo`). Keine Abhilfe löscht deine Daten oder rührt einen Schlüssel an.

`@doctor <question>` (`@doctor why doesn't translate work`) führt die Prüfungen aus, dann erklärt die KI anhand ihrer Ergebnisse die wahrscheinliche Ursache und markiert die Abhilfen, die sie vorschlägt (⏎ übernimmt weiterhin nur die gefahrlosen; die anderen über ihre Nummer). In einer App mit No AI laufen die Prüfungen trotzdem, und nur die Frage wird abgelehnt. Mit Apple Intelligence, wenn dieser Mac sie hat, die die benötigten Prüfungen als Werkzeuge aufruft; sonst mit deinem Anbieter, und das Fenster sagt das. Gesendet werden nur die Prüfergebnisse (keine Pfade über `~` hinaus, keine Schlüssel, nichts von deinem Text) und deine Frage; die Prüfungen allein senden nichts außer der Anfrage von Test Connection (nur wenn der Anbieter einen Schlüssel oder Zugangsdaten zum Testen hat).

## Menüleistenfenster

<img src="../en/panel-swipe.png" width="520" alt="Das Menüleistenfenster: Milchglas, mit Notizen, Erinnerungen und Claude-Aufgaben auf Karten; eine nach links gewischte Zeile zeigt ihre Schaltfläche Remove">

Klicke auf das Symbol von AllInOneIME in der Menüleiste (das Zeichen aus ∞ und Cursor, ohne Rahmen; das umrahmte ist die Eingabequelle), und das Fenster klappt darunter auf; ein Klick woandershin schließt es:

- Notes (Notizen): die mit `@note` gespeicherten Notizen, die neuesten 5; klicke auf eine, um sie in Notizen zu öffnen.
- Reminders (Erinnerungen): die noch nicht erledigten Erinnerungen in der Liste AllInOneIME der App Erinnerungen (`@reminder` fügt sie dieser Liste hinzu), die am frühesten fälligen zuerst, 8 angezeigt; klicke auf den Kreis, um eine abzuhaken, oder auf den Titel, um Erinnerungen zu öffnen.
- Claude Tasks (Claude-Aufgaben): wie `@tasks` die Claude-Aufgaben im Hintergrund (was `@agent` an Claude Code übergibt), bis zu 30, 5 auf einmal angezeigt: scrolle für mehr, oder durchsuche ihre Titel und Antworten im Suchfeld; mit ihrem Fortschritt und der ersten Zeile der letzten Antwort; klicke auf eine, um sie im Terminal zu öffnen und weiterzumachen.

Wische eine Zeile (eine Notiz, eine Erinnerung oder eine Aufgabe) mit zwei Fingern nach links, um ihre Schaltfläche Remove (entfernen) anzuzeigen, oder ganz durch, um sie sofort zu entfernen; mit einer Maus klicke mit der rechten Maustaste darauf. Entfernen nimmt sie nur aus dem Fenster: Die Notiz bleibt in Notizen, die Erinnerung in Erinnerungen (nicht erledigt), die Aufgabe in Claude Code.

Die Kopfzeile zeigt die Anzahlen (etwa "2 reminders · 1 task running"; Aufgaben, die auf dich warten, werden getrennt gezählt, etwa "1 waiting for you") und eine Schaltfläche zum Aktualisieren. Es nimmt der App, in der du tippst, nie den Fokus: Das Abhaken einer Erinnerung oder das Aktualisieren lässt diese App im Vordergrund; nur das Suchfeld der Claude-Aufgaben übernimmt, sobald es angeklickt wird, die Tastatur. Das Symbol wird standardmäßig angezeigt; schalte es unter "Menu Bar Panel" in den Einstellungen aus.

Was es liest, und wann:

- Notizen: Die Liste ist die eigene Aufzeichnung des Fensters (die auch erhalten bleibt, während es geschlossen ist), und Notizen wird nie gestartet: Nur wenn Notizen bereits läuft und AllInOneIME zuvor erlaubt wurde, es zu steuern, prüft das Fenster dort auf geänderte Titel und gelöschte Notizen.
- Erinnerungen: Die Liste AllInOneIME wird gelesen, wenn das Fenster aufklappt, alle 60 Sekunden und wenn sich Erinnerungen ändern. Das Fenster bringt macOS nie von sich aus dazu, nach Zugriff zu fragen: Hat macOS dich noch nicht gefragt, zeigt es "Allow Access to Reminders" (Zugriff auf Erinnerungen erlauben), und nur diese Schaltfläche fragt; hast du abgelehnt, zeigt es "Open System Settings" (Systemeinstellungen öffnen).
- Claude-Aufgaben: Das Fenster führt `claude agents` nur aus, während es aufgeklappt ist: einmal beim Aufklappen, beim Aktualisieren und wenn `@agent` eine Aufgabe übergibt; und alle 15 Sekunden, solange eine Aufgabe noch nicht fertig ist, nicht mehr, sobald alle fertig sind. Die letzten Antworten werden vom Ende der Transkripte von Claude Code auf diesem Mac gelesen (`~/.claude/projects`), und nur, wenn sich ein Transkript geändert hat.
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
- **Kandidatenanordnung**: Zum Auswählen von Wörtern stehen Pinyin- und Hindi-Kandidaten standardmäßig nebeneinander (Horizontal), wie bei den Eingabemethoden des Systems: ← → wählen aus, ↑↓ (oder - =) blättern. Wähle Vertical auf der Seite Input, unter den Eingabesprachen, für eine Anordnung untereinander (↑↓ wählen aus). Die @-Befehlsliste und die Ergebnisse sind immer vertikal.
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
3. Das Installationsprogramm ist mit einer Developer ID signiert und von Apple notarisiert, daher fragt macOS beim ersten Mal nur, ob eine aus dem Internet geladene App geöffnet werden soll: Klicke auf Öffnen. (Versionen vor 0.6.3 waren nicht notarisiert: Jede musste einmal unter Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen erlaubt werden.)

Danach ist AllInOneIME aktiviert und in deinen Eingabequellen; wechsle mit Ctrl+Leertaste dorthin (die 🌐-Taste wechselt nur, wenn "Taste 🌐 drücken für" in Systemeinstellungen → Tastatur auf "Eingabequelle ändern" steht). Fordert dich das Installationsprogramm auf, sie von Hand hinzuzufügen, erlaubt dieser Mac Programmen nicht, sie zu aktivieren; füge sie also einmal selbst hinzu: Systemeinstellungen → Tastatur → Texteingabe → Eingabequellen → Bearbeiten … → + (unten links) → Englisch → AllInOneIME (sie tippt auch Pinyin, sobald du Chinesisch unter Input in ihren Einstellungen hinzufügst).

Wenn Ctrl+Leertaste dich nicht zu AllInOneIME bringt oder nach einer Weile zurück zu U.S. wechselt, führe das Installationsprogramm erneut aus: Es fügt AllInOneIME wieder zu deinen Eingabequellen hinzu.

Aktualisieren: Settings → About → Check for Updates (Nach Updates suchen). Wenn es eine neue Version gibt, sagt About das (und eine Zeile im Menüleistenfenster), mit den Neuerungen; "Update to <version>" (Auf <Version> aktualisieren) lädt sie herunter, prüft sie gegen die mit dem Release-Schlüssel von AllInOneIME signierten Update-Informationen, installiert sie und startet die Eingabemethode neu. Deine Einstellungen, Sprachpakete, gelernten Wörter und Erweiterungen bleiben erhalten, und wenn etwas schiefgeht, wird die Version, die du hattest, wiederhergestellt. AllInOneIME schaut einmal am Tag von selbst nach, im Hintergrund (abschaltbar mit "Check for updates automatically" unter About); installiert wird erst, wenn du klickst. Das funktioniert ab 0.6.3; um eine ältere Version zu aktualisieren, oder wenn du es lieber so machst, installiere das Disk-Image der neuen Version darüber, ohne vorher zu deinstallieren. Lies vor dem Upgrade das [Änderungsprotokoll](../../CHANGELOG.md): Es enthält die Änderungen jeder Version und Hinweise zum Upgrade.

Update auf 0.6.3 von einer früheren Version: 0.6.3 ist die erste mit einer Developer ID signierte Version, daher kennt der Schlüsselbund sie noch nicht als die App, die deine Schlüssel gespeichert hat. Wenn sie einen gespeicherten Schlüssel zum ersten Mal braucht (einen API-Schlüssel, die Anmeldung bei AllInOneIME Cloud, das Passwort einer Erweiterung), fragt macOS nach deinem Anmeldepasswort: Gib es ein und klicke auf "Always Allow" (Immer erlauben). Danach fragt es nicht mehr, auch nicht nach späteren Updates. Die Schlüssel für Amazon Bedrock liegen in `~/.aws/credentials`, das davon nicht betroffen ist. Auch die Bedienungshilfen (Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen), die das Einsetzen in Terminals und das Lesen der Markierung brauchen, erfordern einen Schritt: Ist AllInOneIME dort aufgeführt, entferne es und schalte es wieder ein, wenn du gefragt wirst.

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
2. Verwende ein AWS-Profil, dem `bedrock:InvokeModelWithResponseStream` erlaubt ist: statische Schlüssel in `~/.aws/credentials` oder ein Profil, das temporäre Zugangsdaten bezieht (`credential_process`, eine Rolle, SSO; siehe "AWS-Profile" unten).
3. Öffne "AllInOneIME Settings": Du findest es über Spotlight oder unter Programme, oder öffne es über das Symbol der Eingabemethode in der Menüleiste → Settings…. Wähle Profil, Region und Modell und klicke auf "Test Connection" (Verbindung testen). "Language" (Sprache) oben im Einstellungsfenster kann English oder Chinese sein; standardmäßig ("System") folgt es dem System (Chinesisch, wenn Chinesisch in den bevorzugten Sprachen des Systems vor Englisch steht, sonst Englisch). Das Einstellungsfenster, die Hinweise im Kandidatenfenster und das Eingabemenü folgen alle dieser Einstellung.

<img src="../en/settings.png" width="420" alt="Das Einstellungsfenster">

#### AWS-Profile

Jedes Profil, das die AWS CLI verwenden kann, ohne dich etwas zu fragen, funktioniert, aus `~/.aws/config` und `~/.aws/credentials` (oder den Dateien, die `AWS_CONFIG_FILE` und `AWS_SHARED_CREDENTIALS_FILE` in deiner Shell nennen). Innerhalb eines Profils wird die erste dieser Quellen verwendet, die es enthält, in der Reihenfolge der AWS CLI (ein Profil mit `role_arn` und Schlüsseln zugleich ist eine Rolle):

| Art | Im Profil | Erneuert |
| --- | --- | --- |
| Rolle | `role_arn` mit `source_profile` (hier jede Art, auch Ketten; ein Profil, das sich selbst nennt, verwendet seine eigenen Schlüssel) oder `credential_source = Environment`; `role_session_name`, `external_id`, `duration_seconds` | erneut per STS `AssumeRole` (in der `region` des Profils, sonst us-east-1), 5 Minuten bevor sie ablaufen |
| SSO | `sso_account_id`, `sso_role_name` mit `sso_session` und dessen Abschnitt `[sso-session …]` (oder die älteren `sso_start_url`, `sso_region`) | mit deiner zwischengespeicherten Anmeldung erneut abgerufen, 5 Minuten bevor sie ablaufen |
| Statische Schlüssel | `aws_access_key_id`, `aws_secret_access_key` (und `aws_session_token`) in `~/.aws/credentials` | bei jeder Anfrage neu gelesen |
| `credential_process` | `credential_process = /usr/local/bin/my-creds --profile dev` (zerlegt wie ein Shell-Befehl, ohne Shell ausgeführt, mit dem PATH deiner Login-Shell, in deinem Benutzerordner, höchstens 60 s) | erneut ausgeführt, 5 Minuten vor seinem `Expiration`; ohne dieses, wenn AWS die Zugangsdaten ablehnt |
| Statische Schlüssel | dieselben Schlüssel in `~/.aws/config` | bei jeder Anfrage neu gelesen |

Mit dem Profil "default" (oder wenn keines gewählt ist) kommen die Schlüssel aus deiner Shell zuerst, so wie die AWS CLI sie nimmt: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` und `AWS_SESSION_TOKEN`. Ein Profil, das du benennst, wird nie mit ihnen gemischt. `AWS_REGION` (oder `AWS_DEFAULT_REGION`) in deiner Shell hat Vorrang vor der `region` eines Profils, wie in der AWS CLI; das Feld Region in den Einstellungen hat Vorrang vor beiden.

- **Automatisch:** Zugangsdaten, die ablaufen, werden im Arbeitsspeicher gehalten (nie auf die Festplatte geschrieben) und 5 Minuten vor ihrem Ablauf erneut abgerufen; bleiben weniger als 10 Minuten, verwendet eine Anfrage sie und ruft im Hintergrund neue ab, sodass das Tippen nicht darauf wartet. Gleichzeitige Anfragen warten auf einen einzigen Abruf. Antwortet Bedrock, dass die Zugangsdaten abgelaufen sind (`ExpiredTokenException` …), werden sie erneut abgerufen, und die Anfrage wird ein einziges Mal erneut gesendet.
- **SSO:** AllInOneIME verwendet die Anmeldung, die die AWS CLI in `~/.aws/sso/cache` hält (liest sie nur), und kann dich nicht selbst anmelden, da das einen Browser braucht. Wenn die Anmeldung endet, zeigt das Kandidatenfenster "SSO sign-in expired: run aws sso login --profile X" (SSO-Anmeldung abgelaufen: aws sso login --profile X ausführen): Führe das im Terminal aus (die Einstellungen haben Copy Command und Open in Terminal; `@doctor` bietet den Befehl zum Kopieren an), und AllInOneIME übernimmt die neue Anmeldung von selbst.
- **Nicht unterstützt:** `mfa_serial` (eine Eingabemethode kann dich nicht nach einem MFA-Code fragen: Verwende `credential_process` oder SSO, oder lass deine CLI Zugangsdaten zwischenspeichern), `credential_source = Ec2InstanceMetadata` oder `EcsContainer` (nicht auf einem Mac) und Web Identity.
- **Bekannte Grenzen:** Nur PATH und die Variablen für die AWS-Dateien (`AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`) kommen aus deiner Login-Shell, auch für `credential_process` (nicht der Rest ihrer Umgebung). AllInOneIME erneuert keine `sso_session`-Tokens (das Refresh-Token der CLI wird nicht verwendet: Der SSO-Cache wird nur gelesen); wenn das zwischengespeicherte Token abläuft, führe also `aws sso login` aus (die AWS CLI erneuert es auch, wann immer du sie benutzt).
- **Settings → AI Provider** listet jedes Profil mit seiner Art ("dev — Role via base") und sagt beim gewählten, wann seine Zugangsdaten ablaufen ("Role via base: credentials expire at 15:30", "SSO (signed in until 18:00)") oder was zu tun ist. Test Connection ruft über die ganze Kette frische Zugangsdaten ab; `@doctor` meldet dasselbe.
- Programme laufen und AWS wird nach Zugangsdaten gefragt (`sts.<region>.amazonaws.com`, `portal.sso.<region>.amazonaws.com`) nur, wenn eine Anfrage oder Test Connection sie braucht: nie, um Profile aufzulisten, nie für `@config`.

### Andere KI-Anbieter: Claude API, Gemini, OpenAI-kompatible Dienste

Du brauchst kein AWS: Wähle unter "AI Provider" (KI-Anbieter) in den Einstellungen einen aus, füge einen API-Schlüssel ein, klicke auf "Save" (speichern) und dann auf "Test Connection".

| Anbieter | Standardmodell | API-Schlüssel |
|---|---|---|
| Claude API | `claude-haiku-5-5` (am schnellsten und günstigsten; Sonnet 5.5 und Opus 5.5 sind sorgfältiger, aber langsamer und teurer) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| OpenAI-kompatibel | `gpt-6-luna` von OpenAI (oder `gpt-5.4-mini`); "Common Services…" (gängige Dienste) enthält DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter und Ollama auf diesem Mac: Die Auswahl eines Dienstes trägt seine Basis-URL ein, dann gib sein Modell ein | Der Schlüssel des Dienstes; setze die Base URL auf seine Adresse, z. B. `https://api.deepseek.com/v1`, oder `http://localhost:11434/v1` für Ollama auf diesem Mac |

- API-Schlüssel werden im Schlüsselbund des Systems gespeichert, nie in der Konfigurationsdatei. Ist dort keiner, werden `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (oder `GOOGLE_API_KEY`) und `OPENAI_API_KEY` aus deiner Shell verwendet.
- Die Zeile für den API-Schlüssel zeigt, ob ein Schlüssel festgelegt ist: "✓ Saved · ends in a1b2" (gespeichert · endet auf a1b2: seine letzten 4 Zeichen, mit ihm gespeichert, damit der Schlüssel selbst zum Anzeigen nicht gelesen wird) mit Replace… (ersetzen) und Remove… (entfernen), "✓ From $OPENAI_API_KEY" (aus $OPENAI_API_KEY) für einen aus deiner Shell oder "No API key yet" (noch kein API-Schlüssel) mit dem Feld zum Einfügen.
- "Thinking" (Nachdenken) steht standardmäßig auf niedrig: Die Eingabemethode wartet bei jedem Satz, und weniger Nachdenken ist schneller. Wähle "Not set" (nicht festgelegt) für Modelle, die es nicht unterstützen.
- Ist Claude Opus 5.5 oder Sonnet 5.5 gewählt, enthalten die Anfragen den Ablehnungs-Fallback der Claude API (`fallbacks: "default"`): Lehnt ein Sicherheitsklassifikator ab, versucht der Server es mit einem anderen Modell erneut.
- In der Konfigurationsdatei: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), sowie `model`, `baseURL`, `effort` und `temperature` unter `anthropic`, `gemini` und `openai` (nicht gesetzte verwenden die Standardwerte).

### Apple Intelligence auf diesem Mac (macOS 26)

Auf einem Mac mit Apple Intelligence (Apple Chip, macOS 26 oder neuer, eingeschaltet unter Systemeinstellungen → Apple Intelligence & Siri) wähle "Apple Intelligence (on this Mac)" unter "AI Provider": kein Schlüssel, keine Kosten, und nichts, was du tippst, verlässt den Mac. Es nutzt das in macOS eingebaute Modell (das Foundation Models Framework), mit denselben Anweisungen und demselben Antwortformat wie die anderen Anbieter, aber nur den Beispielen, die in der Sprache des Satzes geschrieben sind (ein kleines Modell übernimmt die Sprache eines Beispiels zu bereitwillig).

- Es ist ein kleines Modell: Sein Kontext umfasst etwa 4K Tokens (8K unter macOS 27), ein langer Absatz kann also zu lang dafür sein, und es spricht weniger Sprachen (Englisch, Chinesisch, Japanisch, Koreanisch, Französisch, Deutsch, Spanisch und ein paar weitere; kein Hindi). In beiden Fällen sagt es das. Seine Ergebnisse liegen unter denen der Cloud-Modelle, und seine `@question`-Antworten zu Fakten und Code sind oft falsch.
- Wo es nicht verwendet werden kann, wird es ausgegraut mit dem Grund aufgeführt (auf diesem Mac nicht unterstützt, ausgeschaltet, Modell nicht bereit), und die Einstellungen verlinken zu Systemeinstellungen → Apple Intelligence & Siri. Vor macOS 26 wird es nicht aufgeführt.
- "Output tokens", Temperatur und Zeitlimit unter "Model Settings" gelten dafür. In der Konfigurationsdatei: `"provider": "apple"`.

### Sensible Informationen verbergen (neu)

Settings → AI Provider → Privacy → "Hide sensitive information before sending" (sensible Informationen vor dem Senden verbergen; standardmäßig aus): Bevor eine Anfrage an die KI geht, wird, was es in deinem Text findet, auf dem Mac durch Platzhalter wie `[EMAIL_1]` ersetzt (gleicher Wert, gleicher Platzhalter), und die Ergebnisse bekommen die echten Werte zurück, bevor sie angezeigt oder eingefügt werden. Das Fenster zeigt "2 items hidden from the AI" (2 Elemente vor der KI verborgen). Jede Art lässt sich ausschalten:

| Art | Zum Beispiel | In der Konfiguration |
| --- | --- | --- |
| E-Mail-Adressen | `bob@example.com` | `emails` |
| Telefonnummern | `+1 (555) 123-4567`, `138 0013 8000` | `phones` |
| Kartennummern (Luhn-geprüft) | `4111 1111 1111 1111` | `cards` |
| API-Schlüssel und Tokens | bekannte Präfixe wie `sk-` oder `ghp_`, lange zufällige Zeichenfolgen | `keys` |
| IP-Adressen | `203.0.113.42`, `2001:db8::1` | `ips` |
| Deine eigenen Wörter, ohne Rücksicht auf Groß- und Kleinschreibung | ein Codename wie `Project Atlas`, ein Name | `customWords` |

- Es gilt für `@improve`, `@translate`, `@question`, deine Prompt-Befehle und Prompt-Plugins sowie das Verfeinern ihrer Ergebnisse (dieselben Platzhalter), bei jedem Anbieter, einschließlich AllInOneIME Cloud und Apple Intelligence. Einträge der Jargon-Liste, die einen zu verbergenden Wert enthalten, werden nicht gesendet.
- Es erkennt formatierte Werte; Namen oder Adressen kann es nicht erkennen, füge sie also als eigene Wörter hinzu. `@agent`, Plugins, die etwas von einer Website abrufen (`@stock`) oder eine öffnen (`@x`), und Skript-Erweiterungen senden den Text, wie er getippt wurde. Mehr unter Datenschutz.
- In der Konfiguration: `"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`.

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
| `candidateLayout` | Pinyin- und Hindi-Kandidaten: `"vertical"` (untereinander) oder `"horizontal"` (nebeneinander; ← → wählen aus, ↑↓ blättern) | `"horizontal"` |
| `fuzzyPinyin` | Paare für unscharfes Pinyin: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | @-Befehle arbeiten mit dem im Feld markierten Text (siehe Auf dem markierten Text) | `true` |
| `checkForUpdates` | Einmal am Tag im Hintergrund nach einer neuen Version suchen; installiert wird erst, wenn du klickst | `true` |
| `agent` | Der Coding-Agent, an den `@agent` den Text übergibt: `claude` (Claude Code), `gemini` (Gemini CLI), `kiro` (Kiro CLI) oder `custom` | `claude` |
| `agentCommand` | Der Befehl des eigenen Agenten, das Getippte als letztes Argument angehängt, z. B. `["muse", "--"]` | `[]` |
| `claudeInBackground` | `@agent` mit Claude Code läuft im Hintergrund und benachrichtigt dich (andere Agenten öffnen sich immer im Terminal) | `true` |
| `rememberQuestions` | Deine letzten 5 `@question`-Fragen und ihre Antworten auf diesem Mac behalten, aufgelistet unter `@question` (siehe Letzte Fragen) | `true` |
| `questionRounds` | Runden einer `@question`-Unterhaltung im Fenster, bevor es vorschlägt, woanders weiterzumachen, 2–10 | `5` |
| `questionContinueIn` | Wo sich eine `@question`-Unterhaltung fortsetzen lässt, in Reihenfolge, die erste ist die Standardwahl: `claudeCode` (der Agent, an den `@agent` übergibt), `claudeWeb`, `chatgpt`, `gemini`, `copy` | der Agent von `@agent` (falls installiert), Claude, ChatGPT, kopieren |
| `appProfiles` | Einstellungen einer App, nach Bundle-ID, jede optional: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI` (siehe Einstellungen pro App) | `{}` |
| `redaction` | Sensible Informationen vor der KI verbergen (siehe Datenschutz): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`; jeder Detektor (`emails`, `phones`, `cards`, `keys`, `ips`) ist an, sofern nicht auf `false` gesetzt | `enabled: false` |

## Datenschutz

- Tippen (Englisch und Pinyin) und Berechnungen mit `@calculate` sind vollständig lokal. Nur wenn du bei `@improve`, `@translate` oder `@question` die Aktionstaste drückst, wird dieser Satz an den von dir gewählten KI-Anbieter gesendet (dein eigenes Bedrock oder den Dienst, dessen Schlüssel du hinzugefügt hast). Ist "Jargon" angehakt und eine Jargon-Liste festgelegt, wird die Liste mitgesendet. Das Verfeinern der Ergebnisse (eine danach getippte Anweisung, dann ⇧⏎) sendet dieselbe Anfrage erneut, mit den angezeigten Ergebnissen und deiner Anweisung; eine Nachfrage (⇧⏎) sendet die bisherige Unterhaltung mit.
- `@config` und `@doctor <question>` senden Text an ein Modell, wenn du ⏎ drückst: an Apple Intelligence auf diesem Mac, wann immer sie verfügbar ist (nichts verlässt den Mac), sonst an deinen Anbieter. `@config` sendet deinen Satz (ein darin getippter Schlüssel wird vorher entfernt) mit den aktuellen Werten der Einstellungen, die es ändern darf: nie einen Schlüssel und nicht die Wörter, die du vor der KI verbirgst (nur ihre Anzahl), und die Namen deiner AWS-Profile nur, wenn es im Satz um AWS oder Bedrock geht. `@doctor <question>` sendet deine Frage mit den Prüfergebnissen, maskiert: keine Pfade über `~` hinaus, keine Schlüssel, Protokollzeilen als feste Formulierungen. Das Verbergen sensibler Informationen gilt für beide, wie für jede Anfrage. Die Prüfungen allein (`@doctor` ohne etwas dahinter) senden nichts außer der Anfrage von Test Connection, und auch die nur, wenn der Anbieter einen Schlüssel oder Zugangsdaten zum Testen hat.
- Eine `@question`-Unterhaltung anderswo fortzusetzen (⌘1 … nach der letzten Runde oder ⌘⏎) sendet sie, mit dem, was du getippt hast, an den Dienst, den du auswählst: der Agent, an den `@agent` übergibt, auf diesem Mac (standardmäßig Claude Code von Anthropic), claude.ai, chatgpt.com oder gemini.google.com, in der Webadresse oder über die Zwischenablage. Sie geht so hinaus, wie du sie gesehen hast: Werte, die vor den Anfragen an die KI verborgen werden (siehe unten), sind unverändert darin enthalten, denn du entscheidest dich, sie dorthin zu senden. Nichts geht irgendwohin, bis du eines auswählst; "Copy the conversation" legt sie nur in die Zwischenablage.
- Mit AllInOneIME Cloud geht der Satz über den Server des Entwicklers an einen Modellanbieter (derzeit über OpenRouter): Der Server speichert nur Zählwerte, nie den Text. Bei der Anmeldung wird nur deine E-Mail-Adresse gespeichert.
- Sensible Informationen verbergen (Settings → AI Provider → Privacy, standardmäßig aus): Bevor eine Anfrage hinausgeht (`@improve`, `@translate`, `@question`, deine Prompt-Befehle und Prompt-Plugins, bei jedem Anbieter einschließlich AllInOneIME Cloud), werden E-Mail-Adressen, Telefonnummern, Kartennummern (Luhn-geprüft), API-Schlüssel und Tokens (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…` und lange zufällige Zeichenfolgen), IP-Adressen und deine eigenen Wörter (ein Codename, ein Name) auf dem Mac durch Platzhalter wie `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]` ersetzt; derselbe Wert bekommt denselben Platzhalter. Die Ergebnisse des Modells bekommen die echten Werte zurück, bevor sie angezeigt oder eingefügt werden, und das Fenster zeigt "2 items hidden from the AI". Ein Ergebnis, dessen Platzhalter das Modell bis zur Unkenntlichkeit verändert hat, wird so angezeigt, wie es geschrieben wurde, markiert mit "⚠ placeholder changed". Einträge der Jargon-Liste mit einem verborgenen Wert werden nicht gesendet. Jede Art lässt sich ausschalten. Auch Formen in voller Breite (`zhang＠example.com`, `１３８…`) werden gefunden, und ein Wert oder eine Wendung darf durch einen Zeilenumbruch geteilt sein. Es erkennt formatierte Werte wie E-Mails, Nummern und Schlüssel; Namen oder Adressen kann es nicht erkennen (füge sie als eigene Wörter hinzu), ebenso wenig ähnlich aussehende Buchstaben aus anderen Alphabeten. Gilt für Anfragen an deinen KI-Dienst; `@agent`, Plugins, die etwas von einer Website abrufen (`@stock`) oder eine öffnen (`@x`), und Skript-Erweiterungen senden den Text, wie er getippt wurde. In der Konfiguration: `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- Sprache wird nur aufgenommen, während du die rechte ⌥-Taste hältst, und auf dem Mac erkannt; der erkannte Text wird nur in den oben genannten Befehlen gesendet, wenn du die Aktionstaste drückst.
- Die Eingabemethode liest den Text der Zwischenablage einmal und nur dann, wenn du in einem Befehl ⌃V oder ⌘V drückst; Inhalte, die Passwortmanager als verborgen markieren, werden nicht gelesen. Der Text wird zuerst im Befehl angezeigt und, wie gesagt, nur gesendet, wenn du die Aktionstaste drückst. Neuere macOS-Versionen fragen, ob AllInOneIME die Zwischenablage lesen darf: Erlaube es. Damit du nicht jedes Mal gefragt wirst, stelle die Einfüge-Berechtigung von AllInOneIME unter Systemeinstellungen → Datenschutz & Sicherheit auf immer erlauben.
- In Passwortfeldern wechselt macOS zu seiner eigenen Tastatur (U.S. oder ABC) und zurück, wenn du sie verlässt. Immer wenn die App, in der du tippst, die sichere Eingabe hält, setzt AllInOneIME keinen Text zusammen und kann nicht aufnehmen: Tasten gehen so hinein, wie sie getippt werden. Und solange das System in sicherer Eingabe ist (Passwortfelder, Sichere Tastatureingabe im Terminal usw.), wird nichts an die KI gesendet.
- `@note` und `@reminder` gehen nicht an die KI: AllInOneIME übergibt den Text nur an Notizen und Erinnerungen auf diesem Mac und wertet auch die Zeit der Erinnerung auf dem Mac aus (ob diese Apps sie mit deinen anderen Geräten synchronisieren, hängt von deren Konten ab, etwa iCloud). Daher funktionieren sie auch während einer sicheren Eingabe.
- `@reportissue` (und "Report an Issue…") sendet selbst nichts: Es öffnet die GitHub-Seite für ein neues Issue in deinem Browser, mit dem Titel, den du getippt hast, und den oben genannten Versionen, Sprachen, der Art des Anbieters und den Anzahlen, die zuerst im Kandidatenfenster angezeigt werden. Nichts erreicht GitHub, solange du dort nicht auf Submit klickst.
- `@open` sucht nur auf diesem Mac. Es merkt sich, was du damit geöffnet hast (die letzten 200), in den eigenen Einstellungen der Eingabemethode (nicht in config.json), um diese zuerst aufzulisten.
- Für "Add App…" unter Settings → Apps speichert die Eingabemethode die Bundle-IDs der letzten 12 Apps, in denen du getippt hast, in ihren eigenen Einstellungen; sonst nichts über sie.
- `@question` merkt sich deine letzten 5 Fragen mit ihren Antworten und dem Zeitpunkt, zu dem sie gestellt wurden, nur auf diesem Mac, in `~/Library/Application Support/AllInOneIME/recent-questions.json` (nur für dein Benutzerkonto lesbar), um sie unter `@question` aufzulisten; eine gespeicherte Antwort wird von dort angezeigt, ohne online zu gehen. Während sicherer Eingabe wird nichts gespeichert, und Fragen zu markiertem Text werden gar nicht gespeichert (ihre Antwort handelt von der Markierung, die sonst auf der Festplatte landen würde). Wird "Remember recent questions" unter Settings → General ausgeschaltet, werden sie ebenfalls gelöscht; wird es über `@config` ausgeschaltet (`rememberQuestions` in der Konfiguration), bleiben sie erhalten, damit es sich genau rückgängig machen lässt. "Clear" löscht sie.
- Um deine Notizen aufzulisten, speichert das Menüleistenfenster die ID und die erste Zeile (bis zu 80 Zeichen) der letzten 30 mit `@note` gespeicherten Notizen in den eigenen Einstellungen der Eingabemethode, auch während das Fenster ausgeschaltet ist.
- `@py` und `@js` laufen nur, wenn du die Aktionstaste drückst, und nur mit Code, den du selbst getippt oder eingefügt hast: Antworten der KI und die Ausgabe anderer Befehle werden nie als Code ausgeführt. `@py` nutzt das `python3` deines Macs, das Dateien lesen und schreiben und ins Netz gehen kann, wie es das im Terminal tut; `@js` läuft in einem eigenen Prozess, der keine Dateien lesen, nicht aufs Netzwerk zugreifen und keine anderen Programme starten kann. Keiner von beiden läuft während einer sicheren Eingabe.
- Update-Prüfung: Einmal am Tag (außer wenn "Check for updates automatically" aus ist) lädt AllInOneIME https://allinoneime.com/update.json und seine Signatur herunter; die Anfrage enthält keine Kennungen und nichts, was du getippt hast. Ein Update wird nur dann heruntergeladen, aus dem GitHub-Release, wenn du auf Update klickst.
- Erweiterungsquellen: git läuft auf deinem Mac, unter deinem Benutzer, nur für die Quellen, die du hinzugefügt hast: ein Abruf (fetch) einmal am Tag für die, die von selbst prüfen (keiner für eine festgelegte), und wenn du auf Check Now, Update oder Re-clone klickst. Es spricht nur mit dem Host des Repositorys, angemeldet über deine eigene Git- und SSH-Einrichtung; nichts, was du tippst, geht mit.
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
make dmg          # the release installer, build/AllInOneIME-<version>.dmg (universal; signed if there's a Developer ID certificate, optionally notarized), and the in-app update, build/AllInOneIME-<version>-update.zip
make update-test  # the in-app updater end to end: a temporary install, a test server on 127.0.0.1, a test key (never the installed app)
```

`make selftest` und `make realtest` hängen nicht von deinen Einstellungen ab. Der Selbsttest verwendet eine eigene Konfiguration (Amazon Bedrock mit dem AWS-Profil und der Region aus deiner, alles andere auf den Standardwerten); der Test in einer echten App stellt den Anbieter während des Laufs auf Bedrock und setzt danach deinen wieder ein. Was sie gerade nicht prüfen können, wird übersprungen, nicht als fehlgeschlagen gewertet: Live-Prüfungen gegen Bedrock ohne Zugangsdaten für dieses Profil und alles, was bei aktiver sicherer Eingabe getippt wird (gesperrter Bildschirm, ein Passwortfeld). Die letzte Zeile zählt bestandene, fehlgeschlagene und übersprungene Prüfungen; nur Fehlschläge lassen den Lauf scheitern, und ein Lauf mit übersprungenen Prüfungen endet mit INCOMPLETE, oder mit SKIPPED, wenn nichts lief, das tippt (BLOCKED: der Test in einer echten App startete auf einem gesperrten Bildschirm), nie mit PASSED.

Aufbau des Codes:

- `Sources/AllInOneIMECore`: Bedrock-Client, SigV4, Prompts, die zweistufige Zustandsmaschine der Eingabe (einschließlich @-Befehlen und der Sprachgeste); keine Abhängigkeit von AppKit
- `Sources/AllInOneIMERime`: Wrapper für librime
- `Sources/AllInOneIME`: die InputMethodKit-Eingabemethode, Kandidatenfenster, Einstellungsfenster, Spracherkennung
- `Sources/AllInOneIMESettings`: der Starter "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: "Install AllInOneIME" auf dem Disk-Image: installiert, aktualisiert und deinstalliert

Sprachpakete haben eine eigene Bibliothek, getrennt von den Plugins: das Repository [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), ausgeliefert unter https://languages.allinoneime.com/, signiert mit einem eigenen Schlüssel. `make pack` baut das Archiv; es wird dort als Release-Asset veröffentlicht (Release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), und `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` schreibt dort `packs.json` und signiert es in `packs.json.sig` mit dem Schlüssel der Sprachpakete aus dem Schlüsselbund (`allinoneime-languages-signing`). Die App liest https://languages.allinoneime.com/packs.json, prüft die Signatur, dann Größe und SHA-256 des Archivs. Um ein Paket von einem lokalen Server auszuprobieren: `--test-key` signiert mit einem Testschlüssel, und `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Eine Version veröffentlichen (der eingebaute Updater liest https://allinoneime.com/update.json, signiert mit dem eigenen Schlüssel der Releases):

1. Erhöhe die Version (`AppVersion.swift` und die drei Info.plist-Dateien; `AppVersionTests` prüft, dass sie übereinstimmen) und aktualisiere die Änderungsprotokolle.
2. `make dmg NOTARY_PROFILE=<profile>`: `build/AllInOneIME-<version>.dmg` mit seiner `.sha256` und `build/AllInOneIME-<version>-update.zip` (beide Apps, wie sie das Installationsprogramm des Disk-Images enthält). Die Apps und das Image werden mit dem Developer-ID-Application-Zertifikat aus dem Schlüsselbund signiert, und das Image wird mit diesem `xcrun notarytool`-Schlüsselbundprofil notarisiert und geheftet (stapled).
3. Lade beides in das GitHub-Release `v<version>` hoch und veröffentliche es.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"` (je ein, zwei Sätze): schreibt `site/public/update.json` (Version, Build und minimales macOS aus den Apps gelesen, Adresse, Größe und SHA-256 der Datei, die Adresse der Versionshinweise und die Zusammenfassung) und signiert sie in `update.json.sig` mit dem Schlüssel aus dem Anmelde-Schlüsselbund (`allinoneime-releases-signing`; macOS fragt eventuell, ob der Zugriff erlaubt wird). Committe beides.
5. Stelle die Website bereit (`cd site && npx wrangler@4 deploy`), erst wenn sich die Dateien des Releases herunterladen lassen: Die Apps schauen einmal am Tag nach, und `AllInOneIME --check-update` zeigt, was sie sehen.

Die App prüft die Signatur des Manifests mit dem eingebauten öffentlichen Schlüssel, bevor sie es liest, installiert nie eine Version, die nicht neuer ist, lädt nur über https von allinoneime.com oder den GitHub-Release-Dateien des Repositorys herunter und installiert das Archiv erst, wenn Größe und SHA-256 mit dem Manifest übereinstimmen, Bundle-IDs, Versionen und Codesignaturen beider Apps stimmen und die neue Eingabemethode startet. Die Eingabemethode übergibt dann an ihre eigene ausführbare Datei als Helfer (`--apply-update`), der wartet, bis sie beendet ist, die Apps so austauscht wie das Installationsprogramm (die alten beiseitegelegt, zurückgelegt, falls etwas fehlschlägt) und die neue registriert. Zum Ausprobieren mit einem lokalen Server: `make update-test`, oder `--test-key` mit `Scripts/build-update-manifest.swift` und `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`.

Die Bundle-ID ist weiterhin `com.aipinyin.inputmethod.AIPinyin`: macOS merkt sich damit die hinzugefügte Eingabequelle und die Mikrofonberechtigung, eine Änderung würde also bedeuten, die Eingabemethode erneut hinzuzufügen und die Berechtigung erneut zu erteilen.

## Lizenz

Copyright © 2026 MicroZ LLC. Quellcode verfügbar unter der [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): Du darfst ihn nutzen, lesen, ändern und weitergeben, für alles außer ein Konkurrenzprodukt. Jede Version wird zwei Jahre nach ihrer Veröffentlichung zu Apache-2.0. Versionen bis einschließlich 0.6.1 wurden unter der GPL-3.0 veröffentlicht und bleiben unter ihr verfügbar.

Komponenten von Drittanbietern (librime und seine Plugins unter BSD-3-Clause; die Lua-Skripte von rime-ice und das chinesische Sprachpaket unter GPL-3.0) sind in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) aufgeführt.
