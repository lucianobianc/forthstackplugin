# Phase 2 — Neovim visualization

The Lua layer displays version 1 and 2 JSON traces from the Gforth prototype using
extmarks and virtual text. Tested with Neovim 0.10.4 on Linux x86-64. It requires
no external Lua packages, mandatory configuration, or global shortcuts. Execution
starts with `ForthStackRun` and then updates automatically as you edit.

## Try it

From the repository root, with `gforth`, `python3`, and `nvim` on PATH:

```sh
python3 prototype/trace.py examples/compiled.fs example > /tmp/forth-stack.json
nvim --cmd 'set runtimepath^=.' examples/compiled.fs
```

In Neovim:

```vim
:ForthStackLoad /tmp/forth-stack.json
:ForthStackToggle
:ForthStackInspect
:ForthStackClear
```

To test without executing Forth, use the bundled test trace:

```vim
:ForthStackLoad tests/fixtures/compiled.json
```

In the prepared cloud environment, first run
`export PATH="/workspace/.cloud-setup/bin:$PATH"`.
For permanent installation, add the repository to runtimepath through your plugin
manager or Neovim's native package mechanism.

## Behavior

`ForthStackLoad` takes a JSON trace path and renders only events for the file in
the current buffer. Relative `source.file` paths are resolved from the JSON file's
directory; the prototype usually produces absolute paths. Symbolic paths are
normalized to their real location when possible. Session-boundary data is not
artificially assigned to a source line.

Each line receives its **latest `after` or `label` observation**, in chronological order:

```text
  1+                    [ 16 ]  after 1+
```

The top is on the right. If a line has multiple tokens or loop iterations, the
most recent observation wins. This **does not mean the state at the end of the
line**: immediate words and control structures may execute after the last probed
token. The `after TOKEN` suffix identifies the observation boundary. Numbers are
shown as integers; the plugin does not infer that `0` is false or a cell is an
address.

`ForthStackInspect` opens a floating window showing the full latest stack on the
cursor line, token, sequence number, and number of `after` observations on that
line. History is retained for future interface development, but selecting an
occurrence is not available yet. The previous inspection window closes on another
inspection, clear, toggle, edit, or rename of the source buffer.

`ForthStackToggle` hides and restores marks without discarding history;
`ForthStackClear` discards both. Other extmark namespaces remain intact. Any edit
invalidates the buffer's data, even while hidden. Reload static JSON traces
manually; a run started with `ForthStackRun` schedules a fresh collection after
typing. Renaming the buffer also invalidates its association.

Marks use `ForthStackValue`, linked to `Comment` by default, while respecting an
existing custom definition. Rendering, hiding, and clearing do not change Forth
text, the `modified` flag, or changedtick.

## Validation and limits

Traces with incomplete execution, errors, or unsupported versions are rejected.
The loader checks event sequence, stacks, phases, and token locations in the
current file. Validation errors preserve the previous visualization. An edit
will already have invalidated it through buffer tracking.

Initial source validation compares tokens, lines, and byte columns against the
buffer. **This does not prove that the whole program is identical**: changes
that leave the same tokens at the same positions may allow an old trace to pass.
Changes in auxiliary files are not detected either. Until a hash manifest covers
all sources, regenerate traces after program changes and do not treat traces
from different revisions as interchangeable.

Limits: 4 MiB JSON, 10,000 events, and 256 cells per snapshot. Loading is synchronous
and bounded; it is not designed for large traces. Integers outside ±(2^53−1) are
rejected because Neovim's LuaJIT decodes JSON numbers as doubles. The Gforth
prototype can produce 64-bit cells; displaying all of them requires a protocol
extension for lossless large integers. Values are never silently rounded.

Explicit asynchronous execution is available through `ForthStackRun`, described
below. Basic identities and source-comment labels are implemented; see
[labels.md](labels.md). Companion-file persistence is not implemented.
Instrumentation retains the limitations in
[gforth-instrumentation.md](gforth-instrumentation.md).

## API and organization

- `require('forth-stack').load(path, bufnr?)`: reads, validates, and displays JSON.
- `show(trace, bufnr?, base?)`: takes an already decoded table; relative paths use
  `base` or the current directory. Input data is borrowed and snapshots are copied.
- `clear(bufnr?)`, `toggle(bufnr?)`, `inspect(bufnr?, line?)`: control the display.
  The default buffer is current. `toggle` returns the resulting visibility, or
  false without a trace; `inspect` returns a window ID, or nil without observations.

`trace.lua` validates and groups; `display.lua` renders; `init.lua` maintains
per-buffer state and invalidates associations. Commands catch errors and notify;
the Lua API propagates errors to its caller. Calling `setup()` is not required
for normal startup installations.

## Tests

```sh
bash tests/run.sh
```

The script runs the Python instrumentation suite, generates a fresh Gforth trace,
and runs eight headless Neovim display scenarios. They check real states and
positions, untaken branches, the final loop occurrence, buffer integrity,
namespace/buffer isolation, toggle/clear, inspection, invalid data, precision,
invalidation after editing/renaming, and the real Gforth → JSON → Neovim path.
They inspect extmarks and window contents through the API; they do not evaluate
colors or readability across terminals visually.

## Installation and integrated execution

The [README](../README.md) contains lazy.nvim and native start-package recipes.
Native installation loads commands during startup without `setup()`. For copies
added to runtimepath after startup, `require('forth-stack').setup()` also registers
them, avoiding manual `:runtime`. There is no compilation step or external
dependency for `:ForthStackDemo`, which finds bundled files relative to the
installed plugin, independently of the current directory.

`:ForthStackRun` executes file code, including literals and calls outside
definitions. `:ForthStackRun word` also calls the named word after loading. Both
run a buffer snapshot asynchronously. Text is sent on stdin to the Python
supervisor, which writes a private temporary file and loads it through `included1`
under the original filename. Source locations and relative includes still refer
to the original program; the user file is not written. The buffer can be modified
or not yet exist on disk, provided it has a name in an existing directory. Other
included files are read from disk, not modified buffers. Source snapshots are
limited to 4 MiB.

By default, opening a `.fs` file starts tracing and automatic updates. Run also
enables updates for its buffer. Edits,
including Insert-mode changes, invalidate marks and cancel the current process.
Automatic execution/analysis and inline updates are deferred during Insert/Replace
mode. Entering suspends pending timers and cancels automatic work in flight;
leaving reschedules one update if work is pending. Outside editing mode, changes
restart a 350 ms timer. The timer captures the latest buffer; a burst of edits
produces one execution. Enter/leave without pending work does not execute again.
Explicit commands still work; one-time automatic startup obeys the deferral rule. Run identity, filename, and changedtick checks discard
late responses. Undo/redo and reloading also participate. Set `auto_start = false`
to require a manual run; `:ForthStackAutoToggle` pauses/resumes automatic `.fs`
tracing for the session. Stop/Clear stay paused when a buffer is reentered or
reloaded.

`:ForthStackStop` pauses timers/execution; Run resumes or changes the entry word.
Clear, loading valid JSON, renaming, or closing also disable tracking. Exiting
Neovim terminates active processes. `auto_update = false` disables updates after
edits, while `auto_start` independently controls the initial run;
`debounce_ms` sets a 1–5000 ms delay. Incomplete code records an error without
repeated notifications and is reevaluated after the next edit; `:ForthStackStatus`
shows diagnostics. `vim.b.forth_stack_status` and `vim.b.forth_stack_error` expose
this data to the API. Status values are `inactive`, `running`, `pending`,
`updated`, `paused`, `analyzed`, and `error`. Manual Run failures still notify. Old results
do not remain visible while the current version is invalid.

Arguments are passed as a list, without a shell. Each update creates a new
process and reruns the file/word, including I/O effects. Words needing stack
arguments can be called through a wrapper; Python's CLI still has `--input`, but
the Neovim command does not. stdout is preserved in JSON without a dedicated
Neovim output panel. Stop sends SIGTERM to the supervisor, which terminates and
waits for its direct Gforth child. Additional descendants are not managed.
Changes to included files in another buffer neither trigger updates nor receive
changedtick validation.

Successful runs render normally. Validated Forth failures can retain successful
observations from the current snapshot, explicitly marked `before error`.
Other failed/incomplete results are not rendered. Manual errors notify; automatic
errors appear as Neovim diagnostics and remain available in Status. A new run clears the previous display. The
supervisor still captures stdout/stderr in memory, and the 4 MiB limit applies
to the received result; it does not preemptively bound collection memory. Do not
use this prototype to execute untrusted programs.

`setup()` accepts `python`, `gforth`, `timeout`, `max_events`, `max_depth`,
`symbolic`, `auto_start`, `inline`, `auto_update`, and `debounce_ms`. Defaults are `python3`,
`gforth`, 5 seconds, 10,000 events, 256 cells, true, true, false, true, and 350 ms. Maximum values are 60 seconds, 10,000
events, 256 cells, and 5000 ms. Options are validated before applying changes;
repeated setup re-registers commands without duplicates. Executable paths,
including those with spaces, are resolved before starting the supervisor.
`:checkhealth forth-stack` checks Neovim, executables, and runtime files.
Missing Python/Gforth produces a warning because demo/load work without them.
Finding an executable does not establish compatibility with every version;
tested versions are documented in the README.

The suite also has eleven native-installation/execution scenarios in temporary
XDG directories and a late-setup test with startup plugin loading disabled.
They verify automatic registration, dependency-free demo, repeated configuration,
diagnostics, real execution, paths with spaces, unsaved files, failures,
cancellation of the Gforth child, and timeout. The lazy.nvim recipe uses the
manager's standard API; lazy.nvim itself was not installed for this validation.

## Continuous-update validation

Additional tests cover unsaved snapshots, preserved source identity and relative
includes, new files without disk creation, and eleven Lua scenarios: debounce,
bursts, incomplete-code recovery without popups, pause, entry replacement,
canceling stale responses, reload, Clear, manual mode, new files, and disabling
on rename/close. Disk contents and the buffer's modified flag are checked to
prevent implicit saving.

## Readable diagnostics

`:ForthStackStatus` opens a text split with the status and full last error.
Long lines wrap; you can scroll, copy text, or save it with
`:write /tmp/forth-stack-error.txt`. `q` closes the report and returns to the
source window. The report is temporary and does not modify the Forth file.
Messages distinguish common Gforth codes, such as stack underflow, unknown words,
and division by zero, and include the last observed location when available.
This location is compilation/last-probe context, not a guaranteed snapshot at
the instant of failure. Gforth process failures also retain stderr.

## Code outside definitions

File mode (`:ForthStackRun` without an argument) observes the text interpreter
during loading. In `examples/top-level.fs`, `18 can-drive` leaves `[-1]`, and
`20 can-drive` leaves `[-1, -1]`. The first result is not automatically discarded.
The `can-drive` definition shows its latest executed body occurrence, while
each external call has its own source location.

Word mode keeps those loading events and makes an additional call at the end.
Do not pass a word already called in the file unless you want it called again.
The selected mode persists through automatic updates, including unsaved edits.
Run without arguments always selects file mode; it does not silently reuse the
previous word name.

Uncalled definitions and empty files complete without marks rather than inventing
states. Collection is suspended during compilation, including `[ ... ]` blocks,
to avoid displaying compiler-control items as program data. Limitations for
immediate words, macros, and custom compilers still apply; this is not a tracer
of every VM primitive.

The CLI also accepts an omitted word:
`python3 prototype/trace.py examples/top-level.fs`.
With `--input`, file mode supplies values before loading; word mode supplies them
after loading and before the additional call.

## Label display

`( LABEL: age )` assigns a label to the runtime top element without changing
Forth execution. Version 2 traces carry numeric stacks plus element identities,
labels, and copy origins. Virtual text renders `age:17`; annotation observations
use the suffix `label age`. Inspection also lists IDs and copy origins. Imported
label traces must match the current annotation text. Existing version 1 traces
remain supported without identity data. See [labels.md](labels.md) for rules,
syntax, conservative barriers, and limitations.


### Optional inline cursor display

Inline display defaults to off. `:ForthStackInlineToggle` switches continuous
cursor display for the current buffer; `inline = true` enables it by default.
`:ForthStackInline` shows one observation until the cursor moves. If no trace is
available, it executes the file once without enabling ongoing updates.

Selection uses the cursor's byte column and the traced token's byte span. Inline
virtual text appears immediately after the token, leaving source text untouched.
The existing end-of-line observation remains visible. `:ForthStackInspect` uses
the selected token, with a line-level fallback. Repeated executions select the
most recent observation for that position; whitespace and unexecuted tokens have
no inline state. Annotations are buffer-scoped and shared between windows.
No keybindings are installed.


### Definition bodies and source order

In file mode (`:ForthStackRun` without a word, including automatic runs),
runtime end-of-line annotations use top-level observations. Documented definitions
show independent symbolic annotations instead. Runtime events inside
compiled words remain available for inline display and Inspect, marked `last
call`; they are not projected onto definition lines as if they happened when the
word was declared. A line containing both top-level code and a definition uses
its latest top-level observation, even if a later call executes its body.

Explicit `:ForthStackRun word` enables body annotations without symbolic coverage
for debugging, with a `last call` marker. Selection uses the existing source word metadata from Gforth,
not a text scan for colons or semicolons. Legacy traces without source word
metadata retain their existing display behavior.


### Symbolic contracts and Neovim diagnostics

Documented definitions are now analyzed independently using their declared input
names, including when uncalled. Symbolic annotations have a separate namespace
and take priority over concrete body observations. Real top-level states retain
priority on mixed lines. `ForthStackAnalyze` performs this analysis once without
executing Forth. Basic stack/arithmetic operations, fixed declared calls, and
simple branch joins are supported; other operations stop with a notice.
See [symbolic analysis and diagnostics](symbolic-analysis.md) for the complete
supported subset, assumptions, warning semantics, and limits.

The supervisor supplies an additive `error_location` on Forth failures. Active
before/after frames identify the outer top-level call; compile failures use the
last compilation site. Neovim validates that location against the current buffer
before attaching an error diagnostic. Only live Forth failures can enable the
partial-observation path; JSON imports continue to require a successful complete
trace. Partial observations retain normal token/value validation and explicit
markers in end-of-line, inline and Inspect views. Edits, cancellation, filename
and changedtick checks still prevent stale results from being installed.
