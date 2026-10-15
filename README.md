# forthstackplugin

See your Forth program's stack next to the code in Neovim. Open a `.fs` file
and values update after you leave Insert mode, without saving the file.

The plugin is under development. Live stack visualization, Gforth execution,
and basic value labels are available.

## Requirements

- **Neovim 0.10 or later.**
- **Python 3 and Gforth** to run your programs.

The demo only needs Neovim. Execution has been tested on Linux with Gforth 0.7.3.

## Installation

### With lazy.nvim

Add this to your plugin list and run `:Lazy sync`:

```lua
{
  'lucianobianc/forthstackplugin',
  main = 'forth-stack',
  lazy = false,
  opts = {},
}
```

### Without a plugin manager (Linux)

Run in your terminal:

```sh
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/plugins/start"
git clone https://github.com/lucianobianc/forthstackplugin.git \
  "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/plugins/start/forthstackplugin"
```

Restart Neovim normally. You do not need to change your `init.lua`.
If the commands do not appear, check that your configuration allows plugins
(`:set loadplugins?`) and that the installation directory is in `packpath`.

## Try it

Inside Neovim, run:

```vim
:ForthStackDemo
```

An example opens with stacks next to the lines. To see details, place the cursor
on an annotated line and run `:ForthStackInspect`.

Already cloned the project and want to try it without installing? From the
repository root, run:

```sh
nvim -u examples/minimal-init.lua -c ForthStackDemo
```

## Use it with your code

Open a Forth file, such as `example.fs`:

```forth
: birthday 1+ ;

16
birthday
```

Tracing starts automatically for `.fs` files. To start or resume it manually:

```vim
:ForthStackRun
```

The `16` line shows `[ 16 ]`, and the call to `birthday` shows `[ 17 ]`.
Documented definitions show an independent symbolic stack, using the names in
their stack effect. Real values from later calls never become symbolic inputs.

Stacks appear next to observed operations, with the top on the right. The display
updates after a 350 ms pause outside Insert/Replace mode, including unsaved
changes. While you are typing in Insert/Replace mode, automatic execution,
symbolic analysis, and inline updates are deferred. Leaving that mode schedules
one update of the latest code. Edits still clear stale results immediately;
explicit commands such as `:ForthStackRun` remain available.

Use `:ForthStackStop` to pause. Run `:ForthStackRun` again to resume. If the code
is incomplete, the plugin waits for the next edit and tries again without showing
a warning on every keystroke.

To call a specific word after loading the file, use `:ForthStackRun example`.
Without an argument, only the code in the file runs; uncalled definitions do not
execute their bodies. An explicit `:ForthStackRun word` also shows observations
inside definitions without a usable symbolic analysis, marked `last call`,
for debugging that execution.

Each update runs the program again, including its input and output operations.
Coverage is still partial: not every Forth operation is traced. See the
[limitations](doc/neovim-display.md#validation-and-limits) for details about the
states shown.

## Understand a definition

Document its stack effect to see how it transforms its inputs, even when it is
never called. The comments on the right illustrate the generated annotations:

```forth
: can-drive ( age -- allowed )  \ [ age ]  symbolic inputs
  18                           \ [ age, 18 ]  symbolic
  >=                           \ [ allowed ]  symbolic
;

20 can-drive                   \ [ -1 ]  after can-drive
```

Names before `--` are the starting stack; names after it label the outputs when
the analyzed depth matches. `( name age id -- status )` starts with
`[ name, age, id ]`. These are symbols, not guessed numeric values.

Analysis runs automatically with tracing. To analyze definitions once **without
executing the file**, use `:ForthStackAnalyze`. This pauses ongoing execution;
`:ForthStackRun` resumes it. Set `symbolic = false` to disable automatic symbolic
annotations.

Unknown operations, loops, and other unsupported constructs receive an
“analysis incomplete” notice. Contract mismatches receive a warning. See
[analysis rules and limits](doc/symbolic-analysis.md).

## See errors in the code

Calling `can-drive` with an empty stack marks the call with a red **Stack
underflow** diagnostic. Other execution failures also appear as Neovim
diagnostics; use `:lua vim.diagnostic.open_float()` to read the full message.

Automatic diagnostics update after leaving Insert/Replace mode and the configured
delay, and clear when the code is corrected.
Valid observations before a Forth error may remain visible, marked `before
error`; they are not a complete execution result. `:ForthStackStatus` still
shows full execution details.

## Explore a line with the cursor

Inline display is **off by default**. Place the cursor over a number or word
and run `:ForthStackInline` to show its stack once. It disappears when you move
the cursor. With automatic tracing off, this command runs the file once if no
trace is available.

Use `:ForthStackInlineToggle` to keep inline display on as you move through the
current buffer; run it again to turn it off. The end of each line still shows
its final stack. When the selected token already has that end-of-line annotation,
it is shown only once. Nothing is inserted into your source.

For `10 20 +`, the cursor reveals `[ 10 ]` over `10`, `[ 10, 20 ]` over `20`,
and `[ 30 ]` over `+`. `:ForthStackInspect` also uses the token under the cursor.

Inside documented definitions, inline display and Inspect use symbolic states.
Other tokens use recorded execution: unexecuted tokens and whitespace have no
runtime stack; loops and repeated calls show the most recent execution.
Cursor annotations are shared between windows displaying the same buffer.

## Choose automatic behavior

Automatic tracing of `.fs` files is **on by default**. Use
`:ForthStackAutoToggle` to switch it off or on for the session. `:ForthStackStop`
pauses only the current buffer; `:ForthStackRun` resumes it.

To change the defaults, set these options in your lazy.nvim plugin entry:

```lua
opts = {
  auto_start = false, -- require a manual run instead of starting on .fs files
  inline = false,     -- keep cursor-driven inline display off
},
```

Without a plugin manager, use `require('forth-stack').setup({ auto_start = false })`
in your `init.lua`. The existing `auto_update = false` option disables updates
after edits, even after a manual run.

No keybindings are assigned. You can use the commands directly or map them to
keys of your choice.

## Optional keybindings

Use `<localleader>s` for a one-time stack, `<localleader>i` to toggle inline
stacks, and `<localleader>r` to run the file. No keys are assigned by the plugin.
`<localleader>` defaults to `\` unless you set `vim.g.maplocalleader`.

For example, add this to your `init.lua` to map the one-time stack in Forth
buffers only:

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'forth',
  group = vim.api.nvim_create_augroup('MyForthStackKeys', { clear = true }),
  callback = function(event)
    vim.keymap.set('n', '<localleader>s', '<cmd>ForthStackInline<cr>', {
      buffer = event.buf,
      desc = 'Show stack once',
    })
  end,
})
```

Check `:verbose nmap <localleader>s` before choosing a key; other plugins or your
configuration may already use it. If you use which-key, the mapping's description
also provides its menu label. To configure more keys, use the commands below.

## Label your values

Add `( LABEL: age )` after a value, then run `:ForthStackRun`.
The comments on the right illustrate the stack annotations displayed by the
plugin; you do not need to type them:

```forth
17 ( LABEL: age )   \ [ age:17 ]  label age
dup                \ [ age:17, age:17 ]  after dup
1+                 \ [ age:17, age:18 ]  after 1+
18 >=              \ [ age:17, -1 ]  after >=
```

`dup` copies the label, and `1+` keeps it as the value changes. The comparison
produces an unlabeled result (`-1`, meaning true).

Labels follow `dup`, `over`, `swap`, `rot`, `nip`, `tuck`, and `drop`. Increment
and decrement preserve them, including `1+`, `1-`, `1 +`, and `1 -`. General
arithmetic and unsupported operations use conservative rules and may remove
labels. Labels stay in your source comments; no companion file is needed.

Names use letters, digits, underscores, or hyphens, start with a letter or
underscore, and have at most 64 characters. Keep each label comment on one line.
See [label rules and limitations](doc/labels.md) and `examples/labels.fs`.

## Useful commands

| Command | What it does |
| --- | --- |
| `:ForthStackDemo` | Opens the demo |
| `:ForthStackRun` | Runs the file and follows edits |
| `:ForthStackAnalyze` | Analyzes documented definitions once without execution |
| `:ForthStackAutoToggle` | Toggles automatic `.fs` tracing for the session |
| `:ForthStackInline` | Shows the cursor token stack once |
| `:ForthStackInlineToggle` | Toggles inline stacks in this buffer |
| `:ForthStackRun word` | Loads the file and also calls a specific word |
| `:ForthStackStop` | Pauses automatic updates |
| `:ForthStackInspect` | Shows stack details for the cursor line |
| `:ForthStackToggle` | Hides or shows stacks |
| `:ForthStackClear` | Clears stacks and pauses automatic updates |
| `:ForthStackStatus` | Opens full diagnostics in a text window |

If something does not work, start with:

```vim
:checkhealth forth-stack
```

## Learn more

- [Configuration, external traces, and limitations](doc/neovim-display.md)
- [Gforth instrumentation investigation](doc/gforth-instrumentation.md)
- [Project specification](SPEC.md)

To run the tests, with Neovim, Python 3, and Gforth available in your terminal:

```sh
bash tests/run.sh
```
