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
the top on the right. Each name represents one cell. Fixed output counts are
checked against every surviving path. Unknown final positions receive the
matching declared output names; exact constants retain their numeric values.
This validates depth, not value meaning or types.

A stack-effect comment must follow the name in a standard colon definition,
before body operations; intervening comments and newlines are allowed. Names
are whitespace-separated and at most 64 bytes each. Inputs must have a fixed
count. The output side supports fixed names, `...` alone for unspecified outputs,
or alternatives separated by a standalone `|`, such as `( n -- 0 | n n )`.
If multiple declarations match one output depth, analysis does not arbitrarily
choose names. Definitions without such a contract have no symbolic annotation.
Runtime `( LABEL: age )` comments remain independent of these symbolic names.

`ForthStackAnalyze` performs one analysis without starting Python or Gforth and
pauses ongoing execution. `ForthStackRun` resumes tracing and automatic analysis
on edits. The `symbolic` setup option defaults to true; false disables automatic
analysis, while an explicit Analyze command still works. Toggle/Clear also
hide/remove symbolic annotations. No default keys are assigned.

## Known values and alternative stacks

The abstract interpreter tracks symbolic cells, exact constants, copies, and
zero/nonzero conditions. It never executes the Forth program to guess a result.

```forth
: maybe ( n -- ... )
  ?dup       \ [ 0 ] | [ n, n ]  symbolic
  1+         \ [ 1 ] | [ n, (n + 1) ]  symbolic
;

: known ( -- n n )
  2 3 +      \ [ 5 ]  symbolic
  ?dup       \ [ 5, 5 ]  symbolic
;
```

- `?dup` with zero keeps the top cell; with a known nonzero value it duplicates
  it. Otherwise it forks into zero and nonzero paths, preserving the prefix.
- `if`/`else`/`then` follows known conditions or retains both feasible branches.
  Different depths remain separate stacks, not a falsely fixed-depth join.
  A fixed output contract warns when any surviving depth is undeclared.
- Zero/nonzero facts follow copied cells. Tests such as `0=` and comparisons
  against zero can refine their original symbol through a branch. This is not
  a general numeric constraint solver: retained alternatives are a conservative
  approximation and may include combinations a stronger solver could exclude.
- Later operations execute abstractly on every path. If some paths underflow or
  divide by a known zero, diagnostics warn and those paths stop. Subsequent
  annotations say `valid paths only`; the failure is not silently discarded.
  If all paths fail, there is no invented after-state.
- An unknown effect is different from known alternatives: it emits an
  informational `Effect unknown` diagnostic and stops analysis, with no guessed
  cardinalities or later states. A known prefix can remain visible.

Line, inline, and Inspect views share the same alternatives. Identical formatted
stacks are displayed once without discarding internal path conditions. Inline
display still avoids duplicating the observation visible at the end of the line.
Line/inline text shows up to four different stacks and then a count/depth summary;
Inspect lists retained alternatives. Incomplete analysis never invents an
additional branch to represent unsupported behavior.

## Supported operations and calls

- Integer literals, true/false, basic arithmetic, comparisons, and bit operations.
- `dup`, `?dup`, `drop`, `swap`, `over`, `rot`, `nip`, `tuck`, `2dup`, and `2drop`.
- `1+`, `1-`, basic unary arithmetic, `.`, `emit`, `cr`, and `noop`.
- Standard `."` parses its same-line quoted text and preserves the data stack.
  Text inside the literal is not scanned as executable Forth. An unterminated
  string stops analysis. A redefined parsing word does not get its native rule.
- Earlier documented, supported bodies can be interpreted abstractly with caller
  arguments, propagating constants through user words without contaminating
  those definitions' own input-seeded annotations. Call bindings are retained
  across later redefinitions. Output-contract mismatches remain warnings; the
  supported body, rather than a knowingly wrong output count, supplies the shape.
- When a body cannot be analyzed but has a fixed/alternative contract, the caller
  can use the declaration as an explicit assumption. Such states say `contract
  assumed`. Named outputs are fresh unknown cells, even if their names match
  inputs. Literal output constraints are assumptions too. A flexible `...`
  declaration alone supplies no usable shape for an opaque call.

Constant folding is deliberately limited to exact integers within ±(2^53−1).
It covers safe `+`, `-`, `*`, increments/decrements, selected unary operations,
comparisons, min/max, signed-32-bit bitwise operands, selected nonnegative shifts,
and nonnegative division/modulo with positive divisors.
Recognized operations without safe folding retain expressions and may fork at
`?dup`; they do not round or invent overflow results. Folding targets the
tested 64-bit Gforth baseline; other cell widths and wrapping arithmetic outside
the safe range are not modeled. Standard decimal and
hex source-base switches and explicit numeric prefixes are recognized. Other
base/dictionary manipulations stop subsequent analysis conservatively.

## Counted loops

`do … loop` and `?do … loop` consume known integer bounds `( limit start -- )`
and analyze each iteration without executing Forth. Nested loops and their `i`
and `j` indexes are supported. Data-stack operations, conditionals, alternatives,
and supported calls continue inside the body. Symbolic input cells remain
independent of actual calls elsewhere in the file.

```forth
: total ( -- sum )
  0          \ [ 0 ]  symbolic
  3 0 do     \ [ 0 ]  symbolic
    i +      \ [ 3 ]  symbolic
  loop       \ [ 3 ]  symbolic
;
```

Here the observations after `+` are `[ 0 ]`, `[ 1 ]`, and `[ 3 ]`.
Line-end and cursor views use the most recent observation of a repeated token;
there is no iteration-history navigation yet. `?do` with equal bounds skips the
body. Ordinary `do` with equal bounds does not skip in Forth: it requires counter
wraparound, which this analyzer deliberately does not model. Starts above the
limit, unknown bounds, more than 256 iterations, `+loop`, `leave`, and other
unsupported loop controls stop analysis with an informational notice. Prior
observations can remain visible, but no final result is claimed. `i` or `j`
without enough enclosing supported loops also stops analysis. Helpers whose
bodies rely on a caller's loop context are not inferred from that context.

The 256-iteration limit applies to each loop invocation. Nested loops also share
the existing execution-step, observation, nesting, path, and cell budgets, so
large nested loops stop explicitly rather than monopolizing the editor.

## Conservative boundaries

Analysis stops at an unsupported operation and emits an informational diagnostic;
its known prefix may remain visible, but later states and final output names are
not fabricated. Unsupported loops, recursion, return/floating stacks, memory operations,
parsing words other than supported `."`, locals, early exits, and other
value-dependent operations are not analyzed. Double-cell literals are not
treated as single cells.
Variadic inputs, non-data-stack notation, and more complex contract syntax are
unsupported. Use one explicit name per input cell, including both halves of
double-cell inputs.

This is a bounded source analyzer for standard colon definitions, not Gforth's
compiler. Standard comments and common quoted-string/name syntax are skipped by
the lexer. In-file redefinitions shadow builtin rules, and immediate words do
not supply ordinary call contracts. Recognized includes, evaluation, search-order
changes, and dynamic execution stop analysis of subsequent definitions because
the dictionary may have changed. Arbitrary custom parsers, generated code,
compiler extensions, and unrecognized dynamic dictionary changes cannot be
modeled reliably. An annotation is not a general correctness guarantee.

Limits: 4 MiB of source, 50,000 lexical tokens, 50,000 abstract execution steps
across the source, 16 retained paths, call/control nesting of 16, 256 cells per
path, 10,000 observation events, 100,000 displayed cell snapshots, 4 MiB of
snapshot text, and expression text of at most 96 bytes (longer expressions become
`?`). Limits and incomplete definitions produce notices. Symbolic
analysis follows the existing update delay outside Insert/Replace mode. It is
deferred while typing, along with automatic execution and inline updates, and is
available even when the subsequent runtime launch fails dependency validation.

## Diagnostics and failed executions

Neovim diagnostics use separate namespaces for static analysis and execution:

- Warning: a documented contract lacks inputs for an operation, output depth
  differs from the declaration, or some/all alternatives underflow or divide by
  zero. Different branch depths alone are supported when outputs are flexible.
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
rejected. A fresh edit invalidates old observations and diagnostics, including while in
Insert/Replace mode. New automatic diagnostics wait until that mode ends; the next
successful run clears the execution error. Unrelated plugins' diagnostics are
never reset.
