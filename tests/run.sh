#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -v
trace_directory=$(mktemp -d)
trap 'rm -rf "$trace_directory"' EXIT
python3 prototype/trace.py examples/compiled.fs example > "$trace_directory/compiled.json"
FORTH_STACK_TEST_TRACE="$trace_directory/compiled.json" \
  nvim --headless -u NONE -i NONE -l tests/test_display.lua
