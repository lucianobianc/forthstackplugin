# forthstackplugin

Veja a pilha do seu programa Forth ao lado do código, dentro do Neovim.
Depois de iniciar uma execução, os valores se atualizam enquanto você escreve,
sem precisar salvar o arquivo.

O plugin está em desenvolvimento. A visualização e a execução com Gforth já
funcionam; etiquetas para os valores ainda não estão disponíveis.

## Requisitos

- **Neovim 0.10 ou superior.**
- **Python 3 e Gforth** para executar seus programas.

A demonstração precisa apenas do Neovim. A execução foi testada em Linux com
Gforth 0.7.3.

## Instalação

### Com lazy.nvim

Adicione à sua lista de plugins e execute `:Lazy sync`:

```lua
{
  'lucianobianc/forthstackplugin',
  main = 'forth-stack',
  lazy = false,
  opts = {},
}
```

### Sem gerenciador de plugins (Linux)

Execute no terminal:

```sh
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/plugins/start"
git clone https://github.com/lucianobianc/forthstackplugin.git \
  "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/plugins/start/forthstackplugin"
```

Reinicie o Neovim normalmente. Não é necessário alterar seu `init.lua`.
Se os comandos não aparecerem, confira se sua configuração permite carregar
plugins (`:set loadplugins?`) e se a pasta instalada está no `packpath`.

## Primeiro teste

Dentro do Neovim, execute:

```vim
:ForthStackDemo
```

Um exemplo será aberto com as pilhas ao lado das linhas. Para ver os detalhes,
coloque o cursor em uma linha anotada e execute `:ForthStackInspect`.

Já clonou o projeto e quer experimentar sem instalar? Na raiz dele, execute:

```sh
nvim -u examples/minimal-init.lua -c ForthStackDemo
```

## Usando no seu código

Abra um arquivo Forth, por exemplo `exemplo.fs`:

```forth
: exemplo
  15
  1+
;
```

Execute uma vez:

```vim
:ForthStackRun exemplo
```

As pilhas aparecem ao lado das operações observadas. O topo da pilha fica à
direita. A partir daí, a visualização se atualiza após uma pausa de 350 ms na
digitação, mesmo com alterações não salvas.

Use `:ForthStackStop` para pausar. Execute `:ForthStackRun exemplo` novamente
para retomar. Se o código estiver incompleto, o plugin aguarda a próxima edição
e tenta de novo, sem abrir avisos a cada tecla.

Cada atualização executa novamente o programa, incluindo suas operações de
entrada e saída. A cobertura ainda é parcial: nem toda operação Forth é
acompanhada. Consulte as [limitações](doc/neovim-display.md#validação-e-limites)
para entender quais estados são exibidos.

## Comandos úteis

| Comando | O que faz |
| --- | --- |
| `:ForthStackDemo` | Abre a demonstração |
| `:ForthStackRun palavra` | Executa e acompanha as edições |
| `:ForthStackStop` | Pausa o acompanhamento |
| `:ForthStackInspect` | Mostra detalhes da pilha na linha do cursor |
| `:ForthStackToggle` | Oculta ou mostra as pilhas |
| `:ForthStackClear` | Limpa as pilhas e pausa o acompanhamento |
| `:ForthStackStatus` | Mostra o estado e o último erro |

Se algo não funcionar, comece por:

```vim
:checkhealth forth-stack
```

## Saiba mais

- [Configuração, registros externos e limitações](doc/neovim-display.md)
- [Investigação da instrumentação no Gforth](doc/gforth-instrumentation.md)
- [Especificação do projeto](SPEC.md)

Para executar os testes, com Neovim, Python 3 e Gforth disponíveis no terminal:

```sh
bash tests/run.sh
```
