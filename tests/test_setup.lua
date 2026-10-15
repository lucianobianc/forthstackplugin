-- Explicit setup must work even when startup plugin discovery was skipped.
local ok, err = pcall(function()
  assert(vim.fn.exists(':ForthStackLoad') == 0, 'Test requires a session without loaded plugins')
  vim.opt.runtimepath:prepend(vim.fn.getcwd())
  require('forth-stack').setup()
  assert(vim.fn.exists(':ForthStackLoad') == 2)
  assert(vim.fn.exists(':ForthStackDemo') == 2)
  assert(vim.fn.exists(':ForthStackRun') == 2)
  require('forth-stack').setup()
  print('PASS late setup registers commands without manual :runtime')
end)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd('cquit 1')
end
vim.cmd('qa!')
