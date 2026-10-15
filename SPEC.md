# Forth Stack Visualizer for Neovim

**Project specification — Version 0.2**

- **Status:** Working experimental implementation; supported behavior and roadmap.
- **Editor and platform:** Neovim 0.10 or later, primarily Linux.
- **Implementation:** Lua interface and symbolic analysis; Python supervisor and
  identity tracking; Gforth instrumentation.
- **Execution engine:** Gforth, tested with 0.7.3 on Linux x86-64 and Neovim 0.10.4.
- **Future engine candidate:** pForth; not implemented.

This revision replaces the initial proposal where product decisions changed.
Automatic file execution, optional token-level inline display, source-comment
labels, symbolic stack effects, and Neovim diagnostics are part of the current
scope. Interactive labels and companion metadata files remain future options.

## 1. Purpose and principles

Make Forth data flow visible beside the code without modifying the buffer or
inventing concrete inputs for definitions. Runtime states come from a real Forth
engine; symbolic definition states come from a separate bounded analyzer.

1. Preserve source text and ordinary Forth syntax and execution semantics.
2. Use native Neovim virtual text, extmarks, floating windows, and diagnostics.
3. Distinguish actual execution, symbolic assumptions, and incomplete results.
4. Require little configuration and impose no default keybindings.
5. Propagate labels conservatively; equal values do not prove equal identities.
6. Keep execution, trace validation, symbolic analysis, and presentation separate.
7. Document unsupported operations instead of promising complete Forth coverage.

Execution is not a sandbox. Instrumentation and analysis have explicit limits;
using the real interpreter does not imply every operation is observable.

## 2. User experience

### 2.1 Defaults and execution lifecycle

Opening a named `.fs` file starts file-mode tracing by default. Automatic work
is deferred in Insert/Replace mode. After edits outside that mode, or after
leaving it with pending changes/work, a 350 ms debounce schedules the latest
unsaved snapshot. Included files are read from disk. The user file is never saved by the
plugin; a new buffer may run if its name belongs to an existing directory.

- `ForthStackRun` executes the file and enables updates for that buffer.
- `ForthStackRun word` loads the file, then calls that word once more. This is
  additional execution, not an isolated invocation of the word's definition.
- `ForthStackStop` pauses the current buffer; Run resumes it.
- `ForthStackAutoToggle` switches automatic `.fs` tracing for the session,
  pausing or resuming eligible buffers.
- Stop/Clear remain paused when a buffer is reentered or reloaded. Renaming or
  closing a buffer disarms its existing tracking.
- `auto_start = false` disables automatic startup. `auto_update = false`
  independently disables reruns after edits; an initial automatic run may still
  occur when auto_start is enabled.

Entering Insert/Replace mode suspends pending automatic timers and cancels
automatic execution in flight; leaving reschedules one latest update. Entering
and leaving without edits or pending work must not rerun the program. Stop/Clear
must cancel deferred work too. Explicit commands remain available in Insert mode;
they are not treated as automatic updates. One-time automatic startup with
`auto_update = false` follows the same deferral rule.

Every runtime update repeats the program's effects, including I/O. Each edit
invalidates old observations and cancels the previous run, including during
Insert mode. Automatic symbolic/inline updates and new diagnostics are also
deferred until editing mode ends. Filename, changedtick,
and run-identity checks reject late results. Automatic failures do not generate
repeated notification popups while typing.

### 2.2 Runtime line annotations

File-mode end-of-line annotations follow top-level execution. A definition must
not appear to have executed when it was merely declared. Operations inside its
body must not inherit unrelated top-level values as symbolic inputs.

The comments on the right below illustrate generated virtual text:

```forth
: birthday 1+ ;
16                 \ [ 16 ]  after 16
birthday           \ [ 17 ]  after birthday
```

The data-stack top is on the right. Runtime cells are displayed as integers;
flags, addresses, and value types are not automatically inferred. In particular,
Forth false/true values appear as `0` and `-1`, not inferred typed booleans.

Repeated executions retain observations in execution order. The current display
selects the latest relevant observation; selecting an earlier occurrence is not
yet implemented.

Explicit named-word runs may show concrete body observations where symbolic
coverage is unavailable, marked `last call`. Inspect and inline views can also
reveal recorded body observations with that marker. A mixed line containing both
a definition and top-level execution gives display priority to its top-level
state. Legacy imported traces without source-word metadata retain their previous
presentation because the missing context cannot be reconstructed reliably.

### 2.3 Optional inline display

Continuous inline display is off by default. It selects the token containing the
cursor using byte positions, then shows the state immediately after that token.
Source text is never changed.

- `ForthStackInline` requests a one-time display until the cursor moves. When no
  analysis/trace state is available, it runs the file once without enabling
  ongoing updates. It uses an existing selected entry when tracking one.
- `ForthStackInlineToggle` toggles continuous inline display for the buffer.
- Documented definitions prefer symbolic token states; other tokens use recorded
  execution. Unexecuted tokens without symbolic coverage have no state to show.
- Whitespace has no token state. Repeated runtime tokens use their latest event.
- If that exact observation is already visible at the end of the line, inline
  display must not duplicate it. Equal values at a different token are not enough
  to suppress its inline state. A hidden end-of-line annotation does not suppress
  a one-time inline request.
- Annotations are buffer-scoped and shared by windows displaying that buffer.

### 2.4 Inspect and diagnostics

`ForthStackInspect` opens a nonfocused floating window for the selected token,
falling back to the latest relevant observation on the line. It includes stack
contents, observation context, and runtime identities/copy origins when present.
Editing invalidates the view. There is no occurrence-navigation UI yet.

Diagnostics use native Neovim severity and highlight groups, including red errors
in standard themes. They do not reset unrelated plugins' diagnostics. The full
message is available through normal diagnostic floats/navigation; execution
status and errors are also available through `ForthStackStatus`.

## 3. Runtime labels and identities

Users assign a label to the current top cell with an ordinary, same-line Forth
comment. The tracer observes that comment's execution position:

```forth
17 ( LABEL: age )   \ [ age:17 ]  label age
dup                \ [ age:17, age:17 ]  after dup
1+                 \ [ age:17, age:18 ]  after 1+
18 >=              \ [ age:17, -1 ]  after >=
```

The uppercase marker `LABEL:` is followed by a 1–64 character ASCII name matching
`[A-Za-z_][A-Za-z0-9_-]{0,63}`. The comment must close on the same line. Strings
and ordinary comments do not create annotations. Invalid recognized names and
labels applied to an empty runtime stack report an error.

The plugin never writes these comments. They persist because the user saves
normal Forth source; IDs are reconstructed on every run. No interactive
`ForthStackLabel` command or companion metadata file is currently implemented.

For annotated runs, each event can contain elements with `id`, `value`, optional
`label`, and optional immediate copy `origin`. IDs belong to one run. Previous
snapshots remain immutable; the event stream supplies observation history rather
than a separate persistent history field on each element.

- `dup`, `over`, and `tuck` create distinct copy IDs and retain origin links.
- `swap`, `rot`, `nip`, and `drop` move or remove the appropriate identities.
- `1+`, `1-`, and recognized literal unit-offset forms preserve the label/ID.
- Comparisons consume operand identities and create unlabeled results.
- Other supported arithmetic creates fresh result identities while preserving
  untouched lower cells.
- Traced user calls use their observed internal operations. Unknown precompiled
  calls, opaque macros, and unexplained mismatches clear identities conservatively.

Runtime primitive rules use original execution tokens, not merely source names.
Matching numbers or stack depths never suffices to infer identity preservation.
See [label rules](doc/labels.md) for exact propagation and resynchronization rules.

## 4. Independent symbolic definition analysis

Automatic symbolic analysis is on by default and does not execute Forth. A fixed
stack-effect comment immediately after a definition's name supplies its inputs
and intended outputs; intervening comments/newlines are allowed.

```forth
: can-drive ( age -- allowed )  \ [ age ]  symbolic inputs
  18                           \ [ age, 18 ]  symbolic
  >=                           \ [ allowed ]  symbolic
;
```

`( name age id -- status )` seeds `[ name, age, id ]`, independently of the
rest of the program. Each name represents one data-stack cell. Definitions need
not be called. When complete analysis produces the declared output depth, its
final positions receive the declared output names. This validates depth, not
value meaning or types. Symbolic names are separate from runtime LABEL identities.

The supported subset includes integer literals, basic stack/arithmetic/comparison
operations, earlier declared fixed contracts, and nested `if`/`else`/`then`.
Branches must leave equal depths; different values at a joined position become
`?`. Calls use declared contracts as assumptions, not proofs of callee correctness.

Unsupported words, loops, recursion, value-dependent effects, non-data stacks,
custom parsing, and recognized dictionary changes stop analysis with a notice.
A known prefix may remain visible; later states and verified output names must
not be fabricated. Insufficient documented inputs, output-depth mismatches, and
incompatible branch depths produce warnings. Definitions without usable contracts
have no symbolic states. In-file redefinitions shadow builtin rules.

`ForthStackAnalyze` performs one analysis without Python/Gforth, pauses ongoing
execution, and sets status to `analyzed`. Run resumes execution. The `symbolic`
option controls automatic analysis; an explicit Analyze command still works.

This is a bounded source analyzer, not a complete Forth compiler or type checker.
See [symbolic analysis](doc/symbolic-analysis.md) for grammar, assumptions,
unsupported syntax, limits, and warning semantics.

## 5. Runtime failures and partial observations

An actual Gforth failure must produce an error diagnostic. In file mode, the
location identifies the active outer top-level call; the message retains the
internal failing token. For example, calling `can-drive` on an empty stack marks
that call with `Stack underflow`. Compile failures use the failing compilation
site. Unmatched source locations produce a first-line summary, not an invented
exact token location.

Successful observations from the current snapshot before a validated Forth
failure may remain visible, explicitly marked `before error` in line, inline,
and Inspect views. Status remains `error`; the failed operation gets no invented
after-state. Symbolic definition analysis stays independent of that failure.

Timeouts, malformed protocol, incomplete results, and process failures do not
expose partial runtime states. Imported failed JSON traces are rejected. Edits
invalidate old observations and diagnostics; correcting the program and rerunning
clears execution errors. Manual execution failures may also notify the user.

## 6. Commands, setup, and keys

| Command | Current behavior |
| --- | --- |
| `ForthStackRun [word]` | Run a file snapshot, optionally call a word, follow edits |
| `ForthStackAnalyze` | Analyze documented definitions once without execution |
| `ForthStackStop` | Pause/cancel execution for this buffer |
| `ForthStackAutoToggle` | Toggle session-wide automatic `.fs` tracing |
| `ForthStackInline` | Request one inline observation until the cursor moves |
| `ForthStackInlineToggle` | Toggle continuous inline display for this buffer |
| `ForthStackInspect` | Inspect the selected token or line in a float |
| `ForthStackToggle` | Hide/show recorded and symbolic stack annotations |
| `ForthStackClear` | Clear owned views/diagnostics and pause tracking |
| `ForthStackStatus` | Open complete status/error details in a text window |
| `ForthStackLoad path.json` | Import a validated successful trace; pause updates |
| `ForthStackDemo` | Open a bundled example and recorded trace without execution |
| `checkhealth forth-stack` | Check Neovim, executables, and installed runtime files |

Setup is optional with normal native packages. Explicit `setup()` also registers
commands when startup discovery was skipped. Native package and lazy.nvim
installation paths are documented in the README.

| Setup option | Default | Constraint or meaning |
| --- | --- | --- |
| `python` | `python3` | Executable name/path, no shell arguments |
| `gforth` | `gforth` | Executable name/path, no shell arguments |
| `timeout` | `5` | Positive seconds, at most 60 |
| `max_events` | `10000` | Integer, 1–10000 |
| `max_depth` | `256` | Integer, 1–256 runtime cells |
| `symbolic` | `true` | Automatic symbolic definition analysis |
| `auto_start` | `true` | Automatic startup for `.fs` files |
| `inline` | `false` | Initial continuous-inline preference |
| `auto_update` | `true` | Updates after editing an armed buffer |
| `debounce_ms` | `350` | Integer automatic update delay outside Insert/Replace mode, 1–5000 ms |

No global or buffer-local keybindings are installed by the plugin. Users may
configure them normally; suggested Forth-local mappings are `<localleader>s`
(one-time inline), `<localleader>i` (inline toggle), and `<localleader>r` (Run).
Existing user/plugin mappings must be considered. Optional which-key integration
comes from normal mapping descriptions; a custom shortcut-configuration screen
is not part of current scope. The README supplies a buffer-local example.

## 7. Execution, trace protocol, and bounds

Gforth compile/interpreter hooks insert in-memory observation probes, including
inside user-defined compiled words. A Python supervisor runs in a separate
process, receives the unsaved snapshot on stdin, and loads a private temporary
copy under the original source identity. Arguments are passed without a shell.

The trace contains ordered entry/before/after/return events, source file, line,
one-based byte column, token, containing word, and numeric stack. Label/opaque
identity events extend that information when required. Source word metadata
separates top-level execution from body observations. This is source-token
instrumentation, not guaranteed tracing of every executed primitive.

- JSON format 1 preserves numeric traces; format 2 adds element identities.
- Gforth failures may supply an additive `error_location` for diagnostics.
- Import validates format, event sequence, integer range, source positions and
  matching tokens; version 2 also validates element identities and labels.
- Source validation is not a whole-file checksum. Live runs additionally use
  buffer changedtick/filename checks.
- Source snapshots and received/imported JSON are limited to 4 MiB.
- Lua presentation rejects runtime integers outside ±(2^53−1) to avoid rounding;
  full-width Gforth cells are not silently approximated.
- Symbolic limits are 4 MiB, 50000 lexical tokens, 256 cells, bounded expressions,
  and 64-byte stack-effect names. These are independent of runtime max_depth.
- stdout/stderr are captured in memory; a dedicated program-output panel and
  preemptive bounded output capture are not implemented.
- Stop terminates the supervisor and its direct Gforth child. Descendants started
  by the program are not managed as a process tree.

Runtime execution is asynchronous. JSON processing and symbolic analysis are
bounded but run on Neovim's thread; absence of pauses for all large inputs has
not been established. Unsaved included-file buffers do not participate in source
snapshots, and their edits do not trigger automatic reruns of dependents.

See [Gforth investigation](doc/gforth-instrumentation.md),
[display and protocol](doc/neovim-display.md), and the prototype for exact
instrumentation coverage and implementation details.

## 8. Implemented architecture

```text
lua/forth-stack/
  init.lua          buffer lifecycle and public operations
  config.lua        validated setup options
  commands.lua      Neovim commands
  engine.lua        asynchronous supervisor launch and cancellation
  live.lua          per-buffer debounce and update lifecycle
  trace.lua         trace import, validation, source associations
  display.lua       runtime/inline annotations and Inspect
  symbolic.lua      bounded source analysis and symbolic annotations
  diagnostics.lua   source-linked runtime diagnostics
  health.lua        health checks
  paths.lua         installed runtime paths
plugin/forth-stack.lua  native startup registration
prototype/
  trace.fs          Gforth observation hooks
  trace.py          process supervision and structured trace production
  labels.py         conservative runtime identities and label propagation
  investigate.py    instrumentation research probes
```

There is no implemented generic backend registry, companion-file persistence
module, or separate Lua identity engine. Engine extensibility remains a design
goal; Gforth hooks must not be assumed portable to pForth.

## 9. Acceptance and verification

The existing `tests/run.sh` is the reproducible validation entry point, requiring
Python 3, Gforth, and Neovim on PATH. Tests cover:

- Real compiled-word and top-level tracing, source mapping, loops/branches,
  limits, timeouts, unsaved snapshots, and execution failures.
- Identity/copy provenance, labels, conservative opaque-operation behavior.
- Native installation, explicit setup, demo, health, imports, asynchronous
  execution, cancellation, debounce, reloads, and stale-result rejection. Real
  Insert-mode tests verify deferred updates, pending/in-flight cancellation,
  resumption, Stop behavior, and explicit-command exceptions.
- Cursor-token selection, symbolic/runtime priorities, duplicate suppression,
  one-shot requests, optional inline mode, and automatic-start defaults.
- Symbolic contracts, permutations, branch joins, mismatches, unsupported
  operations, source/dictionary boundaries, and resource-limit notices.
- Call-site error diagnostics, partial observations, recovery, analysis without
  executing Forth, and preserving other plugins' diagnostics.

The implementation has been validated locally with the documented versions.
An automated CI/version compatibility matrix is not currently checked into the
repository; broad compatibility is not established by the minimum-version claim.

## 10. Remaining work and priorities

These items are not implemented or are only partially covered. They are roadmap
items, not claims about current behavior.

| Priority | Work | Acceptance target |
| --- | --- | --- |
| Near term | CI and compatibility matrix | Run the suite automatically on changes; verify supported Neovim/Gforth versions |
| Near term | Observation-history navigation | Select earlier loop/call occurrences and distinguish invocation context |
| Near term | Broader symbolic coverage | Add operations and selected loop/exit handling with explicit soundness boundaries and regression tests |
| Hardening | Performance/output/process limits | Profile large files/traces, bound capture earlier, evaluate descendant cleanup |
| Hardening | Included-file workflow | Define dependency tracking, unsaved includes, and source validation across files |
| Later | Wider value representation | Preserve full cell precision and explicitly supported floating/return stacks or typed displays |
| Optional | Interactive labels and external metadata | Relabel without source edits and restore associations reliably after reopening/moving code |
| Optional | User-defined propagation rules | Declare semantics without confusing equal values, types, and identity |
| Optional | Engine adapters and pForth investigation | Define a backend contract and demonstrate equivalent observation capabilities |

Interactive labels and companion JSON were proposed initially but superseded
for the first working version by ordinary source comments. They are not required
to preserve today's labels across saves/reopens. A custom keybinding screen is
not planned; native mappings and optional which-key remain the integration path.

Complete static analysis, universal Forth-extension support, perfect semantic
inference, multiple Forth tasks, and a standalone GUI remain outside scope.

## 11. Definition of the working baseline

The baseline is met when a user can install the plugin, open a `.fs` program,
observe real top-level stack evolution, inspect intermediate tokens, track labels
through supported operations, understand documented definitions symbolically,
and find execution errors at their source calls without the plugin writing to
the buffer. Saved ordinary label comments survive reopening; no companion-file
persistence is implied. Unsupported cases must be distinguishable from verified
observations, and failed/incomplete runs must never be presented as complete.
