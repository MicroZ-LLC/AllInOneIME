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
> AllInOneIME todavía no está notarizado por Apple: la primera vez, permítelo en System Settings → Privacy & Security → Open Anyway (Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente). Descárgalo solo desde [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) o desde [allinoneime.com](https://allinoneime.com).

Un método de entrada para macOS con comandos de IA en cada campo de texto. Empieza una frase con `@` y pulsa ⏎ cuando termines: `@improve` pule lo que escribiste y ofrece algunas reescrituras, `@translate` lo traduce a los idiomas que elijas, `@question` hace una pregunta, `@claude` se lo pasa a Claude Code, y `@open` encuentra archivos y apps o abre una dirección web. También puedes mantener pulsada la tecla ⌥ derecha y hablar. Sin `@`, tus pulsaciones van a la app como siempre. También escribe chino (pinyin, basado en Rime y rime-ice), francés, coreano (hangul) e hindi (devanagari a partir de letras latinas), y ejecuta tus propios scripts como comandos @.

![@improve y una frase sin pulir, luego ⏎: versiones pulidas, más reescrituras](../en/improve.png)

Para más detalles (cada comando y cada ajuste, solución de problemas de instalación, privacidad), consulta la [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Creado por [Weijian Zhang](https://weijianz.com) en MicroZ LLC.

## Cómo se usa

Sin `@`, no se interpone: en inglés, las letras se escriben directamente y ⏎ es Retorno; nada se envía a internet. Una instalación nueva escribe en inglés; para escribir también en chino (pinyin), francés, coreano o hindi, añádelo en los ajustes (consulta [Entrada y traducción](#entrada-y-traducción)).

| Tecla | Qué hace |
|---|---|
| Escribir pinyin, Espacio / dígitos | En modo chino: elegir palabras, como en cualquier método de entrada pinyin |
| `@` (al principio de una frase) | Abre la lista de comandos: primero los más usados últimamente, de 5 en 5, desplazable con ↑↓, la rueda o el trackpad; o escribe letras para encontrar uno (primero los nombres que empiezan por ellas, luego los que las contienen). ⏎, Tab, Espacio o un dígito lo elige |
| ⏎ | Ejecuta el comando. Funciona aunque el pinyin aún no esté elegido: se elige primero, como con Espacio |
| Espacio, ⏎ / dígitos | Cuando aparecen los resultados: inserta el resaltado / el numerado; 0 es el original |
| ⌘C | Copia el resultado resaltado (en `@open`, la ruta); el panel de candidatos sigue abierto |
| ⌃V | En un comando (p. ej., después de `@improve `): añade el texto del portapapeles tras lo que has escrito en vez de pegarlo en la app. Varias líneas se convierten en una, hasta 2000 caracteres cada vez (`@note` conserva los saltos de línea y admite hasta 20000). Funciona en cualquier app; sin comando, la tecla va a la app como siempre |
| ⌘V | Como ⌃V, pero algunas apps gestionan ⌘V por su cuenta (terminales como Ghostty, iTerm2 y Terminal, y Notas) y pegan en la app como siempre; usa ⌃V en ellas |
| Esc, ⌫ | Vuelve a la frase para seguir editándola; basta con seguir escribiendo para continuarla |
| Pulsar Mayúsculas | Con más de un idioma de entrada: el siguiente, en su orden (inglés → chino → francés → …, y luego vuelta al primero) |
| Mantener ⌥ derecha | Habla y suelta para terminar. En el idioma en el que escribes (inglés, chino, francés, coreano o hindi). En un comando, el texto va detrás de él; si no, se inserta directamente |

## Comandos @ (beta)

| Comando | Qué hace |
|---|---|
| `@improve` | Pulir: 1–3 son tres versiones en el idioma de la propia frase, a partir de 4 los estilos de reescritura (añadidos y ordenados en los ajustes), 0 es el original. Sin traducción; con "@improve also translates" (@improve también traduce) activado, funciona como `@translate @improve` |
| `@translate` | Traduce a los idiomas que hayas añadido (ajustes → Translate, arrastra para reordenar), una línea por idioma, tres versiones si solo hay uno; se omite el idioma de la propia frase. `@translate @improve` juntos traducen y reescriben en una sola petición |
| `@question` | Hace una pregunta; la respuesta aparece en los candidatos, ⏎ o Espacio la inserta, ⌘C la copia |
| `@claude` | Pasa la tarea a Claude Code: en segundo plano de forma predeterminada, con una notificación cuando termina (haz clic en ella para abrir la sesión en Terminal y continuar), o consulta `@tasks`. Usa tu propio Claude Code (el comando `claude`) con su propio inicio de sesión y sus propios ajustes. Desactiva "@claude runs in the background" (@claude se ejecuta en segundo plano) en los ajustes para abrirlo en Terminal como antes. La primera vez que abre Terminal, macOS pregunta si AllInOneIME puede controlar Terminal: haz clic en OK |
| `@tasks` | Muestra las tareas de Claude en segundo plano (trabajando / terminada / esperándote) con sus últimas respuestas; ⏎ abre una en Terminal, ⌘C copia la respuesta |
| `@settings` | Abre la ventana de ajustes de inmediato (basta con elegirlo) |
| `@open` | Muestra los archivos, carpetas y apps que coinciden mientras escribes (Spotlight). Funcionan varias palabras clave separadas por espacios: cada una debe estar en la ruta y al menos una en el nombre (el nombre de una carpeta estándar cuenta para lo que contiene: `downloads pdf` encuentra los PDF de Downloads (Descargas)). Las apps y las carpetas estándar también se encuentran por su nombre en chino, y una interfaz en chino las muestra así. Primero aparece lo que abriste con `@open`, luego las apps y esas carpetas, y luego los archivos usados o modificados recientemente; cuando los nombres encuentran dos archivos o menos y ninguna app ni ninguna de esas carpetas, también se buscan por contenido los archivos de tu carpeta de inicio, con esas filas marcadas como "content" (contenido); cuando no hay nada más, ⏎ los muestra para que elijas en vez de abrir el primero. Con una dirección web (`github.com`, `localhost:3000`, `https://…`), la primera fila es "open in the browser" (abrir en el navegador) y no se busca en el contenido; un archivo con exactamente ese nombre (por ejemplo, `MANIFEST.in`) aparece primero. Un texto que empieza por `~/` o `/` es una ruta: Tab la completa y entra en las carpetas; ⏎ abre, ⌘C copia la ruta |
| `@note` | Guarda el texto en la app Notas, en una carpeta llamada AllInOneIME (se crea si no existe); no se inserta nada. El texto pegado conserva sus saltos de línea, hasta 20000 caracteres |
| `@reminder` | Añade un recordatorio a la app Recordatorios, en una lista llamada AllInOneIME. Escribe la hora en el texto; se interpreta en el Mac, y una fila muestra lo que se ha entendido: ⏎ o Espacio lo añade, Esc vuelve a la edición. Con hora, tiene una alarma a esa hora; solo con fecha, es para todo el día |
| `@calculate` | Calcula en este Mac; el resultado aparece en los candidatos, ⏎ o Espacio lo inserta: `@calculate 23*17` → `391`. También funciona dentro de una frase: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Ejecuta una línea de Python (el `python3` del Mac) e inserta el resultado: el valor de la última expresión del código, p. ej. `@py 2**100`, `@py import math; math.sqrt(2)`, o si no, lo que haya impreso. No se ofrece sin `python3` (las herramientas de línea de comandos de Xcode lo incluyen) |
| `@js` | Ejecuta una línea de JavaScript e inserta lo mismo: el valor de la última expresión o lo que haya impreso `console.log`, p. ej. `@js [1, 2, 3].map(x => x * 2)`. Usa JavaScriptCore, integrado en macOS, así que no hay nada que instalar; no puede leer archivos, acceder a la red ni ejecutar otros programas |
| `@imessage` | Envía un iMessage: escribe un nombre, un número de teléfono o un correo electrónico (un nombre chino también por su pinyin, completo o por las iniciales) y elige el destinatario en el panel de candidatos (primero aparecen aquellos a quienes has escrito últimamente; también funciona un número o una dirección completos), y luego escribe el mensaje (los comandos que contenga, como `@stock AAPL`, se ejecutan primero). ⏎ muestra "Send to Alex (…): message" en el panel, otro ⏎ lo envía, Esc vuelve a la edición; no se escribe nada en el campo de texto. La primera vez, macOS pregunta si AllInOneIME puede acceder a Contactos y controlar Mensajes: haz clic en OK en ambos casos |

Ejemplo: `@q` ⏎, escribe `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ guarda una nota. `@reminder call Bob tomorrow at 3pm` ⏎, comprueba la hora que ha entendido y pulsa ⏎ de nuevo para añadirlo. Una vez elegido el comando, también puedes mantener pulsada ⌥ derecha y hablar. En modo chino, `@open` y `@calculate` cambian momentáneamente a letras latinas y vuelven al chino cuando terminas.

El código de `@py` y `@js` se escribe con letras latinas, y la puntuación de ancho completo (del modo chino) se convierte en ASCII; escríbelo en una sola línea, con `;` entre las instrucciones. Se ejecuta en un proceso aparte, que se detiene a los 10 segundos o en cualquier momento con Esc; si hay un error, se muestra su primera línea, p. ej. `ZeroDivisionError: division by zero`. Una salida de varias líneas se inserta tal como se imprimió; en un terminal se inserta como una sola línea (un terminal ejecuta cada línea que recibe). Un terminal dentro de un editor (VS Code, Cursor, JetBrains) no se distingue del propio editor, así que ahí la salida de varias líneas de cualquier comando se inserta tal cual. Ambos funcionan también dentro de la frase de otro comando: `@reply the answer is @py 2**100`; pon entre comillas el código con espacios: `@question explain @py "sum(x * x for x in range(10))"`. Al revés no: el código de `@py` y `@js` siempre se ejecuta exactamente como lo escribiste, y los `@commands` que contenga no se ejecutan antes.

![Escribir @ abre la lista de comandos; @question más una pregunta, luego ⏎ para la respuesta](../en/commands.png)

![@open encuentra apps mientras escribes; si empieza por /, es una ruta: se muestra la carpeta y Tab completa](../en/open.png)

Cuando `@` no va seguido de un comando, como en `@john`, el `@` se inserta como siempre, así que mencionar a personas con @ en las apps de chat sigue funcionando. `@question`, `@improve` y `@translate` envían a tu propio Bedrock solo cuando pulsas la tecla de acción; `@open` busca solo en este Mac; `@note` y `@reminder` van solo a Notas y Recordatorios en este Mac; `@claude` usa el Claude Code instalado en tu Mac (el comando `claude`) y su propia cuenta, y te pregunta primero, como siempre, antes de modificar archivos o ejecutar comandos. Sin Claude Code instalado, `@claude` no se ofrece. `@imessage` lee solo los Contactos de este Mac (nombres, números de teléfono, correos electrónicos), nunca pasa por la IA, y es Mensajes quien envía el mensaje; sin la app Mensajes no se ofrece.

`@calculate` funciona en este Mac, sin conexión: `+ - * /` (también `× ÷`), `^` o `**` para potencias, paréntesis, porcentajes (`50%` es 0,5, `200*5%` es 10; como en una calculadora, un porcentaje que se suma o se resta se calcula sobre lo anterior: `100+10%` es 110, `100-10%` es 90), las funciones `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` es en base 10, los ángulos están en radianes, `round(x, 2)` conserva dos decimales) y las constantes `pi` (`π`) y `e`. Los dígitos y signos de ancho completo también funcionan. La aritmética es exacta en decimal, así que `0.1+0.2` da `0.3`; los resultados tienen como máximo 15 cifras significativas, y los números enteros de hasta 38 cifras se escriben completos (`2^100` → `1267650600228229401496703205376`).

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

### Plugins

Los plugins son comandos `@` listos para usar para cosas que no todo el mundo necesita, como `@stock AAPL 600519 700` para cotizaciones bursátiles. Una vez instalados, funcionan como cualquier comando; "Plugins" en los ajustes muestra qué hay instalado y adónde envía cada uno tu texto, y permite eliminarlos. Los plugins son JavaScript que se ejecuta en un proceso aparte: solo pueden acceder a los sitios web que declaran (HTTPS), y no pueden leer archivos ni ejecutar otros programas. "Browse Library…" (explorar biblioteca), en Plugins dentro de los ajustes, los instala desde la [biblioteca de plugins](https://github.com/MicroZ-LLC/AllInOneIME-plugins): muestra con qué sitios web contacta un plugin antes de instalarlo; el índice de la biblioteca está firmado y cada archivo debe coincidir con él. Una versión más reciente muestra un botón "Update" (actualizar); nada se actualiza por sí solo. Tus propios plugins van en `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): plugins locales que la biblioteca nunca sobrescribe. Los plugins de tipo "Link" no ejecutan código: ponen el texto en una dirección web y la abren en el navegador, como `@x nice weather today`, que abre el editor de publicaciones de X con el texto ya escrito; publicar en la página depende de ti. La biblioteca tiene cuatro (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` convierte divisas: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, en una línea con la fecha del tipo de cambio (tipos de ExchangeRate-API). Cómo escribir uno: [docs/plugins.md](../plugins.md).

Los comandos que obtienen algo (plugins y programas) también funcionan dentro de una frase: `@reply tell her @stock AAPL is up today`. Los interiores se ejecutan primero, su salida ocupa su lugar y el comando exterior trabaja sobre el resultado. El argumento es la palabra que sigue al comando, más los códigos en mayúsculas o los números que vienen justo después (`@stock AAPL TSLA`, `@stock 600519 700`); una palabra en minúsculas lo termina (`@stock SNDK is good to buy` consulta SNDK). Las comillas lo delimitan con exactitud: `@stock "aapl tsla"`. `@calculate` también funciona dentro de una frase; su argumento es toda la expresión que le sigue, espacios incluidos, hasta otro texto: `@reply the total is @calculate 23 * 17 dollars`. Dentro de `@claude` y de los comandos de terminal no se ejecutan: estos reciben el texto tal como está escrito (escribir `@` ahí no abre la lista de comandos).

### Tecla de acción

⏎ de forma predeterminada; cámbiala en "Action key" (tecla de acción) en los ajustes (`actionKey` en la configuración): ⏎, Tap ⌥ (pulsación breve de ⌥, de cualquier lado: pulsar y soltar enseguida; mantener ⌥ derecha sigue siendo para hablar), ⌥Espacio, o Espacio (pulsa Espacio una vez más después de elegir las palabras; dos veces en modo inglés). Sea cual sea la tecla de acción, los comandos @ también se ejecutan con ⏎. Si ⌥Espacio ya es un atajo de Alfred, Raycast o similares, estos lo reciben primero.

## Panel de la barra de menús

<img src="../en/panel-swipe.png" width="520" alt="El panel de la barra de menús: cristal esmerilado, con notas, recordatorios y tareas de Claude en tarjetas; una fila deslizada hacia la izquierda muestra su botón Remove">

Haz clic en el icono de AllInOneIME en la barra de menús (la marca de ∞ con un cursor, sin recuadro; la que tiene recuadro es la fuente de entrada) y el panel se despliega debajo; un clic en otro sitio lo cierra:

- Notes (notas): las notas guardadas con `@note`, las 5 más recientes; haz clic en una para abrirla en Notas.
- Reminders (recordatorios): los recordatorios aún no completados de la lista AllInOneIME de Recordatorios (`@reminder` los añade a esa lista), primero los que vencen antes, 8 visibles; haz clic en el círculo para marcar uno como hecho, o en el título para abrir Recordatorios.
- Claude Tasks (tareas de Claude): como `@tasks`, las tareas de Claude en segundo plano (lo que delega `@claude`), hasta 30, 5 visibles a la vez: desplázate para ver más, o busca en sus títulos y respuestas con el campo de búsqueda; con su progreso y la primera línea de la última respuesta; haz clic en una para abrirla en Terminal y continuar.

Desliza una fila (una nota, un recordatorio o una tarea) hacia la izquierda con dos dedos para mostrar su botón Remove (eliminar), o hasta el final para eliminarla de una vez; con un ratón, haz clic derecho sobre ella. Eliminar solo la quita del panel: la nota sigue en Notas, el recordatorio en Recordatorios (sin completar), la tarea en Claude Code.

La cabecera muestra los recuentos (como "2 reminders · 1 task running"; las tareas que te esperan se cuentan aparte, como "1 waiting for you") y un botón para actualizar. Nunca le quita el foco a la app en la que escribes: marcar un recordatorio o actualizar deja esa app en primer plano; solo el campo de búsqueda de las tareas de Claude, una vez que haces clic en él, toma el teclado. El icono se muestra de forma predeterminada; desactívalo en "Menu Bar Panel" en los ajustes.

Qué lee y cuándo:

- Notas: la lista es el registro propio del panel (que se conserva también mientras está cerrado), y Notas nunca se abre: solo cuando Notas ya está en ejecución, y AllInOneIME tenía permiso previo para controlarla, el panel comprueba en ella los títulos editados y las notas eliminadas.
- Recordatorios: la lista AllInOneIME se lee cuando el panel se despliega, cada 60 segundos y cuando cambian los recordatorios. El panel nunca hace que macOS pida acceso por su cuenta: si macOS aún no te lo ha pedido, muestra "Allow Access to Reminders" (permitir acceso a Recordatorios), y solo ese botón lo pide; si dijiste que no, muestra "Open System Settings" (abrir Ajustes del Sistema).
- Tareas de Claude: el panel ejecuta `claude agents` solo mientras está desplegado: una vez al desplegarse, al actualizar y cuando `@claude` delega una tarea; y cada 15 segundos mientras alguna tarea no haya terminado, y ya no cuando todas han terminado. Las últimas respuestas se leen del final de las transcripciones de Claude Code en este Mac (`~/.claude/projects`), y solo cuando una transcripción ha cambiado.
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
3. El instalador aún no está notarizado por Apple, así que macOS no puede verificar quién lo ha creado, y la primera vez dice que no puede verificar "Install AllInOneIME": haz clic en Aceptar (Cancelar en macOS 14), abre Ajustes del Sistema → Privacidad y seguridad, haz clic en Abrir igualmente cerca de la parte inferior y confirma. El instalador de cada nueva versión necesita esto una vez.

Después, AllInOneIME está activado y entre tus fuentes de entrada; cambia a él con Ctrl+Espacio (la tecla 🌐 solo cambia si "Pulsar la tecla 🌐 para" está en "Cambiar fuente de entrada" en Ajustes del Sistema → Teclado). Si el instalador te dice que lo añadas a mano, este Mac no permite que los programas lo activen, así que añádelo tú una vez: Ajustes del Sistema → Teclado → Entrada de texto → Fuentes de entrada → Editar… → + (abajo a la izquierda) → Inglés → AllInOneIME (también escribe pinyin cuando añades el chino en Input, en sus ajustes).

Si Ctrl+Espacio no te lleva a AllInOneIME, o vuelve a U.S. al cabo de un rato, ejecuta de nuevo el instalador: vuelve a añadir AllInOneIME a tus fuentes de entrada.

Para actualizar, vuelve a instalar desde la imagen de disco de la nueva versión, sin desinstalar antes; se conservan los ajustes, la lista de jerga y las palabras aprendidas. Antes de actualizar, lee el [registro de cambios](../../CHANGELOG.md): incluye los cambios de cada versión y notas para actualizar.

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
2. Crea una clave de acceso con el permiso `bedrock:InvokeModelWithResponseStream` y ponla en un perfil de `~/.aws/credentials`. Por ahora solo se admiten estas claves estáticas, no SSO ni assume-role.
3. Abre "AllInOneIME Settings": puedes encontrarlo en Spotlight o en Aplicaciones, o abrirlo desde el icono del método de entrada en la barra de menús → Settings…. Elige el perfil, la región y el modelo, y haz clic en "Test Connection" (probar conexión). "Language" (idioma), en la parte superior de la ventana de ajustes, puede ser English o Chinese; de forma predeterminada ("System") sigue al sistema (chino si el chino va antes que el inglés en los idiomas preferidos del sistema, inglés en caso contrario). La ventana de ajustes, las indicaciones del panel de candidatos y el menú de entrada siguen todos este ajuste.

<img src="../en/settings.png" width="420" alt="La ventana de ajustes">

### Otros proveedores de IA: API de Claude, Gemini, servicios compatibles con OpenAI

No necesitas AWS: elige uno en "AI Provider" (proveedor de IA) en los ajustes, pega una clave de API, haz clic en "Save" (guardar) y luego en "Test Connection".

| Proveedor | Modelo predeterminado | Clave de API |
|---|---|---|
| API de Claude | `claude-haiku-5-5` (el más rápido y barato; Sonnet 5.5 y Opus 5.5 son más cuidadosos, pero más lentos y caros) | [Claude Console](https://platform.claude.com) |
| API de Gemini | `gemini-3.8-flash` | Google AI Studio |
| Compatible con OpenAI | `gpt-6-luna` de OpenAI (o `gpt-5.4-mini`); "Common Services…" (servicios comunes) incluye DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter y Ollama en este Mac: al elegir uno se rellena su URL base, y luego introduces su modelo | La clave del servicio; pon en Base URL su dirección, p. ej. `https://api.deepseek.com/v1`, o `http://localhost:11434/v1` para Ollama en este Mac |

- Las claves de API se guardan en el llavero del sistema, nunca en el archivo de configuración. Si no hay ninguna ahí, se usan `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (o `GOOGLE_API_KEY`) y `OPENAI_API_KEY` de tu shell.
- "Thinking" (razonamiento) está en bajo de forma predeterminada: el método de entrada espera en cada frase, y menos razonamiento es más rápido. Elige "Not set" (sin definir) para los modelos que no lo admiten.
- Con Claude Opus 5.5 o Sonnet 5.5 elegidos, las peticiones llevan el mecanismo de respaldo ante rechazos de la API de Claude (`fallbacks: "default"`): cuando un clasificador de seguridad rechaza la petición, el servidor la reintenta con otro modelo.
- En el archivo de configuración: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), y `model`, `baseURL`, `effort` y `temperature` dentro de `anthropic`, `gemini` y `openai` (los que no se definan usan los valores predeterminados).

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
| `fuzzyPinyin` | Pares de pinyin difuso: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |

## Privacidad

- La escritura (inglés y pinyin) y los cálculos de `@calculate` son completamente locales. Solo cuando pulsas la tecla de acción en `@improve`, `@translate` o `@question` se envía esa frase al proveedor de IA que elegiste (tu propio Bedrock, o el servicio cuya clave añadiste). Con "Jargon" marcado y una lista de jerga definida, la lista se envía junto con ella.
- Con AllInOneIME Cloud, la frase pasa por el servidor del desarrollador hacia un proveedor de modelos (actualmente a través de OpenRouter): el servidor guarda solo recuentos, nunca el texto. Al iniciar sesión solo se guarda tu dirección de correo electrónico.
- La voz solo se graba mientras mantienes pulsada ⌥ derecha y se reconoce en el Mac; el texto reconocido solo se envía en los comandos anteriores, cuando pulsas la tecla de acción.
- El método de entrada lee el texto del portapapeles una vez, y solo cuando pulsas ⌃V o ⌘V en un comando; no se lee el contenido que los gestores de contraseñas marcan como oculto. El texto se muestra primero en el comando y, de nuevo, solo se envía cuando pulsas la tecla de acción. Las versiones recientes de macOS preguntan si AllInOneIME puede leer el portapapeles: permítelo. Para que deje de preguntártelo cada vez, configura el permiso de pegado de AllInOneIME como permitir siempre en Ajustes del Sistema → Privacidad y seguridad.
- En los campos de contraseña, macOS cambia a su propio teclado (U.S. o ABC) y vuelve al salir de ellos. Siempre que la app en la que escribes activa la entrada segura, AllInOneIME no compone texto y no puede grabar: las teclas entran tal cual. Y mientras el sistema está en entrada segura (campos de contraseña, Entrada de teclado segura de Terminal, etc.), no se envía nada a la IA.
- `@note` y `@reminder` no pasan por la IA: AllInOneIME entrega el texto solo a Notas y Recordatorios en este Mac, y también interpreta la hora del recordatorio en el Mac (que esas apps lo sincronicen con tus otros dispositivos depende de sus cuentas, como iCloud). Por eso también funcionan durante la entrada segura.
- `@open` busca solo en este Mac. Recuerda lo que abriste con él (los últimos 200), en las preferencias propias del método de entrada (no en config.json), para mostrarlos primero.
- Para mostrar tus notas, el panel de la barra de menús guarda el identificador y la primera línea (hasta 80 caracteres) de las últimas 30 notas guardadas con `@note`, en las preferencias propias del método de entrada, también mientras el panel está desactivado.
- `@py` y `@js` solo se ejecutan cuando pulsas la tecla de acción, y solo con código que tú mismo escribiste o pegaste: las respuestas de la IA y la salida de otros comandos nunca se ejecutan como código. `@py` usa el `python3` de tu Mac, que puede leer y escribir archivos y conectarse a internet igual que en Terminal; `@js` se ejecuta en un proceso aparte que no puede leer archivos, acceder a la red ni ejecutar otros programas. Ninguno se ejecuta durante la entrada segura.
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
make dmg          # the release installer, build/AllInOneIME-<version>.dmg (universal; signed if there's a Developer ID certificate, optionally notarized)
```

Estructura del código:

- `Sources/AllInOneIMECore`: cliente de Bedrock, SigV4, prompts, la máquina de estados de entrada de dos niveles (incluidos los comandos @ y el gesto de voz); sin dependencia de AppKit
- `Sources/AllInOneIMERime`: envoltorio de librime
- `Sources/AllInOneIME`: el método de entrada de InputMethodKit, el panel de candidatos, la ventana de ajustes, el reconocimiento de voz
- `Sources/AllInOneIMESettings`: el lanzador "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: "Install AllInOneIME" en la imagen de disco: instala, actualiza y desinstala

Los paquetes de idioma tienen su propia biblioteca, separada de la de los plugins: el repositorio [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), servido en https://languages.allinoneime.com/ y firmado con su propia clave. `make pack` genera el archivo; se publica ahí como recurso de release (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), y `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` escribe ahí `packs.json` y lo firma en `packs.json.sig` con la clave de los paquetes de idioma tomada del llavero (`allinoneime-languages-signing`). La app lee https://languages.allinoneime.com/packs.json, comprueba la firma y luego el tamaño y el SHA-256 del archivo. Para probar un paquete desde un servidor local: `--test-key` firma con una clave de prueba, y `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

El ID de bundle sigue siendo `com.aipinyin.inputmethod.AIPinyin`: macOS lo usa para recordar la fuente de entrada añadida y el permiso del micrófono, así que cambiarlo obligaría a añadir de nuevo el método de entrada y a conceder otra vez el permiso.

## Licencia

Copyright © 2026 MicroZ LLC. Código fuente disponible bajo la [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): úsalo, léelo, modifícalo y compártelo para cualquier fin salvo un producto de la competencia. Cada versión pasa a Apache-2.0 dos años después de su publicación. Las versiones hasta la 0.6.1 se publicaron bajo la GPL-3.0 y siguen disponibles bajo ella.

Los componentes de terceros (librime y sus plugins bajo BSD-3-Clause; los scripts Lua de rime-ice y el paquete de idioma chino bajo GPL-3.0) se enumeran en [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
