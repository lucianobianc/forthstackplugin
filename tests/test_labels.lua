vim.opt.runtimepath:prepend(vim.fn.getcwd())
local plugin = require('forth-stack')
local engine = require('forth-stack.engine')
local display = require('forth-stack.display')
plugin.setup({ debounce_ms = 80 })
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local path = directory .. '/labels.fs'
vim.cmd.enew()
vim.api.nvim_buf_set_name(0, path)
local buf = vim.api.nvim_get_current_buf()
local lines = vim.fn.readfile('examples/labels.fs')
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
local captured
local original = engine.run
engine.run = function(target, entry, callback, opts)
  return original(target, entry, function(trace, actual)
    captured = vim.deepcopy(trace)
    callback(trace, actual)
  end, opts)
end
local passed = 0
local function test(name, callback)
  callback(); passed = passed + 1; print('PASS ' .. name)
end
local function marks()
  local result = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, display.namespace, 0, -1, { details = true })) do
    result[mark[2] + 1] = mark[4].virt_text[1][1]
  end
  return result
end
local function wait_for(predicate)
  assert(vim.wait(4000, predicate, 10), 'Label result missing: ' .. tostring(select(2, plugin.status(buf))))
end
local ok, err = pcall(function()
  test('real Gforth trace renders labels, copies, increments, and consumed comparisons', function()
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    plugin.run(nil, buf)
    wait_for(function() return plugin.status(buf) == 'updated' end)
    assert(captured.format_version == 2)
    assert(marks()[5] == '[ age:17 ]  label age')
    assert(marks()[6] == '[ age:17 ]  after drop')
    assert(marks()[7] == '[ age:17, age:18 ]  after birthday')
    assert(marks()[8] == '[ age:17, -1 ]  after can-drive')
    assert(vim.api.nvim_buf_get_changedtick(buf) == tick and vim.bo[buf].modified)
    assert(vim.fn.filereadable(path) == 0, 'Label execution saved the buffer')
  end)
  test('inspect shows copy identities and origin without changing the source', function()
    local win = plugin.inspect(buf, 7)
    local contents = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
    assert(contents:find('Stack: [ age:17, age:18 ]', 1, true))
    assert(contents:find('copied from id=', 1, true))
    vim.api.nvim_win_close(win, true)
    plugin.toggle(buf)
    assert(vim.tbl_isempty(marks()))
    plugin.toggle(buf)
    assert(marks()[7] == '[ age:17, age:18 ]  after birthday')
  end)
  local old
  test('unsaved label edits refresh and reject stale annotation text', function()
    old = captured
    lines[5] = '17 ( LABEL: years )'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    wait_for(function() return marks()[7] == '[ years:17, years:18 ]  after birthday' end)
    assert(not pcall(plugin.show, old, buf), 'Old label comment was accepted')
    assert(marks()[7] == '[ years:17, years:18 ]  after birthday')
    lines[5] = '20 ( LABEL: years )'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    wait_for(function() return marks()[7] == '[ years:20, years:21 ]  after birthday' end)
    assert(marks()[8] == '[ years:20, -1 ]  after can-drive')
  end)
  test('malformed identities and display-injection labels are rejected atomically', function()
    for _, mutate in ipairs({
      function(e) e.elements = {} end,
      function(e) e.elements[1].value = 999 end,
      function(e) e.elements[1].label = 'bad\nlabel' end,
      function(e) e.elements[1].id = -1 end,
      function(e) e.elements[1].origin = e.elements[1].id end,
      function(e) e.elements[2].id = e.elements[1].id end,
    }) do
      local data = vim.deepcopy(captured)
      for _, event in ipairs(data.events) do
        if #event.stack == 2 then mutate(event); break end
      end
      assert(not pcall(plugin.show, data, buf), 'Invalid identities were accepted')
      assert(marks()[7] == '[ years:20, years:21 ]  after birthday')
    end
  end)
  test('rendered identity data is copied and clearing does not modify source labels', function()
    plugin.show(captured, buf)
    for _, event in ipairs(captured.events) do
      for _, element in ipairs(event.elements) do element.label = 'mutated' end
    end
    plugin.toggle(buf); plugin.toggle(buf)
    assert(marks()[7] == '[ years:20, years:21 ]  after birthday')
    plugin.clear(buf)
    assert(vim.tbl_isempty(marks()))
    assert(vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1] == '20 ( LABEL: years )')
  end)
end)
plugin.stop(buf)
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(directory, 'rf')
if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cquit 1') end
print(passed .. ' label display tests passed')
vim.cmd('qa!')
