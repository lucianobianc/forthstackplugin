# forthstackplugin

See your Forth program's stack next to the code in Neovim. Once you start a run,
values update as you type, without saving the file.

The plugin is under development. Stack visualization and Gforth execution work;
labels for individual values are not available yet.

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
