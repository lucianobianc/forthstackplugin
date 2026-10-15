local M = {}
local active = {}

function M.stop(bufnr)
  local run = active[bufnr]
  if not run then return false end
  active[bufnr] = nil
  -- Cancel through the supervisor, which terminates its Gforth child.
  if run.process then run.process:kill(15) end
  return true
end

function M.running(bufnr) return active[bufnr] ~= nil end

function M.run(bufnr, entry, on_success)
  assert(type(entry) == 'string' and entry ~= '' and not entry:find('%s'), 'Informe uma palavra Forth')
  assert(vim.bo[bufnr].buftype == '' and not vim.bo[bufnr].modified, 'Salve o arquivo antes de executar')
  local filename = vim.api.nvim_buf_get_name(bufnr)
  assert(filename ~= '' and vim.fn.filereadable(filename) == 1, 'Abra um arquivo Forth salvo')
  local config = vim.deepcopy(require('forth-stack.config').options)
  for _, key in ipairs({ 'python', 'gforth' }) do
    assert(vim.fn.executable(config[key]) == 1, key .. ' não encontrado; consulte :checkhealth forth-stack')
  end
  local tracer = require('forth-stack.paths').tracer
  assert(vim.fn.filereadable(tracer) == 1, 'Protótipo não encontrado; reinstale o plugin completo')
  M.stop(bufnr)
  local run = { tick = vim.api.nvim_buf_get_changedtick(bufnr), filename = filename }
  active[bufnr] = run
  local command = { vim.fn.exepath(config.python), tracer,
    '--gforth', vim.fn.exepath(config.gforth),
    '--timeout', tostring(config.timeout), '--max-events', tostring(config.max_events),
    '--max-depth', tostring(config.max_depth), '--', filename, entry }
  local ok, process = pcall(vim.system, command, { text = true }, function(result)
    vim.schedule(function()
      if active[bufnr] ~= run then return end
      active[bufnr] = nil
      if not vim.api.nvim_buf_is_valid(bufnr)
        or vim.api.nvim_buf_get_changedtick(bufnr) ~= run.tick
        or vim.api.nvim_buf_get_name(bufnr) ~= run.filename then return end
      local success, err = pcall(function()
        assert(#(result.stdout or '') <= 4 * 1024 * 1024, 'Limite: registro de 4 MiB')
        local decoded, trace = pcall(vim.json.decode, result.stdout or '')
        assert(decoded and type(trace) == 'table', 'Falha no supervisor: ' .. (result.stderr or ''):sub(1, 1000))
        assert(result.code == 0 and trace.complete and trace.status == 'ok',
          'Execução falhou: ' .. tostring(trace.diagnostic or trace.status)
          .. ' (Forth ' .. tostring(trace.forth_code) .. ')')
        on_success(trace, bufnr)
      end)
      if not success then vim.notify(tostring(err), vim.log.levels.ERROR, { title = 'Forth Stack' }) end
    end)
  end)
  if not ok then active[bufnr] = nil; error(process) end
  run.process = process
end

return M
