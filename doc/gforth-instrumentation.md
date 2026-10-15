# Investigação de instrumentação do Gforth

Implementação experimental da fase 1 de `SPEC.md`. Validada em Linux x86-64,
Gforth **0.7.3**, com Python 3 como supervisor. O protótipo continua utilizável
separadamente; o [plugin](neovim-display.md) agora o utiliza para execução explícita.
Não foi verificada compatibilidade com versões de desenvolvimento do Gforth.

## Mecanismos investigados

Foram lidos os fontes distribuídos com o pacote Gforth 0.7.3, especialmente
`debug.fs`, `debugs.fs`, `see.fs`, `source.fs`, `backtrac.fs`,
`kernel/int.fs`, `kernel/comp.fs` e `kernel/require.fs`. Na instalação local,
esses arquivos estão em
`/workspace/.cloud-setup/root/usr/share/gforth/0.7.3/`.

| Recurso | Evidência e utilidade | Limitação para este projeto |
| --- | --- | --- |
| `.s`, `depth`, `sp@` | `.s` preserva os elementos e mostra `<1> 15`, depois `<1> 16`, quando chamada dentro de uma definição | Exige pontos de observação; não fornece, sozinha, eventos ou localização |
| `~~`, `printdebugdata`, `.debugline` | `~~` compilada imprime arquivo, linha e pilha em stderr; as ações são `defer` | É uma sonda explícita no fonte; não registra automaticamente todas as palavras. A ação padrão usa a área de conversão numérica compartilhada |
| `current-sourcepos`, `compile-sourcepos` | Capturam arquivo/linha na compilação; `compile-sourcepos` compila esses dados como literais | Não constituem mapa retroativo de todos os endereços de instrução; não fornecem coluna |
| `see`, `xt-see` | `see sample` decompilou `: sample 15 1+ ;` | Reconstrói código, não a sequência executada nem os estados da pilha; não recupera o texto original com posições |
| `dbg`, `break:`, `break"` | `debug.fs` implementa stepping, entrada em chamadas e breakpoints; `dbg` e `break:` foram executados com `gforth-itc` | Interativo, saída textual com endereços, dependente do engine; não fornece eventos estruturados com posições de fonte |
| `catch`, `throw`, backtrace | Exceção não capturada mostrou o código e a cadeia de chamadas | O backtrace não é histórico de estados. `catch` restaura a pilha ao ponto protegido; ela não representa a pilha no instante da falha |
| `before-word`, `parser1`, `compiler1` | Permitem interceptar tokens enquanto o interpretador de texto compila uma definição | Interfaces específicas do Gforth; o hook não é chamado para cada operação durante a execução de uma palavra já compilada |
| `compile,` | Ponto de extensão do compilador (`defer`), com tradução para primitivas e otimizações | Não equivale a um token do fonte: literais, payloads inline, saltos e palavras imediatas exigem tratamento específico. Não foi usado como tracer universal |

O teste de `dbg sample` com o executável **gforth padrão** terminou com
`Invalid memory address`, código de processo 1, no primeiro literal. O mesmo
programa com **gforth-itc** terminou com código 0 e exibiu as pilhas vazia,
`15` e `16`. Isso corresponde às dependências de ITC explicitadas em
`debug.fs`, incluindo `breaker-size`, `set-bp` e `restore-bp`. Não se deve
apresentar esse resultado como falha de todas as versões ou engines do Gforth.
`--debug` imprime diagnósticos de inicialização, não um rastreamento da aplicação.

Na imagem Debian usada aqui, `dbg`, `~~` e `see` já estão disponíveis. Repetir
`require debug.fs` com o caminho de fontes realocado pode carregar dependências
novamente: `required` compara nomes/caminhos, e os nomes relativos registrados
na imagem diferem dos caminhos absolutos locais. Esse experimento gerou
redefinições e erro em `search.fs`; os testes reproduzíveis usam as palavras já
presentes na imagem, sem recarregar o pacote.

## Decisão e implementação

O protótipo combina **sondas na compilação em memória** com observações do
interpretador de texto durante a carga. O arquivo Forth é incluído
normalmente, sem pré-processador, reescrita ou anotações no disco:

1. O supervisor Python inicia um processo Gforth e abre um canal temporário
   separado para o protocolo. stdout/stderr do programa são preservados como
   campos distintos no resultado.
2. Durante `included`, `before-word` substitui `parser1` somente quando a ação
   vigente é `compiler1` ou `interpreter1`. O hook anterior é chamado e restaurado
   depois da carga. Ações do interpretador são envolvidas por snapshots; argumentos
   do parser não entram na pilha observada.
3. Para cada token comum ou literal, o wrapper captura arquivo, linha, coluna,
   nome da definição e texto do token, emite uma chamada `before`, delega a
   compilação ao próprio `compiler1` e emite uma chamada `after`.
4. Palavras imediatas continuam sendo compiladas/executadas pelo Gforth sem
   sondas próprias. São registradas como `coverage: "opaque"`; as demais têm
   `coverage: "probe"`. Comentários e delimitadores também podem aparecer no mapa.
5. A coleta começa antes da carga, é suspensa durante a compilação e retomada ao
   fechar uma definição. Assim, código interpretado fora das definições e sondas
   dentro dos corpos chamados produzem eventos na mesma sequência. O modo arquivo
   termina após a carga; o modo palavra fornece os argumentos inteiros e faz a
   chamada adicional. A sessão inteira é protegida por `catch`.
6. Cada sonda copia logicamente a visão da pilha via `depth`/`sp@`, sem remover
   seus elementos. Os números usam um conversor decimal próprio, que não usa
   `BASE`, `PAD` nem a área compartilhada de `<# ... #>`. O canal é descarregado
   a cada evento para preservar prefixos de execução em caso de interrupção.

Não há interpretação estática das operações: os valores vêm do Gforth real.
O fluxo condicional, os índices de loops e o número de ocorrências são os
observados na execução. Sondas adicionam chamadas e alteram o código em memória;
isso não é uma garantia de transparência para qualquer programa Forth.

## Executar

Com `gforth` disponível no PATH, a partir da raiz do repositório:

```sh
python3 prototype/trace.py examples/compiled.fs example
python3 -m unittest discover -s tests -v
python3 prototype/investigate.py --gforth gforth --gforth-itc gforth-itc
```

No ambiente cloud preparado, antes dos dois primeiros comandos:

```sh
export PATH="/workspace/.cloud-setup/bin:$PATH"
cd /workspace/forthstackplugin
```

Para reproduzir também a comparação com ITC nesta instalação realocada:

```sh
LD_LIBRARY_PATH=/workspace/.cloud-setup/root/usr/lib/x86_64-linux-gnu \
GFORTHPATH=.:/workspace/.cloud-setup/root/usr/lib/x86_64-linux-gnu/gforth/0.7.3:/workspace/.cloud-setup/root/usr/share/gforth/0.7.3 \
python3 prototype/investigate.py \
  --gforth /workspace/.cloud-setup/bin/gforth \
  --gforth-itc /workspace/.cloud-setup/root/usr/bin/gforth-itc
```

`investigate.py` registra os resultados dos experimentos, inclusive as falhas
esperadas do debugger padrão e do `throw` não capturado. Seu código de saída não
substitui a suíte de testes. Não é preciso instalar dependências Python.

A CLI aceita `--gforth CAMINHO`, `--input N` repetido, `--timeout SEGUNDOS`,
`--max-events N` e `--max-depth N`. Padrões: 5 segundos, 10.000 eventos e 256
células por snapshot. O timeout inclui compilação e execução.

## Resultado demonstrado

`examples/compiled.fs` define `birthday` e `example`, sem sondas no arquivo.
O resultado contém, entre outros, os eventos reais:

| seq | fase | definição/token | fonte (linha:coluna) | pilha |
| --- | --- | --- | --- | --- |
| 3 | before | example / birthday | 8:3 | `[15]` |
| 4 | before | birthday / 1+ | 3:3 | `[15]` |
| 5 | after | birthday / 1+ | 3:3 | `[16]` |
| 6 | after | example / birthday | 8:3 | `[16]` |

O ramo verdadeiro não é executado; o ramo `else` produz `18`, e o loop registra
três ocorrências distintas de `i`, com `0`, `1` e `2`. A pilha final é `[21]`.
Isso satisfaz a demonstração de observações **dentro** de uma palavra compilada,
e não apenas entre linhas interpretadas no nível superior.

## Protocolo e significado dos eventos

O supervisor retorna JSON com `format_version: 1`, `sites`, `events`, `status`,
`complete`, `forth_code`, `process_returncode`, `stdout`, `stderr` e `diagnostic`.
`complete: true` significa que a execução terminou normalmente, não que todas as
primitivas ou palavras imediatas foram instrumentadas.

Cada evento contém `seq`, `site`, `phase`, `source` e `stack`:

- `before` / `after`: snapshots imediatamente antes/depois de um token sondado.
  Chamadas têm efeito inclusivo; eventos de suas definições podem aparecer entre
  o par. Um `throw`, `exit` ou interrupção pode deixar operações sem evento `after`.
- `entry` / `return`: fronteiras da sessão (carga e eventual chamada adicional),
  com `site: 0` e
  `source: null`. Não se inventa uma localização para essas fronteiras.
- `stack`: células inteiras decimais com sinal, do fundo ao topo; topo à direita.
- `source`: arquivo informado pelo Gforth, linha e coluna em **bytes**, começando
  em 1, token e nome da definição. `site` identifica uma posição nesta carga;
  `seq` distingue ocorrências cronológicas, inclusive em loops.

`sites` inclui também tokens não executados e imediatos opacos; ausência de evento
não significa erro. Fonte e eventos são ligados pelo identificador do site, e não
pelo valor numérico da pilha. Não há IDs de instância, etiquetas ou proveniência.

O canal interno usa linhas `M` (metadados com strings em hexadecimal), `E`
(evento: sequência/site/fase/profundidade/células) e `X` (resultado de `catch`).
`X` aceita o código e um campo opcional 0/1 indicando falha durante compilação;
ausência mantém compatibilidade com registros antigos. Esse contexto permite
apontar o último token compilado, sem tratá-lo como snapshot de execução.
O parser verifica sequência, profundidade, referência ao site e marcador final.
Saída truncada ou execução sem resultado não é apresentada como sucesso.
`forth_code: -4096` indica limite de eventos; `-4097`, profundidade excedida.
Timeout, falha de processo, término prematuro via `bye` e erro Forth são distintos.
O JSON mantém o prefixo válido de eventos quando o resultado da execução é erro
ou timeout; um protocolo inválido é rejeitado, sem reutilizar snapshots ambíguos.

## Limitações e próximos pontos de investigação

- **Granularidade:** tokens comuns do fonte e literais, não todas as primitivas
  da VM. `if`, `else`, `then`, loops, `exit`, `recurse`, strings e outros imediatos
  não têm sondas próprias. Seus efeitos são visíveis nas próximas observações;
  `recurse` pode entrar em corpo sondado. Não é possível atribuir toda mudança
  entre eventos à última operação visível quando há um trecho opaco entre elas.
- **Código preexistente:** palavras da imagem e bibliotecas já carregadas são
  observadas somente nas fronteiras de chamada. O interior de novas definições
  incluídas durante a carga é visível; código compilado depois, durante a execução,
  não recebe automaticamente sondas. Não há instrumentação retroativa.
- **Metaprogramação:** macros com `postpone`/`compile,`, compiladores customizados,
  troca de `parser1`, defining words, `does>`, locals, mudanças de search order e
  uso de `evaluate` não têm suporte geral validado. As sondas de uma definição
  imediata executada durante a compilação ficam com coleta desativada; isso não
  torna sua expansão rastreável. Não há reivindicação de cobertura para essas APIs.
- **Fonte:** a posição é capturada na compilação a partir do buffer de entrada;
  não é DWARF nem mapa persistente de instruções. Arquivos incluídos preservam
  sua origem; fontes virtuais/evaluadas podem não fornecer localização válida.
  UTF-8 usa coluna em bytes, não coluna visual. Edições posteriores invalidam o
  mapa; os IDs não são estáveis entre execuções. O nome da definição é obtido de
  `latest`, adequado ao subconjunto de definições `:` testado.
- **Dados:** não se distingue endereço, flag, inteiro ou parte de valor duplo.
  Não se inspecionam memória apontada, pilha de floats, locals nem pilha de retorno.
  As posições e os valores não estabelecem identidade semântica de elementos.
- **Transparência:** sondas mudam tamanho e endereços do código, tempo, I/O e uso
  temporário das pilhas. Programas que inspecionam internals da VM ou dependem
  desses detalhes podem mudar de comportamento. O logger evita a interferência
  conhecida com conversão numérica; isso não prova transparência universal.
- **Falhas:** não há snapshot garantido no ponto de um `throw`/signal; só o último
  evento emitido. A pilha restaurada por `catch` não é exportada como estado da
  falha. Exceções capturadas pelo próprio programa não necessariamente chegam ao
  supervisor; ele informa o resultado que escapou da palavra de entrada.
- **Recursos:** cada snapshot custa O(profundidade) e faz I/O síncrono. Os limites
  cobrem eventos e profundidade, não o volume de metadados ou stdout/stderr, que
  ainda são capturados em memória. O timeout encerra o processo Gforth direto;
  não gerencia descendentes lançados pelo programa. Não é sandbox de execução
  para arquivos não confiáveis, nem coletor adequado a cargas grandes.

O próximo experimento útil é ampliar a cobertura de imediatos/estruturas de
controle com regras específicas, sem confundir token de fonte com primitiva da
VM, e definir um protocolo de eventos que explicite fronteiras opacas e chamadas.
A investigação de identidade e a implementação do plugin ficam para etapas
posteriores.

## Validação

A suíte contém 15 testes de integração/protocolo e passou neste ambiente. Verifica
snapshots e posições reais, ambas as decisões condicionais, iterações, recursão,
`exit`, operações da pilha, `>r`/`r>`, fonte incluída, saída separada, conversão
numérica, célula mínima de 64 bits, erros de compilação/execução, entrada ausente,
limites, timeout e `bye` prematuro. Um programa de operações da pilha também é
executado sem instrumentação para comparar o resultado. Fixtures são verificadas
por SHA-256 antes/depois da execução. Os testes nativos reproduzíveis confirmaram
`see`, `.s`, `~~`, backtrace, `dbg` e `break:` nas condições descritas acima.

## Extensão: execução do arquivo

A palavra de entrada é opcional na CLI e no plugin. O wrapper de `interpreter1`
registra tokens comuns e literais no nível superior, usando `<top-level>` no
campo `source.word`. `:` inicia uma região de compilação sem expor seu controle
interno, `;` encerra essa região, e interpretação entre colchetes durante uma
definição continua com coleta desativada. Palavras imediatas continuam delegadas
ao Gforth sem sondas próprias.

O arquivo é carregado uma única vez por sessão. No modo palavra, o efeito do
código externo às definições permanece na pilha antes da chamada adicional.
Definições não chamadas não geram eventos de execução. Erros na compilação
restauram o parser externo antes do término do processo; definições incompletas
são reportadas como erro de controle (-22).
