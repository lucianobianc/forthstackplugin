# Gforth instrumentation investigation

Experimental implementation of phase 1 of `SPEC.md`. Tested on Linux x86-64,
Gforth **0.7.3**, with Python 3 as supervisor. The prototype remains usable on
its own; the [plugin](neovim-display.md) now uses it for explicit execution.
Compatibility with Gforth development versions has not been verified.

## Mechanisms investigated

The sources shipped with Gforth 0.7.3 were inspected, especially `debug.fs`,
`debugs.fs`, `see.fs`, `source.fs`, `backtrac.fs`, `kernel/int.fs`,
`kernel/comp.fs`, and `kernel/require.fs`. In the local installation they are in
`/workspace/.cloud-setup/root/usr/share/gforth/0.7.3/`.

| Feature | Evidence and purpose | Limitation for this project |
| --- | --- | --- |
| `.s`, `depth`, `sp@` | `.s` preserves elements and shows `<1> 15`, then `<1> 16`, when called inside a definition | Requires observation points; does not itself provide events or locations |
| `~~`, `printdebugdata`, `.debugline` | Compiled `~~` prints file, line, and stack to stderr; actions are deferred | An explicit source probe, not automatic tracing of every word. The default action uses shared numeric-conversion storage |
| `current-sourcepos`, `compile-sourcepos` | Capture file/line at compile time; `compile-sourcepos` compiles these as literals | Not a retroactive map of every instruction address; no column information |
| `see`, `xt-see` | `see sample` decompiled `: sample 15 1+ ;` | Reconstructs code, not the executed sequence or stack states; does not recover original text and positions |
| `dbg`, `break:`, `break"` | `debug.fs` provides stepping, call nesting, and breakpoints; `dbg` and `break:` were run with `gforth-itc` | Interactive, textual address-based output, engine-dependent; no structured source-location events |
| `catch`, `throw`, backtrace | An uncaught exception showed its code and call chain | A backtrace is not state history. `catch` restores the protected stack, not the stack at the instant of failure |
| `before-word`, `parser1`, `compiler1` | Intercept tokens while the text interpreter compiles a definition | Gforth-specific interfaces; the hook does not run for every operation inside an already compiled word |
| `compile,` | Deferred compiler extension point with primitive translation and optimizations | Not equivalent to a source token: literals, inline payloads, branches, and immediates need special handling. Not used as a universal tracer |

`dbg sample` using the **default gforth executable** failed on the first literal
with `Invalid memory address`, process code 1. The same program using
**gforth-itc** returned code 0 and displayed empty, `15`, and `16` stacks.
This matches the ITC dependencies explicitly noted in `debug.fs`, including
`breaker-size`, `set-bp`, and `restore-bp`. This result must not be generalized
to every Gforth version or engine. `--debug` prints startup diagnostics, not an
application execution trace.

In the Debian image used here, `dbg`, `~~`, and `see` are already available.
Repeating `require debug.fs` with relocated source paths can reload dependencies:
`required` compares names/paths, and relative names recorded in the image differ
from local absolute paths. This experiment produced redefinitions and a
`search.fs` error. Reproducible tests use the words already in the image without
reloading the package.

## Decision and implementation

The prototype combines **in-memory compile-time probes** with text-interpreter
observations during loading. The Forth file is included normally, without a
preprocessor, disk rewriting, or source annotations:

1. The Python supervisor starts Gforth and opens a separate temporary protocol
   channel. Program stdout/stderr are preserved as separate result fields.
2. During `included`, `before-word` replaces `parser1` only when its current
   action is `compiler1` or `interpreter1`. The previous hook is called and restored
   after loading. Interpreter actions are wrapped in snapshots; parser arguments
   do not appear in the observed stack.
3. For ordinary tokens and literals, the wrapper captures file, line, column,
   definition name, and token text, emits a `before` call, delegates compilation
   to `compiler1`, and emits an `after` call.
4. Immediate words are still compiled/executed by Gforth without their own probes.
   They are recorded as `coverage: "opaque"`; other sites have `coverage: "probe"`.
   Comments and delimiters may also appear in the map.
5. Collection starts before loading, pauses during compilation, and resumes when
   a definition closes. Top-level interpreted code and probes inside called
   bodies therefore produce one chronological sequence. File mode ends after
   loading; word mode supplies integer inputs and makes the additional call.
   The whole session is protected by `catch`.
6. Each probe observes the stack through `depth`/`sp@` without removing elements.
   Numbers use a private decimal converter, avoiding `BASE`, `PAD`, and the
   shared `<# ... #>` storage. The channel is flushed after each event to retain
   execution prefixes on interruption.

Operations are not statically interpreted: values come from real Gforth execution.
Conditional paths, loop indices, and occurrence counts are observed at runtime.
Probes add calls and change in-memory code; this does not guarantee transparency
for every Forth program.

## Run it

With `gforth` on PATH, from the repository root:

```sh
python3 prototype/trace.py examples/compiled.fs example
python3 -m unittest discover -s tests -v
python3 prototype/investigate.py --gforth gforth --gforth-itc gforth-itc
```

In the prepared cloud environment, before the first two commands:

```sh
export PATH="/workspace/.cloud-setup/bin:$PATH"
cd /workspace/forthstackplugin
```

To also reproduce the ITC comparison with this relocated installation:

```sh
LD_LIBRARY_PATH=/workspace/.cloud-setup/root/usr/lib/x86_64-linux-gnu \
GFORTHPATH=.:/workspace/.cloud-setup/root/usr/lib/x86_64-linux-gnu/gforth/0.7.3:/workspace/.cloud-setup/root/usr/share/gforth/0.7.3 \
python3 prototype/investigate.py \
  --gforth /workspace/.cloud-setup/bin/gforth \
  --gforth-itc /workspace/.cloud-setup/root/usr/bin/gforth-itc
```

`investigate.py` records experiment results, including expected failures of the
default debugger and uncaught `throw`. Its exit code does not replace the test
suite. No Python packages need to be installed.

CLI options include `--gforth PATH`, repeated `--input N`, `--timeout SECONDS`,
`--max-events N`, and `--max-depth N`. Defaults: 5 seconds, 10,000 events, and
256 cells per snapshot. Timeout covers compilation and execution.

## Demonstrated result

`examples/compiled.fs` defines `birthday` and `example` without source probes.
Its result includes these real events:

| seq | phase | definition/token | source (line:column) | stack |
| --- | --- | --- | --- | --- |
| 3 | before | example / birthday | 8:3 | `[15]` |
| 4 | before | birthday / 1+ | 3:3 | `[15]` |
| 5 | after | birthday / 1+ | 3:3 | `[16]` |
| 6 | after | example / birthday | 8:3 | `[16]` |

The true branch is not executed; the `else` branch produces `18`. The loop records
three occurrences of `i`: `0`, `1`, and `2`. The final stack is `[21]`.
This demonstrates observations **inside** a compiled word, not merely between
top-level interpreted lines.

## Protocol and event meaning

The supervisor returns JSON containing `format_version: 1`, `sites`, `events`,
`status`, `complete`, `forth_code`, `process_returncode`, `stdout`, `stderr`, and
`diagnostic`. `complete: true` means execution ended normally, not that every
primitive or immediate word was instrumented.

Each event contains `seq`, `site`, `phase`, `source`, and `stack`:

- `before` / `after`: snapshots immediately before/after a probed token. Calls
  have inclusive effects; events from their definitions can occur between the
  pair. A `throw`, `exit`, or interruption may leave an operation without `after`.
- `entry` / `return`: session boundaries (loading and optional additional call),
  with `site: 0` and `source: null`. No artificial location is assigned to them.
- `stack`: signed decimal integer cells from bottom to top; top on the right.
- `source`: Gforth's filename, 1-based line and **byte** column, token, and
  definition name. `site` identifies a location within this load; `seq`
  distinguishes chronological occurrences, including loop iterations.

`sites` also includes unexecuted tokens and opaque immediates. Missing events do
not imply an error. Sites and events are linked by site ID, not numeric stack
value. There are no instance IDs, labels, or provenance yet.

The internal channel uses `M` lines (metadata with hex-encoded strings), `E`
(event: sequence/site/phase/depth/cells), and `X` (`catch` result). `X` accepts a
code and an optional 0/1 field indicating failure during compilation. Omission
preserves compatibility with older records. This context identifies the last
compiled token without treating it as an execution snapshot.

The parser checks sequence, depth, site references, and the final marker.
Truncated output or execution without a result is not reported as success.
`forth_code: -4096` means the event limit was exceeded; `-4097` means excessive
stack depth. Timeout, process failure, early `bye`, and Forth errors are distinct.
JSON retains valid event prefixes on errors/timeouts; invalid protocols are
rejected without reusing ambiguous snapshots.

## Limitations and further investigation

- **Granularity:** ordinary source tokens and literals, not every VM primitive.
  `if`, `else`, `then`, loops, `exit`, `recurse`, strings, and other immediates
  lack their own probes. Effects appear in later observations; `recurse` can
  enter a probed body. With an opaque segment between events, not every change
  can be attributed to the last visible operation.
- **Preexisting code:** image words and already-loaded libraries are observed
  at call boundaries only. New definitions included while loading have visible
  internals; code compiled later during execution does not automatically receive
  probes. There is no retroactive instrumentation.
- **Metaprogramming:** general support is not validated for `postpone`/`compile,`
  macros, custom compilers, `parser1` replacement, defining words, `does>`, locals,
  search-order changes, or `evaluate`. Probes inside an immediate definition
  executed during compilation have collection disabled; this does not make its
  expansion traceable. No general coverage is claimed for these APIs.
- **Source:** positions come from the input buffer at compilation/interpretation,
  not DWARF or a persistent instruction map. Included files retain their origin;
  virtual/evaluated sources may lack valid locations. UTF-8 columns count bytes,
  not visual columns. Later edits invalidate the map; IDs are not stable between
  runs. Definition names come from `latest`, suitable for the tested `:` subset.
- **Data:** addresses, flags, integers, and parts of double-cell values are not
  distinguished. Pointed-to memory, floating-point stacks, locals, and the return
  stack are not inspected. Positions and values do not establish semantic identity.
- **Transparency:** probes alter code size/addresses, timing, I/O, and temporary
  stack usage. Programs inspecting VM internals or depending on these details
  may behave differently. Avoiding known numeric-conversion interference does
  not prove universal transparency.
- **Failures:** no snapshot is guaranteed at a `throw`/signal, only the last
  emitted event. The stack restored by `catch` is not exported as fault-time
  state. Exceptions caught by the program may never reach the supervisor; it
  reports the result escaping the protected session.
- **Resources:** snapshots cost O(depth) and perform synchronous I/O. Limits
  cover events and depth, not metadata or stdout/stderr volume, still captured
  in memory. Timeout terminates the direct Gforth process, not descendants
  launched by the program. This is neither a sandbox for untrusted files nor
  a collector suitable for large workloads.

A useful next experiment is to extend immediate/control-structure coverage with
specific rules, keeping source tokens distinct from VM primitives, and define a
protocol with explicit opaque boundaries and calls. Identity investigation and
later plugin stages remain separate work.

## Validation

The Python suite contains 24 integration/protocol tests and passed in this
environment. It checks real snapshots and positions, both conditional paths,
iterations, recursion, `exit`, stack operations, `>r`/`r>`, included sources,
separate output, numeric conversion, the minimum 64-bit cell, compilation/runtime
errors, missing entry, limits, timeout, and early `bye`. It also covers top-level
execution and unsaved snapshots. A stack-operation program is executed without
instrumentation to compare results. Fixtures are checked by SHA-256 before/after
execution. Reproducible native experiments confirmed `see`, `.s`, `~~`, backtrace,
`dbg`, and `break:` under the conditions described above.

## Extension: file execution

The entry word is optional in both the CLI and plugin. The `interpreter1` wrapper
records ordinary top-level tokens and literals using `<top-level>` in
`source.word`. `:` starts a compilation region without exposing compiler control
data; `;` closes it. Bracket interpretation inside a definition also keeps
collection disabled. Immediate words are delegated to Gforth without own probes.

The file loads once per session. In word mode, top-level code's stack effects
remain before the additional call. Uncalled definitions produce no execution
events. Compilation errors restore the outer parser before process termination;
incomplete definitions are reported as control errors (-22).
