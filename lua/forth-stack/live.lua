local M = {}
local watches, inserting = {}, {}

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

function M.enable(bufnr, entry, once)
  M.disable(bufnr)
  if once or require('forth-stack.config').options.auto_update then
    watches[bufnr] = { entry = entry, generation = 0, once = once == true }
  end
end

function M.entry(bufnr)
  return watches[bufnr] and watches[bufnr].entry
end

function M.is_inserting(bufnr)
  return inserting[bufnr] or (bufnr == vim.api.nvim_get_current_buf()
    and vim.api.nvim_get_mode().mode:match('^[iR]') ~= nil)
end

function M.enter(bufnr)
  inserting[bufnr] = true
  local state = watches[bufnr]
  if state then
    cancel(state)
    state.generation = state.generation + 1
  end
  local paused = require('forth-stack.engine').pause_automatic(bufnr)
  if paused then
    if not state then M.enable(bufnr, paused.entry, true); state = watches[bufnr] end
    state.dirty = true
  end
  if state and state.dirty then vim.b[bufnr].forth_stack_status = 'pending' end
end

function M.leave(bufnr)
  inserting[bufnr] = nil
  -- Let Neovim finish changing mode before considering a deferred update.
  vim.schedule(function()
    local state = watches[bufnr]
    if state and state.dirty and not M.is_inserting(bufnr) then M.changed(bufnr) end
  end)
end

function M.changed(bufnr)
  local state = watches[bufnr]
  if not state then return end
  cancel(state)
  state.generation = state.generation + 1
  local generation = state.generation
  if not state.once and not require('forth-stack.config').options.auto_update then M.disable(bufnr); return end
  state.dirty = true
  vim.b[bufnr].forth_stack_status = 'pending'
  if M.is_inserting(bufnr) then return end
  local timer = assert(vim.uv.new_timer())
  state.timer = timer
  timer:start(require('forth-stack.config').options.debounce_ms, 0, vim.schedule_wrap(function()
    -- A fired timer may already be queued when another edit or Stop arrives.
    if watches[bufnr] ~= state or state.generation ~= generation then return end
    cancel(state)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
      M.disable(bufnr); return
    end
    if M.is_inserting(bufnr) then return end
    state.dirty = false
    if state.once then watches[bufnr] = nil end
    local ok, err = pcall(require('forth-stack')._refresh, state.entry, bufnr,
      { silent = true, automatic = true })
    if not ok then
      vim.b[bufnr].forth_stack_status = 'error'
      vim.b[bufnr].forth_stack_error = tostring(err)
    end
  end))
end

return M
