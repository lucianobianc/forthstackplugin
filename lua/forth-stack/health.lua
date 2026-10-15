local M = {}
function M.check()
  vim.health.start('Forth Stack')
  if vim.fn.has('nvim-0.10') == 1 then vim.health.ok('Neovim >= 0.10')
  else vim.health.error('Atualize o Neovim para 0.10 ou superior') end
  local config = require('forth-stack.config').options
  for _, key in ipairs({ 'python', 'gforth' }) do
    if vim.fn.executable(config[key]) == 1 then vim.health.ok(key .. ': ' .. config[key])
    else vim.health.warn(key .. ' não encontrado: ' .. config[key], {
      'Necessário para :ForthStackRun; :ForthStackDemo e :ForthStackLoad funcionam sem ele.',
      "Configure require('forth-stack').setup({ " .. key .. " = '/caminho/executavel' }).",
    }) end
  end
  local paths = require('forth-stack.paths')
  for _, key in ipairs({ 'tracer', 'example', 'fixture' }) do
    if vim.fn.filereadable(paths[key]) == 1 then vim.health.ok(key .. ' disponível')
    else vim.health.error('Arquivo ausente: ' .. paths[key], { 'Reinstale o plugin completo.' }) end
  end
  vim.health.info('Execução validada em Linux x86-64 com Gforth 0.7.3 e Neovim 0.10.4.')
end
return M
