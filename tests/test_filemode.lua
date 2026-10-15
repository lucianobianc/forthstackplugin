vim.opt.runtimepath:prepend(vim.fn.getcwd())
local plugin = require('forth-stack')
local display = require('forth-stack.display')
plugin.setup({ debounce_ms = 80 })
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
vim.cmd.enew()
vim.api.nvim_buf_set_name(0, dir .. '/new.fs')
local buf = vim.api.nvim_get_current_buf()
local function edit(lines) vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines) end
local function marks()
  local result = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, display.namespace, 0, -1, { details = true })) do
    result[m[2] + 1] = m[4].virt_text[1][1]
  end
  return result
end
local function wait_for(predicate)
  assert(vim.wait(4000, predicate, 10), 'Result did not appear: ' .. tostring(select(2, plugin.status(buf))))
end
local ok, err = pcall(function()
  edit({ ': can-drive ( age -- f ) 18 >= ;', '', '18 can-drive', '20 can-drive' })
  vim.cmd.ForthStackRun()
  wait_for(function() return marks()[4] == '[ -1, -1 ]  after can-drive' end)
  assert(marks()[3] == '[ -1 ]  after can-drive')
  assert(marks()[1] == '[ -1, -1 ]  after >=')
  assert(vim.fn.filereadable(dir .. '/new.fs') == 0, 'Execution wrote the source file')
  print('PASS Run without arguments shows calls inside and outside definitions')
  edit({ ': can-drive ( age -- f ) 18 >= ;', '', '18 can-drive', '17 can-drive' })
  wait_for(function() return marks()[4] == '[ -1, 0 ]  after can-drive' end)
  print('PASS unsaved edits preserve file mode and update stacks')
  plugin.stop(buf)
  edit({ ': specific 99 ;', '1 2 +' })
  plugin.run('specific', buf)
  wait_for(function() return marks()[1] == '[ 3, 99 ]  after 99' end)
  vim.cmd.ForthStackRun()
  wait_for(function() return marks()[2] == '[ 3 ]  after +' and marks()[1] == nil end)
  print('PASS Run without arguments switches to file mode without invoking the previous entry')
  edit({ ': specific 99 ;' })
  wait_for(function() return plugin.status(buf) == 'updated' end)
  assert(vim.tbl_isempty(marks()), 'Uncalled definition displayed an invented stack')
  print('PASS definitions-only file does not execute bodies or produce an error')
end)
plugin.stop(buf)
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(dir, 'rf')
if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cquit 1') end
print('4 file-mode tests passed')
vim.cmd('qa!')
