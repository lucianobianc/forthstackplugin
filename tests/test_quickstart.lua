local ok, err = pcall(function()
  assert(vim.fn.exists(':ForthStackDemo') == 2, 'demo ausente')
  vim.cmd.ForthStackDemo()
  local ns = require('forth-stack.display').namespace
  assert(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) > 0, 'demo não desenhou estados')
  print('PASS configuração mínima abre demonstração sem instalação')
end)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd('cquit 1')
end
vim.cmd('qa!')
