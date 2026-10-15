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
  check(vim.wait(7000, function() return not require('forth-stack.engine').running(buf) end), 'Execution did not finish')
end
local function write(path, text)
  vim.fn.writefile(vim.split(text, '\n', { plain = true }), path)
end

local ok, err = pcall(function()
  test('start package registers commands automatically in a clean session', function()
    for _, name in ipairs({ 'Load', 'Run', 'Stop', 'Demo', 'Clear', 'Toggle', 'Inspect' }) do
      check(vim.fn.exists(':ForthStack' .. name) == 2, 'Missing command: ' .. name)
    end
    check(vim.g.loaded_forth_stack == true, 'Plugin was not loaded during startup')
  end)
  local plugin = require('forth-stack')
  test('repeated setup and option validation', function()
    plugin.setup({ auto_update = false })
    plugin.setup({ timeout = 2, auto_update = false })
    check(require('forth-stack.config').options.timeout == 2, 'Configuration was ignored')
    check(not pcall(plugin.setup, { max_depth = 999 }), 'Invalid limit was accepted')
    check(not pcall(plugin.setup, { typo = true }), 'Unknown option was accepted')
    check(require('forth-stack.config').options.timeout == 2, 'Error changed the configuration')
    plugin.setup({ auto_update = false })
  end)
  test('demo works independently of cwd and Python/Gforth', function()
    plugin.setup({ python = 'not-installed-python', gforth = 'not-installed-gforth' })
    vim.cmd('cd ' .. vim.fn.fnameescape(vim.env.FORTH_STACK_TMP))
    vim.cmd.ForthStackDemo()
    local found = false
    for _, mark in ipairs(marks(0)) do
      if mark[2] == 2 and mark[4].virt_text[1][1] == '[ 16 ]  after 1+' then found = true end
    end
    check(found, 'Demo could not find installed files')
    check(#notifications == 0, 'Demo required external dependencies')
    plugin.setup({ auto_update = false })
  end)
  test('checkhealth reports available and missing dependencies', function()
    local reports = {}
    local saved = {}
    for _, name in ipairs({ 'start', 'ok', 'warn', 'error', 'info' }) do
      saved[name] = vim.health[name]
      vim.health[name] = function(message) reports[#reports + 1] = { name, message } end
    end
    plugin.setup({ gforth = 'not-installed-gforth' })
    require('forth-stack.health').check()
    for name, value in pairs(saved) do vim.health[name] = value end
    check(vim.tbl_contains(vim.tbl_map(function(r) return r[1] end, reports), 'warn'), 'Missing dependency was not diagnosed')
    plugin.setup({ auto_update = false })
  end)
  test('ForthStackRun executes asynchronously and displays results', function()
    vim.cmd('ForthStackRun example')
    local buf = vim.api.nvim_get_current_buf()
    check(require('forth-stack.engine').running(buf), 'Process did not start')
    local responsive = false
    vim.schedule(function() responsive = true end)
    wait_done(buf)
    check(responsive, 'Event loop did not advance')
    local found = false
    for _, mark in ipairs(marks(buf)) do
      if mark[2] == 14 and mark[4].virt_text[1][1] == '[ 21 ]  after +' then found = true end
    end
    check(found, 'Execution did not display the final stack: ' .. table.concat(notifications, '\n'))
    check(not vim.bo[buf].modified, 'Execution modified the file')
  end)
  local source = vim.env.FORTH_STACK_TMP .. '/program with spaces.fs'
  test('paths with spaces and configurable executable', function()
    write(source, ': -sample 15 1+ ;')
    vim.cmd('edit ' .. vim.fn.fnameescape(source))
    plugin.setup({ gforth = vim.fn.exepath('gforth') })
    plugin.run('-sample')
    local buf = vim.api.nvim_get_current_buf()
    wait_done(buf)
    check(#marks(buf) == 1 and marks(buf)[1][4].virt_text[1][1] == '[ 16 ]  after 1+', 'Path with spaces failed')
  end)
  test('unsaved snapshots execute without writing and missing dependencies prevent execution', function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { ': sample 9 ;' })
    plugin.run('sample')
    wait_done(vim.api.nvim_get_current_buf())
    check(marks(0)[1][4].virt_text[1][1] == '[ 9 ]  after 9', 'Snapshot was ignored')
    check(vim.bo.modified, 'Execution saved the buffer')
    vim.cmd('edit!')
    plugin.setup({ gforth = 'not-installed-gforth' })
    check(not pcall(plugin.run, 'sample'), 'Missing dependency was accepted')
    plugin.setup({ auto_update = false })
  end)
  test('Forth failures notify without displaying a complete trace', function()
    local count = #notifications
    plugin.run('missing-entry')
    wait_done(vim.api.nvim_get_current_buf())
    check(#notifications == count + 1, 'Error was not reported')
    check(not notifications[#notifications]:find('engine.lua:', 1, true), 'Error exposed a Lua line instead of its cause')
    check(notifications[#notifications]:find('unknown Forth word', 1, true), 'Forth error cause is missing')
    check(#marks(0) == 0, 'Failure displayed a stale result')
    local source = vim.api.nvim_get_current_buf()
    vim.cmd.ForthStackStatus()
    local report = vim.api.nvim_get_current_buf()
    local lines = table.concat(vim.api.nvim_buf_get_lines(report, 0, -1, false), '\n')
    check(lines:find('unknown Forth word', 1, true), 'Diagnostics did not show the full message')
    check(lines:find('missing-entry', 1, true), 'Entry word is missing from the report')
    check(vim.bo[report].buftype == 'nofile' and vim.wo.wrap, 'Diagnostics did not open as readable text')
    vim.cmd('normal q')
    check(vim.api.nvim_get_current_buf() == source, 'Diagnostics replaced the user file')
  end)
  test('stop cancels the supervisor and its Gforth child', function()
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
    end), 'Gforth child was not found')
    vim.cmd.ForthStackStop()
    check(not require('forth-stack.engine').running(buf), 'State was not canceled')
    check(vim.wait(2000, function() return vim.uv.kill(child, 0) == nil end), 'Gforth child was orphaned')
    check(#marks(buf) == 0, 'Cancellation displayed a result')
  end)
  test('editing cancels execution and discards late results', function()
    plugin.run('sample')
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ': sample 3 ;' })
    check(not require('forth-stack.engine').running(buf), 'Editing did not cancel execution')
    check(#marks(buf) == 0, 'Editing retained marks')
    vim.cmd('edit!')
  end)
  test('timeout ends a loop without freezing the editor', function()
    plugin.setup({ timeout = 0.2, auto_update = false })
    local count = #notifications
    plugin.run('sample')
    wait_done(vim.api.nvim_get_current_buf())
    check(#notifications == count + 1 and notifications[#notifications]:find('timed out', 1, true), 'Timeout was not diagnosed')
    plugin.setup({ auto_update = false })
  end)
end)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd('cquit 1')
end
print(passed .. ' installation/execution tests passed')
vim.cmd('qa!')
