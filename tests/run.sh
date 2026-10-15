#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -v
trace_directory=$(mktemp -d)
trap 'rm -rf "$trace_directory"' EXIT
python3 prototype/trace.py examples/compiled.fs example > "$trace_directory/compiled.json"
FORTH_STACK_TEST_TRACE="$trace_directory/compiled.json" \
  nvim --headless -u NONE -i NONE -l tests/test_display.lua
# Exercise actual package discovery and plugin startup from an unrelated cwd.
mkdir -p "$trace_directory/data/nvim/site/pack/test/start" "$trace_directory/config" "$trace_directory/state" "$trace_directory/cache"
ln -s "$PWD" "$trace_directory/data/nvim/site/pack/test/start/forthstackplugin"
printf '' > "$trace_directory/init.lua"
FORTH_STACK_ROOT="$PWD" FORTH_STACK_TMP="$trace_directory" \
XDG_DATA_HOME="$trace_directory/data" XDG_CONFIG_HOME="$trace_directory/config" \
XDG_STATE_HOME="$trace_directory/state" XDG_CACHE_HOME="$trace_directory/cache" \
  nvim --headless -u "$trace_directory/init.lua" -i NONE \
    -c "lua dofile(vim.env.FORTH_STACK_ROOT .. '/tests/test_plugin.lua')"
nvim --headless -u NONE -i NONE -l tests/test_setup.lua
# A minimal local init must also work without any installed package.
mkdir -p "$trace_directory/quick-data"
FORTH_STACK_ROOT="$PWD" XDG_DATA_HOME="$trace_directory/quick-data" \
XDG_CONFIG_HOME="$trace_directory/config" XDG_STATE_HOME="$trace_directory/state" \
XDG_CACHE_HOME="$trace_directory/cache" \
  nvim --headless -u examples/minimal-init.lua -i NONE \
    -c "lua dofile(vim.env.FORTH_STACK_ROOT .. '/tests/test_quickstart.lua')"
