<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · [繁體中文](README_zh-TW.md) · [日本語](README_ja.md) · [한국어](README_ko.md) · [Français](README_fr.md) · [Deutsch](README_de.md) · [Español](README_es.md) · [Português (Brasil)](README_pt-BR.md) · **Italiano** · [Русский](README_ru.md) · [Tiếng Việt](README_vi.md) · [ไทย](README_th.md) · [Bahasa Indonesia](README_id.md) · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · [Türkçe](README_tr.md)

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="Icona di AllInOneIME">

# AllInOneIME

### Comandi IA in ogni campo di testo del tuo Mac.

Scrivi `@improve`, `@translate` o `@question` in qualsiasi app, premi ⏎ e scegli il risultato.<br>
Niente copia in una finestra di chat, niente cambi di app. Il tuo fornitore di IA, le tue chiavi.

[![Versione](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#installazione)
[![Apple silicon e Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#installazione)
[![Licenza: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![Download](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[Scarica](https://allinoneime.com/download)** · **[Sito web](https://allinoneime.com)** · **[Documentazione](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[Estensioni](../extensions.md)**

[Come si usa](#come-si-usa) · [Comandi](#comandi--beta) · [I tuoi comandi](#i-tuoi-comandi) · [Lingue](#inserimento-e-traduzione) · [Voce](#input-vocale) · [Installazione](#installazione) · [Privacy](#privacy)

<br>

<img src="../en/demo.png" width="820" alt="@translate e una frase, poi ⏎: una riga in spagnolo, francese e tedesco">

</div>

*Questa è una traduzione del README in inglese; dove differiscono, fa fede la versione inglese.*

> [!NOTE]
> AllInOneIME non è ancora autenticato (notarized) da Apple: la prima volta, consentilo in System Settings → Privacy & Security → Open Anyway (Impostazioni di Sistema → Privacy e sicurezza → Apri comunque). Scaricalo solo dalle [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) o da [allinoneime.com](https://allinoneime.com).

Un metodo di inserimento per macOS con comandi IA in ogni campo di testo. Inizia una frase con `@` e premi ⏎ quando hai finito: `@improve` rifinisce ciò che hai scritto e propone alcune riformulazioni, `@translate` lo traduce nelle lingue che scegli, `@question` fa una domanda, `@claude` lo passa a Claude Code, e `@open` trova file e app o apre un indirizzo web. Puoi anche tenere premuto il tasto ⌥ destro e parlare. Senza `@`, i tasti vanno all'app come al solito. Scrive anche in cinese (pinyin, basato su Rime e rime-ice), francese, coreano (hangul) e hindi (devanagari a partire da lettere latine), ed esegue i tuoi script come comandi @.

![@improve e una frase grezza, poi ⏎: versioni rifinite, più riformulazioni](../en/improve.png)

Per maggiori dettagli (ogni comando e impostazione, risoluzione dei problemi di installazione, privacy), consulta la [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Realizzato da [Weijian Zhang](https://weijianz.com) presso MicroZ LLC.

## Come si usa

Senza `@`, non si mette in mezzo: in inglese le lettere vengono digitate direttamente e ⏎ è Invio; niente va online. Una nuova installazione scrive in inglese; per scrivere anche in cinese (pinyin), francese, coreano o hindi, aggiungilo nelle impostazioni (vedi [Inserimento e traduzione](#inserimento-e-traduzione)).

| Tasto | Cosa fa |
|---|---|
| Digitare pinyin, Spazio / cifre | In modalità cinese: scegliere le parole, come in qualsiasi metodo di inserimento pinyin |
| `@` (all'inizio di una frase) | Apre l'elenco dei comandi: prima i più usati di recente, 5 alla volta, scorrevoli con ↑↓, la rotella o il trackpad; oppure digita delle lettere per trovarne uno (prima i nomi che iniziano con esse, poi quelli che le contengono). ⏎, Tab, Spazio o una cifra lo sceglie |
| ⏎ | Esegue il comando. Funziona anche se il pinyin non è ancora stato scelto: viene scelto prima, come con Spazio |
| Spazio, ⏎ / cifre | Quando compaiono i risultati: inserisce quello evidenziato / numerato; 0 è l'originale |
| ⌘C | Copia il risultato evidenziato (per `@open`, il percorso); il pannello dei candidati resta aperto |
| ⌃V | In un comando (ad es. dopo `@improve `): aggiunge il testo degli appunti dopo ciò che hai digitato invece di incollarlo nell'app. Più righe diventano una sola, fino a 2000 caratteri alla volta (`@note` mantiene gli a capo e ne accetta fino a 20000). Funziona in qualsiasi app; senza un comando, il tasto va all'app come al solito |
| ⌘V | Come ⌃V, ma alcune app gestiscono ⌘V da sé (terminali come Ghostty, iTerm2 e Terminale, e Note) e incollano nell'app come al solito; lì usa ⌃V |
| Esc, ⌫ | Torna alla frase per continuare a modificarla; basta continuare a scrivere per proseguirla |
| Tocco breve su Maiuscole | Con più lingue di inserimento: la successiva, nel loro ordine (inglese → cinese → francese → …, poi di nuovo la prima) |
| Tenere premuto ⌥ destro | Parla, rilascia per fermarti. Nella lingua in cui stai scrivendo (inglese, cinese, francese, coreano o hindi). In un comando, il testo va dopo di esso; altrimenti viene inserito direttamente |

## Comandi @ (beta)

| Comando | Cosa fa |
|---|---|
| `@improve` | Rifinitura: 1–3 sono tre versioni nella lingua della frase stessa, da 4 in poi gli stili di riformulazione (aggiunti e ordinati nelle impostazioni), 0 è l'originale. Nessuna traduzione; con "@improve also translates" (@improve traduce anche) attivo, funziona come `@translate @improve` |
| `@translate` | Traduce nelle lingue che hai aggiunto (impostazioni → Translate, trascina per riordinare), una riga ciascuna, tre versioni se ce n'è una sola; la lingua della frase stessa viene saltata. `@translate @improve` insieme traducono e riformulano in un'unica richiesta |
| `@question` | Fa una domanda; la risposta compare tra i candidati, ⏎ o Spazio la inserisce, ⌘C la copia |
| `@claude` | Passa il compito a Claude Code: in background per impostazione predefinita, con una notifica quando ha finito (fai clic sulla notifica per aprire la sessione in Terminale e proseguire), oppure consulta `@tasks`. Usa il tuo Claude Code (il comando `claude`) con il suo accesso e le sue impostazioni. Disattiva "@claude runs in the background" (@claude viene eseguito in background) nelle impostazioni per aprirlo in Terminale come prima. La prima volta che apre Terminale, macOS chiede se AllInOneIME può controllare Terminale: fai clic su OK |
| `@tasks` | Elenca le attività di Claude in background (in corso / completata / ti aspetta) con le loro ultime risposte; ⏎ ne apre una in Terminale, ⌘C copia la risposta |
| `@settings` | Apre subito la finestra delle impostazioni (basta sceglierlo) |
| `@open` | Elenca file, cartelle e app corrispondenti mentre scrivi (Spotlight). Funzionano più parole chiave separate da spazi: ognuna deve comparire nel percorso, almeno una nel nome (il nome di una cartella standard vale per il suo contenuto: `downloads pdf` trova i PDF in Downloads (Download)). Le app e le cartelle standard si trovano anche con il loro nome cinese, e un'interfaccia in cinese le mostra così. Ciò che hai aperto con `@open` viene per primo, poi le app e quelle cartelle, poi i file usati o modificati di recente; quando i nomi trovano due file o meno e nessuna app né alcuna di quelle cartelle, i file nella tua cartella Inizio vengono cercati anche per contenuto, con quelle righe contrassegnate da "content" (contenuto); quando non c'è nient'altro, ⏎ li elenca per farti scegliere invece di aprire il primo. Con un indirizzo web (`github.com`, `localhost:3000`, `https://…`), la prima riga è "open in the browser" (apri nel browser) e i contenuti non vengono cercati; un file con esattamente quel nome (per esempio `MANIFEST.in`) viene per primo. Un testo che inizia con `~/` o `/` è un percorso: Tab lo completa ed entra nelle cartelle; ⏎ apre, ⌘C copia il percorso |
| `@note` | Salva il testo nell'app Note, in una cartella chiamata AllInOneIME (creata se manca); non viene inserito nulla. Il testo incollato mantiene gli a capo, fino a 20000 caratteri |
| `@reminder` | Aggiunge un promemoria all'app Promemoria, in un elenco chiamato AllInOneIME. Scrivi l'ora nel testo; viene interpretata sul Mac, e una riga mostra cosa è stato capito: ⏎ o Spazio lo aggiunge, Esc torna alla modifica. Con un'ora, ha un avviso a quell'ora; con solo una data, vale per tutto il giorno |
| `@calculate` | Calcola su questo Mac; il risultato compare tra i candidati, ⏎ o Spazio lo inserisce: `@calculate 23*17` → `391`. Funziona anche all'interno di una frase: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Esegue una riga di Python (il `python3` del Mac) e inserisce il risultato: il valore dell'ultima espressione del codice, ad es. `@py 2**100`, `@py import math; math.sqrt(2)`, oppure ciò che ha stampato. Non è proposto senza `python3` (gli strumenti da riga di comando di Xcode lo includono) |
| `@js` | Esegue una riga di JavaScript e inserisce lo stesso: il valore dell'ultima espressione o ciò che ha stampato `console.log`, ad es. `@js [1, 2, 3].map(x => x * 2)`. Usa JavaScriptCore, integrato in macOS, quindi non c'è nulla da installare; non può leggere file, accedere alla rete né eseguire altri programmi |
| `@imessage` | Invia un iMessage: digita un nome, un numero di telefono o un'email (un nome cinese anche col suo pinyin, completo o con le iniziali) e scegli il destinatario nel pannello dei candidati (prima quelli a cui hai scritto di recente; funziona anche un numero o un indirizzo completo), poi scrivi il messaggio (i comandi al suo interno come `@stock AAPL` vengono eseguiti prima). ⏎ mostra "Send to Alex (…): message" nel pannello, un altro ⏎ lo invia, Esc torna alla modifica; nel campo di testo non viene digitato nulla. La prima volta, macOS chiede se AllInOneIME può accedere a Contatti e controllare Messaggi: fai clic su OK per entrambi |

Esempio: `@q` ⏎, digita `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ salva una nota. `@reminder call Bob tomorrow at 3pm` ⏎, controlla l'ora interpretata, poi di nuovo ⏎ per aggiungerlo. Una volta scelto il comando, puoi anche tenere premuto ⌥ destro e parlare. In modalità cinese, `@open` e `@calculate` passano momentaneamente alle lettere latine e tornano al cinese quando hai finito.

Il codice per `@py` e `@js` si digita in lettere latine, e la punteggiatura a larghezza piena (dalla modalità cinese) diventa ASCII; scrivilo su una sola riga, con `;` tra le istruzioni. Viene eseguito in un processo separato, interrotto dopo 10 secondi o in qualsiasi momento con Esc; in caso di errore, viene mostrata la prima riga dell'errore, ad es. `ZeroDivisionError: division by zero`. Un output su più righe viene inserito così come è stato stampato; in un terminale va su una sola riga (un terminale esegue ogni riga che riceve). Un terminale all'interno di un editor (VS Code, Cursor, JetBrains) non si distingue dall'editor stesso, quindi lì l'output su più righe di qualsiasi comando viene inserito così com'è. Entrambi funzionano anche all'interno della frase di un altro comando: `@reply the answer is @py 2**100`; metti tra virgolette il codice con spazi: `@question explain @py "sum(x * x for x in range(10))"`. Non vale il contrario: il codice di `@py` e `@js` viene sempre eseguito esattamente come l'hai digitato, e gli `@commands` al suo interno non vengono eseguiti prima.

![Digitare @ apre l'elenco dei comandi; @question più una domanda, poi ⏎ per la risposta](../en/commands.png)

![@open trova le app mentre scrivi; se inizia con /, è un percorso: la cartella viene elencata, Tab completa](../en/open.png)

Quando `@` non è seguito da un comando, come in `@john`, la `@` viene inserita come al solito, quindi le menzioni con @ nelle app di chat continuano a funzionare. `@question`, `@improve` e `@translate` inviano al tuo Bedrock solo quando premi il tasto azione; `@open` cerca solo su questo Mac; `@note` e `@reminder` vanno solo a Note e Promemoria su questo Mac; `@claude` usa il Claude Code installato sul tuo Mac (il comando `claude`) e il suo account, e ti chiede prima, come al solito, di modificare file o eseguire comandi. Senza Claude Code installato, `@claude` non è proposto. `@imessage` legge solo i Contatti di questo Mac (nomi, numeri di telefono, email), non passa mai per l'IA, ed è Messaggi a inviare il messaggio; senza l'app Messaggi non è proposto.

`@calculate` funziona su questo Mac, offline: `+ - * /` (anche `× ÷`), `^` o `**` per le potenze, le parentesi, le percentuali (`50%` è 0,5, `200*5%` è 10; come su una calcolatrice, una percentuale sommata o sottratta si riferisce a ciò che la precede: `100+10%` è 110, `100-10%` è 90), le funzioni `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` è in base 10, gli angoli sono in radianti, `round(x, 2)` mantiene due decimali) e le costanti `pi` (`π`) ed `e`. Funzionano anche cifre e segni a larghezza piena. L'aritmetica è esatta in decimale, quindi `0.1+0.2` fa `0.3`; i risultati hanno al massimo 15 cifre significative, e i numeri interi fino a 38 cifre sono scritti per intero (`2^100` → `1267650600228229401496703205376`).

### Note e promemoria

`@note` crea una nuova nota; la sua prima riga è il titolo. Dopo aver copiato del testo, ⌃V dopo `@note ` (o ⌘V, fuori dai terminali) lo salva con i suoi a capo, mostrati come ↵ nel comando. Se lasci il campo di testo (fai clic altrove, cambi app) o premi ⇧⏎ (inserisci così come digitato) prima che una nota con a capo sia salvata, non viene digitata nell'app (in un terminale, ogni riga verrebbe eseguita come comando): va invece negli appunti ("The note wasn't saved; its text is on the clipboard"). Una nota di una sola riga viene inserita così come digitata.

`@reminder` capisce indicazioni di tempo come `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (il giorno 1), `end of the year` (anche indicazioni in cinese). Il giorno e l'ora possono essere separati (`tomorrow call Bob at 5`); le settimane iniziano di lunedì. Un'ora senza am o pm (`at 5`) è la prossima, mai tra mezzanotte e le 6 del mattino; un'ora già passata oggi è domani, ma una parte della giornata ancora in corso (`this afternoon`, `tonight`) è oggi, per tutto il giorno; una data già passata quest'anno è quella dell'anno prossimo. Se è scritto per ripetersi (`standup every Monday at 9`), viene aggiunto una volta, per la prossima occorrenza: le parole restano nel titolo e la riga indica "once only" (una sola volta). La riga di conferma mostra l'ora interpretata, ad es. "tomorrow 3:00 PM" (secondo l'impostazione 12/24 ore del Mac); se è sbagliata, Esc torna al testo. Se non contiene né ora né data, non ne ha ("no date").

`@stock` e simili all'interno di questi due non vengono eseguiti: il testo viene salvato così come è scritto (digitare `@` lì non apre l'elenco dei comandi). La prima volta, macOS chiede se AllInOneIME può controllare Note (`@note`) o accedere a Promemoria (`@reminder`): consentilo. Se non l'hai fatto, consenti AllInOneIME in Impostazioni di Sistema → Privacy e sicurezza → Automazione (Note) o → Promemoria. Quando un salvataggio non riesce (per mancanza di permessi, ad esempio), l'avviso ne indica il motivo e il testo torna nel comando, per correggerlo e inviarlo di nuovo; quando devi prima sistemare qualcosa (un permesso, un account), viene anche messo negli appunti (andare in Impostazioni di Sistema toglie il focus dal campo di testo). Se sei passato a un altro campo di testo o stai digitando altro, va invece negli appunti ("Not saved; the text is on the clipboard.").

### I tuoi comandi

Nelle impostazioni, in "Custom @ Commands" (comandi @ personalizzati), fai clic su "Add Command…" (aggiungi comando): dagli un nome e scegli cosa fa (un'istruzione per l'IA, un programma, un programma in Terminale o una pagina web), oppure parti da un esempio. I tuoi comandi vengono dopo quelli integrati; i nomi sono solo in lettere latine e non possono coincidere con quello di un comando integrato; funzionano dalla frase successiva. Sono conservati in `customCommands` nel file di configurazione (`~/.config/allinoneime/config.json`), che puoi anche modificare:

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | Cosa fa |
|---|---|
| `prompt` | Va all'IA con `prompt` come istruzione; la risposta compare tra i candidati, da inserire o copiare (⌘C) |
| `run` | Esegue `argv` in background; ciò che stampa compare tra i candidati (più righe vengono inserite così come stampate, in un terminale su una sola riga). In caso di errore, viene mostrata la sua ultima riga |
| `terminal` | Esegue `argv` in una nuova finestra di Terminale; non viene inserito nulla |
| `link` | Inserisce il testo nell'indirizzo web `url` e lo apre nel browser predefinito; non viene inserito nulla |

- `{input}` diventa ciò che hai scritto dopo il comando, e resta sempre all'interno dell'unico argomento in cui si trova: non è coinvolta alcuna shell. Se ti serve una shell, dichiaralo, come `sh` sopra (`zsh -c`).
- `stdin`: ciò che va all'input standard del programma, con `{input}` anch'esso sostituito.
- L'`url` di un `link` deve iniziare con `https://`, con `{input}` una sola volta, dopo il `?` o il `#`; il testo viene codificato (uno spazio diventa `%20`, un a capo `%0A`), al massimo 4000 caratteri.
- `run` e `terminal` digitano lettere latine per impostazione predefinita (come `@open`; in modalità cinese, il cinese torna dopo), e la punteggiatura a larghezza piena diventa ASCII. Imposta `"ascii": false` per mantenere il testo così come digitato.
- I programmi vengono eseguiti nella tua cartella Inizio con il PATH della tua shell di login (così vengono trovate le installazioni di Homebrew, pyenv e nvm). `run` interrompe un programma dopo 10 secondi (`timeoutSeconds`) o quando stampa troppo; Esc lo interrompe in qualsiasi momento.
- `summary` è la descrizione nell'elenco dei comandi (facoltativa).
- Quando il programma in `argv` non viene trovato (ad esempio, manca `python3`), il comando non è proposto e `@python …` viene inserito come testo; una volta installato il programma, il comando compare nel campo di testo successivo.

`run` e `terminal` eseguono codice sul tuo Mac: aggiungi solo comandi scritti da te e di cui ti fidi. Anch'essi vengono eseguiti solo quando premi il tasto azione, e mai durante l'inserimento sicuro.

### Estensioni script

Aggiungi i tuoi comandi @ come programmi: uno script in qualsiasi linguaggio (bash, Python, Node, Swift, …) con qualche riga di metadati nei commenti. Mettilo in `~/.config/allinoneime/extensions`, o in una cartella che aggiungi in Settings → Custom Commands → Script Extensions. Gli Script Commands di Raycast funzionano così come sono, e le cartelle che già li contengono vengono trovate con Spotlight.

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh` diventa `@flights`. Scrivi i suoi argomenti dopo, separati da virgole: `@flights beijing, new york` lo esegue con `beijing` e `new york` come `$1` e `$2` (le virgole in più restano nell'ultimo); un argomento obbligatorio lasciato vuoto indica cosa manca invece di eseguire lo script. Ciò che stampa viene usato come indica il suo `output`:

| `output` | Cosa succede |
|---|---|
| `insert` (predefinito) | Tutto, e ogni singola riga, da inserire |
| `show` | Mostrato nel pannello man mano che viene stampato (avanzamento); non viene inserito nulla. Se lasci il campo, continua in background (fino a quattro alla volta) |
| `list` | Un elenco nel JSON Script Filter di Alfred, rieseguito mentre scrivi; scegliere una riga inserisce, apre (un indirizzo web, un file o una cartella; mai qualcosa che verrebbe eseguito), copia o avvia un secondo passaggio |
| `silent` | La sua ultima riga vicino al cursore; non viene inserito nulla |

Un comando può anche non ricevere input (`input none`: ⏎ sul suo nome lo esegue), essere eseguito in background (`background`) e avvisarti quando ha finito (nel frattempo il pannello della barra dei menu lo elenca), mostrare uno `status` accanto al suo nome nell'elenco dei comandi, o chiedere conferma prima (`confirm`). Viene eseguito nella propria cartella con il PATH della tua shell di login e le variabili `ALLINONEIME_*`: la lingua dell'interfaccia e di inserimento, l'app in cui stai scrivendo, il testo. Un **bundle** è una cartella con un `extension.json` che ne nomina i comandi: condividono codice e preferenze, che le impostazioni mostrano (le password vanno nel portachiavi). Le impostazioni elencano ogni comando con un interruttore, e gli script esclusi con il motivo.

Le modalità di Raycast si traducono così: `fullOutput` → `show`, `compact` e `silent` → `silent`, `inline` con `refreshTime` → uno stato. L'intero protocollo è in [docs/extensions.md](../extensions.md); [Examples/extensions](../../Examples/extensions) ne contiene uno per ogni tipo. Le estensioni eseguono codice sul tuo Mac: usa solo quelle di cui ti fidi. Vengono eseguite solo quando le esegui tu (uno stato o un elenco mentre scrivi), mai durante l'inserimento sicuro, e si fermano quando il metodo di inserimento si chiude.

### Plugin

I plugin sono comandi `@` già pronti per cose che non servono a tutti, come `@stock AAPL 600519 700` per le quotazioni di borsa. Una volta installati, funzionano come qualsiasi comando; "Plugins" nelle impostazioni mostra cosa è installato e dove ciascuno invia il tuo testo, e permette di rimuoverli. I plugin sono JavaScript eseguito in un processo separato: possono raggiungere solo i siti web che dichiarano (HTTPS), e non possono leggere file né eseguire altri programmi. "Browse Library…" (sfoglia libreria) in Plugins nelle impostazioni li installa dalla [libreria dei plugin](https://github.com/MicroZ-LLC/AllInOneIME-plugins): prima di installare un plugin mostra quali siti web contatta; l'indice della libreria è firmato e ogni file deve corrispondervi. Una versione più recente mostra un pulsante "Update" (aggiorna); nulla si aggiorna da solo. I tuoi plugin vanno in `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): plugin locali, mai sovrascritti dalla libreria. I plugin di tipo "Link" non eseguono codice: inseriscono il testo in un indirizzo web e lo aprono nel browser, come `@x nice weather today`, che apre l'editor dei post di X con il testo già compilato; pubblicare dalla pagina spetta a te. La libreria ne ha quattro (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` converte le valute: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, su una riga con la data del tasso (tassi forniti da ExchangeRate-API). Come scriverne uno: [docs/plugins.md](../plugins.md).

I comandi che recuperano qualcosa (plugin e programmi) funzionano anche all'interno di una frase: `@reply tell her @stock AAPL is up today`. Quelli interni vengono eseguiti per primi, il loro output prende il loro posto, e il comando esterno lavora sul risultato. L'argomento è la parola dopo il comando, più i codici in maiuscolo o i numeri che la seguono subito (`@stock AAPL TSLA`, `@stock 600519 700`); una parola in minuscolo lo chiude (`@stock SNDK is good to buy` cerca SNDK). Le virgolette lo delimitano con esattezza: `@stock "aapl tsla"`. Anche `@calculate` funziona all'interno di una frase; il suo argomento è l'intera espressione che lo segue, spazi compresi, fino ad altro testo: `@reply the total is @calculate 23 * 17 dollars`. All'interno di `@claude` e dei comandi da terminale non vengono eseguiti: questi ricevono il testo così come è scritto (digitare `@` lì non apre l'elenco dei comandi).

### Tasto azione

⏎ per impostazione predefinita; cambialo in "Action key" (tasto azione) nelle impostazioni (`actionKey` nella configurazione): ⏎, Tap ⌥ (tocco breve su ⌥, di entrambi i lati: premi e rilascia subito; tenere premuto ⌥ destro resta per parlare), ⌥Spazio, o Spazio (premi Spazio un'altra volta dopo aver scelto le parole; due volte in modalità inglese). Qualunque sia il tasto azione, i comandi @ vengono eseguiti anche con ⏎. Se ⌥Spazio è già una scorciatoia per Alfred, Raycast o simili, la ricevono loro per primi.

## Pannello della barra dei menu

<img src="../en/panel-swipe.png" width="520" alt="Il pannello della barra dei menu: vetro smerigliato, con note, promemoria e attività di Claude su schede; una riga fatta scorrere verso sinistra mostra il suo pulsante Remove">

Fai clic sull'icona di AllInOneIME nella barra dei menu (il simbolo ∞ con un cursore, senza riquadro; quello con il riquadro è la sorgente di input) e il pannello si apre sotto di essa; un clic altrove lo chiude:

- Notes (note): le note salvate con `@note`, le 5 più recenti; fai clic su una per aprirla in Note.
- Reminders (promemoria): i promemoria non ancora completati nell'elenco AllInOneIME di Promemoria (`@reminder` li aggiunge a quell'elenco), prima quelli con la scadenza più vicina, 8 visibili; fai clic sul cerchio per spuntarne uno, o sul titolo per aprire Promemoria.
- Claude Tasks (attività di Claude): come `@tasks`, le attività di Claude in background (ciò che `@claude` delega), fino a 30, 5 visibili alla volta: scorri per vederne altre, o cerca nei loro titoli e risposte con il campo di ricerca; con il loro avanzamento e la prima riga dell'ultima risposta; fai clic su una per aprirla in Terminale e proseguire.

Fai scorrere una riga (una nota, un promemoria o un'attività) verso sinistra con due dita per mostrare il suo pulsante Remove (rimuovi), o fino in fondo per rimuoverla subito; con un mouse, fai clic destro su di essa. La rimozione la toglie solo dal pannello: la nota resta in Note, il promemoria in Promemoria (non completato), l'attività in Claude Code.

L'intestazione mostra i conteggi (come "2 reminders · 1 task running"; le attività che ti aspettano sono contate a parte, come "1 waiting for you") e un pulsante di aggiornamento. Non toglie mai il focus all'app in cui stai scrivendo: spuntare un promemoria o aggiornare lascia quell'app in primo piano; solo il campo di ricerca delle attività di Claude, una volta cliccato, prende la tastiera. L'icona è visibile per impostazione predefinita; disattivala in "Menu Bar Panel" nelle impostazioni.

Cosa legge, e quando:

- Note: l'elenco è il registro proprio del pannello (conservato anche quando è chiuso), e Note non viene mai avviata: solo quando Note è già in esecuzione, e AllInOneIME era stato autorizzato in precedenza a controllarla, il pannello vi controlla i titoli modificati e le note eliminate.
- Promemoria: l'elenco AllInOneIME viene letto quando il pannello si apre, ogni 60 secondi e quando i promemoria cambiano. Il pannello non fa mai chiedere l'accesso a macOS di sua iniziativa: se macOS non te l'ha ancora chiesto, mostra "Allow Access to Reminders" (consenti l'accesso a Promemoria), e solo quel pulsante lo chiede; se hai rifiutato, mostra "Open System Settings" (apri Impostazioni di Sistema).
- Attività di Claude: il pannello esegue `claude agents` solo mentre è aperto: una volta all'apertura, all'aggiornamento e quando `@claude` delega un'attività; e ogni 15 secondi finché un'attività non è finita, non più una volta che sono tutte finite. Le ultime risposte vengono lette dalla fine delle trascrizioni di Claude Code su questo Mac (`~/.claude/projects`), e solo quando una trascrizione è cambiata.
- Mentre è chiuso, niente di tutto ciò viene eseguito; tiene solo un registro delle note che `@note` salva.

## Inserimento e traduzione

Nelle impostazioni:

- **Lingue di inserimento**: da una a cinque tra inglese, cinese (pinyin), francese, coreano e hindi, aggiunte con + (sempre presente; disattivato a cinque). Una nuova installazione inizia solo con l'inglese. I nuovi campi di testo iniziano nella prima; un tocco breve su Maiuscole passa alla successiva, nel loro ordine; con una sola, Maiuscole non cambia nulla.
  - **Il francese** si digita con il proprio layout di tastiera: AZERTY, a meno che tu non ne scelga un altro nella sua scheda. Anche i suoi tasti morti (^, ¨, `, ´, ~) compongono a partire da esso.
  - **Il coreano** digita l'hangul con il layout a 2 gruppi (Dubeolsik), con ogni sillaba composta mentre scrivi (g k s → 한); Maiuscole dà ㄲ ㄸ ㅃ ㅆ ㅉ e ㅒ ㅖ.
  - **L'hindi**: digita le parole come suonano in lettere latine e ottieni il devanagari (namaste → नमस्ते). Le parole comuni sono scritte come le scrive l'hindi; altrimenti Spazio inserisce la prima grafia, una cifra un'altra, ⏎ le lettere così come digitate, e "." il danda (।).
  - Il nome di un comando, il testo di `@open` e il codice (`@py`, `@js`) si digitano in lettere latine qualunque sia la lingua; questa torna dopo il comando.
  - `@improve` mantiene una frase coreana, hindi o francese nella sua lingua, e `@translate` la traduce nelle tue lingue (il francese viene distinto dall'inglese quando è una delle tue lingue di inserimento).
- **Pacchetti lingua**: l'app include l'inglese (e il francese, che richiede solo il layout di macOS). Cinese, coreano e hindi sono pacchetti che scarichi quando li aggiungi: aggiungere il cinese (pinyin) scarica i suoi dizionari (circa 34 MB, 125 MB decompressi) con una barra di avanzamento, e il pinyin funziona appena finito, senza riavvio; il pacchetto del coreano (la sua tabella dei tasti e il modo in cui i jamo formano le sillabe) e quello dell'hindi (le sue lettere e parole comuni) pesano pochi kilobyte. Un pacchetto contiene solo dati (dizionari, tabelle e schemi, mai codice), è elencato in un indice firmato e viene verificato con il suo SHA-256 prima dell'uso, come i plugin. La scheda di ogni lingua mostra il suo pacchetto (versione, dimensione, provenienza) con Delete… (elimina), e rimuovendo la lingua viene proposto di eliminarne il pacchetto. L'aggiornamento dalla 0.6.1 o precedenti mantiene il cinese senza download: il programma di installazione conserva i dizionari forniti con la vecchia versione.
- **Pinyin approssimativo** (con l'inserimento in cinese): suoni che non distingui, digitati in un modo o nell'altro, ad es. z ↔ zh, n ↔ l, in ↔ ing. Nella pagina Input, scegli Chinese (pinyin) nella barra delle lingue di inserimento, attiva "Fuzzy pinyin" e scegli le coppie; i dizionari vengono ridistribuiti in un secondo o due. Viene scritto `rime_ice.custom.yaml` nella cartella utente di Rime, e mai sopra un tuo file presente lì.
- **Traduzione (@translate)**: aggiungi le lingue in cui tradurre (spagnolo, francese, tedesco, giapponese, coreano, cinese, hindi, bengalese, tamil e le altre principali lingue indiane…) e trascinale nell'ordine voluto. L'hindi digitato in lettere latine ("aap kaise ho") torna in devanagari. `@translate` scrive una riga in ciascuna, in quest'ordine (tre versioni se ce n'è una sola); la lingua della frase stessa viene saltata. Una nuova installazione traduce nella prima lingua tra le lingue preferite del tuo Mac che non sia l'inglese; con il solo inglese, `@translate` apre questa pagina per aggiungerne una.
- **Layout di tastiera**: il francese si digita con il layout scelto nella sua scheda (`keyboardLayouts` nella configurazione). Per le altre lingue, sotto il metodo di inserimento macOS mantiene il tuo ultimo layout latino (AZERTY, QWERTZ, spagnolo, U.S. International…), quindi scrivi come al solito, `@` compresa ovunque la preveda il tuo layout, e i tasti morti compongono anche nel testo di un comando (⌥E poi E → é, ^ poi e → ê). I layout senza lettere latine (russo, hindi InScript) non si possono usare sotto un metodo di inserimento: passa a essi con ⌃Spazio, oppure incolla (⌃V) o detta il testo in un comando.
- `@improve` rifinisce e riformula senza tradurre; `@translate @improve` insieme traducono e riformulano in un'unica richiesta. Attiva "@improve also translates" nelle impostazioni perché `@improve` faccia sempre così.

## Stili di riformulazione

Dopo le righe 1–3 vengono le riformulazioni, **nella lingua in cui hai scritto**: riformulazioni in inglese per l'inglese, in cinese per il cinese. Scegli quelle che vuoi nelle impostazioni:

- Polish (rifinito): stesso tono, più naturale
- Concise (conciso)
- Formal (formale): per responsabili e clienti
- Casual (informale)
- Tactful (diplomatico)
- Jargon (gergo): il gergo di Amazon in inglese (bandwidth, circle back…), il gergo delle big tech in cinese. Le cattive notizie vengono minimizzate, ad es. "this is a blocker bug" → "Oh! Looks like your team has the bandwidth to fix this minor issue!"

Le riformulazioni che cambiano solo la punteggiatura o ripetono un'altra riga non vengono mostrate.

### Elenco del gergo (i tuoi termini)

Jargon non ha un elenco di termini integrato. Puoi prepararne uno tuo (per esempio, le espressioni che usa il tuo team), e il modello ne preferisce i termini. Tra i candidati, la riga Jargon indica cosa significano i termini che ha usato.

L'elenco è un file di testo con un termine per riga, seguito facoltativamente dal suo significato, separato da "=", due punti o una tabulazione (puoi copiare due colonne da un foglio di calcolo e incollarle). Le righe che iniziano con `#` sono commenti:

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

In "Rewrite Styles → Jargon list" nelle impostazioni, fai clic su "New" (nuovo) per creare un elenco vuoto in `~/.config/allinoneime/jargon.txt` e aprirlo; se hai già un file con l'elenco, fai clic su "Choose File…" (scegli file) per usarlo dove si trova (`jargonFile` nella configurazione). Le modifiche si applicano subito. Vengono letti solo i primi 150 termini. Con "Jargon" selezionato, l'elenco viene inviato a Bedrock insieme a ogni richiesta.

<img src="../en/panel-dark.png" width="420" alt="Il pannello dei candidati in modalità scura">

## Input vocale

<img src="../en/voice.png" width="340" alt="Tieni premuto ⌥ destro per parlare">

Tieni premuto ⌥ destro e parla; quando rilasci, il testo viene inserito. Viene riconosciuto nella lingua in cui stai scrivendo (inglese, cinese, francese, coreano o hindi). Se prima digiti un comando (ad es. `@improve `, `@question `) e poi parli, il testo va dopo il comando e ⏎ lo esegue; puoi anche premere ⏎ senza rilasciare ⌥ destro per eseguirlo appena finisci. Il parlato viene riconosciuto sul Mac dal riconoscimento vocale integrato di macOS (SpeechAnalyzer), e nessun audio viene caricato; serve macOS 26 o successivo.

La prima volta:

- macOS chiede se AllInOneIME può usare il microfono. Puoi anche fare clic in anticipo su "Allow Microphone" (consenti microfono) nelle impostazioni.
- Se questo Mac non ha ancora il modello vocale per quella lingua, viene scaricato una volta, automaticamente. Puoi anche scaricarlo nelle impostazioni.

La registrazione inizia solo dopo aver tenuto premuto il tasto per circa 0,2 s, quindi un tocco breve su ⌥ destro non accende il microfono (con il tasto azione impostato su "Tap ⌥", un tocco breve esegue l'azione). Se premi un altro tasto mentre lo tieni premuto (una scorciatoia con ⌥, ⌥←), conta come scorciatoia e anche in questo caso non viene registrato nulla. Premere qualsiasi altro tasto durante la registrazione la annulla.

## Installazione

Per usarlo serve macOS 14 o successivo, per l'input vocale macOS 26 o successivo. Il programma di installazione è universale: funziona sui Mac con Apple silicon e Intel. Finora è stato testato solo su macOS 27 con Apple silicon (la build per Intel solo tramite il suo autotest sotto Rosetta).

1. Scarica `AllInOneIME-<version>.dmg` dalle [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) (solo da lì) e aprilo.
2. Fai doppio clic su "Install AllInOneIME" al suo interno e fai clic su Install. Il metodo di inserimento va in `~/Library/Input Methods` e "AllInOneIME Settings" in `~/Applications`. Solo per questo utente; non serve la password di amministratore.
3. Il programma di installazione non è ancora autenticato (notarized) da Apple, quindi macOS non può verificare chi l'ha creato, e la prima volta dice di non poter verificare "Install AllInOneIME": fai clic su Fine (Annulla su macOS 14), apri Impostazioni di Sistema → Privacy e sicurezza, fai clic su Apri comunque in basso e conferma. Il programma di installazione di ogni nuova versione richiede questo passaggio una volta.

Dopodiché AllInOneIME è attivato e compare tra le tue sorgenti di input; passa a esso con Ctrl+Spazio (il tasto 🌐 cambia sorgente solo se "Premi il tasto 🌐 per" è impostato su "Cambiare sorgente di input" in Impostazioni di Sistema → Tastiera). Se il programma di installazione ti dice di aggiungerlo a mano, questo Mac non permette ai programmi di attivarlo, quindi aggiungilo tu una volta: Impostazioni di Sistema → Tastiera → Input di testo → Sorgenti di input → Modifica… → + (in basso a sinistra) → Inglese → AllInOneIME (scrive anche in pinyin una volta aggiunto il cinese in Input nelle sue impostazioni).

Se Ctrl+Spazio non ti porta ad AllInOneIME, o torna a U.S. dopo un po', esegui di nuovo il programma di installazione: aggiunge di nuovo AllInOneIME alle tue sorgenti di input.

Per aggiornare, installa di nuovo dall'immagine disco della nuova versione, senza disinstallare prima; impostazioni, elenco del gergo e parole apprese vengono conservati. Prima di aggiornare, leggi il [registro delle modifiche](../../CHANGELOG.md): contiene le modifiche di ogni versione e le note per l'aggiornamento.

Se avevi installato AIPinyin (il nome precedente di AllInOneIME), installa e basta: la vecchia AIPinyin.app e il suo launcher delle impostazioni vengono rimossi, e la voce tra le tue sorgenti di input prende il nuovo nome, senza bisogno di aggiungerla di nuovo. Impostazioni, elenco del gergo e parole apprese vengono spostati nelle nuove cartelle (`~/.config/allinoneime` e altre) al primo avvio, e ogni vecchia cartella resta come collegamento a quella nuova.

Per disinstallare, apri "Install AllInOneIME" e fai clic su Uninstall…. Impostazioni e parole apprese vengono conservate.

### Compilare dai sorgenti

Per compilare serve Xcode 26 o successivo, poiché l'input vocale usa l'SDK di macOS 26.

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` scarica librime e i dizionari di rime-ice e li verifica, compila e installa negli stessi percorsi, aggiungendolo alle tue sorgenti di input allo stesso modo. L'app che installa non ha dizionari cinesi (costituiscono il pacchetto lingua cinese): un'installazione che li aveva li conserva come pacchetto; altrimenti `make install-pack` installa il pacchetto dai dizionari del checkout, senza download. `make status` mostra la versione installata (`version:`) e se è tra le tue sorgenti di input (`listed:`). Per disinstallare: `make uninstall`.

## Configurare l'IA

Traduzioni e riformulazioni usano il tuo fornitore di IA, e i costi vanno sul tuo account: Amazon Bedrock nel tuo account AWS per impostazione predefinita, oppure l'API di Claude, Gemini o un servizio compatibile con OpenAI (vedi "Altri fornitori di IA" più sotto).

### Amazon Bedrock

1. Attiva Bedrock nella console AWS e assicurati di poter usare il modello scelto. Quello predefinito è Claude Haiku 4.5; la prima volta che usi un modello Anthropic, compili una volta un modulo sul caso d'uso.
2. Crea una chiave di accesso con il permesso `bedrock:InvokeModelWithResponseStream` e mettila in un profilo in `~/.aws/credentials`. Per ora sono supportate solo queste chiavi statiche, non SSO né assume-role.
3. Apri "AllInOneIME Settings": lo trovi in Spotlight o in Applicazioni, oppure aprilo dall'icona del metodo di inserimento nella barra dei menu → Settings…. Scegli profilo, regione e modello, e fai clic su "Test Connection" (verifica connessione). "Language" (lingua), in cima alla finestra delle impostazioni, può essere English o Chinese; per impostazione predefinita ("System") segue il sistema (cinese se il cinese viene prima dell'inglese nelle lingue preferite del sistema, altrimenti inglese). La finestra delle impostazioni, i suggerimenti nel pannello dei candidati e il menu di input lo seguono tutti.

<img src="../en/settings.png" width="420" alt="La finestra delle impostazioni">

### Altri fornitori di IA: API di Claude, Gemini, servizi compatibili con OpenAI

Non ti serve AWS: scegline uno in "AI Provider" (fornitore di IA) nelle impostazioni, incolla una chiave API, fai clic su "Save" (salva), poi su "Test Connection".

| Fornitore | Modello predefinito | Chiave API |
|---|---|---|
| API di Claude | `claude-haiku-5-5` (il più veloce ed economico; Sonnet 5.5 e Opus 5.5 sono più accurati ma più lenti e costosi) | [Claude Console](https://platform.claude.com) |
| API di Gemini | `gemini-3.8-flash` | Google AI Studio |
| Compatibile con OpenAI | `gpt-6-luna` di OpenAI (o `gpt-5.4-mini`); "Common Services…" (servizi comuni) include DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter e Ollama su questo Mac: sceglierne uno compila il suo URL di base, poi inserisci il suo modello | La chiave del servizio; imposta la Base URL sul suo indirizzo, ad es. `https://api.deepseek.com/v1`, o `http://localhost:11434/v1` per Ollama su questo Mac |

- Le chiavi API sono conservate nel portachiavi di sistema, mai nel file di configurazione. Se lì non ce n'è una, vengono usate `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (o `GOOGLE_API_KEY`) e `OPENAI_API_KEY` della tua shell.
- "Thinking" (ragionamento) è basso per impostazione predefinita: il metodo di inserimento attende a ogni frase, e meno ragionamento è più veloce. Scegli "Not set" (non impostato) per i modelli che non lo supportano.
- Con Claude Opus 5.5 o Sonnet 5.5 selezionato, le richieste includono il fallback in caso di rifiuto dell'API di Claude (`fallbacks: "default"`): quando un classificatore di sicurezza rifiuta, il server riprova con un altro modello.
- Nel file di configurazione: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), e `model`, `baseURL`, `effort` e `temperature` sotto `anthropic`, `gemini` e `openai` (quelli non impostati usano i valori predefiniti).

Tutte le impostazioni sono memorizzate in `~/.config/allinoneime/config.json`; dopo una modifica, la traduzione successiva usa le nuove impostazioni, senza riavvio. Le chiavi più recenti:

| Chiave | Cosa fa | Predefinito |
|---|---|---|
| `inputLanguages` | Lingue di inserimento, da una a cinque, la prima è quella predefinita: `"en"` inglese, `"zh"` cinese (pinyin), `"fr"` francese, `"ko"` coreano, `"hi"` hindi, ad es. `["en", "zh"]`, `["fr", "en", "ko"]`. Cinese, coreano e hindi funzionano una volta installato il loro pacchetto | `["en"]` (nuova installazione) |
| `keyboardLayouts` | Il layout di tastiera con cui si digita una lingua di inserimento, in base al suo codice (per ora solo il francese): `{"fr": "com.apple.keylayout.French-PC"}` | Francese: `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | Le lingue in cui traduce `@translate`, in ordine: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | `@improve` traduce anche (come `@translate @improve`) | `false` |
| `voiceInput` | Tenere premuto ⌥ destro per parlare | `true` |
| `actionKey` | Tasto azione: `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Spazio), `"space"` (Spazio) | `"enter"` |
| `uiLanguage` | Lingua dell'interfaccia (finestra delle impostazioni, suggerimenti del pannello dei candidati, menu): `"zh"`, `"en"` | `null` (segue il sistema) |
| `rewriteStyles` | Stili di riformulazione: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, ad es. `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | Il tuo file con l'elenco del gergo | `null` (cioè `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | L'icona nella barra dei menu e il suo pannello a discesa | `true` |
| `fuzzyPinyin` | Coppie di pinyin approssimativo: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |

## Privacy

- La digitazione (inglese e pinyin) e i calcoli di `@calculate` sono interamente locali. Solo quando premi il tasto azione su `@improve`, `@translate` o `@question` quella frase viene inviata al fornitore di IA che hai scelto (il tuo Bedrock, o il servizio di cui hai aggiunto la chiave). Con "Jargon" selezionato e un elenco del gergo impostato, l'elenco viene inviato insieme alla frase.
- Con AllInOneIME Cloud, la frase passa attraverso il server dello sviluppatore verso un fornitore di modelli (attualmente tramite OpenRouter): il server conserva solo dei conteggi, mai il testo. L'accesso conserva solo il tuo indirizzo email.
- La voce viene registrata solo mentre tieni premuto ⌥ destro e viene riconosciuta sul Mac; il testo riconosciuto viene inviato solo nei comandi sopra indicati, quando premi il tasto azione.
- Il metodo di inserimento legge il testo degli appunti una volta, solo quando premi ⌃V o ⌘V in un comando; i contenuti che i gestori di password contrassegnano come nascosti non vengono letti. Il testo viene prima mostrato nel comando e, di nuovo, viene inviato solo quando premi il tasto azione. Le versioni recenti di macOS chiedono se AllInOneIME può leggere gli appunti: consentilo. Per non sentirti chiedere ogni volta, imposta il permesso di incollare di AllInOneIME su consenti sempre in Impostazioni di Sistema → Privacy e sicurezza.
- Nei campi password macOS passa alla propria tastiera (U.S. o ABC) e torna indietro quando li lasci. Ogni volta che l'app in cui scrivi attiva l'inserimento sicuro, AllInOneIME non compone testo e non può registrare: i tasti entrano così come digitati. E mentre il sistema è in inserimento sicuro (campi password, Inserimento sicuro da tastiera di Terminale, ecc.), nulla viene inviato all'IA.
- `@note` e `@reminder` non passano dall'IA: AllInOneIME consegna il testo solo a Note e Promemoria su questo Mac, e interpreta anche l'ora del promemoria sul Mac (se quelle app lo sincronizzano con gli altri tuoi dispositivi dipende dai loro account, come iCloud). Quindi funzionano anche durante l'inserimento sicuro.
- `@open` cerca solo su questo Mac. Ricorda ciò che hai aperto con esso (gli ultimi 200 elementi), nelle preferenze proprie del metodo di inserimento (non in config.json), per elencarli per primi.
- Per elencare le tue note, il pannello della barra dei menu conserva l'identificativo e la prima riga (fino a 80 caratteri) delle ultime 30 note salvate con `@note`, nelle preferenze proprie del metodo di inserimento, anche quando il pannello è disattivato.
- `@py` e `@js` vengono eseguiti solo quando premi il tasto azione, e solo con codice che hai digitato o incollato tu: le risposte dell'IA e l'output di altri comandi non vengono mai eseguiti come codice. `@py` usa il `python3` del tuo Mac, che può leggere e scrivere file e andare online come fa in Terminale; `@js` viene eseguito in un processo separato che non può leggere file, accedere alla rete né eseguire altri programmi. Nessuno dei due viene eseguito durante l'inserimento sicuro.
- I log non registrano ciò che digiti. Per ogni metodo di inserimento di terze parti, macOS avverte che lo sviluppatore può accedere a tutto ciò che digiti con questa sorgente di input; è un avviso generico del sistema.

## Sviluppo

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

Struttura del codice:

- `Sources/AllInOneIMECore`: client Bedrock, SigV4, prompt, la macchina a stati di inserimento a due livelli (compresi i comandi @ e il gesto vocale); nessuna dipendenza da AppKit
- `Sources/AllInOneIMERime`: wrapper di librime
- `Sources/AllInOneIME`: il metodo di inserimento InputMethodKit, il pannello dei candidati, la finestra delle impostazioni, il riconoscimento vocale
- `Sources/AllInOneIMESettings`: il launcher "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: "Install AllInOneIME" sull'immagine disco: installa, aggiorna e disinstalla

I pacchetti lingua hanno una propria libreria, separata da quella dei plugin: il repository [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), servito su https://languages.allinoneime.com/, firmato con una propria chiave. `make pack` crea l'archivio; viene pubblicato lì come asset di release (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), e `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` scrive lì `packs.json` e lo firma in `packs.json.sig` con la chiave dei pacchetti lingua presa dal portachiavi (`allinoneime-languages-signing`). L'app legge https://languages.allinoneime.com/packs.json, verifica la firma, poi dimensione e SHA-256 dell'archivio. Per provare un pacchetto da un server locale: `--test-key` firma con una chiave di prova, e `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Il bundle ID è ancora `com.aipinyin.inputmethod.AIPinyin`: macOS lo usa per ricordare la sorgente di input aggiunta e il permesso del microfono, quindi cambiarlo significherebbe aggiungere di nuovo il metodo di inserimento e concedere di nuovo il permesso.

## Licenza

Copyright © 2026 MicroZ LLC. Sorgente disponibile secondo la [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): usalo, leggilo, modificalo e condividilo per qualsiasi scopo tranne un prodotto concorrente. Ogni versione passa ad Apache-2.0 due anni dopo il suo rilascio. Le versioni fino alla 0.6.1 sono state rilasciate sotto GPL-3.0 e restano disponibili con quella licenza.

I componenti di terze parti (librime e i suoi plugin sotto BSD-3-Clause; gli script Lua di rime-ice e il pacchetto lingua cinese sotto GPL-3.0) sono elencati in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
