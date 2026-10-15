if vim.g.loaded_forth_stack then return end
vim.g.loaded_forth_stack = true

local function command(name, callback, opts)
  vim.api.nvim_create_user_command(name, function(args)
    local ok, err = pcall(callback, args)
    if not ok then vim.notify(tostring(err), vim.log.levels.ERROR, { title = 'Forth Stack' }) end
  end, opts or {})
end

command('ForthStackLoad', function(args) require('forth-stack').load(args.args) end,
  { nargs = 1, complete = 'file', desc = 'Carregar registro JSON de execução' })
command('ForthStackClear', function() require('forth-stack').clear() end)
command('ForthStackToggle', function() require('forth-stack').toggle() end)
command('ForthStackInspect', function()
  if not require('forth-stack').inspect() then
    vim.notify('Sem estado observado nesta linha', vim.log.levels.INFO, { title = 'Forth Stack' })
  end
end)
