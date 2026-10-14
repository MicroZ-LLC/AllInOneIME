<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · [繁體中文](README_zh-TW.md) · [日本語](README_ja.md) · [한국어](README_ko.md) · **Français** · [Deutsch](README_de.md) · [Español](README_es.md) · [Português (Brasil)](README_pt-BR.md) · [Italiano](README_it.md) · [Русский](README_ru.md) · [Tiếng Việt](README_vi.md) · [ไทย](README_th.md) · [Bahasa Indonesia](README_id.md) · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · [Türkçe](README_tr.md)

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="Icône d'AllInOneIME">

# AllInOneIME

### Des commandes d'IA dans chaque champ de texte de votre Mac.

Tapez `@improve`, `@translate` ou `@question` dans n'importe quelle application, appuyez sur ⏎ et choisissez le résultat.<br>
Pas de copier-coller dans une fenêtre de chat, pas de changement d'application. Votre propre fournisseur d'IA, vos propres clés.

[![Version](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#installation)
[![Puce Apple et Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#installation)
[![Licence : FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![Téléchargements](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[Télécharger](https://allinoneime.com/download)** · **[Site web](https://allinoneime.com)** · **[Documentation](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[Extensions](../extensions.md)**

[Utilisation](#utilisation) · [Commandes](#commandes--bêta) · [Vos propres commandes](#vos-propres-commandes) · [Langues](#saisie-et-traduction) · [Voix](#saisie-vocale) · [Installation](#installation) · [Confidentialité](#confidentialité)

<br>

<img src="../en/demo.png" width="820" alt="@translate et une phrase, puis ⏎ : une ligne en espagnol, en français et en allemand">

</div>

*Ceci est une traduction du README anglais ; en cas de divergence, c'est la version anglaise qui fait foi.*

> [!NOTE]
> AllInOneIME n'est pas encore notarié par Apple : la première fois, autorisez-le dans System Settings → Privacy & Security → Open Anyway (Réglages Système → Confidentialité et sécurité → Ouvrir quand même). Téléchargez-le uniquement depuis les [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) ou depuis [allinoneime.com](https://allinoneime.com).

Une méthode de saisie pour macOS qui met des commandes d'IA dans chaque champ de texte. Commencez une phrase par `@` et appuyez sur ⏎ quand vous avez terminé : `@improve` peaufine ce que vous avez écrit et propose quelques reformulations, `@translate` le traduit dans les langues de votre choix, `@question` pose une question, `@claude` confie la tâche à Claude Code, et `@open` trouve des fichiers et des applications ou ouvre une adresse web. Vous pouvez aussi maintenir la touche ⌥ de droite et parler. Sans `@`, vos frappes vont à l'application comme d'habitude. Elle tape aussi le chinois (pinyin, fondé sur Rime et rime-ice), le français, le coréen (hangeul) et le hindi (devanagari à partir de lettres latines), et exécute vos propres scripts comme commandes @.

![@improve et une phrase approximative, puis ⏎ : des versions peaufinées, plus des reformulations](../en/improve.png)

Pour plus de détails (chaque commande et chaque réglage, le dépannage de l'installation, la confidentialité), consultez le [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Réalisé par [Weijian Zhang](https://weijianz.com) chez MicroZ LLC.

## Utilisation

Sans `@`, elle se fait oublier : en anglais, les lettres sont tapées directement et ⏎ est la touche Retour ; rien ne part en ligne. Une nouvelle installation écrit en anglais ; pour taper aussi le chinois (pinyin), le français, le coréen ou le hindi, ajoutez-le dans les réglages (voir [Saisie et traduction](#saisie-et-traduction)).

| Touche | Ce qu'elle fait |
|---|---|
| Taper du pinyin, Espace / chiffres | En mode chinois : choisir les mots, comme dans toute méthode de saisie pinyin |
| `@` (en début de phrase) | Ouvre la liste des commandes : les plus utilisées récemment d'abord, 5 à la fois, défilement avec ↑↓, la molette ou le trackpad ; ou tapez des lettres pour en trouver une (d'abord les noms qui commencent par elles, puis ceux qui les contiennent). ⏎, Tab, Espace ou un chiffre la sélectionne |
| ⏎ | Exécute la commande. Fonctionne même si le pinyin n'est pas encore choisi : il est choisi d'abord, comme avec Espace |
| Espace, ⏎ / chiffres | Une fois les résultats affichés : insère celui qui est en surbrillance / numéroté ; 0 est l'original |
| ⌘C | Copie le résultat en surbrillance (pour `@open`, le chemin) ; le panneau des candidats reste ouvert |
| ⌃V | Dans une commande (par ex. après `@improve `) : ajoute le texte du presse-papiers après ce que vous avez tapé au lieu de le coller dans l'application. Plusieurs lignes n'en font plus qu'une, jusqu'à 2000 caractères à la fois (`@note` conserve les retours à la ligne et en accepte jusqu'à 20000). Fonctionne dans toutes les applications ; sans commande, la touche va à l'application comme d'habitude |
| ⌘V | Comme ⌃V, mais certaines applications gèrent ⌘V elles-mêmes (des terminaux comme Ghostty, iTerm2 et Terminal, ainsi que Notes) et collent dans l'application comme d'habitude ; utilisez ⌃V dans celles-ci |
| Échap, ⌫ | Retour à la phrase pour continuer à la modifier ; il suffit de taper pour la poursuivre |
| Appui bref sur Maj | Avec plusieurs langues de saisie : la suivante, dans leur ordre (anglais → chinois → français → …, puis retour à la première) |
| Maintenir ⌥ de droite | Parlez, relâchez pour arrêter. Dans la langue que vous tapez (anglais, chinois, français, coréen ou hindi). Dans une commande, le texte s'ajoute après elle ; sinon il est inséré directement |

## Commandes @ (bêta)

| Commande | Ce qu'elle fait |
|---|---|
| `@improve` | Peaufinage : 1–3 sont trois versions dans la langue de la phrase, à partir de 4 les styles de reformulation (ajoutés et ordonnés dans les réglages), 0 est l'original. Pas de traduction ; avec "@improve also translates" (@improve traduit aussi) activé, elle fonctionne comme `@translate @improve` |
| `@translate` | Traduit dans les langues que vous avez ajoutées (réglages → Translate, glissez pour réordonner), une ligne chacune, trois versions s'il n'y en a qu'une ; la langue de la phrase elle-même est ignorée. `@translate @improve` ensemble traduit et reformule en une seule requête |
| `@question` | Pose une question ; la réponse apparaît dans les candidats, ⏎ ou Espace l'insère, ⌘C la copie |
| `@claude` | Confie la tâche à Claude Code : en arrière-plan par défaut, avec une notification une fois terminée (cliquez dessus pour ouvrir la session dans Terminal et continuer), ou consultez `@tasks`. Elle utilise votre propre Claude Code (la commande `claude`) avec sa propre connexion et ses propres réglages. Désactivez "@claude runs in the background" (@claude s'exécute en arrière-plan) dans les réglages pour l'ouvrir dans Terminal comme avant. La première fois qu'elle ouvre Terminal, macOS demande si AllInOneIME peut contrôler Terminal : cliquez sur OK |
| `@tasks` | Liste les tâches Claude en arrière-plan (en cours / terminée / vous attend) avec leurs dernières réponses ; ⏎ en ouvre une dans Terminal, ⌘C copie la réponse |
| `@settings` | Ouvre immédiatement la fenêtre des réglages (il suffit de la choisir) |
| `@open` | Liste les fichiers, dossiers et applications correspondants pendant la frappe (Spotlight). Plusieurs mots-clés séparés par des espaces fonctionnent : chacun doit figurer dans le chemin, au moins un dans le nom (le nom d'un dossier standard vaut pour son contenu : `downloads pdf` trouve les PDF du dossier Downloads (Téléchargements)). Les applications et les dossiers standard se trouvent aussi par leur nom chinois, et une interface en chinois les affiche ainsi. Ce que vous avez ouvert avec `@open` vient en premier, puis les applications et ces dossiers, puis les fichiers récemment utilisés ou modifiés ; quand les noms trouvent deux fichiers ou moins et aucune application ni aucun de ces dossiers, les fichiers de votre dossier de départ sont aussi cherchés par contenu, ces lignes étant marquées "content" (contenu) ; quand il n'y a rien d'autre, ⏎ les liste pour que vous choisissiez au lieu d'ouvrir le premier. Avec une adresse web (`github.com`, `localhost:3000`, `https://…`), la première ligne est "open in the browser" (ouvrir dans le navigateur) et le contenu n'est pas cherché ; un fichier portant exactement ce nom (par exemple `MANIFEST.in`) vient en premier. Un texte commençant par `~/` ou `/` est un chemin : Tab le complète et entre dans les dossiers ; ⏎ ouvre, ⌘C copie le chemin |
| `@note` | Enregistre le texte dans l'app Notes, dans un dossier nommé AllInOneIME (créé s'il n'existe pas) ; rien n'est inséré. Le texte collé conserve ses retours à la ligne, jusqu'à 20000 caractères |
| `@reminder` | Ajoute un rappel dans l'app Rappels, dans une liste nommée AllInOneIME. Écrivez l'heure dans le texte ; elle est interprétée sur le Mac, et une ligne montre ce qui a été compris : ⏎ ou Espace l'ajoute, Échap revient à la modification. Avec une heure, il sonne à ce moment-là ; avec seulement une date, il dure toute la journée |
| `@calculate` | Calcule sur ce Mac ; le résultat apparaît dans les candidats, ⏎ ou Espace l'insère : `@calculate 23*17` → `391`. Fonctionne aussi au milieu d'une phrase : `@reply the total is @calculate 23*17 dollars` |
| `@py` | Exécute une ligne de Python (le `python3` du Mac) et insère le résultat : la valeur de la dernière expression du code, par ex. `@py 2**100`, `@py import math; math.sqrt(2)`, ou sinon ce qu'il a affiché. Non proposée sans `python3` (les outils en ligne de commande de Xcode le fournissent) |
| `@js` | Exécute une ligne de JavaScript et insère la même chose : la valeur de la dernière expression ou ce que `console.log` a affiché, par ex. `@js [1, 2, 3].map(x => x * 2)`. Elle utilise JavaScriptCore, intégré à macOS, donc rien à installer ; elle ne peut ni lire de fichiers, ni accéder au réseau, ni lancer d'autres programmes |
| `@imessage` | Envoie un iMessage : tapez un nom, un numéro de téléphone ou une adresse e-mail (un nom chinois aussi par son pinyin, complet ou par les initiales) et choisissez le destinataire dans le panneau des candidats (ceux à qui vous avez écrit récemment viennent en premier ; un numéro ou une adresse complète fonctionne aussi), puis écrivez le message (les commandes qu'il contient, comme `@stock AAPL`, s'exécutent d'abord). ⏎ affiche "Send to Alex (…): message" dans le panneau, un second ⏎ l'envoie, Échap revient à la modification ; rien n'est tapé dans le champ de texte. La première fois, macOS demande si AllInOneIME peut accéder à Contacts et contrôler Messages : cliquez sur OK pour les deux |

Exemple : `@q` ⏎, tapez `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ enregistre une note. `@reminder call Bob tomorrow at 3pm` ⏎, vérifiez l'heure comprise, puis ⏎ à nouveau pour l'ajouter. Une fois la commande choisie, vous pouvez aussi maintenir ⌥ de droite et parler. En mode chinois, `@open` et `@calculate` passent momentanément aux lettres latines et reviennent au chinois quand vous avez fini.

Le code de `@py` et `@js` se tape en lettres latines, et la ponctuation pleine chasse (du mode chinois) devient ASCII ; écrivez-le sur une seule ligne, avec `;` entre les instructions. Il s'exécute dans un processus séparé, arrêté au bout de 10 secondes ou à tout moment avec Échap ; en cas d'erreur, la première ligne de l'erreur s'affiche, par ex. `ZeroDivisionError: division by zero`. Une sortie de plusieurs lignes est insérée telle qu'affichée ; dans un terminal, elle est insérée sur une seule ligne (un terminal exécute chaque ligne qu'on lui donne). Un terminal intégré à un éditeur (VS Code, Cursor, JetBrains) ne se distingue pas de l'éditeur lui-même, donc là, la sortie de plusieurs lignes de n'importe quelle commande est insérée telle quelle. Les deux fonctionnent aussi dans la phrase d'une autre commande : `@reply the answer is @py 2**100` ; mettez entre guillemets le code contenant des espaces : `@question explain @py "sum(x * x for x in range(10))"`. L'inverse n'est pas vrai : le code de `@py` et `@js` s'exécute toujours exactement comme vous l'avez tapé, et les `@commands` qu'il contient ne s'exécutent pas d'abord.

![Taper @ ouvre la liste des commandes ; @question plus une question, puis ⏎ pour la réponse](../en/commands.png)

![@open trouve les applications pendant la frappe ; en commençant par /, c'est un chemin : le dossier est listé, Tab complète](../en/open.png)

Quand `@` n'est pas suivi d'une commande, comme dans `@john`, le `@` est inséré comme d'habitude, donc mentionner des personnes avec @ dans les applications de messagerie fonctionne toujours. `@question`, `@improve` et `@translate` n'envoient à votre propre Bedrock que lorsque vous appuyez sur la touche d'action ; `@open` ne cherche que sur ce Mac ; `@note` et `@reminder` ne vont qu'à Notes et Rappels sur ce Mac ; `@claude` utilise le Claude Code installé sur votre Mac (la commande `claude`) et son propre compte, et il vous demande d'abord, comme d'habitude, avant de modifier des fichiers ou d'exécuter des commandes. Sans Claude Code installé, `@claude` n'est pas proposée. `@imessage` ne lit que les Contacts de ce Mac (noms, numéros de téléphone, adresses e-mail), ne passe jamais par l'IA, et c'est Messages qui envoie le message ; sans l'app Messages, elle n'est pas proposée.

`@calculate` fonctionne sur ce Mac, hors ligne : `+ - * /` (aussi `× ÷`), `^` ou `**` pour les puissances, les parenthèses, les pourcentages (`50%` vaut 0,5, `200*5%` vaut 10 ; comme sur une calculatrice, un pourcentage ajouté ou soustrait porte sur ce qui précède : `100+10%` vaut 110, `100-10%` vaut 90), les fonctions `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` est en base 10, les angles sont en radians, `round(x, 2)` garde deux décimales) et les constantes `pi` (`π`) et `e`. Les chiffres et signes pleine chasse fonctionnent aussi. L'arithmétique est exacte en décimal, donc `0.1+0.2` donne `0.3` ; les résultats ont au plus 15 chiffres significatifs, et les nombres entiers jusqu'à 38 chiffres sont écrits en entier (`2^100` → `1267650600228229401496703205376`).

### Notes et rappels

`@note` crée une nouvelle note ; sa première ligne en est le titre. Après avoir copié du texte, ⌃V après `@note ` (ou ⌘V, hors des terminaux) l'enregistre avec ses retours à la ligne, affichés sous forme de ↵ dans la commande. Si vous quittez le champ de texte (clic ailleurs, changement d'application) ou appuyez sur ⇧⏎ (insérer tel quel) avant qu'une note contenant des retours à la ligne soit enregistrée, elle n'est pas tapée dans l'application (dans un terminal, chaque ligne s'exécuterait comme une commande) : elle va dans le presse-papiers à la place ("The note wasn't saved; its text is on the clipboard"). Une note d'une seule ligne est insérée telle quelle.

`@reminder` comprend des expressions de temps comme `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (le 1er du mois), `end of the year` (ainsi que des expressions en chinois). Le jour et l'heure peuvent être séparés (`tomorrow call Bob at 5`) ; les semaines commencent le lundi. Une heure sans am ni pm (`at 5`) désigne la prochaine occurrence, jamais entre minuit et 6 h ; une heure déjà passée aujourd'hui désigne demain, mais une partie de la journée encore en cours (`this afternoon`, `tonight`) désigne aujourd'hui, toute la journée ; une date déjà passée cette année désigne celle de l'année prochaine. Un rappel écrit pour se répéter (`standup every Monday at 9`) est ajouté une seule fois, pour la prochaine occurrence : les mots restent dans le titre et la ligne indique "once only" (une seule fois). La ligne de confirmation montre l'heure comprise, par ex. "tomorrow 3:00 PM" (selon le réglage 12/24 heures du Mac) ; si elle est fausse, Échap revient au texte. S'il ne contient ni heure ni date, le rappel n'en a pas ("no date").

`@stock` et les commandes similaires à l'intérieur de ces deux-là ne s'exécutent pas : le texte est enregistré tel qu'écrit (taper `@` à cet endroit n'ouvre pas la liste des commandes). La première fois, macOS demande si AllInOneIME peut contrôler Notes (`@note`) ou accéder à Rappels (`@reminder`) : autorisez-le. Si vous ne l'avez pas fait, autorisez AllInOneIME dans Réglages Système → Confidentialité et sécurité → Automatisation (Notes) ou → Rappels. Quand un enregistrement échoue (faute d'autorisation, par exemple), la notification en indique la raison et le texte revient dans la commande, pour le corriger et le renvoyer ; quand vous devez d'abord corriger quelque chose (une autorisation, un compte), il est aussi mis dans le presse-papiers (aller dans Réglages Système retire le focus du champ de texte). Si vous êtes passé à un autre champ de texte ou tapez autre chose, il va dans le presse-papiers à la place ("Not saved; the text is on the clipboard.").

### Vos propres commandes

Dans les réglages, sous "Custom @ Commands" (commandes @ personnalisées), cliquez sur "Add Command…" (ajouter une commande) : donnez-lui un nom et choisissez ce qu'elle fait (une instruction pour l'IA, un programme, un programme dans Terminal, ou une page web), ou partez d'un exemple. Vos commandes viennent après celles intégrées ; les noms ne contiennent que des lettres latines et ne peuvent pas reprendre le nom d'une commande intégrée ; elles fonctionnent à partir de la phrase suivante. Elles sont conservées dans `customCommands` dans le fichier de configuration (`~/.config/allinoneime/config.json`), que vous pouvez aussi modifier :

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | Ce qu'elle fait |
|---|---|
| `prompt` | Envoie à l'IA avec `prompt` comme instruction ; la réponse apparaît dans les candidats, à insérer ou copier (⌘C) |
| `run` | Exécute `argv` en arrière-plan ; ce qu'il affiche apparaît dans les candidats (plusieurs lignes sont insérées telles qu'affichées, dans un terminal sur une seule ligne). En cas d'erreur, sa dernière ligne s'affiche |
| `terminal` | Exécute `argv` dans une nouvelle fenêtre de Terminal ; rien n'est inséré |
| `link` | Place le texte dans l'adresse web `url` et l'ouvre dans le navigateur par défaut ; rien n'est inséré |

- `{input}` devient ce que vous avez écrit après la commande, et reste toujours dans l'unique argument où il se trouve : aucun shell n'intervient. Pour un shell, dites-le explicitement, comme `sh` ci-dessus (`zsh -c`).
- `stdin` : ce qui est envoyé sur l'entrée standard du programme, `{input}` y étant aussi remplacé.
- L'`url` d'un `link` doit commencer par `https://`, avec `{input}` une seule fois, après le `?` ou le `#` ; le texte est encodé (une espace devient `%20`, un retour à la ligne `%0A`), 4000 caractères au plus.
- `run` et `terminal` tapent en lettres latines par défaut (comme `@open` ; en mode chinois, le chinois revient ensuite), et la ponctuation pleine chasse devient ASCII. Définissez `"ascii": false` pour garder le texte tel que tapé.
- Les programmes s'exécutent dans votre dossier de départ avec le PATH de votre shell de connexion (les installations Homebrew, pyenv et nvm sont donc trouvées). `run` arrête un programme au bout de 10 secondes (`timeoutSeconds`) ou quand il affiche trop de choses ; Échap l'arrête à tout moment.
- `summary` est la description dans la liste des commandes (facultative).
- Quand le programme indiqué dans `argv` est introuvable (par exemple, pas de `python3`), la commande n'est pas proposée et `@python …` est inséré comme du texte ; une fois le programme installé, la commande apparaît dans le champ de texte suivant.

`run` et `terminal` exécutent du code sur votre Mac : n'ajoutez que des commandes que vous avez écrites et en lesquelles vous avez confiance. Elles aussi ne s'exécutent que lorsque vous appuyez sur la touche d'action, et jamais pendant une saisie sécurisée.

### Extensions par script

Ajoutez vos propres commandes @ sous forme de programmes : un script dans n'importe quel langage (bash, Python, Node, Swift, …) avec quelques lignes de métadonnées dans ses commentaires. Placez-le dans `~/.config/allinoneime/extensions`, ou dans un dossier que vous ajoutez sous Settings → Custom Commands → Script Extensions. Les Script Commands de Raycast fonctionnent telles quelles, et les dossiers qui en contiennent déjà sont trouvés avec Spotlight.

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh` devient `@flights`. Écrivez ses arguments après, séparés par des virgules : `@flights beijing, new york` l'exécute avec `beijing` et `new york` comme `$1` et `$2` (les virgules en trop restent dans le dernier) ; un argument obligatoire laissé vide indique ce qui manque au lieu de lancer le script. Ce qu'il affiche est utilisé selon son `output` :

| `output` | Ce qui se passe |
|---|---|
| `insert` (par défaut) | Tout, et chaque ligne, à insérer |
| `show` | Affiché dans le panneau au fil de l'exécution (progression) ; rien n'est inséré. Quittez le champ et il continue en arrière-plan (jusqu'à quatre à la fois) |
| `list` | Une liste au format JSON Script Filter d'Alfred, réexécutée pendant la frappe ; choisir une ligne insère, ouvre (une adresse web, un fichier ou un dossier ; jamais quelque chose qui s'exécuterait), copie ou lance une deuxième étape |
| `silent` | Sa dernière ligne près du curseur ; rien n'est inséré |

Une commande peut aussi ne prendre aucune entrée (`input none` : ⏎ sur son nom l'exécute), s'exécuter en arrière-plan (`background`) et vous prévenir quand elle a terminé (le panneau de la barre des menus la liste entre-temps), afficher un `status` à côté de son nom dans la liste des commandes, ou demander confirmation d'abord (`confirm`). Elle s'exécute dans son propre dossier avec le PATH de votre shell de connexion et des variables `ALLINONEIME_*` : la langue de l'interface et de saisie, l'application dans laquelle vous tapez, le texte. Un **bundle** est un dossier avec un `extension.json` qui nomme ses commandes : elles partagent du code et des préférences, que les réglages affichent (les mots de passe vont dans le trousseau). Les réglages listent chaque commande avec un interrupteur, ainsi que les scripts écartés et la raison.

Les modes de Raycast se transposent ainsi : `fullOutput` → `show`, `compact` et `silent` → `silent`, `inline` avec `refreshTime` → un statut. Le protocole complet se trouve dans [docs/extensions.md](../extensions.md) ; [Examples/extensions](../../Examples/extensions) en contient un de chaque sorte. Les extensions exécutent du code sur votre Mac : utilisez celles en lesquelles vous avez confiance. Elles ne s'exécutent que lorsque vous les lancez (un statut ou une liste pendant la frappe), jamais pendant une saisie sécurisée, et s'arrêtent quand la méthode de saisie se ferme.

### Plugins

Les plugins sont des commandes `@` prêtes à l'emploi pour des usages dont tout le monde n'a pas besoin, comme `@stock AAPL 600519 700` pour des cours de bourse. Une fois installés, ils fonctionnent comme n'importe quelle commande ; "Plugins" dans les réglages montre ce qui est installé et où chacun envoie votre texte, et permet de les supprimer. Les plugins sont du JavaScript exécuté dans un processus séparé : ils ne peuvent joindre que les sites web qu'ils déclarent (HTTPS), et ne peuvent ni lire de fichiers ni lancer d'autres programmes. "Browse Library…" (parcourir la bibliothèque) sous Plugins dans les réglages les installe depuis la [bibliothèque de plugins](https://github.com/MicroZ-LLC/AllInOneIME-plugins) : elle montre quels sites web un plugin contacte avant de l'installer ; l'index de la bibliothèque est signé et chaque fichier doit lui correspondre. Une version plus récente fait apparaître un bouton "Update" (mettre à jour) ; rien ne se met à jour tout seul. Vos propres plugins vont dans `~/.config/allinoneime/plugins/` ("Open Plugins Folder") : des plugins locaux, jamais écrasés par la bibliothèque. Les plugins de type "Link" n'exécutent aucun code : ils placent le texte dans une adresse web et l'ouvrent dans le navigateur, comme `@x nice weather today`, qui ouvre l'éditeur de publication de X avec le texte déjà rempli ; c'est à vous de publier sur la page. La bibliothèque en compte quatre (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` convertit les devises : `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, sur une ligne avec la date du taux (taux fournis par ExchangeRate-API). Pour en écrire un : [docs/plugins.md](../plugins.md).

Les commandes qui récupèrent quelque chose (plugins et programmes) fonctionnent aussi au milieu d'une phrase : `@reply tell her @stock AAPL is up today`. Les commandes intérieures s'exécutent d'abord, leur sortie prend leur place, et la commande extérieure travaille sur le résultat. L'argument est le mot qui suit la commande, plus les codes en majuscules ou les nombres qui le suivent immédiatement (`@stock AAPL TSLA`, `@stock 600519 700`) ; un mot en minuscules y met fin (`@stock SNDK is good to buy` recherche SNDK). Les guillemets le délimitent exactement : `@stock "aapl tsla"`. `@calculate` fonctionne aussi au milieu d'une phrase ; son argument est toute l'expression qui la suit, espaces compris, jusqu'au texte suivant : `@reply the total is @calculate 23 * 17 dollars`. À l'intérieur de `@claude` et des commandes de terminal, elles ne s'exécutent pas : celles-ci reçoivent le texte tel qu'écrit (taper `@` à cet endroit n'ouvre pas la liste des commandes).

### Touche d'action

⏎ par défaut ; modifiez-la sous "Action key" (touche d'action) dans les réglages (`actionKey` dans la configuration) : ⏎, Tap ⌥ (appui bref sur ⌥, d'un côté ou de l'autre : appuyer et relâcher aussitôt ; maintenir ⌥ de droite sert toujours à parler), ⌥Espace, ou Espace (appuyez encore une fois sur Espace après avoir choisi les mots ; deux fois en mode anglais). Quelle que soit la touche d'action, les commandes @ s'exécutent aussi avec ⏎. Si ⌥Espace est déjà un raccourci pour Alfred, Raycast ou un outil similaire, ceux-ci le reçoivent en premier.

## Panneau de la barre des menus

<img src="../en/panel-swipe.png" width="520" alt="Le panneau de la barre des menus : verre dépoli, avec les notes, les rappels et les tâches Claude sur des cartes ; une ligne balayée vers la gauche affiche son bouton Remove">

Cliquez sur l'icône d'AllInOneIME dans la barre des menus (le symbole ∞ avec un curseur, sans cadre ; celui avec un cadre est la source de saisie) et le panneau se déroule en dessous ; un clic ailleurs le ferme :

- Notes : les notes enregistrées avec `@note`, les 5 plus récentes ; cliquez sur l'une d'elles pour l'ouvrir dans Notes.
- Reminders (rappels) : les rappels non terminés de la liste AllInOneIME de Rappels (`@reminder` ajoute à cette liste), les plus proches d'abord, 8 affichés ; cliquez sur le cercle pour en cocher un, ou sur le titre pour ouvrir Rappels.
- Claude Tasks (tâches Claude) : comme `@tasks`, les tâches Claude en arrière-plan (ce que `@claude` délègue), jusqu'à 30, 5 affichées à la fois : faites défiler pour en voir plus, ou cherchez dans leurs titres et réponses avec le champ de recherche ; avec leur progression et la première ligne de la dernière réponse ; cliquez sur l'une d'elles pour l'ouvrir dans Terminal et continuer.

Balayez une ligne (une note, un rappel ou une tâche) vers la gauche avec deux doigts pour afficher son bouton Remove (supprimer), ou jusqu'au bout pour la supprimer d'un coup ; avec une souris, faites un clic droit dessus. La suppression la retire seulement du panneau : la note reste dans Notes, le rappel dans Rappels (non terminé), la tâche dans Claude Code.

L'en-tête affiche les compteurs (comme "2 reminders · 1 task running" ; les tâches qui vous attendent sont comptées à part, comme "1 waiting for you") et un bouton d'actualisation. Il ne prend jamais le focus à l'application dans laquelle vous tapez : cocher un rappel ou actualiser laisse cette application au premier plan ; seul le champ de recherche des tâches Claude, une fois cliqué, prend le clavier. L'icône est affichée par défaut ; désactivez-la sous "Menu Bar Panel" dans les réglages.

Ce qu'il lit, et quand :

- Notes : la liste est le registre propre du panneau (conservé même quand il est fermé), et Notes n'est jamais lancée : c'est seulement quand Notes est déjà ouverte, et qu'AllInOneIME a été autorisé auparavant à la contrôler, que le panneau y vérifie les titres modifiés et les notes supprimées.
- Rappels : la liste AllInOneIME est lue quand le panneau se déroule, toutes les 60 secondes et quand les rappels changent. Le panneau ne fait jamais demander l'accès par macOS de lui-même : si macOS ne vous l'a pas encore demandé, il affiche "Allow Access to Reminders" (autoriser l'accès à Rappels), et seul ce bouton le demande ; si vous avez refusé, il affiche "Open System Settings" (ouvrir Réglages Système).
- Tâches Claude : le panneau n'exécute `claude agents` que lorsqu'il est déroulé : une fois à l'ouverture, lors d'une actualisation, et quand `@claude` délègue une tâche ; et toutes les 15 secondes tant qu'une tâche n'est pas terminée, plus du tout une fois qu'elles le sont toutes. Les dernières réponses sont lues à la fin des transcriptions de Claude Code sur ce Mac (`~/.claude/projects`), et seulement quand une transcription a changé.
- Quand il est fermé, rien de tout cela ne s'exécute ; il se contente de garder un registre des notes que `@note` enregistre.

## Saisie et traduction

Dans les réglages :

- **Langues de saisie** : de une à cinq parmi l'anglais, le chinois (pinyin), le français, le coréen et le hindi, ajoutées avec + (toujours présent ; grisé à cinq). Une nouvelle installation commence avec l'anglais seulement. Les nouveaux champs de texte commencent dans la première ; un appui bref sur Maj passe à la suivante, dans leur ordre ; avec une seule, Maj ne change rien.
  - **Le français** se tape avec sa propre disposition de clavier : AZERTY, sauf si vous en choisissez une autre sur sa carte. Ses touches mortes (^, ¨, `, ´, ~) composent aussi à partir de celle-ci.
  - **Le coréen** se tape en hangeul avec la disposition 2-set (Dubeolsik), chaque syllabe étant assemblée au fil de la frappe (g k s → 한) ; Maj donne ㄲ ㄸ ㅃ ㅆ ㅉ et ㅒ ㅖ.
  - **Le hindi** : tapez les mots tels qu'ils se prononcent en lettres latines et obtenez du devanagari (namaste → नमस्ते). Les mots courants sont orthographiés comme on les écrit en hindi ; sinon Espace insère la première graphie, un chiffre une autre, ⏎ les lettres telles que tapées, et "." le danda (।).
  - Le nom d'une commande, le texte de `@open` et le code (`@py`, `@js`) se tapent en lettres latines quelle que soit la langue ; celle-ci revient après la commande.
  - `@improve` garde une phrase coréenne, hindie ou française dans sa propre langue, et `@translate` la traduit dans vos langues (le français est distingué de l'anglais lorsqu'il fait partie de vos langues de saisie).
- **Packs de langue** : l'application est fournie avec l'anglais (et le français, qui n'a besoin que de la disposition de macOS). Le chinois, le coréen et le hindi sont des packs que vous téléchargez en les ajoutant : ajouter le chinois (pinyin) télécharge ses dictionnaires (environ 34 Mo, 125 Mo une fois décompressés) avec une barre de progression, et le pinyin fonctionne dès que c'est terminé, sans redémarrage ; le pack du coréen (sa table de touches et la façon dont les jamo forment des syllabes) et celui du hindi (ses lettres et ses mots courants) pèsent quelques kilo-octets. Un pack ne contient que des données (dictionnaires, tables et schémas, jamais de code), il est listé dans un index signé et vérifié par rapport à son SHA-256 avant d'être utilisé, comme les plugins. La carte de chaque langue affiche son pack (version, taille, provenance) avec Delete… (supprimer), et retirer la langue propose de supprimer son pack. Une mise à jour depuis la version 0.6.1 ou antérieure conserve le chinois sans téléchargement : l'installeur garde les dictionnaires fournis avec l'ancienne version.
- **Pinyin approximatif** (avec la saisie du chinois) : des sons que vous ne distinguez pas, tapés d'une façon ou de l'autre, par ex. z ↔ zh, n ↔ l, in ↔ ing. Sur la page Input, choisissez Chinese (pinyin) dans la barre des langues de saisie, activez "Fuzzy pinyin" et choisissez les paires ; les dictionnaires sont redéployés en une seconde ou deux. Cela écrit `rime_ice.custom.yaml` dans le dossier utilisateur de Rime, et jamais par-dessus un fichier à vous qui s'y trouverait.
- **Traduction (@translate)** : ajoutez les langues vers lesquelles traduire (espagnol, français, allemand, japonais, coréen, chinois, hindi, bengali, tamoul et les autres grandes langues de l'Inde…) et faites-les glisser pour les ordonner. Le hindi tapé en lettres latines ("aap kaise ho") revient en devanagari. `@translate` écrit une ligne dans chacune, dans cet ordre (trois versions s'il n'y en a qu'une) ; la langue de la phrase elle-même est ignorée. Une nouvelle installation traduit vers la première langue des langues préférées de votre Mac qui n'est pas l'anglais ; avec l'anglais seul, `@translate` ouvre cette page pour en ajouter une.
- **Dispositions de clavier** : le français se tape avec la disposition choisie sur sa carte (`keyboardLayouts` dans la configuration). Pour les autres langues, sous la méthode de saisie, macOS conserve votre dernière disposition latine (AZERTY, QWERTZ, espagnol, U.S. International…), vous tapez donc comme d'habitude, `@` compris là où votre disposition le place, et les touches mortes composent aussi dans le texte d'une commande (⌥E puis E → é, ^ puis e → ê). Les dispositions sans lettres latines (russe, hindi InScript) ne peuvent pas être utilisées sous une méthode de saisie : passez-y avec ⌃Espace, ou collez (⌃V) ou dictez du texte dans une commande.
- `@improve` peaufine et reformule sans traduire ; `@translate @improve` ensemble traduit et reformule en une seule requête. Activez "@improve also translates" dans les réglages pour que `@improve` fasse toujours cela.

## Styles de reformulation

Après les lignes 1–3 viennent les reformulations, **dans la langue que vous avez tapée** : des reformulations en anglais pour l'anglais, en chinois pour le chinois. Choisissez celles que vous voulez dans les réglages :

- Polish (peaufiner) : même ton, plus naturel
- Concise (concis)
- Formal (formel) : pour les managers et les clients
- Casual (décontracté)
- Tactful (diplomate)
- Jargon : le jargon d'Amazon en anglais (bandwidth, circle back…), le jargon des grandes entreprises tech en chinois. Les mauvaises nouvelles sont minimisées, par ex. "this is a blocker bug" → "Oh! Looks like your team has the bandwidth to fix this minor issue!"

Les reformulations qui ne changent que la ponctuation ou répètent une autre ligne ne sont pas affichées.

### Liste de jargon (vos propres termes)

Jargon n'a pas de liste de termes intégrée. Vous pouvez préparer la vôtre (par exemple, les expressions qu'utilise votre équipe), et le modèle privilégie ses termes. Dans les candidats, la ligne Jargon précise le sens des termes qu'elle a utilisés.

La liste est un fichier texte avec un terme par ligne, éventuellement suivi de sa signification, séparée par "=", deux-points ou une tabulation (vous pouvez copier deux colonnes d'un tableur et les coller). Les lignes commençant par `#` sont des commentaires :

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

Sous "Rewrite Styles → Jargon list" dans les réglages, cliquez sur "New" (nouveau) pour créer une liste vide à l'emplacement `~/.config/allinoneime/jargon.txt` et l'ouvrir ; si vous avez déjà un fichier de liste, cliquez sur "Choose File…" (choisir un fichier) pour l'utiliser là où il se trouve (`jargonFile` dans la configuration). Les modifications s'appliquent immédiatement. Seuls les 150 premiers termes sont lus. Avec "Jargon" coché, la liste est envoyée à Bedrock avec chaque requête.

<img src="../en/panel-dark.png" width="420" alt="Le panneau des candidats en mode sombre">

## Saisie vocale

<img src="../en/voice.png" width="340" alt="Maintenez ⌥ de droite pour parler">

Maintenez ⌥ de droite et parlez ; quand vous relâchez, le texte est inséré. Il est reconnu dans la langue que vous tapez (anglais, chinois, français, coréen ou hindi). Si vous tapez d'abord une commande (par ex. `@improve `, `@question `) puis parlez, le texte s'ajoute après la commande et ⏎ l'exécute ; vous pouvez aussi appuyer sur ⏎ sans relâcher ⌥ de droite pour l'exécuter dès que vous avez fini. La parole est reconnue sur le Mac par la reconnaissance vocale intégrée de macOS (SpeechAnalyzer), et aucun son n'est envoyé en ligne ; il faut macOS 26 ou une version ultérieure.

La première fois :

- macOS demande si AllInOneIME peut utiliser le micro. Vous pouvez aussi cliquer à l'avance sur "Allow Microphone" (autoriser le micro) dans les réglages.
- Si ce Mac n'a pas encore le modèle vocal de cette langue, il est téléchargé une fois, automatiquement. Vous pouvez aussi le télécharger dans les réglages.

L'enregistrement ne commence qu'après avoir maintenu la touche environ 0,2 s, si bien qu'un appui bref sur ⌥ de droite n'allume pas le micro (avec la touche d'action réglée sur "Tap ⌥", un appui bref exécute l'action). Si vous appuyez sur une autre touche en la maintenant (un raccourci avec ⌥, ⌥←), cela compte comme un raccourci et rien n'est enregistré non plus. Appuyer sur n'importe quelle autre touche pendant l'enregistrement l'annule.

## Installation

Il faut macOS 14 ou une version ultérieure pour l'utiliser, et macOS 26 ou ultérieur pour la saisie vocale. L'installeur est universel : il fonctionne sur les Mac à puce Apple et Intel. Pour l'instant, il n'a été testé que sur macOS 27 sur puce Apple (la version Intel seulement par son autotest sous Rosetta).

1. Téléchargez `AllInOneIME-<version>.dmg` depuis les [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) (uniquement depuis là) et ouvrez-le.
2. Double-cliquez sur "Install AllInOneIME" qu'il contient et cliquez sur Install. La méthode de saisie va dans `~/Library/Input Methods` et "AllInOneIME Settings" dans `~/Applications`. Pour cet utilisateur seulement ; aucun mot de passe administrateur n'est nécessaire.
3. L'installeur n'est pas encore notarié par Apple, donc macOS ne peut pas vérifier qui l'a fait, et la première fois il indique ne pas pouvoir vérifier "Install AllInOneIME" : cliquez sur Terminé (Annuler sur macOS 14), ouvrez Réglages Système → Confidentialité et sécurité, cliquez sur Ouvrir quand même vers le bas, et confirmez. L'installeur de chaque nouvelle version demande cela une fois.

Ensuite, AllInOneIME est activé et figure dans vos sources de saisie ; passez-y avec Ctrl+Espace (la touche 🌐 ne change de source que si "Appuyer sur la touche 🌐 pour" est réglé sur "Changer de source de saisie" dans Réglages Système → Clavier). Si l'installeur vous dit de l'ajouter à la main, ce Mac ne permet pas aux programmes de l'activer ; ajoutez-le donc vous-même une fois : Réglages Système → Clavier → Saisie de texte → Sources de saisie → Modifier… → + (en bas à gauche) → Anglais → AllInOneIME (il tape aussi le pinyin une fois que vous avez ajouté le chinois sous Input dans ses réglages).

Si Ctrl+Espace ne vous amène pas à AllInOneIME, ou s'il revient à U.S. au bout d'un moment, relancez l'installeur : il rajoute AllInOneIME à vos sources de saisie.

Pour mettre à jour, réinstallez depuis l'image disque de la nouvelle version, sans désinstaller d'abord ; les réglages, la liste de jargon et les mots appris sont conservés. Avant de mettre à niveau, lisez le [journal des modifications](../../CHANGELOG.md) : il contient les changements de chaque version et les notes de mise à niveau.

Si vous aviez installé AIPinyin (l'ancien nom d'AllInOneIME), installez simplement : l'ancienne AIPinyin.app et son lanceur de réglages sont supprimés, et l'entrée de vos sources de saisie prend le nouveau nom, sans qu'il faille la rajouter. Les réglages, la liste de jargon et les mots appris sont déplacés vers les nouveaux dossiers (`~/.config/allinoneime` et autres) au premier lancement, et chaque ancien dossier est remplacé par un lien vers le nouveau.

Pour désinstaller, ouvrez "Install AllInOneIME" et cliquez sur Uninstall…. Les réglages et les mots appris sont conservés.

### Compiler depuis les sources

La compilation nécessite Xcode 26 ou une version ultérieure, car la saisie vocale utilise le SDK de macOS 26.

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` télécharge librime et les dictionnaires rime-ice et les vérifie, compile, puis installe aux mêmes emplacements, en l'ajoutant à vos sources de saisie de la même façon. L'application installée ainsi n'a pas de dictionnaires chinois (ils constituent le pack de langue chinois) : une installation qui les avait les garde comme pack ; sinon `make install-pack` installe le pack à partir des dictionnaires du dépôt local, sans téléchargement. `make status` affiche la version installée (`version:`) et indique si elle figure dans vos sources de saisie (`listed:`). Pour désinstaller : `make uninstall`.

## Configurer l'IA

Les traductions et reformulations utilisent votre propre fournisseur d'IA, et les coûts sont imputés à votre compte : Amazon Bedrock dans votre compte AWS par défaut, ou l'API Claude, Gemini ou un service compatible OpenAI (voir "Autres fournisseurs d'IA" ci-dessous).

### Amazon Bedrock

1. Activez Bedrock dans la console AWS et assurez-vous de pouvoir utiliser le modèle choisi. Le modèle par défaut est Claude Haiku 4.5 ; la première fois que vous utilisez un modèle Anthropic, vous remplissez une fois un formulaire de cas d'usage.
2. Créez une clé d'accès avec l'autorisation `bedrock:InvokeModelWithResponseStream` et placez-la dans un profil de `~/.aws/credentials`. Seules ces clés statiques sont prises en charge pour l'instant, pas SSO ni assume-role.
3. Ouvrez "AllInOneIME Settings" : vous le trouverez dans Spotlight ou dans Applications, ou ouvrez-le depuis l'icône de la méthode de saisie dans la barre des menus → Settings…. Choisissez le profil, la région et le modèle, puis cliquez sur "Test Connection" (tester la connexion). "Language" (langue), en haut de la fenêtre des réglages, peut être English ou Chinese ; par défaut ("System"), il suit le système (chinois si le chinois précède l'anglais dans les langues préférées du système, anglais sinon). La fenêtre des réglages, les indications du panneau des candidats et le menu de saisie le suivent tous.

<img src="../en/settings.png" width="420" alt="La fenêtre des réglages">

### Autres fournisseurs d'IA : API Claude, Gemini, services compatibles OpenAI

Vous n'avez pas besoin d'AWS : choisissez-en un sous "AI Provider" (fournisseur d'IA) dans les réglages, collez une clé d'API, cliquez sur "Save" (enregistrer), puis sur "Test Connection".

| Fournisseur | Modèle par défaut | Clé d'API |
|---|---|---|
| API Claude | `claude-haiku-5-5` (le plus rapide et le moins cher ; Sonnet 5.5 et Opus 5.5 sont plus soigneux mais plus lents et plus chers) | [Claude Console](https://platform.claude.com) |
| API Gemini | `gemini-3.8-flash` | Google AI Studio |
| Compatible OpenAI | `gpt-6-luna` d'OpenAI (ou `gpt-5.4-mini`) ; "Common Services…" (services courants) propose DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter et Ollama sur ce Mac : en choisir un remplit son URL de base, puis saisissez son modèle | La clé du service ; réglez la Base URL sur son adresse, par ex. `https://api.deepseek.com/v1`, ou `http://localhost:11434/v1` pour Ollama sur ce Mac |

- Les clés d'API sont conservées dans le trousseau du système, jamais dans le fichier de configuration. S'il n'y en a pas, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (ou `GOOGLE_API_KEY`) et `OPENAI_API_KEY` de votre shell sont utilisées.
- "Thinking" (réflexion) est réglé sur bas par défaut : la méthode de saisie attend à chaque phrase, et moins de réflexion va plus vite. Choisissez "Not set" (non défini) pour les modèles qui ne le prennent pas en charge.
- Avec Claude Opus 5.5 ou Sonnet 5.5, les requêtes incluent le repli en cas de refus de l'API Claude (`fallbacks: "default"`) : quand un classificateur de sécurité refuse, le serveur réessaie avec un autre modèle.
- Dans le fichier de configuration : `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), et `model`, `baseURL`, `effort` et `temperature` sous `anthropic`, `gemini` et `openai` (ceux qui ne sont pas définis prennent les valeurs par défaut).

Tous les réglages sont stockés dans `~/.config/allinoneime/config.json` ; après une modification, la traduction suivante utilise les nouveaux réglages, sans redémarrage. Les clés les plus récentes :

| Clé | Ce qu'elle fait | Par défaut |
|---|---|---|
| `inputLanguages` | Langues de saisie, de une à cinq, la première étant celle par défaut : `"en"` anglais, `"zh"` chinois (pinyin), `"fr"` français, `"ko"` coréen, `"hi"` hindi, par ex. `["en", "zh"]`, `["fr", "en", "ko"]`. Le chinois, le coréen et le hindi fonctionnent une fois leur pack installé | `["en"]` (nouvelle installation) |
| `keyboardLayouts` | La disposition de clavier avec laquelle une langue de saisie se tape, par son code (seulement le français pour l'instant) : `{"fr": "com.apple.keylayout.French-PC"}` | Français : `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | Les langues vers lesquelles `@translate` traduit, dans l'ordre : `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | `@improve` traduit aussi (comme `@translate @improve`) | `false` |
| `voiceInput` | Maintenir ⌥ de droite pour parler | `true` |
| `actionKey` | Touche d'action : `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Espace), `"space"` (Espace) | `"enter"` |
| `uiLanguage` | Langue de l'interface (fenêtre des réglages, indications du panneau des candidats, menu) : `"zh"`, `"en"` | `null` (suit le système) |
| `rewriteStyles` | Styles de reformulation : `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, par ex. `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | Votre propre fichier de liste de jargon | `null` (soit `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | L'icône de la barre des menus et son panneau déroulant | `true` |
| `fuzzyPinyin` | Paires de pinyin approximatif : `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |

## Confidentialité

- La frappe (anglais et pinyin) et les calculs de `@calculate` sont entièrement locaux. Ce n'est que lorsque vous appuyez sur la touche d'action avec `@improve`, `@translate` ou `@question` que la phrase est envoyée au fournisseur d'IA que vous avez choisi (votre propre Bedrock, ou le service dont vous avez ajouté la clé). Avec "Jargon" coché et une liste de jargon définie, la liste est envoyée avec elle.
- Avec AllInOneIME Cloud, la phrase passe par le serveur du développeur vers un fournisseur de modèles (actuellement via OpenRouter) : le serveur ne conserve que des compteurs, jamais le texte. La connexion ne conserve que votre adresse e-mail.
- La voix n'est enregistrée que pendant que vous maintenez ⌥ de droite et elle est reconnue sur le Mac ; le texte reconnu n'est envoyé que dans les commandes ci-dessus, lorsque vous appuyez sur la touche d'action.
- La méthode de saisie lit le texte du presse-papiers, une fois, uniquement lorsque vous appuyez sur ⌃V ou ⌘V dans une commande ; le contenu que les gestionnaires de mots de passe marquent comme masqué n'est pas lu. Le texte est d'abord affiché dans la commande et, là encore, n'est envoyé que lorsque vous appuyez sur la touche d'action. Les versions récentes de macOS demandent si AllInOneIME peut lire le presse-papiers : autorisez-le. Pour ne plus avoir à répondre à chaque fois, réglez l'autorisation de collage d'AllInOneIME sur toujours autoriser dans Réglages Système → Confidentialité et sécurité.
- Dans les champs de mot de passe, macOS passe à son propre clavier (U.S. ou ABC) et revient quand vous les quittez. Chaque fois que l'application dans laquelle vous tapez active la saisie sécurisée, AllInOneIME ne compose pas de texte et ne peut pas enregistrer : les touches passent telles quelles. Et tant que le système est en saisie sécurisée (champs de mot de passe, Entrée clavier sécurisée de Terminal, etc.), rien n'est envoyé à l'IA.
- `@note` et `@reminder` ne passent pas par l'IA : AllInOneIME ne remet le texte qu'à Notes et Rappels sur ce Mac, et interprète aussi l'heure du rappel sur le Mac (que ces applications le synchronisent avec vos autres appareils dépend de leurs comptes, comme iCloud). Elles fonctionnent donc aussi pendant une saisie sécurisée.
- `@open` ne cherche que sur ce Mac. Elle mémorise ce que vous avez ouvert avec elle (les 200 derniers éléments), dans les préférences propres à la méthode de saisie (pas dans config.json), pour les lister en premier.
- Pour lister vos notes, le panneau de la barre des menus conserve l'identifiant et la première ligne (jusqu'à 80 caractères) des 30 dernières notes enregistrées avec `@note`, dans les préférences propres à la méthode de saisie, y compris quand le panneau est désactivé.
- `@py` et `@js` ne s'exécutent que lorsque vous appuyez sur la touche d'action, et uniquement sur du code que vous avez tapé ou collé vous-même : les réponses de l'IA et la sortie des autres commandes ne sont jamais exécutées comme du code. `@py` utilise le `python3` de votre Mac, qui peut lire et écrire des fichiers et accéder à Internet comme il le fait dans Terminal ; `@js` s'exécute dans un processus séparé qui ne peut ni lire de fichiers, ni accéder au réseau, ni lancer d'autres programmes. Aucune des deux ne s'exécute pendant une saisie sécurisée.
- Les journaux n'enregistrent pas ce que vous tapez. Pour toute méthode de saisie tierce, macOS avertit que le développeur peut accéder à tout ce que vous tapez avec cette source de saisie ; c'est un avertissement générique du système.

## Développement

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

Organisation du code :

- `Sources/AllInOneIMECore` : client Bedrock, SigV4, prompts, la machine à états de saisie à deux niveaux (y compris les commandes @ et le geste vocal) ; aucune dépendance à AppKit
- `Sources/AllInOneIMERime` : enveloppe de librime
- `Sources/AllInOneIME` : la méthode de saisie InputMethodKit, le panneau des candidats, la fenêtre des réglages, la reconnaissance vocale
- `Sources/AllInOneIMESettings` : le lanceur "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller` : "Install AllInOneIME" sur l'image disque : installe, met à jour et désinstalle

Les packs de langue ont leur propre bibliothèque, distincte de celle des plugins : le dépôt [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), servi à l'adresse https://languages.allinoneime.com/, signé avec sa propre clé. `make pack` construit l'archive ; elle y est publiée comme fichier de release (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), et `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` y écrit `packs.json` et le signe dans `packs.json.sig` avec la clé des packs de langue tirée du trousseau (`allinoneime-languages-signing`). L'application lit https://languages.allinoneime.com/packs.json, vérifie la signature, puis la taille et le SHA-256 de l'archive. Pour essayer un pack depuis un serveur local : `--test-key` signe avec une clé de test, puis `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

L'identifiant de bundle est toujours `com.aipinyin.inputmethod.AIPinyin` : macOS s'en sert pour mémoriser la source de saisie ajoutée et l'autorisation du micro, donc le changer obligerait à rajouter la méthode de saisie et à accorder de nouveau l'autorisation.

## Licence

Copyright © 2026 MicroZ LLC. Source disponible sous la [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2) : utilisez-le, lisez-le, modifiez-le et partagez-le pour tout usage, sauf pour un produit concurrent. Chaque version passe sous Apache-2.0 deux ans après sa sortie. Les versions jusqu'à la 0.6.1 ont été publiées sous GPL-3.0 et restent disponibles sous cette licence.

Les composants tiers (librime et ses plugins sous BSD-3-Clause ; les scripts Lua de rime-ice et le pack de langue chinois sous GPL-3.0) sont listés dans [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
