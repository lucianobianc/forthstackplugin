local M = {}
local watches = {}

local function cancel(state)
  if state and state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
end

function M.disable(bufnr)
  cancel(watches[bufnr])
  watches[bufnr] = nil
end

function M.enable(bufnr, entry)
  M.disable(bufnr)
  if require('forth-stack.config').options.auto_update then
    watches[bufnr] = { entry = entry, generation = 0 }
  end
end

function M.entry(bufnr)
  return watches[bufnr] and watches[bufnr].entry
end

function M.changed(bufnr)
  local state = watches[bufnr]
  if not state then return end
  cancel(state)
  state.generation = state.generation + 1
  local generation = state.generation
  if not require('forth-stack.config').options.auto_update then M.disable(bufnr); return end
  vim.b[bufnr].forth_stack_status = 'aguardando'
  local timer = assert(vim.uv.new_timer())
  state.timer = timer
  timer:start(require('forth-stack.config').options.debounce_ms, 0, vim.schedule_wrap(function()
    -- A fired timer may already be queued when another edit or Stop arrives.
    if watches[bufnr] ~= state or state.generation ~= generation then return end
    cancel(state)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
      M.disable(bufnr); return
    end
    local ok, err = pcall(require('forth-stack')._refresh, state.entry, bufnr, { silent = true })
    if not ok then
      vim.b[bufnr].forth_stack_status = 'erro'
      vim.b[bufnr].forth_stack_error = tostring(err)
    end
  end))
end

return M
