# Fase 2 — Visualização no Neovim

A camada Lua apresenta registros JSON de versão 1 do protótipo Gforth usando
extmarks e virtual text. Validada com Neovim 0.10.4, Linux x86-64. Não possui
pacotes Lua externos nem configuração obrigatória, atalhos globais ou execução
automática de código Forth.

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
oculta; desfazer a edição não restaura o registro automaticamente. O usuário deve
carregá-lo novamente. Renomear o buffer também invalida a associação.

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

Não há `ForthStackRun`, execução de processos pelo plugin, gerenciamento de
identidade, etiquetas ou persistência. A instrumentação mantém as limitações
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
