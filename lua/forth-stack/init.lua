local M = {}
local display = require('forth-stack.display')
local states, attached, reloads = {}, {}, {}
local engine = require('forth-stack.engine')
local live = require('forth-stack.live')

local function close_inspect(state)
  if state and state.window and vim.api.nvim_win_is_valid(state.window) then
    vim.api.nvim_win_close(state.window, true)
  end
end

local function buffer(bufnr)
  return bufnr and bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
end

function M.clear(bufnr)
  bufnr = buffer(bufnr)
  reloads[bufnr] = nil
  live.disable(bufnr)
  engine.stop(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr].forth_stack_status = 'inativo'
    vim.b[bufnr].forth_stack_error = nil
  end
  close_inspect(states[bufnr])
  states[bufnr] = nil
  display.clear(bufnr)
end

local function watch(bufnr)
  if not attached[bufnr] then
    local function changed(_, target)
      engine.stop(target)
      local state = states[target]
      states[target] = nil
      display.clear(target)
      vim.schedule(function() close_inspect(state) end)
      live.changed(target)
    end
    local ok = vim.api.nvim_buf_attach(bufnr, false, {
      on_lines = changed,
      on_reload = changed,
      on_detach = function(_, detached)
        local ticket = {}
        reloads[detached] = ticket
        local entry = live.entry(detached)
        local name = vim.api.nvim_buf_is_valid(detached) and vim.api.nvim_buf_get_name(detached)
        live.disable(detached)
        engine.stop(detached)
        local state = states[detached]
        states[detached], attached[detached] = nil, nil
        vim.schedule(function()
          close_inspect(state)
          -- :edit! detaches and reloads the same buffer synchronously.
          if entry and reloads[detached] == ticket and vim.api.nvim_buf_is_valid(detached)
            and vim.api.nvim_buf_is_loaded(detached)
            and vim.api.nvim_buf_get_name(detached) == name then
            watch(detached)
            live.enable(detached, entry)
            live.changed(detached)
          end
          if reloads[detached] == ticket then reloads[detached] = nil end
        end)
      end,
    })
    assert(ok, 'Não foi possível acompanhar alterações no buffer')
    attached[bufnr] = true
  end
end

function M.show(trace, bufnr, base)
  bufnr = buffer(bufnr)
  -- Validate everything before replacing an existing visualization.
  local lines = require('forth-stack.trace').lines(trace, bufnr, base or vim.fn.getcwd())
  engine.stop(bufnr)
  watch(bufnr)
  close_inspect(states[bufnr])
  states[bufnr] = { lines = lines, visible = true }
  display.render(bufnr, lines)
end

function M.load(path, bufnr)
  path = vim.fn.fnamemodify(path, ':p')
  M.show(require('forth-stack.trace').read(path), bufnr, vim.fs.dirname(path))
  reloads[buffer(bufnr)] = nil
  live.disable(buffer(bufnr))
end

function M.toggle(bufnr)
  bufnr = buffer(bufnr)
  local state = states[bufnr]
  if not state then return false end
  close_inspect(state)
  state.visible = not state.visible
  if state.visible then display.render(bufnr, state.lines) else display.clear(bufnr) end
  return state.visible
end

function M.inspect(bufnr, line)
  bufnr = buffer(bufnr)
  local state = states[bufnr]
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  local history = state and state.lines[line]
  if not history then return nil end
  close_inspect(state)
  state.window = display.inspect(history)
  return state.window
end

function M.setup(opts)
  require('forth-stack.config').setup(opts)
  require('forth-stack.commands').register()
end

function M.demo()
  local paths = require('forth-stack.paths')
  vim.cmd('split ' .. vim.fn.fnameescape(paths.example))
  M.load(paths.fixture)
end

function M._refresh(entry, bufnr, opts)
  bufnr = buffer(bufnr)
  watch(bufnr)
  engine.run(bufnr, entry, function(trace, target)
    M.show(trace, target, vim.fn.getcwd())
  end, opts)
  close_inspect(states[bufnr])
  states[bufnr] = nil
  display.clear(bufnr)
end

function M.run(entry, bufnr)
  bufnr = buffer(bufnr)
  reloads[bufnr] = nil
  M._refresh(entry, bufnr)
  live.enable(bufnr, entry)
end

function M.stop(bufnr)
  bufnr = buffer(bufnr)
  reloads[bufnr] = nil
  live.disable(bufnr)
  vim.b[bufnr].forth_stack_status = 'pausado'
  return engine.stop(bufnr)
end

function M.status(bufnr)
  bufnr = buffer(bufnr)
  return vim.b[bufnr].forth_stack_status or 'inativo', vim.b[bufnr].forth_stack_error
end

vim.api.nvim_create_autocmd('BufFilePost', {
  group = vim.api.nvim_create_augroup('ForthStackSource', { clear = true }),
  callback = function(args) M.clear(args.buf) end,
})

vim.api.nvim_create_autocmd('BufReadPost', {
  group = 'ForthStackSource',
  callback = function(args)
    if not attached[args.buf] then return end
    engine.stop(args.buf)
    close_inspect(states[args.buf])
    states[args.buf] = nil
    display.clear(args.buf)
    live.changed(args.buf)
  end,
})

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = 'ForthStackSource',
  callback = function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do live.disable(bufnr); engine.stop(bufnr) end
  end,
})

return M
