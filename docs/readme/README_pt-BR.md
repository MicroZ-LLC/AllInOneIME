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
[![Notarizado pela Apple](https://img.shields.io/badge/Apple-notarized-0a84ff?logo=apple&logoColor=white)](#instalação)
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
> A partir da 0.6.3, o AllInOneIME é assinado com um Developer ID e notarizado pela Apple: não é mais preciso permiti-lo em "System Settings → Privacy & Security" (Ajustes do Sistema → Privacidade e Segurança). Depois de atualizar de uma versão anterior, o macOS pede uma vez a sua senha de login para cada chave que o AllInOneIME guardou nas Chaves: digite-a e clique em "Always Allow" (Sempre Permitir). Baixe o AllInOneIME apenas do [GitHub Releases](https://github.com/MicroZ-LLC/AllInOneIME/releases) ou de [allinoneime.com](https://allinoneime.com).

Um método de entrada para macOS com comandos de IA em qualquer campo de texto. Comece uma frase com `@` e pressione ⏎ ao terminar: `@improve` refina o que você escreveu e oferece algumas reescritas, `@translate` traduz para os idiomas que você escolher, `@question` faz uma pergunta, `@agent` passa a tarefa para um agente de programação (Claude Code, Gemini CLI, Kiro CLI …) e `@open` encontra arquivos e apps ou abre um endereço web. Você também pode manter pressionada a tecla ⌥ direita e falar. Sem `@`, suas teclas vão para o app normalmente. Ele também digita chinês (pinyin, baseado em Rime e rime-ice), francês, coreano (Hangul) e híndi (devanágari a partir de letras latinas), e executa seus próprios scripts como comandos @.

O acionador de comandos é `@` por padrão. Em Settings → General → Command trigger você pode escolher outro símbolo: `#`, `%`, `&`, `*`, `+`, `|` ou `~`; os comandos passam a começar com ele (por exemplo `~translate`), e `@` é digitado normalmente. Letras, dígitos, espaços e os símbolos de que a digitação precisa (teclas do pinyin como `'` `-` `=` `[` `]` `` ` `` e os que o pinyin digita como pontuação chinesa, como `,` `.` `?` `\`) são recusados, e os ajustes dizem por quê. No arquivo de configuração: `"commandTrigger": "~"`.

![@improve e uma frase mal escrita, depois ⏎: versões refinadas, além de reescritas](../en/improve.png)

Para mais detalhes (todos os comandos e ajustes, solução de problemas de instalação, privacidade), veja a [Wiki](https://github.com/MicroZ-LLC/AllInOneIME/wiki). Feito por [Weijian Zhang](https://weijianz.com) na MicroZ LLC.

## Como usar

Sem `@`, ele não atrapalha: em inglês, as letras são digitadas diretamente e ⏎ é Return; nada vai para a internet. Uma instalação nova escreve em inglês; para digitar também chinês (pinyin), francês, coreano ou híndi, adicione o idioma nos ajustes (veja [Entrada e tradução](#entrada-e-tradução)).

| Tecla | O que faz |
|---|---|
| Digitar pinyin, Espaço / dígitos | No modo chinês: escolher palavras, como em qualquer método de entrada pinyin |
| `@` (no início de uma frase) | Abre a lista de comandos: os mais usados recentemente primeiro, 5 por vez, rolando com ↑↓, a roda do mouse ou o trackpad; ou digite letras para encontrar um (primeiro um nome digitado por inteiro, depois os nomes que começam com elas, depois os que as contêm). ⏎, Tab, Espaço ou um dígito escolhe |
| ⏎ | Executa o comando. Funciona mesmo que o pinyin ainda não tenha sido escolhido: ele é escolhido primeiro, como com Espaço |
| Espaço, ⏎ / dígitos | Quando os resultados aparecem: insere o destacado / o de número correspondente; 0 é o original. ⏎ insere mesmo com uma continuação digitada pela metade (ela é descartada) |
| ⇧⏎ | Com uma continuação digitada depois dos resultados da IA: envia-a (a próxima pergunta de uma conversa do `@question`, ou um refinamento). Enquanto um comando está sendo digitado, ou com resultados da IA e nada digitado: insere o que você digitou do jeito que está, `@command` incluído. Em outros resultados (`@open`, um lembrete …), insere a linha destacada, como o ⏎ |
| ⌘C | Copia o resultado destacado (no `@open`, o caminho); o painel de candidatos continua aberto |
| ⌃V | Em um comando (por exemplo, depois de `@improve `): acrescenta o texto da área de transferência depois do que você digitou, em vez de colá-lo no app. Várias linhas viram uma, até 2000 caracteres por vez (`@note` mantém as quebras de linha e aceita até 20000). Funciona em qualquer app; sem um comando, a tecla vai para o app normalmente |
| ⌘V | Como ⌃V, mas alguns apps tratam ⌘V por conta própria (terminais como Ghostty, iTerm2 e Terminal, e o Notes) e colam no app normalmente; use ⌃V neles |
| Esc, ⌫ | Volta para a frase para continuar editando; digitar pontuação ou dígitos depois dos resultados a continua. Depois de um refinamento: volta aos resultados de antes |
| Letras, com os resultados da IA na tela | Uma continuação: depois do `@question`, a próxima pergunta (veja [Conversas](#conversas-com-o-question-novo)); depois do `@improve` ou de um comando de instrução, uma instrução como `shorter` (veja [Refinar os resultados](#refinar-os-resultados-novo)); ⇧⏎ a envia. Depois do `@translate`, as letras continuam a frase, e ⏎ a traduz de novo |
| ⌘⏎, ⌘1–⌘9 | Em uma conversa do `@question`: mostra onde continuá-la (os agentes de programação instalados, primeiro aquele para o qual o `@agent` passa as tarefas; Claude, ChatGPT, Gemini; ou copiá-la); ⌘1, ⌘2 … escolhem um |
| Clicar em uma linha | No painel de candidatos: escolhe a linha, como o dígito dela faria (uma palavra, um comando da lista, um resultado, um arquivo do `@open`, um destinatário, uma linha de extensão); a linha sob o ponteiro fica destacada. O campo de texto mantém o foco |
| Toque em Shift | Com mais de um idioma de entrada: o próximo, na ordem deles (inglês → chinês → francês → …, e depois de volta ao primeiro) |
| Manter a ⌥ direita pressionada | Fale e solte para parar. No idioma em que você está digitando (inglês, chinês, francês, coreano ou híndi). Em um comando, o texto vai depois dele; caso contrário, é inserido diretamente |

## Comandos @ (beta)

| Comando | O que faz |
|---|---|
| `@improve` | Refinar: 1–3 são três versões no próprio idioma da frase, de 4 em diante vêm os estilos de reescrita (adicionados e ordenados nos ajustes), 0 é o original. Sem tradução; com "@improve also translates" (o @improve também traduz) ativado, funciona como `@translate @improve` |
| `@translate` | Traduz para os idiomas que você adicionou (ajustes → "Translate", arraste para reordenar), uma linha para cada um, três versões se houver só um; o próprio idioma da frase é pulado. `@translate @improve` juntos traduzem e reescrevem em uma única solicitação |
| `@question` | Faz uma pergunta; a resposta aparece nos candidatos, ⏎ ou Espaço a insere, ⌘C a copia. Continue digitando e ⇧⏎ faz uma pergunta de acompanhamento: o painel vira uma conversa de até 5 rodadas e depois sugere continuar no Claude ou em outra IA. Sem nada digitado depois, lista as suas últimas 5 perguntas, a mais recente primeiro; digitar filtra a lista (palavras em qualquer parte da pergunta, sem diferenciar maiúsculas, chinês também). Um dígito, ↑↓ e depois ⏎, ou um clique mostra na hora a resposta salva de uma pergunta, offline, para inserir ou copiar como sempre; ⌘R ali pergunta de novo para obter uma resposta nova. Sem correspondência, ou sem nada escolhido, ⏎ pergunta o que você digitou |
| `@reply` | Escreve três respostas para a mensagem à qual você está respondendo, no idioma da outra pessoa e no tom do app (o primeiro estilo de reescrita do app em Settings → Apps; senão, informal em apps de chat e formal no e-mail, onde cada resposta é o corpo inteiro de um e-mail). Passe a mensagem selecionando-a, copiando-a e pressionando ⌃V no rascunho, ou tirando uma captura de tela (⌃⇧⌘4, ou a do próprio WeChat) e pressionando ⌃V; o que você digita depois dele diz o que responder: `@reply politely decline`. ⌘R escreve mais três; veja [Responder com o @reply](#responder-com-o-reply-novo) |
| `@agent` | Passa a tarefa para um agente de programação no seu Mac, escolhido em Settings → Agent: Claude Code (o padrão), Gemini CLI, Kiro CLI ou um comando seu (o que você digitou é adicionado como último argumento). A página também mostra se cada um está instalado e como ele inicia. O Claude Code roda em segundo plano por padrão, com uma notificação quando termina (clique nela para abrir a sessão no Terminal e continuar), ou veja `@tasks`; desative lá, em Claude Code, "Runs in the background and notifies me" (roda em segundo plano e me avisa) para abri-lo no Terminal. Os outros agentes abrem no Terminal com o que você digitou como primeira mensagem. Cada um usa o próprio login e os próprios ajustes. No Google Chrome, ele leva a página junto: o endereço e o título, o campo em que você digitou com o formulário ou a seção dele (★ marca onde você está), o texto selecionado e o que está visível na janela — nunca um campo de senha, nunca a página inteira —, então `@agent why doesn't this work` no campo de usuário de um formulário de login é sobre esse campo, e `@agent why is this blocked` na página de um pipeline é sobre essa página; o agente julga qual dos dois. O texto da página vai para o agente como foi lido, marcado como vindo da web (não como instruções suas). Requer a permissão de Acessibilidade; o Chrome só monta a árvore da página para ele enquanto o `@agent` está sendo escrito ali, e a desliga depois (Settings → Agent → "@agent and @reply take the Chrome page along", o @agent e o @reply levam a página do Chrome junto, desativa tudo isso). Na primeira vez que ele abre o Terminal, o macOS pergunta se o AllInOneIME pode controlar o Terminal: clique em OK. (Antes da 0.6.4 ele se chamava `@claude`.) |
| `@tasks` | Lista as tarefas do Claude em segundo plano (trabalhando / concluída / aguardando você) com as últimas respostas; ⏎ abre uma no Terminal, ⌘C copia a resposta |
| `@settings` | Abre a janela de ajustes na hora (basta escolhê-lo) |
| `@open` | Lista arquivos, pastas e apps correspondentes enquanto você digita (Spotlight). Funcionam várias palavras-chave, separadas por espaços: cada uma precisa estar no caminho, e pelo menos uma no nome (o nome de uma pasta padrão vale para o que está dentro dela: `downloads pdf` encontra os PDFs em Downloads). Apps e pastas padrão também são encontrados pelos nomes em chinês, e uma interface em chinês os mostra assim. O que você abriu com `@open` vem primeiro, depois apps e essas pastas, depois arquivos usados ou alterados recentemente; quando os nomes encontram dois arquivos ou menos e nenhum app ou pasta desses, os arquivos da sua pasta pessoal também são pesquisados pelo conteúdo, com essas linhas marcadas como "content"; quando não há mais nada, ⏎ os lista para você escolher em vez de abrir o primeiro. Com um endereço web (`github.com`, `localhost:3000`, `https://…`), a primeira linha é "open in the browser" (abrir no navegador) e o conteúdo dos arquivos não é pesquisado; um arquivo com exatamente esse nome (digamos, `MANIFEST.in`) vem primeiro. Texto que começa com `~/` ou `/` é um caminho: Tab o completa e entra nas pastas; ⏎ abre, ⌘C copia o caminho |
| `@note` | Salva o texto no app Notes (Notas), em uma pasta chamada AllInOneIME (criada se não existir), ou onde Settings → Plugins → Notes (@note) indicar: o Notion, ou uma pasta de arquivos Markdown (um cofre do Obsidian ou qualquer pasta); nada é inserido. Texto colado mantém as quebras de linha, até 20000 caracteres |
| `@reminder` | Adiciona um lembrete ao app Reminders (Lembretes), em uma lista chamada AllInOneIME. Escreva a hora no texto; ela é interpretada no próprio Mac, e uma linha mostra o que foi entendido: ⏎ ou Espaço adiciona, Esc volta para editar. Com uma hora, o lembrete tem um alarme nesse momento; só com uma data, é de dia inteiro |
| `@py` | Executa uma linha de Python (o `python3` do Mac) e insere o resultado: o valor da última expressão do código, por exemplo `@py 2**100`, `@py import math; math.sqrt(2)`, ou então o que ele imprimiu. Não é oferecido sem `python3` (as ferramentas de linha de comando do Xcode o incluem) |
| `@js` | Executa uma linha de JavaScript e insere o mesmo: o valor da última expressão ou o que `console.log` imprimiu, por exemplo `@js [1, 2, 3].map(x => x * 2)`. Usa o JavaScriptCore embutido no macOS, então não há nada para instalar; ele não pode ler arquivos, acessar a rede nem executar outros programas |
| `@reportissue` | Relata um problema: abre no navegador a página do GitHub para uma nova issue, com o que você digitou depois do comando como título e "What happened / What you expected" (o que aconteceu / o que você esperava) para preencher. Acrescenta as versões do app e do macOS, a arquitetura do seu Mac, os idiomas da interface e de entrada, os pacotes de idioma instalados, o tipo de provedor de IA (e o modelo, se for público; senão "custom"), a tecla de ação e quantos comandos personalizados, plugins e extensões você tem, nunca os nomes deles, o seu texto, caminhos ou chaves. ⏎ (ou a sua tecla de ação) mostra tudo isso primeiro no painel de candidatos; ⏎ de novo, ou um clique na linha, abre a página, onde você revisa e clica em Submit (com a sua conta do GitHub); Esc volta. Também no menu de entrada ("Report an Issue…") e em Settings → About |
| `@imessage` | Envia um iMessage: digite um nome, um número de telefone ou um e-mail (um nome chinês também pelo pinyin, completo ou só as iniciais) e escolha o destinatário no painel de candidatos (as pessoas com quem você conversou recentemente vêm primeiro; um número ou endereço completo também funciona), depois escreva a mensagem (comandos dentro dela, como `@stock AAPL`, são executados primeiro). ⏎ mostra "Send to Alex (…): message" no painel, ⏎ de novo a envia, Esc volta para a edição; nada é digitado no campo de texto. Na primeira vez, o macOS pergunta se o AllInOneIME pode acessar o Contacts (Contatos) e controlar o Messages (Mensagens): clique em OK nos dois |

Exemplo: `@q` ⏎, digite `what is quantum computing`, ⏎. `@note books to read: The Three-Body Problem` ⏎ salva uma nota. `@reminder call Bob tomorrow at 3pm` ⏎, confira a hora que ele entendeu e pressione ⏎ de novo para adicionar. Depois de escolher o comando, você também pode manter a ⌥ direita pressionada e falar. No modo chinês, `@open` passa para letras inglesas no momento e volta ao chinês quando você termina.

O código de `@py` e `@js` é digitado em letras inglesas, e a pontuação de largura total (do modo chinês) vira ASCII; escreva-o em uma linha, com `;` entre as instruções. Ele roda em um processo separado, interrompido após 10 segundos ou com Esc a qualquer momento; em caso de erro, a primeira linha do erro é mostrada, por exemplo `ZeroDivisionError: division by zero`. Uma saída com várias linhas é inserida como foi impressa; em um terminal, entra como uma linha só (um terminal executa cada linha que recebe). Um terminal dentro de um editor (VS Code, Cursor, JetBrains) não pode ser distinguido do próprio editor, então ali a saída com várias linhas de qualquer comando entra como está. Os dois também funcionam dentro da frase de outro comando: `@reply the answer is @py 2**100`; coloque código com espaços entre aspas: `@question explain @py "sum(x * x for x in range(10))"`. O contrário não vale: o código de `@py` e `@js` sempre roda exatamente como você o digitou, e `@commands` dentro dele não são executados antes.

![Digitar @ abre a lista de comandos; @question mais uma pergunta, depois ⏎ para a resposta](../en/commands.png)

![@open encontra apps enquanto você digita; começando com /, é um caminho: a pasta é listada, Tab completa](../en/open.png)

Quando `@` não é seguido de um comando, como em `@john`, o `@` é inserido normalmente, então mencionar pessoas com @ em apps de chat continua funcionando. Digitado logo depois de uma letra, um dígito, `.`, `_` ou `-`, como em `bob@example.com` ou `ssh user@host`, o `@` é só texto: nenhuma lista abre, em nenhum app, terminais incluídos. Com a lista aberta, ← → ou uma tecla que não pode fazer parte do nome de um comando (`.`, `:`, `/`) a fecham e deixam o que você digitou (`@`, `@im`) como está; em um terminal, ← → então só fecham a lista. `@question`, `@improve`, `@translate` e `@reply` enviam para o seu próprio Bedrock somente quando você pressiona a tecla de ação (uma captura de tela é lida neste Mac e só o texto dela é enviado); `@open` pesquisa apenas neste Mac; `@note` e `@reminder` vão apenas para o Notes e o Reminders deste Mac (o `@note` vai para uma pasta ou para o Notion, se você escolheu um deles); `@agent` usa o agente instalado no seu Mac (por padrão, o comando `claude` do Claude Code) e a conta dele, e pergunta antes, como de costume, de alterar arquivos ou executar comandos. Sem o agente instalado, `@agent` não é oferecido. `@imessage` lê o Contacts apenas neste Mac (nomes, números de telefone, e-mails), nunca passa pela IA, e é o Messages que envia a mensagem; sem o app Messages, ele não é oferecido.

### No texto selecionado (novo)

Selecione um texto em qualquer app (uma frase no Notas, um parágrafo no Mail), digite `@improve`, `@translate`, `@question` ou outro comando que receba texto e pressione ⏎: o comando trabalha sobre a seleção, e o resultado que você escolher a substitui. A seleção fica como está, selecionada, enquanto você digita: o comando é escrito no painel de candidatos, cuja primeira linha é o que você digita e a seguinte "On the selection: “…” (N characters)" (na seleção: N caracteres). Esc, ⇧⏎ ou clicar em outro lugar deixam o texto como estava; o mesmo acontece se você mudar a seleção nesse meio-tempo, o que cancela o comando. O texto digitado depois do comando é uma instrução para `@improve` e `@translate` (`@translate ja`, `@improve more formal`) e a pergunta para `@question` (`@question what does this mean`), sobre a seleção. `@open`, `@agent`, `@tasks`, `@settings`, `@reminder`, `@imessage`, `@reportissue`, os comandos de terminal e as extensões de script não a usam: recebem o que você digita, e a seleção fica como está. Até 5000 caracteres; nunca é lida durante a entrada segura nem em um terminal. Desative em Settings → General → "Use the selected text" (usar o texto selecionado) se não funcionar bem em algum app.

### Responder com o @reply (novo)

`@reply` escreve três respostas que você poderia enviar para a mensagem à qual está respondendo. Passe a mensagem de qualquer uma destas formas e pressione ⏎:

- **Selecione-a** no campo e digite `@reply` (a resposta escolhida entra depois dela, em uma linha própria).
- **Copie-a**, digite `@reply` e pressione ⌃V: o painel mostra "Copied message · N characters" (mensagem copiada · N caracteres), e o rascunho fica como está.
- **Tire uma captura de tela** para a área de transferência (⌃⇧⌘4, ou a captura do próprio WeChat), digite `@reply` e pressione ⌃V: o painel mostra "Screenshot · N lines (read on this Mac)" (captura de tela · N linhas, lida neste Mac). A captura é lida neste Mac (pelo Vision da Apple; na primeira vez, um pouco mais devagar) e só o texto dela é enviado; a imagem não vai para lugar nenhum e não é guardada. As linhas à esquerda são da outra pessoa e as da direita são suas, como os apps de chat as mostram; os horários entre as mensagens ficam de fora. Use-a no WeChat, cuja janela não pode ser lida de nenhum outro jeito.

Digite depois dele o que você quer dizer (`@reply politely decline`, `@reply 委婉拒绝`), ou nada, para uma resposta sensata. As respostas saem no idioma da outra pessoa, a menos que você peça outro, e no tom do app: o primeiro estilo de reescrita do perfil dele (Settings → Apps); senão, informal em apps de chat e formal em apps de e-mail, onde cada resposta é o corpo inteiro de um e-mail. O texto em volta do cursor também vai junto. ⌫ sem nada digitado depois de `@reply` remove o que foi colado. ⏎ ou um dígito insere uma resposta; ⌘R escreve mais três (Esc traz as anteriores de volta), e digitar uma instrução as refina, como em qualquer resultado da IA. No Google Chrome, sem nada selecionado nem colado, ele leva a página junto, como o `@agent` (Settings → Agent → "@agent and @reply take the Chrome page along"). Sem nada a que responder e sem nada digitado, ele diz do que precisa. Ocultar informações sensíveis cobre também o texto da captura; durante a entrada segura, a área de transferência não é lida e nada é enviado. Um comando personalizado que você tinha chamado de `reply` agora é `@myreply`.

Uma captura de tela colada em qualquer outro comando também funciona: `@translate` ⌃V a traduz (no cursor), `@question what does this say` ⌃V pergunta sobre ela, e os comandos sem IA recebem o texto dela como se ele tivesse sido copiado (o `@note` mantém as linhas). Com texto selecionado, `@improve` e `@translate` continuam trabalhando sobre a seleção, e um aviso diz que a captura não foi usada.

### Refinar os resultados (novo)

Enquanto os resultados do `@improve`, de um comando de instrução (seu ou de um plugin) ou da reescrita de uma seleção estão na tela, digite o que mudar, como `shorter`, `warmer`, `more formal`, `add a joke`, `in Japanese` ou `用更口语的说法` (pinyin funciona, e um toque em Shift troca de idioma), e pressione ⇧⏎: os resultados voltam para a IA com a sua instrução, e os novos os substituem no mesmo painel. ⏎ insere o resultado selecionado, mesmo com uma instrução digitada pela metade (ela é descartada). Refine quantas vezes quiser; a linha de cima do painel lista as etapas ("Refined: shorter · more formal"), e você pode escolher uma linha a qualquer momento, como sempre. Uma letra começa a instrução (mostrada como "refine › …" no topo do painel); enquanto ela está vazia, dígitos, Espaço e ⏎ escolhem como antes, e ⇧⏎ insere o que você digitou do jeito que está. O refinamento começa quando os resultados estão completos: digitar enquanto os primeiros resultados ainda chegam continua a frase, como antes. Enquanto um refinamento roda, você já pode digitar a próxima instrução; o refinamento continua, e ⇧⏎ executa a próxima assim que os resultados dele chegam. Esc apaga a instrução, depois volta uma etapa para os resultados de antes do último refinamento (durante um refinamento: interrompe-o), depois volta para a frase; ⌫ em uma linha vazia volta do mesmo jeito. No texto selecionado, o resultado escolhido continua substituindo exatamente a seleção, que não é tocada até lá. Um refinamento que falha (ou é recusado durante a entrada segura) deixa os resultados como estavam, com a instrução pronta para tentar de novo com ⇧⏎. O mesmo refinamento dos mesmos resultados é respondido a partir do cache. O `@translate` não tem refinamento: digitar depois dos resultados dele continua a frase, e ⏎ a traduz de novo.

### Conversas com o @question (novo)

Depois que o `@question` responde, o que você digita é a próxima pergunta: ⇧⏎ a faz, junto com as perguntas e respostas até ali, e o painel vira a conversa, com as rodadas anteriores esmaecidas como linhas Q / A e a resposta mais recente abaixo delas. A linha de cima diz qual rodada vem a seguir ("question 2/5 › …"). Qualquer resposta pode ser inserida: pelo dígito dela (1–5), ↑↓ e depois ⏎, ou um clique; a mais recente fica selecionada, e ⌘C copia a selecionada. ⏎ a insere mesmo com uma pergunta digitada pela metade (ela é descartada). Esc apaga o que você digitou e depois volta uma rodada; na primeira, sai como antes. O painel cresce até cerca de metade da tela e depois rola, com o mais recente embaixo.

Depois de 5 rodadas (`questionRounds` na configuração, 2–10), a linha da próxima pergunta passa a ser "5 rounds in: continue in Claude or another AI" (5 rodadas: continue no Claude ou em outra IA), com as opções numeradas ⌘1, ⌘2 …; ⌘⏎ as mostra em qualquer rodada (enquanto uma resposta ainda está chegando, não faz nada e nunca chega ao app). O que você digitar então é a primeira mensagem lá; só ⌘1, ⌘2 … a enviam (⇧⏎ não pergunta mais nada e não abre nada). Uma pergunta sobre texto selecionado leva esse texto junto, citado em um bloco próprio. As opções:

- **Os agentes de programação instalados** neste Mac, cada um pelo nome: primeiro aquele para o qual o `@agent` passa as tarefas (⌘1), depois os outros (Claude Code, Gemini CLI, Kiro CLI, o seu próprio comando de Settings → Agent). Cada um abre uma sessão interativa no Terminal, iniciada como o `@agent` a inicia, que começa com a conversa e "Let's continue this discussion". Um que não está instalado não aparece.
- **Claude** ou **ChatGPT** na web, com a conversa já preenchida (uma longa vai para a área de transferência: cole-a).
- **Gemini** na web, com a conversa na área de transferência para colar.
- **Copy the conversation** (copiar a conversa), em Markdown (**Q:** / **A:**).

Quais, e em que ordem (a primeira é a padrão): Settings → General → "Continue a conversation in" (continuar uma conversa em; `questionContinueIn` na configuração); com mais de 5, ⌘6 … ⌘9 escolhem os restantes. "@agent's agent" (o agente do @agent) é ali o agente que Settings → Agent escolher, pelo nome; um agente que não está instalado agora mantém o seu lugar na lista quando você a edita. Com o Apple Intelligence neste Mac, uma conversa longa não cabe no contexto pequeno dele: as respostas mais antigas são encurtadas, depois as rodadas mais antigas ficam de fora, e o painel diz "earlier rounds shortened" (rodadas anteriores encurtadas). Uma conversa é salva sob a primeira pergunta dela nas perguntas recentes, e escolhê-la mostra as rodadas para continuar.

### Perguntas recentes (novo)

`@question` sem nada digitado depois lista as suas últimas 5 perguntas, a mais recente primeiro, com quando foram feitas ("3 hours ago"). Digitar filtra a lista: cada palavra em qualquer parte da pergunta, sem diferenciar maiúsculas (chinês sem espaços também). Um dígito, ↑↓ e depois ⏎, ou um clique mostra na hora a resposta salva de uma pergunta, sem ir à internet: Espaço ou ⏎ a insere, ⌘C a copia, ⌘R pergunta de novo para obter uma resposta nova (em uma conversa: a última pergunta dela), Esc volta à lista. Uma conversa salva mostra todas as rodadas: digite para continuá-la. Sem correspondência, ou sem nada escolhido, ⏎ pergunta o que você digitou. Uma nova resposta à mesma pergunta, ou uma conversa que continua, substitui a salva.

- Elas ficam guardadas só neste Mac (veja Privacidade): não durante a entrada segura, e nunca para perguntas sobre texto selecionado.
- Settings → General → "Remember recent questions" (lembrar as perguntas recentes) desativa o recurso (`rememberQuestions` na configuração); desativado ali, ele também as apaga. Desativado pelo Settings → Assistant, elas são mantidas, para que desfazer devolva exatamente o que havia (a pré-visualização dele avisa); "Clear (N)" (limpar) as apaga.

### Notas e lembretes

`@note` cria uma nota nova; a primeira linha é o título. Depois de copiar algum texto, ⌃V depois de `@note ` (ou ⌘V, fora de terminais) o salva com as quebras de linha, mostradas como ↵ no comando. Para onde ela vai fica em Settings → Plugins → Notes (@note) → Save to (salvar em):

- **Notes** (como antes): uma nota nova na pasta AllInOneIME.
- **Folder (Obsidian or any)** (pasta, do Obsidian ou qualquer outra): um arquivo Markdown novo por nota na pasta que você escolher, com o nome da primeira linha dela (`/\:*?"<>|#^[]` viram `-`; um nome já usado ganha " 2", " 3"). O arquivo traz um front matter `created:` e depois o texto inteiro, como foi digitado. Um arquivo nunca é sobrescrito, e uma pasta que não existe (um disco desmontado, um cofre movido) não é criada: em vez disso, a nota volta. Em um cofre do Obsidian (com uma pasta `.obsidian` nele ou acima dele), o aviso diz "Saved to Obsidian", e o painel da barra de menus abre a nota no Obsidian.
- **Notion**: Create Integration… (criar integração: New integration → Internal → copie o token), cole o token (guardado nas Chaves) e, no Notion, abra a página ou o banco de dados → ··· → Connections → adicione a sua integração; depois cole aqui o link da página ou do banco de dados. O Test mostra "✓ “Inbox” (database)". Uma página ganha uma subpágina nova, e um banco de dados, uma linha nova (com a primeira linha como título); o resto da nota é o corpo, em uma única solicitação. Sem conexão ou com recusa, nada fica guardado para enviar depois: a nota volta. Durante a entrada segura, o `@note` não envia para o Notion.

O aviso diz para onde a nota foi ("Saved to Notion", "Saved to “Inbox”"). Se você sair do campo de texto (clicar em outro lugar, trocar de app) ou pressionar ⇧⏎ (inserir como digitado) antes que uma nota com quebras de linha seja salva, ela não é digitada no app (em um terminal, cada linha seria executada como um comando): em vez disso, vai para a área de transferência ("The note wasn't saved; its text is on the clipboard"). Uma nota de uma só linha é inserida como foi digitada.

`@reminder` entende horários como `tomorrow at 3pm`, `in 2 hours`, `in 3 days at 3pm`, `on the 15th`, `this weekend`, `in 1 month`, `next month` (o dia 1º), `end of the year` (e também horários em chinês). O dia e a hora podem estar separados (`tomorrow call Bob at 5`); as semanas começam na segunda-feira. Uma hora sem am ou pm (`at 5`) é a próxima, nunca entre meia-noite e 6 da manhã; uma hora que já passou hoje fica para amanhã, mas uma parte do dia ainda em andamento (`this afternoon`, `tonight`) é hoje, o dia inteiro; uma data que já passou neste ano fica para o ano que vem. Um lembrete escrito para se repetir (`standup every Monday at 9`) é adicionado uma vez, para a próxima ocorrência: as palavras ficam no título e a linha diz "once only" (só uma vez). A linha de confirmação mostra a hora entendida, por exemplo "tomorrow 3:00 PM" (seguindo o ajuste de 12/24 horas do Mac); se estiver errada, Esc volta para o texto. Sem hora nem data no texto, o lembrete não tem nenhuma ("no date").

`@stock` e similares dentro desses dois não são executados: o texto é salvo como foi escrito (digitar `@` ali não abre a lista de comandos). Na primeira vez, o macOS pergunta se o AllInOneIME pode controlar o Notes (`@note`) ou acessar o Reminders (`@reminder`): permita. Se não permitiu, autorize o AllInOneIME em "System Settings → Privacy & Security → Automation" (Ajustes do Sistema → Privacidade e Segurança → Automação) (Notes) ou → "Reminders". Quando um salvamento falha (por falta de permissão, por exemplo), o aviso diz o motivo e o texto volta para o comando, para você corrigir e enviar de novo; quando é preciso corrigir algo antes (uma permissão, uma conta), ele também é colocado na área de transferência (ir para o System Settings tira o foco do campo de texto). Se você já foi para outro campo de texto ou está digitando outra coisa, ele vai para a área de transferência ("Not saved; the text is on the clipboard.").

### Seus próprios comandos

Nos ajustes, em "Custom @ Commands" (comandos @ personalizados), clique em "Add Command…" (adicionar comando): dê um nome e escolha o que ele faz (uma instrução para a IA, um programa, um programa no Terminal, uma página web ou um texto para inserir), ou comece a partir de um exemplo. Seus comandos vêm depois dos embutidos; os nomes usam apenas letras inglesas e não podem ser o de um comando embutido; eles funcionam a partir da próxima frase. Eles ficam em `customCommands` no arquivo de configuração (`~/.config/allinoneime/config.json`), que você também pode editar:

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

| `type` | O que faz |
|---|---|
| `prompt` | Vai para a IA com `prompt` como instrução; a resposta aparece nos candidatos, para inserir ou copiar (⌘C) |
| `run` | Executa `argv` em segundo plano; o que ele imprime aparece nos candidatos (várias linhas são inseridas como foram impressas; em um terminal, como uma linha só). Em caso de erro, a última linha dele é mostrada |
| `terminal` | Executa `argv` em uma nova janela do Terminal; nada é inserido |
| `link` | Coloca o texto no endereço web `url` e o abre no navegador padrão; nada é inserido |
| `snippet` | Insere `text` na hora, com os marcadores preenchidos (veja abaixo); sem IA, sem programa |

- `{input}` vira o que você escreveu depois do comando, e sempre fica dentro do único argumento em que está: nenhum shell é envolvido. Para usar um shell, diga isso explicitamente, como o `sh` acima (`zsh -c`).
- `stdin`: o que vai para a entrada padrão do programa, também com `{input}` substituído.
- O `url` de um `link` precisa ser `https://`, com `{input}` uma vez, depois do `?` ou do `#`; o texto é codificado (um espaço vira `%20`, uma quebra de linha `%0A`), com no máximo 4000 caracteres.
- `run` e `terminal` digitam letras inglesas por padrão (como `@open`; no modo chinês, o chinês volta depois), e a pontuação de largura total vira ASCII. Defina `"ascii": false` para manter o texto como digitado.
- Os programas rodam na sua pasta pessoal com o PATH do seu shell de login (assim, o que foi instalado com Homebrew, pyenv e nvm é encontrado). `run` interrompe um programa após 10 segundos (`timeoutSeconds`) ou quando ele imprime demais; Esc o interrompe a qualquer momento.
- `summary` é a descrição na lista de comandos (opcional).
- Quando o programa em `argv` não é encontrado (digamos, sem `python3`), o comando não é oferecido e `@python …` é inserido como texto; depois que o programa é instalado, o comando aparece no próximo campo de texto.

`run` e `terminal` executam código no seu Mac: adicione apenas comandos que você escreveu e em que confia. Eles também só rodam quando você pressiona a tecla de ação, e nunca durante a entrada segura.

#### Snippets: textos que você insere com frequência (novo)

Um comando `snippet` ("Insert text", inserir texto, no editor) insere um texto que você salvou, como uma assinatura, um endereço ou o link de uma reunião: `@sig` ⏎ o coloca na hora (Tab ou Espaço só completam o nome). O `text` dele pode ter marcadores:

| Marcador | Vira |
|---|---|
| `{input}` | tudo o que você escreveu depois do nome: `@tag foo bar` com `#{input}` insere `#foo bar` |
| `{name?}` | uma lacuna, preenchida com o que você escreveu, separado por vírgulas (`,` ou `，`), na ordem: `Dear {name?}, see you {day?}.` com `@meet Bob, Friday`. Se uma ficar vazia, um aviso diz qual, e nada é inserido |
| `{clipboard}` | o texto da área de transferência (o macOS pode perguntar antes) |
| `{selection}` | o texto selecionado quando você digitou `@` (ele é substituído, como por qualquer comando sobre a seleção) |
| `{date}`, `{time}` | a data de hoje como `2026-10-17`, a hora como `14:05`; `{date:EEEE, MMM d}` com um [padrão de data](https://unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table), no idioma da interface |
| `{cursor}` | onde o cursor fica depois da inserção (no máximo uma vez; não em um terminal) |

- `{{` escreve `{`, e o `}}` que o fecha escreve `}` (`{{input}}` insere `{input}`); qualquer outro `}}` ou `{…}` fica como está, então JSON ou código em um snippet não é problema: `{"a":{"b":1}}` entra como foi escrito.
- Sem `{input}` e sem lacunas, o que você escreve depois do nome entra depois do snippet, após um espaço.
- Escreva `@sig` dentro do texto de outro comando para incluí-lo: `@question summarize this @zoom` envia o próprio link. Ali só funcionam snippets sem `{clipboard}`, `{selection}` ou lacunas; com `{input}`, o argumento é uma palavra ou uma expressão entre aspas: `@meet「Friday 3pm」`.
- Só texto simples (as quebras de linha são mantidas), no máximo 20.000 caracteres. Os snippets ficam neste Mac, então funcionam durante a entrada segura e em apps definidos como No AI. Os bundles de extensões também podem trazê-los (`snippets` no `extension.json`; veja [docs/extensions.md](../extensions.md)).

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

Os modos do Raycast correspondem assim: `fullOutput` → `show`, `compact` e `silent` → `silent`, `inline` com `refreshTime` → um status. O protocolo completo está em [docs/extensions.md](../extensions.md); [Core/Examples/extensions](../../Core/Examples/extensions) tem um de cada tipo. Extensões executam código no seu Mac: use apenas as que são de confiança. Elas só rodam quando você as executa (um status ou uma lista enquanto você digita), nunca durante a entrada segura, e param quando o método de entrada é encerrado.

#### Fontes de extensões (novo)

Um bundle pode vir de um repositório Git, seu ou da sua equipe, e se manter atualizado a partir dali. Settings → Custom Commands → Extension Sources → **Add from Link…** (adicionar a partir de um link): cole o endereço do repositório (`git@github.com:you/my-extensions.git`, `ssh://…`, `https://…`; opcionalmente uma branch, a pasta do bundle no repositório e uma tag ou um commit em que fixá-lo). O AllInOneIME o clona com **a sua própria configuração de git e SSH** (chaves, agente, ~/.ssh/config, auxiliares de credenciais), então um repositório privado funciona como no Terminal; o app nunca pede nem guarda uma senha. O clone vai para `~/Library/Application Support/AllInOneIME/Sources/`: primeiro para uma pasta de preparação oculta, nunca direto para uma pasta de extensões. (Não coloque um nome, uma senha ou um token em um endereço https: o auxiliar de credenciais do git os guarda.)

- **Revisão primeiro.** Antes que qualquer coisa seja carregada, você vê o bundle, cada comando (nome, título, descrição, saída), os programas que eles executam, as preferências dele e o commit, sob o aviso "This source isn't signed: it will run programs from <address>" (esta fonte não está assinada: ela vai executar programas desse endereço). Só **Enable** (ativar) a adiciona; Cancel (cancelar) apaga o clone. Você revisa uma fonte uma única vez.
- **Quem aplica as atualizações é você.** Uma vez por dia (e logo depois que o método de entrada inicia), a fonte é buscada (fetch) para ver o que há de novo: os ajustes mostram "N updates" (N atualizações) com os commits (assunto, autor, data) e um selo na página. Nada muda até você clicar em **Update** (atualizar), que só avança em fast-forward e não executa nenhum hook. Um push forçado faz a fonte precisar de uma nova revisão: **Re-clone** (clonar de novo) a mostra, e só o Enable coloca o histórico reescrito no lugar (até lá, a versão revisada continua funcionando). Uma fonte fixada em uma tag ou um commit não é verificada. A verificação diária pode ser desativada fonte por fonte (`autoCheck`).
- **Os erros** são as palavras do próprio git, com "This uses your own git and SSH setup; check that `git ls-remote <url>` works in Terminal" (isto usa a sua própria configuração de git e SSH; verifique se esse comando funciona no Terminal), e embaixo o seu próprio lembrete, se você definiu um (`authHint` na configuração).
- **Remove** (remover) move o clone para o Lixo; as preferências do bundle são mantidas para a próxima vez.
- Pelo terminal: `AllInOneIME --add-source <url> [--path …] [--branch …] [--pin …]` (mostra a revisão e ativa a fonte; de novo depois de um push forçado), `--update-sources` (avança em fast-forward cada fonte revisada que não esteja fixada), `--list-extensions` (no `~/Library/Input Methods/AllInOneIME.app/Contents/MacOS/AllInOneIME`).
- Só código revisado é carregado: uma pasta de fonte na lista de carregamento que não foi revisada neste Mac (uma configuração copiada) fica de fora. O git nunca espera uma resposta: sem terminal e sem perguntas, então uma chave de host desconhecida ou um pedido de senha falha na hora.

A configuração as guarda como `extensionSources`; a estrutura do repositório está em [docs/extensions.md](../extensions.md#10-extension-sources).

### Plugins

Plugins são comandos `@` prontos para coisas de que nem todo mundo precisa, como `@stock AAPL 600519 700` para cotações de ações. Uma vez instalados, funcionam como qualquer comando; "Plugins" nos ajustes mostra o que está instalado e para onde cada um envia o seu texto, e permite removê-los. Plugins são JavaScript executado em um processo separado: só podem acessar os sites que declaram (HTTPS), e não podem ler arquivos nem executar outros programas. "Browse Library…" (explorar biblioteca), em "Plugins" nos ajustes, os instala a partir da [biblioteca de plugins](https://github.com/MicroZ-LLC/AllInOneIME-plugins): ela mostra quais sites um plugin contata antes de instalá-lo; o índice da biblioteca é assinado e todo arquivo precisa corresponder a ele. Uma versão mais nova mostra um botão "Update" (atualizar); nada se atualiza sozinho. Seus próprios plugins ficam em `~/.config/allinoneime/plugins/` ("Open Plugins Folder"): são plugins locais, nunca sobrescritos pela biblioteca. Plugins de "link" não executam código: colocam o texto em um endereço web e o abrem no navegador, como `@x nice weather today`, que abre o editor de posts do X com o texto preenchido; publicar fica por sua conta, na página. A biblioteca tem quatro (`@x`, `@threads`, `@bsky`, `@weibo`). `@xe` converte moedas: `@xe 100 USD CNY`, `@xe 1000 JPY EUR`, uma linha com a data da cotação (cotações da ExchangeRate-API). `@calculator` é uma calculadora que funciona offline, `@calculator 23*17` → `391` (o `@calculate` embutido antes da 0.6.5), e `@calendar` faz contas com datas: `@calendar +10` → "Tue, Oct 27 · in 10 days". Para escrever um plugin: [docs/plugins.md](../plugins.md).

Comandos que buscam algo (plugins e programas) também funcionam dentro de uma frase: `@reply tell her @stock AAPL is up today`. Os internos rodam primeiro, a saída deles toma o seu lugar, e o comando externo trabalha sobre o resultado. O argumento é a palavra depois do comando, mais os códigos em maiúsculas ou números logo em seguida (`@stock AAPL TSLA`, `@stock 600519 700`); uma palavra em minúsculas o encerra (`@stock SNDK is good to buy` consulta SNDK). Aspas o delimitam exatamente: `@stock "aapl tsla"`. O plugin `@calculator` também funciona ali: `@reply the total is @calculator 23*17 dollars`. Dentro de `@agent` e de comandos de terminal eles não são executados: esses recebem o texto como foi escrito (digitar `@` ali não abre a lista de comandos).

### Tecla de ação

⏎ por padrão; altere em "Action key" (tecla de ação) nos ajustes (`actionKey` na configuração): ⏎, "Tap ⌥" (tocar em ⌥, de qualquer lado: pressione e solte logo; manter a ⌥ direita pressionada continua sendo para falar), ⌥Space ou Space (pressione Espaço mais uma vez depois que as palavras forem escolhidas; duas vezes no modo inglês). Seja qual for a tecla de ação, os comandos @ também rodam com ⏎. Se ⌥Space já for um atalho do Alfred, do Raycast ou similares, eles o recebem primeiro.

### Digitar os resultados

Ative "Type results out" (digitar os resultados) em Settings → General (`typeOut` na configuração) e o resultado de um comando é digitado no app caractere por caractere, como uma pessoa digitando, em vez de entrar de uma vez; as escolhas do pinyin continuam entrando de uma vez. O controle deslizante define o ritmo, de 6 segundos por caractere a 40 por segundo (`typeOutRate`), e "Speed up and slow down (like a person)" (acelerar e desacelerar, como uma pessoa) digita em rajadas de ritmo variável (`typeOutVaries`). Esc para onde estiver; qualquer outra tecla digita o resto de uma vez.

"Make occasional typos and fix them" (cometer erros de digitação de vez em quando e corrigi-los, `typeOutMistakes`) deixa tudo ainda mais parecido com uma pessoa: de vez em quando a tecla ao lado da certa, percebida até três letras depois, apagada e digitada de novo; uma letra ou um espaço digitado duas vezes e apagado; ou uma palavra curta digitada, apagada e digitada de novo. Alguns a cada 100 caracteres, nunca dois próximos e nunca no início de uma linha. Em código, endereços web e de e-mail e números, um erro é só uma letra ou um dígito errado, corrigido na hora (nunca um parêntese, aspas ou espaço errado, com os quais os editores fazem pares ou recuos). As letras erradas são vizinhas no seu layout de teclado (QWERTY, AZERTY, QWERTZ…). Chinês, japonês e coreano só hesitam (dois caracteres digitados, apagados e digitados de novo), nunca com um caractere errado.

Em um campo que aceita desfazer um erro (as visualizações de texto da Apple, como o TextEdit e o Notas, navegadores, a maioria dos editores): digitado até o fim, ou com outra tecla pressionada para digitar o resto de uma vez, o texto é exatamente o resultado; Esc (ou sair do campo) no meio de um erro remove o erro primeiro, de modo que o campo contém um início exato do resultado. Se o cursor se move enquanto um erro está na tela (um clique), o erro é removido onde estava e o resto é digitado sem erros.

Nunca há erros em terminais, nem em apps que não informam ao método de entrada onde o cursor está. A cada vez, o primeiro erro é simples (uma letra errada, corrigida de uma vez), até que o campo mostre que aceita desfazer um erro; enquanto um erro está na tela, o método de entrada confere antes de cada tecla que o campo contém o que ele digitou. Um campo que ignora onde substituir o texto não consegue desfazer um erro: ali esse primeiro erro fica, então o texto termina com um caractere diferente (também depois de Esc ou outra tecla), e o app não recebe mais erros. Settings → General lista esses apps abaixo da chave de erros; "Forget apps where typos couldn't be fixed" (esquecer os apps onde os erros não puderam ser corrigidos) deixa que tentem de novo.

### Ajustes por app (novo)

Settings → Apps dá a um app ajustes próprios, todos opcionais; o que um app não define segue os ajustes de todos os apps:

| Ajuste | Por exemplo | Na configuração |
| --- | --- | --- |
| O idioma de entrada com que os campos de texto dele começam | Slack em inglês, WeChat em pinyin | `inputLanguage` |
| Os estilos de reescrita que o `@improve` oferece ali | Mail formal e diplomático, Slack informal | `rewriteStyles` |
| Digitar os resultados, ou não | ativado em um app de chat, desativado no Mail | `typeOut` |
| Sem IA neste app | `@improve`, `@translate`, `@question`, `@agent` e os seus comandos de instrução não enviam nada ali e avisam; digitar e os outros comandos funcionam | `noAI` |
| Sempre traduzir enquanto digita | o WeChat sempre com a tradução enquanto digita (veja [Traduzir enquanto digita](#traduzir-enquanto-digita)) | `translateAlways` |

"Add App…" (adicionar app) lista os apps em que você digitou recentemente, ou escolhe um em /Applications. O menu de entrada, em "This App: <nome>", tem chaves rápidas para o app em que você está digitando (No AI, Type Results Out, o idioma inicial). Na configuração, eles ficam em `appProfiles`, por bundle ID: `"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["casual"], "noAI": false}}`. Os bundle IDs são comparados sem diferenciar maiúsculas (`com.apple.Mail` é o `com.apple.mail` do Mail). O `@reportissue` conta os apps que definem algo, sem nunca nomeá-los.

- O idioma inicial funciona como o idioma de entrada padrão: um campo de texto o adota quando fica ativo, e uma troca com Shift depois permanece para os campos daquele app até o ajuste mudar.
- Com No AI, os comandos de IA continuam na lista @; executar um mostra o aviso e mantém o que você escreveu. Os seus próprios comandos de terminal (`"type": "terminal"`) executam programas, não a IA, então continuam funcionando ali.

### Settings → Assistant (novo)

Os ajustes abrem em **Assistant**, uma página com duas seções (antes da 0.6.5, eram os comandos `@config` e `@doctor`).

**Mudar ajustes com uma frase** ("Change settings in a sentence"): escreva o que você quer ("translate into Japanese and English", "candidates in a column", "use Claude") e clique em Preview (ou ⌘⏎). Cada mudança aparece como antes → depois; Apply as aplica, e Undo as desfaz em até 10 minutos. Ele também ativa ou desativa a sincronização pelo iCloud (o que é sincronizado só se escolhe nos ajustes). Chaves de API, comandos próprios, plugins e tudo o que executa programas nunca são alterados ali; um provedor sem chave abre o campo da chave em Settings → AI Provider, e o Test Connection roda depois de uma troca de provedor. Funciona no Apple Intelligence se este Mac o tiver; senão, no seu provedor.

**Verificar problemas** ("Check for problems"): o método de entrada, o provedor de IA, as permissões, a entrada segura, os pacotes de idioma, o `config.json`, as extensões, as atualizações, a sincronização pelo iCloud (ativada ou não, quando sincronizou pela última vez, o último erro, iCloud Drive indisponível, ajustes do iCloud não usados aqui) e os erros recentes são verificados neste Mac quando a página abre, primeiro os problemas (tudo certo: "Everything looks good"). Check verifica de novo, com o Test Connection; com uma pergunta em "What's wrong? (optional)", a IA explica a causa provável. Uma linha que pode ser corrigida tem um botão Fix: as mudanças de ajustes aparecem na prévia acima, com Apply e Undo; as outras agem na hora.

### Sincronizar pelo iCloud (novo)

Settings → General → **Sync through iCloud** (sincronizar pelo iCloud; desativado por padrão) mantém iguais em todos os seus Macs os seus ajustes, a lista de jargão, os comandos personalizados e as palavras que o pinyin aprendeu, pelo seu próprio iCloud Drive: sem outro login, nada passando pelos nossos servidores. Requer o iCloud Drive (Ajustes do Sistema → Conta Apple → iCloud); sem ele, o interruptor fica desativado e avisa, com um botão que abre esse painel.

| Interruptor | O que sincroniza | Padrão |
| --- | --- | --- |
| Settings (ajustes) | os ajustes do `config.json`: idiomas, estilos de reescrita, a tecla de ação, digitar os resultados, os ajustes por app, ocultar informações sensíveis (só os interruptores), o provedor e o modelo de IA (nunca uma chave) … | ativado |
| Jargon and custom commands (jargão e comandos personalizados) | a sua lista de jargão e os `customCommands` | ativado |
| Learned words (palavras aprendidas) | o que o pinyin aprendeu com as suas escolhas (o dicionário de usuário do Rime, pela sincronização de dicionários de usuário do librime; os seus próprios arquivos do Rime, como frases personalizadas, ficam no Mac) | ativado |
| Hidden words (palavras ocultas) | as palavras que você esconde da IA ("iCloud Drive is end-to-end encrypted only with Advanced Data Protection": o iCloud Drive só tem criptografia de ponta a ponta com a Proteção Avançada de Dados) | desativado |
| Recent questions (perguntas recentes) | as perguntas recentes do `@question` e as respostas (enquanto "Remember recent questions" estiver ativado) | desativado |
| API keys and passwords (chaves de API e senhas) | as suas chaves de API e as senhas das extensões, pelas Chaves do iCloud, que sempre têm criptografia de ponta a ponta (requer Senhas e Chaves ativado em Ajustes do Sistema → Conta Apple → iCloud) | desativado |

`iCloud Drive/AllInOneIME/settings.json` guarda cada ajuste com quando ele mudou e em qual Mac (um id aleatório), e, ajuste por ajuste, vale a mudança mais recente: uma lista (os seus comandos personalizados, os estilos de reescrita) é um valor só, os ajustes por app vão app por app, e remover os ajustes de um app também é uma mudança. Ele sincroniza quando o método de entrada inicia, cerca de 5 s depois de você mudar algo, quando o iCloud traz uma mudança de outro Mac (e a cada 5 minutos) e em **Sync Now** (sincronizar agora); as palavras aprendidas, quando o método de entrada inicia, a cada 30 minutos (depois de uma pausa na digitação) e em Sync Now. A linha de status diz "Last synced 2 min ago" (última sincronização há 2 min), "Waiting for iCloud…" (aguardando o iCloud…) ou o erro.

- Ao ativar a sincronização, um Mac adota os ajustes que já estão no iCloud; os dele só preenchem o que ainda não está lá. Já as coleções dele são mescladas: as perguntas recentes (as duas listas, as mais recentes primeiro, cada pergunta uma vez), as palavras ocultas, os comandos personalizados (pelo nome; em um conflito, vale o do iCloud) e as linhas da lista de jargão. O mesmo vale quando um interruptor abaixo dele é ativado pela primeira vez. O que você tirar depois em outro Mac (um comando personalizado ou uma palavra oculta apagada) continua fora. Isso volta uma vez (e apagar de novo é definitivo) quando veio do primeiro Mac que ativou a sincronização e esse Mac estava em repouso enquanto outro Mac mesclava a lista dele, quando foi apagado em um Mac ainda na 0.6.4, ou quando um Mac ainda na 0.6.4 o traz de volta. Um ajuste salvo nos ajustes enquanto um Mac está ativando a sincronização é mantido e vai para os outros Macs.
- Reativada depois de ter ficado desativada: o que o iCloud mudou nesse meio-tempo entra (mesmo onde este Mac também mudou), o que só este Mac mudou sobe, e uma coleção à qual ele acrescentou algo nesse meio-tempo é mesclada, nunca descartada.
- As perguntas recentes de dois Macs são mescladas; "Clear" (limpar) em um Mac também limpa nos outros todas as perguntas feitas antes dele. Desativar "Remember recent questions" as apaga só naquele Mac, e, quando ele é reativado, as perguntas dos outros Macs voltam para ele. Um Clear feito enquanto um Mac não sincroniza as perguntas recentes (ou não as guarda) vale só para esse Mac.
- Desativar Hidden words ou Recent questions deixa no iCloud o que já foi sincronizado: **Remove from iCloud…** (remover do iCloud), abaixo de cada interruptor (com confirmação), os tira de lá; os outros Macs mantêm os seus, e um que ainda os sincronize põe os dele de volta.
- Um valor de outro Mac que este não pode usar (um provedor sem chave aqui, um perfil da AWS que ele não tem, um valor fora do intervalo) não é aplicado: a linha de status e o Check for problems do Settings → Assistant dizem qual.
- Um arquivo que o iCloud ainda não baixou é aguardado, nunca tratado como vazio; um `settings.json` que não pode ser lido é posto de lado como `settings (unreadable …).json`, nunca sobrescrito. Ajustes de uma versão mais nova são mantidos como estão.
- As chaves de API e as senhas vão pelas Chaves do iCloud, não pelo iCloud Drive: com "API keys and passwords" ativado (e a sincronização ativada), uma chave salva ou substituída em um Mac aparece nos outros. Fica desativado por padrão: ativar só a sincronização não move nenhuma chave, e nada é movido até você ativar essa linha. Ativá-la move as chaves deste Mac das chaves de login para as Chaves do iCloud (e o macOS deixa de pedir a sua senha de login para elas depois de uma atualização); desativá-la as copia de volta para as chaves de login e as deixa nas Chaves do iCloud para os seus outros Macs. As chaves que não são sincronizadas ficam nas chaves de login, como antes, e o login do AllInOneIME Cloud também, que nunca é sincronizado: cada Mac faz o próprio login. Quando dois Macs têm chaves diferentes, vale a salva por último (pela data em que foi salva, que cada cópia guarda). A outra não é apagada: fica nas chaves de login do Mac em que estava como uma cópia substituída (em "AllInOneIME replaced API key", com o nome terminando em "(replaced)"), que nunca é usada. Uma chave que vai para as Chaves do iCloud também guarda uma, caso a chave diferente de outro Mac chegue por cima dela. Há uma cópia substituída por chave em cada Mac: uma mais nova substitui a anterior. Remover uma chave enquanto ela é sincronizada a remove em todos os Macs que sincronizam chaves (a pergunta diz "all your Macs", todos os seus Macs), junto com a cópia substituída deste Mac; um Mac com "API keys and passwords" desativado, ou ainda na 0.6.4, mantém a própria cópia e a põe de volta se a sincronização de chaves for ativada nele depois (a pergunta também avisa). Em um Mac com essa linha desativada, Remove… remove a chave e a cópia substituída só daquele Mac (a pergunta diz "this Mac", este Mac), e a cópia nas Chaves do iCloud fica para os seus outros Macs. Uma chave que o macOS não deixou o AllInOneIME ler sem a sua senha de login na hora de movê-la fica nas chaves de login até o próximo uso: se o macOS então pedir e você permitir, ela volta a ser usada, mesmo que tenha sido removida em outro Mac. Cada chave continua indo só para o host para o qual foi salva. Enquanto as chaves são sincronizadas, o `allinoneime-cli` e as versões anteriores à 0.6.5 não as veem nas Chaves. Uma compilação sem o perfil de provisionamento (uma compilação de desenvolvimento) guarda as chaves nas chaves de login e não consegue sincronizá-las: a linha avisa.
- Nunca sincronizados: o login do AllInOneIME Cloud, as credenciais da AWS (em `~/.aws`), fontes de extensões (executam código: cada Mac decide), pastas de extensões e plugins (caminhos de cada Mac), os apps sem erros de digitação e os apps recentes, o estado das janelas e os próprios interruptores da sincronização (de cada Mac).
- Desativá-la interrompe a sincronização e deixa tudo como está, neste Mac e no iCloud; **Remove from iCloud…** (com confirmação) move a pasta para o Lixo e desativa a sincronização neste Mac.
- O Settings → Assistant ("sync through iCloud") a ativa ou desativa; as palavras ocultas e as perguntas recentes só se escolhem em Settings → General. Na configuração: `iCloudSync` (`enabled`, `settings`, `jargon`, `learnedWords`, `hiddenWords`, `recentQuestions`, `keys`).

## Painel da barra de menus

<img src="../en/panel-swipe.png" width="520" alt="O painel da barra de menus: vidro fosco, com notas, lembretes e tarefas do Claude em cartões; uma linha deslizada para a esquerda mostra o botão Remove">

Clique no ícone do AllInOneIME na barra de menus (a marca de ∞ com cursor, sem moldura; a que tem moldura é a fonte de entrada) e o painel se abre logo abaixo dele; um clique em outro lugar o fecha:

- "Notes" (notas): as notas salvas com `@note`, as 5 mais recentes; clique em uma para abri-la onde ela foi salva: no Notes, no Obsidian ou no app do próprio arquivo, ou na página do Notion. Um arquivo que não existe mais deixa de ser listado.
- "Reminders" (lembretes): os lembretes ainda não concluídos na lista AllInOneIME do Reminders (`@reminder` adiciona a essa lista), os de vencimento mais próximo primeiro, 8 visíveis; clique no círculo para marcar um como concluído, ou no título para abrir o Reminders.
- "Claude Tasks" (tarefas do Claude): como em `@tasks`, as tarefas do Claude em segundo plano (o que o `@agent` delega ao Claude Code), até 30, 5 visíveis por vez: role para ver mais, ou pesquise nos títulos e nas respostas pelo campo de busca; com o andamento e a primeira linha da última resposta; clique em uma para abri-la no Terminal e continuar.

Deslize uma linha (uma nota, um lembrete ou uma tarefa) para a esquerda com dois dedos para mostrar o botão "Remove" (remover), ou até o fim para removê-la de uma vez; com um mouse, clique nela com o botão direito. Remover só a tira do painel: a nota continua no Notes, o lembrete no Reminders (não concluído), a tarefa no Claude Code.

O cabeçalho mostra as contagens (como "2 reminders · 1 task running"; tarefas aguardando você são contadas à parte, como "1 waiting for you") e um botão de atualizar. Ele nunca tira o foco do app em que você está digitando: marcar um lembrete como concluído ou atualizar deixa esse app na frente; só o campo de busca das tarefas do Claude, depois de clicado, recebe o teclado. O ícone aparece por padrão; desative-o em "Menu Bar Panel" nos ajustes.

O que ele lê, e quando:

- Notas: a lista é o registro próprio do painel (mantido também enquanto ele está fechado), e o Notes nunca é aberto: só quando o Notes já está em execução, e o AllInOneIME já recebeu permissão para controlá-lo antes, o painel o consulta em busca de títulos editados e notas apagadas.
- Lembretes: a lista AllInOneIME é lida quando o painel se abre, a cada 60 segundos e quando os lembretes mudam. O painel nunca faz o macOS pedir acesso por conta própria: se o macOS ainda não perguntou a você, ele mostra "Allow Access to Reminders", e só esse botão faz a pergunta; se você disse não, ele mostra "Open System Settings".
- Tarefas do Claude: o painel executa `claude agents` só enquanto está aberto: uma vez quando se abre, ao clicar em atualizar e quando `@agent` delega uma tarefa; e a cada 15 segundos enquanto alguma tarefa não terminou, não mais depois que todas terminam. As últimas respostas são lidas do final das transcrições do Claude Code neste Mac (`~/.claude/projects`), e só quando uma transcrição mudou.
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
- **Disposição dos candidatos**: para escolher palavras, os candidatos de pinyin e de hindi ficam lado a lado por padrão (Horizontal), como nos métodos de entrada do próprio sistema: ← → escolhem e ↑↓ (ou - =) mudam de página. Escolha Vertical na página "Input", abaixo dos idiomas de entrada, para um embaixo do outro (↑↓ escolhem). A lista de comandos @ e os resultados são sempre verticais.
- **Fuzzy pinyin** (pinyin aproximado, com a entrada em chinês): sons que você não distingue podem ser digitados de qualquer forma, por exemplo z ↔ zh, n ↔ l, in ↔ ing. Na página "Input", escolha "Chinese (pinyin)" na barra de idiomas de entrada, ative "Fuzzy pinyin" e escolha os pares; os dicionários são implantados de novo em um ou dois segundos. Ele grava `rime_ice.custom.yaml` na pasta de usuário do Rime, e nunca por cima de um arquivo seu ali.
- **Personal Dictionaries** (dicionários pessoais, na entrada em chinês): Settings → Input → Chinese (pinyin) → Personal Dictionaries → **Import or Update…** adiciona um vocabulário do Rime em UTF-8 (`.dict.yaml`) ao lado do rime-ice (o pacote de idioma chinês precisa estar instalado). A lista mostra o `name` do Rime, o nome do arquivo e o número de entradas de cada um; importar de novo o mesmo `name` substitui a cópia salva (editar só o arquivo original não a atualiza). Cada importação, atualização ou remoção recompila o dicionário de pinyin (todas as palavras do rime-ice mais as suas), o que pode levar cerca de um minuto; enquanto isso a digitação em chinês fica pausada, e a página mostra o progresso ou um erro. As cópias ficam neste Mac, fora da sincronização com o iCloud e das solicitações à IA; mas uma palavra que você escolhe delas é aprendida como qualquer outra, no dicionário de usuário do Rime, que sincroniza com as palavras aprendidas quando isso está ativado e continua lá depois que o dicionário é removido. Se você tem seu próprio `rime_ice.custom.yaml`, a importação é recusada antes de qualquer arquivo mudar.
- **Translate (@translate)**: adicione os idiomas para os quais traduzir (espanhol, francês, alemão, japonês, coreano, chinês, híndi, bengali, tâmil e os outros principais idiomas indianos…) e arraste-os para ordená-los. Híndi digitado em letras latinas ("aap kaise ho") volta em devanágari. `@translate` escreve uma linha em cada um, nessa ordem (três versões se houver só um); o próprio idioma da frase é pulado. Uma instalação nova traduz para o primeiro idioma das preferências de idioma do seu Mac que não seja inglês; só com inglês, `@translate` avisa que ainda não há idioma para tradução, e ⏎ nesse aviso abre esta página com "Add…" (adicionar…) contornado (a frase entra como você digitou). O Traduzir enquanto digita também não liga nesse caso, e diz onde adicionar um.
- **Keyboard layouts** (layouts de teclado): o francês digita com o layout escolhido no cartão dele (`keyboardLayouts` na configuração). Para os outros idiomas, sob o método de entrada o macOS mantém o seu último layout latino (AZERTY, QWERTZ, espanhol, US International…), então você digita como sempre, `@` incluído, onde quer que o seu layout o tenha, e as teclas mortas também compõem no texto de um comando (⌥E e depois E → é, ^ e depois e → ê). Layouts sem letras latinas (russo, híndi InScript) não podem ser usados sob um método de entrada: alterne para eles com ⌃Space, ou cole (⌃V) ou dite texto em um comando.
- `@improve` refina e reescreve sem traduzir; `@translate @improve` juntos traduzem e reescrevem em uma única solicitação. Ative "@improve also translates" nos ajustes para que o `@improve` sempre faça isso.

Um dicionário pessoal fica assim (os campos de cada entrada são separados por **tabulações**):

```yaml
---
name: my_vocabulary
version: "1"
columns: [text, code, weight]
...
星河项目	xing he xiang mu	100
蓝杉团队	lan shan tuan dui	200
```

Escreva o pinyin em letras latinas minúsculas, com espaços entre as sílabas e `v` para `ü`; o peso é opcional (um número não negativo). Sem `columns`, a ordem é `text`, `code`, `weight`. `name` pode conter letras latinas, dígitos, `-`, `_` e `.`; um arquivo pode ter no máximo 32 MiB. Arquivos que dependem de `import_tables` ou não têm códigos pinyin são recusados sem mudar nada.

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

## Traduzir enquanto digita

Um protótipo, para experimentar. Mantenha Shift pressionado sozinho por 1 segundo para ativar (ou desativar) o Translate as You Type (traduzir enquanto digita); um toque rápido em Shift continua trocando o idioma de entrada. Aos 0,5 s, uma dica perto do cursor diz "Keep holding → Translate as You Type" (continue segurando → traduzir enquanto digita), e a 1 s "Translate as You Type on: Chinese → English · hold Shift again to turn off" (ativado: chinês → inglês · segure Shift de novo para desativar; com o idioma para o qual ele traduz) confirma por cerca de 1,5 s (ao desativar: "Keep holding → Translate as You Type off" e depois "Translate as You Type off"); solte antes disso e nada muda. Shift com uma letra (uma maiúscula) ou com outra tecla nunca o ativa. Enquanto ele está ativado, o ícone da barra de menus leva um pontinho. Não há comando para ele.

Enquanto ele está ativado, o que você digita vai se juntando em um rascunho, com os idiomas na etiqueta ao lado ("ZH → EN"; 「中 → 英」 na interface em chinês). Ele traduz para o idioma que você escolheu por último na etiqueta (veja abaixo), em todos os apps e mesmo depois de reiniciar; até você escolher um, para o seu primeiro idioma de tradução nos ajustes (e de volta para ele quando o idioma escolhido não estiver mais entre eles). Se você digita em um só idioma, ele é pulado: digitando só em inglês, com inglês e depois francês como idiomas de tradução, é o francês. O idioma em que você está digitando quando ele é ativado não muda isso. ⏎ traduz o rascunho e a tradução entra na hora, sem candidatos para escolher: enquanto isso, o rascunho diz "Translating…" (traduzindo…), e nada é enviado (um novo ⏎ já vai para o app). ⇧⏎ insere o rascunho como foi digitado; Esc durante a tradução a interrompe e mantém o rascunho (⌫ também a interrompe, e apaga um caractere como no rascunho); se ela falhar (a rede, uma recusa, a entrada segura), o rascunho fica, com um aviso de uma linha, e ⏎ tenta de novo. Um texto digitado no idioma para o qual ele traduz (toque em Shift para ir ao inglês) entra como foi digitado.

Enquanto ele está ativado, uma pequena etiqueta "ZH → EN" (「中 → 英」 na interface em chinês) aparece abaixo da linha em que você digita, no próprio painel do método de entrada (o painel de candidatos: acima dos candidatos enquanto você digita pinyin), então ela nunca tira o foco do app. Clique em "ZH" para trocar o idioma de entrada, como um toque em Shift. Clique em "EN" para ver uma pequena lista dos seus idiomas de tradução, com o atual marcado, e clique em um: ele passa a ser o idioma de destino na hora (a etiqueta e a próxima tradução acompanham) e daí em diante. As teclas funcionam como antes; qualquer uma fecha a lista.

- **Tom**: segue o app: o primeiro estilo de reescrita do app em Settings → Apps; senão, informal em apps de chat (WeChat, Slack, Messages, Telegram, Discord, Teams), formal em apps de e-mail (Mail, Outlook, Spark) e natural no resto.
- **Apps**: trocar para outro app (mesmo um sem campo de texto) o desativa, sem aviso, e voltar o deixa desativado, a menos que esse app tenha "Always Translate as You Type" (sempre traduzir enquanto digita; 「总是边打边译」) em Settings → Apps (`translateAlways` no perfil dele): ali ele se ativa sozinho. Em um app com No AI ele não faz nada: o texto entra como digitado, com um aviso; o mesmo vale para o que você digita durante a entrada segura (um campo de senha).
- **Privacidade**: como no `@translate`: o texto só é enviado quando você pressiona ⏎, ao seu próprio provedor de IA, com as informações sensíveis ocultadas quando isso está ativado.

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
3. O instalador é assinado com um Developer ID e notarizado pela Apple, então na primeira vez o macOS só pergunta se deve abrir um app baixado da internet: clique em Abrir. (As versões anteriores à 0.6.3 não eram notarizadas: cada uma precisava ser permitida uma vez em Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim.)

Depois disso, o AllInOneIME fica ativado e nas suas fontes de entrada; alterne para ele com Ctrl+Espaço (a tecla 🌐 só alterna se "Press 🌐 key to" estiver definido como "Change Input Source" em "System Settings → Keyboard"). Se o instalador disser para adicioná-lo manualmente, é porque este Mac não permite que programas o ativem; então adicione-o você mesmo, uma vez: "System Settings → Keyboard → Text Input → Input Sources → Edit… → + (canto inferior esquerdo) → English → AllInOneIME" (Ajustes do Sistema → Teclado → Entrada de Texto → Fontes de Entrada → Editar… → + → Inglês → AllInOneIME) (ele também digita pinyin depois que você adiciona o chinês em "Input" nos ajustes dele).

Se Ctrl+Espaço não leva você ao AllInOneIME, ou ele volta para U.S. depois de um tempo, execute o instalador de novo: ele adiciona o AllInOneIME de volta às suas fontes de entrada.

Atualizar: Settings → About → Check for Updates (verificar atualizações). Quando há uma versão nova, o About avisa (e uma linha no painel da barra de menus), com as novidades; "Update to <version>" (atualizar para <versão>) a baixa, confere com as informações de atualização assinadas com a chave de publicação do AllInOneIME, instala e reinicia o método de entrada. Os seus ajustes, pacotes de idioma, palavras aprendidas e extensões ficam, e se algo der errado a versão que você tinha é restaurada. O AllInOneIME verifica sozinho uma vez por dia, em segundo plano (desative com "Check for updates automatically" no About); nada é instalado até você clicar. Isso funciona a partir da 0.6.3; para atualizar uma versão mais antiga, ou se preferir, instale a imagem de disco da nova versão por cima, sem desinstalar antes. Antes de atualizar, leia o [registro de alterações](../../CHANGELOG.md): ele tem as mudanças de cada versão e as notas de atualização.

Atualizar para a 0.6.3 a partir de uma versão anterior: a 0.6.3 é a primeira versão assinada com um Developer ID, então as Chaves ainda não a reconhecem como o app que guardou as suas chaves. Na primeira vez que precisa de cada chave que guardou (uma chave de API, o login do AllInOneIME Cloud, a senha de uma extensão), o macOS pede a sua senha de login: digite-a e clique em "Always Allow" (Sempre Permitir). Ele não pede de novo, nem depois de atualizações futuras. As chaves do Amazon Bedrock ficam em `~/.aws/credentials`, que não é afetado. A Acessibilidade (Ajustes do Sistema → Privacidade e Segurança → Acessibilidade), que colar em terminais e ler a seleção usam, também precisa de um passo: se o AllInOneIME estiver na lista, remova-o e ative-o de novo quando for pedido.

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

As traduções e reescritas vão para o provedor de IA escolhido em Settings → AI Provider. Uma instalação nova começa no AllInOneIME Cloud: faça login e você tem 20 solicitações gratuitas por dia. Em um Mac com Apple Intelligence, tudo pode rodar neste Mac em vez disso, sem conta (veja "Apple Intelligence neste Mac" abaixo). Ou use o seu próprio provedor, com os custos na sua conta: Amazon Bedrock na sua conta AWS, a Claude API, o Gemini ou um serviço compatível com OpenAI (veja "Outros provedores de IA" abaixo).

### Amazon Bedrock

1. Ative o Bedrock no console da AWS e confirme que você pode usar o modelo escolhido. O padrão é o Claude Haiku 4.5; na primeira vez que você usa um modelo da Anthropic, preenche uma única vez um formulário de caso de uso.
2. Use um perfil da AWS com permissão para `bedrock:InvokeModelWithResponseStream`: chaves estáticas em `~/.aws/credentials`, ou um perfil que obtém credenciais temporárias (`credential_process`, uma função (role), SSO; veja "Perfis da AWS" abaixo).
3. Abra o "AllInOneIME Settings": você o encontra no Spotlight ou em Aplicativos, ou pode abri-lo pelo ícone do método de entrada na barra de menus → "Settings…". Escolha o perfil, a região e o modelo, e clique em "Test Connection" (testar conexão). A interface vem em English, 简体中文 (chinês simplificado), 繁體中文 (chinês tradicional), 日本語, 한국어, Deutsch, Français, Español e Português (Brasil). Por padrão ("Follow the system", seguir o sistema, em Settings → General → "Interface language") ela segue os idiomas preferidos do sistema (Ajustes do Sistema → Geral → Idioma e Região): o primeiro deles que o app tiver; uma variante regional fica com o idioma dela (Deutsch para de-AT, Español para es-MX, Français para fr-CA); chinês tradicional para zh-Hant, zh-TW e zh-HK, e simplificado para os outros chineses; português do Brasil também para o de Portugal (lá ele se lê melhor que o inglês); inglês quando não houver nenhum. Ou escolha um deles ali, cada um listado no próprio idioma. A janela de ajustes, as dicas no painel de candidatos e o menu de entrada seguem essa escolha. Os ajustes abrem na página Assistant: mudar ajustes descrevendo-os e verificar problemas, com um Fix para cada um (veja [Settings → Assistant](#settings--assistant-novo)).

<img src="../en/settings.png" width="420" alt="A janela de ajustes">

#### Perfis da AWS

Funciona qualquer perfil que a AWS CLI consiga usar sem perguntar nada a você, de `~/.aws/config` e `~/.aws/credentials` (ou dos arquivos que `AWS_CONFIG_FILE` e `AWS_SHARED_CREDENTIALS_FILE` indicam no seu shell). Dentro de um perfil, é usada a primeira destas fontes que ele tiver, na ordem da AWS CLI (um perfil com `role_arn` e chaves ao mesmo tempo é uma função):

| Tipo | No perfil | Renovação |
| --- | --- | --- |
| Função | `role_arn` com `source_profile` (de qualquer tipo, inclusive em cadeia; um perfil que aponta para si mesmo usa as próprias chaves) ou `credential_source = Environment`; `role_session_name`, `external_id`, `duration_seconds` | de novo pelo STS `AssumeRole` (na `region` do perfil, senão us-east-1) 5 minutos antes de expirarem |
| SSO | `sso_account_id`, `sso_role_name` com `sso_session` e a seção `[sso-session …]` dela (ou os antigos `sso_start_url`, `sso_region`) | buscadas de novo com o seu login em cache 5 minutos antes de expirarem |
| Chaves estáticas | `aws_access_key_id`, `aws_secret_access_key` (e `aws_session_token`) em `~/.aws/credentials` | lidas de novo a cada solicitação |
| `credential_process` | `credential_process = /usr/local/bin/my-creds --profile dev` (dividido como um comando de shell, executado sem shell, com o PATH do seu shell de login, na sua pasta pessoal, no máximo 60 s) | executado de novo 5 minutos antes do seu `Expiration`; sem ele, quando a AWS recusa as credenciais |
| Chaves estáticas | as mesmas chaves em `~/.aws/config` | lidas de novo a cada solicitação |

Com o perfil "default" (ou nenhum escolhido), as chaves do seu shell vêm primeiro, como a AWS CLI as usa: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN`. Um perfil que você nomeia nunca é misturado com elas. `AWS_REGION` (ou `AWS_DEFAULT_REGION`) no seu shell tem prioridade sobre a `region` de um perfil, como na AWS CLI; o campo Region dos ajustes tem prioridade sobre os dois.

- **Automático:** credenciais que expiram ficam na memória (nunca são gravadas no disco) e são buscadas de novo 5 minutos antes de expirarem; com menos de 10 minutos restantes, uma solicitação as usa e busca novas em segundo plano, para que a digitação não espere. Solicitações simultâneas esperam por uma única busca. Quando o Bedrock responde que as credenciais expiraram (`ExpiredTokenException` …), elas são buscadas de novo e a solicitação é reenviada, uma única vez.
- **SSO:** o AllInOneIME usa o login que a AWS CLI guarda em `~/.aws/sso/cache` (só o lê) e não consegue fazer login por você, porque isso exige um navegador. Quando o login termina, o painel de candidatos diz "SSO sign-in expired: run aws sso login --profile X" (o login do SSO expirou: execute aws sso login --profile X): execute isso no Terminal (os ajustes têm Copy Command e Open in Terminal; o Settings → Assistant oferece o comando para copiar), e o AllInOneIME passa a usar o novo login sozinho.
- **Não suportado:** `mfa_serial` (um método de entrada não pode pedir um código MFA: use `credential_process` ou SSO, ou deixe a sua CLI guardar as credenciais em cache), `credential_source = Ec2InstanceMetadata` ou `EcsContainer` (não existem em um Mac) e web identity.
- **Limitações conhecidas:** só o PATH e as variáveis dos arquivos da AWS (`AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`) vêm do seu shell de login, também para o `credential_process` (não o resto do ambiente). O AllInOneIME não renova tokens de `sso_session` (o token de atualização da CLI não é usado: o cache do SSO é só lido), então, quando o token em cache expirar, execute `aws sso login` (a AWS CLI também o renova sempre que você a usa).
- **Settings → AI Provider** lista cada perfil com o tipo dele ("dev — Role via base") e diz, do escolhido, quando as credenciais expiram ("Role via base: credentials expire at 15:30", "SSO (signed in until 18:00)") ou o que fazer. O Test Connection busca credenciais novas por toda a cadeia; o Settings → Assistant informa o mesmo.
- Programas só rodam e a AWS só é consultada para credenciais (`sts.<region>.amazonaws.com`, `portal.sso.<region>.amazonaws.com`) quando uma solicitação ou o Test Connection precisa delas: nunca para listar perfis, nunca para o Settings → Assistant.

### Outros provedores de IA: Claude API, Gemini, serviços compatíveis com OpenAI

Você não precisa da AWS: escolha um provedor em "AI Provider" nos ajustes, cole uma chave de API, clique em "Save" e depois em "Test Connection".

| Provedor | Modelo padrão | Chave de API |
|---|---|---|
| Claude API | `claude-haiku-5-5` (o mais rápido e barato; Sonnet 5.5 e Opus 5.5 são mais cuidadosos, mas mais lentos e caros) | [Claude Console](https://platform.claude.com) |
| Gemini API | `gemini-3.8-flash` | Google AI Studio |
| Compatível com OpenAI | O `gpt-6-luna` da OpenAI (ou `gpt-5.4-mini`); "Common Services…" (serviços comuns) tem DeepSeek, Qwen, Kimi, Zhipu GLM, SiliconFlow, OpenRouter e Ollama neste Mac: escolher um preenche a URL base dele, e depois você informa o modelo | A chave do serviço; defina a "Base URL" como o endereço dele, por exemplo `https://api.deepseek.com/v1`, ou `http://localhost:11434/v1` para o Ollama neste Mac |

- As chaves de API ficam nas chaves de login, nunca no arquivo de configuração; se você ativar "API keys and passwords" em Sync through iCloud, ficam nas Chaves do iCloud, onde o `allinoneime-cli` e as versões anteriores à 0.6.5 não as veem. Se não houver nenhuma lá, são usadas as variáveis `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (ou `GOOGLE_API_KEY`) e `OPENAI_API_KEY` do seu shell.
- A linha da chave de API diz se há uma chave definida: "✓ Saved · ends in a1b2" (salva · termina em a1b2: os últimos 4 caracteres, guardados junto com ela para que a chave em si não seja lida para mostrá-los) com Replace… (substituir) e Remove… (remover), "✓ From $OPENAI_API_KEY" (de $OPENAI_API_KEY) para uma do seu shell, ou "No API key yet" (ainda sem chave de API) com o campo para colá-la.
- "Thinking" (raciocínio) fica baixo por padrão: o método de entrada espera a cada frase, e menos raciocínio é mais rápido. Escolha "Not set" (não definido) para modelos que não o aceitam.
- Com o Claude Opus 5.5 ou o Sonnet 5.5 escolhido, as solicitações levam o fallback de recusa da Claude API (`fallbacks: "default"`): quando um classificador de segurança recusa, o servidor tenta de novo com outro modelo.
- No arquivo de configuração: `provider` (`"bedrock"`, `"anthropic"`, `"gemini"`, `"openai"`), e `model`, `baseURL`, `effort` e `temperature` dentro de `anthropic`, `gemini` e `openai` (os que não estiverem definidos usam os padrões).

### Apple Intelligence neste Mac (macOS 26)

Em um Mac com Apple Intelligence (Apple Silicon, macOS 26 ou posterior, ativado em Ajustes do Sistema → Apple Intelligence e Siri), escolha "Apple Intelligence (on this Mac)" em "AI Provider": sem chave, sem custo, e nada do que você digita sai do Mac. Ele usa o modelo embutido no macOS (o framework Foundation Models), com as mesmas instruções e o mesmo formato de resposta dos outros provedores, mas só os exemplos escritos no próprio idioma da frase (um modelo pequeno copia o idioma de um exemplo com facilidade demais).

- É um modelo pequeno: o contexto dele é de cerca de 4K tokens (8K no macOS 27), então um parágrafo longo pode ser longo demais para ele, e ele fala menos idiomas (inglês, chinês, japonês, coreano, francês, alemão, espanhol e mais alguns; não hindi). Em ambos os casos, ele avisa. Os resultados ficam abaixo dos modelos na nuvem, e as respostas do `@question` sobre fatos e código muitas vezes estão erradas.
- Onde não pode ser usado, aparece esmaecido com o motivo (não compatível com este Mac, desativado, modelo não pronto), e os ajustes levam a Ajustes do Sistema → Apple Intelligence e Siri. Antes do macOS 26, não aparece.
- "Output tokens", a temperatura e o tempo limite em "Model Settings" valem para ele. No arquivo de configuração: `"provider": "apple"`.

### Ocultar informações sensíveis (novo)

Settings → AI Provider → Privacy → "Hide sensitive information before sending" (ocultar informações sensíveis antes de enviar; desativado por padrão): antes de uma solicitação ir para a IA, o que ele encontra no seu texto é substituído no Mac por marcadores como `[EMAIL_1]` (o mesmo valor, o mesmo marcador), e os resultados recebem os valores reais de volta antes de serem mostrados ou inseridos. O painel diz "2 items hidden from the AI" (2 itens ocultos da IA). Cada tipo pode ser desativado:

| Tipo | Por exemplo | Na configuração |
| --- | --- | --- |
| Endereços de e-mail | `bob@example.com` | `emails` |
| Números de telefone | `+1 (555) 123-4567`, `138 0013 8000` | `phones` |
| Números de cartão de pagamento (verificados por Luhn) | `4111 1111 1111 1111` | `cards` |
| Chaves de API e tokens | prefixos conhecidos como `sk-` ou `ghp_`, sequências aleatórias longas | `keys` |
| Endereços IP | `203.0.113.42`, `2001:db8::1` | `ips` |
| Suas próprias palavras, sem diferenciar maiúsculas | um codinome como `Project Atlas`, um nome | `customWords` |

- Vale para `@improve`, `@translate`, `@question`, os seus comandos de instrução e plugins de instrução, e para o refinamento dos resultados deles (os mesmos marcadores), com todos os provedores, incluindo o AllInOneIME Cloud e o Apple Intelligence. Entradas da lista de jargão que contêm um valor a ocultar não são enviadas.
- Ele reconhece valores formatados; não consegue reconhecer nomes ou endereços, então adicione-os como suas próprias palavras. `@agent`, os plugins que buscam dados em um site (`@stock`) ou abrem um (`@x`) e as extensões de script enviam o texto como foi digitado. Mais em Privacidade.
- Na configuração: `"redaction": {"enabled": true, "customWords": ["Project Atlas"]}`.

Todos os ajustes ficam em `~/.config/allinoneime/config.json`; depois de uma alteração, a próxima tradução já usa os novos ajustes, sem reiniciar. As chaves mais novas:

| Chave | O que faz | Padrão |
|---|---|---|
| `inputLanguages` | Idiomas de entrada, de um a cinco; o primeiro é o padrão: `"en"` inglês, `"zh"` chinês (pinyin), `"fr"` francês, `"ko"` coreano, `"hi"` híndi, por exemplo `["en", "zh"]`, `["fr", "en", "ko"]`. Chinês, coreano e híndi funcionam depois que o pacote deles é instalado | `["en"]` (instalação nova) |
| `keyboardLayouts` | O layout de teclado com que um idioma de entrada digita, pelo código do idioma (por enquanto, só o francês): `{"fr": "com.apple.keylayout.French-PC"}` | Francês: `com.apple.keylayout.French` (AZERTY) |
| `outputLanguages` | Para quais idiomas o `@translate` traduz, em ordem: `["es", "fr", "de"]`, … | `["en"]` |
| `improveTranslates` | O `@improve` também traduz (como `@translate @improve`) | `false` |
| `voiceInput` | Manter a ⌥ direita pressionada para falar | `true` |
| `actionKey` | Tecla de ação: `"enter"` (⏎), `"optionTap"` (Tap ⌥), `"optionSpace"` (⌥Space), `"space"` (Space) | `"enter"` |
| `commandTrigger` | O símbolo que inicia os comandos: um de `"#"`, `"%"`, `"&"`, `"*"`, `"+"`, `"@"`, `"\|"`, `"~"`; qualquer outro valor vale `"@"` | `"@"` |
| `uiLanguage` | Idioma da interface (janela de ajustes, dicas do painel de candidatos, menu): `"zh"` (chinês simplificado), `"en"` ou o código de outro idioma que o app traz: `"zh-Hant"`, `"ja"`, `"ko"`, `"de"`, `"fr"`, `"es"`, `"pt-BR"` | `null` (segue o sistema) |
| `rewriteStyles` | Estilos de reescrita: `polish`, `concise`, `formal`, `casual`, `tactful`, `jargon`, por exemplo `["polish", "concise", "jargon"]` | Polish, Concise, Formal |
| `jargonFile` | O seu próprio arquivo de lista de jargão | `null` (ou seja, `~/.config/allinoneime/jargon.txt`) |
| `menuBarIcon` | O ícone da barra de menus e o painel suspenso dele | `true` |
| `candidateLayout` | Candidatos de pinyin e de hindi: `"vertical"` (um embaixo do outro) ou `"horizontal"` (lado a lado; ← → escolhem, ↑↓ mudam de página) | `"horizontal"` |
| `fuzzyPinyin` | Pares de pinyin aproximado: `["z-zh", "n-l", "in-ing"]` (z-zh, c-ch, s-sh, n-l, f-h, r-l, an-ang, en-eng, in-ing, ian-iang, uan-uang) | `[]` |
| `useSelection` | Os comandos @ trabalham sobre o texto selecionado no campo (veja No texto selecionado) | `true` |
| `checkForUpdates` | Procurar uma versão nova uma vez por dia, em segundo plano; nada é instalado até você clicar | `true` |
| `agent` | O agente de programação para o qual o `@agent` passa o texto (Settings → Agent): `claude` (Claude Code), `gemini` (Gemini CLI), `kiro` (Kiro CLI) ou `custom` | `claude` |
| `agentCommand` | O comando do agente personalizado, com o que você digitou adicionado como último argumento, por exemplo `["muse", "--"]` | `[]` |
| `agentPageContext` | O `@agent` no Google Chrome leva a página junto (o campo, o formulário ou a seção dele, a seleção, o texto visível; nunca uma senha) | `true` |
| `claudeInBackground` | O `@agent` com o Claude Code roda em segundo plano e avisa você (os outros agentes sempre abrem no Terminal) | `true` |
| `rememberQuestions` | Guardar as suas últimas 5 perguntas do `@question` e as respostas neste Mac, listadas sob `@question` (veja Perguntas recentes) | `true` |
| `questionRounds` | Rodadas de uma conversa do `@question` no painel antes de sugerir continuar em outro lugar, 2–10 | `5` |
| `questionContinueIn` | Onde uma conversa do `@question` pode continuar, em ordem, a primeira é a padrão: `agent` (aquele para o qual o `@agent` passa as tarefas, no lugar da entrada própria desse agente), `claudeCode`, `geminiCLI`, `kiroCLI`, `customAgent` (os agentes, cada um só se estiver instalado), `claudeWeb`, `chatgpt`, `gemini`, `copy` | `agent`, os outros agentes instalados, Claude, ChatGPT, copiar |
| `appProfiles` | Ajustes de um app, por bundle ID, todos opcionais: `inputLanguage`, `rewriteStyles`, `typeOut`, `noAI`, `translateAlways` (veja Ajustes por app) | `{}` |
| `notes` | Onde o `@note` salva (Settings → Plugins → Notes): `{"destination": "folder", "folder": "~/Vault/Inbox"}`, ou `"notion"` com a página ou o banco de dados que o Test encontrou; nunca é sincronizado pelo iCloud Drive (o token fica nas Chaves e só vai pelas Chaves do iCloud com "API keys and passwords" ativado) | `destination: "notes"` |
| `redaction` | Ocultar informações sensíveis da IA (veja Privacidade): `{"enabled": true, "phones": false, "customWords": ["Phoenix"]}`; cada detector (`emails`, `phones`, `cards`, `keys`, `ips`) fica ativo, a não ser que seja definido como `false` | `enabled: false` |

## Privacidade

- A digitação (inglês e pinyin) e os cálculos do plugin `@calculator` são inteiramente locais. Só quando você pressiona a tecla de ação em `@improve`, `@translate` ou `@question` essa frase é enviada ao provedor de IA que você escolheu (o seu próprio Bedrock, ou o serviço cuja chave você adicionou). Com "Jargon" marcado e uma lista de jargão definida, a lista é enviada junto. Refinar os resultados (uma instrução digitada depois deles, e então ⇧⏎) envia de novo a mesma solicitação com os resultados mostrados e a sua instrução; uma pergunta de acompanhamento (⇧⏎) envia junto a conversa até ali.
- O Settings → Assistant só envia texto a um modelo quando você clica em Preview, ou em Check com uma pergunta: ao Apple Intelligence neste Mac sempre que estiver disponível (nada sai do Mac); senão, ao seu provedor. Um pedido envia a sua frase (uma chave digitada nela é removida antes) com os valores atuais dos ajustes que ele pode mudar: nunca uma chave, nem as palavras que você esconde da IA (só quantas são), e os nomes dos seus perfis da AWS só quando a frase fala de AWS ou Bedrock. Uma pergunta é enviada com os resultados das verificações, mascarados: nenhum caminho além de `~`, nenhuma chave, linhas de log como frases fixas. Ocultar informações sensíveis vale para os dois. As verificações sozinhas não enviam nada; Check envia só a requisição do Test Connection, e só quando o provedor tem uma chave ou credenciais para testar.
- Continuar uma conversa do `@question` em outro lugar (⌘1 … depois da última rodada, ou ⌘⏎) a envia, com o que você digitou, ao serviço que você escolher: um agente de programação neste Mac (Claude Code, Gemini CLI, Kiro CLI ou o seu próprio, cada um com a própria conta e o próprio serviço), claude.ai, chatgpt.com ou gemini.google.com, no endereço web ou pela área de transferência. Ela vai como você a viu: os valores ocultados das solicitações à IA (veja abaixo) estão nela como são, já que é você quem escolhe enviá-la para lá. Nada vai a lugar nenhum até você escolher um; "Copy the conversation" só a coloca na área de transferência.
- Com o AllInOneIME Cloud, a frase passa pelo servidor do desenvolvedor até um provedor de modelos (atualmente pelo OpenRouter): o servidor guarda apenas contagens, nunca o texto. Fazer login guarda apenas o seu endereço de e-mail.
- Ocultar informações sensíveis (Settings → AI Provider → Privacy, desativado por padrão): antes de qualquer solicitação sair (`@improve`, `@translate`, `@question`, os seus comandos de instrução e plugins de instrução, com todos os provedores, incluindo o AllInOneIME Cloud), endereços de e-mail, números de telefone, números de cartão de pagamento (verificados por Luhn), chaves de API e tokens (`sk-`, `sk-ant-`, `AKIA…`, `ghp_`, `xox…` e sequências aleatórias longas), endereços IP e suas próprias palavras (um codinome, um nome) são substituídos no Mac por marcadores como `[EMAIL_1]`, `[PHONE_1]`, `[ITEM_1]`; o mesmo valor recebe o mesmo marcador. Os resultados do modelo recebem os valores reais de volta antes de serem mostrados ou inseridos, e o painel diz "2 items hidden from the AI". Um resultado cujo marcador o modelo alterou a ponto de não ser reconhecível é mostrado como foi escrito, marcado com "⚠ placeholder changed". Entradas da lista de jargão com um valor oculto não são enviadas. Cada tipo pode ser desativado. Formas de largura total (`zhang＠example.com`, `１３８…`) também são encontradas, e um valor ou expressão pode estar dividido por uma quebra de linha. Ele reconhece valores formatados, como e-mails, números e chaves; não consegue reconhecer nomes ou endereços (adicione-os como suas próprias palavras), nem letras parecidas de outros alfabetos. Vale para solicitações ao seu serviço de IA; `@agent` (com a página do Chrome que ele leva junto), os plugins que buscam dados em um site (`@stock`) ou abrem um (`@x`) e as extensões de script enviam o texto como foi digitado. Na configuração: `redaction` (`enabled`, `emails`, `phones`, `cards`, `keys`, `ips`, `customWords`).
- A voz só é gravada enquanto você mantém a ⌥ direita pressionada e é reconhecida no próprio Mac; o texto reconhecido só é enviado nos comandos acima, quando você pressiona a tecla de ação.
- O método de entrada lê o texto da área de transferência, uma vez, só quando você pressiona ⌃V ou ⌘V em um comando; conteúdo que gerenciadores de senhas marcam como oculto não é lido. O texto aparece primeiro no comando e, novamente, só é enviado quando você pressiona a tecla de ação. Versões recentes do macOS perguntam se o AllInOneIME pode ler a área de transferência: permita. Para não ser perguntado toda vez, defina a permissão de colar do AllInOneIME como sempre permitir em "System Settings → Privacy & Security".
- Em campos de senha, o macOS muda para o próprio teclado (U.S. ou ABC) e volta quando você sai deles. Sempre que o app em que você digita mantém a entrada segura, o AllInOneIME não compõe texto e não pode gravar: as teclas entram como digitadas. E enquanto o sistema está em entrada segura (campos de senha, a "Secure Keyboard Entry" do Terminal etc.), nada é enviado à IA.
- `@note` e `@reminder` não vão para a IA: o AllInOneIME entrega o texto apenas ao Notes e ao Reminders deste Mac, e também interpreta a hora do lembrete no próprio Mac (se esses apps o sincronizam com seus outros dispositivos depende das contas deles, como o iCloud). Por isso eles também funcionam durante a entrada segura. O `@note` para uma pasta grava um arquivo neste Mac (ele é sincronizado se a pasta for, como uma pasta do iCloud Drive ou do Obsidian Sync). O `@note` para o Notion envia a nota ao Notion (api.notion.com, com o token da sua integração, guardado nas Chaves), e só nesse momento: não durante a entrada segura.
- O `@reportissue` (e "Report an Issue…") não envia nada por conta própria: ele abre no navegador a página de nova issue do GitHub com o título que você digitou e as versões, idiomas, tipo de provedor e contagens listados acima, mostrados primeiro no painel de candidatos. Nada chega ao GitHub a menos que você clique em Submit lá.
- `@open` pesquisa apenas neste Mac. Ele lembra o que você abriu com ele (os últimos 200), nas preferências do próprio método de entrada (não no config.json), para listar esses itens primeiro.
- Para o "Add App…" em Settings → Apps, o método de entrada guarda os bundle IDs dos últimos 12 apps em que você digitou, nas suas próprias preferências; nada mais sobre eles.
- O `@question` lembra as suas últimas 5 perguntas com as respostas e quando foram feitas, só neste Mac (a menos que você escolha sincronizá-las pelo iCloud, veja acima), em `~/Library/Application Support/AllInOneIME/recent-questions.json` (legível só pela sua conta de usuário), para listá-las sob `@question`; uma resposta salva é mostrada dali sem ir à internet. Nada é guardado durante a entrada segura, e perguntas feitas sobre texto selecionado não são guardadas de jeito nenhum (a resposta delas é sobre a seleção, que acabaria no disco). Desativar "Remember recent questions" em Settings → General também as apaga; desativá-lo pelo Settings → Assistant (`rememberQuestions` na configuração) as mantém, para que possa ser desfeito com exatidão. "Clear" as apaga.
- Para listar as suas notas, o painel da barra de menus guarda o id (o da nota no Notes, o caminho do arquivo ou o endereço da página do Notion) e a primeira linha (até 80 caracteres) das últimas 30 notas salvas com `@note`, nas preferências do próprio método de entrada, também enquanto o painel está desativado. Abrir o painel nunca consulta o Notion.
- `@py` e `@js` só rodam quando você pressiona a tecla de ação, e apenas com código que você mesmo digitou ou colou: as respostas da IA e a saída de outros comandos nunca são executadas como código. `@py` usa o `python3` do seu Mac, que pode ler e gravar arquivos e acessar a internet como faz no Terminal; `@js` roda em um processo separado que não pode ler arquivos, acessar a rede nem executar outros programas. Nenhum dos dois roda durante a entrada segura.
- Verificação de atualizações: uma vez por dia (a menos que "Check for updates automatically" esteja desativado), o AllInOneIME baixa https://allinoneime.com/update.json e a assinatura dele; a solicitação não leva identificadores nem nada do que você digitou. Uma atualização só é baixada, da release do GitHub, quando você clica em Update.
- Fontes de extensões: o git roda no seu Mac, como você, só para as fontes que você adicionou: uma busca (fetch) por dia para as que se verificam sozinhas (nenhuma para uma fonte fixada), e quando você clica em Check Now, Update ou Re-clone. Ele só se comunica com o servidor do repositório, autenticado pela sua própria configuração de git e SSH; nada do que você digita vai junto.
- Sincronizar pelo iCloud (desativado por padrão): só para o seu próprio iCloud Drive, `~/Library/Mobile Documents/com~apple~CloudDocs/AllInOneIME/`, que a Apple sincroniza com os seus outros Macs; nada vai para os servidores do desenvolvedor. O que vai para lá: `settings.json` (os ajustes sincronizados, cada um com quando mudou e um id aleatório por Mac; os seus comandos personalizados, também os que executam um programa, que continuam só rodando quando você os escolhe), `jargon.txt` (a sua lista de jargão), `rime/` (a cópia de cada Mac do que o pinyin aprendeu, nada mais da pasta do Rime: as suas frases personalizadas e os ajustes do Rime ficam no Mac) e, só se você os ativar, as palavras que você esconde da IA (no `settings.json`) e `questions.json` (perguntas recentes e respostas, legível só pela sua conta de usuário). Desativar esses dois os deixa no iCloud até você removê-los ("Remove from iCloud…" abaixo de cada interruptor). Nunca: chaves de API, tokens ou senhas, fontes de extensões, pastas de extensões e plugins, os apps sem erros de digitação, os apps recentes, o estado das janelas, os interruptores da sincronização. O iCloud Drive só tem criptografia de ponta a ponta com a Proteção Avançada de Dados. O registro do próprio Mac do que ele sincronizou fica em `~/Library/Application Support/AllInOneIME/iCloudSync/state.json`.
- Os logs não registram o que você digita. Para todo método de entrada de terceiros, o macOS avisa "The developer can access anything you type with this input source" (o desenvolvedor pode acessar tudo o que você digitar com esta fonte de entrada); é um aviso genérico do sistema.

## Desenvolvimento

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

`make selftest` e `make realtest` não dependem dos seus ajustes. O autoteste usa uma configuração própria (Amazon Bedrock com o perfil da AWS e a região tirados da sua, todo o resto nos padrões); o teste em um app real muda o provedor para o Bedrock enquanto roda e depois devolve o seu. O que eles não conseguem verificar no momento é pulado, não reprovado: as verificações ao vivo do Bedrock sem credenciais para esse perfil, e tudo o que é digitado com a entrada segura ativa (a tela bloqueada, um campo de senha). A última linha conta as verificações aprovadas, reprovadas e puladas; só as reprovações fazem a execução falhar, e uma execução com verificações puladas termina em INCOMPLETE, ou em SKIPPED quando nada que digita rodou (BLOCKED: o teste em um app real começou com a tela bloqueada), nunca em PASSED.

O texto da interface é escrito como `tr("中文", "English")`: o chinês simplificado e o inglês vêm do código; os outros idiomas, dos String Catalogs, `Core/Resources/Localizable.xcstrings` para o texto do núcleo e `Resources/Localizable.xcstrings` para o do próprio app (mesclados e compilados em cada app pelo Makefile com o `xcstringstool` do Xcode), com o texto em inglês como chave e `%@` para cada interpolação. Depois de adicionar ou alterar um texto, execute `make strings` (o `make test` falha até lá; o texto dos autotestes, em `*SelfTest.swift`, não é para tradutores). Onde um mesmo texto em inglês significa duas coisas (o `make strings` aponta esses casos, e o `make strings-check` falha com eles), dê a um dos usos uma chave própria, um nome curto com pontos que diga onde ou como ele é usado: `tr("删除", "Remove", key: "remove.delete")`; o inglês dele é o valor em inglês dessa chave no catálogo. Adicionar um idioma é adicionar a coluna dele ao catálogo: as traduções revisadas, um arquivo JSON por idioma (`"core\t<key>"` ou `"app\t<key>"` → a tradução), entram com `Scripts/import-translations.py <folder>`, que nunca mexe no inglês e recusa uma tradução cujos marcadores não sejam os da chave dela. Os textos do próprio núcleo recebem o código do idioma da interface e o procuram do mesmo jeito (`InterfaceText.lookup`, que cada app define: os bundles `.lproj` dele no macOS; nas outras plataformas, o `StringCatalog` lê as tabelas do catálogo).

Organização do código: a raiz é o app para macOS; `Core/` é o núcleo que todas as plataformas compartilham, um pacote Swift próprio (ele compila e roda os testes sozinho, no macOS, no Linux e no Windows); `Windows/` é o começo do app para Windows.

- `Core/Sources/AllInOneIMECore`: cliente do Bedrock, SigV4, prompts, a máquina de estados de entrada de dois níveis (incluindo os comandos @ e o gesto de voz); sem dependência do AppKit
- `Core/Sources/AllInOneIMEText`: o texto da interface e o idioma dele (`UIString`, `InterfaceText`, `InterfaceLanguage` e `StringCatalog`, que lê o catálogo onde não há bundles `.lproj`); todos os links que abrem os ajustes (o `AllInOneIMECore` o reexporta)
- `Core/Sources/AllInOneIMEQuickJS`: QuickJS-ng (com o código-fonte em C em `Core/Sources/CQuickJS`), o JavaScript dos plugins e do `@js` onde não há JavaScriptCore (Windows, Linux, Android)
- `Core/Sources/AllInOneIMERime`: wrapper do librime
- `Core/Sources/AllInOneIMECLI`: a linha de comando, `allinoneime-cli` (`make cli`), executada pelo `main` próprio de cada plataforma
- `Sources/AllInOneIMEMac`: o que só o Mac tem (layouts de teclado, assinatura de código, Spotlight, AppleScript, a instalação do atualizador) e `Platform.mac`
- `Sources/AllInOneIME`: o método de entrada InputMethodKit, o painel de candidatos, a janela de ajustes, o reconhecimento de fala
- `Sources/AllInOneIMESettings`: o atalho "AllInOneIME Settings"
- `Sources/AllInOneIMEInstaller`: o "Install AllInOneIME" da imagem de disco: instala, atualiza e desinstala

Os pacotes de idioma têm a sua própria biblioteca, separada da dos plugins: o repositório [MicroZ-LLC/AllInOneIME-languages](https://github.com/MicroZ-LLC/AllInOneIME-languages), servido em https://languages.allinoneime.com/ e assinado com uma chave própria. `make pack` gera o arquivo compactado; ele é publicado lá como asset de release (release `zh-pinyin-<version>`, `ko-hangul-<version>`, `hi-phonetic-<version>`), e `swift Scripts/build-packs-index.swift <languages repo> build/packs/*.tar.xz.json` grava o `packs.json` lá e o assina em `packs.json.sig` com a chave dos pacotes de idioma guardada no keychain (`allinoneime-languages-signing`). O app lê https://languages.allinoneime.com/packs.json, verifica a assinatura e depois o tamanho e o SHA-256 do arquivo compactado. Para testar um pacote a partir de um servidor local: `--test-key` assina com uma chave de teste, e `AllInOneIME --install-pack zh-pinyin --library http://127.0.0.1:8765/ --key <its public key> --packs-dir <folder>`.

Publicar uma versão (o atualizador embutido lê https://allinoneime.com/update.json, assinado com a chave própria das releases):

1. Aumente a versão (`AppVersion.swift` e os três Info.plist; `AppVersionTests` confere se concordam) e os registros de alterações.
2. `make dmg NOTARY_PROFILE=<profile>`: `build/AllInOneIME-<version>.dmg` com o seu `.sha256`, e `build/AllInOneIME-<version>-update.zip` (os dois apps, como o instalador da imagem de disco os traz). Os apps e a imagem são assinados com o certificado Developer ID Application das Chaves, e a imagem é notarizada com esse perfil de chaves do `xcrun notarytool` e grampeada (stapled). O método de entrada leva o perfil de provisionamento Developer ID (`Resources/Signing/AllInOneIME-DeveloperID.provisionprofile`, `DIST_PROFILE`), que concede os entitlements de keychain dele; a compilação é interrompida se o perfil não listar o certificado de assinatura, não provisionar todos os dispositivos ou não tiver pelo menos 30 dias de validade (`Scripts/profile-entitlements.sh`), ou se a assinatura não tiver os entitlements de keychain, e executa uma vez o método de entrada assinado (o macOS encerra um cujo perfil não sirva). Um `DIST_PROFILE` vazio também a interrompe: uma release sem os entitlements perderia de vista todas as chaves que foram para as Chaves do iCloud. O perfil lista só os dois certificados Developer ID G1: antes de assinar com outro (G2), crie no portal de desenvolvedor um novo perfil que o liste (à mão: a assinatura do App ID não fica a cargo do Xcode) e faça commit dele.
3. Envie os dois para a release `v<version>` do GitHub e publique-a.
4. `make update-manifest UPDATE_SUMMARY_EN="…" UPDATE_SUMMARY_ZH="…"` (uma ou duas frases cada): escreve `site/public/update.json` (versão, build e macOS mínimo lidos dos apps, o endereço, tamanho e SHA-256 do arquivo, o endereço das notas da versão e o resumo) e o assina em `update.json.sig` com a chave das chaves de login (`allinoneime-releases-signing`; o macOS pode pedir para permitir o acesso). Faça commit dos dois.
5. Publique o site (`cd site && npx wrangler@4 deploy`), só quando os arquivos da release já puderem ser baixados: os apps verificam uma vez por dia, e `AllInOneIME --check-update` mostra o que eles veem.

O app confere a assinatura do manifesto com a chave pública embutida nele antes de lê-lo, nunca instala uma versão que não seja mais nova, só baixa por https de allinoneime.com ou dos arquivos das releases do repositório no GitHub, e só instala o arquivo quando o tamanho e o SHA-256 batem com o manifesto, os bundle IDs, as versões e as assinaturas de código dos dois apps estão corretos e o novo método de entrada inicia. O método de entrada então passa o trabalho para o próprio executável como auxiliar (`--apply-update`), que espera ele encerrar, troca os apps como o instalador faz (os antigos são postos de lado e voltam se algo falhar) e registra o novo. Para testar com um servidor local: `make update-test`, ou `--test-key` com `Scripts/build-update-manifest.swift` e `AllInOneIME --install-update --manifest-url http://127.0.0.1:<port>/update.json --key <its public key> --target-dir <folder>`.

O bundle ID ainda é `com.aipinyin.inputmethod.AIPinyin`: o macOS o usa para lembrar a fonte de entrada adicionada e a permissão do microfone, então mudá-lo significaria adicionar o método de entrada e conceder a permissão de novo.

## Licença

Copyright © 2026 MicroZ LLC. Código-fonte disponível sob a [Functional Source License 1.1](../../LICENSE) (FSL-1.1-ALv2): use, leia, altere e compartilhe para qualquer finalidade, exceto um produto concorrente. Cada versão passa a ser Apache-2.0 dois anos após o seu lançamento. As versões até a 0.6.1 foram lançadas sob a GPL-3.0 e continuam disponíveis sob ela.

Componentes de terceiros (o librime e seus plugins, sob BSD-3-Clause; os scripts Lua do rime-ice e o pacote de idioma chinês, sob GPL-3.0) estão listados em [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
