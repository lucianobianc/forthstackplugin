local M = {}

function M.register()
  local function command(name, callback, opts)
    vim.api.nvim_create_user_command(name, function(args)
      local ok, err = pcall(callback, args)
      if not ok then vim.notify(tostring(err), vim.log.levels.ERROR, { title = 'Forth Stack' }) end
    end, opts or {})
  end
  command('ForthStackLoad', function(args) require('forth-stack').load(args.args) end,
    { nargs = 1, complete = 'file', desc = 'Load a JSON execution trace' })
  command('ForthStackDemo', function() require('forth-stack').demo() end,
    { desc = 'Open the stack demo without executing Forth' })
  command('ForthStackRun', function(args) require('forth-stack').run(args.args) end,
    { nargs = '?', desc = 'Run the Forth file or a specific word' })
  command('ForthStackStatus', function()
    require('forth-stack').status_view()
  end)
  command('ForthStackStop', function() require('forth-stack').stop() end)
  command('ForthStackClear', function() require('forth-stack').clear() end)
  command('ForthStackToggle', function() require('forth-stack').toggle() end)
  command('ForthStackInspect', function()
    if not require('forth-stack').inspect() then
      vim.notify('No stack state observed on this line', vim.log.levels.INFO, { title = 'Forth Stack' })
    end
  end)
end

return M
