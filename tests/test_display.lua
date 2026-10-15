local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.cmd('runtime plugin/forth-stack.lua')
local plugin = require('forth-stack')
local display = require('forth-stack.display')
local trace = require('forth-stack.trace')
local fixture = root .. '/tests/fixtures/compiled.json'
local passed = 0
local function check(condition, message)
  assert(condition, message)
end
local function marks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, display.namespace, 0, -1, { details = true })
end
local function test(name, callback)
  callback()
  passed = passed + 1
  print('PASS ' .. name)
end

local ok, err = pcall(function()
  vim.cmd.edit(root .. '/examples/compiled.fs')
  local buf = vim.api.nvim_get_current_buf()
  local original = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local modified = vim.bo[buf].modified
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  test('commands register and render per line without editing the buffer', function()
    check(vim.fn.exists(':ForthStackLoad') == 2, 'Missing command')
    vim.cmd('ForthStackLoad ' .. fixture)
    local found = {}
    for _, mark in ipairs(marks(buf)) do found[mark[2] + 1] = mark[4].virt_text[1][1] end
    check(found[3] == '[ 16 ]  after 1+', 'Incorrect internal birthday state')
    check(found[15] == '[ 21 ]  after +', 'Incorrect final loop occurrence')
    check(found[10] == nil, 'Unexecuted branch was rendered')
    check(found[9] == '[ 16, 0 ]  after >=', 'Incorrect final token on the line')
    check(vim.deep_equal(original, vim.api.nvim_buf_get_lines(buf, 0, -1, false)), 'Buffer text changed')
    check(vim.bo[buf].modified == modified and vim.api.nvim_buf_get_changedtick(buf) == tick,
      'Buffer was marked modified')
  end)
  test('toggle preserves traces and clear only removes its own namespace', function()
    local other = vim.api.nvim_create_namespace('other-plugin')
    vim.api.nvim_buf_set_extmark(buf, other, 0, 0, {})
    local count = #marks(buf)
    vim.cmd.ForthStackToggle()
    check(#marks(buf) == 0, 'Toggle did not hide marks')
    vim.cmd.ForthStackToggle()
    check(#marks(buf) == count, 'Toggle lost trace data')
    vim.cmd.ForthStackClear()
    check(#marks(buf) == 0, 'Clear did not remove marks')
    check(#vim.api.nvim_buf_get_extmarks(buf, other, 0, -1, {}) == 1, 'Another plugin namespace was removed')
    check(plugin.toggle() == false, 'Clear retained trace state')
  end)
  test('inspect shows stack and history in a floating window', function()
    plugin.load(fixture)
    local win = plugin.inspect(buf, 15)
    check(win and vim.api.nvim_win_is_valid(win), 'Window is missing')
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    check(lines[1] == 'Stack: [ 21 ]', 'Incorrect stack')
    check(lines[4] == 'Observations on this line: 6', 'Occurrences were lost')
    plugin.clear()
    check(not vim.api.nvim_win_is_valid(win), 'Stale window remained after clear')
    check(plugin.inspect(buf, 1) == nil, 'Invented a state on a line without events')
  end)
  test('invalid or unrelated traces do not replace a valid display', function()
    plugin.load(fixture)
    local count = #marks(buf)
    local data = trace.read(fixture)
    data.complete = false
    check(not pcall(plugin.show, data, buf, root .. '/tests/fixtures'), 'Incomplete trace was accepted')
    data.complete = true
    data.format_version = 99
    check(not pcall(plugin.show, data, buf), 'Unsupported version was accepted')
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(other, root .. '/examples/other.fs')
    check(not pcall(plugin.show, trace.read(fixture), other, root .. '/tests/fixtures'), 'Unrelated file was accepted')
    vim.api.nvim_buf_delete(other, { force = true })
    check(#marks(buf) == count, 'Failure removed valid state')
  end)
  test('mismatched locations, invalid sequences and inexact integers are rejected', function()
    for _, change in ipairs({
      function(data) data.events[3].source.column_bytes = 999 end,
      function(data) data.events[3].seq = 999 end,
      function(data) data.events[3].stack = { 9007199254740992 } end,
      function(data) data.events[3].stack = { '16' } end,
    }) do
      local data = trace.read(fixture)
      change(data)
      check(not pcall(plugin.show, data, buf, root .. '/tests/fixtures'), 'Invalid trace was accepted')
    end
    check(display.stack({}) == '[ ]', 'Incorrect empty stack')
    check(display.stack({ -1, 9007199254740991 }) == '[ -1, 9007199254740991 ]', 'Incorrect integer formatting')
  end)
  test('editing invalidates hidden data and closes inspect', function()
    plugin.load(fixture)
    local win = plugin.inspect(buf, 15)
    vim.api.nvim_buf_set_lines(buf, 6, 7, false, { '  99' })
    check(#marks(buf) == 0, 'Stale marks remained')
    vim.wait(100, function() return not vim.api.nvim_win_is_valid(win) end)
    check(not vim.api.nvim_win_is_valid(win), 'Stale inspect window remained')
    check(plugin.toggle(buf) == false, 'Editing did not invalidate state')
    check(not pcall(plugin.load, fixture), 'Modified token was accepted')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
    plugin.load(fixture)
    plugin.toggle(buf)
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { '\\ new comment' })
    check(plugin.toggle(buf) == false and #marks(buf) == 0, 'Hidden state survived an edit')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
  end)
  test('buffers are independent and deletion does not revive state', function()
    plugin.load(fixture)
    vim.api.nvim_buf_set_name(buf, root .. '/examples/renamed.fs')
    check(#marks(buf) == 0 and not plugin.toggle(buf), 'Renaming preserved stale state')
    vim.api.nvim_buf_set_name(buf, root .. '/examples/compiled.fs')
    plugin.load(fixture)
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(other, root .. '/examples/unrelated.fs')
    plugin.clear(other)
    check(#marks(buf) > 0, 'Clear affected another buffer')
    vim.api.nvim_buf_delete(other, { force = true })
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
  test('real trace generated by the prototype', function()
    local real = vim.env.FORTH_STACK_TEST_TRACE
    check(real and real ~= '', 'Real trace was not provided')
    vim.cmd.edit(root .. '/examples/compiled.fs')
    plugin.load(real)
    local found = false
    for _, mark in ipairs(marks(vim.api.nvim_get_current_buf())) do
      if mark[2] == 14 and mark[4].virt_text[1][1] == '[ 21 ]  after +' then found = true end
    end
    check(found, 'Incorrect Gforth → JSON → Neovim pipeline')
  end)
end)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd('cquit 1')
end
print(passed .. ' Neovim tests passed')
vim.cmd('qa!')
