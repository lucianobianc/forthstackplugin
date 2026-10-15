vim.opt.runtimepath:prepend(vim.fn.getcwd())
local plugin = require('forth-stack')
local display = require('forth-stack.display')
local symbolic = require('forth-stack.symbolic')
plugin.setup({ auto_start = false, debounce_ms = 50, inline = true })
vim.cmd.enew()
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '.fs')
local source = {
  ': maybe ( n -- ... )', '?dup dup', ';',
  ': hello ( -- ) ." Hello world" ;',
  ': known ( -- n n ) 2 3 + ?dup ;',
  '5 maybe',
}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
local function marks(namespace)
  return vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
end
local function point(row, column)
  vim.api.nvim_win_set_cursor(0, { row, column })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
end
local ok, err = pcall(function()
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  plugin.run()
  assert(vim.wait(5000, function() return plugin.status() == 'updated' end, 10), tostring(select(2, plugin.status())))
  local by_line = {}
  for _, mark in ipairs(marks(symbolic.namespace)) do by_line[mark[2] + 1] = mark[4].virt_text[1][1] end
  assert(by_line[2] == '[ 0, 0 ] | [ n, n, n ]  symbolic', vim.inspect(by_line))
  assert(by_line[4] == '[ ]  symbolic')
  assert(by_line[5] == '[ 5, 5 ]  symbolic')
  assert(#vim.diagnostic.get(buf) == 0, 'Supported ?dup or native dot-quote still emitted a notice')
  point(2, 0)
  local inline = marks(display.cursor_namespace)
  assert(#inline == 1 and inline[1][4].virt_text[1][1] == ' [ 0 ] | [ n, n ] ')
  local win = plugin.inspect()
  local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
  assert(text:find('Stack: [ 0 ] | [ n, n ]', 1, true))
  assert(text:find('Possible stacks', 1, true))
  vim.api.nvim_win_close(win, true)
  point(2, 5)
  assert(#marks(display.cursor_namespace) == 0, 'Final alternatives duplicated the line annotation')
  plugin.inline_once()
  assert(#marks(display.cursor_namespace) == 0)
  plugin.toggle()
  plugin.inline_once()
  assert(#marks(display.cursor_namespace) == 1, 'A hidden alternative annotation suppressed one-shot display')
  plugin.toggle()
  assert(vim.api.nvim_buf_get_changedtick(buf) == tick)
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source))
  print('PASS alternatives appear in line, inline and Inspect views; native strings, constants, deduplication and source preservation work')
end)
plugin.clear()
if not ok then print(err); vim.cmd('cquit 1') else vim.cmd('qa!') end
