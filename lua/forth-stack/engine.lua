local M = {}
local active = {}

local function check(condition, message)
  if not condition then error(message, 0) end
end

function M.stop(bufnr)
  local run = active[bufnr]
  if not run then return false end
  active[bufnr] = nil
  -- Cancel through the supervisor, which terminates its Gforth child.
  if run.process then run.process:kill(15) end
  return true
end

function M.running(bufnr) return active[bufnr] ~= nil end

function M.run(bufnr, entry, on_success, opts)
  opts = opts or {}
  check(type(entry) == 'string' and entry ~= '' and not entry:find('%s'), 'Informe uma palavra Forth')
  check(vim.bo[bufnr].buftype == '', 'Abra um buffer de arquivo Forth')
  local filename = vim.api.nvim_buf_get_name(bufnr)
  check(filename ~= '' and vim.fn.isdirectory(vim.fs.dirname(filename)) == 1,
    'Dê um nome ao buffer em uma pasta existente (:file caminho.fs)')
  local snapshot = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  if vim.bo[bufnr].endofline then snapshot = snapshot .. '\n' end
  check(#snapshot <= 4 * 1024 * 1024, 'Limite: fonte de 4 MiB')
  local config = vim.deepcopy(require('forth-stack.config').options)
  for _, key in ipairs({ 'python', 'gforth' }) do
    check(vim.fn.executable(config[key]) == 1, key .. ' não encontrado; consulte :checkhealth forth-stack')
  end
  local tracer = require('forth-stack.paths').tracer
  check(vim.fn.filereadable(tracer) == 1, 'Protótipo não encontrado; reinstale o plugin completo')
  M.stop(bufnr)
  local run = { tick = vim.api.nvim_buf_get_changedtick(bufnr), filename = filename }
  active[bufnr] = run
  local command = { vim.fn.exepath(config.python), tracer,
    '--gforth', vim.fn.exepath(config.gforth),
    '--timeout', tostring(config.timeout), '--max-events', tostring(config.max_events),
    '--max-depth', tostring(config.max_depth), '--stdin-source', '--', filename, entry }
  vim.b[bufnr].forth_stack_status = 'executando'
  vim.b[bufnr].forth_stack_error = nil
  local ok, process = pcall(vim.system, command, { text = true, stdin = snapshot }, function(result)
    vim.schedule(function()
      if active[bufnr] ~= run then return end
      active[bufnr] = nil
      if not vim.api.nvim_buf_is_valid(bufnr)
        or vim.api.nvim_buf_get_changedtick(bufnr) ~= run.tick
        or vim.api.nvim_buf_get_name(bufnr) ~= run.filename then return end
      local success, err = pcall(function()
        check(#(result.stdout or '') <= 4 * 1024 * 1024, 'Limite: registro de 4 MiB')
        local decoded, trace = pcall(vim.json.decode, result.stdout or '')
        check(decoded and type(trace) == 'table', 'Falha no supervisor: ' .. (result.stderr or ''):sub(1, 1000))
        check(result.code == 0 and trace.complete and trace.status == 'ok',
          'Execução falhou: ' .. tostring(trace.diagnostic or trace.status)
          .. ' (Forth ' .. tostring(trace.forth_code) .. ')'
          .. ((trace.stderr and trace.stderr ~= '' and trace.status ~= 'process_error')
            and ('\n' .. trace.stderr:sub(1, 1500)) or ''))
        on_success(trace, bufnr)
        vim.b[bufnr].forth_stack_status = 'atualizado'
      end)
      if not success then
        vim.b[bufnr].forth_stack_status = 'erro'
        vim.b[bufnr].forth_stack_error = tostring(err)
        if not opts.silent then vim.notify(tostring(err), vim.log.levels.ERROR, { title = 'Forth Stack' }) end
      end
    end)
  end)
  if not ok then active[bufnr] = nil; error(process) end
  run.process = process
end

return M
