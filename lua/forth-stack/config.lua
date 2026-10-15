local M = {}
M.defaults = { python = 'python3', gforth = 'gforth', timeout = 5, max_events = 10000, max_depth = 256, auto_update = true, debounce_ms = 350 }
M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  assert(opts == nil or type(opts) == 'table', 'Opções devem ser uma tabela')
  local candidate = vim.tbl_extend('force', {}, M.defaults, opts or {})
  for key in pairs(candidate) do assert(M.defaults[key] ~= nil, 'Opção desconhecida: ' .. key) end
  for _, key in ipairs({ 'python', 'gforth' }) do
    assert(type(candidate[key]) == 'string' and candidate[key] ~= '', key .. ' deve ser um executável')
  end
  assert(type(candidate.auto_update) == 'boolean', 'auto_update deve ser booleano')
  for key, maximum in pairs({ timeout = 60, max_events = 10000, max_depth = 256, debounce_ms = 5000 }) do
    local value = candidate[key]
    assert(type(value) == 'number' and value > 0 and value <= maximum,
      key .. ' deve estar entre 0 e ' .. maximum)
    if key ~= 'timeout' then assert(value == math.floor(value), key .. ' deve ser inteiro') end
  end
  M.options = candidate
end

return M
