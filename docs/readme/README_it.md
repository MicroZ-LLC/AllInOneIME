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
[![Notarizzato da Apple](https://img.shields.io/badge/Apple-notarized-0a84ff?logo=apple&logoColor=white)](#installazione)
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
> Dalla 0.6.3 AllInOneIME è firmato con un Developer ID e autenticato (notarized) da Apple: non serve più consentirlo in System Settings → Privacy & Security (Impostazioni di Sistema → Privacy e sicurezza). Dopo l'aggiornamento da una versione precedente, macOS chiede una volta la password di login per ogni chiave che AllInOneIME ha salvato nel portachiavi: inseriscila e fai clic su "Always Allow" (Consenti sempre). Scarica AllInOneIME solo dalle [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) o da [allinoneime.com](https://allinoneime.com).

Un metodo di inserimento per macOS con comandi IA in ogni campo di testo. Inizia una frase con `@` e premi ⏎ quando hai finito: `@improve` rifinisce ciò che hai scritto e propone alcune riformulazioni, `@translate` lo traduce nelle lingue che scegli, `@question` fa una domanda, `@agent` lo passa a un agente di programmazione (Claude Code, Gemini CLI, Kiro CLI …), e `@open` trova file e app o apre un indirizzo web. Puoi anche tenere premuto il tasto ⌥ destro e parlare. Senza `@`, i tasti vanno all'app come al solito. Scrive anche in cinese (pinyin, basato su Rime e rime-ice), francese, coreano (hangul) e hindi (devanagari a partire da lettere latine), ed esegue i tuoi script come comandi @.

![@improve e una frase grezza, poi ⏎: versioni rifinite, più riformulazioni](../en/improve.png)

Per maggiori dettagli (ogni comando e impostazione, risoluzione dei problemi di installazione, privacy), consulta la [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Realizzato da [Weijian Zhang](https://weijianz.com) presso MicroZ LLC.

## Come si usa

Senza `@`, non si mette in mezzo: in inglese le lettere vengono digitate direttamente e ⏎ è Invio; niente va online. Una nuova installazione scrive in inglese; per scrivere anche in cinese (pinyin), francese, coreano o hindi, aggiungilo nelle impostazioni (vedi [Inserimento e traduzione](#inserimento-e-traduzione)).

| Tasto | Cosa fa |
|---|---|
| Digitare pinyin, Spazio / cifre | In modalità cinese: scegliere le parole, come in qualsiasi metodo di inserimento pinyin |
| `@` (all'inizio di una frase) | Apre l'elenco dei comandi: prima i più usati di recente, 5 alla volta, scorrevole con ↑↓, la rotella o il trackpad; oppure digita delle lettere per trovarne uno (prima un nome digitato per intero, poi i nomi che iniziano con quelle lettere, poi quelli che le contengono). ⏎, Tab, Spazio o una cifra lo sceglie |
| ⏎ | Esegue il comando. Funziona anche se il pinyin non è ancora stato scelto: viene scelto prima, come con Spazio |
| Spazio, ⏎ / cifre | Quando compaiono i risultati: inserisce quello evidenziato / numerato; 0 è l'originale. ⏎ inserisce anche con un seguito digitato a metà (che viene scartato) |
| ⇧⏎ | Con un seguito digitato dopo i risultati dell'IA: lo invia (la domanda successiva di una conversazione di `@question`, o un perfezionamento). Mentre si digita un comando, o sui risultati dell'IA senza nulla digitato: inserisce ciò che hai digitato così com'è, `@command` compreso. Su altri risultati (`@open`, un promemoria …) inserisce la riga evidenziata, come ⏎ |
| ⌘C | Copia il risultato evidenziato (per `@open`, il percorso); il pannello dei candidati resta aperto |
| ⌃V | In un comando (ad es. dopo `@improve `): aggiunge il testo degli appunti dopo ciò che hai digitato invece di incollarlo nell'app. Più righe diventano una sola, fino a 2000 caratteri alla volta (`@note` mantiene gli a capo e ne accetta fino a 20000). Funziona in qualsiasi app; senza un comando, il tasto va all'app come al solito |
| ⌘V | Come ⌃V, ma alcune app gestiscono ⌘V da sé (terminali come Ghostty, iTerm2 e Terminale, e Note) e incollano nell'app come al solito; lì usa ⌃V |
| Esc, ⌫ | Torna alla frase per continuare a modificarla; digitare punteggiatura o cifre dopo i risultati la prosegue. Dopo un perfezionamento: torna ai risultati di prima |
| Lettere, quando ci sono i risultati dell'IA | Un seguito: dopo `@question` la domanda successiva (vedi [Conversazioni](#conversazioni-con-question-novità)), dopo `@improve` o un comando di istruzione un'istruzione come `shorter` (vedi [Perfezionare i risultati](#perfezionare-i-risultati-novità)); ⇧⏎ lo invia. Dopo `@translate` le lettere proseguono la frase, e ⏎ la traduce di nuovo |
| ⌘⏎, ⌘1–⌘9 | In una conversazione di `@question`: mostra dove proseguirla (gli agenti di programmazione installati, per primo quello a cui `@agent` passa i compiti; Claude, ChatGPT, Gemini; o copiarla); ⌘1, ⌘2 … ne scelgono uno |
| Clic su una riga | Nel pannello dei candidati: la sceglie, come farebbe la sua cifra (una parola, un comando dell'elenco, un risultato, un file di `@open`, un destinatario, la riga di un'estensione); la riga sotto il puntatore è evidenziata. Il campo di testo mantiene il focus |
| Tocco breve su Maiuscole | Con più lingue di inserimento: la successiva, nel loro ordine (inglese → cinese → francese → …, poi di nuovo la prima) |
| Tenere premuto ⌥ destro | Parla, rilascia per fermarti. Nella lingua in cui stai scrivendo (inglese, cinese, francese, coreano o hindi). In un comando, il testo va dopo di esso; altrimenti viene inserito direttamente |

## Comandi @ (beta)

| Comando | Cosa fa |
|---|---|
| `@improve` | Rifinitura: 1–3 sono tre versioni nella lingua della frase stessa, da 4 in poi gli stili di riformulazione (aggiunti e ordinati nelle impostazioni), 0 è l'originale. Nessuna traduzione; con "@improve also translates" (@improve traduce anche) attivo, funziona come `@translate @improve` |
| `@translate` | Traduce nelle lingue che hai aggiunto (impostazioni → Translate, trascina per riordinare), una riga ciascuna, tre versioni se ce n'è una sola; la lingua della frase stessa viene saltata. `@translate @improve` insieme traducono e riformulano in un'unica richiesta |
| `@question` | Fa una domanda; la risposta compare tra i candidati, ⏎ o Spazio la inserisce, ⌘C la copia. Continua a digitare e ⇧⏎ fa una domanda di seguito: il pannello diventa una conversazione di al massimo 5 turni, poi propone di proseguirla in Claude o in un'altra IA. Senza nulla digitato dopo, elenca le tue ultime 5 domande, dalla più recente; digitando le filtri (parole in qualsiasi punto della domanda, senza distinzione tra maiuscole e minuscole, anche in cinese). Una cifra, ↑↓ e poi ⏎, oppure un clic mostra subito la risposta salvata di una domanda, offline, da inserire o copiare come al solito; lì ⌘R la ripropone per avere una risposta nuova. Senza corrispondenze, o se non scegli nulla, ⏎ chiede ciò che hai digitato |
| `@reply` | Scrive tre risposte al messaggio a cui stai rispondendo, nella lingua dell'interlocutore e con il tono dell'app (il primo stile di riformulazione dell'app in Settings → Apps, altrimenti informale nelle app di chat e formale nella posta, dove ogni risposta è il corpo completo di un'email). Dagli il messaggio selezionandolo, copiandolo e premendo ⌃V nella bozza, oppure facendo uno screenshot (⌃⇧⌘4, o quello di WeChat) e premendo ⌃V; ciò che digiti dopo dice cosa rispondere: `@reply politely decline`. ⌘R ne scrive altre tre; vedi [Rispondere](#rispondere-con-reply-novità) |
| `@agent` | Passa il compito a un agente di programmazione sul tuo Mac, scelto in Settings → Agent: Claude Code (predefinito), Gemini CLI, Kiro CLI o un comando tuo (ciò che hai digitato viene aggiunto come ultimo argomento). La pagina mostra anche se ciascuno è installato e come si avvia. Claude Code viene eseguito in background per impostazione predefinita, con una notifica quando ha finito (fai clic per aprire la sessione in Terminale e continuare), oppure guarda `@tasks`; disattiva lì, sotto Claude Code, "Runs in the background and notifies me" (viene eseguito in background e mi avvisa) per aprirlo in Terminale. Gli altri agenti si aprono in Terminale con ciò che hai digitato come primo messaggio. Ognuno usa il proprio accesso e le proprie impostazioni. In Google Chrome porta con sé la pagina: indirizzo e titolo, il campo in cui hai digitato con il suo modulo o la sua sezione (★ indica dove ti trovi), il testo selezionato e ciò che è visibile nella finestra (mai un campo password, mai l'intera pagina), così `@agent why doesn't this work` nel campo del nome utente di un modulo di accesso riguarda quel campo, e `@agent why is this blocked` sulla pagina di una pipeline riguarda quella pagina; è l'agente a capire quale dei due. Il testo della pagina arriva all'agente così come è stato letto, indicato come proveniente dal web (non come istruzioni tue). Serve l'Accessibilità; Chrome costruisce per lui l'albero della pagina solo mentre lì si scrive `@agent`, e poi lo spegne di nuovo (Settings → Agent → "@agent and @reply take the Chrome page along" (@agent e @reply portano con sé la pagina di Chrome) disattiva tutto questo). La prima volta che apre Terminale, macOS chiede se AllInOneIME può controllare Terminale: fai clic su OK. (Prima della 0.6.4 si chiamava `@claude`.) |
| `@tasks` | Elenca le attività di Claude in background (in corso / completata / ti aspetta) con le loro ultime risposte; ⏎ ne apre una in Terminale, ⌘C copia la risposta |
| `@settings` | Apre subito la finestra delle impostazioni (basta sceglierlo) |
| `@open` | Elenca file, cartelle e app corrispondenti mentre scrivi (Spotlight). Funzionano più parole chiave separate da spazi: ognuna deve comparire nel percorso, almeno una nel nome (il nome di una cartella standard vale per il suo contenuto: `downloads pdf` trova i PDF in Downloads (Download)). Le app e le cartelle standard si trovano anche con il loro nome cinese, e un'interfaccia in cinese le mostra così. Ciò che hai aperto con `@open` viene per primo, poi le app e quelle cartelle, poi i file usati o modificati di recente; quando i nomi trovano due file o meno e nessuna app né alcuna di quelle cartelle, i file nella tua cartella Inizio vengono cercati anche per contenuto, con quelle righe contrassegnate da "content" (contenuto); quando non c'è nient'altro, ⏎ li elenca per farti scegliere invece di aprire il primo. Con un indirizzo web (`github.com`, `localhost:3000`, `https://…`), la prima riga è "open in the browser" (apri nel browser) e i contenuti non vengono cercati; un file con esattamente quel nome (per esempio `MANIFEST.in`) viene per primo. Un testo che inizia con `~/` o `/` è un percorso: Tab lo completa ed entra nelle cartelle; ⏎ apre, ⌘C copia il percorso |
| `@note` | Salva il testo nell'app Note, in una cartella chiamata AllInOneIME (creata se manca), oppure dove indica Settings → Plugins → Notes (@note): Notion, o una cartella di file Markdown (un vault di Obsidian o qualsiasi cartella); non viene inserito nulla. Il testo incollato mantiene gli a capo, fino a 20000 caratteri |
| `@reminder` | Aggiunge un promemoria all'app Promemoria, in un elenco chiamato AllInOneIME. Scrivi l'ora nel testo; viene interpretata sul Mac, e una riga mostra cosa è stato capito: ⏎ o Spazio lo aggiunge, Esc torna alla modifica. Con un'ora, ha un avviso a quell'ora; con solo una data, vale per tutto il giorno |
| `@py` | Esegue una riga di Python (il `python3` del Mac) e inserisce il risultato: il valore dell'ultima espressione del codice, ad es. `@py 2**100`, `@py import math; math.sqrt(2)`, oppure ciò che ha stampato. Non è proposto senza `python3` (gli strumenti da riga di comando di Xcode lo includono) |
| `@js` | Esegue una riga di JavaScript e inserisce lo stesso: il valore dell'ultima espressione o ciò che ha stampato `console.log`, ad es. `@js [1, 2, 3].map(x => x * 2)`. Usa JavaScriptCore, integrato in macOS, quindi non c'è nulla da installare; non può leggere file, accedere alla rete né eseguire altri programmi |
| `@reportissue` | Segnala un problema: apre nel browser la pagina di GitHub per una nuova issue, con quello che hai digitato dopo il comando come titolo e "What happened / What you expected" (cosa è successo / cosa ti aspettavi) da compilare. Aggiunge le versioni dell'app e di macOS, l'architettura del tuo Mac, le lingue dell'interfaccia e di inserimento, i pacchetti di lingua installati, il tipo di fornitore di IA (e il modello, se è pubblico; altrimenti "custom"), il tasto azione e quanti comandi personalizzati, plugin ed estensioni hai, mai i loro nomi, il tuo testo, percorsi o chiavi. ⏎ (o il tuo tasto azione) mostra prima tutto questo nel pannello dei candidati; ⏎ di nuovo, o un clic sulla riga, apre la pagina, dove lo rileggi e fai clic su Submit (con il tuo account GitHub); Esc torna indietro. Anche nel menu di inserimento ("Report an Issue…") e in Settings → About |
| `@imessage` | Invia un iMessage: digita un nome, un numero di telefono o un'email (un nome cinese anche col suo pinyin, completo o con le iniziali) e scegli il destinatario nel pannello dei candidati (prima quelli a cui hai scritto di recente; funziona anche un numero o un indirizzo completo), poi scrivi il messaggio (i comandi al suo interno come `@stock AAPL` vengono eseguiti prima). ⏎ mostra "Send to Alex (…): message" nel pannello, un altro ⏎ lo invia, Esc torna alla modifica; nel campo di testo non viene digitato nulla. La prima volta, macOS chiede se AllInOneIME può accedere a Contatti e controllare Messaggi: fai clic su OK per entrambi |

Esempio: `@q` ⏎, digita `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ salva una nota. `@reminder call Bob tomorrow at 3pm` ⏎, controlla l'ora interpretata, poi di nuovo ⏎ per aggiungerlo. Una volta scelto il comando, puoi anche tenere premuto ⌥ destro e parlare. In modalità cinese, `@open` passa momentaneamente alle lettere latine e torna al cinese quando hai finito.

Il codice per `@py` e `@js` si digita in lettere latine, e la punteggiatura a larghezza piena (dalla modalità cinese) diventa ASCII; scrivilo su una sola riga, con `;` tra le istruzioni. Viene eseguito in un processo separato, interrotto dopo 10 secondi o in qualsiasi momento con Esc; in caso di errore, viene mostrata la prima riga dell'errore, ad es. `ZeroDivisionError: division by zero`. Un output su più righe viene inserito così come è stato stampato; in un terminale va su una sola riga (un terminale esegue ogni riga che riceve). Un terminale all'interno di un editor (VS Code, Cursor, JetBrains) non si distingue dall'editor stesso, quindi lì l'output su più righe di qualsiasi comando viene inserito così com'è. Entrambi funzionano anche all'interno della frase di un altro comando: `@reply the answer is @py 2**100`; metti tra virgolette il codice con spazi: `@question explain @py "sum(x * x for x in range(10))"`. Non vale il contrario: il codice di `@py` e `@js` viene sempre eseguito esattamente come l'hai digitato, e gli `@commands` al suo interno non vengono eseguiti prima.

![Digitare @ apre l'elenco dei comandi; @question più una domanda, poi ⏎ per la risposta](../en/commands.png)

![@open trova le app mentre scrivi; se inizia con /, è un percorso: la cartella viene elencata, Tab completa](../en/open.png)

Quando `@` non è seguito da un comando, come in `@john`, la `@` viene inserita come al solito, quindi le menzioni con @ nelle app di chat continuano a funzionare. Digitata subito dopo una lettera, una cifra, `.`, `_` o `-`, come in `bob@example.com` o `ssh user@host`, la `@` è solo testo: non si apre nessun elenco, in nessuna app, terminali compresi. Con l'elenco aperto, ← → o un tasto che non può far parte del nome di un comando (`.`, `:`, `/`) lo chiudono e lasciano ciò che hai digitato (`@`, `@im`) così com'è; in un terminale ← → in quel caso chiudono soltanto l'elenco. `@question`, `@improve`, `@translate` e `@reply` inviano al tuo Bedrock solo quando premi il tasto azione (uno screenshot viene letto su questo Mac e se ne invia solo il testo); `@open` cerca solo su questo Mac; `@note` e `@reminder` vanno solo a Note e Promemoria su questo Mac (`@note` invece a una cartella o a Notion, se ne hai scelto uno); `@agent` usa l'agente installato sul tuo Mac (per impostazione predefinita il comando `claude` di Claude Code) e il suo account, e ti chiede prima, come al solito, di modificare file o eseguire comandi. Senza l'agente installato, `@agent` non è proposto. `@imessage` legge solo i Contatti di questo Mac (nomi, numeri di telefono, email), non passa mai per l'IA, ed è Messaggi a inviare il messaggio; senza l'app Messaggi non è proposto.

### Sul testo selezionato (novità)

Seleziona del testo in qualsiasi app (una frase in Note, un paragrafo in Mail), digita `@improve`, `@translate`, `@question` o un altro comando che prende testo e premi ⏎: il comando lavora sulla selezione, e il risultato che scegli la sostituisce. La selezione resta com'è, selezionata, mentre digiti: il comando viene scritto nel pannello dei candidati, la cui prima riga è ciò che digiti e la successiva "On the selection: “…” (N characters)" (sulla selezione: N caratteri). Esc, ⇧⏎ o un clic altrove lasciano il testo com'era; lo stesso vale se nel frattempo cambi la selezione, cosa che annulla il comando. Il testo digitato dopo il comando è un'istruzione per `@improve` e `@translate` (`@translate ja`, `@improve more formal`) e la domanda per `@question` (`@question what does this mean`), riferite alla selezione. `@open`, `@agent`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, i comandi da terminale e le estensioni script non la usano: prendono ciò che digiti, e la selezione resta com'è. Fino a 5000 caratteri; mai letta durante l'inserimento sicuro o in un terminale. Disattivala in Settings → General → "Use the selected text" (usa il testo selezionato) se in un'app non funziona bene.

### Rispondere con @reply (novità)

`@reply` scrive tre risposte che potresti inviare al messaggio a cui stai rispondendo. Dagli il messaggio in uno di questi modi, poi premi ⏎:

- **Selezionalo** nel campo, poi digita `@reply` (la risposta che scegli va dopo di esso, su una riga a sé).
- **Copialo**, digita `@reply` e premi ⌃V: il pannello mostra "Copied message · N characters" (messaggio copiato · N caratteri), e la bozza resta com'è.
- **Fai uno screenshot** negli appunti (⌃⇧⌘4, o lo screenshot di WeChat), digita `@reply` e premi ⌃V: il pannello mostra "Screenshot · N lines (read on this Mac)" (screenshot · N righe, letto su questo Mac). Lo screenshot viene letto su questo Mac (con Vision di Apple; la prima volta un po' più lentamente) e se ne invia solo il testo; l'immagine non va da nessuna parte e non viene conservata. Le righe a sinistra sono dell'interlocutore e quelle a destra tue, come le mostrano le app di chat; gli orari tra i messaggi vengono tralasciati. Usalo per WeChat, la cui finestra non si può leggere in nessun altro modo.

Digita dopo il comando cosa vuoi dire (`@reply politely decline`, `@reply 委婉拒绝`), o niente per una risposta sensata. Le risposte sono nella lingua dell'interlocutore, a meno che tu non ne chieda un'altra, e con il tono dell'app: il primo stile di riformulazione del suo profilo (Settings → Apps), altrimenti informale nelle app di chat e formale nelle app di posta, dove ogni risposta è il corpo completo di un'email. Viene inviato anche il testo attorno al cursore. ⌫ senza nulla digitato dopo `@reply` toglie ciò che era stato incollato. ⏎ o una cifra inserisce una risposta; ⌘R ne scrive altre tre (Esc riporta le precedenti), e digitare un'istruzione le perfeziona come per qualsiasi risultato dell'IA. In Google Chrome, se non hai selezionato né incollato nulla, porta con sé la pagina come `@agent` (Settings → Agent → "@agent and @reply take the Chrome page along"). Senza nulla a cui rispondere e senza nulla digitato, dice cosa gli serve. Nascondere le informazioni sensibili copre anche il testo dello screenshot; durante l'inserimento sicuro gli appunti non vengono letti e non viene inviato nulla. Un comando personalizzato che avevi chiamato `reply` ora è `@myreply`.

Uno screenshot incollato in qualsiasi altro comando funziona allo stesso modo: `@translate` ⌃V lo traduce (nel punto del cursore), `@question what does this say` ⌃V fa una domanda su di esso, e i comandi senza IA ricevono il suo testo come se fosse stato copiato (`@note` ne mantiene le righe). Con del testo selezionato, `@improve` e `@translate` continuano a lavorare sulla selezione, e un avviso dice che lo screenshot non è stato usato.

### Perfezionare i risultati (novità)

Mentre sono visibili i risultati di `@improve`, di un comando di istruzione (tuo o di un plugin) o della riscrittura di una selezione, digita cosa cambiare, come `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese` o `用更口语的说法` (il pinyin funziona, e un tocco di Maiuscole cambia lingua), e premi ⇧⏎: i risultati tornano all'IA con la tua istruzione, e quelli nuovi li sostituiscono nello stesso pannello. ⏎ inserisce il risultato selezionato, anche con un'istruzione digitata a metà (che viene scartata). Perfeziona tutte le volte che vuoi; la riga in alto del pannello elenca i passaggi ("Refined: shorter · more formal"), e puoi scegliere una riga in qualsiasi momento come al solito. Una lettera avvia l'istruzione (mostrata come "refine › …" in cima al pannello); finché è vuota, cifre, Spazio e ⏎ scelgono come prima, e ⇧⏎ inserisce ciò che hai digitato così com'è. Il perfezionamento inizia quando i risultati sono completi: digitare mentre arrivano ancora i primi risultati prosegue la frase, come prima. Mentre un perfezionamento è in corso puoi già digitare l'istruzione successiva; il perfezionamento continua, e ⇧⏎ avvia il successivo appena arrivano i suoi risultati. Esc cancella l'istruzione, poi torna indietro di un passo ai risultati prima dell'ultimo perfezionamento (durante un perfezionamento: lo ferma), poi alla frase; ⌫ su una riga vuota torna indietro allo stesso modo. Sul testo selezionato, il risultato scelto sostituisce comunque esattamente la selezione, che resta intatta fino ad allora. Un perfezionamento che non riesce (o che viene rifiutato durante l'inserimento sicuro) lascia i risultati com'erano, con la sua istruzione pronta per riprovare con ⇧⏎. Lo stesso perfezionamento degli stessi risultati viene servito dalla cache. `@translate` non ha perfezionamento: digitare dopo i suoi risultati prosegue la frase, e ⏎ la traduce di nuovo.

### Conversazioni con @question (novità)

Dopo che `@question` ha risposto, ciò che digiti è la domanda successiva: ⇧⏎ la pone, insieme alle domande e risposte precedenti, e il pannello diventa la conversazione, con i turni precedenti attenuati come righe Q / A e l'ultima risposta sotto. La riga in alto indica quale turno viene dopo ("question 2/5 › …"). Ogni risposta si può inserire: con la sua cifra (1–5), con ↑↓ e poi ⏎, o con un clic; l'ultima è selezionata, e ⌘C copia quella selezionata. ⏎ la inserisce anche con una domanda digitata a metà (che viene scartata). Esc cancella ciò che hai digitato, poi torna indietro di un turno; al primo, esce come prima. Il pannello cresce fino a circa metà dello schermo, poi scorre, con l'ultimo in fondo.

Dopo 5 turni (`questionRounds` nella configurazione, 2–10) la riga della domanda successiva diventa "5 rounds in: continue in Claude or another AI" (5 turni: prosegui in Claude o in un'altra IA), con le scelte numerate ⌘1, ⌘2 …; ⌘⏎ le mostra a qualsiasi turno (mentre una risposta sta ancora arrivando non fa nulla, e non raggiunge mai l'app). Ciò che digiti a quel punto è il primo messaggio lì; solo ⌘1, ⌘2 … lo inviano (⇧⏎ non chiede più nulla e non apre nulla). Una domanda sul testo selezionato porta con sé quel testo, citato in un blocco a parte. Le scelte:

- **Gli agenti di programmazione installati** su questo Mac, ciascuno con il suo nome: per primo quello a cui `@agent` passa i compiti (⌘1), poi gli altri (Claude Code, Gemini CLI, Kiro CLI, il tuo comando da Settings → Agent). Ognuno apre una sessione interattiva in Terminale, avviata come la avvia `@agent`, che inizia con la conversazione e "Let's continue this discussion". Uno che non è installato non viene mostrato.
- **Claude** o **ChatGPT** sul web, con la conversazione già compilata (una lunga va negli appunti: incollala).
- **Gemini** sul web, con la conversazione negli appunti da incollare.
- **Copy the conversation** (copia la conversazione), in Markdown (**Q:** / **A:**).

Quali, e in che ordine (il primo è quello predefinito): Settings → General → "Continue a conversation in" (prosegui una conversazione in; `questionContinueIn` nella configurazione); con più di 5, ⌘6 … ⌘9 scelgono gli altri. "@agent's agent" (l'agente di @agent) è lì l'agente scelto in Settings → Agent, con il suo nome; un agente che al momento non è installato mantiene il suo posto nell'elenco quando lo modifichi. Con Apple Intelligence su questo Mac una conversazione lunga non entra nel suo piccolo contesto: le risposte più vecchie vengono accorciate, poi i turni più vecchi lasciati fuori, e il pannello dice "earlier rounds shortened" (turni precedenti accorciati). Una conversazione viene salvata sotto la sua prima domanda tra le domande recenti, e sceglierla mostra i turni per proseguirla.

### Domande recenti (novità)

`@question` senza nulla digitato dopo elenca le tue ultime 5 domande, dalla più recente, con quando sono state fatte ("3 hours ago"). Digitando le filtri: ogni parola in qualsiasi punto della domanda, senza distinzione tra maiuscole e minuscole (anche il cinese senza spazi). Una cifra, ↑↓ e poi ⏎, oppure un clic mostra subito la risposta salvata di una domanda, senza andare online: Spazio o ⏎ la inserisce, ⌘C la copia, ⌘R la ripropone per una risposta nuova (per una conversazione: la sua ultima domanda), Esc torna all'elenco. Una conversazione salvata mostra tutti i suoi turni: digita per proseguirla. Senza corrispondenze, o se non scegli nulla, ⏎ chiede ciò che hai digitato. Una nuova risposta alla stessa domanda, o una conversazione che prosegue, sostituisce quella salvata.

- Vengono conservate solo su questo Mac (vedi Privacy): non durante l'inserimento sicuro, e mai per le domande sul testo selezionato.
- Settings → General → "Remember recent questions" (ricorda le domande recenti) disattiva la funzione (`rememberQuestions` nella configurazione); disattivata lì, le elimina anche. Disattivata da Settings → Assistant, vengono conservate, così che annullare rimetta esattamente com'era (la sua anteprima lo dice); "Clear (N)" (cancella) le elimina.

### Note e promemoria

`@note` crea una nuova nota; la sua prima riga è il titolo. Dopo aver copiato del testo, ⌃V dopo `@note ` (o ⌘V, fuori dai terminali) lo salva con i suoi a capo, mostrati come ↵ nel comando. Dove va lo decide Settings → Plugins → Notes (@note) → Save to (salva in):

- **Notes** (come prima): una nuova nota nella cartella AllInOneIME di Note.
- **Folder (Obsidian or any)** (una cartella, di Obsidian o qualsiasi): un nuovo file Markdown per ogni nota nella cartella che scegli, con il nome della sua prima riga (`/\:*?"<>|#^[]` diventano `-`; a un nome già usato si aggiunge " 2", " 3"). Il file contiene un front matter `created:`, poi tutto il testo così come digitato. Un file non viene mai sovrascritto, e una cartella che non c'è (un disco non montato, un vault spostato) non viene creata: la nota torna invece nel comando. In un vault di Obsidian (con una cartella `.obsidian` al suo interno o più in alto) l'avviso dice "Saved to Obsidian", e il pannello della barra dei menu apre la nota in Obsidian.
- **Notion**: Create Integration… (New integration → Internal → copia il token), incolla il token (conservato nel portachiavi), poi in Notion apri la pagina o il database → ··· → Connections → aggiungi la tua integrazione, e incollane il link; Test mostra "✓ “Inbox” (database)". Una pagina riceve una nuova pagina figlia, un database una nuova riga (con la prima riga della nota come titolo); il resto della nota ne è il corpo, in un'unica richiesta. Offline o in caso di rifiuto, nulla viene conservato per un invio successivo: la nota torna nel comando. Durante l'inserimento sicuro `@note` non invia a Notion.

L'avviso dice dove è finita la nota ("Saved to Notion", "Saved to “Inbox”"). Se lasci il campo di testo (fai clic altrove, cambi app) o premi ⇧⏎ (inserisci così come digitato) prima che una nota con a capo sia salvata, non viene digitata nell'app (in un terminale, ogni riga verrebbe eseguita come comando): va invece negli appunti ("The note wasn't saved; its text is on the clipboard"). Una nota di una sola riga viene inserita così come digitata.

`@reminder` capisce indicazioni di tempo come `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (il giorno 1), `end of the year` (anche indicazioni in cinese). Il giorno e l'ora possono essere separati (`tomorrow call Bob at 5`); le settimane iniziano di lunedì. Un'ora senza am o pm (`at 5`) è la prossima, mai tra mezzanotte e le 6 del mattino; un'ora già passata oggi è domani, ma una parte della giornata ancora in corso (`this afternoon`, `tonight`) è oggi, per tutto il giorno; una data già passata quest'anno è quella dell'anno prossimo. Se è scritto per ripetersi (`standup every Monday at 9`), viene aggiunto una volta, per la prossima occorrenza: le parole restano nel titolo e la riga indica "once only" (una sola volta). La riga di conferma mostra l'ora interpretata, ad es. "tomorrow 3:00 PM" (secondo l'impostazione 12/24 ore del Mac); se è sbagliata, Esc torna al testo. Se non contiene né ora né data, non ne ha ("no date").

`@stock` e simili all'interno di questi due non vengono eseguiti: il testo viene salvato così come è scritto (digitare `@` lì non apre l'elenco dei comandi). La prima volta, macOS chiede se AllInOneIME può controllare Note (`@note`) o accedere a Promemoria (`@reminder`): consentilo. Se non l'hai fatto, consenti AllInOneIME in Impostazioni di Sistema → Privacy e sicurezza → Automazione (Note) o → Promemoria. Quando un salvataggio non riesce (per mancanza di permessi, ad esempio), l'avviso ne indica il motivo e il testo torna nel comando, per correggerlo e inviarlo di nuovo; quando devi prima sistemare qualcosa (un permesso, un account), viene anche messo negli appunti (andare in Impostazioni di Sistema toglie il focus dal campo di testo). Se sei passato a un altro campo di testo o stai digitando altro, va invece negli appunti ("Not saved; the text is on the clipboard.").

### I tuoi comandi

Nelle impostazioni, in "Custom @ Commands" (comandi @ personalizzati), fai clic su "Add Command…" (aggiungi comando): dagli un nome e scegli cosa fa (un'istruzione per l'IA, un programma, un programma in Terminale, una pagina web o un testo da inserire), oppure parti da un esempio. I tuoi comandi vengono dopo quelli integrati; i nomi sono solo in lettere latine e non possono coincidere con quello di un comando integrato; funzionano dalla frase successiva. Sono conservati in `customCommands` nel file di configurazione (`~/.config/allinoneime/config.json`), che puoi anche modificare:

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

| `type` | Cosa fa |
|---|---|
| `prompt` | Va all'IA con `prompt` come istruzione; la risposta compare tra i candidati, da inserire o copiare (⌘C) |
| `run` | Esegue `argv` in background; ciò che stampa compare tra i candidati (più righe vengono inserite così come stampate, in un terminale su una sola riga). In caso di errore, viene mostrata la sua ultima riga |
| `terminal` | Esegue `argv` in una nuova finestra di Terminale; non viene inserito nulla |
| `link` | Inserisce il testo nell'indirizzo web `url` e lo apre nel browser predefinito; non viene inserito nulla |
| `snippet` | Inserisce subito `text`, con i suoi segnaposto compilati (vedi sotto); niente IA, nessun programma |

- `{input}` diventa ciò che hai scritto dopo il comando, e resta sempre all'interno dell'unico argomento in cui si trova: non è coinvolta alcuna shell. Se ti serve una shell, dichiaralo, come `sh` sopra (`zsh -c`).
- `stdin`: ciò che va all'input standard del programma, con `{input}` anch'esso sostituito.
- L'`url` di un `link` deve iniziare con `https://`, con `{input}` una sola volta, dopo il `?` o il `#`; il testo viene codificato (uno spazio diventa `%20`, un a capo `%0A`), al massimo 4000 caratteri.
- `run` e `terminal` digitano lettere latine per impostazione predefinita (come `@open`; in modalità cinese, il cinese torna dopo), e la punteggiatura a larghezza piena diventa ASCII. Imposta `"ascii": false` per mantenere il testo così come digitato.
- I programmi vengono eseguiti nella tua cartella Inizio con il PATH della tua shell di login (così vengono trovate le installazioni di Homebrew, pyenv e nvm). `run` interrompe un programma dopo 10 secondi (`timeoutSeconds`) o quando stampa troppo; Esc lo interrompe in qualsiasi momento.
- `summary` è la descrizione nell'elenco dei comandi (facoltativa).
- Quando il programma in `argv` non viene trovato (ad esempio, manca `python3`), il comando non è proposto e `@python …` viene inserito come testo; una volta installato il programma, il comando compare nel campo di testo successivo.

`run` e `terminal` eseguono codice sul tuo Mac: aggiungi solo comandi scritti da te e di cui ti fidi. Anch'essi vengono eseguiti solo quando premi il tasto azione, e mai durante l'inserimento sicuro.

#### Snippet: testo che inserisci spesso (novità)

Un comando `snippet` ("Insert text" nell'editor) inserisce un testo che hai salvato, come una firma, un indirizzo o il link di una riunione: `@sig` ⏎ lo inserisce subito (Tab o Spazio completano soltanto il nome). Il suo `text` può contenere segnaposto:

| Segnaposto | Diventa |
|---|---|
| `{input}` | tutto ciò che hai scritto dopo il nome: `@tag foo bar` con `#{input}` inserisce `#foo bar` |
| `{name?}` | un campo da compilare: i campi si riempiono, nell'ordine, con ciò che hai scritto, separato da virgole (`,` o `，`): `Dear {name?}, see you {day?}.` con `@meet Bob, Friday`. Se uno resta vuoto, un avviso lo nomina e non viene inserito nulla |
| `{clipboard}` | il testo degli appunti (macOS può chiedere prima) |
| `{selection}` | il testo selezionato quando hai digitato `@` (viene sostituito, come con qualsiasi comando sulla selezione) |
| `{date}`, `{time}` | la data di oggi come `2026-10-17`, l'ora come `14:05`; `{date:EEEE, MMM d}` con un [modello di data](https://unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table), nella lingua dell'interfaccia |
| `{cursor}` | dove va il cursore dopo l'inserimento (al massimo una volta; non in un terminale) |

- `{{` scrive `{`, e la `}}` che lo chiude scrive `}` (`{{input}}` inserisce `{input}`); ogni altra `}}` o `{…}` resta com'è, quindi JSON o codice in uno snippet vanno bene: `{"a":{"b":1}}` entra così come è scritto.
- Senza `{input}` e senza campi da compilare, ciò che scrivi dopo il nome va dopo lo snippet, preceduto da uno spazio.
- Scrivi `@sig` nel testo di un altro comando per includerlo: `@question summarize this @zoom` invia il link stesso. Lì funzionano solo gli snippet senza `{clipboard}`, `{selection}` né campi da compilare; con `{input}`, prende una parola o una frase tra virgolette: `@meet「Friday 3pm」`.
- Solo testo semplice (a capo mantenuti), al massimo 20000 caratteri. Gli snippet restano su questo Mac, quindi funzionano durante l'inserimento sicuro e nelle app impostate su No AI. Anche i bundle di estensioni possono includerne (`snippets` in `extension.json`, vedi [docs/extensions.md](../extensions.md)).

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

Le modalità di Raycast si traducono così: `fullOutput` → `show`, `compact` e `silent` → `silent`, `inline` con `refreshTime` → uno stato. L'intero protocollo è in [docs/extensions.md](../extensions.md); [Core/Examples/extensions](../../Core/Examples/extensions) ne contiene uno per ogni tipo. Le estensioni eseguono codice sul tuo Mac: usa solo quelle di cui ti fidi. Vengono eseguite solo quando le esegui tu (uno stato o un elenco mentre scrivi), mai durante l'inserimento sicuro, e si fermano quando il metodo di inserimento si chiude.

#### Sorgenti delle estensioni (novità)

Un bundle può provenire da un repository Git, tuo o del tuo team, e restare aggiornato da lì. Settings → Custom Commands → Extension Sources → **Add from Link…** (aggiungi da link): incolla l'indirizzo del repository (`git@github.com:you/my-extensions.git`, `ssh://…`, `https://…`; facoltativamente un branch, la cartella del bundle nel repository e un tag o un commit a cui fissarlo). AllInOneIME lo clona con **la tua configurazione di git e SSH** (chiavi, agent, ~/.ssh/config, credential helper), quindi un repository privato funziona come in Terminale; l'app non chiede né memorizza mai una password. Il clone va in `~/Library/Application Support/AllInOneIME/Sources/`: prima in una cartella di preparazione nascosta, mai direttamente in una cartella di estensioni. (Non mettere un nome, una password o un token in un indirizzo https: li conserva il credential helper di git.)

- **Prima la revisione.** Prima che venga caricato qualsiasi cosa vedi il bundle, ogni comando (nome, titolo, descrizione, output), i programmi che eseguono, le sue preferenze e il commit, sotto l'avviso "This source isn't signed: it will run programs from <address>" (questa sorgente non è firmata: eseguirà programmi da quell'indirizzo). Solo **Enable** (attiva) la aggiunge; Cancel (annulla) elimina il clone. Una sorgente si rivede una volta sola.
- **Gli aggiornamenti li applichi tu.** Una volta al giorno (e poco dopo l'avvio del metodo di inserimento) la sorgente viene recuperata (fetch) per vedere cosa c'è di nuovo: le impostazioni mostrano "N updates" (N aggiornamenti) con i commit (oggetto, autore, data) e un badge sulla pagina. Non cambia nulla finché non fai clic su **Update** (aggiorna), che fa solo un fast-forward e non esegue hook. Un push forzato fa sì che la sorgente vada rivista: **Re-clone** (clona di nuovo) la mostra, e solo Enable mette al suo posto la cronologia riscritta (fino ad allora la versione rivista continua a funzionare). Una sorgente fissata a un tag o a un commit non viene controllata. Il controllo giornaliero si disattiva sorgente per sorgente (`autoCheck`).
- **Gli errori** sono le parole di git stesso, con "This uses your own git and SSH setup; check that `git ls-remote <url>` works in Terminal" (qui si usa la tua configurazione di git e SSH; verifica che quel comando funzioni in Terminale), e sotto il tuo promemoria, se ne hai impostato uno (`authHint` nella configurazione).
- **Remove** (rimuovi) sposta il clone nel Cestino; le preferenze del bundle vengono conservate per la prossima volta.
- Da un terminale: `AllInOneIME --add-source <url> [--path …] [--branch …] [--pin …]` (stampa la revisione e attiva la sorgente; di nuovo dopo un push forzato), `--update-sources` (fa il fast-forward di ogni sorgente rivista non fissata), `--list-extensions` (su `~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME`).
- Si carica solo codice rivisto: una cartella di sorgente nell'elenco di caricamento che non è stata rivista su questo Mac (una configurazione copiata) resta esclusa. git non aspetta mai una risposta: niente terminale e niente richieste, quindi una chiave host sconosciuta o una richiesta di password fallisce subito.

La configurazione le conserva come `extensionSources`; la struttura del repository è in [docs/extensions.md](../extensions.md#10-extension-sources).

### Plugin

I plugin sono comandi `@` già pronti per cose che non servono a tutti, come `@stock AAPL 600519 700` per le quotazioni di borsa. Una volta installati, funzionano come qualsiasi comando; "Plugins" nelle impostazioni mostra cosa è installato e dove ciascuno invia il tuo testo, e permette di rimuoverli. I plugin sono JavaScript eseguito in un processo separato: possono raggiungere solo i siti web che dichiarano (HTTPS), e non possono leggere file né eseguire altri programmi. "Browse Library…" (sfoglia libreria) in Plugins nelle impostazioni li installa dalla [libreria dei plugin](https://github.com/MicroZ-LLC/AllInOneIME-plugins): prima di installare un plugin mostra quali siti web contatta; l'indice della libreria è firmato e ogni file deve corrispondervi. Una versione più recente mostra un pulsante "Update" (aggiorna); nulla si aggiorna da solo. I tuoi plugin vanno in `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): plugin locali, mai sovrascritti dalla libreria. I plugin di tipo "Link" non eseguono codice: inseriscono il testo in un indirizzo web e lo aprono nel browser, come `@x nice weather today`, che apre l'editor dei post di X con il testo già compilato; pubblicare dalla pagina spetta a te. La libreria ne ha quattro (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` converte le valute: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, su una riga con la data del tasso (tassi forniti da ExchangeRate-API). `@calculator` è una calcolatrice che funziona offline, `@calculator 23*17` → `391` (il `@calculate` integrato prima della 0.6.5), e `@calendar` lavora con le date: `@calendar +10` → "Tue, Oct 27 · in 10 days". Come scriverne uno: [docs/plugins.md](../plugins.md).

I comandi che recuperano qualcosa (plugin e programmi) funzionano anche all'interno di una frase: `@reply tell her @stock AAPL is up today`. Quelli interni vengono eseguiti per primi, il loro output prende il loro posto, e il comando esterno lavora sul risultato. L'argomento è la parola dopo il comando, più i codici in maiuscolo o i numeri che la seguono subito (`@stock AAPL TSLA`, `@stock 600519 700`); una parola in minuscolo lo chiude (`@stock SNDK is good to buy` cerca SNDK). Le virgolette lo delimitano con esattezza: `@stock "aapl tsla"`. Anche il plugin `@calculator` funziona lì: `@reply the total is @calculator 23*17 dollars`. All'interno di `@agent` e dei comandi da terminale non vengono eseguiti: questi ricevono il testo così come è scritto (digitare `@` lì non apre l'elenco dei comandi).

### Tasto azione

⏎ per impostazione predefinita; cambialo in "Action key" (tasto azione) nelle impostazioni (`actionKey` nella configurazione): ⏎, Tap ⌥ (tocco breve su ⌥, di entrambi i lati: premi e rilascia subito; tenere premuto ⌥ destro resta per parlare), ⌥Spazio, o Spazio (premi Spazio un'altra volta dopo aver scelto le parole; due volte in modalità inglese). Qualunque sia il tasto azione, i comandi @ vengono eseguiti anche con ⏎. Se ⌥Spazio è già una scorciatoia per Alfred, Raycast o simili, la ricevono loro per primi.

### Digitare i risultati

Attiva "Type results out" (digita i risultati) in Settings → General (`typeOut` nella configurazione) e il risultato di un comando viene digitato nell'app carattere per carattere, come farebbe una persona, invece di entrare tutto in una volta; le parole scelte in pinyin entrano comunque in una volta. Il cursore regola il ritmo, da 6 secondi per carattere a 40 al secondo (`typeOutRate`), e "Speed up and slow down (like a person)" (accelera e rallenta, come una persona) digita a raffiche con ritmo variabile (`typeOutVaries`). Esc lo ferma dove si trova; qualsiasi altro tasto digita il resto in una volta.

"Make occasional typos and fix them" (fai qualche errore di battitura e correggilo, `typeOutMistakes`) lo rende ancora più umano: ogni tanto il tasto accanto a quello giusto, notato fino a tre lettere dopo, cancellato e ridigitato; una lettera o uno spazio digitati due volte e cancellati; oppure una parola breve digitata, cancellata e ridigitata. Alcuni ogni 100 caratteri, mai due vicini e mai all'inizio di una riga. In codice, indirizzi web ed email e numeri, un errore è solo una lettera o una cifra sbagliata, corretta subito (mai una parentesi, una virgoletta o uno spazio sbagliati, su cui gli editor creano coppie o rientri). Le lettere sbagliate sono vicine sul tuo layout di tastiera (QWERTY, AZERTY, QWERTZ…). Cinese, giapponese e coreano esitano soltanto (due caratteri digitati, cancellati e ridigitati), mai con un carattere sbagliato.

In un campo che accetta la correzione di un errore (le viste di testo di Apple come TextEdit e Note, i browser, la maggior parte degli editor): digitato fino alla fine, o con un altro tasto premuto per digitare il resto in una volta, il testo è esattamente il risultato; Esc (o uscire dal campo) nel mezzo di un errore toglie prima l'errore, così il campo contiene un inizio esatto del risultato. Se il cursore si sposta mentre un errore è visibile (un clic), l'errore viene tolto dov'era e il resto viene digitato senza errori.

Gli errori non vengono mai fatti nei terminali, né nelle app che non dicono al metodo di inserimento dove si trova il cursore. Ogni volta il primo errore è semplice (una lettera sbagliata, corretta in un colpo), finché il campo non ha dimostrato di accettare la correzione di un errore; mentre un errore è visibile, il metodo di inserimento controlla prima di ogni tasto che il campo contenga ciò che ha digitato. Un campo che ignora dove sostituire il testo non può correggere un errore: lì quel primo errore resta, quindi il testo finisce con un carattere diverso (anche dopo Esc o un altro tasto), e l'app non riceve più errori. Settings → General elenca queste app sotto l'interruttore degli errori; "Forget apps where typos couldn't be fixed" (dimentica le app in cui gli errori non si sono potuti correggere) le lascia riprovare.

### Impostazioni per app (novità)

Settings → Apps dà a un'app impostazioni proprie, tutte facoltative; ciò che un'app non imposta segue le impostazioni valide per tutte le app:

| Impostazione | Per esempio | Nella configurazione |
| --- | --- | --- |
| La lingua di inserimento con cui partono i suoi campi di testo | Slack in inglese, WeChat in pinyin | `inputLanguage` |
| Gli stili di riformulazione che `@improve` offre lì | Mail formale e diplomatico, Slack informale | `rewriteStyles` |
| Digitare i risultati, oppure no | attivo in un'app di chat, disattivo in Mail | `typeOut` |
| Nessuna IA in questa app | `@improve`, `@translate`, `@question`, `@agent` e i tuoi comandi di istruzione lì non inviano nulla e lo dicono; la digitazione e gli altri comandi funzionano | `noAI` |
| Traduci mentre scrivi sempre attivo | WeChat sempre con Traduci mentre scrivi (vedi [Traduci mentre scrivi](#traduci-mentre-scrivi)) | `translateAlways` |

"Add App…" (aggiungi app) elenca le app in cui hai digitato di recente, oppure ne sceglie una in /Applications. Il menu di inserimento, con "This App: <nome>", ha interruttori rapidi per l'app in cui stai digitando (No AI, Type Results Out, la lingua di partenza). Nella configurazione stanno in `appProfiles`, per bundle ID: `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. I bundle ID si confrontano senza distinzione tra maiuscole e minuscole (`com.apple.Mail` è il `com.apple.mail` di Mail). `@reportissue` conta le app che impostano qualcosa, senza mai nominarle.

- La lingua di partenza funziona come la lingua di inserimento predefinita: un campo di testo la prende quando diventa attivo, e un cambio con Maiuscole resta poi valido per i campi di quell'app finché l'impostazione non cambia.
- Con No AI, i comandi IA restano nell'elenco @; eseguirne uno mostra l'avviso e conserva ciò che hai scritto. I tuoi comandi da terminale (`"type": "terminal"`) eseguono programmi, non l'IA, quindi lì funzionano ancora.

### Settings → Assistant (novità)

Le impostazioni si aprono su **Assistant**, una pagina con due sezioni (prima della 0.6.5 erano i comandi `@config` e `@doctor`).

**Cambiare le impostazioni con una frase** ("Change settings in a sentence"): scrivi cosa vuoi ("translate into Japanese and English", "candidates in a column", "use Claude") e fai clic su Preview (o ⌘⏎). Ogni modifica appare come prima → dopo; Apply le applica e Undo le annulla entro 10 minuti. Può anche attivare o disattivare la sincronizzazione tramite iCloud (cosa sincronizzare si sceglie solo nelle impostazioni). Le chiavi API, i comandi personalizzati, i plugin e tutto ciò che avvia programmi non vengono mai cambiati lì; un fornitore senza chiave apre il suo campo della chiave in Settings → AI Provider, e dopo un cambio di fornitore viene eseguito Test Connection. Funziona con Apple Intelligence se questo Mac ce l'ha, altrimenti con il tuo fornitore.

**Controllare i problemi** ("Check for problems"): metodo di inserimento, fornitore di IA, permessi, input sicuro, pacchetti di lingua, `config.json`, estensioni, aggiornamenti, sincronizzazione tramite iCloud (attiva o no, l'ultima sincronizzazione, l'ultimo errore, iCloud Drive non disponibile, impostazioni di iCloud non usate qui) ed errori recenti vengono controllati su questo Mac all'apertura della pagina, prima i problemi (tutto a posto: "Everything looks good"). Check li controlla di nuovo con Test Connection; con una domanda in "What's wrong? (optional)", l'IA spiega la causa probabile. Una riga che si può correggere ha un pulsante Fix: le modifiche alle impostazioni compaiono nell'anteprima sopra, con Apply e Undo; le altre agiscono subito.

### Sincronizzazione tramite iCloud (novità)

Settings → General → **Sync through iCloud** (sincronizza tramite iCloud; disattivato per impostazione predefinita) mantiene uguali su tutti i tuoi Mac le impostazioni, l'elenco del gergo, i comandi personalizzati e le parole apprese dal pinyin, tramite il tuo iCloud Drive: nessun altro account a cui accedere, niente passa dai nostri server. Serve iCloud Drive (Impostazioni di Sistema → Account Apple → iCloud); senza, l'interruttore resta disattivato e lo dice, con un pulsante che apre quel pannello.

| Interruttore | Cosa si sincronizza | Predefinito |
| --- | --- | --- |
| Settings (impostazioni) | le impostazioni di `config.json`: lingue, stili di riformulazione, tasto azione, digitazione dei risultati, impostazioni per app, nascondere le informazioni sensibili (i suoi interruttori), fornitore e modello di IA (mai una chiave) … | attivo |
| Jargon and custom commands (gergo e comandi personalizzati) | il tuo elenco del gergo e `customCommands` | attivo |
| Learned words (parole apprese) | ciò che il pinyin ha appreso dalle tue scelte (il dizionario utente di Rime, tramite la sincronizzazione del dizionario utente di librime; i tuoi file di Rime, come le frasi personalizzate, restano sul Mac) | attivo |
| Hidden words (parole nascoste) | le parole che nascondi all'IA (l'interruttore ricorda che iCloud Drive è cifrato end-to-end solo con la Protezione avanzata dei dati) | disattivo |
| Recent questions (domande recenti) | le domande recenti di `@question` con le risposte (finché "Remember recent questions" è attivo) | disattivo |
| API keys and passwords (chiavi API e password) | le tue chiavi API e le password delle estensioni, tramite Portachiavi iCloud, che è sempre cifrato end-to-end (serve Password e portachiavi attivo in Impostazioni di Sistema → Account Apple → iCloud) | disattivo |

`iCloud Drive/AllInOneIME/settings.json` contiene ogni impostazione con il momento in cui è cambiata e su quale Mac (un id casuale), e per ogni impostazione vince la modifica più recente: un elenco (i tuoi comandi personalizzati, gli stili di riformulazione) è un unico valore, le impostazioni per app vanno app per app, e anche rimuovere le impostazioni di un'app è una modifica. Si sincronizza all'avvio del metodo di inserimento, circa 5 s dopo che cambi qualcosa, quando iCloud porta una modifica da un altro Mac (e ogni 5 minuti) e con **Sync Now** (sincronizza ora); le parole apprese all'avvio del metodo di inserimento, ogni 30 minuti (dopo una pausa nella digitazione) e con Sync Now. La riga di stato dice "Last synced 2 min ago", "Waiting for iCloud…" o l'errore.

- Quando la attivi, un Mac prende le impostazioni già presenti in iCloud; le sue completano solo ciò che lì manca ancora. Le sue raccolte invece vengono unite: domande recenti (le due liste, dalla più recente, ogni domanda una volta sola), parole nascoste, comandi personalizzati (per nome; in caso di conflitto vince quello di iCloud) e le righe dell'elenco del gergo. Lo stesso vale quando un interruttore sottostante viene attivato per la prima volta. Ciò che poi togli su un altro Mac (un comando personalizzato o una parola nascosta eliminati) resta fuori. Ricompare una sola volta (e una seconda eliminazione è definitiva) se veniva dal primo Mac che ha attivato la sincronizzazione e quel Mac era in stop mentre un altro Mac vi univa la sua lista, se è stato eliminato su un Mac ancora alla 0.6.4, o se un Mac ancora alla 0.6.4 lo riporta. Un'impostazione salvata nelle impostazioni mentre un Mac sta attivando la sincronizzazione viene conservata, e va agli altri Mac.
- Riattivata dopo essere stata disattivata: arriva ciò che iCloud ha cambiato nel frattempo (anche dove l'ha cambiato pure questo Mac), sale ciò che ha cambiato solo questo Mac, e una raccolta a cui questo Mac ha aggiunto qualcosa nel frattempo viene unita, mai scartata.
- Le domande recenti di due Mac vengono unite; "Clear" su un Mac cancella anche sugli altri ogni domanda fatta prima. Disattivare "Remember recent questions" le elimina solo su quel Mac, e riattivandolo tornano le domande degli altri Mac. Un Clear fatto mentre un Mac non sincronizza le domande recenti (o non le ricorda) vale solo per quel Mac.
- Disattivare Hidden words o Recent questions lascia in iCloud ciò che era stato sincronizzato: **Remove from iCloud…** (rimuovi da iCloud) sotto ciascun interruttore (con richiesta di conferma) lo toglie; gli altri Mac conservano il loro, e uno che li sincronizza ancora rimette i suoi.
- Un valore di un altro Mac che questo non può usare (un fornitore senza chiave qui, un profilo AWS che non ha, un valore fuori intervallo) non viene applicato: la riga di stato e il controllo dei problemi di Settings → Assistant dicono quale.
- Un file che iCloud non ha ancora scaricato viene atteso, mai preso per vuoto; un `settings.json` illeggibile viene messo da parte come `settings (unreadable …).json`, mai sovrascritto. Le impostazioni di una versione più recente vengono conservate così come sono.
- Le chiavi API e le password passano da Portachiavi iCloud, non da iCloud Drive: con "API keys and passwords" attivo (mentre la sincronizzazione è attiva), una chiave salvata o sostituita su un Mac si ritrova sugli altri. È disattivato per impostazione predefinita: attivare solo la sincronizzazione non sposta alcuna chiave, e nulla si sposta finché non attivi questo interruttore. Attivarlo sposta le chiavi di questo Mac dal portachiavi login a Portachiavi iCloud (dopodiché, dopo un aggiornamento, macOS non chiede più la password di login per esse); disattivarlo le ricopia nel portachiavi login e le lascia in Portachiavi iCloud per gli altri tuoi Mac. Le chiavi che non si sincronizzano restano nel portachiavi login, come prima, e così anche l'accesso ad AllInOneIME Cloud, che non si sincronizza mai: ogni Mac accede per conto suo. Quando due Mac hanno chiavi diverse, vince quella salvata per ultima (in base al momento del salvataggio, che ogni copia conserva). L'altra non viene eliminata: resta nel portachiavi login del suo Mac come copia sostituita (sotto "AllInOneIME replaced API key", con il nome che termina con "(replaced)"), che non viene mai usata. Anche una chiave che passa in Portachiavi iCloud ne conserva una, nel caso le arrivi sopra una chiave diversa da un altro Mac. Su ogni Mac c'è una sola copia sostituita per chiave: una successiva prende il suo posto. Rimuovere una chiave mentre si sincronizza la rimuove su ogni Mac che sincronizza le chiavi (la richiesta di conferma dice "all your Macs"), insieme alla copia sostituita di questo Mac; un Mac con "API keys and passwords" disattivato, o ancora alla 0.6.4, conserva la propria copia, e la rimette se in seguito vi si attiva la sincronizzazione delle chiavi (lo dice anche la richiesta di conferma). Su un Mac dove è disattivato, Remove… rimuove la chiave e la sua copia sostituita solo da quel Mac (la richiesta di conferma dice "this Mac"), e la copia in Portachiavi iCloud resta per gli altri tuoi Mac. Una chiave che, al momento di spostarla, macOS non lasciava leggere ad AllInOneIME senza la tua password di login resta nel portachiavi login fino al suo prossimo uso: se allora macOS lo chiede e lo consenti, viene usata di nuovo, anche se è stata rimossa su un altro Mac. Ogni chiave continua ad andare solo all'host per cui è stata salvata. Mentre le chiavi si sincronizzano, `allinoneime-cli` e le versioni precedenti alla 0.6.5 non le vedono nel portachiavi. Una build senza il profilo di provisioning (una build di sviluppo) tiene le chiavi nel portachiavi login e non può sincronizzarle: l'interruttore lo dice.
- Mai sincronizzati: l'accesso ad AllInOneIME Cloud, le credenziali AWS (in `~/.aws`), le sorgenti delle estensioni (eseguono codice: decide ogni Mac), le cartelle delle estensioni e i plugin (percorsi propri di ogni Mac), le app senza errori di battitura e le app recenti, lo stato delle finestre e gli interruttori della sincronizzazione stessi (propri di ogni Mac).
- Disattivarla interrompe la sincronizzazione e lascia tutto com'è, su questo Mac e in iCloud; **Remove from iCloud…** (con richiesta di conferma) sposta la cartella nel Cestino e disattiva la sincronizzazione su questo Mac.
- Settings → Assistant ("sync through iCloud") la attiva o disattiva; parole nascoste e domande recenti si scelgono solo in Settings → General. Nella configurazione: `iCloudSync` (`enabled`, `settings`, `jargon`, `learnedWords`, `hiddenWords`, `recentQuestions`, `keys`).

## Pannello della barra dei menu

<img src="../en/panel-swipe.png" width="520" alt="Il pannello della barra dei menu: vetro smerigliato, con note, promemoria e attività di Claude su schede; una riga fatta scorrere verso sinistra mostra il suo pulsante Remove">

Fai clic sull'icona di AllInOneIME nella barra dei menu (il simbolo ∞ con un cursore, senza riquadro; quello con il riquadro è la sorgente di input) e il pannello si apre sotto di essa; un clic altrove lo chiude:

- Notes (note): le note salvate con `@note`, le 5 più recenti; fai clic su una per aprirla dove è finita: in Note, in Obsidian o nell'app del file, oppure la pagina di Notion. Un file che non c'è più non viene più elencato.
- Reminders (promemoria): i promemoria non ancora completati nell'elenco AllInOneIME di Promemoria (`@reminder` li aggiunge a quell'elenco), prima quelli con la scadenza più vicina, 8 visibili; fai clic sul cerchio per spuntarne uno, o sul titolo per aprire Promemoria.
- Claude Tasks (attività di Claude): come `@tasks`, le attività di Claude in background (ciò che `@agent` delega a Claude Code), fino a 30, 5 visibili alla volta: scorri per vederne altre, o cerca nei loro titoli e risposte con il campo di ricerca; con il loro avanzamento e la prima riga dell'ultima risposta; fai clic su una per aprirla in Terminale e proseguire.

Fai scorrere una riga (una nota, un promemoria o un'attività) verso sinistra con due dita per mostrare il suo pulsante Remove (rimuovi), o fino in fondo per rimuoverla subito; con un mouse, fai clic destro su di essa. La rimozione la toglie solo dal pannello: la nota resta in Note, il promemoria in Promemoria (non completato), l'attività in Claude Code.

L'intestazione mostra i conteggi (come "2 reminders · 1 task running"; le attività che ti aspettano sono contate a parte, come "1 waiting for you") e un pulsante di aggiornamento. Non toglie mai il focus all'app in cui stai scrivendo: spuntare un promemoria o aggiornare lascia quell'app in primo piano; solo il campo di ricerca delle attività di Claude, una volta cliccato, prende la tastiera. L'icona è visibile per impostazione predefinita; disattivala in "Menu Bar Panel" nelle impostazioni.

Cosa legge, e quando:

- Note: l'elenco è il registro proprio del pannello (conservato anche quando è chiuso), e Note non viene mai avviata: solo quando Note è già in esecuzione, e AllInOneIME era stato autorizzato in precedenza a controllarla, il pannello vi controlla i titoli modificati e le note eliminate.
- Promemoria: l'elenco AllInOneIME viene letto quando il pannello si apre, ogni 60 secondi e quando i promemoria cambiano. Il pannello non fa mai chiedere l'accesso a macOS di sua iniziativa: se macOS non te l'ha ancora chiesto, mostra "Allow Access to Reminders" (consenti l'accesso a Promemoria), e solo quel pulsante lo chiede; se hai rifiutato, mostra "Open System Settings" (apri Impostazioni di Sistema).
- Attività di Claude: il pannello esegue `claude agents` solo mentre è aperto: una volta all'apertura, all'aggiornamento e quando `@agent` delega un'attività; e ogni 15 secondi finché un'attività non è finita, non più una volta che sono tutte finite. Le ultime risposte vengono lette dalla fine delle trascrizioni di Claude Code su questo Mac (`~/.claude/projects`), e solo quando una trascrizione è cambiata.
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
- **Disposizione dei candidati**: per scegliere le parole, i candidati pinyin e hindi sono affiancati per impostazione predefinita (Horizontal), come nei metodi di inserimento del sistema: ← → scelgono e ↑↓ (o - =) cambiano pagina. Scegli Vertical nella pagina Input, sotto le lingue di inserimento, per averli uno sotto l'altro (↑↓ scelgono). L'elenco dei comandi @ e i risultati sono sempre verticali.
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

## Traduci mentre scrivi

Un prototipo, da provare. Tieni premuto Maiuscole da solo per 1 secondo per attivare (o disattivare) Translate as You Type, la traduzione mentre scrivi; un tocco breve su Maiuscole continua a cambiare la lingua di inserimento. A 0,5 s un suggerimento vicino al cursore dice "Keep holding → Translate as You Type" (continua a tenere premuto), e a 1 s "Translate as You Type on: Chinese → English · hold Shift again to turn off" (con il nome della lingua in cui traduce) lo conferma per circa 1,5 s (per disattivarlo: "Keep holding → Translate as You Type off", poi "Translate as You Type off"); se rilasci prima, non cambia nulla. Maiuscole insieme a una lettera (una maiuscola) o a un altro tasto non lo attiva mai. Mentre è attivo, l'icona nella barra dei menu porta un puntino. Non c'è un comando per attivarlo.

Mentre è attivo, ciò che digiti si raccoglie in una bozza, accanto all'etichetta con le lingue ("ZH → EN"; 「中 → 英」 nell'interfaccia in cinese). Traduce nella lingua che hai scelto per ultima sull'etichetta (vedi sotto), in ogni app e anche dopo un riavvio; finché non ne scegli una, nella tua prima lingua di traduzione nelle impostazioni (e torna a quella quando la lingua scelta non è più tra di esse). La lingua in cui stai scrivendo quando lo attivi non la cambia. ⏎ traduce la bozza e la traduzione entra subito, senza candidati da scegliere: nel frattempo la bozza dice "Translating…", e nell'app non parte nulla (il ⏎ successivo è quello dell'app). ⇧⏎ inserisce la bozza così com'è; Esc durante la traduzione la ferma e conserva la bozza (anche ⌫ la ferma, e cancella un carattere come sulla bozza); se non riesce (la rete, un rifiuto, l'inserimento sicuro), la bozza resta con un avviso di una riga e ⏎ riprova. Il testo digitato nella lingua di destinazione (tocca Maiuscole per l'inglese) entra così come digitato.

L'etichetta "ZH → EN" (「中 → 英」 nell'interfaccia in cinese) compare in piccolo sotto la riga in cui scrivi, nel pannello del metodo di inserimento (il pannello dei candidati: sopra i candidati mentre digiti pinyin), così non toglie mai il focus all'app. Fai clic su "ZH" per cambiare lingua di inserimento, come con un tocco su Maiuscole. Fai clic su "EN" per un breve elenco delle tue lingue di traduzione, con quella attuale spuntata, e scegline una: diventa subito la lingua di destinazione (l'etichetta e la traduzione successiva si adeguano) e lo resta da allora in poi. I tasti funzionano come prima; uno qualsiasi chiude l'elenco.

- **Tono**: segue l'app: il primo stile di riformulazione dell'app in Settings → Apps, altrimenti informale nelle app di chat (WeChat, Slack, Messaggi, Telegram, Discord, Teams), formale nelle app di posta (Mail, Outlook, Spark), naturale altrove.
- **App**: passare a un'altra app (anche una senza campo di testo) lo disattiva, senza avviso, e quando torni resta disattivato, a meno che quell'app non abbia "Always Translate as You Type" (「总是边打边译」) in Settings → Apps (`translateAlways` nel suo profilo): lì si attiva da solo. In un'app con No AI non fa nulla: il testo entra così come digitato, con un avviso; lo stesso per ciò che digiti durante l'inserimento sicuro (un campo password).
- **Privacy**: come per `@translate`: il testo viene inviato solo quando premi ⏎, al tuo fornitore di IA, con le informazioni sensibili nascoste se l'opzione è attiva.

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
3. Il programma di installazione è firmato con un Developer ID e autenticato (notarized) da Apple, quindi la prima volta macOS chiede solo se aprire un'app scaricata da internet: fai clic su Apri. (Le versioni precedenti alla 0.6.3 non erano autenticate: ognuna andava consentita una volta in Impostazioni di Sistema → Privacy e sicurezza → Apri comunque.)

Dopodiché AllInOneIME è attivato e compare tra le tue sorgenti di input; passa a esso con Ctrl+Spazio (il tasto 🌐 cambia sorgente solo se "Premi il tasto 🌐 per" è impostato su "Cambiare sorgente di input" in Impostazioni di Sistema → Tastiera). Se il programma di installazione ti dice di aggiungerlo a mano, questo Mac non permette ai programmi di attivarlo, quindi aggiungilo tu una volta: Impostazioni di Sistema → Tastiera → Input di testo → Sorgenti di input → Modifica… → + (in basso a sinistra) → Inglese → AllInOneIME (scrive anche in pinyin una volta aggiunto il cinese in Input nelle sue impostazioni).

Se Ctrl+Spazio non ti porta ad AllInOneIME, o torna a U.S. dopo un po', esegui di nuovo il programma di installazione: aggiunge di nuovo AllInOneIME alle tue sorgenti di input.

Aggiornare: Settings → About → Check for Updates (controlla aggiornamenti). Quando c'è una nuova versione, About lo dice (e una riga nel pannello della barra dei menu), con le novità; "Update to <version>" (aggiorna a <versione>) la scarica, la verifica con le informazioni di aggiornamento firmate con la chiave di rilascio di AllInOneIME, la installa e riavvia il metodo di inserimento. Le tue impostazioni, i pacchetti di lingua, le parole apprese e le estensioni restano, e se qualcosa va storto viene ripristinata la versione che avevi. AllInOneIME controlla da solo una volta al giorno, in background (disattivalo con "Check for updates automatically" in About); non viene installato nulla finché non fai clic. Funziona dalla 0.6.3 in poi; per aggiornare una versione più vecchia, o se preferisci, installa sopra l'immagine disco della nuova versione, senza disinstallare prima. Prima di aggiornare, leggi il [registro delle modifiche](../../CHANGELOG.md): contiene le modifiche di ogni versione e le note di aggiornamento.

Aggiornare alla 0.6.3 da una versione precedente: la 0.6.3 è la prima versione firmata con un Developer ID, quindi il portachiavi non la riconosce ancora come l'app che ha salvato le tue chiavi. La prima volta che le serve ciascuna chiave salvata (una chiave API, l'accesso ad AllInOneIME Cloud, la password di un'estensione), macOS chiede la tua password di login: inseriscila e fai clic su "Always Allow" (Consenti sempre). Non la chiede più, nemmeno dopo gli aggiornamenti successivi. Le chiavi di Amazon Bedrock si trovano in `~/.aws/credentials`, che non è interessato. Anche Accessibilità (Impostazioni di Sistema → Privacy e sicurezza → Accessibilità), che usano l'incolla nei terminali e la lettura della selezione, richiede un passaggio: se AllInOneIME è nell'elenco, rimuovilo e riattivalo quando ti viene chiesto.

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

Traduzioni e riformulazioni vanno al fornitore di IA scelto in Settings → AI Provider. Una nuova installazione parte con AllInOneIME Cloud: accedi e hai 20 richieste gratuite al giorno. Su un Mac con Apple Intelligence, può invece funzionare su questo Mac, senza account (vedi "Apple Intelligence su questo Mac" più sotto). Oppure usa il tuo fornitore, con i costi sul tuo account: Amazon Bedrock nel tuo account AWS, l'API di Claude, Gemini o un servizio compatibile con OpenAI (vedi "Altri fornitori di IA" più sotto).

### Amazon Bedrock

1. Attiva Bedrock nella console AWS e assicurati di poter usare il modello scelto. Quello predefinito è Claude Haiku 4.5; la prima volta che usi un modello Anthropic, compili una volta un modulo sul caso d'uso.
2. Usa un profilo AWS autorizzato a `bedrock:InvokeModelWithResponseStream`: chiavi statiche in `~/.aws/credentials`, oppure un profilo che ottiene credenziali temporanee (`credential_process`, un ruolo, SSO; vedi "Profili AWS" più sotto).
3. Apri "AllInOneIME Settings": lo trovi in Spotlight o in Applicazioni, oppure aprilo dall'icona del metodo di inserimento nella barra dei menu → Settings…. Scegli profilo, regione e modello, e fai clic su "Test Connection" (verifica connessione). L'interfaccia è disponibile in English, 简体中文 (cinese semplificato), 繁體中文 (cinese tradizionale), 日本語, 한국어, Deutsch, Français, Español e Português (Brasil). Per impostazione predefinita ("Follow the system" in Settings → General → "Interface language") segue le lingue preferite del sistema (Impostazioni di Sistema → Generali → Lingua e zona): la prima che l'app ha; una variante regionale prende la sua lingua (Deutsch per de-AT, Español per es-MX, Français per fr-CA), zh-Hant, zh-TW e zh-HK il cinese tradizionale, gli altri tipi di cinese il semplificato, e il portoghese del Portogallo il portoghese brasiliano (lì si legge meglio dell'inglese); l'inglese quando non ce n'è nessuna. Oppure scegline una lì, ognuna elencata nella propria lingua. La finestra delle impostazioni, i suggerimenti nel pannello dei candidati e il menu di input la seguono tutti. Le impostazioni si aprono sulla pagina Assistant: cambiare le impostazioni descrivendole e controllare i problemi, con un Fix per ciascuno (vedi [Settings → Assistant](#settings--assistant-novità)).

<img src="../en/settings.png" width="420" alt="La finestra delle impostazioni">

#### Profili AWS

Funziona qualsiasi profilo che l'AWS CLI può usare senza chiederti nulla, da `~/.aws/config` e `~/.aws/credentials` (o dai file indicati da `AWS_CONFIG_FILE` e `AWS_SHARED_CREDENTIALS_FILE` nella tua shell). All'interno di un profilo viene usata la prima di queste fonti che contiene, nell'ordine dell'AWS CLI (un profilo con sia `role_arn` sia delle chiavi è un ruolo):

| Tipo | Nel profilo | Rinnovo |
| --- | --- | --- |
| Ruolo | `role_arn` con `source_profile` (di qualsiasi tipo, anche a catena; un profilo che nomina se stesso usa le proprie chiavi) o `credential_source = Environment`; `role_session_name`, `external_id`, `duration_seconds` | di nuovo con STS `AssumeRole` (nella `region` del profilo, altrimenti us-east-1) 5 minuti prima che scadano |
| SSO | `sso_account_id`, `sso_role_name` con `sso_session` e la sua sezione `[sso-session …]` (o i vecchi `sso_start_url`, `sso_region`) | recuperate di nuovo con il tuo accesso in cache 5 minuti prima che scadano |
| Chiavi statiche | `aws_access_key_id`, `aws_secret_access_key` (e `aws_session_token`) in `~/.aws/credentials` | rilette a ogni richiesta |
| `credential_process` | `credential_process = /usr/local/bin/my-creds --profile dev` (suddiviso come un comando di shell, eseguito senza shell, con il PATH della tua shell di login, nella tua cartella Inizio, al massimo 60 s) | rieseguito 5 minuti prima del suo `Expiration`; se manca, quando AWS rifiuta le credenziali |
| Chiavi statiche | le stesse chiavi in `~/.aws/config` | rilette a ogni richiesta |

Con il profilo "default" (o se non ne è scelto nessuno), le chiavi della tua shell vengono per prime, come le prende l'AWS CLI: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN`. Un profilo che indichi per nome non viene mai mescolato con esse. `AWS_REGION` (o `AWS_DEFAULT_REGION`) nella tua shell prevale sulla `region` di un profilo, come nell'AWS CLI; il campo Region nelle impostazioni prevale su entrambi.

- **Automatico:** le credenziali che scadono vengono tenute in memoria (mai scritte su disco) e recuperate di nuovo 5 minuti prima della scadenza; se mancano meno di 10 minuti, una richiesta le usa e ne recupera di nuove in background, così la digitazione non aspetta. Le richieste contemporanee aspettano un unico recupero. Quando Bedrock risponde che le credenziali sono scadute (`ExpiredTokenException` …), vengono recuperate di nuovo e la richiesta viene reinviata, una sola volta.
- **SSO:** AllInOneIME usa l'accesso che l'AWS CLI conserva in `~/.aws/sso/cache` (si limita a leggerlo) e non può accedere al posto tuo, perché serve un browser. Quando l'accesso scade, il pannello dei candidati dice "SSO sign-in expired: run aws sso login --profile X" (accesso SSO scaduto: esegui aws sso login --profile X): eseguilo in Terminale (le impostazioni hanno Copy Command e Open in Terminal; Settings → Assistant offre il comando da copiare), e AllInOneIME riprende da solo il nuovo accesso.
- **Non supportati:** `mfa_serial` (un metodo di inserimento non può chiederti un codice MFA: usa `credential_process` o SSO, oppure lascia che la tua CLI metta in cache le credenziali), `credential_source = Ec2InstanceMetadata` o `EcsContainer` (non su un Mac) e web identity.
- **Limiti noti:** dalla tua shell di login arrivano solo il PATH e le variabili dei file AWS (`AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`), anche per `credential_process` (non il resto del suo ambiente). AllInOneIME non rinnova i token di `sso_session` (il refresh token della CLI non viene usato: la cache SSO viene solo letta), quindi quando il token in cache scade esegui `aws sso login` (l'AWS CLI lo rinnova anche ogni volta che la usi).
- **Settings → AI Provider** elenca ogni profilo con il suo tipo ("dev — Role via base") e, per quello scelto, dice quando scadono le sue credenziali ("Role via base: credentials expire at 15:30", "SSO (signed in until 18:00)") o cosa fare. Test Connection recupera credenziali nuove lungo tutta la catena; Settings → Assistant riporta lo stesso.
- I programmi vengono eseguiti e ad AWS vengono chieste credenziali (`sts.<region>.amazonaws.com`, `portal.sso.<region>.amazonaws.com`) solo quando una richiesta o Test Connection ne ha bisogno: mai per elencare i profili, mai per Settings → Assistant.

### Altri fornitori di IA: API di Claude, Gemini, servizi compatibili con OpenAI

Non ti serve AWS: scegline uno in "AI Provider" (fornitore di IA) nelle impostazioni, incolla una chiave API, fai clic su "Save" (salva), poi su "Test Connection".

| Fornitore | Modello predefinito | Chiave API |
|---|---|---|
| API di Claude | `claude-haiku-5-5` (il più veloce ed economico; Sonnet 5.5 e Opus 5.5 sono più accurati ma più lenti e costosi) | [Claude Console](https://platform.claude.com) |
| API di Gemini | `gemini-3.8-flash` | Google AI Studio |
| Compatibile con OpenAI | `gpt-6-luna` di OpenAI (o `gpt-5.4-mini`); "Common Services…" (servizi comuni) include DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter e Ollama su questo Mac: sceglierne uno compila il suo URL di base, poi inserisci il suo modello | La chiave del servizio; imposta la Base URL sul suo indirizzo, ad es. `https://api.deepseek.com/v1`, o `http://localhost:11434/v1` per Ollama su questo Mac |

- Le chiavi API sono conservate nel portachiavi login, mai nel file di configurazione; se attivi "API keys and passwords" in Sync through iCloud, sono invece in Portachiavi iCloud, dove `allinoneime-cli` e le versioni precedenti alla 0.6.5 non le vedono. Se lì non ce n'è una, vengono usate `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (o `GOOGLE_API_KEY`) e `OPENAI_API_KEY` della tua shell.
- La riga della chiave API dice se è impostata una chiave: "✓ Saved · ends in a1b2" (salvata · termina con a1b2: i suoi ultimi 4 caratteri, conservati insieme a essa così che per mostrarli non si legga la chiave stessa) con Replace… (sostituisci) e Remove… (rimuovi), "✓ From $OPENAI_API_KEY" (da $OPENAI_API_KEY) per una presa dalla tua shell, oppure "No API key yet" (ancora nessuna chiave API) con il campo per incollarla.
- "Thinking" (ragionamento) è basso per impostazione predefinita: il metodo di inserimento attende a ogni frase, e meno ragionamento è più veloce. Scegli "Not set" (non impostato) per i modelli che non lo supportano.
- Con Claude Opus 5.5 o Sonnet 5.5 selezionato, le richieste includono il fallback in caso di rifiuto dell'API di Claude (`fallbacks: "default"`): quando un classificatore di sicurezza rifiuta, il server riprova con un altro modello.
- Nel file di configurazione: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), e `model`, `baseURL`, `effort` e `temperature` sotto `anthropic`, `gemini` e `openai` (quelli non impostati usano i valori predefiniti).

### Apple Intelligence su questo Mac (macOS 26)

Su un Mac con Apple Intelligence (chip Apple, macOS 26 o successivo, attivata in Impostazioni di Sistema → Apple Intelligence e Siri), scegli "Apple Intelligence (on this Mac)" in "AI Provider": nessuna chiave, nessun costo, e niente di ciò che digiti lascia il Mac. Usa il modello integrato in macOS (il framework Foundation Models), con le stesse istruzioni e lo stesso formato di risposta degli altri fornitori, ma solo gli esempi scritti nella lingua della frase (un modello piccolo copia troppo facilmente la lingua di un esempio).

- È un modello piccolo: il suo contesto è di circa 4K token (8K su macOS 27), quindi un paragrafo lungo può essere troppo per lui, e parla meno lingue (inglese, cinese, giapponese, coreano, francese, tedesco, spagnolo e poche altre; non l'hindi). In entrambi i casi lo dice. I suoi risultati sono inferiori a quelli dei modelli cloud, e le sue risposte di `@question` su fatti e codice sono spesso sbagliate.
- Dove non può essere usato, compare in grigio con il motivo (non supportato su questo Mac, disattivato, modello non pronto), e le impostazioni rimandano a Impostazioni di Sistema → Apple Intelligence e Siri. Prima di macOS 26 non compare.
- "Output tokens", la temperatura e il timeout in "Model Settings" si applicano anche a lui. Nel file di configurazione: `"provider": "apple"`.

### Nascondere le informazioni sensibili (novità)

Settings → AI Provider → Privacy → "Hide sensitive information before sending" (nascondi le informazioni sensibili prima dell'invio; disattivato per impostazione predefinita): prima che una richiesta vada all'IA, ciò che trova nel tuo testo viene sostituito sul Mac con segnaposto come `[EMAIL_1]` (stesso valore, stesso segnaposto), e i risultati riavranno i valori reali prima di essere mostrati o inseriti. Il pannello dice "2 items hidden from the AI" (2 elementi nascosti all'IA). Ogni tipo si può disattivare:

| Tipo | Per esempio | Nella configurazione |
| --- | --- | --- |
| Indirizzi email | `bob@example.com` | `emails` |
| Numeri di telefono | `+1 (555) 123-4567`, `138 0013 8000` | `phones` |
| Numeri di carte di pagamento (verificati con Luhn) | `4111 1111 1111 1111` | `cards` |
| Chiavi API e token | prefissi noti come `sk-` o `ghp_`, lunghe stringhe casuali | `keys` |
| Indirizzi IP | `203.0.113.42`, `2001:db8::1` | `ips` |
| Le tue parole, senza distinzione tra maiuscole e minuscole | un nome in codice come `Project Atlas`, un nome | `customWords` |

- Si applica a `@improve`, `@translate`, `@question`, ai tuoi comandi di istruzione e plugin di istruzione, e al perfezionamento dei loro risultati (gli stessi segnaposto), con tutti i fornitori, compresi AllInOneIME Cloud e Apple Intelligence. Le voci dell'elenco del gergo che contengono un valore da nascondere non vengono inviate.
- Riconosce i valori formattati; non può riconoscere nomi o indirizzi, quindi aggiungili come parole tue. `@agent`, i plugin che recuperano dati da un sito web (`@stock`) o ne aprono uno (`@x`) e le estensioni script inviano il testo così come è stato digitato. Altro in Privacy.
- Nella configurazione: `"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`.

Tutte le impostazioni sono memorizzate in `~/.config/allinoneime/config.json`; dopo una modifica, la traduzione successiva usa le nuove impostazioni, senza riavvio. Le chiavi più recenti:

| Chiave | Cosa fa | Predefinito |
|---|---|---|
| `inputLanguages` | Lingue di inserimento, da una a cinque, la prima è quella predefinita: `"en"` inglese, `"zh"` cinese (pinyin), `"fr"` francese, `"ko"` coreano, `"hi"` hindi, ad es. `["en", "zh"]`, `["fr", "en", "ko"]`. Cinese, coreano e hindi funzionano una volta installato il loro pacchetto | `["en"]` (nuova installazione) |
| `keyboardLayouts` | Il layout di tastiera con cui si digita una lingua di inserimento, in base al suo codice (per ora solo il francese): `{"fr": "com.apple.keylayout.French-PC"}` | Francese: `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | Le lingue in cui traduce `@translate`, in ordine: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | `@improve` traduce anche (come `@translate @improve`) | `false` |
| `voiceInput` | Tenere premuto ⌥ destro per parlare | `true` |
| `actionKey` | Tasto azione: `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Spazio), `"space"` (Spazio) | `"enter"` |
| `uiLanguage` | Lingua dell'interfaccia (finestra delle impostazioni, suggerimenti del pannello dei candidati, menu): `"zh"` (cinese semplificato), `"en"`, o il codice di un'altra lingua inclusa nell'app: `"zh-Hant"`, `"ja"`, `"ko"`, `"de"`, `"fr"`, `"es"`, `"pt-BR"` | `null` (segue il sistema) |
| `rewriteStyles` | Stili di riformulazione: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, ad es. `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | Il tuo file con l'elenco del gergo | `null` (cioè `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | L'icona nella barra dei menu e il suo pannello a discesa | `true` |
| `candidateLayout` | Candidati pinyin e hindi: `"vertical"` (uno sotto l'altro) o `"horizontal"` (affiancati; ← → scelgono, ↑↓ cambiano pagina) | `"horizontal"` |
| `fuzzyPinyin` | Coppie di pinyin approssimativo: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | I comandi @ lavorano sul testo selezionato nel campo (vedi Sul testo selezionato) | `true` |
| `checkForUpdates` | Cerca una nuova versione una volta al giorno, in background; non viene installato nulla finché non fai clic | `true` |
| `agent` | L'agente di programmazione a cui `@agent` passa il testo (Settings → Agent): `claude` (Claude Code), `gemini` (Gemini CLI), `kiro` (Kiro CLI) o `custom` | `claude` |
| `agentCommand` | Il comando dell'agente personalizzato, con ciò che hai digitato aggiunto come ultimo argomento, ad es. `["muse", "--"]` | `[]` |
| `agentPageContext` | `@agent` in Google Chrome porta con sé la pagina (il campo, il suo modulo o la sua sezione, la selezione, il testo visibile; mai una password) | `true` |
| `claudeInBackground` | `@agent` con Claude Code viene eseguito in background e ti avvisa (gli altri agenti si aprono sempre in Terminale) | `true` |
| `rememberQuestions` | Conserva le tue ultime 5 domande di `@question` e le risposte su questo Mac, elencate sotto `@question` (vedi Domande recenti) | `true` |
| `questionRounds` | Turni di una conversazione di `@question` nel pannello prima che proponga di proseguire altrove, 2–10 | `5` |
| `questionContinueIn` | Dove può proseguire una conversazione di `@question`, in ordine, il primo è quello predefinito: `agent` (quello a cui `@agent` passa i compiti, al posto della voce propria di quell'agente), `claudeCode`, `geminiCLI`, `kiroCLI`, `customAgent` (gli agenti, ciascuno solo se installato), `claudeWeb`, `chatgpt`, `gemini`, `copy` | `agent`, gli altri agenti installati, Claude, ChatGPT, copia |
| `appProfiles` | Impostazioni di un'app, per bundle ID, tutte facoltative: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI`, `translateAlways` (vedi Impostazioni per app) | `{}` |
| `notes` | Dove salva `@note` (Settings → Plugins → Notes): `{"destination": "folder", "folder": "~/Vault/Inbox"}`, oppure `"notion"` con la pagina o il database trovati da Test; mai sincronizzato tramite iCloud Drive (il token è nel portachiavi, e passa da Portachiavi iCloud solo con "API keys and passwords" attivo) | `destination: "notes"` |
| `redaction` | Nascondi le informazioni sensibili all'IA (vedi Privacy): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`; ogni rilevatore (`emails`, `phones`, `cards`, `keys`, `ips`) è attivo a meno che non sia impostato a `false` | `enabled: false` |

## Privacy

- La digitazione (inglese e pinyin) e i calcoli del plugin `@calculator` sono interamente locali. Solo quando premi il tasto azione su `@improve`, `@translate` o `@question` quella frase viene inviata al fornitore di IA che hai scelto (il tuo Bedrock, o il servizio di cui hai aggiunto la chiave). Con "Jargon" selezionato e un elenco del gergo impostato, l'elenco viene inviato insieme alla frase. Perfezionare i risultati (un'istruzione digitata dopo di essi, poi ⇧⏎) invia di nuovo la stessa richiesta con i risultati mostrati e la tua istruzione; una domanda di seguito (⇧⏎) invia con sé la conversazione fino a quel punto.
- Settings → Assistant invia testo a un modello solo quando fai clic su Preview, o su Check con una domanda: ad Apple Intelligence su questo Mac quando è disponibile (nulla lascia il Mac), altrimenti al tuo fornitore. Una richiesta invia la tua frase (una chiave digitata al suo interno viene tolta prima) con i valori attuali delle impostazioni che può cambiare: mai una chiave, né le parole che nascondi all'IA (solo quante sono), e i nomi dei tuoi profili AWS solo quando la frase parla di AWS o Bedrock. Una domanda viene inviata con i risultati dei controlli, mascherati: nessun percorso oltre `~`, nessuna chiave, le righe di log come frasi fisse. Nascondere le informazioni sensibili vale per entrambe. I controlli da soli non inviano nulla; Check invia anche la richiesta di Test Connection, e solo se il fornitore ha una chiave o credenziali da verificare.
- Proseguire altrove una conversazione di `@question` (⌘1 … dopo l'ultimo turno, o ⌘⏎) la invia, con ciò che hai digitato, al servizio che scegli: un agente di programmazione su questo Mac (Claude Code, Gemini CLI, Kiro CLI o il tuo, ciascuno con il proprio account e il proprio servizio), claude.ai, chatgpt.com o gemini.google.com, nell'indirizzo web o tramite gli appunti. Parte così come l'hai vista: i valori nascosti alle richieste all'IA (vedi sotto) ci sono così come sono, dato che sei tu a scegliere di mandarla lì. Non va da nessuna parte finché non ne scegli uno; "Copy the conversation" la mette soltanto negli appunti.
- Con AllInOneIME Cloud, la frase passa attraverso il server dello sviluppatore verso un fornitore di modelli (attualmente tramite OpenRouter): il server conserva solo dei conteggi, mai il testo. L'accesso conserva solo il tuo indirizzo email.
- Nascondere le informazioni sensibili (Settings → AI Provider → Privacy, disattivato per impostazione predefinita): prima che parta qualsiasi richiesta (`@improve`, `@translate`, `@question`, i tuoi comandi di istruzione e plugin di istruzione, con tutti i fornitori, compreso AllInOneIME Cloud), indirizzi email, numeri di telefono, numeri di carte di pagamento (verificati con Luhn), chiavi API e token (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…` e lunghe stringhe casuali), indirizzi IP e le tue parole (un nome in codice, un nome) vengono sostituiti sul Mac con segnaposto come `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]`; lo stesso valore riceve lo stesso segnaposto. I risultati del modello riavranno i valori reali prima di essere mostrati o inseriti, e il pannello dice "2 items hidden from the AI". Un risultato il cui segnaposto è stato modificato dal modello fino a renderlo irriconoscibile viene mostrato così com'è, contrassegnato da "⚠ placeholder changed". Le voci dell'elenco del gergo con un valore nascosto non vengono inviate. Ogni tipo si può disattivare. Vengono trovate anche le forme a larghezza piena (`zhang＠example.com`, `１３８…`), e un valore o un'espressione possono essere spezzati da un a capo. Riconosce valori formattati come email, numeri e chiavi; non può riconoscere nomi o indirizzi (aggiungili come parole tue), né lettere simili di altri alfabeti. Si applica alle richieste al tuo servizio di IA; `@agent` (con la pagina di Chrome che porta con sé), i plugin che recuperano dati da un sito web (`@stock`) o ne aprono uno (`@x`) e le estensioni script inviano il testo così come è stato digitato. Nella configurazione: `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- La voce viene registrata solo mentre tieni premuto ⌥ destro e viene riconosciuta sul Mac; il testo riconosciuto viene inviato solo nei comandi sopra indicati, quando premi il tasto azione.
- Il metodo di inserimento legge il testo degli appunti una volta, solo quando premi ⌃V o ⌘V in un comando; i contenuti che i gestori di password contrassegnano come nascosti non vengono letti. Il testo viene prima mostrato nel comando e, di nuovo, viene inviato solo quando premi il tasto azione. Le versioni recenti di macOS chiedono se AllInOneIME può leggere gli appunti: consentilo. Per non sentirti chiedere ogni volta, imposta il permesso di incollare di AllInOneIME su consenti sempre in Impostazioni di Sistema → Privacy e sicurezza.
- Nei campi password macOS passa alla propria tastiera (U.S. o ABC) e torna indietro quando li lasci. Ogni volta che l'app in cui scrivi attiva l'inserimento sicuro, AllInOneIME non compone testo e non può registrare: i tasti entrano così come digitati. E mentre il sistema è in inserimento sicuro (campi password, Inserimento sicuro da tastiera di Terminale, ecc.), nulla viene inviato all'IA.
- `@note` e `@reminder` non passano dall'IA: AllInOneIME consegna il testo solo a Note e Promemoria su questo Mac, e interpreta anche l'ora del promemoria sul Mac (se quelle app lo sincronizzano con gli altri tuoi dispositivi dipende dai loro account, come iCloud). Quindi funzionano anche durante l'inserimento sicuro. `@note` verso una cartella scrive un file su questo Mac (che si sincronizza se la cartella si sincronizza, come una cartella di iCloud Drive o di Obsidian Sync). `@note` verso Notion invia la nota a Notion (api.notion.com, con il token della tua integrazione, conservato nel portachiavi), e solo in quel caso: non durante l'inserimento sicuro.
- `@reportissue` (e "Report an Issue…") non invia nulla da solo: apre nel browser la pagina di GitHub per una nuova issue con il titolo che hai digitato e le versioni, le lingue, il tipo di fornitore e i conteggi indicati sopra, mostrati prima nel pannello dei candidati. Nulla arriva a GitHub finché non fai clic su Submit lì.
- `@open` cerca solo su questo Mac. Ricorda ciò che hai aperto con esso (gli ultimi 200 elementi), nelle preferenze proprie del metodo di inserimento (non in config.json), per elencarli per primi.
- Per "Add App…" in Settings → Apps, il metodo di inserimento conserva i bundle ID delle ultime 12 app in cui hai digitato, nelle sue preferenze; nient'altro su di esse.
- `@question` ricorda le tue ultime 5 domande con le risposte e quando sono state fatte, solo su questo Mac (a meno che tu non scelga di sincronizzarle tramite iCloud, vedi sopra), in `~/Library/Application Support/AllInOneIME/recent-questions.json` (leggibile solo dal tuo account utente), per elencarle sotto `@question`; una risposta salvata viene mostrata da lì senza andare online. Non viene conservato nulla durante l'inserimento sicuro, e le domande fatte sul testo selezionato non vengono conservate affatto (la loro risposta riguarda la selezione, che finirebbe sul disco). Disattivare "Remember recent questions" in Settings → General le elimina anche; disattivarla da Settings → Assistant (`rememberQuestions` nella configurazione) le conserva, così che si possa annullare esattamente. "Clear" le elimina.
- Per elencare le tue note, il pannello della barra dei menu conserva l'identificativo (quello della nota in Note, il percorso del file o l'indirizzo della pagina di Notion) e la prima riga (fino a 80 caratteri) delle ultime 30 note salvate con `@note`, nelle preferenze proprie del metodo di inserimento, anche quando il pannello è disattivato. Aprire il pannello non interroga mai Notion.
- `@py` e `@js` vengono eseguiti solo quando premi il tasto azione, e solo con codice che hai digitato o incollato tu: le risposte dell'IA e l'output di altri comandi non vengono mai eseguiti come codice. `@py` usa il `python3` del tuo Mac, che può leggere e scrivere file e andare online come fa in Terminale; `@js` viene eseguito in un processo separato che non può leggere file, accedere alla rete né eseguire altri programmi. Nessuno dei due viene eseguito durante l'inserimento sicuro.
- Controllo degli aggiornamenti: una volta al giorno (a meno che "Check for updates automatically" sia disattivato), AllInOneIME scarica https://allinoneime.com/update.json e la sua firma; la richiesta non contiene identificativi né nulla di ciò che hai digitato. Un aggiornamento viene scaricato, dalla release di GitHub, solo quando fai clic su Update.
- Sorgenti delle estensioni: git viene eseguito sul tuo Mac, come te, solo per le sorgenti che hai aggiunto: un recupero (fetch) al giorno per quelle che si controllano da sole (nessuno per una fissata), e quando fai clic su Check Now, Update o Re-clone. Comunica solo con l'host del repository, autenticato dalla tua configurazione di git e SSH; niente di ciò che digiti viaggia con lui.
- Sincronizzazione tramite iCloud (disattivata per impostazione predefinita): solo nel tuo iCloud Drive, `~/Library/Mobile Documents/com~apple~CloudDocs/AllInOneIME/`, che Apple sincronizza con gli altri tuoi Mac; nulla va ai server dello sviluppatore. Cosa ci va: `settings.json` (le impostazioni sincronizzate, ciascuna con il momento in cui è cambiata e un id casuale per ogni Mac; i tuoi comandi personalizzati, anche quelli che eseguono un programma, che comunque vengono eseguiti solo quando li scegli), `jargon.txt` (il tuo elenco del gergo), `rime/` (la copia, per ogni Mac, di ciò che il pinyin ha appreso, nient'altro della cartella di Rime: le tue frasi personalizzate e le impostazioni di Rime restano sul Mac) e, solo se li attivi, le parole che nascondi all'IA (in `settings.json`) e `questions.json` (domande recenti e risposte, leggibile solo dal tuo account utente). Disattivare questi due li lascia in iCloud finché non li rimuovi ("Remove from iCloud…" sotto ciascun interruttore). Mai: chiavi API, token o password, sorgenti delle estensioni, cartelle delle estensioni e plugin, le app senza errori di battitura, le app recenti, lo stato delle finestre, gli interruttori della sincronizzazione. iCloud Drive è cifrato end-to-end solo con la Protezione avanzata dei dati. Il registro di ciò che questo Mac ha sincronizzato è in `~/Library/Application Support/AllInOneIME/iCloudSync/state.json`.
- I log non registrano ciò che digiti. Per ogni metodo di inserimento di terze parti, macOS avverte che lo sviluppatore può accedere a tutto ciò che digiti con questa sorgente di input; è un avviso generico del sistema.

## Sviluppo

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

`make selftest` e `make realtest` non dipendono dalle tue impostazioni. L'autotest usa una propria configurazione (Amazon Bedrock con il profilo AWS e la regione presi dalla tua, tutto il resto ai valori predefiniti); il test in un'app reale imposta il fornitore su Bedrock mentre è in esecuzione e poi rimette il tuo. Ciò che non possono controllare in quel momento viene saltato, non dato per fallito: i controlli live di Bedrock senza credenziali per quel profilo, e tutto ciò che si digita con l'inserimento sicuro attivo (schermo bloccato, un campo password). L'ultima riga conta i controlli superati, falliti e saltati; solo i fallimenti fanno fallire l'esecuzione, e un'esecuzione con controlli saltati termina con INCOMPLETE, o con SKIPPED quando non è stato eseguito nulla che digiti (BLOCKED: il test in un'app reale è partito con lo schermo bloccato), mai con PASSED.

Il testo dell'interfaccia si scrive come `tr("中文", "English")`: cinese semplificato e inglese vengono dal codice, le altre lingue dai String Catalog, `Core/Resources/Localizable.xcstrings` per il testo del core e `Resources/Localizable.xcstrings` per quello dell'app (uniti e compilati in ogni app dal Makefile con `xcstringstool` di Xcode), con il testo inglese come chiave e `%@` per ogni interpolazione. Dopo aver aggiunto o modificato del testo, esegui `make strings` (fino ad allora `make test` fallisce; il testo degli autotest, in `*SelfTest.swift`, non è per i traduttori). Dove uno stesso testo inglese significa due cose (`make strings` le segnala, e `make strings-check` fallisce), dai a una delle due una chiave propria, un breve nome puntato che dica dove o come viene usata: `tr("删除", "Remove", key: "remove.delete")`; il suo inglese è il valore inglese della chiave nel catalogo. Aggiungere una lingua significa aggiungere la sua colonna al catalogo: le traduzioni revisionate, un file JSON per lingua (`"core\t<key>"` o `"app\t<key>"` → la sua traduzione), entrano con `Scripts/import-translations.py <folder>`, che non tocca mai l'inglese e rifiuta una traduzione i cui segnaposto non sono quelli della sua chiave. I testi propri del core prendono il codice della lingua dell'interfaccia e la cercano allo stesso modo (`InterfaceText.lookup`, che ogni app imposta: i suoi bundle `.lproj` su macOS; altrove `StringCatalog` legge le tabelle del catalogo).

Struttura del codice: la radice è l'app per macOS; `Core/` è il core condiviso da tutte le piattaforme, un pacchetto Swift a sé (si compila e si testa da solo, su macOS, Linux e Windows); `Windows/` è l'inizio dell'app per Windows.

- `Core/Sources/AllInOneIMECore`: client Bedrock, SigV4, prompt, la macchina a stati di inserimento a due livelli (compresi i comandi @ e il gesto vocale); nessuna dipendenza da AppKit
- `Core/Sources/AllInOneIMEText`: il testo dell'interfaccia e la sua lingua (`UIString`, `InterfaceText`, `InterfaceLanguage` e `StringCatalog`, che legge il catalogo dove non ci sono bundle `.lproj`); tutti i link che aprono le impostazioni (`AllInOneIMECore` lo riesporta)
- `Core/Sources/AllInOneIMEQuickJS`: QuickJS-ng (i suoi sorgenti C in `Core/Sources/CQuickJS`), che esegue il JavaScript dei plugin e di `@js` dove non c'è JavaScriptCore (Windows, Linux, Android)
- `Core/Sources/AllInOneIMERime`: wrapper di librime
- `Core/Sources/AllInOneIMECLI`: la riga di comando, `allinoneime-cli` (`make cli`), avviata dal `main` proprio di ogni piattaforma
- `Sources/AllInOneIMEMac`: ciò che ha solo il Mac (layout di tastiera, firma del codice, Spotlight, AppleScript, l'installazione degli aggiornamenti), e `Platform.mac`
- `Sources/AllInOneIME`: il metodo di inserimento InputMethodKit, il pannello dei candidati, la finestra delle impostazioni, il riconoscimento vocale
- `Sources/AllInOneIMESettings`: il launcher "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: "Install AllInOneIME" sull'immagine disco: installa, aggiorna e disinstalla

I pacchetti lingua hanno una propria libreria, separata da quella dei plugin: il repository [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), servito su https://languages.allinoneime.com/, firmato con una propria chiave. `make pack` crea l'archivio; viene pubblicato lì come asset di release (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), e `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` scrive lì `packs.json` e lo firma in `packs.json.sig` con la chiave dei pacchetti lingua presa dal portachiavi (`allinoneime-languages-signing`). L'app legge https://languages.allinoneime.com/packs.json, verifica la firma, poi dimensione e SHA-256 dell'archivio. Per provare un pacchetto da un server locale: `--test-key` firma con una chiave di prova, e `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Pubblicare una versione (l'aggiornamento integrato legge https://allinoneime.com/update.json, firmato con la chiave propria dei rilasci):

1. Aumenta la versione (`AppVersion.swift` e i tre Info.plist; `AppVersionTests` controlla che coincidano) e aggiorna i registri delle modifiche.
2. `make dmg NOTARY_PROFILE=<profile>`: `build/AllInOneIME-<version>.dmg` con il suo `.sha256`, e `build/AllInOneIME-<version>-update.zip` (le due app, come le contiene il programma di installazione dell'immagine disco). Le app e l'immagine sono firmate con il certificato Developer ID Application del portachiavi, e l'immagine viene autenticata con quel profilo di portachiavi di `xcrun notarytool` e pinzata (stapled). Il metodo di inserimento porta con sé il profilo di provisioning Developer ID (`Resources/Signing/AllInOneIME-DeveloperID.provisionprofile`, `DIST_PROFILE`), che gli concede gli entitlement del portachiavi; la build si ferma se il profilo non elenca il certificato di firma, non copre tutti i dispositivi o ha meno di 30 giorni di validità (`Scripts/profile-entitlements.sh`), o se alla firma mancano gli entitlement del portachiavi, ed esegue una volta il metodo di inserimento firmato (macOS termina quello il cui profilo non va bene). Anche un `DIST_PROFILE` vuoto la ferma: una release senza gli entitlement perderebbe di vista ogni chiave passata in Portachiavi iCloud. Il profilo elenca solo i due certificati Developer ID G1: prima di firmare con un altro (G2), crea nel portale per sviluppatori un nuovo profilo che lo elenchi (a mano: la firma dell'App ID non è lasciata a Xcode) e fanne il commit.
3. Carica entrambi nella release GitHub `v<version>` e pubblicala.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"` (una o due frasi ciascuno): scrive `site/public/update.json` (versione, build e macOS minimo letti dalle app, indirizzo, dimensione e SHA-256 del file, indirizzo delle note di rilascio e riepilogo) e lo firma in `update.json.sig` con la chiave del portachiavi login (`allinoneime-releases-signing`; macOS può chiedere di consentire l'accesso). Fai il commit di entrambi.
5. Pubblica il sito (`cd site && npx wrangler@4 deploy`), solo quando i file della release sono scaricabili: le app controllano una volta al giorno, e `AllInOneIME --check-update` mostra ciò che vedono.

L'app verifica la firma del manifesto con la chiave pubblica integrata prima di leggerlo, non installa mai una versione che non sia più recente, scarica solo via https da allinoneime.com o dai file delle release GitHub del repository, e installa l'archivio solo quando dimensione e SHA-256 corrispondono al manifesto, i bundle ID, le versioni e le firme del codice di entrambe le app sono corretti e il nuovo metodo di inserimento si avvia. Il metodo di inserimento passa poi il compito al proprio eseguibile come aiutante (`--apply-update`), che aspetta che si chiuda, scambia le app come fa il programma di installazione (le vecchie messe da parte, ripristinate se qualcosa non va) e registra la nuova. Per provarlo con un server locale: `make update-test`, oppure `--test-key` con `Scripts/build-update-manifest.swift` e `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`.

Il bundle ID è ancora `com.aipinyin.inputmethod.AIPinyin`: macOS lo usa per ricordare la sorgente di input aggiunta e il permesso del microfono, quindi cambiarlo significherebbe aggiungere di nuovo il metodo di inserimento e concedere di nuovo il permesso.

## Licenza

Copyright © 2026 MicroZ LLC. Sorgente disponibile secondo la [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): usalo, leggilo, modificalo e condividilo per qualsiasi scopo tranne un prodotto concorrente. Ogni versione passa ad Apache-2.0 due anni dopo il suo rilascio. Le versioni fino alla 0.6.1 sono state rilasciate sotto GPL-3.0 e restano disponibili con quella licenza.

I componenti di terze parti (librime e i suoi plugin sotto BSD-3-Clause; gli script Lua di rime-ice e il pacchetto lingua cinese sotto GPL-3.0) sono elencati in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
