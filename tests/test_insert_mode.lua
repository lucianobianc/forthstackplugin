-- Run with -c, so scheduled steps return to Neovim's real input loop.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.swapfile = false
vim.opt.showmode = false
vim.opt.columns = 180
local plugin = require('forth-stack')
local engine = require('forth-stack.engine')
local display = require('forth-stack.display')
local symbolic = require('forth-stack.symbolic')
local diagnostics = require('forth-stack.diagnostics')
plugin.setup({ auto_start = false, debounce_ms = 60, timeout = 2, inline = true })
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
vim.cmd.enew()
vim.api.nvim_buf_set_name(0, dir .. '/typing.fs')
local buf = vim.api.nvim_get_current_buf()
local starts, finished = 0, false
local original = engine.run
engine.run = function(...)
  starts = starts + 1
  return original(...)
end
vim.notify = function() end
local thread
local function resume()
  local ok, err = coroutine.resume(thread)
  if not ok then print(err); finished = true; vim.cmd('cquit 1') end
end
local function pause(ms)
  vim.defer_fn(resume, ms)
  coroutine.yield()
end
local function wait_for(predicate, message)
  for _ = 1, 500 do
    if predicate() then return end
    pause(10)
  end
  error(message or 'Timed out')
end
local function ready()
  wait_for(function() return plugin.status(buf) == 'updated' end,
    'Result missing: ' .. tostring(select(2, plugin.status(buf))))
end
local function enter()
  vim.cmd('startinsert!')
  pause(30)
  assert(vim.api.nvim_get_mode().mode:match('^i'), 'Test did not enter actual Insert mode')
end
local function leave()
  vim.api.nvim_input('<Esc>')
  pause(30)
  assert(not vim.api.nvim_get_mode().mode:match('^[iR]'), 'Test did not leave Insert mode')
end
local function text()
  local marks = vim.api.nvim_buf_get_extmarks(buf, display.namespace, 0, -1, { details = true })
  return marks[#marks] and marks[#marks][4].virt_text[1][1]
end
thread = coroutine.create(function()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ': keep ( n -- n ) noop ;', '1' })
  plugin.run()
  ready()
  local count = starts
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  enter()
  vim.api.nvim_input(' 2 +')
  pause(200) -- longer than debounce, while remaining in Insert mode
  assert(starts == count and not engine.running(buf), 'Automatic execution occurred while typing')
  assert(#vim.diagnostic.get(buf, { namespace = diagnostics.namespace }) == 0)
  assert(#vim.api.nvim_buf_get_extmarks(buf, symbolic.namespace, 0, -1, {}) == 0)
  assert(#vim.api.nvim_buf_get_extmarks(buf, display.cursor_namespace, 0, -1, {}) == 0)
  leave()
  ready()
  assert(starts == count + 1 and text() == '[ 3 ]  after +')
  print('PASS actual Insert mode suppresses execution, symbolic refresh and inline updates until leave')

  count = starts
  enter()
  pause(150)
  leave()
  pause(150)
  assert(starts == count, 'Entering and leaving without edits reran the program')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '4' })
  enter() -- cancel an already-pending timer without editing again
  pause(150)
  assert(starts == count, 'Pending timer fired during Insert mode')
  leave()
  ready()
  assert(starts == count + 1 and text() == '[ 4 ]  after 4')
  print('PASS pending timers wait for InsertLeave; entering alone causes no redundant run')

  count = starts
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_input('R')
  pause(30)
  assert(vim.api.nvim_get_mode().mode:match('^R'), 'Test did not enter Replace mode')
  vim.api.nvim_input('8')
  pause(150)
  assert(starts == count, 'Automatic execution occurred during Replace mode')
  leave()
  ready()
  assert(starts == count + 1 and text() == '[ 8 ]  after 8')
  print('PASS actual Replace mode defers automatic updates too')

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '1000 ms', '7' })
  wait_for(function() return engine.running(buf) end, 'Automatic slow run did not start')
  count = starts
  enter()
  pause(150)
  assert(not engine.running(buf), 'In-flight automatic run was not canceled')
  assert(starts == count and plugin.status(buf) == 'pending')
  leave()
  ready()
  assert(starts == count + 1 and text() == '[ 7 ]  after 7')
  print('PASS entering Insert mode cancels automatic work in flight and reruns once afterward')

  count = starts
  enter()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ':' })
  pause(150)
  assert(starts == count and #vim.diagnostic.get(buf, { namespace = diagnostics.namespace }) == 0)
  leave()
  wait_for(function() return plugin.status(buf) == 'error' end, 'Incomplete source was not validated after InsertLeave')
  assert(#vim.diagnostic.get(buf, { namespace = diagnostics.namespace }) == 1)
  count = starts
  enter()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ': still-typing' })
  pause(150)
  assert(starts == count and #vim.diagnostic.get(buf, { namespace = diagnostics.namespace }) == 0)
  plugin.stop()
  leave()
  pause(150)
  assert(starts == count and plugin.status(buf) == 'paused', 'InsertLeave resumed a stopped buffer')
  print('PASS incomplete source reports errors only after InsertLeave and Stop remains paused')

  plugin.setup({ auto_start = true, auto_update = false, debounce_ms = 60 })
  vim.fn.writefile({ '9' }, dir .. '/once.fs')
  vim.cmd('edit! ' .. vim.fn.fnameescape(dir .. '/once.fs'))
  buf = vim.api.nvim_get_current_buf()
  count = starts
  enter()
  pause(150)
  assert(starts == count, 'One-time automatic startup ran in Insert mode')
  leave()
  ready()
  assert(starts == count + 1 and require('forth-stack.live').entry(buf) == nil)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '10' })
  pause(150)
  assert(starts == count + 1, 'One-time startup enabled ongoing updates')
  print('PASS auto_update=false initial runs also defer without enabling edit updates')

  plugin.setup({ auto_start = false, debounce_ms = 60 })
  enter()
  count = starts
  plugin.run() -- explicit commands remain available in Insert mode
  ready()
  assert(starts == count + 1 and vim.api.nvim_get_mode().mode:match('^i'))
  plugin.stop()
  leave()
  print('PASS an explicit manual run is still allowed while automatic updates are deferred')
  finished = true
  plugin.clear()
  vim.fn.delete(dir, 'rf')
  vim.cmd('qa!')
end)
vim.defer_fn(function()
  if not finished then print('Insert-mode test watchdog expired'); vim.cmd('cquit 1') end
end, 12000)
vim.schedule(resume)
