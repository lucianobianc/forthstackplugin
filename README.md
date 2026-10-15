# forthstackplugin

Plugin Neovim para observar a pilha de programas Forth. Mostra valores ao lado das
linhas e permite executar uma palavra explicitamente com Gforth, sem modificar o
fonte. Ainda experimental: identidades, etiquetas e persistência estão pendentes.

## Teste sem instalar

Se você já clonou o repositório, atualize com `git pull` e, na raiz dele, execute:

```sh
nvim -u examples/minimal-init.lua -c ForthStackDemo
```

Isso abre uma configuração mínima e a demonstração, sem modificar seu `init.lua`.

## Instalação

Requer **Neovim 0.10 ou superior** (validado em 0.10.4). Não há etapa de build.
Para experimentar a demonstração, basta o Neovim.

### lazy.nvim

Adicione à sua lista de plugins e execute `:Lazy sync`:

```lua
{
  'lucianobianc/forthstackplugin',
  main = 'forth-stack',
  lazy = false,
  opts = {},
}
```

O campo `main` identifica o módulo Lua correto para a configuração automática.
Também é possível carregar sob demanda: substitua `lazy = false` por
`cmd = { 'ForthStackDemo', 'ForthStackLoad', 'ForthStackRun', 'ForthStackStop',
'ForthStackInspect', 'ForthStackToggle', 'ForthStackClear' }`.

### Packages nativos do Neovim (Linux)

Sem gerenciador de plugins, execute no terminal:

```sh
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/plugins/start"
git clone https://github.com/lucianobianc/forthstackplugin.git \
  "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/plugins/start/forthstackplugin"
```

Reabra o Neovim normalmente. Os comandos são registrados automaticamente; não é
necessário alterar `init.lua` nem executar `:runtime`. Para atualizar, execute
`git pull` na pasta instalada. Com `NVIM_APPNAME` personalizado, use a pasta
exibida por `:echo stdpath('data')` seguida de `/site/pack/plugins/start/`.

Para carregar uma cópia local em uma sessão já aberta:

```lua
vim.opt.runtimepath:prepend('/caminho/absoluto/forthstackplugin')
require('forth-stack').setup()
```

`setup()` é opcional em instalações normais e pode ser chamado mais de uma vez.
Esse caminho explícito também funciona com `nvim -u NONE`, que desativa a carga
automática de plugins. Só adicionar ao runtimepath depois da inicialização não
executa retroativamente os arquivos `plugin/`.

## Experimente agora

Depois de instalar, execute:

```vim
:ForthStackDemo
```

Abre o exemplo incluído e exibe um registro pronto. Não depende do diretório
atual, de Python ou de Gforth. Posicione o cursor em uma linha anotada e execute
`:ForthStackInspect` para ver a pilha. Use `:ForthStackToggle` para ocultar/mostrar
e `:ForthStackClear` para limpar.

## Execute seu programa

Para execução real, instale **Python 3 e Gforth** no PATH. Validado em Linux
x86-64 com Gforth 0.7.3. Confira a instalação com:

```vim
:checkhealth forth-stack
```

Abra um arquivo `.fs`, salve-o e execute uma palavra definida nele:

```forth
: exemplo
  15
  1+
;
```

```vim
:ForthStackRun exemplo
```

A execução acontece em segundo plano, e as pilhas aparecem nas linhas observadas.
`:ForthStackStop` interrompe a execução do buffer atual. Editar, renomear ou fechar
o buffer cancela sua execução e invalida os resultados. Reexecutar substitui o
processo anterior. Arquivos são carregados normalmente pelo Gforth, inclusive
código de nível superior; o plugin só executa quando solicitado.

Configuração opcional no `opts` do lazy.nvim ou via Lua:

```lua
require('forth-stack').setup({
  python = 'python3',
  gforth = 'gforth',
  timeout = 5,        -- segundos, máximo 60
  max_events = 10000, -- máximo 10000
  max_depth = 256,    -- máximo 256 células
})
```

`python` e `gforth` recebem nomes de executáveis ou caminhos completos, não
comandos com argumentos de shell. Não são impostos atalhos globais.

## Comandos

| Comando | Função |
| --- | --- |
| `:ForthStackDemo` | Abrir exemplo com registro incluído |
| `:ForthStackRun palavra` | Executar palavra no arquivo salvo atual |
| `:ForthStackStop` | Interromper execução do buffer atual |
| `:ForthStackLoad arquivo.json` | Carregar registro externo |
| `:ForthStackInspect` | Inspecionar última observação na linha do cursor |
| `:ForthStackToggle` | Ocultar/mostrar visualização |
| `:ForthStackClear` | Limpar visualização e cancelar execução |

## Limitações e desenvolvimento

Os estados são observados depois dos tokens sondados; não representam
necessariamente o estado ao final de cada linha. Palavras imediatas e trechos
preexistentes têm cobertura limitada. São exibidos apenas registros completos e
inteiros representáveis exatamente pelo Lua (±(2^53−1)). A validação de um registro
externo compara posições e tokens, sem comprovar igualdade integral das fontes.
A execução não fornece sandbox para código não confiável. Os detalhes estão na
[investigação do Gforth](doc/gforth-instrumentation.md) e no
[guia da visualização e execução](doc/neovim-display.md).

Com `python3`, `gforth` e `nvim` no PATH, na raiz do projeto:

```sh
bash tests/run.sh
```

A suíte cobre o protótipo, a visualização, uma instalação nativa em ambiente
isolado, configuração tardia, execução assíncrona, cancelamento e timeout.
A especificação e as fases planejadas estão em [SPEC.md](SPEC.md).
