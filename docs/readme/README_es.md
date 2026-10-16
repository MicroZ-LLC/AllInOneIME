<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · [繁體中文](README_zh-TW.md) · [日本語](README_ja.md) · [한국어](README_ko.md) · [Français](README_fr.md) · [Deutsch](README_de.md) · **Español** · [Português (Brasil)](README_pt-BR.md) · [Italiano](README_it.md) · [Русский](README_ru.md) · [Tiếng Việt](README_vi.md) · [ไทย](README_th.md) · [Bahasa Indonesia](README_id.md) · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · [Türkçe](README_tr.md)

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="Icono de AllInOneIME">

# AllInOneIME

### Comandos de IA en cada campo de texto de tu Mac.

Escribe `@improve`, `@translate` o `@question` en cualquier app, pulsa ⏎ y elige el resultado.<br>
Sin copiar en una ventana de chat, sin cambiar de app. Tu propio proveedor de IA, tus propias claves.

[![Versión](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#instalación)
[![Apple silicon e Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#instalación)
[![Licencia: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![Descargas](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[Descargar](https://allinoneime.com/download)** · **[Sitio web](https://allinoneime.com)** · **[Documentación](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[Extensiones](../extensions.md)**

[Cómo se usa](#cómo-se-usa) · [Comandos](#comandos--beta) · [Tus propios comandos](#tus-propios-comandos) · [Idiomas](#entrada-y-traducción) · [Voz](#entrada-por-voz) · [Instalación](#instalación) · [Privacidad](#privacidad)

<br>

<img src="../en/demo.png" width="820" alt="@translate y una frase, luego ⏎: una línea en español, francés y alemán">

</div>

*Esta es una traducción del README en inglés; si difieren, la versión en inglés es la correcta.*

> [!NOTE]
> Desde la 0.6.3, AllInOneIME está firmado con un Developer ID y notarizado por Apple: ya no hace falta permitirlo en System Settings → Privacy & Security (Ajustes del Sistema → Privacidad y seguridad). Tras actualizar desde una versión anterior, macOS pide una vez tu contraseña de inicio de sesión por cada clave que AllInOneIME guardó en el llavero: escríbela y haz clic en "Always Allow" (Permitir siempre). Descarga AllInOneIME solo desde [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) o desde [allinoneime.com](https://allinoneime.com).

Un método de entrada para macOS con comandos de IA en cada campo de texto. Empieza una frase con `@` y pulsa ⏎ cuando termines: `@improve` pule lo que escribiste y ofrece algunas reescrituras, `@translate` lo traduce a los idiomas que elijas, `@question` hace una pregunta, `@agent` se lo pasa a un agente de programación (Claude Code, Gemini CLI, Kiro CLI …), y `@open` encuentra archivos y apps o abre una dirección web. También puedes mantener pulsada la tecla ⌥ derecha y hablar. Sin `@`, tus pulsaciones van a la app como siempre. También escribe chino (pinyin, basado en Rime y rime-ice), francés, coreano (hangul) e hindi (devanagari a partir de letras latinas), y ejecuta tus propios scripts como comandos @.

![@improve y una frase sin pulir, luego ⏎: versiones pulidas, más reescrituras](../en/improve.png)

Para más detalles (cada comando y cada ajuste, solución de problemas de instalación, privacidad), consulta la [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Creado por [Weijian Zhang](https://weijianz.com) en MicroZ LLC.

## Cómo se usa

Sin `@`, no se interpone: en inglés, las letras se escriben directamente y ⏎ es Retorno; nada se envía a internet. Una instalación nueva escribe en inglés; para escribir también en chino (pinyin), francés, coreano o hindi, añádelo en los ajustes (consulta [Entrada y traducción](#entrada-y-traducción)).

| Tecla | Qué hace |
|---|---|
| Escribir pinyin, Espacio / dígitos | En modo chino: elegir palabras, como en cualquier método de entrada pinyin |
| `@` (al principio de una frase) | Abre la lista de comandos: primero los más usados últimamente, de 5 en 5, desplazable con ↑↓, la rueda o el trackpad; o escribe letras para encontrar uno (primero un nombre escrito completo, luego los nombres que empiezan por ellas y después los que las contienen). ⏎, Tab, Espacio o un dígito lo elige |
| ⏎ | Ejecuta el comando. Funciona aunque el pinyin aún no esté elegido: se elige primero, como con Espacio |
| Espacio, ⏎ / dígitos | Cuando aparecen los resultados: inserta el resaltado / el numerado; 0 es el original. ⏎ inserta aunque haya un seguimiento a medio escribir (se descarta) |
| ⇧⏎ | Con un seguimiento escrito tras los resultados de la IA: lo envía (la siguiente pregunta de una conversación de `@question`, o un refinado). Mientras escribes un comando, o sobre resultados de la IA sin nada escrito: inserta tal cual lo que escribiste, `@command` incluido. Sobre otros resultados (`@open`, un recordatorio …) inserta la fila resaltada, como ⏎. Sobre los resultados de `@config` y `@doctor`, ⇧⏎ sin nada escrito no hace nada |
| ⌘C | Copia el resultado resaltado (en `@open`, la ruta); el panel de candidatos sigue abierto |
| ⌃V | En un comando (p. ej., después de `@improve `): añade el texto del portapapeles tras lo que has escrito en vez de pegarlo en la app. Varias líneas se convierten en una, hasta 2000 caracteres cada vez (`@note` conserva los saltos de línea y admite hasta 20000). Funciona en cualquier app; sin comando, la tecla va a la app como siempre |
| ⌘V | Como ⌃V, pero algunas apps gestionan ⌘V por su cuenta (terminales como Ghostty, iTerm2 y Terminal, y Notas) y pegan en la app como siempre; usa ⌃V en ellas |
| Esc, ⌫ | Vuelve a la frase para seguir editándola; escribir signos de puntuación o dígitos tras los resultados la continúa. Tras un refinado: vuelve a los resultados de antes |
| Letras, con los resultados de la IA en pantalla | Un seguimiento: tras `@question`, la siguiente pregunta (consulta [Conversaciones](#conversaciones-con-question-nuevo)); tras `@improve` o un comando de instrucción, una instrucción como `shorter` (consulta [Refinar los resultados](#refinar-los-resultados-nuevo)); ⇧⏎ lo envía. Tras `@translate`, las letras continúan la frase, y ⏎ la vuelve a traducir |
| ⌘⏎, ⌘1–⌘5 | En una conversación de `@question`: muestra dónde continuarla (Claude Code o el otro agente que elegiste para `@agent`, Claude, ChatGPT, Gemini, o copiarla); ⌘1, ⌘2 … eligen uno |
| Clic en una fila | En el panel de candidatos: la elige, como lo haría su dígito (una palabra, un comando de la lista, un resultado, un archivo de `@open`, un destinatario, una fila de una extensión); la fila bajo el puntero se resalta. El campo de texto conserva el foco |
| Pulsar Mayúsculas | Con más de un idioma de entrada: el siguiente, en su orden (inglés → chino → francés → …, y luego vuelta al primero) |
| Mantener ⌥ derecha | Habla y suelta para terminar. En el idioma en el que escribes (inglés, chino, francés, coreano o hindi). En un comando, el texto va detrás de él; si no, se inserta directamente |

## Comandos @ (beta)

| Comando | Qué hace |
|---|---|
| `@improve` | Pulir: 1–3 son tres versiones en el idioma de la propia frase, a partir de 4 los estilos de reescritura (añadidos y ordenados en los ajustes), 0 es el original. Sin traducción; con "@improve also translates" (@improve también traduce) activado, funciona como `@translate @improve` |
| `@translate` | Traduce a los idiomas que hayas añadido (ajustes → Translate, arrastra para reordenar), una línea por idioma, tres versiones si solo hay uno; se omite el idioma de la propia frase. `@translate @improve` juntos traducen y reescriben en una sola petición |
| `@question` | Hace una pregunta; la respuesta aparece en los candidatos, ⏎ o Espacio la inserta, ⌘C la copia. Sigue escribiendo y ⇧⏎ hace una pregunta de seguimiento: el panel se convierte en una conversación de hasta 5 rondas y luego ofrece continuarla en Claude u otra IA. Sin nada escrito detrás, muestra tus últimas 5 preguntas, la más reciente primero; al escribir se filtran (palabras en cualquier parte de la pregunta, sin distinguir mayúsculas, también en chino). Un dígito, ↑↓ y luego ⏎, o un clic muestra al instante la respuesta guardada de una pregunta, sin conexión, para insertarla o copiarla como siempre; ahí ⌘R la vuelve a preguntar para obtener una respuesta nueva. Sin coincidencias, o si no eliges nada, ⏎ pregunta lo que escribiste |
| `@agent` | Pasa la tarea a un agente de programación en tu Mac, elegido en Settings → General → "@agent hands it to" (@agent se lo pasa a): Claude Code (el predeterminado), Gemini CLI, Kiro CLI o un comando propio (lo que escribiste se añade como su último argumento). Claude Code se ejecuta en segundo plano de forma predeterminada, con una notificación cuando termina (haz clic en ella para abrir la sesión en Terminal y continuar), o consulta `@tasks`; desactiva "@agent runs in the background and notifies me" (@agent se ejecuta en segundo plano y me avisa) para abrirlo en Terminal. Los demás agentes se abren en Terminal con lo que escribiste como primer mensaje. Cada uno usa su propio inicio de sesión y sus propios ajustes. La primera vez que abre Terminal, macOS pregunta si AllInOneIME puede controlar Terminal: haz clic en OK. (Antes de la 0.6.4 se llamaba `@claude`.) |
| `@tasks` | Muestra las tareas de Claude en segundo plano (trabajando / terminada / esperándote) con sus últimas respuestas; ⏎ abre una en Terminal, ⌘C copia la respuesta |
| `@settings` | Abre la ventana de ajustes de inmediato (basta con elegirlo) |
| `@config` | Cambia los ajustes según los describes: `@config output languages English and French`, `@config use Chinese in WeChat`, `@config candidates in a column`. ⏎ muestra los cambios, antes → después; ⏎ (o 1) los aplica, Esc cancela, escribe más y pulsa ⇧⏎ para refinarlos; ⌘Z o `@config undo` los deshace. Consulta [Cambiar los ajustes describiéndolos](#cambiar-los-ajustes-describiéndolos-nuevo) |
| `@doctor` | Comprueba tu instalación en este Mac y arregla lo que puede arreglar sin riesgo: ⏎ muestra los resultados, los problemas primero; un dígito arregla ese, ⏎ los que no tienen riesgo, a través de la vista previa de `@config`. `@doctor why doesn't translate work` además hace que la IA explique la causa probable. Consulta [Comprobar tu instalación](#comprobar-tu-instalación-nuevo) |
| `@open` | Muestra los archivos, carpetas y apps que coinciden mientras escribes (Spotlight). Funcionan varias palabras clave separadas por espacios: cada una debe estar en la ruta y al menos una en el nombre (el nombre de una carpeta estándar cuenta para lo que contiene: `downloads pdf` encuentra los PDF de Downloads (Descargas)). Las apps y las carpetas estándar también se encuentran por su nombre en chino, y una interfaz en chino las muestra así. Primero aparece lo que abriste con `@open`, luego las apps y esas carpetas, y luego los archivos usados o modificados recientemente; cuando los nombres encuentran dos archivos o menos y ninguna app ni ninguna de esas carpetas, también se buscan por contenido los archivos de tu carpeta de inicio, con esas filas marcadas como "content" (contenido); cuando no hay nada más, ⏎ los muestra para que elijas en vez de abrir el primero. Con una dirección web (`github.com`, `localhost:3000`, `https://…`), la primera fila es "open in the browser" (abrir en el navegador) y no se busca en el contenido; un archivo con exactamente ese nombre (por ejemplo, `MANIFEST.in`) aparece primero. Un texto que empieza por `~/` o `/` es una ruta: Tab la completa y entra en las carpetas; ⏎ abre, ⌘C copia la ruta |
| `@note` | Guarda el texto en la app Notas, en una carpeta llamada AllInOneIME (se crea si no existe); no se inserta nada. El texto pegado conserva sus saltos de línea, hasta 20000 caracteres |
| `@reminder` | Añade un recordatorio a la app Recordatorios, en una lista llamada AllInOneIME. Escribe la hora en el texto; se interpreta en el Mac, y una fila muestra lo que se ha entendido: ⏎ o Espacio lo añade, Esc vuelve a la edición. Con hora, tiene una alarma a esa hora; solo con fecha, es para todo el día |
| `@calculate` | Calcula en este Mac; el resultado aparece en los candidatos, ⏎ o Espacio lo inserta: `@calculate 23*17` → `391`. También funciona dentro de una frase: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Ejecuta una línea de Python (el `python3` del Mac) e inserta el resultado: el valor de la última expresión del código, p. ej. `@py 2**100`, `@py import math; math.sqrt(2)`, o si no, lo que haya impreso. No se ofrece sin `python3` (las herramientas de línea de comandos de Xcode lo incluyen) |
| `@js` | Ejecuta una línea de JavaScript e inserta lo mismo: el valor de la última expresión o lo que haya impreso `console.log`, p. ej. `@js [1, 2, 3].map(x => x * 2)`. Usa JavaScriptCore, integrado en macOS, así que no hay nada que instalar; no puede leer archivos, acceder a la red ni ejecutar otros programas |
| `@reportissue` | Informa de un problema: abre en tu navegador la página de GitHub para una nueva incidencia (issue), con lo que escribiste tras el comando como título y "What happened / What you expected" (qué pasó / qué esperabas) para rellenar. Añade las versiones de la app y de macOS, la arquitectura de tu Mac, los idiomas de la interfaz y de entrada, los paquetes de idioma instalados, el tipo de proveedor de IA (y el modelo, si es público; si no, "custom"), la tecla de acción y cuántos comandos personalizados, plugins y extensiones tienes, nunca sus nombres, tu texto, rutas ni claves. ⏎ (o tu tecla de acción) muestra primero todo eso en el panel de candidatos; ⏎ otra vez, o un clic en la fila, abre la página, donde lo lees y haces clic en Submit (con tu cuenta de GitHub); Esc vuelve atrás. También en el menú de entrada ("Report an Issue…") y en Settings → About |
| `@imessage` | Envía un iMessage: escribe un nombre, un número de teléfono o un correo electrónico (un nombre chino también por su pinyin, completo o por las iniciales) y elige el destinatario en el panel de candidatos (primero aparecen aquellos a quienes has escrito últimamente; también funciona un número o una dirección completos), y luego escribe el mensaje (los comandos que contenga, como `@stock AAPL`, se ejecutan primero). ⏎ muestra "Send to Alex (…): message" en el panel, otro ⏎ lo envía, Esc vuelve a la edición; no se escribe nada en el campo de texto. La primera vez, macOS pregunta si AllInOneIME puede acceder a Contactos y controlar Mensajes: haz clic en OK en ambos casos |

Ejemplo: `@q` ⏎, escribe `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ guarda una nota. `@reminder call Bob tomorrow at 3pm` ⏎, comprueba la hora que ha entendido y pulsa ⏎ de nuevo para añadirlo. Una vez elegido el comando, también puedes mantener pulsada ⌥ derecha y hablar. En modo chino, `@open` y `@calculate` cambian momentáneamente a letras latinas y vuelven al chino cuando terminas.

El código de `@py` y `@js` se escribe con letras latinas, y la puntuación de ancho completo (del modo chino) se convierte en ASCII; escríbelo en una sola línea, con `;` entre las instrucciones. Se ejecuta en un proceso aparte, que se detiene a los 10 segundos o en cualquier momento con Esc; si hay un error, se muestra su primera línea, p. ej. `ZeroDivisionError: division by zero`. Una salida de varias líneas se inserta tal como se imprimió; en un terminal se inserta como una sola línea (un terminal ejecuta cada línea que recibe). Un terminal dentro de un editor (VS Code, Cursor, JetBrains) no se distingue del propio editor, así que ahí la salida de varias líneas de cualquier comando se inserta tal cual. Ambos funcionan también dentro de la frase de otro comando: `@reply the answer is @py 2**100`; pon entre comillas el código con espacios: `@question explain @py "sum(x * x for x in range(10))"`. Al revés no: el código de `@py` y `@js` siempre se ejecuta exactamente como lo escribiste, y los `@commands` que contenga no se ejecutan antes.

![Escribir @ abre la lista de comandos; @question más una pregunta, luego ⏎ para la respuesta](../en/commands.png)

![@open encuentra apps mientras escribes; si empieza por /, es una ruta: se muestra la carpeta y Tab completa](../en/open.png)

Cuando `@` no va seguido de un comando, como en `@john`, el `@` se inserta como siempre, así que mencionar a personas con @ en las apps de chat sigue funcionando. Escrito justo después de una letra, un dígito, `.`, `_` o `-`, como en `bob@example.com` o `ssh user@host`, `@` es solo texto: no se abre ninguna lista, en ninguna app, terminales incluidos. Con la lista abierta, ← → o una tecla que no puede formar parte del nombre de un comando (`.`, `:`, `/`) la cierran y dejan lo que escribiste (`@`, `@im`) tal cual; en un terminal, ← → entonces solo cierran la lista. `@question`, `@improve` y `@translate` envían a tu propio Bedrock solo cuando pulsas la tecla de acción; `@open` busca solo en este Mac; `@note` y `@reminder` van solo a Notas y Recordatorios en este Mac; `@agent` usa el agente instalado en tu Mac (de forma predeterminada, el comando `claude` de Claude Code) y su propia cuenta, y te pregunta primero, como siempre, antes de modificar archivos o ejecutar comandos. Sin el agente instalado, `@agent` no se ofrece. `@imessage` lee solo los Contactos de este Mac (nombres, números de teléfono, correos electrónicos), nunca pasa por la IA, y es Mensajes quien envía el mensaje; sin la app Mensajes no se ofrece.

`@calculate` funciona en este Mac, sin conexión: `+ - * /` (también `× ÷`), `^` o `**` para potencias, paréntesis, porcentajes (`50%` es 0,5, `200*5%` es 10; como en una calculadora, un porcentaje que se suma o se resta se calcula sobre lo anterior: `100+10%` es 110, `100-10%` es 90), las funciones `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` es en base 10, los ángulos están en radianes, `round(x, 2)` conserva dos decimales) y las constantes `pi` (`π`) y `e`. Los dígitos y signos de ancho completo también funcionan. La aritmética es exacta en decimal, así que `0.1+0.2` da `0.3`; los resultados tienen como máximo 15 cifras significativas, y los números enteros de hasta 38 cifras se escriben completos (`2^100` → `1267650600228229401496703205376`).

### Sobre el texto seleccionado (nuevo)

Selecciona texto en cualquier app (una frase en Notas, un párrafo en Mail), escribe `@improve`, `@translate`, `@question` u otro comando que tome texto y pulsa ⏎: el comando trabaja sobre la selección, y el resultado que elijas la sustituye. La selección se queda como está, seleccionada, mientras escribes: el comando se escribe en el panel de candidatos, cuya primera línea es lo que escribes y la siguiente "On the selection: “…” (N characters)" (sobre la selección: N caracteres). Esc, ⇧⏎ o hacer clic en otro sitio dejan el texto como estaba; lo mismo ocurre si cambias la selección entretanto, lo que cancela el comando. El texto escrito tras el comando es una instrucción para `@improve` y `@translate` (`@translate ja`, `@improve more formal`) y la pregunta para `@question` (`@question what does this mean`), sobre la selección. `@open`, `@agent`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, los comandos de terminal y las extensiones de script no la usan: toman lo que escribes, y la selección se queda como está. Hasta 5000 caracteres; nunca se lee durante la entrada segura ni en un terminal. Desactívalo en Settings → General → "Use the selected text" (usar el texto seleccionado) si funciona mal en alguna app.

### Refinar los resultados (nuevo)

Mientras se muestran los resultados de `@improve`, de un comando de instrucción (tuyo o de un plugin) o de la reescritura de una selección, escribe qué cambiar, como `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese` o `用更口语的说法` (el pinyin funciona, y una pulsación de Mayúsculas cambia de idioma), y pulsa ⇧⏎: los resultados vuelven a la IA con tu instrucción, y los nuevos los sustituyen en el mismo panel. ⏎ inserta el resultado seleccionado, también con una instrucción a medio escribir (se descarta). Refina tantas veces como quieras; la línea superior del panel enumera los pasos ("Refined: shorter · more formal"), y puedes elegir una fila en cualquier momento como siempre. Una letra empieza la instrucción (se muestra como "refine › …" arriba del panel); mientras está vacía, los dígitos, Espacio y ⏎ eligen como antes, y ⇧⏎ inserta tal cual lo que escribiste. El refinado empieza cuando los resultados están completos: escribir mientras aún llegan los primeros resultados continúa la frase, como antes. Mientras se ejecuta un refinado ya puedes escribir la siguiente instrucción; el refinado sigue, y ⇧⏎ lanza el siguiente en cuanto llegan sus resultados. Esc borra la instrucción, después retrocede un paso a los resultados anteriores al último refinado (durante un refinado: lo detiene) y luego vuelve a la frase; ⌫ en una línea vacía retrocede de la misma manera. Sobre texto seleccionado, el resultado que elijas sigue sustituyendo exactamente la selección, que no se toca hasta entonces. Un refinado que falla (o que se rechaza durante la entrada segura) deja los resultados como estaban, con su instrucción lista para volver a intentarlo con ⇧⏎. El mismo refinado de los mismos resultados se responde desde la caché. `@translate` no tiene refinado: escribir tras sus resultados continúa la frase, y ⏎ la vuelve a traducir.

### Conversaciones con @question (nuevo)

Una vez que `@question` ha respondido, lo que escribes es la siguiente pregunta: ⇧⏎ la hace, junto con las preguntas y respuestas anteriores, y el panel se convierte en la conversación, con las rondas anteriores atenuadas como filas Q / A y la última respuesta debajo. La línea superior indica qué ronda viene ("question 2/5 › …"). Cualquier respuesta se puede insertar: su dígito (1–5), ↑↓ y luego ⏎, o un clic; la última está seleccionada, y ⌘C copia la seleccionada. ⏎ la inserta aunque haya una pregunta a medio escribir (se descarta). Esc borra lo que escribiste y luego retrocede una ronda; en la primera, sale como antes. El panel crece hasta cerca de la mitad de la pantalla y después se desplaza, con lo último abajo.

Tras 5 rondas (`questionRounds` en la configuración, 2–10), la línea de la siguiente pregunta pasa a ser "5 rounds in: continue in Claude or another AI" (5 rondas: continúa en Claude u otra IA), con las opciones numeradas ⌘1, ⌘2 …; ⌘⏎ las muestra en cualquier ronda (mientras aún llega una respuesta no hace nada, y nunca llega a la app). Lo que escribas entonces es el primer mensaje allí; solo ⌘1, ⌘2 … lo envían (⇧⏎ ya no pregunta nada ni abre nada). Una pregunta sobre texto seleccionado se lleva ese texto, citado en un bloque propio. Las opciones:

- **El agente al que `@agent` pasa las tareas**, con su nombre (Claude Code de forma predeterminada, o Gemini CLI, Kiro CLI o tu propio comando, según lo elegido en Settings → General), cuando está instalado: una sesión interactiva en Terminal, que empieza con la conversación y "Let's continue this discussion".
- **Claude** o **ChatGPT** en la web, con la conversación ya rellenada (una larga va al portapapeles: pégala).
- **Gemini** en la web, con la conversación en el portapapeles para pegarla.
- **Copy the conversation** (copiar la conversación), en Markdown (**Q:** / **A:**).

Cuáles, y en qué orden (la primera es la predeterminada): Settings → General → "Continue a conversation in" (continuar una conversación en; `questionContinueIn` en la configuración). Con Apple Intelligence en este Mac, una conversación larga no cabe en su contexto pequeño: las respuestas más antiguas se acortan, luego se dejan fuera las rondas más antiguas, y el panel dice "earlier rounds shortened" (rondas anteriores acortadas). Una conversación se guarda bajo su primera pregunta en las preguntas recientes, y al elegirla se muestran las rondas para seguir con ella.

### Preguntas recientes (nuevo)

`@question` sin nada escrito detrás muestra tus últimas 5 preguntas, la más reciente primero, con cuándo se hicieron ("3 hours ago"). Al escribir se filtran: cada palabra en cualquier parte de la pregunta, sin distinguir mayúsculas (también chino sin espacios). Un dígito, ↑↓ y luego ⏎, o un clic muestra al instante la respuesta guardada de una pregunta, sin conectarse: Espacio o ⏎ la inserta, ⌘C la copia, ⌘R la vuelve a preguntar para obtener una respuesta nueva (en una conversación: su última pregunta), Esc vuelve a la lista. Una conversación guardada muestra todas sus rondas: escribe para seguir con ella. Sin coincidencias, o si no eliges nada, ⏎ pregunta lo que escribiste. Una respuesta nueva a la misma pregunta, o una conversación que continúa, sustituye a la guardada.

- Solo se guardan en este Mac (consulta Privacidad): no durante la entrada segura, y nunca las preguntas sobre texto seleccionado.
- Settings → General → "Remember recent questions" (recordar las preguntas recientes) lo desactiva (`rememberQuestions` en la configuración); desactivado ahí, también las borra. Desactivado con `@config`, se conservan, para que deshacerlo devuelva exactamente lo que había (su vista previa lo indica); "Clear (N)" (borrar) las borra.

### Notas y recordatorios

`@note` crea una nota nueva; su primera línea es el título. Después de copiar un texto, ⌃V tras `@note ` (o ⌘V, fuera de los terminales) lo guarda con sus saltos de línea, que se muestran como ↵ en el comando. Si sales del campo de texto (haciendo clic en otro sitio o cambiando de app) o pulsas ⇧⏎ (insertar tal cual) antes de que se guarde una nota con saltos de línea, no se escribe en la app (en un terminal, cada línea se ejecutaría como un comando): va al portapapeles ("The note wasn't saved; its text is on the clipboard"). Una nota de una sola línea se inserta tal cual.

`@reminder` entiende expresiones de tiempo como `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (su día 1), `end of the year` (también expresiones en chino). El día y la hora pueden ir separados (`tomorrow call Bob at 5`); las semanas empiezan el lunes. Una hora sin am ni pm (`at 5`) es la siguiente, nunca entre la medianoche y las 6 de la mañana; una hora que ya ha pasado hoy es mañana, pero una parte del día que aún no ha terminado (`this afternoon`, `tonight`) es hoy, para todo el día; una fecha que ya ha pasado este año es la del año que viene. Si está escrito para repetirse (`standup every Monday at 9`), se añade una vez, para la próxima ocasión: las palabras se quedan en el título y la fila indica "once only" (solo una vez). La fila de confirmación muestra la hora entendida, p. ej. "tomorrow 3:00 PM" (según el ajuste de 12/24 horas del Mac); si es incorrecta, Esc vuelve al texto. Si no contiene hora ni fecha, no tiene ninguna ("no date").

`@stock` y similares dentro de estos dos no se ejecutan: el texto se guarda tal como está escrito (escribir `@` ahí no abre la lista de comandos). La primera vez, macOS pregunta si AllInOneIME puede controlar Notas (`@note`) o acceder a Recordatorios (`@reminder`): permítelo. Si no lo hiciste, permite AllInOneIME en Ajustes del Sistema → Privacidad y seguridad → Automatización (Notas) o → Recordatorios. Cuando falla un guardado (por falta de permiso, por ejemplo), el aviso indica el motivo y el texto vuelve al comando, para corregirlo y enviarlo de nuevo; cuando primero tienes que arreglar algo (un permiso, una cuenta), también se copia al portapapeles (ir a Ajustes del Sistema quita el foco del campo de texto). Si te has movido a otro campo de texto o estás escribiendo otra cosa, va al portapapeles ("Not saved; the text is on the clipboard.").

### Tus propios comandos

En los ajustes, en "Custom @ Commands" (comandos @ personalizados), haz clic en "Add Command…" (añadir comando): ponle un nombre y elige qué hace (una instrucción para la IA, un programa, un programa en Terminal o una página web), o parte de un ejemplo. Tus comandos aparecen después de los integrados; los nombres solo admiten letras latinas y no pueden coincidir con el de un comando integrado; funcionan a partir de la siguiente frase. Se guardan en `customCommands` en el archivo de configuración (`~/.config/allinoneime/config.json`), que también puedes editar:

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | Qué hace |
|---|---|
| `prompt` | Va a la IA con `prompt` como instrucción; la respuesta aparece en los candidatos, para insertarla o copiarla (⌘C) |
| `run` | Ejecuta `argv` en segundo plano; lo que imprime aparece en los candidatos (varias líneas se insertan tal como se imprimen; en un terminal, como una sola línea). Si hay un error, se muestra su última línea |
| `terminal` | Ejecuta `argv` en una ventana nueva de Terminal; no se inserta nada |
| `link` | Pone el texto en la dirección web `url` y la abre en el navegador predeterminado; no se inserta nada |

- `{input}` se convierte en lo que escribiste después del comando, y siempre se queda dentro del único argumento en el que está: no interviene ningún shell. Si quieres un shell, indícalo, como `sh` arriba (`zsh -c`).
- `stdin`: lo que se pasa a la entrada estándar del programa, también con `{input}` sustituido.
- La `url` de un `link` debe empezar por `https://`, con `{input}` una sola vez, después del `?` o del `#`; el texto se codifica (un espacio es `%20`, un salto de línea `%0A`), con 4000 caracteres como máximo.
- `run` y `terminal` escriben letras latinas de forma predeterminada (como `@open`; en modo chino, el chino vuelve después), y la puntuación de ancho completo se convierte en ASCII. Define `"ascii": false` para conservar el texto tal como se escribió.
- Los programas se ejecutan en tu carpeta de inicio con el PATH de tu shell de inicio de sesión (así se encuentran las instalaciones de Homebrew, pyenv y nvm). `run` detiene un programa a los 10 segundos (`timeoutSeconds`) o cuando imprime demasiado; Esc lo detiene en cualquier momento.
- `summary` es la descripción en la lista de comandos (opcional).
- Cuando no se encuentra el programa de `argv` (por ejemplo, no hay `python3`), el comando no se ofrece y `@python …` se inserta como texto; una vez instalado, el comando aparece en el siguiente campo de texto.

`run` y `terminal` ejecutan código en tu Mac: añade solo comandos que hayas escrito tú y en los que confíes. También se ejecutan solo cuando pulsas la tecla de acción, y nunca durante la entrada segura.

### Extensiones de script

Añade tus propios comandos @ como programas: un script en cualquier lenguaje (bash, Python, Node, Swift, …) con unas pocas líneas de metadatos en sus comentarios. Colócalo en `~/.config/allinoneime/extensions`, o en una carpeta que añadas en Settings → Custom Commands → Script Extensions. Los Script Commands de Raycast funcionan tal cual, y las carpetas que ya los contienen se encuentran con Spotlight.

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh` es `@flights`. Escribe sus argumentos detrás, separados por comas: `@flights beijing, new york` lo ejecuta con `beijing` y `new york` como `$1` y `$2` (las comas sobrantes se quedan en el último); si un argumento obligatorio se deja vacío, indica qué falta en lugar de ejecutarse. Lo que imprime se usa según indique su `output`:

| `output` | Qué ocurre |
|---|---|
| `insert` (predeterminado) | Todo, y cada línea, para insertar |
| `show` | Se muestra en el panel a medida que se imprime (progreso); no se inserta nada. Si sales del campo, sigue en segundo plano (hasta cuatro a la vez) |
| `list` | Una lista en el JSON de Script Filter de Alfred, que se vuelve a ejecutar mientras escribes; elegir una fila inserta, abre (una dirección web, un archivo o una carpeta; nunca algo que se ejecutaría), copia o ejecuta un segundo paso |
| `silent` | Su última línea junto al cursor; no se inserta nada |

Un comando también puede no recibir entrada (`input none`: ⏎ sobre su nombre lo ejecuta), ejecutarse en segundo plano (`background`) y avisarte cuando termine (mientras tanto, el panel de la barra de menús lo muestra), mostrar un `status` junto a su nombre en la lista de comandos, o pedir confirmación antes (`confirm`). Se ejecuta en su propia carpeta con el PATH de tu shell de inicio de sesión y variables `ALLINONEIME_*`: el idioma de la interfaz y de entrada, la app en la que escribes, el texto. Un **bundle** es una carpeta con un `extension.json` que nombra sus comandos: comparten código y preferencias, que los ajustes muestran (las contraseñas van al llavero). Los ajustes muestran cada comando con un interruptor, y los scripts descartados con el motivo.

Los modos de Raycast se corresponden así: `fullOutput` → `show`, `compact` y `silent` → `silent`, `inline` con `refreshTime` → un estado. El protocolo completo está en [docs/extensions.md](../extensions.md); [Examples/extensions](../../Examples/extensions) tiene uno de cada tipo. Las extensiones ejecutan código en tu Mac: usa solo las que sean de confianza. Se ejecutan solo cuando las ejecutas tú (un estado o una lista mientras escribes), nunca durante la entrada segura, y se detienen cuando se cierra el método de entrada.

#### Fuentes de extensiones (nuevo)

Un bundle puede venir de un repositorio Git, tuyo o de tu equipo, y mantenerse actualizado desde ahí. Settings → Custom Commands → Extension Sources → **Add from Link…** (añadir desde un enlace): pega la dirección del repositorio (`git@github.com:you/my-extensions.git`, `ssh://…`, `https://…`; opcionalmente una rama, la carpeta del bundle dentro del repositorio y una etiqueta o un commit al que fijarlo). AllInOneIME lo clona con **tu propia configuración de git y SSH** (claves, agente, ~/.ssh/config, asistentes de credenciales), así que un repositorio privado funciona igual que en Terminal; la app nunca pide ni guarda una contraseña. El clon va a `~/Library/Application Support/AllInOneIME/Sources/`: primero a una carpeta de preparación oculta, nunca directamente a una carpeta de extensiones. (No pongas un nombre, una contraseña ni un token en una dirección https: el asistente de credenciales de git los guarda.)

- **Primero, la revisión.** Antes de que se cargue nada ves el bundle, cada comando (nombre, título, descripción, salida), los programas que ejecutan, sus preferencias y el commit, bajo el aviso "This source isn't signed: it will run programs from <address>" (esta fuente no está firmada: ejecutará programas de esa dirección). Solo **Enable** (activar) la añade; Cancel (cancelar) borra el clon. Cada fuente se revisa una sola vez.
- **Las actualizaciones las aplicas tú.** Una vez al día (y poco después de que arranque el método de entrada) se consulta la fuente (fetch) para ver qué hay de nuevo: los ajustes muestran "N updates" (N actualizaciones) con los commits (asunto, autor, fecha) y una insignia en la página. Nada cambia hasta que haces clic en **Update** (actualizar), que solo avanza en fast-forward y no ejecuta ningún hook. Un push forzado hace que la fuente necesite una nueva revisión: **Re-clone** (volver a clonar) la muestra, y solo Enable pone en su sitio el historial reescrito (hasta entonces, la versión revisada sigue funcionando). Una fuente fijada a una etiqueta o un commit no se comprueba. La comprobación diaria se desactiva fuente por fuente (`autoCheck`).
- **Los errores** son las propias palabras de git, con "This uses your own git and SSH setup; check that `git ls-remote <url>` works in Terminal" (esto usa tu propia configuración de git y SSH; comprueba que ese comando funciona en Terminal), y debajo tu propio recordatorio, si definiste uno (`authHint` en la configuración).
- **Remove** (quitar) mueve el clon a la Papelera; las preferencias del bundle se conservan para la próxima vez.
- Desde un terminal: `AllInOneIME --add-source <url> [--path …] [--branch …] [--pin …]` (muestra la revisión y la activa; otra vez tras un push forzado), `--update-sources` (avanza en fast-forward cada fuente revisada que no esté fijada), `--list-extensions` (sobre `~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME`).
- Solo se carga código revisado: una carpeta de fuente de la lista de carga que no se revisó en este Mac (una configuración copiada) se deja fuera. git nunca espera una respuesta: sin terminal y sin preguntas, así que una clave de host desconocida o una petición de contraseña falla al instante.

La configuración las guarda como `extensionSources`; la estructura del repositorio está en [docs/extensions.md](../extensions.md#10-extension-sources).

### Plugins

Los plugins son comandos `@` listos para usar para cosas que no todo el mundo necesita, como `@stock AAPL 600519 700` para cotizaciones bursátiles. Una vez instalados, funcionan como cualquier comando; "Plugins" en los ajustes muestra qué hay instalado y adónde envía cada uno tu texto, y permite eliminarlos. Los plugins son JavaScript que se ejecuta en un proceso aparte: solo pueden acceder a los sitios web que declaran (HTTPS), y no pueden leer archivos ni ejecutar otros programas. "Browse Library…" (explorar biblioteca), en Plugins dentro de los ajustes, los instala desde la [biblioteca de plugins](https://github.com/MicroZ-LLC/AllInOneIME-plugins): muestra con qué sitios web contacta un plugin antes de instalarlo; el índice de la biblioteca está firmado y cada archivo debe coincidir con él. Una versión más reciente muestra un botón "Update" (actualizar); nada se actualiza por sí solo. Tus propios plugins van en `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): plugins locales que la biblioteca nunca sobrescribe. Los plugins de tipo "Link" no ejecutan código: ponen el texto en una dirección web y la abren en el navegador, como `@x nice weather today`, que abre el editor de publicaciones de X con el texto ya escrito; publicar en la página depende de ti. La biblioteca tiene cuatro (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` convierte divisas: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, en una línea con la fecha del tipo de cambio (tipos de ExchangeRate-API). Cómo escribir uno: [docs/plugins.md](../plugins.md).

Los comandos que obtienen algo (plugins y programas) también funcionan dentro de una frase: `@reply tell her @stock AAPL is up today`. Los interiores se ejecutan primero, su salida ocupa su lugar y el comando exterior trabaja sobre el resultado. El argumento es la palabra que sigue al comando, más los códigos en mayúsculas o los números que vienen justo después (`@stock AAPL TSLA`, `@stock 600519 700`); una palabra en minúsculas lo termina (`@stock SNDK is good to buy` consulta SNDK). Las comillas lo delimitan con exactitud: `@stock "aapl tsla"`. `@calculate` también funciona dentro de una frase; su argumento es toda la expresión que le sigue, espacios incluidos, hasta otro texto: `@reply the total is @calculate 23 * 17 dollars`. Dentro de `@agent` y de los comandos de terminal no se ejecutan: estos reciben el texto tal como está escrito (escribir `@` ahí no abre la lista de comandos).

### Tecla de acción

⏎ de forma predeterminada; cámbiala en "Action key" (tecla de acción) en los ajustes (`actionKey` en la configuración): ⏎, Tap ⌥ (pulsación breve de ⌥, de cualquier lado: pulsar y soltar enseguida; mantener ⌥ derecha sigue siendo para hablar), ⌥Espacio, o Espacio (pulsa Espacio una vez más después de elegir las palabras; dos veces en modo inglés). Sea cual sea la tecla de acción, los comandos @ también se ejecutan con ⏎. Si ⌥Espacio ya es un atajo de Alfred, Raycast o similares, estos lo reciben primero.

### Escribir los resultados

Activa "Type results out" (escribir los resultados) en Settings → General (`typeOut` en la configuración) y el resultado de un comando se escribe en la app carácter a carácter, como lo haría una persona, en lugar de entrar de golpe; las palabras elegidas en pinyin siguen entrando de golpe. El control deslizante fija el ritmo, de 6 segundos por carácter a 40 por segundo (`typeOutRate`), y "Speed up and slow down (like a person)" (acelerar y frenar, como una persona) escribe a ráfagas de ritmo cambiante (`typeOutVaries`). Esc lo detiene donde esté; cualquier otra tecla escribe el resto de golpe.

"Make occasional typos and fix them" (cometer alguna errata y corregirla, `typeOutMistakes`) lo hace aún más humano: de vez en cuando la tecla de al lado de la correcta, advertida hasta tres letras después, borrada y vuelta a escribir; una letra o un espacio escritos dos veces y borrados; o una palabra corta escrita, borrada y vuelta a escribir. Unas pocas cada 100 caracteres, nunca dos seguidas y nunca al principio de una línea. En código, direcciones web y de correo y números, una errata es solo una letra o un dígito equivocados, corregidos al momento (nunca un paréntesis, una comilla o un espacio equivocados, con los que los editores emparejan o sangran). Las letras equivocadas son vecinas en tu distribución de teclado (QWERTY, AZERTY, QWERTZ…). El chino, el japonés y el coreano solo dudan (dos caracteres escritos, borrados y vueltos a escribir), nunca con un carácter equivocado.

En un campo que admite deshacer una errata (las vistas de texto de Apple como TextEdit y Notas, los navegadores, la mayoría de los editores): escrito hasta el final, o con otra tecla pulsada para escribir el resto de golpe, el texto es exactamente el resultado; Esc (o salir del campo) en medio de una errata quita primero la errata, de modo que el campo contiene un comienzo exacto del resultado. Si el cursor se mueve mientras se ve una errata (un clic), la errata se quita donde estaba y el resto se escribe sin erratas.

Nunca se cometen erratas en terminales, ni en apps que no le dicen al método de entrada dónde está el cursor. Cada vez, la primera errata es una sencilla (una letra equivocada, corregida de una vez), hasta que el campo ha demostrado que admite deshacer una errata; mientras se ve una errata, el método de entrada comprueba antes de cada tecla que el campo contiene lo que escribió. Un campo que ignora dónde reemplazar texto no puede deshacer una errata: ahí esa primera errata se queda, así que el texto acaba con un carácter de diferencia (también tras Esc u otra tecla), y la app ya no recibe erratas. Settings → General enumera esas apps bajo el interruptor de erratas; "Forget apps where typos couldn't be fixed" (olvidar las apps donde no se pudieron corregir erratas) les deja volver a intentarlo.

### Ajustes por app (nuevo)

Settings → Apps da a una app sus propios ajustes, todos opcionales; lo que una app no define sigue los ajustes de todas las apps:

| Ajuste | Por ejemplo | En la configuración |
| --- | --- | --- |
| El idioma de entrada con el que empiezan sus campos de texto | Slack en inglés, WeChat en pinyin | `inputLanguage` |
| Los estilos de reescritura que `@improve` ofrece ahí | Mail formal y diplomático, Slack informal | `rewriteStyles` |
| Escribir los resultados, o no | activado en una app de chat, desactivado en Mail | `typeOut` |
| Sin IA en esta app | `@improve`, `@translate`, `@question`, `@agent` y tus comandos de instrucción no envían nada ahí y lo avisan; escribir y los demás comandos funcionan | `noAI` |

"Add App…" (añadir app) muestra las apps en las que escribiste últimamente, o elige una en /Applications. El menú de entrada, con "This App: <nombre>", tiene interruptores rápidos para la app en la que escribes (No AI, Type Results Out, el idioma de inicio). En la configuración están en `appProfiles`, por ID de paquete (bundle ID): `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. Los ID de paquete se comparan sin distinguir mayúsculas (`com.apple.Mail` es el `com.apple.mail` de Mail). `@reportissue` cuenta las apps que definen algo, sin nombrarlas nunca.

- El idioma de inicio funciona como el idioma de entrada predeterminado: un campo de texto lo toma cuando se activa, y un cambio con Mayúsculas se mantiene después para los campos de esa app hasta que cambie el ajuste.
- Con No AI, los comandos de IA siguen en la lista @; ejecutar uno muestra el aviso y conserva lo que escribiste. Tus propios comandos de terminal (`"type": "terminal"`) ejecutan programas, no la IA, así que ahí siguen funcionando.

### Cambiar los ajustes describiéndolos (nuevo)

`@config` convierte una frase en ajustes: `@config output languages English and French`, `@config 微信里用中文，邮件里语气正式一点`, `@config candidates in a column`, `@config turn off the typos`, `@config use Claude`. ⏎ muestra los cambios en el panel de candidatos, uno por fila, antes → después, con las etiquetas que usan los ajustes ("Translation languages: English, Japanese → English, French", "Apps · WeChat · Starts in: Same as everywhere → Chinese"); todavía no se cambia ni se escribe nada. ⏎ (o 1) los aplica todos, Esc cancela, y escribir más y luego ⇧⏎ refina la propuesta ("también alemán"; ⇧⏎ sin nada escrito no hace nada, y ⏎ aplica la propuesta mostrada). Una vez aplicados, ⌘Z mientras se ve la confirmación, o `@config undo` en los 10 minutos siguientes, restaura exactamente los valores que tenían esos ajustes.

- **Qué puede cambiar:** los idiomas de traducción y de entrada (y el predeterminado), los estilos de reescritura, la disposición de los candidatos, el tecleo de los resultados (activado o no, velocidad, acelerar y frenar, errores de tecleo), el uso de la selección, recordar las preguntas, ocultar información sensible (activado o no, qué se oculta, palabras que añadir), la búsqueda de actualizaciones, los ajustes por app (una app nombrada como tú la llamas, encontrada entre tus apps por su nombre o su ID de bundle) y el proveedor de IA: cuál, el perfil de Bedrock (de `~/.aws`) y la región, un modelo que la app conoce para él, y una URL base compatible con OpenAI (solo `https://`).
- **Qué no toca nunca:** las claves de API y todo lo que hay en el llavero, los comandos personalizados, las carpetas y fuentes de extensiones, los plugins, la lista de jerga, todo lo que ejecuta programas y cualquier otro ajuste. Esas filas se rechazan, con el motivo, y el resto se puede aplicar igualmente.
- **Comprobado como en los ajustes:** un idioma que no lo es, más de 5 idiomas de traducción, un valor fuera de rango, una app que no logra identificar, o un idioma cuyo paquete no está instalado ("needs the Korean language pack: download it in Settings → Input", es decir, hace falta el paquete de idioma coreano: descárgalo en Settings → Input) se rechaza fila por fila; nunca se escribe una configuración no válida.
- **Claves:** nunca cambia a un proveedor que no tiene clave (ni en el llavero ni en tu shell): la fila dice "Gemini API needs an API key: ⏎ opens Settings to add it (never sent to the AI); you can switch to it there" (la API de Gemini necesita una clave de API: ⏎ abre los ajustes para añadirla, nunca se envía a la IA; allí puedes cambiar a ella), y aplicarla abre Settings → AI Provider con una pequeña hoja para esa clave (Save para guardarla, o Save and Use para guardarla y cambiar a ese proveedor), mientras las demás filas se aplican igualmente. Con una clave, el proveedor cambia, se ejecuta Test Connection y su resultado aparece bajo la confirmación. Una clave escrita en la frase se elimina antes de enviar nada.
- **Primero en este Mac:** usa Apple Intelligence siempre que este Mac la tenga (macOS 26), sea cual sea el proveedor que elegiste e incluso antes de configurar uno, limitada a los ajustes y valores permitidos, con consultas de tus apps, perfiles de AWS y paquetes de idioma. Sin ella, responde tu proveedor. La solicitud contiene solo los ajustes permitidos y sus valores actuales (nunca una clave, ni las palabras que ocultas), y la ocultación de información sensible se aplica como en cualquier solicitud.

### Comprobar tu instalación (nuevo)

`@doctor` ⏎ comprueba la instalación de este Mac en un segundo o dos (mientras tanto se muestra la prueba de conexión) y muestra los resultados en el panel de candidatos, uno por fila, primero los problemas ✗, luego las advertencias ⚠ y luego ✓ lo que está bien, cada uno con un breve arreglo: el método de entrada (instalado, activado, en tus fuentes de entrada), el proveedor de IA (su clave guardada o las credenciales del perfil de Bedrock encontradas, nunca leídas ni mostradas; Test Connection; Apple Intelligence), los permisos (Accesibilidad, el micrófono si dictas, controlar Notas, Recordatorios, Terminal y Mensajes, consultados a macOS sin mostrar ninguna petición), la entrada segura, los paquetes de idioma de tus idiomas de entrada, `config.json` (legible, claves desconocidas, valores fuera de rango, un idioma repetido, más de 5 idiomas de traducción), las extensiones y plugins que no se cargaron, las actualizaciones y los errores recientes en los registros propios de la app.

Las filas con un arreglo están numeradas: un dígito (o un clic) muestra lo que hace en la vista previa de `@config`, y ⏎ lo aplica; ⏎ sobre la lista arregla de una vez todos los que no tienen riesgo (ajustes reparados, idiomas repetidos eliminados, el método de entrada activado de nuevo). Abrir un panel de Ajustes del Sistema, descargar un paquete de idioma, Check for Updates (abre los ajustes) y el campo de la clave en los ajustes se eligen uno a uno. Los cambios de ajustes se deshacen como los de `@config` (⌘Z, `@config undo`). Ningún arreglo borra tus datos ni toca una clave.

`@doctor <question>` (`@doctor why doesn't translate work`) ejecuta las comprobaciones, luego la IA explica la causa probable a partir de sus resultados y marca los arreglos que sugiere (⏎ sigue aplicando solo los que no tienen riesgo; los demás, por su número). En una app con No AI, las comprobaciones se ejecutan igualmente y solo se rechaza la pregunta. Responde Apple Intelligence cuando este Mac la tiene, y llama como herramientas a las comprobaciones que necesita; si no, tu proveedor, y el panel lo indica. Solo se envían los resultados de las comprobaciones (ninguna ruta más allá de `~`, ninguna clave, nada de tu texto) y tu pregunta; las comprobaciones no envían nada salvo la solicitud de Test Connection (solo cuando el proveedor tiene una clave o credenciales que probar).

## Panel de la barra de menús

<img src="../en/panel-swipe.png" width="520" alt="El panel de la barra de menús: cristal esmerilado, con notas, recordatorios y tareas de Claude en tarjetas; una fila deslizada hacia la izquierda muestra su botón Remove">

Haz clic en el icono de AllInOneIME en la barra de menús (la marca de ∞ con un cursor, sin recuadro; la que tiene recuadro es la fuente de entrada) y el panel se despliega debajo; un clic en otro sitio lo cierra:

- Notes (notas): las notas guardadas con `@note`, las 5 más recientes; haz clic en una para abrirla en Notas.
- Reminders (recordatorios): los recordatorios aún no completados de la lista AllInOneIME de Recordatorios (`@reminder` los añade a esa lista), primero los que vencen antes, 8 visibles; haz clic en el círculo para marcar uno como hecho, o en el título para abrir Recordatorios.
- Claude Tasks (tareas de Claude): como `@tasks`, las tareas de Claude en segundo plano (lo que `@agent` delega en Claude Code), hasta 30, 5 visibles a la vez: desplázate para ver más, o busca en sus títulos y respuestas con el campo de búsqueda; con su progreso y la primera línea de la última respuesta; haz clic en una para abrirla en Terminal y continuar.

Desliza una fila (una nota, un recordatorio o una tarea) hacia la izquierda con dos dedos para mostrar su botón Remove (eliminar), o hasta el final para eliminarla de una vez; con un ratón, haz clic derecho sobre ella. Eliminar solo la quita del panel: la nota sigue en Notas, el recordatorio en Recordatorios (sin completar), la tarea en Claude Code.

La cabecera muestra los recuentos (como "2 reminders · 1 task running"; las tareas que te esperan se cuentan aparte, como "1 waiting for you") y un botón para actualizar. Nunca le quita el foco a la app en la que escribes: marcar un recordatorio o actualizar deja esa app en primer plano; solo el campo de búsqueda de las tareas de Claude, una vez que haces clic en él, toma el teclado. El icono se muestra de forma predeterminada; desactívalo en "Menu Bar Panel" en los ajustes.

Qué lee y cuándo:

- Notas: la lista es el registro propio del panel (que se conserva también mientras está cerrado), y Notas nunca se abre: solo cuando Notas ya está en ejecución, y AllInOneIME tenía permiso previo para controlarla, el panel comprueba en ella los títulos editados y las notas eliminadas.
- Recordatorios: la lista AllInOneIME se lee cuando el panel se despliega, cada 60 segundos y cuando cambian los recordatorios. El panel nunca hace que macOS pida acceso por su cuenta: si macOS aún no te lo ha pedido, muestra "Allow Access to Reminders" (permitir acceso a Recordatorios), y solo ese botón lo pide; si dijiste que no, muestra "Open System Settings" (abrir Ajustes del Sistema).
- Tareas de Claude: el panel ejecuta `claude agents` solo mientras está desplegado: una vez al desplegarse, al actualizar y cuando `@agent` delega una tarea; y cada 15 segundos mientras alguna tarea no haya terminado, y ya no cuando todas han terminado. Las últimas respuestas se leen del final de las transcripciones de Claude Code en este Mac (`~/.claude/projects`), y solo cuando una transcripción ha cambiado.
- Mientras está cerrado, nada de esto se ejecuta; solo mantiene un registro de las notas que guarda `@note`.

## Entrada y traducción

En los ajustes:

- **Idiomas de entrada**: de uno a cinco entre inglés, chino (pinyin), francés, coreano e hindi, añadidos con + (siempre visible; atenuado al llegar a cinco). Una instalación nueva empieza solo con inglés. Los campos de texto nuevos empiezan en el primero; pulsa Mayúsculas para pasar al siguiente, en su orden; con uno solo, Mayúsculas no cambia nada.
  - **El francés** se escribe con su propia distribución de teclado: AZERTY, salvo que elijas otra en su tarjeta. Sus teclas muertas (^, ¨, `, ´, ~) también componen a partir de ella.
  - **El coreano** escribe hangul con la distribución de 2 grupos (Dubeolsik), y cada sílaba se compone mientras escribes (g k s → 한); Mayúsculas da ㄲ ㄸ ㅃ ㅆ ㅉ y ㅒ ㅖ.
  - **El hindi**: escribe las palabras tal como suenan con letras latinas y obtén devanagari (namaste → नमस्ते). Las palabras comunes se escriben como se escriben en hindi; si no, Espacio inserta la primera grafía, un dígito otra, ⏎ las letras tal como se escribieron, y "." el danda (।).
  - El nombre de un comando, el texto de `@open` y el código (`@py`, `@js`) se escriben con letras latinas sea cual sea el idioma; este vuelve después del comando.
  - `@improve` mantiene una frase en coreano, hindi o francés en su propio idioma, y `@translate` la traduce a tus idiomas (el francés se distingue del inglés cuando es uno de tus idiomas de entrada).
- **Paquetes de idioma**: la app incluye inglés (y francés, que solo necesita la distribución de macOS). El chino, el coreano y el hindi son paquetes que descargas al añadirlos: añadir el chino (pinyin) descarga sus diccionarios (unos 34 MB, 125 MB descomprimidos) con una barra de progreso, y el pinyin funciona en cuanto termina, sin reiniciar; el paquete del coreano (su tabla de teclas y cómo los jamo forman sílabas) y el del hindi (sus letras y palabras comunes) ocupan unos pocos kilobytes. Un paquete contiene solo datos (diccionarios, tablas y esquemas, nunca código), figura en un índice firmado y se comprueba con su SHA-256 antes de usarse, como los plugins. La tarjeta de cada idioma muestra su paquete (versión, tamaño, procedencia) con Delete… (eliminar), y al quitar el idioma se ofrece eliminar su paquete. Actualizar desde la 0.6.1 o anteriores conserva el chino sin descarga: el instalador conserva los diccionarios que traía la versión anterior.
- **Disposición de los candidatos**: para elegir palabras, los candidatos de pinyin y de hindi aparecen uno al lado de otro de forma predeterminada (Horizontal), como en los métodos de entrada del propio sistema: ← → eligen y ↑↓ (o - =) pasan de página. Elige Vertical en la página Input, bajo los idiomas de entrada, para verlos uno debajo de otro (↑↓ eligen). La lista de comandos @ y los resultados son siempre verticales.
- **Pinyin difuso** (con entrada en chino): sonidos que no distingues, escritos de cualquiera de las dos formas, p. ej. z ↔ zh, n ↔ l, in ↔ ing. En la página Input, elige Chinese (pinyin) en la barra de idiomas de entrada, activa "Fuzzy pinyin" y elige los pares; los diccionarios se vuelven a desplegar en uno o dos segundos. Escribe `rime_ice.custom.yaml` en la carpeta de usuario de Rime, y nunca sobre un archivo tuyo que esté ahí.
- **Traducción (@translate)**: añade los idiomas a los que traducir (español, francés, alemán, japonés, coreano, chino, hindi, bengalí, tamil y las demás lenguas principales de la India…) y arrástralos para ordenarlos. El hindi escrito con letras latinas ("aap kaise ho") vuelve en devanagari. `@translate` escribe una línea en cada uno, en este orden (tres versiones si solo hay uno); se omite el idioma de la propia frase. Una instalación nueva traduce al primer idioma de los idiomas preferidos de tu Mac que no sea el inglés; si solo hay inglés, `@translate` abre esta página para añadir uno.
- **Distribuciones de teclado**: el francés se escribe con la distribución elegida en su tarjeta (`keyboardLayouts` en la configuración). Para los demás idiomas, bajo el método de entrada macOS mantiene tu última distribución latina (AZERTY, QWERTZ, español, U.S. International…), así que escribes como siempre, `@` incluida dondequiera que la tenga tu distribución, y las teclas muertas también componen en el texto de un comando (⌥E y luego E → é, ^ y luego e → ê). Las distribuciones sin letras latinas (ruso, hindi InScript) no se pueden usar bajo un método de entrada: cambia a ellas con ⌃Espacio, o pega (⌃V) o dicta el texto en un comando.
- `@improve` pule y reescribe sin traducir; `@translate @improve` juntos traducen y reescriben en una sola petición. Activa "@improve also translates" en los ajustes para que `@improve` haga siempre eso.

## Estilos de reescritura

Después de las líneas 1–3 vienen las reescrituras, **en el idioma en el que escribiste**: reescrituras en inglés para el inglés, en chino para el chino. Elige las que quieras en los ajustes:

- Polish (pulir): mismo tono, más natural
- Concise (conciso)
- Formal: para jefes y clientes
- Casual (informal)
- Tactful (diplomático)
- Jargon (jerga): la jerga de Amazon en inglés (bandwidth, circle back…), la jerga de las grandes tecnológicas en chino. Las malas noticias se suavizan, p. ej. "this is a blocker bug" → "Oh! Looks like your team has the bandwidth to fix this minor issue!"

No se muestran las reescrituras que solo cambian la puntuación o repiten otra línea.

### Lista de jerga (tus propios términos)

Jargon no tiene una lista de términos integrada. Puedes preparar la tuya (por ejemplo, las expresiones que usa tu equipo), y el modelo da preferencia a sus términos. En los candidatos, la línea de Jargon indica qué significan los términos que ha usado.

La lista es un archivo de texto con un término por línea, seguido opcionalmente de su significado, separado por "=", dos puntos o una tabulación (puedes copiar dos columnas de una hoja de cálculo y pegarlas). Las líneas que empiezan por `#` son comentarios:

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

En "Rewrite Styles → Jargon list" en los ajustes, haz clic en "New" (nueva) para crear una lista vacía en `~/.config/allinoneime/jargon.txt` y abrirla; si ya tienes un archivo de lista, haz clic en "Choose File…" (elegir archivo) para usarlo donde está (`jargonFile` en la configuración). Los cambios se aplican al instante. Solo se leen los primeros 150 términos. Con "Jargon" marcado, la lista se envía a Bedrock junto con cada petición.

<img src="../en/panel-dark.png" width="420" alt="El panel de candidatos en modo oscuro">

## Entrada por voz

<img src="../en/voice.png" width="340" alt="Mantén pulsada ⌥ derecha para hablar">

Mantén pulsada ⌥ derecha y habla; al soltarla, se inserta el texto. Se reconoce en el idioma en el que escribes (inglés, chino, francés, coreano o hindi). Si primero escribes un comando (p. ej. `@improve `, `@question `) y luego hablas, el texto va detrás del comando y ⏎ lo ejecuta; también puedes pulsar ⏎ sin soltar ⌥ derecha para ejecutarlo en cuanto termines. La voz se reconoce en el Mac con el reconocimiento de voz integrado de macOS (SpeechAnalyzer), y no se sube ningún audio; requiere macOS 26 o posterior.

La primera vez:

- macOS pregunta si AllInOneIME puede usar el micrófono. También puedes hacer clic antes en "Allow Microphone" (permitir micrófono) en los ajustes.
- Si este Mac aún no tiene el modelo de voz de ese idioma, se descarga una vez, automáticamente. También puedes descargarlo en los ajustes.

La grabación empieza solo después de mantener la tecla unos 0,2 s, así que una pulsación breve de ⌥ derecha no enciende el micrófono (con la tecla de acción en "Tap ⌥", una pulsación breve ejecuta la acción). Si pulsas otra tecla mientras la mantienes (un atajo con ⌥, ⌥←), cuenta como un atajo y tampoco se graba nada. Pulsar cualquier otra tecla durante la grabación la cancela.

## Instalación

Para usarlo se necesita macOS 14 o posterior, y para la entrada por voz macOS 26 o posterior. El instalador es universal: funciona en Macs con Apple silicon e Intel. Hasta ahora solo se ha probado en macOS 27 con Apple silicon (la compilación para Intel solo mediante su autoprueba en Rosetta).

1. Descarga `AllInOneIME-<version>.dmg` de [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) (solo de ahí) y ábrelo.
2. Haz doble clic en "Install AllInOneIME", dentro de él, y haz clic en Install. El método de entrada se instala en `~/Library/Input Methods` y "AllInOneIME Settings" en `~/Applications`. Solo para este usuario; no hace falta contraseña de administrador.
3. El instalador está firmado con un Developer ID y notarizado por Apple, así que la primera vez macOS solo pregunta si quieres abrir una app descargada de internet: haz clic en Abrir. (Las versiones anteriores a la 0.6.3 no estaban notarizadas: cada una había que permitirla una vez en Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente.)

Después, AllInOneIME está activado y entre tus fuentes de entrada; cambia a él con Ctrl+Espacio (la tecla 🌐 solo cambia si "Pulsar la tecla 🌐 para" está en "Cambiar fuente de entrada" en Ajustes del Sistema → Teclado). Si el instalador te dice que lo añadas a mano, este Mac no permite que los programas lo activen, así que añádelo tú una vez: Ajustes del Sistema → Teclado → Entrada de texto → Fuentes de entrada → Editar… → + (abajo a la izquierda) → Inglés → AllInOneIME (también escribe pinyin cuando añades el chino en Input, en sus ajustes).

Si Ctrl+Espacio no te lleva a AllInOneIME, o vuelve a U.S. al cabo de un rato, ejecuta de nuevo el instalador: vuelve a añadir AllInOneIME a tus fuentes de entrada.

Actualizar: Settings → About → Check for Updates (buscar actualizaciones). Cuando hay una versión nueva, About lo dice (y una línea en el panel de la barra de menús), con las novedades; "Update to <version>" (actualizar a <versión>) la descarga, la comprueba con la información de actualización firmada con la clave de publicación de AllInOneIME, la instala y reinicia el método de entrada. Tus ajustes, paquetes de idioma, palabras aprendidas y extensiones se conservan, y si algo sale mal se restaura la versión que tenías. AllInOneIME lo comprueba solo una vez al día, en segundo plano (desactívalo con "Check for updates automatically" en About); no se instala nada hasta que haces clic. Esto funciona a partir de la 0.6.3; para actualizar una versión anterior, o si lo prefieres, instala la imagen de disco de la nueva versión encima, sin desinstalar antes. Antes de actualizar, lee el [registro de cambios](../../CHANGELOG.md): contiene los cambios de cada versión y las notas de actualización.

Actualizar a la 0.6.3 desde una versión anterior: la 0.6.3 es la primera versión firmada con un Developer ID, así que el llavero aún no la reconoce como la app que guardó tus claves. La primera vez que necesita cada clave que guardó (una clave de API, el inicio de sesión de AllInOneIME Cloud, la contraseña de una extensión), macOS pide tu contraseña de inicio de sesión: escríbela y haz clic en "Always Allow" (Permitir siempre). No vuelve a pedirla, tampoco tras actualizaciones posteriores. Las claves de Amazon Bedrock están en `~/.aws/credentials`, que no se ve afectado. La accesibilidad (Ajustes del Sistema → Privacidad y seguridad → Accesibilidad), que usan el pegado en terminales y la lectura de la selección, también necesita un paso: si AllInOneIME aparece en la lista, quítalo y vuelve a activarlo cuando se te pida.

Si tenías instalado AIPinyin (el nombre anterior de AllInOneIME), simplemente instala: se eliminan la antigua AIPinyin.app y su lanzador de ajustes, y la entrada de tus fuentes de entrada recibe el nuevo nombre, sin necesidad de volver a añadirla. Los ajustes, la lista de jerga y las palabras aprendidas se mueven a las nuevas carpetas (`~/.config/allinoneime` y otras) en el primer arranque, y cada carpeta antigua queda como un enlace a la nueva.

Para desinstalar, abre "Install AllInOneIME" y haz clic en Uninstall…. Se conservan los ajustes y las palabras aprendidas.

### Compilar desde el código fuente

Para compilar se necesita Xcode 26 o posterior, ya que la entrada por voz usa el SDK de macOS 26.

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` descarga librime y los diccionarios de rime-ice y los verifica, compila e instala en los mismos lugares, añadiéndolo a tus fuentes de entrada del mismo modo. La app que instala no tiene diccionarios de chino (son el paquete de idioma chino): una instalación que ya los tenía los conserva como paquete; si no, `make install-pack` instala el paquete a partir de los diccionarios del repositorio local, sin descarga. `make status` muestra la versión instalada (`version:`) y si está en tus fuentes de entrada (`listed:`). Para desinstalar: `make uninstall`.

## Configurar la IA

Las traducciones y reescrituras usan tu propio proveedor de IA, y los costes van a tu cuenta: Amazon Bedrock en tu cuenta de AWS de forma predeterminada, o la API de Claude, Gemini o un servicio compatible con OpenAI (consulta "Otros proveedores de IA" más abajo).

### Amazon Bedrock

1. Activa Bedrock en la consola de AWS y asegúrate de poder usar el modelo elegido. El predeterminado es Claude Haiku 4.5; la primera vez que usas un modelo de Anthropic, rellenas una vez un formulario de caso de uso.
2. Usa un perfil de AWS con permiso para `bedrock:InvokeModelWithResponseStream`: claves estáticas en `~/.aws/credentials`, o un perfil que obtiene credenciales temporales (`credential_process`, un rol, SSO; consulta "Perfiles de AWS" más abajo).
3. Abre "AllInOneIME Settings": puedes encontrarlo en Spotlight o en Aplicaciones, o abrirlo desde el icono del método de entrada en la barra de menús → Settings…. Elige el perfil, la región y el modelo, y haz clic en "Test Connection" (probar conexión). "Language" (idioma), en la parte superior de la ventana de ajustes, puede ser English o Chinese; de forma predeterminada ("System") sigue al sistema (chino si el chino va antes que el inglés en los idiomas preferidos del sistema, inglés en caso contrario). La ventana de ajustes, las indicaciones del panel de candidatos y el menú de entrada siguen todos este ajuste.

<img src="../en/settings.png" width="420" alt="La ventana de ajustes">

#### Perfiles de AWS

Funciona cualquier perfil que la AWS CLI pueda usar sin preguntarte nada, de `~/.aws/config` y `~/.aws/credentials` (o de los archivos que indiquen `AWS_CONFIG_FILE` y `AWS_SHARED_CREDENTIALS_FILE` en tu shell). Dentro de un perfil se usa la primera de estas fuentes que tenga, en el orden de la AWS CLI (un perfil con `role_arn` y claves a la vez es un rol):

| Tipo | En el perfil | Renovación |
| --- | --- | --- |
| Rol | `role_arn` con `source_profile` (de cualquier tipo, también en cadena; un perfil que se nombra a sí mismo usa sus propias claves) o `credential_source = Environment`; `role_session_name`, `external_id`, `duration_seconds` | otra vez con STS `AssumeRole` (en la `region` del perfil o, si no, us-east-1) 5 minutos antes de que caduquen |
| SSO | `sso_account_id`, `sso_role_name` con `sso_session` y su sección `[sso-session …]` (o los antiguos `sso_start_url`, `sso_region`) | se obtienen de nuevo con tu inicio de sesión en caché 5 minutos antes de que caduquen |
| Claves estáticas | `aws_access_key_id`, `aws_secret_access_key` (y `aws_session_token`) en `~/.aws/credentials` | se leen de nuevo en cada solicitud |
| `credential_process` | `credential_process = /usr/local/bin/my-creds --profile dev` (dividido como un comando de shell, ejecutado sin shell, con el PATH de tu shell de inicio de sesión, en tu carpeta de inicio, 60 s como máximo) | se ejecuta otra vez 5 minutos antes de su `Expiration`; si no tiene, cuando AWS rechaza las credenciales |
| Claves estáticas | las mismas claves en `~/.aws/config` | se leen de nuevo en cada solicitud |

Con el perfil "default" (o sin ninguno elegido), las claves de tu shell van primero, como las toma la AWS CLI: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN`. Un perfil que nombras nunca se mezcla con ellas. `AWS_REGION` (o `AWS_DEFAULT_REGION`) en tu shell prevalece sobre la `region` de un perfil, como en la AWS CLI; el campo Region de los ajustes prevalece sobre ambos.

- **Automático:** las credenciales que caducan se guardan en memoria (nunca se escriben en disco) y se obtienen de nuevo 5 minutos antes de que caduquen; si quedan menos de 10 minutos, una solicitud las usa y obtiene otras nuevas en segundo plano, así que la escritura no espera. Las solicitudes simultáneas esperan a una sola obtención. Cuando Bedrock responde que las credenciales caducaron (`ExpiredTokenException` …), se obtienen de nuevo y la solicitud se vuelve a enviar, una sola vez.
- **SSO:** AllInOneIME usa el inicio de sesión que la AWS CLI guarda en `~/.aws/sso/cache` (solo lo lee) y no puede iniciar sesión por ti, porque para eso hace falta un navegador. Cuando el inicio de sesión termina, el panel de candidatos dice "SSO sign-in expired: run aws sso login --profile X" (el inicio de sesión de SSO caducó: ejecuta aws sso login --profile X): ejecútalo en Terminal (los ajustes tienen Copy Command y Open in Terminal; `@doctor` ofrece el comando para copiarlo), y AllInOneIME toma el nuevo inicio de sesión por sí solo.
- **No compatible:** `mfa_serial` (un método de entrada no puede pedirte un código MFA: usa `credential_process` o SSO, o deja que tu CLI guarde las credenciales en caché), `credential_source = Ec2InstanceMetadata` o `EcsContainer` (no existen en un Mac) y web identity.
- **Límites conocidos:** de tu shell de inicio de sesión solo se toman el PATH y las variables de los archivos de AWS (`AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`), también para `credential_process` (no el resto de su entorno). AllInOneIME no renueva los tokens de `sso_session` (no usa el token de actualización de la CLI: la caché de SSO solo se lee), así que cuando caduca el token en caché, ejecuta `aws sso login` (la AWS CLI también lo renueva cada vez que la usas).
- **Settings → AI Provider** muestra cada perfil con su tipo ("dev — Role via base") y, para el elegido, cuándo caducan sus credenciales ("Role via base: credentials expire at 15:30", "SSO (signed in until 18:00)") o qué hacer. Test Connection obtiene credenciales nuevas a lo largo de toda la cadena; `@doctor` informa de lo mismo.
- Solo se ejecutan programas y se piden credenciales a AWS (`sts.<region>.amazonaws.com`, `portal.sso.<region>.amazonaws.com`) cuando una solicitud o Test Connection las necesita: nunca para listar perfiles, nunca para `@config`.

### Otros proveedores de IA: API de Claude, Gemini, servicios compatibles con OpenAI

No necesitas AWS: elige uno en "AI Provider" (proveedor de IA) en los ajustes, pega una clave de API, haz clic en "Save" (guardar) y luego en "Test Connection".

| Proveedor | Modelo predeterminado | Clave de API |
|---|---|---|
| API de Claude | `claude-haiku-5-5` (el más rápido y barato; Sonnet 5.5 y Opus 5.5 son más cuidadosos, pero más lentos y caros) | [Claude Console](https://platform.claude.com) |
| API de Gemini | `gemini-3.8-flash` | Google AI Studio |
| Compatible con OpenAI | `gpt-6-luna` de OpenAI (o `gpt-5.4-mini`); "Common Services…" (servicios comunes) incluye DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter y Ollama en este Mac: al elegir uno se rellena su URL base, y luego introduces su modelo | La clave del servicio; pon en Base URL su dirección, p. ej. `https://api.deepseek.com/v1`, o `http://localhost:11434/v1` para Ollama en este Mac |

- Las claves de API se guardan en el llavero del sistema, nunca en el archivo de configuración. Si no hay ninguna ahí, se usan `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (o `GOOGLE_API_KEY`) y `OPENAI_API_KEY` de tu shell.
- La fila de la clave de API indica si hay una clave: "✓ Saved · ends in a1b2" (guardada · termina en a1b2: sus últimos 4 caracteres, guardados con ella para no tener que leer la clave al mostrarlos) con Replace… (reemplazar) y Remove… (quitar), "✓ From $OPENAI_API_KEY" (de $OPENAI_API_KEY) si viene de tu shell, o "No API key yet" (aún no hay clave de API) con el campo para pegarla.
- "Thinking" (razonamiento) está en bajo de forma predeterminada: el método de entrada espera en cada frase, y menos razonamiento es más rápido. Elige "Not set" (sin definir) para los modelos que no lo admiten.
- Con Claude Opus 5.5 o Sonnet 5.5 elegidos, las peticiones llevan el mecanismo de respaldo ante rechazos de la API de Claude (`fallbacks: "default"`): cuando un clasificador de seguridad rechaza la petición, el servidor la reintenta con otro modelo.
- En el archivo de configuración: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), y `model`, `baseURL`, `effort` y `temperature` dentro de `anthropic`, `gemini` y `openai` (los que no se definan usan los valores predeterminados).

### Apple Intelligence en este Mac (macOS 26)

En un Mac con Apple Intelligence (chip de Apple, macOS 26 o posterior, activado en Ajustes del Sistema → Apple Intelligence y Siri), elige "Apple Intelligence (on this Mac)" en "AI Provider": sin clave, sin coste, y nada de lo que escribes sale del Mac. Usa el modelo integrado en macOS (el framework Foundation Models), con las mismas instrucciones y el mismo formato de respuesta que los demás proveedores, pero solo los ejemplos escritos en el idioma de la frase (un modelo pequeño copia con demasiada facilidad el idioma de un ejemplo).

- Es un modelo pequeño: su contexto es de unos 4K tokens (8K en macOS 27), así que un párrafo largo puede ser demasiado para él, y habla menos idiomas (inglés, chino, japonés, coreano, francés, alemán, español y algunos más; no hindi). En ambos casos lo dice. Sus resultados están por debajo de los de los modelos en la nube, y sus respuestas de `@question` sobre hechos y código a menudo son erróneas.
- Donde no se puede usar, aparece atenuado con el motivo (no compatible con este Mac, desactivado, modelo no listo), y los ajustes enlazan con Ajustes del Sistema → Apple Intelligence y Siri. Antes de macOS 26 no aparece.
- "Output tokens", la temperatura y el tiempo de espera de "Model Settings" se le aplican. En el archivo de configuración: `"provider": "apple"`.

### Ocultar información sensible (nuevo)

Settings → AI Provider → Privacy → "Hide sensitive information before sending" (ocultar información sensible antes de enviar; desactivado de forma predeterminada): antes de que una solicitud vaya a la IA, lo que encuentra en tu texto se sustituye en el Mac por marcadores como `[EMAIL_1]` (el mismo valor, el mismo marcador), y los resultados recuperan los valores reales antes de mostrarse o insertarse. El panel dice "2 items hidden from the AI" (2 elementos ocultos a la IA). Cada tipo se puede desactivar:

| Tipo | Por ejemplo | En la configuración |
| --- | --- | --- |
| Direcciones de correo electrónico | `bob@example.com` | `emails` |
| Números de teléfono | `+1 (555) 123-4567`, `138 0013 8000` | `phones` |
| Números de tarjeta de pago (comprobados con Luhn) | `4111 1111 1111 1111` | `cards` |
| Claves de API y tokens | prefijos conocidos como `sk-` o `ghp_`, cadenas aleatorias largas | `keys` |
| Direcciones IP | `203.0.113.42`, `2001:db8::1` | `ips` |
| Tus propias palabras, sin distinguir mayúsculas | un nombre en clave como `Project Atlas`, un nombre | `customWords` |

- Se aplica a `@improve`, `@translate`, `@question`, tus comandos de instrucción y plugins de instrucción, y al refinado de sus resultados (los mismos marcadores), con todos los proveedores, incluidos AllInOneIME Cloud y Apple Intelligence. Las entradas de la lista de jerga que contienen un valor que ocultar no se envían.
- Reconoce valores con formato; no puede reconocer nombres ni direcciones, así que añádelos como tus propias palabras. `@agent`, los plugins que obtienen datos de un sitio web (`@stock`) o lo abren (`@x`) y las extensiones de script envían el texto tal como se escribió. Más en Privacidad.
- En la configuración: `"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`.

Todos los ajustes se guardan en `~/.config/allinoneime/config.json`; tras un cambio, la siguiente traducción usa los nuevos ajustes, sin reiniciar. Las claves más recientes:

| Clave | Qué hace | Predeterminado |
|---|---|---|
| `inputLanguages` | Idiomas de entrada, de uno a cinco; el primero es el predeterminado: `"en"` inglés, `"zh"` chino (pinyin), `"fr"` francés, `"ko"` coreano, `"hi"` hindi, p. ej. `["en", "zh"]`, `["fr", "en", "ko"]`. El chino, el coreano y el hindi funcionan una vez instalado su paquete | `["en"]` (instalación nueva) |
| `keyboardLayouts` | La distribución de teclado con la que escribe un idioma de entrada, por su código (por ahora solo el francés): `{"fr": "com.apple.keylayout.French-PC"}` | Francés: `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | A qué idiomas traduce `@translate`, en orden: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | `@improve` también traduce (como `@translate @improve`) | `false` |
| `voiceInput` | Mantener ⌥ derecha para hablar | `true` |
| `actionKey` | Tecla de acción: `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Espacio), `"space"` (Espacio) | `"enter"` |
| `uiLanguage` | Idioma de la interfaz (ventana de ajustes, indicaciones del panel de candidatos, menú): `"zh"`, `"en"` | `null` (sigue al sistema) |
| `rewriteStyles` | Estilos de reescritura: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, p. ej. `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | Tu propio archivo de lista de jerga | `null` (es decir, `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | El icono de la barra de menús y su panel desplegable | `true` |
| `candidateLayout` | Candidatos de pinyin y de hindi: `"vertical"` (uno debajo de otro) o `"horizontal"` (uno al lado de otro; ← → eligen, ↑↓ pasan de página) | `"horizontal"` |
| `fuzzyPinyin` | Pares de pinyin difuso: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | Los comandos @ trabajan sobre el texto seleccionado en el campo (consulta Sobre el texto seleccionado) | `true` |
| `checkForUpdates` | Buscar una versión nueva una vez al día, en segundo plano; no se instala nada hasta que haces clic | `true` |
| `agent` | El agente de programación al que `@agent` pasa el texto: `claude` (Claude Code), `gemini` (Gemini CLI), `kiro` (Kiro CLI) o `custom` | `claude` |
| `agentCommand` | El comando del agente propio, con lo que escribiste añadido como último argumento, p. ej. `["muse", "--"]` | `[]` |
| `claudeInBackground` | `@agent` con Claude Code se ejecuta en segundo plano y te avisa (los demás agentes siempre se abren en Terminal) | `true` |
| `rememberQuestions` | Guardar tus últimas 5 preguntas de `@question` y sus respuestas en este Mac, mostradas bajo `@question` (consulta Preguntas recientes) | `true` |
| `questionRounds` | Rondas de una conversación de `@question` en el panel antes de que proponga continuar en otro sitio, 2–10 | `5` |
| `questionContinueIn` | Dónde puede continuar una conversación de `@question`, en orden, la primera es la predeterminada: `claudeCode` (el agente al que `@agent` pasa las tareas), `claudeWeb`, `chatgpt`, `gemini`, `copy` | el agente de `@agent` (si está instalado), Claude, ChatGPT, copiar |
| `appProfiles` | Ajustes de una app, por ID de paquete, todos opcionales: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI` (consulta Ajustes por app) | `{}` |
| `redaction` | Ocultar información sensible a la IA (consulta Privacidad): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`; cada detector (`emails`, `phones`, `cards`, `keys`, `ips`) está activado salvo que se ponga en `false` | `enabled: false` |

## Privacidad

- La escritura (inglés y pinyin) y los cálculos de `@calculate` son completamente locales. Solo cuando pulsas la tecla de acción en `@improve`, `@translate` o `@question` se envía esa frase al proveedor de IA que elegiste (tu propio Bedrock, o el servicio cuya clave añadiste). Con "Jargon" marcado y una lista de jerga definida, la lista se envía junto con ella. Refinar los resultados (una instrucción escrita tras ellos y luego ⇧⏎) vuelve a enviar la misma solicitud con los resultados mostrados y tu instrucción; una pregunta de seguimiento (⇧⏎) envía con ella la conversación hasta ese momento.
- `@config` y `@doctor <question>` envían texto a un modelo cuando pulsas ⏎: a Apple Intelligence en este Mac siempre que esté disponible (nada sale del Mac) y, si no, a tu proveedor. `@config` envía tu frase (si escribiste una clave en ella, se quita antes) con los valores actuales de los ajustes que puede cambiar: nunca una clave, ni las palabras que ocultas a la IA (solo cuántas son), y los nombres de tus perfiles de AWS solo cuando la frase trata de AWS o de Bedrock. `@doctor <question>` envía tu pregunta con los resultados de las comprobaciones, enmascarados: ninguna ruta más allá de `~`, ninguna clave, las líneas de registro como frases fijas. La ocultación de información sensible se aplica a ambos, como a cualquier solicitud. Las comprobaciones por sí solas (`@doctor` sin nada detrás) no envían nada salvo la solicitud de Test Connection, y solo cuando el proveedor tiene una clave o credenciales que probar.
- Continuar una conversación de `@question` en otro sitio (⌘1 … tras la última ronda, o ⌘⏎) la envía, con lo que escribiste, al servicio que elijas: el agente al que `@agent` pasa las tareas, en este Mac (de forma predeterminada, Claude Code, de Anthropic), claude.ai, chatgpt.com o gemini.google.com, en la dirección web o a través del portapapeles. Va tal como la viste: los valores ocultos en las solicitudes a la IA (consulta más abajo) van tal cual, ya que eres tú quien decide enviarla allí. No se envía nada a ningún sitio hasta que eliges uno; "Copy the conversation" solo la pone en el portapapeles.
- Con AllInOneIME Cloud, la frase pasa por el servidor del desarrollador hacia un proveedor de modelos (actualmente a través de OpenRouter): el servidor guarda solo recuentos, nunca el texto. Al iniciar sesión solo se guarda tu dirección de correo electrónico.
- Ocultar información sensible (Settings → AI Provider → Privacy, desactivado de forma predeterminada): antes de que salga cualquier solicitud (`@improve`, `@translate`, `@question`, tus comandos de instrucción y plugins de instrucción, con todos los proveedores, incluido AllInOneIME Cloud), las direcciones de correo, números de teléfono, números de tarjeta de pago (comprobados con Luhn), claves de API y tokens (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…` y cadenas aleatorias largas), direcciones IP y tus propias palabras (un nombre en clave, un nombre) se sustituyen en el Mac por marcadores como `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]`; el mismo valor recibe el mismo marcador. Los resultados del modelo recuperan los valores reales antes de mostrarse o insertarse, y el panel dice "2 items hidden from the AI". Un resultado cuyo marcador el modelo cambió hasta hacerlo irreconocible se muestra tal como se escribió, marcado con "⚠ placeholder changed". Las entradas de la lista de jerga que contienen un valor oculto no se envían. Cada tipo se puede desactivar. También se encuentran las formas de ancho completo (`zhang＠example.com`, `１３８…`), y un valor o una frase pueden estar partidos por un salto de línea. Reconoce valores con formato como correos, números y claves; no puede reconocer nombres ni direcciones (añádelos como tus propias palabras), ni letras parecidas de otros alfabetos. Se aplica a las solicitudes a tu servicio de IA; `@agent`, los plugins que obtienen datos de un sitio web (`@stock`) o lo abren (`@x`) y las extensiones de script envían el texto tal como se escribió. En la configuración: `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- La voz solo se graba mientras mantienes pulsada ⌥ derecha y se reconoce en el Mac; el texto reconocido solo se envía en los comandos anteriores, cuando pulsas la tecla de acción.
- El método de entrada lee el texto del portapapeles una vez, y solo cuando pulsas ⌃V o ⌘V en un comando; no se lee el contenido que los gestores de contraseñas marcan como oculto. El texto se muestra primero en el comando y, de nuevo, solo se envía cuando pulsas la tecla de acción. Las versiones recientes de macOS preguntan si AllInOneIME puede leer el portapapeles: permítelo. Para que deje de preguntártelo cada vez, configura el permiso de pegado de AllInOneIME como permitir siempre en Ajustes del Sistema → Privacidad y seguridad.
- En los campos de contraseña, macOS cambia a su propio teclado (U.S. o ABC) y vuelve al salir de ellos. Siempre que la app en la que escribes activa la entrada segura, AllInOneIME no compone texto y no puede grabar: las teclas entran tal cual. Y mientras el sistema está en entrada segura (campos de contraseña, Entrada de teclado segura de Terminal, etc.), no se envía nada a la IA.
- `@note` y `@reminder` no pasan por la IA: AllInOneIME entrega el texto solo a Notas y Recordatorios en este Mac, y también interpreta la hora del recordatorio en el Mac (que esas apps lo sincronicen con tus otros dispositivos depende de sus cuentas, como iCloud). Por eso también funcionan durante la entrada segura.
- `@reportissue` (y "Report an Issue…") no envía nada por sí mismo: abre en tu navegador la página de nueva incidencia de GitHub con el título que escribiste y las versiones, idiomas, tipo de proveedor y recuentos indicados arriba, mostrados primero en el panel de candidatos. Nada llega a GitHub a menos que hagas clic en Submit allí.
- `@open` busca solo en este Mac. Recuerda lo que abriste con él (los últimos 200), en las preferencias propias del método de entrada (no en config.json), para mostrarlos primero.
- Para "Add App…" en Settings → Apps, el método de entrada guarda los ID de paquete de las últimas 12 apps en las que escribiste, en sus propias preferencias; nada más sobre ellas.
- `@question` recuerda tus últimas 5 preguntas con sus respuestas y cuándo se hicieron, solo en este Mac, en `~/Library/Application Support/AllInOneIME/recent-questions.json` (legible solo por tu cuenta de usuario), para mostrarlas bajo `@question`; una respuesta guardada se muestra desde ahí sin conectarse. No se guarda nada durante la entrada segura, y las preguntas hechas sobre texto seleccionado no se guardan en absoluto (su respuesta trata de la selección, que acabaría en el disco). Desactivar "Remember recent questions" en Settings → General también las borra; desactivarlo con `@config` (`rememberQuestions` en la configuración) las conserva, para que se pueda deshacer con exactitud. "Clear" las borra.
- Para mostrar tus notas, el panel de la barra de menús guarda el identificador y la primera línea (hasta 80 caracteres) de las últimas 30 notas guardadas con `@note`, en las preferencias propias del método de entrada, también mientras el panel está desactivado.
- `@py` y `@js` solo se ejecutan cuando pulsas la tecla de acción, y solo con código que tú mismo escribiste o pegaste: las respuestas de la IA y la salida de otros comandos nunca se ejecutan como código. `@py` usa el `python3` de tu Mac, que puede leer y escribir archivos y conectarse a internet igual que en Terminal; `@js` se ejecuta en un proceso aparte que no puede leer archivos, acceder a la red ni ejecutar otros programas. Ninguno se ejecuta durante la entrada segura.
- Comprobación de actualizaciones: una vez al día (salvo que "Check for updates automatically" esté desactivado), AllInOneIME descarga https://allinoneime.com/update.json y su firma; la solicitud no lleva identificadores ni nada de lo que escribiste. Una actualización solo se descarga, desde la versión publicada en GitHub, cuando haces clic en Update.
- Fuentes de extensiones: git se ejecuta en tu Mac, con tu usuario, solo para las fuentes que añadiste: una consulta (fetch) al día para las que se comprueban solas (ninguna para una fijada), y cuando haces clic en Check Now, Update o Re-clone. Solo se comunica con el servidor del repositorio, autenticado con tu propia configuración de git y SSH; nada de lo que escribes va con él.
- Los registros no guardan lo que escribes. Con cualquier método de entrada de terceros, macOS advierte de que el desarrollador puede acceder a todo lo que escribas con esa fuente de entrada; es una advertencia genérica del sistema.

## Desarrollo

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

`make selftest` y `make realtest` no dependen de tus ajustes. La autoprueba usa una configuración propia (Amazon Bedrock con el perfil de AWS y la región de la tuya, todo lo demás con los valores predeterminados); la prueba en una app real pone el proveedor en Bedrock mientras se ejecuta y después vuelve a poner el tuyo. Lo que no pueden comprobar en ese momento se omite, no se da por fallido: las comprobaciones en vivo de Bedrock sin credenciales para ese perfil, y todo lo que se escribe con la entrada segura activa (la pantalla bloqueada, un campo de contraseña). La última línea cuenta las comprobaciones superadas, fallidas y omitidas; solo los fallos hacen fallar la ejecución, y una ejecución con omisiones termina en INCOMPLETE, o en SKIPPED cuando no se ejecutó nada que escriba (BLOCKED: la prueba en una app real empezó con la pantalla bloqueada), nunca en PASSED.

Estructura del código:

- `Sources/AllInOneIMECore`: cliente de Bedrock, SigV4, prompts, la máquina de estados de entrada de dos niveles (incluidos los comandos @ y el gesto de voz); sin dependencia de AppKit
- `Sources/AllInOneIMERime`: envoltorio de librime
- `Sources/AllInOneIME`: el método de entrada de InputMethodKit, el panel de candidatos, la ventana de ajustes, el reconocimiento de voz
- `Sources/AllInOneIMESettings`: el lanzador "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: "Install AllInOneIME" en la imagen de disco: instala, actualiza y desinstala

Los paquetes de idioma tienen su propia biblioteca, separada de la de los plugins: el repositorio [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), servido en https://languages.allinoneime.com/ y firmado con su propia clave. `make pack` genera el archivo; se publica ahí como recurso de release (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), y `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` escribe ahí `packs.json` y lo firma en `packs.json.sig` con la clave de los paquetes de idioma tomada del llavero (`allinoneime-languages-signing`). La app lee https://languages.allinoneime.com/packs.json, comprueba la firma y luego el tamaño y el SHA-256 del archivo. Para probar un paquete desde un servidor local: `--test-key` firma con una clave de prueba, y `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Publicar una versión (el actualizador integrado lee https://allinoneime.com/update.json, firmado con la clave propia de las publicaciones):

1. Sube el número de versión (`AppVersion.swift` y los tres Info.plist; `AppVersionTests` comprueba que coincidan) y actualiza los registros de cambios.
2. `make dmg NOTARY_PROFILE=<profile>`: `build/AllInOneIME-<version>.dmg` con su `.sha256`, y `build/AllInOneIME-<version>-update.zip` (las dos apps, tal como las lleva el instalador de la imagen de disco). Las apps y la imagen se firman con el certificado Developer ID Application del llavero, y la imagen se notariza con ese perfil de llavero de `xcrun notarytool` y se grapa (stapled).
3. Sube ambos a la versión de GitHub `v<version>` y publícala.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"` (una o dos frases cada uno): escribe `site/public/update.json` (la versión, la compilación y el macOS mínimo leídos de las apps, la dirección, el tamaño y el SHA-256 del archivo, la dirección de las notas de la versión y el resumen) y lo firma en `update.json.sig` con la clave del llavero de inicio de sesión (`allinoneime-releases-signing`; macOS puede pedir permiso de acceso). Haz commit de ambos.
5. Despliega el sitio (`cd site && npx wrangler@4 deploy`), solo cuando los archivos de la versión ya se descarguen: las apps comprueban una vez al día, y `AllInOneIME --check-update` muestra lo que ven.

La app comprueba la firma del manifiesto con la clave pública que lleva integrada antes de leerlo, nunca instala una versión que no sea más nueva, solo descarga por https desde allinoneime.com o desde los archivos de las versiones de GitHub del repositorio, e instala el archivo solo cuando su tamaño y su SHA-256 coinciden con el manifiesto, los ID de paquete, las versiones y las firmas de código de ambas apps son correctos y el nuevo método de entrada arranca. Después, el método de entrada pasa el relevo a su propio ejecutable como ayudante (`--apply-update`), que espera a que se cierre, intercambia las apps como lo hace el instalador (las antiguas se apartan y se restauran si algo falla) y registra la nueva. Para probarlo con un servidor local: `make update-test`, o `--test-key` con `Scripts/build-update-manifest.swift` y `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`.

El ID de bundle sigue siendo `com.aipinyin.inputmethod.AIPinyin`: macOS lo usa para recordar la fuente de entrada añadida y el permiso del micrófono, así que cambiarlo obligaría a añadir de nuevo el método de entrada y a conceder otra vez el permiso.

## Licencia

Copyright © 2026 MicroZ LLC. Código fuente disponible bajo la [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): úsalo, léelo, modifícalo y compártelo para cualquier fin salvo un producto de la competencia. Cada versión pasa a Apache-2.0 dos años después de su publicación. Las versiones hasta la 0.6.1 se publicaron bajo la GPL-3.0 y siguen disponibles bajo ella.

Los componentes de terceros (librime y sus plugins bajo BSD-3-Clause; los scripts Lua de rime-ice y el paquete de idioma chino bajo GPL-3.0) se enumeran en [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
