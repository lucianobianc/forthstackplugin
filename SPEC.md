# Forth Stack Visualizer for Neovim
**Especificação de Projeto — Versão 0.1**

**Estado:** Proposta inicial  
**Linguagem do plugin:** Lua  
**Editor:** Neovim  
**Motores Forth:** Gforth inicialmente; pForth futuramente  
**Plataforma prioritária:** Linux

---

## 1. Visão geral

O projeto consiste em desenvolver um plugin para Neovim capaz de visualizar o estado da pilha de dados (*data stack*) durante a execução de programas Forth.

A visualização deve aparecer diretamente ao lado das linhas de código, permitindo ao programador acompanhar a evolução dos valores e identificar os elementos da pilha por meio de etiquetas (*labels*) personalizadas.

O sistema utilizará um interpretador Forth real como motor de execução, em vez de depender exclusivamente de análise estática.

O plugin não deverá modificar a sintaxe, a semântica ou os arquivos de código-fonte Forth.

### 1.1 Objetivo principal

Tornar o fluxo de dados de programas Forth imediatamente compreensível por meio da visualização dos estados intermediários da pilha.

### 1.2 Princípios

1. Preservar integralmente a linguagem Forth.
2. Aproveitar os recursos nativos do Neovim.
3. Utilizar interpretadores Forth existentes.
4. Minimizar a necessidade de configuração manual.
5. Automatizar o rastreamento de valores e etiquetas sempre que possível.
6. Separar execução, análise, apresentação e persistência.
7. Desenvolver incrementalmente, mantendo o sistema funcional a cada etapa.

---

## 2. Experiência do usuário

### 2.1 Visualização da pilha

Após executar o programa, o plugin deverá apresentar o estado da pilha ao lado das linhas correspondentes.

Exemplo conceitual:

```forth
15                 [ IDADE: 15 ]
FAZ-ANIVERSARIO    [ IDADE: 16 ]
18                 [ IDADE: 16, 18 ]
>=                 [ FALSE ]
```

Os conteúdos entre colchetes representam elementos visuais produzidos pelo plugin. Não fazem parte do arquivo Forth.

O topo da pilha será representado à direita.

A representação deverá distinguir valores numéricos, valores lógicos e outros tipos quando houver informação suficiente para fazê-lo com segurança.

### 2.2 Etiquetas personalizadas

O usuário poderá atribuir nomes aos elementos da pilha.

Exemplo:

```text
Antes: [ 15 ]
Depois: [ IDADE: 15 ]
```

A atribuição ocorrerá por meio de uma interação do Neovim, sem modificar o código-fonte.

Uma etiqueta identifica conceitualmente um elemento da pilha, não simplesmente sua posição ou seu valor numérico.

### 2.3 Propagação automática de etiquetas

As etiquetas deverão acompanhar os elementos durante as transformações que preservam sua identidade conceitual.

Exemplo:

```forth
15                 [ IDADE: 15 ]
FAZ-ANIVERSARIO    [ IDADE: 16 ]
```

Quando uma operação consumir elementos e produzir um resultado semanticamente diferente, suas etiquetas não deverão ser transferidas automaticamente.

Exemplo:

```forth
15                 [ IDADE: 15 ]
18                 [ IDADE: 15, 18 ]
>=                 [ FALSE ]
```

O resultado da comparação não herda a etiqueta `IDADE`.

**Regra fundamental:** a preservação de identidade não pode ser inferida exclusivamente da quantidade de elementos consumidos e produzidos.

O analisador deverá combinar informações da execução com regras de propagação e rastreamento de proveniência.

Nos casos ambíguos, a política inicial será não propagar a etiqueta, evitando apresentar informações potencialmente incorretas.

### 2.4 Manipulação da pilha

O analisador deverá compreender inicialmente as seguintes operações:

| Palavra | Comportamento esperado |
|---|---|
| `DUP` | Duplica o elemento e sua informação de identidade |
| `DROP` | Remove elemento e etiqueta |
| `SWAP` | Permuta elementos e etiquetas |
| `OVER` | Copia o elemento correspondente e sua etiqueta |
| `ROT` | Reorganiza elementos e etiquetas |
| `NIP` | Remove o elemento correspondente |
| `TUCK` | Reorganiza e duplica os elementos correspondentes |

As cópias deverão possuir identidades de instância distintas, preservando o vínculo com sua origem.

Operações aritméticas e lógicas deverão utilizar regras de propagação próprias, sem presumir que todas preservam a identidade.

---

## 3. Execução dinâmica

### 3.1 Motor Forth

A primeira implementação utilizará Gforth.

O sistema deverá ser arquitetado de maneira que outros motores, como pForth, possam ser integrados posteriormente.

Não se deve assumir que os mecanismos internos de instrumentação desses interpretadores sejam equivalentes.

### 3.2 Instrumentação

O plugin deverá obter informações suficientes para reconstruir os estados intermediários da pilha durante a execução.

Essas informações deverão incluir, quando tecnicamente disponíveis:

- Identificação do ponto de execução no código-fonte.
- Estado da pilha antes e depois das operações observadas.
- Operação executada.
- Ordem cronológica de execução.
- Informações necessárias para rastrear a origem dos elementos.

A consulta à pilha apenas ao final do programa é insuficiente.

A instrumentação de palavras compiladas deverá ser investigada especificamente para Gforth.

**Não se pressupõe que Gforth disponibilize diretamente todas essas informações por uma API pronta.** Poderá ser necessária instrumentação adicional.

### 3.3 Execução controlada

A execução deverá ser iniciada explicitamente pelo usuário.

Comando proposto:

```vim
:ForthStackRun
```

A execução automática a cada tecla pressionada não fará parte da versão inicial.

O interpretador deverá executar em um processo separado do Neovim.

O plugin deverá permitir interromper uma execução em andamento e configurar limites de tempo e volume de dados registrados.

Esses limites não constituem, por si só, isolamento de segurança. A execução de programas Forth não confiáveis exigirá medidas adicionais de sandboxing.

### 3.4 Múltiplas execuções

Uma mesma linha poderá ser executada diversas vezes, particularmente dentro de loops.

O sistema deverá preservar o histórico dos estados observados e permitir selecionar uma ocorrência específica.

Na versão inicial, poderá ser exibida apenas a última ocorrência, desde que a arquitetura permita a futura navegação pelo histórico.

### 3.5 Caminhos condicionais

O analisador deverá refletir o caminho efetivamente percorrido durante a execução.

Não será necessário calcular todos os caminhos possíveis por análise estática.

O resultado exibido dependerá dos dados de entrada utilizados na execução observada.

---

## 4. Modelo de identidade

Cada elemento observado na pilha deverá possuir uma representação interna independente do valor concreto.

Modelo conceitual:

```text
StackElement
    instance_id
    value
    label
    origin
    history
```

- `instance_id`: identificação da instância observada.
- `value`: representação do valor obtido durante a execução.
- `label`: etiqueta opcional atribuída pelo usuário.
- `origin`: informações sobre a criação ou derivação do elemento.
- `history`: referências às transformações registradas.

Os identificadores de instância serão válidos no contexto de uma execução, não necessariamente entre execuções diferentes.

O modelo deverá distinguir:

1. Preservação de identidade.
2. Cópia de um elemento.
3. Transformação de um elemento.
4. Combinação de elementos.
5. Consumo e descarte.
6. Criação de um novo elemento.

### 4.1 Limites da inferência automática

A identidade conceitual de um valor nem sempre pode ser determinada apenas pela execução.

Duas palavras com efeitos de pilha semelhantes podem representar operações semanticamente diferentes.

Portanto, o sistema deverá admitir:

- Regras automáticas conhecidas.
- Rastreamento de proveniência.
- Regras conservadoras para operações desconhecidas.
- Eventuais ajustes do usuário, sem torná-los obrigatórios no uso cotidiano.

Não será exigida inferência semântica perfeita.

---

## 5. Integração com Neovim

### 5.1 Tecnologia

O plugin será desenvolvido prioritariamente em Lua, utilizando as APIs nativas do Neovim.

### 5.2 Virtual text

A apresentação dos estados da pilha utilizará inicialmente *virtual text*.

O conteúdo deverá ser exibido sem alterar o texto armazenado no buffer.

### 5.3 Extmarks

Extmarks serão utilizados para associar as informações visuais às posições do código.

Entretanto, extmarks não deverão ser tratados como identificadores persistentes e infalíveis de instruções.

O sistema precisará invalidar ou reconciliar associações quando o código for modificado.

### 5.4 Interface inicial

Comandos propostos:

| Comando | Função |
|---|---|
| `:ForthStackRun` | Executar e coletar estados |
| `:ForthStackClear` | Remover visualizações |
| `:ForthStackToggle` | Ativar ou ocultar visualizações |
| `:ForthStackInspect` | Inspecionar a pilha no ponto selecionado |
| `:ForthStackLabel` | Atribuir ou alterar uma etiqueta |
| `:ForthStackStop` | Interromper a execução |

Os nomes são provisórios.

O usuário deverá poder configurar atalhos, sem que o plugin imponha mapeamentos globais.

### 5.5 Visualização detalhada

Uma janela flutuante poderá apresentar a pilha completa, inclusive quando o conteúdo exceder a largura disponível na linha.

A apresentação deverá ser legível em terminais e esquemas de cores diferentes.

---

## 6. Persistência de metadados

As etiquetas e preferências relacionadas ao código deverão ser armazenadas em arquivos separados.

Exemplo:

```text
programa.fs
programa.stack.json
```

O arquivo `.fs` deverá permanecer intocado pelo plugin.

O arquivo auxiliar poderá conter:

- Etiquetas atribuídas pelo usuário.
- Referências aos pontos de criação dos elementos.
- Regras de propagação definidas pelo usuário, quando necessárias.
- Preferências de visualização específicas do arquivo.

Os estados de execução não precisarão ser persistidos inicialmente.

### 6.1 Associação de etiquetas ao código

Não será suficiente armazenar apenas números de linha ou identificadores temporários de execução.

O sistema deverá estabelecer uma estratégia para reencontrar os pontos de atribuição das etiquetas em execuções posteriores.

Essa estratégia poderá utilizar uma combinação de localização no arquivo, contexto sintático e identificação da operação.

Alterações que impossibilitem uma associação confiável deverão invalidar ou sinalizar a etiqueta correspondente, em vez de associá-la silenciosamente ao elemento errado.

### 6.2 Formato

JSON será o formato inicial proposto.

O esquema definitivo será estabelecido após a validação do mecanismo de associação das etiquetas.

O arquivo deverá possuir um identificador de versão de formato para permitir migrações futuras.

---

## 7. Arquitetura proposta

```text
forth-stack.nvim/
├── lua/
│   └── forth-stack/
│       ├── init.lua
│       ├── config.lua
│       ├── display.lua
│       ├── labels.lua
│       ├── stack.lua
│       ├── trace.lua
│       ├── persistence.lua
│       └── engine/
│           ├── init.lua
│           └── gforth.lua
├── plugin/
│   └── forth-stack.lua
├── tests/
├── examples/
├── doc/
└── README.md
```

As responsabilidades deverão permanecer separadas:

**Motor:** executa o programa e fornece eventos observáveis.

**Rastreamento:** reconstrói estados e relações entre elementos.

**Etiquetas:** administra nomes e regras de propagação.

**Persistência:** armazena e recupera metadados.

**Interface:** apresenta os resultados no Neovim.

O protocolo entre motor e analisador deverá ser documentado e independente da apresentação.

---

## 8. Escopo inicial

### Incluído

- Neovim em Linux.
- Plugin em Lua.
- Integração inicial com Gforth.
- Execução explícita.
- Visualização da pilha com virtual text.
- Etiquetas personalizadas.
- Persistência em arquivo auxiliar.
- Rastreamento das operações básicas da pilha.
- Transformações aritméticas simples.
- Registro dos estados observados.
- Tratamento de erros e interrupções.

### Fora do escopo inicial

- Desenvolvimento de um interpretador Forth próprio.
- Suporte simultâneo a vários interpretadores.
- Análise estática completa.
- Inferência semântica perfeita.
- Alteração da sintaxe Forth.
- Interface gráfica independente do Neovim.
- Execução automática a cada edição.
- Suporte completo a todas as extensões de Forth.
- Rastreamento integral da pilha de retorno.
- Suporte a múltiplas tarefas Forth concorrentes.

---

## 9. Plano de desenvolvimento

### Fase 1 — Investigação técnica

**Objetivo:** comprovar a viabilidade da instrumentação com Gforth.

Investigar como observar estados intermediários da pilha e relacioná-los às instruções do código-fonte, inclusive dentro de palavras compiladas.

Entregável: protótipo mínimo capaz de executar um exemplo Forth e produzir um registro estruturado de estados.

**Critério de aceitação:** demonstrar rastreamento dentro de uma palavra definida pelo usuário, e não apenas entre linhas interpretadas no nível superior.

Caso isso não seja viável com o mecanismo escolhido, documentar as limitações e avaliar alternativas antes de avançar.

### Fase 2 — Visualização no Neovim

Implementar a apresentação de estados de pilha com virtual text, inicialmente utilizando registros de execução de teste.

**Critério de aceitação:** apresentar corretamente diferentes estados ao lado das linhas correspondentes, sem modificar o buffer.

### Fase 3 — Modelo de identidades

Implementar a pilha paralela e o rastreamento de operações básicas.

**Critério de aceitação:** movimentações, duplicações e remoções preservam corretamente as associações entre elementos e etiquetas.

### Fase 4 — Etiquetas e persistência

Permitir atribuição interativa de etiquetas e armazenamento no arquivo auxiliar.

**Critério de aceitação:** fechar e reabrir o arquivo, executar novamente o programa e recuperar as etiquetas nos pontos identificados com segurança.

### Fase 5 — Integração funcional

Integrar execução, rastreamento, etiquetas e visualização.

**Critério de aceitação:** executar um programa Forth real, visualizar os estados e acompanhar automaticamente etiquetas em operações suportadas.

### Fase 6 — Estruturas de controle

Ampliar o rastreamento para condicionais, loops e execuções repetidas.

**Critério de aceitação:** apresentar os estados do caminho efetivamente executado, permitindo distinguir ocorrências diferentes da mesma linha.

### Fase 7 — Extensibilidade

Documentar a interface dos motores e avaliar integração com pForth.

A implementação efetiva do suporte a pForth dependerá de uma decisão posterior.

---

## 10. Requisitos não funcionais

### Desempenho

O plugin não deverá bloquear a interface do Neovim durante a execução ou o processamento de registros extensos.

O histórico deverá possuir limites configuráveis para evitar crescimento descontrolado de memória.

### Confiabilidade

O encerramento inesperado do interpretador não deverá comprometer a sessão do Neovim.

Falhas de instrumentação deverão ser comunicadas ao usuário.

Estados incompletos não deverão ser apresentados como se fossem registros completos e confiáveis.

### Compatibilidade

A versão mínima do Neovim e as versões suportadas de Gforth deverão ser definidas e documentadas após os primeiros testes.

### Testabilidade

Os componentes de rastreamento, propagação de etiquetas e persistência deverão possuir testes independentes da interface.

A integração com o interpretador deverá ser testada com pequenos programas Forth reproduzíveis.

---

## 11. Questões técnicas em aberto

As seguintes questões deverão ser resolvidas durante a investigação inicial:

1. Qual mecanismo de Gforth permitirá registrar operações dentro de palavras compiladas?
2. Qual granularidade de instrumentação será viável: palavra-fonte, primitiva executada ou ambas?
3. Como obter estados confiáveis sem interpretar incorretamente valores que representam endereços, flags ou outros tipos?
4. Como rastrear palavras com efeitos de pilha variáveis?
5. Como reconstruir identidades em operações que manipulam a pilha de maneira não convencional?
6. Como associar etiquetas persistentes a valores criados em loops e chamadas repetidas?
7. Qual será o comportamento quando uma palavra não puder ser instrumentada?
8. Como controlar a quantidade de eventos gerados sem prejudicar excessivamente o desempenho?

Essas questões não deverão ser resolvidas por suposição.

---

## 12. Definição de sucesso

A primeira versão funcional será considerada bem-sucedida quando o usuário conseguir:

1. Abrir um programa Forth no Neovim.
2. Executá-lo utilizando Gforth por meio do plugin.
3. Visualizar estados intermediários da pilha ao lado do código.
4. Atribuir uma etiqueta a um elemento.
5. Observar essa etiqueta acompanhar transformações suportadas.
6. Observar a remoção da etiqueta quando o elemento for consumido sem preservação de identidade.
7. Fechar e reabrir o arquivo mantendo as etiquetas persistidas separadamente.
8. Realizar essas operações sem modificar a linguagem ou inserir anotações no código-fonte Forth.

O resultado deverá ser uma ferramenta de programação que torne o fluxo de dados de Forth visível, preservando a simplicidade e a natureza da linguagem.
