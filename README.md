# forthstackplugin

Projeto de um plugin Neovim para visualizar a pilha de programas Forth.
A especificação está em [SPEC.md](SPEC.md); o plugin ainda não foi implementado.

O [protótipo de instrumentação](doc/gforth-instrumentation.md) executa uma
palavra compilada no Gforth e produz JSON com estados intermediários da pilha,
arquivo, linha e coluna, sem alterar o arquivo Forth.

Requisitos validados: Linux x86-64, Gforth 0.7.3 e Python 3, sem pacotes Python
adicionais. Na raiz do repositório, com `gforth` no PATH:

```sh
python3 prototype/trace.py examples/compiled.fs example
python3 -m unittest discover -s tests -v
```

O exemplo registra a transformação `15 → 16` dentro de `birthday`, segue o ramo
executado e três iterações do loop, terminando com `[21]`.
Consulte a [investigação](doc/gforth-instrumentation.md) para o protocolo,
experimentos com o debugger nativo, comandos deste ambiente e limitações.
