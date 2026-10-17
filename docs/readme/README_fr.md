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
[![Notarisé par Apple](https://img.shields.io/badge/Apple-notarized-0a84ff?logo=apple&logoColor=white)](#installation)
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
> Depuis la version 0.6.3, AllInOneIME est signé avec un Developer ID et notarié par Apple : plus besoin de l'autoriser dans System Settings → Privacy & Security (Réglages Système → Confidentialité et sécurité). Après une mise à jour depuis une version antérieure, macOS demande une fois votre mot de passe de session pour chaque clé qu'AllInOneIME a enregistrée dans le trousseau : saisissez-le et cliquez sur "Always Allow" (Toujours autoriser). Téléchargez AllInOneIME uniquement depuis les [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) ou depuis [allinoneime.com](https://allinoneime.com).

Une méthode de saisie pour macOS qui met des commandes d'IA dans chaque champ de texte. Commencez une phrase par `@` et appuyez sur ⏎ quand vous avez terminé : `@improve` peaufine ce que vous avez écrit et propose quelques reformulations, `@translate` le traduit dans les langues de votre choix, `@question` pose une question, `@claude` confie la tâche à Claude Code, et `@open` trouve des fichiers et des applications ou ouvre une adresse web. Vous pouvez aussi maintenir la touche ⌥ de droite et parler. Sans `@`, vos frappes vont à l'application comme d'habitude. Elle tape aussi le chinois (pinyin, fondé sur Rime et rime-ice), le français, le coréen (hangeul) et le hindi (devanagari à partir de lettres latines), et exécute vos propres scripts comme commandes @.

![@improve et une phrase approximative, puis ⏎ : des versions peaufinées, plus des reformulations](../en/improve.png)

Pour plus de détails (chaque commande et chaque réglage, le dépannage de l'installation, la confidentialité), consultez le [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Réalisé par [Weijian Zhang](https://weijianz.com) chez MicroZ LLC.

## Utilisation

Sans `@`, elle se fait oublier : en anglais, les lettres sont tapées directement et ⏎ est la touche Retour ; rien ne part en ligne. Une nouvelle installation écrit en anglais ; pour taper aussi le chinois (pinyin), le français, le coréen ou le hindi, ajoutez-le dans les réglages (voir [Saisie et traduction](#saisie-et-traduction)).

| Touche | Ce qu'elle fait |
|---|---|
| Taper du pinyin, Espace / chiffres | En mode chinois : choisir les mots, comme dans toute méthode de saisie pinyin |
| `@` (en début de phrase) | Ouvre la liste des commandes : les plus utilisées récemment d'abord, 5 à la fois, défilement avec ↑↓, la molette ou le trackpad ; ou tapez des lettres pour en trouver une (d'abord le nom tapé en entier, puis les noms qui commencent par elles, puis ceux qui les contiennent). ⏎, Tab, Espace ou un chiffre la sélectionne |
| ⏎ | Exécute la commande. Fonctionne même si le pinyin n'est pas encore choisi : il est choisi d'abord, comme avec Espace |
| Espace, ⏎ / chiffres | Une fois les résultats affichés : insère celui qui est en surbrillance / numéroté ; 0 est l'original |
| ⌘C | Copie le résultat en surbrillance (pour `@open`, le chemin) ; le panneau des candidats reste ouvert |
| ⌃V | Dans une commande (par ex. après `@improve `) : ajoute le texte du presse-papiers après ce que vous avez tapé au lieu de le coller dans l'application. Plusieurs lignes n'en font plus qu'une, jusqu'à 2000 caractères à la fois (`@note` conserve les retours à la ligne et en accepte jusqu'à 20000). Fonctionne dans toutes les applications ; sans commande, la touche va à l'application comme d'habitude |
| ⌘V | Comme ⌃V, mais certaines applications gèrent ⌘V elles-mêmes (des terminaux comme Ghostty, iTerm2 et Terminal, ainsi que Notes) et collent dans l'application comme d'habitude ; utilisez ⌃V dans celles-ci |
| Échap, ⌫ | Retour à la phrase pour continuer à la modifier ; taper de la ponctuation ou des chiffres après les résultats la poursuit. Après un affinage : retour aux résultats d'avant |
| Des lettres, une fois les résultats de l'IA affichés | Une consigne de suivi, comme `shorter` : ⏎ affine les résultats (voir [Affiner les résultats](#affiner-les-résultats-nouveau)) |
| Clic sur une ligne | Dans le panneau des candidats : la choisit, comme son chiffre le ferait (un mot, une commande de la liste, un résultat, un fichier de `@open`, un destinataire, une ligne d'extension) ; la ligne sous le pointeur est en surbrillance. Le champ de texte garde le focus |
| Appui bref sur Maj | Avec plusieurs langues de saisie : la suivante, dans leur ordre (anglais → chinois → français → …, puis retour à la première) |
| Maintenir ⌥ de droite | Parlez, relâchez pour arrêter. Dans la langue que vous tapez (anglais, chinois, français, coréen ou hindi). Dans une commande, le texte s'ajoute après elle ; sinon il est inséré directement |

## Commandes @ (bêta)

| Commande | Ce qu'elle fait |
|---|---|
| `@improve` | Peaufinage : 1–3 sont trois versions dans la langue de la phrase, à partir de 4 les styles de reformulation (ajoutés et ordonnés dans les réglages), 0 est l'original. Pas de traduction ; avec "@improve also translates" (@improve traduit aussi) activé, elle fonctionne comme `@translate @improve` |
| `@translate` | Traduit dans les langues que vous avez ajoutées (réglages → Translate, glissez pour réordonner), une ligne chacune, trois versions s'il n'y en a qu'une ; la langue de la phrase elle-même est ignorée. `@translate @improve` ensemble traduit et reformule en une seule requête |
| `@question` | Pose une question ; la réponse apparaît dans les candidats, ⏎ ou Espace l'insère, ⌘C la copie. Sans rien tapé après, elle liste vos 5 dernières questions, les plus récentes d'abord ; taper filtre la liste (des mots n'importe où dans la question, sans tenir compte de la casse, en chinois aussi). Un chiffre, ↑↓ puis ⏎, ou un clic affiche aussitôt la réponse enregistrée d'une question, hors ligne, à insérer ou copier comme d'habitude ; R la repose pour obtenir une nouvelle réponse. Sans correspondance, ou si rien n'est choisi, ⏎ pose ce que vous avez tapé |
| `@claude` | Confie la tâche à Claude Code : en arrière-plan par défaut, avec une notification une fois terminée (cliquez dessus pour ouvrir la session dans Terminal et continuer), ou consultez `@tasks`. Elle utilise votre propre Claude Code (la commande `claude`) avec sa propre connexion et ses propres réglages. Désactivez "@claude runs in the background and notifies me" (@claude s'exécute en arrière-plan et me prévient) dans les réglages pour l'ouvrir dans Terminal comme avant. La première fois qu'elle ouvre Terminal, macOS demande si AllInOneIME peut contrôler Terminal : cliquez sur OK |
| `@tasks` | Liste les tâches Claude en arrière-plan (en cours / terminée / vous attend) avec leurs dernières réponses ; ⏎ en ouvre une dans Terminal, ⌘C copie la réponse |
| `@settings` | Ouvre immédiatement la fenêtre des réglages (il suffit de la choisir) |
| `@open` | Liste les fichiers, dossiers et applications correspondants pendant la frappe (Spotlight). Plusieurs mots-clés séparés par des espaces fonctionnent : chacun doit figurer dans le chemin, au moins un dans le nom (le nom d'un dossier standard vaut pour son contenu : `downloads pdf` trouve les PDF du dossier Downloads (Téléchargements)). Les applications et les dossiers standard se trouvent aussi par leur nom chinois, et une interface en chinois les affiche ainsi. Ce que vous avez ouvert avec `@open` vient en premier, puis les applications et ces dossiers, puis les fichiers récemment utilisés ou modifiés ; quand les noms trouvent deux fichiers ou moins et aucune application ni aucun de ces dossiers, les fichiers de votre dossier de départ sont aussi cherchés par contenu, ces lignes étant marquées "content" (contenu) ; quand il n'y a rien d'autre, ⏎ les liste pour que vous choisissiez au lieu d'ouvrir le premier. Avec une adresse web (`github.com`, `localhost:3000`, `https://…`), la première ligne est "open in the browser" (ouvrir dans le navigateur) et le contenu n'est pas cherché ; un fichier portant exactement ce nom (par exemple `MANIFEST.in`) vient en premier. Un texte commençant par `~/` ou `/` est un chemin : Tab le complète et entre dans les dossiers ; ⏎ ouvre, ⌘C copie le chemin |
| `@note` | Enregistre le texte dans l'app Notes, dans un dossier nommé AllInOneIME (créé s'il n'existe pas) ; rien n'est inséré. Le texte collé conserve ses retours à la ligne, jusqu'à 20000 caractères |
| `@reminder` | Ajoute un rappel dans l'app Rappels, dans une liste nommée AllInOneIME. Écrivez l'heure dans le texte ; elle est interprétée sur le Mac, et une ligne montre ce qui a été compris : ⏎ ou Espace l'ajoute, Échap revient à la modification. Avec une heure, il sonne à ce moment-là ; avec seulement une date, il dure toute la journée |
| `@calculate` | Calcule sur ce Mac ; le résultat apparaît dans les candidats, ⏎ ou Espace l'insère : `@calculate 23*17` → `391`. Fonctionne aussi au milieu d'une phrase : `@reply the total is @calculate 23*17 dollars` |
| `@py` | Exécute une ligne de Python (le `python3` du Mac) et insère le résultat : la valeur de la dernière expression du code, par ex. `@py 2**100`, `@py import math; math.sqrt(2)`, ou sinon ce qu'il a affiché. Non proposée sans `python3` (les outils en ligne de commande de Xcode le fournissent) |
| `@js` | Exécute une ligne de JavaScript et insère la même chose : la valeur de la dernière expression ou ce que `console.log` a affiché, par ex. `@js [1, 2, 3].map(x => x * 2)`. Elle utilise JavaScriptCore, intégré à macOS, donc rien à installer ; elle ne peut ni lire de fichiers, ni accéder au réseau, ni lancer d'autres programmes |
| `@reportissue` | Signale un problème : ouvre dans votre navigateur la page de GitHub pour un nouveau ticket (issue), avec ce que vous avez tapé après la commande comme titre, et "What happened / What you expected" (ce qui s'est passé / ce que vous attendiez) à remplir. Elle ajoute les versions de l'app et de macOS, l'architecture de votre Mac, les langues de l'interface et de saisie, les packs de langue installés, le type de fournisseur d'IA (et le modèle, s'il est public ; sinon "custom"), la touche d'action, et combien de commandes personnalisées, de plugins et d'extensions vous avez, jamais leurs noms, votre texte, vos chemins ni vos clés. ⏎ (ou votre touche d'action) affiche d'abord tout cela dans le panneau des candidats ; ⏎ à nouveau, ou un clic sur la ligne, ouvre la page, où vous le relisez et cliquez sur Submit (avec votre compte GitHub) ; Échap revient en arrière. Aussi dans le menu de saisie ("Report an Issue…") et dans Settings → About |
| `@imessage` | Envoie un iMessage : tapez un nom, un numéro de téléphone ou une adresse e-mail (un nom chinois aussi par son pinyin, complet ou par les initiales) et choisissez le destinataire dans le panneau des candidats (ceux à qui vous avez écrit récemment viennent en premier ; un numéro ou une adresse complète fonctionne aussi), puis écrivez le message (les commandes qu'il contient, comme `@stock AAPL`, s'exécutent d'abord). ⏎ affiche "Send to Alex (…): message" dans le panneau, un second ⏎ l'envoie, Échap revient à la modification ; rien n'est tapé dans le champ de texte. La première fois, macOS demande si AllInOneIME peut accéder à Contacts et contrôler Messages : cliquez sur OK pour les deux |

Exemple : `@q` ⏎, tapez `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ enregistre une note. `@reminder call Bob tomorrow at 3pm` ⏎, vérifiez l'heure comprise, puis ⏎ à nouveau pour l'ajouter. Une fois la commande choisie, vous pouvez aussi maintenir ⌥ de droite et parler. En mode chinois, `@open` et `@calculate` passent momentanément aux lettres latines et reviennent au chinois quand vous avez fini.

Le code de `@py` et `@js` se tape en lettres latines, et la ponctuation pleine chasse (du mode chinois) devient ASCII ; écrivez-le sur une seule ligne, avec `;` entre les instructions. Il s'exécute dans un processus séparé, arrêté au bout de 10 secondes ou à tout moment avec Échap ; en cas d'erreur, la première ligne de l'erreur s'affiche, par ex. `ZeroDivisionError: division by zero`. Une sortie de plusieurs lignes est insérée telle qu'affichée ; dans un terminal, elle est insérée sur une seule ligne (un terminal exécute chaque ligne qu'on lui donne). Un terminal intégré à un éditeur (VS Code, Cursor, JetBrains) ne se distingue pas de l'éditeur lui-même, donc là, la sortie de plusieurs lignes de n'importe quelle commande est insérée telle quelle. Les deux fonctionnent aussi dans la phrase d'une autre commande : `@reply the answer is @py 2**100` ; mettez entre guillemets le code contenant des espaces : `@question explain @py "sum(x * x for x in range(10))"`. L'inverse n'est pas vrai : le code de `@py` et `@js` s'exécute toujours exactement comme vous l'avez tapé, et les `@commands` qu'il contient ne s'exécutent pas d'abord.

![Taper @ ouvre la liste des commandes ; @question plus une question, puis ⏎ pour la réponse](../en/commands.png)

![@open trouve les applications pendant la frappe ; en commençant par /, c'est un chemin : le dossier est listé, Tab complète](../en/open.png)

Quand `@` n'est pas suivi d'une commande, comme dans `@john`, le `@` est inséré comme d'habitude, donc mentionner des personnes avec @ dans les applications de messagerie fonctionne toujours. `@question`, `@improve` et `@translate` n'envoient à votre propre Bedrock que lorsque vous appuyez sur la touche d'action ; `@open` ne cherche que sur ce Mac ; `@note` et `@reminder` ne vont qu'à Notes et Rappels sur ce Mac ; `@claude` utilise le Claude Code installé sur votre Mac (la commande `claude`) et son propre compte, et il vous demande d'abord, comme d'habitude, avant de modifier des fichiers ou d'exécuter des commandes. Sans Claude Code installé, `@claude` n'est pas proposée. `@imessage` ne lit que les Contacts de ce Mac (noms, numéros de téléphone, adresses e-mail), ne passe jamais par l'IA, et c'est Messages qui envoie le message ; sans l'app Messages, elle n'est pas proposée.

`@calculate` fonctionne sur ce Mac, hors ligne : `+ - * /` (aussi `× ÷`), `^` ou `**` pour les puissances, les parenthèses, les pourcentages (`50%` vaut 0,5, `200*5%` vaut 10 ; comme sur une calculatrice, un pourcentage ajouté ou soustrait porte sur ce qui précède : `100+10%` vaut 110, `100-10%` vaut 90), les fonctions `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` est en base 10, les angles sont en radians, `round(x, 2)` garde deux décimales) et les constantes `pi` (`π`) et `e`. Les chiffres et signes pleine chasse fonctionnent aussi. L'arithmétique est exacte en décimal, donc `0.1+0.2` donne `0.3` ; les résultats ont au plus 15 chiffres significatifs, et les nombres entiers jusqu'à 38 chiffres sont écrits en entier (`2^100` → `1267650600228229401496703205376`).

### Sur le texte sélectionné (nouveau)

Sélectionnez du texte dans n'importe quelle application (une phrase dans Notes, un paragraphe dans Mail), tapez `@improve`, `@translate`, `@question` ou une autre commande qui prend du texte, et appuyez sur ⏎ : la commande travaille sur la sélection, et le résultat que vous choisissez la remplace. La sélection reste telle quelle, sélectionnée, pendant que vous tapez : la commande s'écrit dans le panneau des candidats, dont la première ligne est ce que vous tapez et la suivante "On the selection: “…” (N characters)" (sur la sélection : N caractères). Échap, ⇧⏎ ou un clic ailleurs laissent le texte tel qu'il était ; de même si vous changez la sélection entre-temps, ce qui annule la commande. Le texte tapé après la commande est une consigne pour `@improve` et `@translate` (`@translate ja`, `@improve more formal`) et la question pour `@question` (`@question what does this mean`), à propos de la sélection. `@open`, `@claude`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, les commandes de terminal et les extensions par script ne l'utilisent pas : elles prennent ce que vous tapez, et la sélection reste telle quelle. Jusqu'à 5000 caractères ; jamais lue pendant une saisie sécurisée ni dans un terminal. Désactivez-la sous Settings → General → "Use the selected text" (utiliser le texte sélectionné) si elle se comporte mal dans une application.

### Affiner les résultats (nouveau)

Pendant que les résultats de `@improve`, `@translate`, `@question` ou d'une commande d'instruction sont affichés, tapez ce qu'il faut changer, comme `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese` ou `用更口语的说法` (le pinyin fonctionne, et un appui bref sur Maj change de langue), et appuyez sur ⏎ : les résultats repartent vers l'IA avec votre consigne, et les nouveaux les remplacent dans le même panneau. Affinez autant de fois que vous voulez ; la ligne du haut du panneau liste les étapes ("Refined: shorter · more formal"), et vous pouvez choisir une ligne à tout moment comme d'habitude. Une lettre commence la consigne (affichée comme "refine › …" en haut du panneau) ; tant qu'elle est vide, les chiffres, Espace et ⏎ choisissent comme avant. L'affinage commence une fois les résultats complets : taper pendant que les premiers résultats arrivent encore poursuit la phrase, comme avant. Pendant qu'un affinage s'exécute, vous pouvez déjà taper la consigne suivante ; l'affinage continue, et ⏎ lance le suivant une fois ses résultats arrivés. Échap efface la consigne, puis revient d'une étape aux résultats d'avant le dernier affinage (pendant un affinage : l'arrête), puis à la phrase ; ⌫ sur une ligne vide revient en arrière de la même façon. Sur du texte sélectionné, le résultat choisi remplace toujours exactement la sélection, qui reste intacte jusque-là. Un affinage qui échoue (ou qui est refusé pendant une saisie sécurisée) laisse les résultats tels quels, sa consigne prête pour réessayer avec ⏎. Le même affinage des mêmes résultats est servi depuis le cache.

### Questions récentes (nouveau)

`@question` sans rien tapé après liste vos 5 dernières questions, les plus récentes d'abord, avec le moment où elles ont été posées ("3 hours ago"). Taper filtre la liste : chaque mot n'importe où dans la question, sans tenir compte de la casse (le chinois sans espaces aussi). Un chiffre, ↑↓ puis ⏎, ou un clic affiche aussitôt la réponse enregistrée d'une question, sans aller en ligne : Espace ou ⏎ l'insère, ⌘C la copie, 0 affiche la question, R la repose pour une nouvelle réponse, Échap revient à la liste. Sans correspondance, ou si rien n'est choisi, ⏎ pose ce que vous avez tapé. Une nouvelle réponse à la même question, reposée ou affinée, remplace celle enregistrée.

- Elles ne sont conservées que sur ce Mac (voir Confidentialité) : pas pendant une saisie sécurisée, et jamais pour les questions sur du texte sélectionné.
- Settings → General → "Remember recent questions" (mémoriser les questions récentes) désactive la fonction et les supprime (`rememberQuestions` dans la configuration) ; "Clear (N)" (effacer) les supprime.

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

### Taper les résultats

Activez "Type results out" (taper les résultats) sous Settings → General (`typeOut` dans la configuration) et le résultat d'une commande est tapé dans l'application caractère par caractère, comme le ferait une personne, au lieu d'arriver d'un coup ; les mots choisis en pinyin arrivent toujours d'un coup. Le curseur règle le rythme, de 6 secondes par caractère à 40 par seconde (`typeOutRate`), et "Speed up and slow down (like a person)" (accélérer et ralentir, comme une personne) tape par rafales de rythme variable (`typeOutVaries`). Échap l'arrête là où il en est ; toute autre touche tape le reste d'un coup.

"Make occasional typos and fix them" (faire de temps en temps des fautes de frappe et les corriger, `typeOutMistakes`) rend l'effet encore plus humain : de temps en temps la touche voisine de la bonne, remarquée jusqu'à trois lettres plus tard, effacée et retapée ; une lettre ou une espace tapée deux fois puis effacée ; ou un mot court tapé, effacé et retapé. Quelques-unes pour 100 caractères, jamais deux rapprochées, et jamais en début de ligne. Dans du code, des adresses web et e-mail et des nombres, une faute n'est qu'une mauvaise lettre ou un mauvais chiffre, corrigé aussitôt (jamais une mauvaise parenthèse, un guillemet ou une espace, sur lesquels les éditeurs apparient ou indentent). Les mauvaises lettres sont des voisines sur votre disposition de clavier (QWERTY, AZERTY, QWERTZ…). Le chinois, le japonais et le coréen ne font qu'hésiter (deux caractères tapés, effacés et retapés), jamais avec un mauvais caractère.

Dans un champ qui accepte qu'on revienne sur une faute (les vues de texte d'Apple comme TextEdit et Notes, les navigateurs, la plupart des éditeurs) : tapé jusqu'au bout, ou avec une autre touche pressée pour taper le reste d'un coup, le texte est exactement le résultat ; Échap (ou quitter le champ) au milieu d'une faute retire d'abord la faute, si bien que le champ contient un début exact du résultat. Si le curseur bouge pendant qu'une faute est affichée (un clic), la faute est retirée là où elle était et le reste est tapé sans fautes.

Il n'y a jamais de fautes dans les terminaux, ni dans les applications qui n'indiquent pas à la méthode de saisie où se trouve le curseur. À chaque fois, la première faute est une faute simple (une mauvaise lettre, corrigée en une fois), jusqu'à ce que le champ ait montré qu'il accepte qu'on revienne sur une faute ; tant qu'une faute est affichée, la méthode de saisie vérifie avant chaque touche que le champ contient ce qu'elle a tapé. Un champ qui ignore où remplacer le texte ne peut pas revenir sur une faute : là, cette première faute reste, et le texte finit décalé d'un caractère (aussi après Échap ou une autre touche), et l'application ne reçoit plus de fautes. Settings → General liste ces applications sous l'interrupteur des fautes ; "Forget apps where typos couldn't be fixed" (oublier les applications où les fautes n'ont pas pu être corrigées) les laisse réessayer.

### Réglages par application (nouveau)

Settings → Apps donne à une application ses propres réglages, tous facultatifs ; ce qu'une application ne définit pas suit les réglages communs à toutes les applications :

| Réglage | Par exemple | Dans la configuration |
| --- | --- | --- |
| La langue de saisie dans laquelle ses champs de texte commencent | Slack en anglais, WeChat en pinyin | `inputLanguage` |
| Les styles de reformulation que `@improve` y propose | Mail formel et diplomate, Slack décontracté | `rewriteStyles` |
| Taper les résultats, ou non | activé dans une app de messagerie, désactivé dans Mail | `typeOut` |
| Pas d'IA dans cette application | `@improve`, `@translate`, `@question`, `@claude` et vos commandes d'instruction n'y envoient rien et le disent ; la frappe et les autres commandes fonctionnent | `noAI` |

"Add App…" (ajouter une app) liste les applications dans lesquelles vous avez tapé récemment, ou en choisit une dans /Applications. Le menu de saisie, avec "This App: <nom>", propose des interrupteurs rapides pour l'application dans laquelle vous tapez (No AI, Type Results Out, la langue de départ). Dans la configuration, ils sont sous `appProfiles`, par identifiant de bundle : `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. Les identifiants de bundle se comparent sans tenir compte de la casse (`com.apple.Mail` est le `com.apple.mail` de Mail). `@reportissue` compte les applications qui définissent quelque chose, sans jamais les nommer.

- La langue de départ fonctionne comme la langue de saisie par défaut : un champ de texte la prend quand il devient actif, et un changement avec Maj reste ensuite pour les champs de cette application jusqu'à ce que le réglage change.
- Avec No AI, les commandes d'IA restent dans la liste @ ; en lancer une affiche la notification et garde ce que vous avez écrit. Vos propres commandes de terminal (`"type": "terminal"`) exécutent des programmes, pas l'IA, et fonctionnent donc toujours là.

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
- **Disposition des candidats** : pour choisir les mots, les candidats pinyin et hindi sont côte à côte par défaut (Horizontal), comme dans les méthodes de saisie du système : ← → choisissent et ↑↓ (ou - =) changent de page. Choisissez Vertical sur la page Input, sous les langues de saisie, pour les avoir les uns sous les autres (↑↓ choisissent). La liste des commandes @ et les résultats sont toujours verticaux.
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
3. L'installeur est signé avec un Developer ID et notarié par Apple, donc la première fois macOS demande seulement s'il faut ouvrir une application téléchargée sur Internet : cliquez sur Ouvrir. (Les versions antérieures à 0.6.3 n'étaient pas notariées : chacune devait être autorisée une fois dans Réglages Système → Confidentialité et sécurité → Ouvrir quand même.)

Ensuite, AllInOneIME est activé et figure dans vos sources de saisie ; passez-y avec Ctrl+Espace (la touche 🌐 ne change de source que si "Appuyer sur la touche 🌐 pour" est réglé sur "Changer de source de saisie" dans Réglages Système → Clavier). Si l'installeur vous dit de l'ajouter à la main, ce Mac ne permet pas aux programmes de l'activer ; ajoutez-le donc vous-même une fois : Réglages Système → Clavier → Saisie de texte → Sources de saisie → Modifier… → + (en bas à gauche) → Anglais → AllInOneIME (il tape aussi le pinyin une fois que vous avez ajouté le chinois sous Input dans ses réglages).

Si Ctrl+Espace ne vous amène pas à AllInOneIME, ou s'il revient à U.S. au bout d'un moment, relancez l'installeur : il rajoute AllInOneIME à vos sources de saisie.

Mise à jour : Settings → About → Check for Updates (rechercher des mises à jour). Quand une nouvelle version existe, About l'indique (ainsi qu'une ligne dans le panneau de la barre des menus), avec les nouveautés ; "Update to <version>" (mettre à jour vers <version>) la télécharge, la vérifie par rapport aux informations de mise à jour signées avec la clé de publication d'AllInOneIME, l'installe et redémarre la méthode de saisie. Vos réglages, packs de langue, mots appris et extensions sont conservés, et si quelque chose se passe mal, la version que vous aviez est remise en place. AllInOneIME vérifie une fois par jour de lui-même, en arrière-plan (désactivez-le avec "Check for updates automatically" sous About) ; rien n'est installé tant que vous ne cliquez pas. Cela fonctionne à partir de 0.6.3 ; pour mettre à jour une version plus ancienne, ou si vous préférez, installez l'image disque de la nouvelle version par-dessus, sans désinstaller d'abord. Avant de mettre à niveau, lisez le [journal des modifications](../../CHANGELOG.md) : il contient les changements de chaque version et les notes de mise à niveau.

Mise à jour vers 0.6.3 depuis une version antérieure : 0.6.3 est la première version signée avec un Developer ID, donc le trousseau ne la reconnaît pas encore comme l'application qui a enregistré vos clés. La première fois qu'elle a besoin de chaque clé enregistrée (une clé d'API, la connexion à AllInOneIME Cloud, le mot de passe d'une extension), macOS demande votre mot de passe de session : saisissez-le et cliquez sur "Always Allow" (Toujours autoriser). Il ne le redemande plus, y compris après les mises à jour suivantes. Les clés d'Amazon Bedrock se trouvent dans `~/.aws/credentials`, qui n'est pas concerné.

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

### Apple Intelligence sur ce Mac (macOS 26)

Sur un Mac doté d'Apple Intelligence (puce Apple, macOS 26 ou ultérieur, activée dans Réglages Système → Apple Intelligence et Siri), choisissez "Apple Intelligence (on this Mac)" sous "AI Provider" : pas de clé, pas de coût, et rien de ce que vous tapez ne quitte le Mac. Elle utilise le modèle intégré à macOS (le framework Foundation Models), avec les mêmes instructions et le même format de réponse que les autres fournisseurs, mais uniquement les exemples écrits dans la langue de la phrase (un petit modèle copie trop facilement la langue d'un exemple).

- C'est un petit modèle : son contexte est d'environ 4K tokens (8K sur macOS 27), donc un long paragraphe peut être trop long pour lui, et il parle moins de langues (anglais, chinois, japonais, coréen, français, allemand, espagnol et quelques autres ; pas le hindi). Dans les deux cas, il le dit. Ses résultats sont en dessous de ceux des modèles dans le cloud, et ses réponses de `@question` sur des faits et du code sont souvent fausses.
- Là où il ne peut pas être utilisé, il est listé en grisé avec la raison (non pris en charge sur ce Mac, désactivé, modèle pas prêt), et les réglages renvoient vers Réglages Système → Apple Intelligence et Siri. Avant macOS 26, il n'est pas listé.
- "Output tokens", la température et le délai d'expiration sous "Model Settings" s'y appliquent. Dans le fichier de configuration : `"provider": "apple"`.

### Masquer les informations sensibles (nouveau)

Settings → AI Provider → Privacy → "Hide sensitive information before sending" (masquer les informations sensibles avant l'envoi ; désactivé par défaut) : avant qu'une requête parte vers l'IA, ce qu'il trouve dans votre texte est remplacé sur le Mac par des espaces réservés comme `[EMAIL_1]` (même valeur, même espace réservé), et les résultats récupèrent les vraies valeurs avant d'être affichés ou insérés. Le panneau indique "2 items hidden from the AI" (2 éléments masqués à l'IA). Chaque type peut être désactivé :

| Type | Par exemple | Dans la configuration |
| --- | --- | --- |
| Adresses e-mail | `bob@example.com` | `emails` |
| Numéros de téléphone | `+1 (555) 123-4567`, `138 0013 8000` | `phones` |
| Numéros de carte de paiement (vérifiés par Luhn) | `4111 1111 1111 1111` | `cards` |
| Clés d'API et jetons | préfixes connus comme `sk-` ou `ghp_`, longues chaînes aléatoires | `keys` |
| Adresses IP | `203.0.113.42`, `2001:db8::1` | `ips` |
| Vos propres mots, quelle que soit la casse | un nom de code comme `Project Atlas`, un nom | `customWords` |

- Cela s'applique à `@improve`, `@translate`, `@question`, vos commandes d'instruction et plugins d'instruction, et à l'affinage de leurs résultats (mêmes espaces réservés), avec tous les fournisseurs, y compris AllInOneIME Cloud et Apple Intelligence. Les entrées de la liste de jargon contenant une valeur à masquer ne sont pas envoyées.
- Il reconnaît les valeurs formatées ; il ne peut pas reconnaître les noms ni les adresses, ajoutez-les donc comme vos propres mots. `@claude`, les plugins qui récupèrent des données sur un site web (`@stock`) ou en ouvrent un (`@x`) et les extensions par script envoient le texte tel que tapé. Plus de détails sous Confidentialité.
- Dans la configuration : `"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`.

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
| `candidateLayout` | Candidats pinyin et hindi : `"vertical"` (les uns sous les autres) ou `"horizontal"` (côte à côte ; ← → choisissent, ↑↓ changent de page) | `"horizontal"` |
| `fuzzyPinyin` | Paires de pinyin approximatif : `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | Les commandes @ travaillent sur le texte sélectionné dans le champ (voir Sur le texte sélectionné) | `true` |
| `checkForUpdates` | Chercher une nouvelle version une fois par jour, en arrière-plan ; rien n'est installé tant que vous ne cliquez pas | `true` |
| `rememberQuestions` | Conserver vos 5 dernières questions `@question` et leurs réponses sur ce Mac, listées sous `@question` (voir Questions récentes) | `true` |
| `appProfiles` | Réglages d'une application, par identifiant de bundle, tous facultatifs : `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI` (voir Réglages par application) | `{}` |
| `redaction` | Masquer les informations sensibles à l'IA (voir Confidentialité) : `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}` ; chaque détecteur (`emails`, `phones`, `cards`, `keys`, `ips`) est actif sauf s'il vaut `false` | `enabled: false` |

## Confidentialité

- La frappe (anglais et pinyin) et les calculs de `@calculate` sont entièrement locaux. Ce n'est que lorsque vous appuyez sur la touche d'action avec `@improve`, `@translate` ou `@question` que la phrase est envoyée au fournisseur d'IA que vous avez choisi (votre propre Bedrock, ou le service dont vous avez ajouté la clé). Avec "Jargon" coché et une liste de jargon définie, la liste est envoyée avec elle. Affiner les résultats (une consigne tapée après eux, puis ⏎) renvoie la même requête avec les résultats affichés et votre consigne.
- Avec AllInOneIME Cloud, la phrase passe par le serveur du développeur vers un fournisseur de modèles (actuellement via OpenRouter) : le serveur ne conserve que des compteurs, jamais le texte. La connexion ne conserve que votre adresse e-mail.
- Masquer les informations sensibles (Settings → AI Provider → Privacy, désactivé par défaut) : avant l'envoi de toute requête (`@improve`, `@translate`, `@question`, vos commandes d'instruction et plugins d'instruction, avec tous les fournisseurs, y compris AllInOneIME Cloud), les adresses e-mail, numéros de téléphone, numéros de carte de paiement (vérifiés par Luhn), clés d'API et jetons (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…` et longues chaînes aléatoires), adresses IP et vos propres mots (un nom de code, un nom) sont remplacés sur le Mac par des espaces réservés comme `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]` ; la même valeur reçoit le même espace réservé. Les résultats du modèle récupèrent les vraies valeurs avant d'être affichés ou insérés, et le panneau indique "2 items hidden from the AI". Un résultat dont le modèle a modifié l'espace réservé au point de le rendre méconnaissable est affiché tel qu'écrit, marqué "⚠ placeholder changed". Les entrées de la liste de jargon contenant une valeur masquée ne sont pas envoyées. Chaque type peut être désactivé. Les formes pleine chasse (`zhang＠example.com`, `１３８…`) sont trouvées aussi, et une valeur ou une expression peut être coupée par un retour à la ligne. Il reconnaît les valeurs formatées comme les e-mails, les numéros et les clés ; il ne peut reconnaître ni les noms ni les adresses (ajoutez-les comme vos propres mots), ni les lettres semblables d'autres alphabets. S'applique aux requêtes vers votre service d'IA ; `@claude`, les plugins qui récupèrent des données sur un site web (`@stock`) ou en ouvrent un (`@x`) et les extensions par script envoient le texte tel que tapé. Dans la configuration : `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- La voix n'est enregistrée que pendant que vous maintenez ⌥ de droite et elle est reconnue sur le Mac ; le texte reconnu n'est envoyé que dans les commandes ci-dessus, lorsque vous appuyez sur la touche d'action.
- La méthode de saisie lit le texte du presse-papiers, une fois, uniquement lorsque vous appuyez sur ⌃V ou ⌘V dans une commande ; le contenu que les gestionnaires de mots de passe marquent comme masqué n'est pas lu. Le texte est d'abord affiché dans la commande et, là encore, n'est envoyé que lorsque vous appuyez sur la touche d'action. Les versions récentes de macOS demandent si AllInOneIME peut lire le presse-papiers : autorisez-le. Pour ne plus avoir à répondre à chaque fois, réglez l'autorisation de collage d'AllInOneIME sur toujours autoriser dans Réglages Système → Confidentialité et sécurité.
- Dans les champs de mot de passe, macOS passe à son propre clavier (U.S. ou ABC) et revient quand vous les quittez. Chaque fois que l'application dans laquelle vous tapez active la saisie sécurisée, AllInOneIME ne compose pas de texte et ne peut pas enregistrer : les touches passent telles quelles. Et tant que le système est en saisie sécurisée (champs de mot de passe, Entrée clavier sécurisée de Terminal, etc.), rien n'est envoyé à l'IA.
- `@note` et `@reminder` ne passent pas par l'IA : AllInOneIME ne remet le texte qu'à Notes et Rappels sur ce Mac, et interprète aussi l'heure du rappel sur le Mac (que ces applications le synchronisent avec vos autres appareils dépend de leurs comptes, comme iCloud). Elles fonctionnent donc aussi pendant une saisie sécurisée.
- `@reportissue` (et "Report an Issue…") n'envoie rien de lui-même : il ouvre dans votre navigateur la page de nouveau ticket de GitHub avec le titre que vous avez tapé et les versions, langues, type de fournisseur et compteurs listés plus haut, affichés d'abord dans le panneau des candidats. Rien n'arrive sur GitHub tant que vous ne cliquez pas sur Submit là-bas.
- `@open` ne cherche que sur ce Mac. Elle mémorise ce que vous avez ouvert avec elle (les 200 derniers éléments), dans les préférences propres à la méthode de saisie (pas dans config.json), pour les lister en premier.
- Pour "Add App…" dans Settings → Apps, la méthode de saisie conserve les identifiants de bundle des 12 dernières applications dans lesquelles vous avez tapé, dans ses propres préférences ; rien d'autre à leur sujet.
- `@question` mémorise vos 5 dernières questions avec leurs réponses et le moment où elles ont été posées, uniquement sur ce Mac, dans `~/Library/Application Support/AllInOneIME/recent-questions.json` (lisible uniquement par votre compte utilisateur), pour les lister sous `@question` ; une réponse enregistrée est affichée depuis ce fichier sans aller en ligne. Rien n'est conservé pendant une saisie sécurisée, et les questions posées sur du texte sélectionné ne sont pas conservées du tout (leur réponse porte sur la sélection, qui se retrouverait sur le disque). Settings → General → "Remember recent questions" désactive la fonction et les supprime (`rememberQuestions` dans la configuration) ; "Clear" les supprime.
- Pour lister vos notes, le panneau de la barre des menus conserve l'identifiant et la première ligne (jusqu'à 80 caractères) des 30 dernières notes enregistrées avec `@note`, dans les préférences propres à la méthode de saisie, y compris quand le panneau est désactivé.
- `@py` et `@js` ne s'exécutent que lorsque vous appuyez sur la touche d'action, et uniquement sur du code que vous avez tapé ou collé vous-même : les réponses de l'IA et la sortie des autres commandes ne sont jamais exécutées comme du code. `@py` utilise le `python3` de votre Mac, qui peut lire et écrire des fichiers et accéder à Internet comme il le fait dans Terminal ; `@js` s'exécute dans un processus séparé qui ne peut ni lire de fichiers, ni accéder au réseau, ni lancer d'autres programmes. Aucune des deux ne s'exécute pendant une saisie sécurisée.
- Vérification des mises à jour : une fois par jour (sauf si "Check for updates automatically" est désactivé), AllInOneIME télécharge https://allinoneime.com/update.json et sa signature ; la requête ne contient aucun identifiant ni rien de ce que vous avez tapé. Une mise à jour n'est téléchargée, depuis la release GitHub, que lorsque vous cliquez sur Update.
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
make dmg          # the release installer, build/AllInOneIME-<version>.dmg (universal; signed if there's a Developer ID certificate, optionally notarized), and the in-app update, build/AllInOneIME-<version>-update.zip
make update-test  # the in-app updater end to end: a temporary install, a test server on 127.0.0.1, a test key (never the installed app)
```

Organisation du code :

- `Sources/AllInOneIMECore` : client Bedrock, SigV4, prompts, la machine à états de saisie à deux niveaux (y compris les commandes @ et le geste vocal) ; aucune dépendance à AppKit
- `Sources/AllInOneIMERime` : enveloppe de librime
- `Sources/AllInOneIME` : la méthode de saisie InputMethodKit, le panneau des candidats, la fenêtre des réglages, la reconnaissance vocale
- `Sources/AllInOneIMESettings` : le lanceur "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller` : "Install AllInOneIME" sur l'image disque : installe, met à jour et désinstalle

Les packs de langue ont leur propre bibliothèque, distincte de celle des plugins : le dépôt [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), servi à l'adresse https://languages.allinoneime.com/, signé avec sa propre clé. `make pack` construit l'archive ; elle y est publiée comme fichier de release (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), et `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` y écrit `packs.json` et le signe dans `packs.json.sig` avec la clé des packs de langue tirée du trousseau (`allinoneime-languages-signing`). L'application lit https://languages.allinoneime.com/packs.json, vérifie la signature, puis la taille et le SHA-256 de l'archive. Pour essayer un pack depuis un serveur local : `--test-key` signe avec une clé de test, puis `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Publier une version (le système de mise à jour intégré lit https://allinoneime.com/update.json, signé avec la clé propre aux publications) :

1. Augmentez le numéro de version (`AppVersion.swift` et les trois Info.plist ; `AppVersionTests` vérifie qu'ils concordent) et mettez à jour les journaux des modifications.
2. `make dmg NOTARY_PROFILE=<profile>` : `build/AllInOneIME-<version>.dmg` avec son `.sha256`, et `build/AllInOneIME-<version>-update.zip` (les deux applications, telles que l'installeur de l'image disque les contient). Les applications et l'image sont signées avec le certificat Developer ID Application du trousseau, et l'image est notariée avec ce profil de trousseau `xcrun notarytool`, puis agrafée (stapled).
3. Envoyez les deux dans la release GitHub `v<version>` et publiez-la.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"` (une phrase ou deux chacun) : écrit `site/public/update.json` (la version, le build et la version minimale de macOS lus dans les applications, l'adresse, la taille et le SHA-256 du fichier, l'adresse des notes de version et le résumé) et le signe dans `update.json.sig` avec la clé du trousseau de session (`allinoneime-releases-signing` ; macOS peut demander d'autoriser l'accès). Validez (commit) les deux.
5. Déployez le site (`cd site && npx wrangler@4 deploy`), seulement une fois que les fichiers de la release se téléchargent : les applications vérifient une fois par jour, et `AllInOneIME --check-update` montre ce qu'elles voient.

L'application vérifie la signature du manifeste avec la clé publique qu'elle contient avant de le lire, n'installe jamais une version qui n'est pas plus récente, ne télécharge qu'en https depuis allinoneime.com ou les fichiers des releases GitHub du dépôt, et n'installe l'archive qu'une fois que sa taille et son SHA-256 correspondent au manifeste, que les identifiants de bundle, les versions et les signatures de code des deux applications sont corrects et que la nouvelle méthode de saisie démarre. La méthode de saisie passe ensuite la main à son propre exécutable comme assistant (`--apply-update`), qui attend qu'elle se ferme, échange les applications comme le fait l'installeur (les anciennes mises de côté, remises en place si quelque chose échoue) et enregistre la nouvelle. Pour essayer avec un serveur local : `make update-test`, ou `--test-key` avec `Scripts/build-update-manifest.swift` et `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`.

L'identifiant de bundle est toujours `com.aipinyin.inputmethod.AIPinyin` : macOS s'en sert pour mémoriser la source de saisie ajoutée et l'autorisation du micro, donc le changer obligerait à rajouter la méthode de saisie et à accorder de nouveau l'autorisation.

## Licence

Copyright © 2026 MicroZ LLC. Source disponible sous la [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2) : utilisez-le, lisez-le, modifiez-le et partagez-le pour tout usage, sauf pour un produit concurrent. Chaque version passe sous Apache-2.0 deux ans après sa sortie. Les versions jusqu'à la 0.6.1 ont été publiées sous GPL-3.0 et restent disponibles sous cette licence.

Les composants tiers (librime et ses plugins sous BSD-3-Clause ; les scripts Lua de rime-ice et le pack de langue chinois sous GPL-3.0) sont listés dans [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
