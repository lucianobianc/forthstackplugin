# forthstackplugin

See your Forth program's stack next to the code in Neovim. Once you start a run,
values update as you type, without saving the file.

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

Run this once, without specifying a word:

```vim
:ForthStackRun
```

The `16` line shows `[ 16 ]`, and `birthday` shows `[ 17 ]`. The plugin tracks
both calls outside definitions and operations inside them.

Stacks appear next to observed operations, with the top on the right. The display
then updates after a 350 ms pause in typing, including unsaved changes.

Use `:ForthStackStop` to pause. Run `:ForthStackRun` again to resume. If the code
is incomplete, the plugin waits for the next edit and tries again without showing
a warning on every keystroke.

To call a specific word after loading the file, use `:ForthStackRun example`.
Without an argument, only the code in the file runs; uncalled definitions do not
execute their bodies.

Each update runs the program again, including its input and output operations.
Coverage is still partial: not every Forth operation is traced. See the
[limitations](doc/neovim-display.md#validation-and-limits) for details about the
states shown.

## Explore a line with the cursor

After `:ForthStackRun`, move the cursor over a number or word to see the stack
immediately after that token. It appears inline, between tokens; the end of the
line still shows its final stack. Nothing is inserted into your source.

For `10 20 +`, the cursor reveals `[ 10 ]` over `10`, `[ 10, 20 ]` over `20`,
and `[ 30 ]` over `+`. `:ForthStackInspect` also uses the token under the cursor.

This shows recorded execution, so unexecuted tokens have no inline stack.
For loops or repeated calls, it shows the most recent execution of that token.
Whitespace has no inline annotation. Cursor annotations are shared between
windows displaying the same buffer.

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
