<div align="center">

[English](../../README.md) · [简体中文](../../README.zh-CN.md) · [繁體中文](README_zh-TW.md) · [日本語](README_ja.md) · [한국어](README_ko.md) · [Français](README_fr.md) · [Deutsch](README_de.md) · [Español](README_es.md) · **Português (Brasil)** · [Italiano](README_it.md) · [Русский](README_ru.md) · [Tiếng Việt](README_vi.md) · [ไทย](README_th.md) · [Bahasa Indonesia](README_id.md) · [हिन्दी](README_hi.md) · [العربية](README_ar.md) · [Türkçe](README_tr.md)

<br>

<img src="../../Resources/AppIcon.png" width="112" alt="Ícone do AllInOneIME">

# AllInOneIME

### Comandos de IA em qualquer campo de texto do seu Mac.

Digite `@improve`, `@translate` ou `@question` em qualquer app, pressione ⏎ e escolha o resultado.<br>
Nada de copiar para uma janela de chat, nada de trocar de app. Seu próprio provedor de IA, suas próprias chaves.

[![Versão](https://img.shields.io/github/v/release/MicroZ-LLC/AllInOneIME?label=release&color=3b82f6)](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#instalação)
[![Apple silicon e Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555)](#instalação)
[![Licença: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-f59e0b)](../../LICENSE)
[![Downloads](https://img.shields.io/github/downloads/MicroZ-LLC/AllInOneIME/total?color=22c55e)](https://github.com/MicroZ-LLC/AllInOneIME/releases)

**[Baixar](https://allinoneime.com/download)** · **[Site](https://allinoneime.com)** · **[Documentação](https://github.com/MicroZ-LLC/AllInOneIME/wiki)** · **[Extensões](../extensions.md)**

[Como usar](#como-usar) · [Comandos](#comandos--beta) · [Seus próprios comandos](#seus-próprios-comandos) · [Idiomas](#entrada-e-tradução) · [Voz](#entrada-por-voz) · [Instalação](#instalação) · [Privacidade](#privacidade)

<br>

<img src="../en/demo.png" width="820" alt="@translate e uma frase, depois ⏎: uma linha em espanhol, francês e alemão">

</div>

*Esta é uma tradução do README em inglês; onde os dois divergirem, vale o inglês.*

> [!NOTE]
> O AllInOneIME ainda não é notarizado pela Apple: na primeira vez, permita-o em "System Settings → Privacy & Security → Open Anyway" (Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim). Baixe-o apenas do [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) ou de [allinoneime.com](https://allinoneime.com).

Um método de entrada para macOS com comandos de IA em qualquer campo de texto. Comece uma frase com `@` e pressione ⏎ ao terminar: `@improve` refina o que você escreveu e oferece algumas reescritas, `@translate` traduz para os idiomas que você escolher, `@question` faz uma pergunta, `@claude` passa a tarefa para o Claude Code e `@open` encontra arquivos e apps ou abre um endereço web. Você também pode manter pressionada a tecla ⌥ direita e falar. Sem `@`, suas teclas vão para o app normalmente. Ele também digita chinês (pinyin, baseado em Rime e rime-ice), francês, coreano (Hangul) e híndi (devanágari a partir de letras latinas), e executa seus próprios scripts como comandos @.

![@improve e uma frase mal escrita, depois ⏎: versões refinadas, além de reescritas](../en/improve.png)

Para mais detalhes (todos os comandos e ajustes, solução de problemas de instalação, privacidade), veja a [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Feito por [Weijian Zhang](https://weijianz.com) na MicroZ LLC.

## Como usar

Sem `@`, ele não atrapalha: em inglês, as letras são digitadas diretamente e ⏎ é Return; nada vai para a internet. Uma instalação nova escreve em inglês; para digitar também chinês (pinyin), francês, coreano ou híndi, adicione o idioma nos ajustes (veja [Entrada e tradução](#entrada-e-tradução)).

| Tecla | O que faz |
|---|---|
| Digitar pinyin, Espaço / dígitos | No modo chinês: escolher palavras, como em qualquer método de entrada pinyin |
| `@` (no início de uma frase) | Abre a lista de comandos: os mais usados recentemente primeiro, 5 por vez, rolando com ↑↓, a roda do mouse ou o trackpad; ou digite letras para encontrar um (primeiro os nomes que começam com elas, depois os que as contêm). ⏎, Tab, Espaço ou um dígito escolhe |
| ⏎ | Executa o comando. Funciona mesmo que o pinyin ainda não tenha sido escolhido: ele é escolhido primeiro, como com Espaço |
| Espaço, ⏎ / dígitos | Quando os resultados aparecem: insere o destacado / o de número correspondente; 0 é o original |
| ⌘C | Copia o resultado destacado (no `@open`, o caminho); o painel de candidatos continua aberto |
| ⌃V | Em um comando (por exemplo, depois de `@improve `): acrescenta o texto da área de transferência depois do que você digitou, em vez de colá-lo no app. Várias linhas viram uma, até 2000 caracteres por vez (`@note` mantém as quebras de linha e aceita até 20000). Funciona em qualquer app; sem um comando, a tecla vai para o app normalmente |
| ⌘V | Como ⌃V, mas alguns apps tratam ⌘V por conta própria (terminais como Ghostty, iTerm2 e Terminal, e o Notes) e colam no app normalmente; use ⌃V neles |
| Esc, ⌫ | Volta para a frase para continuar editando; basta continuar digitando |
| Toque em Shift | Com mais de um idioma de entrada: o próximo, na ordem deles (inglês → chinês → francês → …, e depois de volta ao primeiro) |
| Manter a ⌥ direita pressionada | Fale e solte para parar. No idioma em que você está digitando (inglês, chinês, francês, coreano ou híndi). Em um comando, o texto vai depois dele; caso contrário, é inserido diretamente |

## Comandos @ (beta)

| Comando | O que faz |
|---|---|
| `@improve` | Refinar: 1–3 são três versões no próprio idioma da frase, de 4 em diante vêm os estilos de reescrita (adicionados e ordenados nos ajustes), 0 é o original. Sem tradução; com "@improve also translates" (o @improve também traduz) ativado, funciona como `@translate @improve` |
| `@translate` | Traduz para os idiomas que você adicionou (ajustes → "Translate", arraste para reordenar), uma linha para cada um, três versões se houver só um; o próprio idioma da frase é pulado. `@translate @improve` juntos traduzem e reescrevem em uma única solicitação |
| `@question` | Faz uma pergunta; a resposta aparece nos candidatos, ⏎ ou Espaço a insere, ⌘C a copia |
| `@claude` | Passa a tarefa para o Claude Code: em segundo plano por padrão, com uma notificação quando terminar (clique nela para abrir a sessão no Terminal e continuar), ou veja `@tasks`. Usa o seu próprio Claude Code (o comando `claude`), com o login e os ajustes dele. Desative "@claude runs in the background" (o @claude roda em segundo plano) nos ajustes para abri-lo no Terminal como antes. Na primeira vez que ele abre o Terminal, o macOS pergunta se o AllInOneIME pode controlar o Terminal: clique em OK |
| `@tasks` | Lista as tarefas do Claude em segundo plano (trabalhando / concluída / aguardando você) com as últimas respostas; ⏎ abre uma no Terminal, ⌘C copia a resposta |
| `@settings` | Abre a janela de ajustes na hora (basta escolhê-lo) |
| `@open` | Lista arquivos, pastas e apps correspondentes enquanto você digita (Spotlight). Funcionam várias palavras-chave, separadas por espaços: cada uma precisa estar no caminho, e pelo menos uma no nome (o nome de uma pasta padrão vale para o que está dentro dela: `downloads pdf` encontra os PDFs em Downloads). Apps e pastas padrão também são encontrados pelos nomes em chinês, e uma interface em chinês os mostra assim. O que você abriu com `@open` vem primeiro, depois apps e essas pastas, depois arquivos usados ou alterados recentemente; quando os nomes encontram dois arquivos ou menos e nenhum app ou pasta desses, os arquivos da sua pasta pessoal também são pesquisados pelo conteúdo, com essas linhas marcadas como "content"; quando não há mais nada, ⏎ os lista para você escolher em vez de abrir o primeiro. Com um endereço web (`github.com`, `localhost:3000`, `https://…`), a primeira linha é "open in the browser" (abrir no navegador) e o conteúdo dos arquivos não é pesquisado; um arquivo com exatamente esse nome (digamos, `MANIFEST.in`) vem primeiro. Texto que começa com `~/` ou `/` é um caminho: Tab o completa e entra nas pastas; ⏎ abre, ⌘C copia o caminho |
| `@note` | Salva o texto no app Notes (Notas), em uma pasta chamada AllInOneIME (criada se não existir); nada é inserido. Texto colado mantém as quebras de linha, até 20000 caracteres |
| `@reminder` | Adiciona um lembrete ao app Reminders (Lembretes), em uma lista chamada AllInOneIME. Escreva a hora no texto; ela é interpretada no próprio Mac, e uma linha mostra o que foi entendido: ⏎ ou Espaço adiciona, Esc volta para editar. Com uma hora, o lembrete tem um alarme nesse momento; só com uma data, é de dia inteiro |
| `@calculate` | Calcula neste Mac; o resultado aparece nos candidatos, ⏎ ou Espaço o insere: `@calculate 23*17` → `391`. Também funciona dentro de uma frase: `@reply the total is @calculate 23*17 dollars` |
| `@py` | Executa uma linha de Python (o `python3` do Mac) e insere o resultado: o valor da última expressão do código, por exemplo `@py 2**100`, `@py import math; math.sqrt(2)`, ou então o que ele imprimiu. Não é oferecido sem `python3` (as ferramentas de linha de comando do Xcode o incluem) |
| `@js` | Executa uma linha de JavaScript e insere o mesmo: o valor da última expressão ou o que `console.log` imprimiu, por exemplo `@js [1, 2, 3].map(x => x * 2)`. Usa o JavaScriptCore embutido no macOS, então não há nada para instalar; ele não pode ler arquivos, acessar a rede nem executar outros programas |
| `@imessage` | Envia um iMessage: digite um nome, um número de telefone ou um e-mail (um nome chinês também pelo pinyin, completo ou só as iniciais) e escolha o destinatário no painel de candidatos (as pessoas com quem você conversou recentemente vêm primeiro; um número ou endereço completo também funciona), depois escreva a mensagem (comandos dentro dela, como `@stock AAPL`, são executados primeiro). ⏎ mostra "Send to Alex (…): message" no painel, ⏎ de novo a envia, Esc volta para a edição; nada é digitado no campo de texto. Na primeira vez, o macOS pergunta se o AllInOneIME pode acessar o Contacts (Contatos) e controlar o Messages (Mensagens): clique em OK nos dois |

Exemplo: `@q` ⏎, digite `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ salva uma nota. `@reminder call Bob tomorrow at 3pm` ⏎, confira a hora que ele entendeu e pressione ⏎ de novo para adicionar. Depois de escolher o comando, você também pode manter a ⌥ direita pressionada e falar. No modo chinês, `@open` e `@calculate` passam para letras inglesas no momento e voltam ao chinês quando você termina.

O código de `@py` e `@js` é digitado em letras inglesas, e a pontuação de largura total (do modo chinês) vira ASCII; escreva-o em uma linha, com `;` entre as instruções. Ele roda em um processo separado, interrompido após 10 segundos ou com Esc a qualquer momento; em caso de erro, a primeira linha do erro é mostrada, por exemplo `ZeroDivisionError: division by zero`. Uma saída com várias linhas é inserida como foi impressa; em um terminal, entra como uma linha só (um terminal executa cada linha que recebe). Um terminal dentro de um editor (VS Code, Cursor, JetBrains) não pode ser distinguido do próprio editor, então ali a saída com várias linhas de qualquer comando entra como está. Os dois também funcionam dentro da frase de outro comando: `@reply the answer is @py 2**100`; coloque código com espaços entre aspas: `@question explain @py "sum(x * x for x in range(10))"`. O contrário não vale: o código de `@py` e `@js` sempre roda exatamente como você o digitou, e `@commands` dentro dele não são executados antes.

![Digitar @ abre a lista de comandos; @question mais uma pergunta, depois ⏎ para a resposta](../en/commands.png)

![@open encontra apps enquanto você digita; começando com /, é um caminho: a pasta é listada, Tab completa](../en/open.png)

Quando `@` não é seguido de um comando, como em `@john`, o `@` é inserido normalmente, então mencionar pessoas com @ em apps de chat continua funcionando. `@question`, `@improve` e `@translate` enviam para o seu próprio Bedrock somente quando você pressiona a tecla de ação; `@open` pesquisa apenas neste Mac; `@note` e `@reminder` vão apenas para o Notes e o Reminders deste Mac; `@claude` usa o Claude Code instalado no seu Mac (o comando `claude`) e a conta dele, e pergunta antes, como de costume, de alterar arquivos ou executar comandos. Sem o Claude Code instalado, `@claude` não é oferecido. `@imessage` lê o Contacts apenas neste Mac (nomes, números de telefone, e-mails), nunca passa pela IA, e é o Messages que envia a mensagem; sem o app Messages, ele não é oferecido.

`@calculate` funciona neste Mac, offline: `+ - * /` (também `× ÷`), `^` ou `**` para potências, parênteses, porcentagem (`50%` é 0.5, `200*5%` é 10; como em uma calculadora, uma porcentagem somada ou subtraída é calculada sobre o que vem antes: `100+10%` é 110, `100-10%` é 90), as funções `sqrt abs round floor ceil ln log exp sin cos tan min max pow` (`log` é na base 10, os ângulos são em radianos, `round(x, 2)` mantém duas casas decimais) e as constantes `pi` (`π`) e `e`. Dígitos e sinais de largura total também funcionam. A aritmética é exata em decimal, então `0.1+0.2` dá `0.3`; os resultados têm no máximo 15 dígitos significativos, e números inteiros de até 38 dígitos são escritos por extenso (`2^100` → `1267650600228229401496703205376`).

### Notas e lembretes

`@note` cria uma nota nova; a primeira linha é o título. Depois de copiar algum texto, ⌃V depois de `@note ` (ou ⌘V, fora de terminais) o salva com as quebras de linha, mostradas como ↵ no comando. Se você sair do campo de texto (clicar em outro lugar, trocar de app) ou pressionar ⇧⏎ (inserir como digitado) antes que uma nota com quebras de linha seja salva, ela não é digitada no app (em um terminal, cada linha seria executada como um comando): em vez disso, vai para a área de transferência ("The note wasn't saved; its text is on the clipboard"). Uma nota de uma só linha é inserida como foi digitada.

`@reminder` entende horários como `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (o dia 1º), `end of the year` (e também horários em chinês). O dia e a hora podem estar separados (`tomorrow call Bob at 5`); as semanas começam na segunda-feira. Uma hora sem am ou pm (`at 5`) é a próxima, nunca entre meia-noite e 6 da manhã; uma hora que já passou hoje fica para amanhã, mas uma parte do dia ainda em andamento (`this afternoon`, `tonight`) é hoje, o dia inteiro; uma data que já passou neste ano fica para o ano que vem. Um lembrete escrito para se repetir (`standup every Monday at 9`) é adicionado uma vez, para a próxima ocorrência: as palavras ficam no título e a linha diz "once only" (só uma vez). A linha de confirmação mostra a hora entendida, por exemplo "tomorrow 3:00 PM" (seguindo o ajuste de 12/24 horas do Mac); se estiver errada, Esc volta para o texto. Sem hora nem data no texto, o lembrete não tem nenhuma ("no date").

`@stock` e similares dentro desses dois não são executados: o texto é salvo como foi escrito (digitar `@` ali não abre a lista de comandos). Na primeira vez, o macOS pergunta se o AllInOneIME pode controlar o Notes (`@note`) ou acessar o Reminders (`@reminder`): permita. Se não permitiu, autorize o AllInOneIME em "System Settings → Privacy & Security → Automation" (Ajustes do Sistema → Privacidade e Segurança → Automação) (Notes) ou → "Reminders". Quando um salvamento falha (por falta de permissão, por exemplo), o aviso diz o motivo e o texto volta para o comando, para você corrigir e enviar de novo; quando é preciso corrigir algo antes (uma permissão, uma conta), ele também é colocado na área de transferência (ir para o System Settings tira o foco do campo de texto). Se você já foi para outro campo de texto ou está digitando outra coisa, ele vai para a área de transferência ("Not saved; the text is on the clipboard.").

### Seus próprios comandos

Nos ajustes, em "Custom @ Commands" (comandos @ personalizados), clique em "Add Command…" (adicionar comando): dê um nome e escolha o que ele faz (uma instrução para a IA, um programa, um programa no Terminal ou uma página web), ou comece a partir de um exemplo. Seus comandos vêm depois dos embutidos; os nomes usam apenas letras inglesas e não podem ser o de um comando embutido; eles funcionam a partir da próxima frase. Eles ficam em `customCommands` no arquivo de configuração (`~/.config/allinoneime/config.json`), que você também pode editar:

```json
"customCommands": [
  { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"], "summary": "Run Python" },
  { "name": "bc", "type": "run", "argv": ["bc", "-l"], "stdin": "{input}\n" },
  { "name": "sh", "type": "terminal", "argv": ["zsh", "-c", "{input}"] },
  { "name": "reply", "type": "prompt", "prompt": "Write a short, polite reply to the user's message." },
  { "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }
]
```

| `type` | O que faz |
|---|---|
| `prompt` | Vai para a IA com `prompt` como instrução; a resposta aparece nos candidatos, para inserir ou copiar (⌘C) |
| `run` | Executa `argv` em segundo plano; o que ele imprime aparece nos candidatos (várias linhas são inseridas como foram impressas; em um terminal, como uma linha só). Em caso de erro, a última linha dele é mostrada |
| `terminal` | Executa `argv` em uma nova janela do Terminal; nada é inserido |
| `link` | Coloca o texto no endereço web `url` e o abre no navegador padrão; nada é inserido |

- `{input}` vira o que você escreveu depois do comando, e sempre fica dentro do único argumento em que está: nenhum shell é envolvido. Para usar um shell, diga isso explicitamente, como o `sh` acima (`zsh -c`).
- `stdin`: o que vai para a entrada padrão do programa, também com `{input}` substituído.
- O `url` de um `link` precisa ser `https://`, com `{input}` uma vez, depois do `?` ou do `#`; o texto é codificado (um espaço vira `%20`, uma quebra de linha `%0A`), com no máximo 4000 caracteres.
- `run` e `terminal` digitam letras inglesas por padrão (como `@open`; no modo chinês, o chinês volta depois), e a pontuação de largura total vira ASCII. Defina `"ascii": false` para manter o texto como digitado.
- Os programas rodam na sua pasta pessoal com o PATH do seu shell de login (assim, o que foi instalado com Homebrew, pyenv e nvm é encontrado). `run` interrompe um programa após 10 segundos (`timeoutSeconds`) ou quando ele imprime demais; Esc o interrompe a qualquer momento.
- `summary` é a descrição na lista de comandos (opcional).
- Quando o programa em `argv` não é encontrado (digamos, sem `python3`), o comando não é oferecido e `@python …` é inserido como texto; depois que o programa é instalado, o comando aparece no próximo campo de texto.

`run` e `terminal` executam código no seu Mac: adicione apenas comandos que você escreveu e em que confia. Eles também só rodam quando você pressiona a tecla de ação, e nunca durante a entrada segura.

### Extensões de script

Adicione seus próprios comandos @ como programas: um script em qualquer linguagem (bash, Python, Node, Swift, …) com algumas linhas de metadados nos comentários. Coloque-o em `~/.config/allinoneime/extensions`, ou em uma pasta que você adicionar em "Settings → Custom Commands → Script Extensions". Os Raycast Script Commands funcionam como estão, e as pastas que já os contêm são encontradas com o Spotlight.

```bash
#!/bin/bash
# @allinoneime.schemaVersion 1
# @allinoneime.title Flights
# @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
# @allinoneime.argument2 {"type": "text", "placeholder": "to city"}

echo "Flights from $1 to $2"
```

`flights.sh` é `@flights`. Escreva os argumentos depois dele, separados por vírgulas: `@flights beijing, new york` o executa com `beijing` e `new york` como `$1` e `$2` (vírgulas a mais ficam no último); se um argumento obrigatório ficar vazio, ele diz o que falta em vez de executar. O que ele imprime é usado conforme o seu `output`:

| `output` | O que acontece |
|---|---|
| `insert` (padrão) | Tudo, e cada linha, para inserir |
| `show` | Mostrado no painel à medida que é impresso (progresso); nada é inserido. Saia do campo e ele continua em segundo plano (até quatro de uma vez) |
| `list` | Uma lista no formato JSON do Script Filter do Alfred, executada de novo enquanto você digita; escolher uma linha insere, abre (um endereço web, arquivo ou pasta; nunca algo que seria executado), copia ou executa uma segunda etapa |
| `silent` | A última linha dele perto do cursor; nada é inserido |

Um comando também pode não receber entrada (`input none`: ⏎ no nome dele o executa), rodar em segundo plano (`background`) e avisar você quando terminar (enquanto isso, o painel da barra de menus o lista), mostrar um `status` ao lado do nome na lista de comandos, ou pedir confirmação antes (`confirm`). Ele roda na própria pasta com o PATH do seu shell de login e as variáveis `ALLINONEIME_*`: o idioma da interface e o de entrada, o app em que você está digitando, o texto. Um **bundle** é uma pasta com um `extension.json` que lista os seus comandos: eles compartilham código e preferências, que os ajustes mostram (as senhas vão para o keychain do sistema). Os ajustes listam cada comando com um interruptor, e os scripts deixados de fora com o motivo.

Os modos do Raycast correspondem assim: `fullOutput` → `show`, `compact` e `silent` → `silent`, `inline` com `refreshTime` → um status. O protocolo completo está em [docs/extensions.md](../extensions.md); [Examples/extensions](../../Examples/extensions) tem um de cada tipo. Extensões executam código no seu Mac: use apenas as que são de confiança. Elas só rodam quando você as executa (um status ou uma lista enquanto você digita), nunca durante a entrada segura, e param quando o método de entrada é encerrado.

### Plugins

Plugins são comandos `@` prontos para coisas de que nem todo mundo precisa, como `@stock AAPL 600519 700` para cotações de ações. Uma vez instalados, funcionam como qualquer comando; "Plugins" nos ajustes mostra o que está instalado e para onde cada um envia o seu texto, e permite removê-los. Plugins são JavaScript executado em um processo separado: só podem acessar os sites que declaram (HTTPS), e não podem ler arquivos nem executar outros programas. "Browse Library…" (explorar biblioteca), em "Plugins" nos ajustes, os instala a partir da [biblioteca de plugins](https://github.com/MicroZ-LLC/AllInOneIME-plugins): ela mostra quais sites um plugin contata antes de instalá-lo; o índice da biblioteca é assinado e todo arquivo precisa corresponder a ele. Uma versão mais nova mostra um botão "Update" (atualizar); nada se atualiza sozinho. Seus próprios plugins ficam em `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): são plugins locais, nunca sobrescritos pela biblioteca. Plugins de "link" não executam código: colocam o texto em um endereço web e o abrem no navegador, como `@x nice weather today`, que abre o editor de posts do X com o texto preenchido; publicar fica por sua conta, na página. A biblioteca tem quatro (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` converte moedas: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, uma linha com a data da cotação (cotações da ExchangeRate-API). Para escrever um plugin: [docs/plugins.md](../plugins.md).

Comandos que buscam algo (plugins e programas) também funcionam dentro de uma frase: `@reply tell her @stock AAPL is up today`. Os internos rodam primeiro, a saída deles toma o seu lugar, e o comando externo trabalha sobre o resultado. O argumento é a palavra depois do comando, mais os códigos em maiúsculas ou números logo em seguida (`@stock AAPL TSLA`, `@stock 600519 700`); uma palavra em minúsculas o encerra (`@stock SNDK is good to buy` consulta SNDK). Aspas o delimitam exatamente: `@stock "aapl tsla"`. `@calculate` também funciona dentro de uma frase; o argumento dele é a expressão inteira que vem depois, incluindo espaços, até o próximo texto: `@reply the total is @calculate 23 * 17 dollars`. Dentro de `@claude` e de comandos de terminal eles não são executados: esses recebem o texto como foi escrito (digitar `@` ali não abre a lista de comandos).

### Tecla de ação

⏎ por padrão; altere em "Action key" (tecla de ação) nos ajustes (`actionKey` na configuração): ⏎, "Tap ⌥" (tocar em ⌥, de qualquer lado: pressione e solte logo; manter a ⌥ direita pressionada continua sendo para falar), ⌥Space ou Space (pressione Espaço mais uma vez depois que as palavras forem escolhidas; duas vezes no modo inglês). Seja qual for a tecla de ação, os comandos @ também rodam com ⏎. Se ⌥Space já for um atalho do Alfred, do Raycast ou similares, eles o recebem primeiro.

## Painel da barra de menus

<img src="../en/panel-swipe.png" width="520" alt="O painel da barra de menus: vidro fosco, com notas, lembretes e tarefas do Claude em cartões; uma linha deslizada para a esquerda mostra o botão Remove">

Clique no ícone do AllInOneIME na barra de menus (a marca de ∞ com cursor, sem moldura; a que tem moldura é a fonte de entrada) e o painel se abre logo abaixo dele; um clique em outro lugar o fecha:

- "Notes" (notas): as notas salvas com `@note`, as 5 mais recentes; clique em uma para abri-la no Notes.
- "Reminders" (lembretes): os lembretes ainda não concluídos na lista AllInOneIME do Reminders (`@reminder` adiciona a essa lista), os de vencimento mais próximo primeiro, 8 visíveis; clique no círculo para marcar um como concluído, ou no título para abrir o Reminders.
- "Claude Tasks" (tarefas do Claude): como em `@tasks`, as tarefas do Claude em segundo plano (o que o `@claude` delega), até 30, 5 visíveis por vez: role para ver mais, ou pesquise nos títulos e nas respostas pelo campo de busca; com o andamento e a primeira linha da última resposta; clique em uma para abri-la no Terminal e continuar.

Deslize uma linha (uma nota, um lembrete ou uma tarefa) para a esquerda com dois dedos para mostrar o botão "Remove" (remover), ou até o fim para removê-la de uma vez; com um mouse, clique nela com o botão direito. Remover só a tira do painel: a nota continua no Notes, o lembrete no Reminders (não concluído), a tarefa no Claude Code.

O cabeçalho mostra as contagens (como "2 reminders · 1 task running"; tarefas aguardando você são contadas à parte, como "1 waiting for you") e um botão de atualizar. Ele nunca tira o foco do app em que você está digitando: marcar um lembrete como concluído ou atualizar deixa esse app na frente; só o campo de busca das tarefas do Claude, depois de clicado, recebe o teclado. O ícone aparece por padrão; desative-o em "Menu Bar Panel" nos ajustes.

O que ele lê, e quando:

- Notas: a lista é o registro próprio do painel (mantido também enquanto ele está fechado), e o Notes nunca é aberto: só quando o Notes já está em execução, e o AllInOneIME já recebeu permissão para controlá-lo antes, o painel o consulta em busca de títulos editados e notas apagadas.
- Lembretes: a lista AllInOneIME é lida quando o painel se abre, a cada 60 segundos e quando os lembretes mudam. O painel nunca faz o macOS pedir acesso por conta própria: se o macOS ainda não perguntou a você, ele mostra "Allow Access to Reminders", e só esse botão faz a pergunta; se você disse não, ele mostra "Open System Settings".
- Tarefas do Claude: o painel executa `claude agents` só enquanto está aberto: uma vez quando se abre, ao clicar em atualizar e quando `@claude` delega uma tarefa; e a cada 15 segundos enquanto alguma tarefa não terminou, não mais depois que todas terminam. As últimas respostas são lidas do final das transcrições do Claude Code neste Mac (`~/.claude/projects`), e só quando uma transcrição mudou.
- Enquanto ele está fechado, nada disso roda; ele só mantém um registro das notas que `@note` salva.

## Entrada e tradução

Nos ajustes:

- **Input languages** (idiomas de entrada): de um a cinco entre inglês, chinês (pinyin), francês, coreano e híndi, adicionados com + (sempre visível; fica cinza quando há cinco). Uma instalação nova começa só com inglês. Campos de texto novos começam no primeiro; toque em Shift para ir ao próximo, na ordem deles; com um só, Shift não alterna.
  - O **francês** digita com seu próprio layout de teclado: AZERTY, a menos que você escolha outro no cartão dele. As teclas mortas dele (^, ¨, `, ´, ~) também compõem a partir desse layout.
  - O **coreano** digita Hangul no layout de 2 conjuntos (Dubeolsik), montando cada sílaba enquanto você digita (g k s → 한); Shift dá ㄲ ㄸ ㅃ ㅆ ㅉ e ㅒ ㅖ.
  - **Híndi**: digite as palavras como soam, em letras latinas, e obtenha devanágari (namaste → नमस्ते). Palavras comuns são grafadas como o híndi as escreve; nos outros casos, Espaço insere a primeira grafia, um dígito outra, ⏎ as letras como digitadas, e "." o danda (।).
  - O nome de um comando, o texto do `@open` e o código (`@py`, `@js`) são digitados em letras latinas, qualquer que seja o idioma; ele volta depois do comando.
  - `@improve` mantém uma frase em coreano, híndi ou francês no próprio idioma, e `@translate` a traduz para os seus idiomas (o francês é distinguido do inglês quando é um dos seus idiomas de entrada).
- **Language packs** (pacotes de idioma): o app vem com inglês (e francês, que só precisa do layout do macOS). Chinês, coreano e híndi são pacotes que você baixa ao adicioná-los: adicionar chinês (pinyin) baixa os dicionários (cerca de 34 MB, 125 MB descompactados) com uma barra de progresso, e o pinyin funciona assim que o download termina, sem reiniciar; o pacote do coreano (sua tabela de teclas e como os jamo formam sílabas) e o do híndi (suas letras e palavras comuns) têm poucos kilobytes. Um pacote é só dados (dicionários, tabelas e esquemas, nunca código), listado em um índice assinado e verificado pelo SHA-256 antes de ser usado, como os plugins. O cartão de cada idioma mostra o pacote dele (versão, tamanho, origem) com "Delete…", e remover o idioma oferece apagar o pacote. Atualizar a partir da 0.6.1 ou anterior mantém o chinês sem download: o instalador mantém os dicionários que vinham com a versão antiga.
- **Fuzzy pinyin** (pinyin aproximado, com a entrada em chinês): sons que você não distingue podem ser digitados de qualquer forma, por exemplo z ↔ zh, n ↔ l, in ↔ ing. Na página "Input", escolha "Chinese (pinyin)" na barra de idiomas de entrada, ative "Fuzzy pinyin" e escolha os pares; os dicionários são implantados de novo em um ou dois segundos. Ele grava `rime_ice.custom.yaml` na pasta de usuário do Rime, e nunca por cima de um arquivo seu ali.
- **Translate (@translate)**: adicione os idiomas para os quais traduzir (espanhol, francês, alemão, japonês, coreano, chinês, híndi, bengali, tâmil e os outros principais idiomas indianos…) e arraste-os para ordená-los. Híndi digitado em letras latinas ("aap kaise ho") volta em devanágari. `@translate` escreve uma linha em cada um, nessa ordem (três versões se houver só um); o próprio idioma da frase é pulado. Uma instalação nova traduz para o primeiro idioma das preferências de idioma do seu Mac que não seja inglês; só com inglês, `@translate` abre esta página para você adicionar um.
- **Keyboard layouts** (layouts de teclado): o francês digita com o layout escolhido no cartão dele (`keyboardLayouts` na configuração). Para os outros idiomas, sob o método de entrada o macOS mantém o seu último layout latino (AZERTY, QWERTZ, espanhol, US International…), então você digita como sempre, `@` incluído, onde quer que o seu layout o tenha, e as teclas mortas também compõem no texto de um comando (⌥E e depois E → é, ^ e depois e → ê). Layouts sem letras latinas (russo, híndi InScript) não podem ser usados sob um método de entrada: alterne para eles com ⌃Space, ou cole (⌃V) ou dite texto em um comando.
- `@improve` refina e reescreve sem traduzir; `@translate @improve` juntos traduzem e reescrevem em uma única solicitação. Ative "@improve also translates" nos ajustes para que o `@improve` sempre faça isso.

## Estilos de reescrita

Depois das linhas 1–3 vêm as reescritas, **no idioma em que você digitou**: reescritas em inglês para inglês, em chinês para chinês. Escolha qualquer um destes estilos nos ajustes:

- "Polish" (refinar): mesmo tom, mais natural
- "Concise" (conciso)
- "Formal": para gestores e clientes
- "Casual" (informal)
- "Tactful" (diplomático)
- "Jargon" (jargão): o jargão da Amazon em inglês (bandwidth, circle back…), o jargão das big techs em chinês. Más notícias são suavizadas, por exemplo "this is a blocker bug" → "Oh! Looks like your team has the bandwidth to fix this minor issue!"

Reescritas que só mudam a pontuação ou repetem outra linha não são mostradas.

### Lista de jargão (seus próprios termos)

O Jargon não tem uma lista de termos embutida. Você pode preparar a sua (por exemplo, as expressões que a sua equipe usa), e o modelo dá preferência a esses termos. Nos candidatos, a linha do Jargon indica o que significam os termos que ela usou.

A lista é um arquivo de texto com um termo por linha, opcionalmente seguido do significado, separado por "=", dois-pontos ou Tab (você pode copiar duas colunas de uma planilha e colá-las). Linhas que começam com `#` são comentários:

```
PRFAQ = a new-feature proposal: the press release and FAQ, written first
COE = an incident review
two-way door = a decision you can undo at any time
```

Em "Rewrite Styles → Jargon list" nos ajustes, clique em "New" para criar uma lista vazia em `~/.config/allinoneime/jargon.txt` e abri-la; se você já tem um arquivo de lista, clique em "Choose File…" para usá-lo onde está (`jargonFile` na configuração). As alterações valem na hora. Só os primeiros 150 termos são lidos. Com "Jargon" marcado, a lista é enviada ao Bedrock junto com cada solicitação.

<img src="../en/panel-dark.png" width="420" alt="O painel de candidatos no modo escuro">

## Entrada por voz

<img src="../en/voice.png" width="340" alt="Mantenha a ⌥ direita pressionada para falar">

Mantenha a ⌥ direita pressionada e fale; quando você soltar, o texto é inserido. Ele é reconhecido no idioma em que você está digitando (inglês, chinês, francês, coreano ou híndi). Se você digitar um comando primeiro (por exemplo, `@improve `, `@question `) e depois falar, o texto vai depois do comando e ⏎ o executa; você também pode pressionar ⏎ sem soltar a ⌥ direita para executá-lo assim que terminar. A fala é reconhecida no próprio Mac pelo reconhecimento de fala embutido do macOS (SpeechAnalyzer), e nenhum áudio é enviado; isso requer macOS 26 ou posterior.

Na primeira vez:

- O macOS pergunta se o AllInOneIME pode usar o microfone. Você também pode clicar em "Allow Microphone" (permitir microfone) nos ajustes antes.
- Se este Mac ainda não tiver o modelo de fala desse idioma, ele é baixado uma vez, automaticamente. Você também pode baixá-lo nos ajustes.

A gravação só começa depois que você mantém a tecla pressionada por cerca de 0,2 s, então um toque rápido na ⌥ direita não liga o microfone (com a tecla de ação definida como "Tap ⌥", um toque executa a ação). Se você pressionar outra tecla enquanto a segura (um atalho com ⌥, ⌥←), isso conta como atalho e também nada é gravado. Pressionar qualquer outra tecla durante a gravação a cancela.

## Instalação

Executá-lo requer macOS 14 ou posterior; a entrada por voz, macOS 26 ou posterior. O instalador é universal: funciona em Macs com Apple silicon e Intel. Até agora só foi testado no macOS 27 em Apple silicon (a versão para Intel, apenas pelo autoteste sob Rosetta).

1. Baixe `AllInOneIME-<version>.dmg` em [Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases/latest) (só de lá) e abra-o.
2. Clique duas vezes em "Install AllInOneIME", dentro dele, e clique em "Install". O método de entrada vai para `~/Library/Input Methods` e o "AllInOneIME Settings" para `~/Applications`. Só para este usuário; não é preciso senha de administrador.
3. O instalador ainda não é notarizado pela Apple, então o macOS não consegue verificar quem o fez, e na primeira vez diz que não pode verificar "Install AllInOneIME": clique em "Done" (Concluído) ("Cancel" no macOS 14), abra "System Settings → Privacy & Security", clique em "Open Anyway" (Abrir Mesmo Assim) perto do fim da página e confirme. O instalador de cada nova versão precisa disso uma vez.

Depois disso, o AllInOneIME fica ativado e nas suas fontes de entrada; alterne para ele com Ctrl+Espaço (a tecla 🌐 só alterna se "Press 🌐 key to" estiver definido como "Change Input Source" em "System Settings → Keyboard"). Se o instalador disser para adicioná-lo manualmente, é porque este Mac não permite que programas o ativem; então adicione-o você mesmo, uma vez: "System Settings → Keyboard → Text Input → Input Sources → Edit… → + (canto inferior esquerdo) → English → AllInOneIME" (Ajustes do Sistema → Teclado → Entrada de Texto → Fontes de Entrada → Editar… → + → Inglês → AllInOneIME) (ele também digita pinyin depois que você adiciona o chinês em "Input" nos ajustes dele).

Se Ctrl+Espaço não leva você ao AllInOneIME, ou ele volta para U.S. depois de um tempo, execute o instalador de novo: ele adiciona o AllInOneIME de volta às suas fontes de entrada.

Para atualizar, instale de novo a partir da imagem de disco da nova versão, sem desinstalar antes; os ajustes, a lista de jargão e as palavras aprendidas são mantidos. Antes de atualizar, leia o [changelog](../../CHANGELOG.md): ele traz as mudanças de cada versão e as notas de atualização.

Se você tinha o AIPinyin instalado (o nome anterior do AllInOneIME), basta instalar: o antigo AIPinyin.app e o atalho dos ajustes dele são removidos, e a entrada nas suas fontes de entrada recebe o novo nome, sem precisar adicioná-la de novo. Os ajustes, a lista de jargão e as palavras aprendidas passam para as novas pastas (`~/.config/allinoneime` e outras) na primeira execução, e cada pasta antiga fica como um link para a nova.

Para desinstalar, abra "Install AllInOneIME" e clique em "Uninstall…". Os ajustes e as palavras aprendidas são mantidos.

### Compilar a partir do código-fonte

Compilar requer Xcode 26 ou posterior, já que a entrada por voz usa o SDK do macOS 26.

```sh
git clone https://github.com/MicroZ-LLC/AllInOneIME.git
cd AllInOneIME
make install
```

`make install` baixa o librime e os dicionários do rime-ice e os verifica, compila e instala nos mesmos lugares, adicionando-o às suas fontes de entrada da mesma forma. O app que ele instala não tem dicionários de chinês (eles são o pacote de idioma chinês): uma instalação que já os tinha os mantém como pacote; caso contrário, `make install-pack` instala o pacote a partir dos dicionários do checkout, sem download. `make status` mostra a versão instalada (`version:`) e se ele está nas suas fontes de entrada (`listed:`). Para desinstalar: `make uninstall`.

## Configurar a IA

As traduções e reescritas usam o seu próprio provedor de IA, e os custos vão para a sua conta: Amazon Bedrock na sua conta AWS por padrão, ou a Claude API, o Gemini ou um serviço compatível com OpenAI (veja "Outros provedores de IA" abaixo).

### Amazon Bedrock

1. Ative o Bedrock no console da AWS e confirme que você pode usar o modelo escolhido. O padrão é o Claude Haiku 4.5; na primeira vez que você usa um modelo da Anthropic, preenche uma única vez um formulário de caso de uso.
2. Crie uma chave de acesso com a permissão `bedrock:InvokeModelWithResponseStream` e coloque-a em um perfil em `~/.aws/credentials`. Por enquanto, só esse tipo de chave estática é suportado, não SSO nem assume-role.
3. Abra o "AllInOneIME Settings": você o encontra no Spotlight ou em Aplicativos, ou pode abri-lo pelo ícone do método de entrada na barra de menus → "Settings…". Escolha o perfil, a região e o modelo, e clique em "Test Connection" (testar conexão). "Language" (idioma), no topo da janela de ajustes, pode ser inglês ou chinês; por padrão ("System") segue o sistema (chinês se o chinês vier antes do inglês nos idiomas preferidos do sistema; inglês caso contrário). A janela de ajustes, as dicas no painel de candidatos e o menu de entrada seguem essa escolha.

<img src="../en/settings.png" width="420" alt="A janela de ajustes">

### Outros provedores de IA: Claude API, Gemini, serviços compatíveis com OpenAI

Você não precisa da AWS: escolha um provedor em "AI Provider" nos ajustes, cole uma chave de API, clique em "Save" e depois em "Test Connection".

| Provedor | Modelo padrão | Chave de API |
|---|---|---|
| Claude API | `claude-haiku-5-5` (o mais rápido e barato; Sonnet 5.5 e Opus 5.5 são mais cuidadosos, mas mais lentos e caros) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| Compatível com OpenAI | O `gpt-6-luna` da OpenAI (ou `gpt-5.4-mini`); "Common Services…" (serviços comuns) tem DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter e Ollama neste Mac: escolher um preenche a URL base dele, e depois você informa o modelo | A chave do serviço; defina a "Base URL" como o endereço dele, por exemplo `https://api.deepseek.com/v1`, ou `http://localhost:11434/v1` para o Ollama neste Mac |

- As chaves de API ficam no keychain do sistema, nunca no arquivo de configuração. Se não houver nenhuma lá, são usadas as variáveis `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (ou `GOOGLE_API_KEY`) e `OPENAI_API_KEY` do seu shell.
- "Thinking" (raciocínio) fica baixo por padrão: o método de entrada espera a cada frase, e menos raciocínio é mais rápido. Escolha "Not set" (não definido) para modelos que não o aceitam.
- Com o Claude Opus 5.5 ou o Sonnet 5.5 escolhido, as solicitações levam o fallback de recusa da Claude API (`fallbacks: "default"`): quando um classificador de segurança recusa, o servidor tenta de novo com outro modelo.
- No arquivo de configuração: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), e `model`, `baseURL`, `effort` e `temperature` dentro de `anthropic`, `gemini` e `openai` (os que não estiverem definidos usam os padrões).

Todos os ajustes ficam em `~/.config/allinoneime/config.json`; depois de uma alteração, a próxima tradução já usa os novos ajustes, sem reiniciar. As chaves mais novas:

| Chave | O que faz | Padrão |
|---|---|---|
| `inputLanguages` | Idiomas de entrada, de um a cinco; o primeiro é o padrão: `"en"` inglês, `"zh"` chinês (pinyin), `"fr"` francês, `"ko"` coreano, `"hi"` híndi, por exemplo `["en", "zh"]`, `["fr", "en", "ko"]`. Chinês, coreano e híndi funcionam depois que o pacote deles é instalado | `["en"]` (instalação nova) |
| `keyboardLayouts` | O layout de teclado com que um idioma de entrada digita, pelo código do idioma (por enquanto, só o francês): `{"fr": "com.apple.keylayout.French-PC"}` | Francês: `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | Para quais idiomas o `@translate` traduz, em ordem: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | O `@improve` também traduz (como `@translate @improve`) | `false` |
| `voiceInput` | Manter a ⌥ direita pressionada para falar | `true` |
| `actionKey` | Tecla de ação: `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Space), `"space"` (Space) | `"enter"` |
| `uiLanguage` | Idioma da interface (janela de ajustes, dicas do painel de candidatos, menu): `"zh"`, `"en"` | `null` (segue o sistema) |
| `rewriteStyles` | Estilos de reescrita: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, por exemplo `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | O seu próprio arquivo de lista de jargão | `null` (ou seja, `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | O ícone da barra de menus e o painel suspenso dele | `true` |
| `fuzzyPinyin` | Pares de pinyin aproximado: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |

## Privacidade

- A digitação (inglês e pinyin) e os cálculos do `@calculate` são inteiramente locais. Só quando você pressiona a tecla de ação em `@improve`, `@translate` ou `@question` essa frase é enviada ao provedor de IA que você escolheu (o seu próprio Bedrock, ou o serviço cuja chave você adicionou). Com "Jargon" marcado e uma lista de jargão definida, a lista é enviada junto.
- Com o AllInOneIME Cloud, a frase passa pelo servidor do desenvolvedor até um provedor de modelos (atualmente pelo OpenRouter): o servidor guarda apenas contagens, nunca o texto. Fazer login guarda apenas o seu endereço de e-mail.
- A voz só é gravada enquanto você mantém a ⌥ direita pressionada e é reconhecida no próprio Mac; o texto reconhecido só é enviado nos comandos acima, quando você pressiona a tecla de ação.
- O método de entrada lê o texto da área de transferência, uma vez, só quando você pressiona ⌃V ou ⌘V em um comando; conteúdo que gerenciadores de senhas marcam como oculto não é lido. O texto aparece primeiro no comando e, novamente, só é enviado quando você pressiona a tecla de ação. Versões recentes do macOS perguntam se o AllInOneIME pode ler a área de transferência: permita. Para não ser perguntado toda vez, defina a permissão de colar do AllInOneIME como sempre permitir em "System Settings → Privacy & Security".
- Em campos de senha, o macOS muda para o próprio teclado (U.S. ou ABC) e volta quando você sai deles. Sempre que o app em que você digita mantém a entrada segura, o AllInOneIME não compõe texto e não pode gravar: as teclas entram como digitadas. E enquanto o sistema está em entrada segura (campos de senha, a "Secure Keyboard Entry" do Terminal etc.), nada é enviado à IA.
- `@note` e `@reminder` não vão para a IA: o AllInOneIME entrega o texto apenas ao Notes e ao Reminders deste Mac, e também interpreta a hora do lembrete no próprio Mac (se esses apps o sincronizam com seus outros dispositivos depende das contas deles, como o iCloud). Por isso eles também funcionam durante a entrada segura.
- `@open` pesquisa apenas neste Mac. Ele lembra o que você abriu com ele (os últimos 200), nas preferências do próprio método de entrada (não no config.json), para listar esses itens primeiro.
- Para listar as suas notas, o painel da barra de menus guarda o id e a primeira linha (até 80 caracteres) das últimas 30 notas salvas com `@note`, nas preferências do próprio método de entrada, também enquanto o painel está desativado.
- `@py` e `@js` só rodam quando você pressiona a tecla de ação, e apenas com código que você mesmo digitou ou colou: as respostas da IA e a saída de outros comandos nunca são executadas como código. `@py` usa o `python3` do seu Mac, que pode ler e gravar arquivos e acessar a internet como faz no Terminal; `@js` roda em um processo separado que não pode ler arquivos, acessar a rede nem executar outros programas. Nenhum dos dois roda durante a entrada segura.
- Os logs não registram o que você digita. Para todo método de entrada de terceiros, o macOS avisa "The developer can access anything you type with this input source" (o desenvolvedor pode acessar tudo o que você digitar com esta fonte de entrada); é um aviso genérico do sistema.

## Desenvolvimento

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

Organização do código:

- `Sources/AllInOneIMECore`: cliente do Bedrock, SigV4, prompts, a máquina de estados de entrada de dois níveis (incluindo os comandos @ e o gesto de voz); sem dependência do AppKit
- `Sources/AllInOneIMERime`: wrapper do librime
- `Sources/AllInOneIME`: o método de entrada InputMethodKit, o painel de candidatos, a janela de ajustes, o reconhecimento de fala
- `Sources/AllInOneIMESettings`: o atalho "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: o "Install AllInOneIME" da imagem de disco: instala, atualiza e desinstala

Os pacotes de idioma têm a sua própria biblioteca, separada da dos plugins: o repositório [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), servido em https://languages.allinoneime.com/ e assinado com uma chave própria. `make pack` gera o arquivo compactado; ele é publicado lá como asset de release (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), e `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` grava o `packs.json` lá e o assina em `packs.json.sig` com a chave dos pacotes de idioma guardada no keychain (`allinoneime-languages-signing`). O app lê https://languages.allinoneime.com/packs.json, verifica a assinatura e depois o tamanho e o SHA-256 do arquivo compactado. Para testar um pacote a partir de um servidor local: `--test-key` assina com uma chave de teste, e `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

O bundle ID ainda é `com.aipinyin.inputmethod.AIPinyin`: o macOS o usa para lembrar a fonte de entrada adicionada e a permissão do microfone, então mudá-lo significaria adicionar o método de entrada e conceder a permissão de novo.

## Licença

Copyright © 2026 MicroZ LLC. Código-fonte disponível sob a [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): use, leia, altere e compartilhe para qualquer finalidade, exceto um produto concorrente. Cada versão passa a ser Apache-2.0 dois anos após o seu lançamento. As versões até a 0.6.1 foram lançadas sob a GPL-3.0 e continuam disponíveis sob ela.

Componentes de terceiros (o librime e seus plugins, sob BSD-3-Clause; os scripts Lua do rime-ice e o pacote de idioma chinês, sob GPL-3.0) estão listados em [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
