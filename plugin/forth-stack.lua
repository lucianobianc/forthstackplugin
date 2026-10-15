if vim.g.loaded_forth_stack then return end
if vim.fn.has('nvim-0.10') ~= 1 then
  vim.notify('Forth Stack requer Neovim 0.10 ou superior', vim.log.levels.ERROR)
  return
end
vim.g.loaded_forth_stack = true
require('forth-stack.commands').register()
