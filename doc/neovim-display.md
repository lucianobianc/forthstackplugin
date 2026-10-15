# Fase 2 — Visualização no Neovim

A camada Lua apresenta registros JSON de versão 1 do protótipo Gforth usando
extmarks e virtual text. Validada com Neovim 0.10.4, Linux x86-64. Não possui
pacotes Lua externos nem configuração obrigatória ou atalhos globais. A execução
é iniciada com `ForthStackRun` e depois atualizada automaticamente ao editar.

## Experimentar

Na raiz do repositório, com `gforth`, `python3` e `nvim` no PATH:

```sh
python3 prototype/trace.py examples/compiled.fs example > /tmp/forth-stack.json
nvim --cmd 'set runtimepath^=.' examples/compiled.fs
```

No Neovim:

```vim
:ForthStackLoad /tmp/forth-stack.json
:ForthStackToggle
:ForthStackInspect
:ForthStackClear
```

Para testar sem executar Forth, use o registro de teste incluído:

```vim
:ForthStackLoad tests/fixtures/compiled.json
```

No ambiente cloud, execute antes `export PATH="/workspace/.cloud-setup/bin:$PATH"`.
Para instalação permanente, adicione o repositório ao runtimepath usando o seu
gerenciador de plugins ou o mecanismo nativo de packages do Neovim.

## Comportamento

`ForthStackLoad` recebe o caminho de um registro JSON e desenha somente os eventos
do arquivo aberto no buffer atual. Caminhos relativos no campo `source.file` são
resolvidos a partir da pasta do JSON; o protótipo normalmente produz caminhos
absolutos. Caminhos simbólicos são normalizados pela localização real quando
possível. Os dados da palavra de entrada não são atribuídos artificialmente a
uma linha do fonte.

Cada linha recebe a **última observação `after`**, em ordem cronológica:

```text
  1+                    [ 16 ]  após 1+
```

O topo aparece à direita. Se houver vários tokens ou várias iterações na mesma
linha, a observação mais recente prevalece. Isso **não significa estado ao final
da linha**: palavras imediatas e estruturas de controle podem executar depois
do último token sondado. O sufixo `após TOKEN` delimita o que foi observado.
Números são exibidos como inteiros; não se infere que `0` é falso ou que uma
célula é um endereço.

`ForthStackInspect` mostra em janela flutuante a pilha completa da última
observação na linha do cursor, token, sequência e quantidade de observações
`after` naquela linha. O histórico é retido para permitir evolução da interface,
mas não existe seleção de ocorrência nesta fase. A janela anterior é fechada ao
inspecionar novamente, limpar, alternar a visualização, editar ou trocar o nome
do arquivo associado ao buffer.

`ForthStackToggle` oculta e restaura as marcas sem descartar o histórico;
`ForthStackClear` descarta ambos. Outros namespaces de extmarks permanecem
intactos. Qualquer edição invalida os dados do buffer, mesmo com a visualização
oculta. Para registros JSON estáticos, carregue novamente o registro. Para uma
execução iniciada com `ForthStackRun`, uma nova coleta é agendada após a digitação. Renomear o buffer também invalida a associação.

As marcas usam o grupo `ForthStackValue`, associado por padrão a `Comment`,
respeitando uma definição personalizada já existente. Texto Forth, estado
`modified` e changedtick não são alterados por desenhar, ocultar ou limpar.

## Validação e limites

Registros com execução incompleta, erro ou versão desconhecida são rejeitados.
O carregador verifica sequência de eventos, pilhas, fases e a localização dos
tokens do arquivo atual. Um erro na validação preserva a visualização anterior.
Uma edição já terá invalidado essa visualização pelo acompanhamento do buffer.

A verificação inicial de origem compara o token, linha e coluna em bytes com o
buffer. **Não é uma prova de igualdade integral do programa**: se o código mudar
mantendo os mesmos tokens nessas posições, um trace antigo pode passar. Também
não detecta alterações em arquivos auxiliares. Até existir um manifesto de hashes
de todas as fontes, gere novamente o registro após qualquer alteração no programa
e não transporte registros entre revisões como se fossem equivalentes.

Limites desta fase: JSON de 4 MiB, 10.000 eventos, 256 células por snapshot.
A carga é síncrona e limitada; não foi projetada para registros grandes.
Valores fora de ±(2^53−1) são rejeitados, pois o LuaJIT do Neovim decodifica os
números JSON como doubles. O protótipo Gforth consegue produzir células de 64
bits; exibi-las integralmente exigirá estender o protocolo para representar
inteiros grandes sem perda. Não se arredondam silenciosamente esses valores.

Há execução explícita assíncrona via `ForthStackRun`, descrita abaixo. Ainda não há
gerenciamento de identidade, etiquetas ou persistência. A instrumentação mantém as limitações
descritas em [gforth-instrumentation.md](gforth-instrumentation.md).

## API e organização

- `require('forth-stack').load(path, bufnr?)`: lê, valida e exibe um JSON.
- `show(trace, bufnr?, base?)`: recebe uma tabela já decodificada; caminhos relativos
  usam `base`, ou o diretório atual. Recebe dados emprestados e copia os snapshots.
- `clear(bufnr?)`, `toggle(bufnr?)`, `inspect(bufnr?, line?)`: controlam a exibição.
  O buffer padrão é o atual. `toggle` retorna a visibilidade resultante ou false
  sem registro; `inspect` retorna o ID da janela ou nil sem observação.

O módulo `trace.lua` valida e agrupa; `display.lua` desenha; `init.lua` mantém o
estado por buffer e invalida associações. Os comandos capturam erros e notificam
o usuário; a API Lua propaga erros ao chamador. Não é necessário chamar `setup()`.

## Testes

```sh
bash tests/run.sh
```

O script executa os 15 testes Python da instrumentação, gera um registro novo pelo
Gforth e executa 8 cenários headless no Neovim. Eles verificam estados e posições,
ramo não executado, última ocorrência de loop, integridade do buffer, isolamento
de namespaces e buffers, toggle/clear, inspeção, dados inválidos, precisão,
invalidação após edição/renomeação e o caminho real Gforth → JSON → Neovim.
Os testes verificam os extmarks e o conteúdo da janela via API; não são uma
avaliação visual de cores ou legibilidade em diferentes terminais.

## Instalação e execução integrada

O [README](../README.md) contém receitas para lazy.nvim e packages start nativos.
A instalação nativa carrega os comandos no startup sem `setup()`. Para cópias
adicionadas ao runtimepath após o startup, `require('forth-stack').setup()` também
registra os comandos, dispensando `:runtime` manual. Não há etapa de compilação
ou dependências externas para `:ForthStackDemo`, que encontra os arquivos incluídos
pela localização do plugin instalado, independentemente do diretório atual.

`:ForthStackRun palavra` escolhe a palavra de entrada e executa um snapshot do
buffer em processo assíncrono. O texto é enviado por stdin ao supervisor Python,
que usa um arquivo privado temporário e o carrega com `included1`, atribuindo o
nome original ao fluxo. Assim, as localizações e includes relativos continuam
apontando para o programa original; o arquivo do usuário não é escrito. O buffer
pode estar modificado ou ainda não existir no disco, desde que tenha nome em uma
pasta existente. Outros arquivos incluídos são lidos do disco, não de buffers
modificados. Snapshot de fonte: máximo 4 MiB.

Por padrão, Run arma atualização automática **somente naquele buffer**. Alterações,
inclusive em modo de inserção, invalidam marcas, cancelam o processo corrente e
reiniciam um timer de 350 ms. O timer captura a versão mais recente do buffer;
editações em rajada geram uma única execução. O teste de identidade da execução,
nome e changedtick descarta respostas atrasadas. Desfazer/refazer e recarregar o
buffer também participam do acompanhamento. Não há execução só por abrir arquivos.

`:ForthStackStop` pausa timers/execução; Run retoma ou muda a palavra de entrada.
Clear, carregar um JSON válido, renomear ou fechar também desarmam o acompanhamento.
Sair do Neovim encerra processos ativos. `auto_update = false` mantém apenas
execução manual; `debounce_ms` configura a pausa entre 1 e 5000 ms. Código
incompleto gera estado de erro sem notificações repetidas durante edição e será
reavaliado após a próxima mudança; `:ForthStackStatus` mostra o diagnóstico.
`vim.b.forth_stack_status` e `vim.b.forth_stack_error` expõem esses dados à API.
Erros de Run manual continuam sendo notificados. Resultados antigos não ficam
visíveis enquanto a versão atual está inválida.

Argumentos são passados como lista, sem shell. Cada atualização cria um processo
novo e reexecuta arquivo/palavra, incluindo seus efeitos de I/O. Palavras que
precisam de argumentos podem ser chamadas por um wrapper; `--input` continua
na CLI Python, mas não no comando Neovim. stdout é preservado no JSON, sem painel
próprio no Neovim. Stop envia SIGTERM ao supervisor, que encerra e aguarda seu
filho Gforth direto. Descendentes adicionais não são gerenciados. Includes
alterados em outro buffer não disparam atualizações nem têm changedtick validado.

Somente resultados completos e bem-sucedidos são desenhados; erros são mostrados
como notificações. Uma execução nova limpa a visualização anterior. O supervisor
continua capturando stdout/stderr em memória, e o limite de 4 MiB é aplicado ao
resultado recebido; isso não limita preventivamente toda a memória de coleta.
Não se deve usar este protótipo para executar programas não confiáveis.

`setup()` aceita `python`, `gforth`, `timeout`, `max_events`, `max_depth`,
`auto_update` e `debounce_ms`, com os
padrões e limites descritos no README. As opções são validadas antes da alteração;
repetir setup registra novamente os comandos sem duplicá-los. Caminhos de
executáveis são resolvidos antes de iniciar o supervisor, incluindo caminhos com
espaços. `:checkhealth forth-stack` verifica versão do Neovim, executáveis e
arquivos de runtime; ausência de Python/Gforth é aviso, pois demo/load funcionam
sem eles. A checagem encontra executáveis, sem prometer compatibilidade de toda
versão encontrada; as versões validadas estão documentadas no README.

A suíte inclui também 11 cenários de instalação nativa/execução em diretórios XDG
temporários e um teste de setup após startup sem carregamento de plugins. Eles
comprovam registro automático, demo sem dependências, configuração repetida,
diagnóstico, execução real, caminhos com espaços, arquivos não salvos, falhas,
cancelamento do filho Gforth e timeout. A receita lazy.nvim usa a API padrão do
gerenciador; o próprio lazy.nvim não foi instalado para essa validação.

## Validação de atualização contínua

Além da suíte existente, os testes cobrem snapshots não salvos, origem e includes
relativos preservados, arquivos novos sem criação no disco e onze cenários Lua:
edição com debounce, rajadas, código incompleto/recuperação sem popups, pausa,
troca da palavra de entrada, cancelamento de respostas antigas, recarga do disco,
Clear, modo manual,
arquivo novo e desligamento por renomeação/fechamento. O arquivo no disco e o
estado modified do buffer são verificados para impedir salvamento implícito.

## Diagnóstico legível

`:ForthStackStatus` abre um split de texto com o estado e a mensagem completa do
último erro. Linhas longas são quebradas visualmente; é possível rolar normalmente,
copiar o texto ou salvar com `:write /tmp/forth-stack-error.txt`. `q` fecha o
relatório e volta ao código. A janela é temporária e não modifica o arquivo Forth.
As mensagens distinguem códigos comuns do Gforth (pilha vazia, palavra desconhecida,
divisão por zero etc.) e incluem a última posição observada quando disponível.
Essa posição é contexto de compilação/última sonda, não um snapshot garantido no
instante da falha. Falhas do processo Gforth preservam também seu stderr.
