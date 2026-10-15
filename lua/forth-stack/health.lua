local M = {}
function M.check()
  vim.health.start('Forth Stack')
  if vim.fn.has('nvim-0.10') == 1 then vim.health.ok('Neovim >= 0.10')
  else vim.health.error('Upgrade Neovim to 0.10 or later') end
  local config = require('forth-stack.config').options
  for _, key in ipairs({ 'python', 'gforth' }) do
    if vim.fn.executable(config[key]) == 1 then vim.health.ok(key .. ': ' .. config[key])
    else vim.health.warn(key .. ' not found: ' .. config[key], {
      'Required for :ForthStackRun; :ForthStackDemo and :ForthStackLoad work without it.',
      "Configure require('forth-stack').setup({ " .. key .. " = '/path/to/executable' }).",
    }) end
  end
  local paths = require('forth-stack.paths')
  for _, key in ipairs({ 'tracer', 'label_tracker', 'example', 'fixture' }) do
    if vim.fn.filereadable(paths[key]) == 1 then vim.health.ok(key .. ' available')
    else vim.health.error('Missing file: ' .. paths[key], { 'Reinstall the complete plugin.' }) end
  end
  vim.health.info('Execution tested on Linux x86-64 with Gforth 0.7.3 and Neovim 0.10.4.')
end
return M
