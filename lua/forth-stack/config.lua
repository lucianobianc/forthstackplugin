local M = {}
M.defaults = { python = 'python3', gforth = 'gforth', timeout = 5, max_events = 10000, max_depth = 256, symbolic = true, auto_start = true, inline = false, auto_update = true, debounce_ms = 350 }
M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  assert(opts == nil or type(opts) == 'table', 'Options must be a table')
  local candidate = vim.tbl_extend('force', {}, M.defaults, opts or {})
  for key in pairs(candidate) do assert(M.defaults[key] ~= nil, 'Unknown option: ' .. key) end
  for _, key in ipairs({ 'python', 'gforth' }) do
    assert(type(candidate[key]) == 'string' and candidate[key] ~= '', key .. ' must be an executable')
  end
  for _, key in ipairs({ 'auto_update', 'auto_start', 'inline', 'symbolic' }) do
    assert(type(candidate[key]) == 'boolean', key .. ' must be a boolean')
  end
  for key, maximum in pairs({ timeout = 60, max_events = 10000, max_depth = 256, debounce_ms = 5000 }) do
    local value = candidate[key]
    assert(type(value) == 'number' and value > 0 and value <= maximum,
      key .. ' must be greater than 0 and at most ' .. maximum)
    if key ~= 'timeout' then assert(value == math.floor(value), key .. ' must be an integer') end
  end
  M.options = candidate
end

return M
