vim.opt.runtimepath:prepend(vim.fn.getcwd())
local plugin = require('forth-stack')
local display = require('forth-stack.display')
plugin.setup({ inline = true, auto_start = false })
vim.cmd.enew()
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '.fs')
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  ': word1 + ; : word2 2 * ;',
  '10 20 word1 word2',
  '17 ( LABEL: age ) dup 1+',
  ': twice dup dup ;',
  'twice drop twice',
  '( café ) 5 6 +',
})
local tick = vim.api.nvim_buf_get_changedtick(buf)
local function point(line, column, expected)
  vim.api.nvim_win_set_cursor(0, { line, column })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
  local marks = vim.api.nvim_buf_get_extmarks(buf, display.cursor_namespace, 0, -1, { details = true })
  if not expected then assert(#marks == 0); return end
  assert(#marks == 1, "No mark at " .. line .. ":" .. column)
  assert(marks[1][4].virt_text_pos == 'inline')
  assert(marks[1][4].virt_text[1][1] == ' ' .. expected .. ' ', vim.inspect(marks))
end
local ok, err = pcall(function()
  plugin.run(nil, buf)
  assert(vim.wait(5000, function() return plugin.status(buf) == 'updated' end, 10),
    tostring(select(2, plugin.status(buf))))
  point(2, 0, '[ 10 ]')
  point(2, 1, '[ 10 ]')
  point(2, 3, '[ 10, 20 ]')
  point(2, 6, '[ 30 ]')
  point(2, 12, nil) -- final state is already displayed at end of line
  point(2, 2, nil) -- whitespace is not a token
  point(3, 18, '[ 60, age:17, age:17 ]')
  point(3, 22, nil) -- labeled final state is not repeated inline
  -- Most recent execution of the first dup inside a repeatedly called word.
  point(4, 8, '[ 60, age:17, age:18, age:18, age:18 ]')
  point(6, 10, '[ 60, age:17, age:18, age:18, age:18, age:18, 5 ]')
  point(1, 0, nil) -- definition syntax has no after-event
  point(2, 3, '[ 10, 20 ]')
  local win = plugin.inspect()
  local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
  assert(text:find('Stack: [ 10, 20 ]', 1, true))
  vim.api.nvim_win_close(win, true)
  plugin.toggle(buf)
  assert(#vim.api.nvim_buf_get_extmarks(buf, display.cursor_namespace, 0, -1, {}) == 0)
  plugin.toggle(buf)
  point(2, 3, '[ 10, 20 ]')
  assert(vim.api.nvim_buf_get_changedtick(buf) == tick)
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { '10 30 word1 word2' })
  assert(#vim.api.nvim_buf_get_extmarks(buf, display.cursor_namespace, 0, -1, {}) == 0,
    'Editing left a stale cursor annotation')
  plugin.clear(buf)
  point(2, 0, nil)
  print('PASS cursor stacks: literals, calls, labels, repeated execution, byte columns, inspect, toggle and clear')
end)
if not ok then print(err); vim.cmd('cquit 1') else vim.cmd('qa!') end
