-- Run AFTER normal startup, not with -l (which skips plugin loading).
local root = assert(vim.env.FORTH_STACK_ROOT)
local passed = 0
local notifications = {}
vim.notify = function(message) notifications[#notifications + 1] = message end
local function test(name, callback)
  callback()
  passed = passed + 1
  print('PASS ' .. name)
end
local function check(condition, message) assert(condition, message) end
local function marks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, require('forth-stack.display').namespace, 0, -1, { details = true })
end
local function wait_done(buf)
  check(vim.wait(7000, function() return not require('forth-stack.engine').running(buf) end), 'execução não terminou')
end
local function write(path, text)
  vim.fn.writefile(vim.split(text, '\n', { plain = true }), path)
end

local ok, err = pcall(function()
  test('package start registra comandos automaticamente em sessão limpa', function()
    for _, name in ipairs({ 'Load', 'Run', 'Stop', 'Demo', 'Clear', 'Toggle', 'Inspect' }) do
      check(vim.fn.exists(':ForthStack' .. name) == 2, 'comando ausente: ' .. name)
    end
    check(vim.g.loaded_forth_stack == true, 'plugin não carregado na inicialização')
  end)
  local plugin = require('forth-stack')
  test('setup repetido e validação de opções', function()
    plugin.setup()
    plugin.setup({ timeout = 2 })
    check(require('forth-stack.config').options.timeout == 2, 'configuração ignorada')
    check(not pcall(plugin.setup, { max_depth = 999 }), 'limite inválido aceito')
    check(not pcall(plugin.setup, { typo = true }), 'opção desconhecida aceita')
    check(require('forth-stack.config').options.timeout == 2, 'erro alterou configuração')
    plugin.setup()
  end)
  test('demo independe de cwd e de Python/Gforth', function()
    plugin.setup({ python = 'not-installed-python', gforth = 'not-installed-gforth' })
    vim.cmd('cd ' .. vim.fn.fnameescape(vim.env.FORTH_STACK_TMP))
    vim.cmd.ForthStackDemo()
    local found = false
    for _, mark in ipairs(marks(0)) do
      if mark[2] == 2 and mark[4].virt_text[1][1] == '[ 16 ]  após 1+' then found = true end
    end
    check(found, 'demo não encontrou arquivos instalados')
    check(#notifications == 0, 'demo exigiu dependências')
    plugin.setup()
  end)
  test('checkhealth relata dependências disponíveis e ausentes', function()
    local reports = {}
    local saved = {}
    for _, name in ipairs({ 'start', 'ok', 'warn', 'error', 'info' }) do
      saved[name] = vim.health[name]
      vim.health[name] = function(message) reports[#reports + 1] = { name, message } end
    end
    plugin.setup({ gforth = 'not-installed-gforth' })
    require('forth-stack.health').check()
    for name, value in pairs(saved) do vim.health[name] = value end
    check(vim.tbl_contains(vim.tbl_map(function(r) return r[1] end, reports), 'warn'), 'não diagnosticou dependência ausente')
    plugin.setup()
  end)
  test('ForthStackRun executa de forma assíncrona e mostra resultado', function()
    vim.cmd('ForthStackRun example')
    local buf = vim.api.nvim_get_current_buf()
    check(require('forth-stack.engine').running(buf), 'processo não iniciou')
    local responsive = false
    vim.schedule(function() responsive = true end)
    wait_done(buf)
    check(responsive, 'event loop não avançou')
    local found = false
    for _, mark in ipairs(marks(buf)) do
      if mark[2] == 14 and mark[4].virt_text[1][1] == '[ 21 ]  após +' then found = true end
    end
    check(found, 'execução não desenhou pilha final: ' .. table.concat(notifications, '\n'))
    check(not vim.bo[buf].modified, 'execução modificou arquivo')
  end)
  local source = vim.env.FORTH_STACK_TMP .. '/program with spaces.fs'
  test('arquivo com espaços e executável configurável', function()
    write(source, ': -sample 15 1+ ;')
    vim.cmd('edit ' .. vim.fn.fnameescape(source))
    plugin.setup({ gforth = vim.fn.exepath('gforth') })
    plugin.run('-sample')
    local buf = vim.api.nvim_get_current_buf()
    wait_done(buf)
    check(#marks(buf) == 1 and marks(buf)[1][4].virt_text[1][1] == '[ 16 ]  após 1+', 'espaços no caminho falharam')
  end)
  test('buffer não salvo e dependência ausente não executam', function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { ': sample 9 ;' })
    check(not pcall(plugin.run, 'sample'), 'buffer não salvo executou')
    vim.cmd('edit!')
    plugin.setup({ gforth = 'not-installed-gforth' })
    check(not pcall(plugin.run, 'sample'), 'dependência ausente aceita')
    plugin.setup()
  end)
  test('erro Forth notifica e não exibe registro como completo', function()
    local count = #notifications
    plugin.run('missing-entry')
    wait_done(vim.api.nvim_get_current_buf())
    check(#notifications == count + 1, 'erro não comunicado')
    check(#marks(0) == 0, 'erro mostrou resultado obsoleto')
  end)
  test('stop cancela supervisor e seu filho Gforth', function()
    -- Observe the real child PID through /proc; the shell wrapper execs Gforth.
    write(source, ': sample begin again ;')
    vim.cmd('edit!')
    plugin.run('sample')
    local buf = vim.api.nvim_get_current_buf()
    local child
    check(vim.wait(2000, function()
      local children = vim.fn.system({ 'ps', '-eo', 'pid=,comm=,args=' })
      for line in children:gmatch('[^\n]+') do
        local pid, comm, args = line:match('^%s*(%d+)%s+(%S+)%s+(.+)$')
        if comm and comm:match('^gforth') and args:find('/prototype/trace.fs', 1, true) and args:find('fst-run bye', 1, true) then
          child = tonumber(pid)
          return true
        end
      end
      return false
    end), 'filho Gforth não encontrado')
    vim.cmd.ForthStackStop()
    check(not require('forth-stack.engine').running(buf), 'estado não cancelado')
    check(vim.wait(2000, function() return vim.uv.kill(child, 0) == nil end), 'filho Gforth ficou órfão')
    check(#marks(buf) == 0, 'cancelamento mostrou resultado')
  end)
  test('edição cancela execução e descarta resultado atrasado', function()
    plugin.run('sample')
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ': sample 3 ;' })
    check(not require('forth-stack.engine').running(buf), 'edição não cancelou')
    check(#marks(buf) == 0, 'edição manteve marcas')
    vim.cmd('edit!')
  end)
  test('timeout encerra loop sem congelar o editor', function()
    plugin.setup({ timeout = 0.2 })
    local count = #notifications
    plugin.run('sample')
    wait_done(vim.api.nvim_get_current_buf())
    check(#notifications == count + 1 and notifications[#notifications]:find('timed out', 1, true), 'timeout não diagnosticado')
    plugin.setup()
  end)
end)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd('cquit 1')
end
print(passed .. ' testes de instalação/execução passaram')
vim.cmd('qa!')
