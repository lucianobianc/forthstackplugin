# Symbolic stacks and diagnostics

## Two kinds of state

Runtime annotations show actual Gforth integer cells at top-level execution
sites. A definition is analyzed separately from its callers, starting from the
names in its documented stack effect. Symbolic annotations explicitly say
`symbolic` or `symbolic inputs`; no numeric test inputs are invented and this
analysis never executes Forth. Definitions do not need to be called.

```forth
: eligible ( age -- allowed )  \ [ age ]  symbolic inputs
  18                          \ [ age, 18 ]  symbolic
  >=                          \ [ allowed ]  symbolic
;
```

The annotations above are illustrations; the plugin uses virtual text and never
inserts comments. Names before `--` seed the data stack from left to right, with
the top on the right. Each name represents one cell. The output names label the
final positions only when the analyzed output count matches the declaration.
This checks depth, not the meaning of the returned values or their types.

A stack-effect comment must follow the name in a standard colon definition,
before body operations; intervening comments and newlines are allowed. Names
are whitespace-separated and at most 64 bytes each. Definitions without such a
contract have no symbolic annotation. Runtime `( LABEL: age )` comments remain
independent of these symbolic names.

`ForthStackAnalyze` performs one analysis without starting Python or Gforth and
pauses ongoing execution. `ForthStackRun` resumes tracing and automatic analysis
on edits. The `symbolic` setup option defaults to true; false disables automatic
analysis, while an explicit Analyze command still works. Toggle/Clear also
hide/remove symbolic annotations. No default keys are assigned.

## Supported analysis

- Integer literals, true/false, basic arithmetic, comparisons, and bit operations.
- `dup`, `drop`, `swap`, `over`, `rot`, `nip`, `tuck`, `2dup`, and `2drop`.
- `1+`, `1-`, basic unary arithmetic, `.`, `emit`, `cr`, and `noop`.
- Calls to earlier definitions with declared fixed data-stack effects. If an
  output name is also an input name, its caller symbol is preserved; other
  outputs take their declared names. Matching names preserve naming, not a
  guarantee that a numeric value is unchanged. Callee contracts are assumptions,
  not a proof that those definitions are correct.
- Nested `if`/`else`/`then` with equal output depths. Unequal depths warn and stop
  the analysis. Different values at a joined position become `?`.

Definitions are analyzed independently, without values left by top-level code.
In mixed lines, a real top-level observation has display priority. Inline display
and Inspect can still select a symbolic operation by its byte position.
Explicit named-word execution may display body observations without symbolic
coverage, marked `last call`.

## Conservative boundaries

Analysis stops at an unsupported operation and emits an informational diagnostic;
its known prefix may remain visible, but later states and final output names are
not fabricated. Loops, recursion, return/floating stacks, memory operations,
strings/parsing words, locals, early exits, and value-dependent effects such as
`?dup` are not analyzed. Double-cell literals are not treated as single cells.
Variadic and alternative stack-effect notation is unsupported. Use one explicit
name per cell, including both halves of double-cell inputs.

This is a bounded source analyzer for standard colon definitions, not Gforth's
compiler. Standard comments and common quoted-string/name syntax are skipped by
the lexer. In-file redefinitions shadow builtin rules, and immediate words do
not supply ordinary call contracts. Recognized includes, evaluation, search-order
changes, and dynamic execution stop analysis of subsequent definitions because
the dictionary may have changed. Arbitrary custom parsers, generated code,
compiler extensions, and unrecognized dynamic dictionary changes cannot be
modeled reliably. An annotation is not a general correctness guarantee.

Limits: 4 MiB of source, 50,000 lexical tokens, 256 symbolic cells, and bounded
expression text. Limits and incomplete definitions produce notices. Symbolic
analysis follows the existing update delay and is available even when the
subsequent runtime launch fails dependency validation.

## Diagnostics and failed executions

Neovim diagnostics use separate namespaces for static analysis and execution:

- Warning: a documented contract lacks inputs for an operation, output depth
  differs from the declaration, or branches leave incompatible depths.
- Information: analysis cannot continue safely with the supported subset.
- Error: an actual execution failure, including Gforth stack underflow (-4),
  unknown word (-13), and other runtime/compiler failures.

Runtime diagnostics point at the outer active top-level call, while the message
retains the internal failing token and position. Compile failures point at the
failing compilation token. If a source position cannot be matched to this buffer,
a summary is attached to its first line rather than inventing an exact token.
Colors come from Neovim's diagnostic highlight groups and the active theme.
Use `vim.diagnostic.open_float()` or normal diagnostic navigation to read them.

After a validated Forth failure, successful observations from the same snapshot
can be shown with `before error`. No state is invented for the failed operation,
and the status remains `error`. Partial observations are also marked in inline
and Inspect views. Timeout, process, malformed-protocol, and incomplete-result
failures do not expose partial runtime states. Failed JSON imports are still
rejected. A fresh edit invalidates old observations and diagnostics; the next
successful run clears the execution error. Unrelated plugins' diagnostics are
never reset.
