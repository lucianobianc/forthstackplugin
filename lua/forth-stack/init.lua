local M = {}
local display = require('forth-stack.display')
local states, attached, reloads = {}, {}, {}
local auto_seen, inline, read_names = {}, {}, {}
local engine = require('forth-stack.engine')
local live = require('forth-stack.live')
local symbolic = require('forth-stack.symbolic')
local diagnostics = require('forth-stack.diagnostics')
local analyses = {}

local function analyze(bufnr, runtime)
  if require('forth-stack.config').options.symbolic then
    analyses[bufnr] = symbolic.refresh(bufnr, runtime)
  else symbolic.clear(bufnr); analyses[bufnr] = nil end
  return analyses[bufnr]
end

local function histories(bufnr, runtime, line)
  local source = runtime and runtime[line]
  local events = analyses[bufnr] and analyses[bufnr].lines[line]
  if not events then return { [line] = source } end
  local merged = vim.list_slice(events)
  -- Symbolic bodies and real call-site states stay distinct on mixed lines.
  for _, event in ipairs(source or {}) do
    if not event.compiled then merged[#merged + 1] = event end
  end
  return { [line] = merged }
end

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
  auto_seen[bufnr] = true
  engine.stop(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr].forth_stack_status = 'inactive'
    vim.b[bufnr].forth_stack_error = nil
  end
  close_inspect(states[bufnr])
  states[bufnr] = nil
  display.clear(bufnr)
  symbolic.clear(bufnr)
  diagnostics.clear(bufnr)
  analyses[bufnr] = nil
end

local function watch(bufnr)
  if not attached[bufnr] then
    local function changed(_, target)
      engine.stop(target)
      local state = states[target]
      states[target] = nil
      display.clear(target)
      symbolic.clear(target)
      analyses[target] = nil
      vim.schedule(function() if vim.api.nvim_buf_is_valid(target) then diagnostics.clear(target) end end)
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
        states[detached], attached[detached], analyses[detached] = nil, nil, nil
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
    assert(ok, 'Could not watch buffer changes')
    attached[bufnr] = true
  end
end

function M.show(trace, bufnr, base, partial)
  bufnr = buffer(bufnr)
  -- Validate everything before replacing an existing visualization.
  local lines = require('forth-stack.trace').lines(trace, bufnr, base or vim.fn.getcwd(), partial)
  engine.stop(bufnr)
  watch(bufnr)
  close_inspect(states[bufnr])
  auto_seen[bufnr] = true
  states[bufnr] = { lines = lines, visible = true, entry = trace.entry, partial = partial }
  local analysis = analyze(bufnr, lines)
  display.render(bufnr, lines, trace.entry, partial, analysis)
  diagnostics.clear(bufnr)
  if bufnr == vim.api.nvim_get_current_buf() then M.cursor() end
end

function M.analyze(bufnr)
  bufnr = buffer(bufnr)
  M.clear(bufnr)
  watch(bufnr)
  analyses[bufnr] = symbolic.refresh(bufnr)
  states[bufnr] = { lines = {}, visible = true }
  vim.b[bufnr].forth_stack_status = 'analyzed'
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
  if not state and analyses[bufnr] then
    state = { lines = {}, visible = true }; states[bufnr] = state
  end
  if not state then return false end
  close_inspect(state)
  state.visible = not state.visible
  if state.visible then
    display.render(bufnr, state.lines, state.entry, state.partial, analyses[bufnr])
    if analyses[bufnr] then symbolic.render(bufnr, analyses[bufnr], state.lines) end
  else display.clear(bufnr); symbolic.clear(bufnr) end
  if state.visible and bufnr == vim.api.nvim_get_current_buf() then M.cursor() end
  return state.visible
end

function M.cursor(once)
  local bufnr = vim.api.nvim_get_current_buf()
  if not once and live.is_inserting(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, display.cursor_namespace, 0, -1)
    return
  end
  local state = states[bufnr]
  if state or analyses[bufnr] then
    local enabled = inline[bufnr]
    if enabled == nil then enabled = require('forth-stack.config').options.inline end
    local position = vim.api.nvim_win_get_cursor(0)
    local lines = histories(bufnr, state and state.lines, position[1])
    local row = position[1]
    local symbols = analyses[bufnr] and analyses[bufnr].lines[row]
    local line_end
    if not state or state.visible then
      line_end = display.line_end(state and state.lines[row], state and state.entry, symbols)
    end
    display.cursor(bufnr, (once or ((not state or state.visible) and enabled)) and lines or {}, position, line_end)
  end
end

function M.inline_once()
  local bufnr = buffer()
  if states[bufnr] or analyses[bufnr] then M.cursor(true); return end
  -- A one-shot inspection also works when automatic tracing is disabled.
  auto_seen[bufnr] = true
  watch(bufnr)
  local entry = live.entry(bufnr)
  if entry ~= nil then live.enable(bufnr, entry) end -- cancel a pending debounce
  engine.run(bufnr, entry or '', function(trace, target)
    M.show(trace, target, vim.fn.getcwd())
    if target == vim.api.nvim_get_current_buf() then M.cursor(true) end
  end)
end

function M.inline_toggle()
  local bufnr = buffer()
  local enabled = inline[bufnr]
  if enabled == nil then enabled = require('forth-stack.config').options.inline end
  inline[bufnr] = not enabled
  M.cursor()
  return inline[bufnr]
end

function M.auto_start(bufnr)
  bufnr = buffer(bufnr)
  if not require('forth-stack.config').options.auto_start or auto_seen[bufnr]
    or not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].buftype ~= ''
    or not vim.api.nvim_buf_get_name(bufnr):match('%.fs$') then return end
  auto_seen[bufnr] = true
  if live.entry(bufnr) ~= nil then return end
  watch(bufnr)
  live.enable(bufnr, '', not require('forth-stack.config').options.auto_update)
  live.changed(bufnr)
end

function M.start_auto()
  vim.schedule(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do M.auto_start(bufnr) end
  end)
end

function M.auto_toggle()
  local config = require('forth-stack.config').options
  config.auto_start = not config.auto_start
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(bufnr):match('%.fs$') then
      auto_seen[bufnr] = nil
      if not config.auto_start then M.stop(bufnr) else M.auto_start(bufnr) end
    end
  end
  return config.auto_start
end

function M.inspect(bufnr, line)
  bufnr = buffer(bufnr)
  local state = states[bufnr]
  local position = vim.api.nvim_win_get_cursor(0)
  local explicit_line = line ~= nil
  line = line or position[1]
  local history = histories(bufnr, state and state.lines, line)[line]
  if not explicit_line and history then
    history = display.at_token(history, position[2]) or history
  end
  if not history then return nil end
  if not state then state = { lines = {}, visible = true }; states[bufnr] = state end
  close_inspect(state)
  state.window = display.inspect(history)
  return state.window
end

function M.setup(opts)
  require('forth-stack.config').setup(opts)
  require('forth-stack.commands').register()
  M.start_auto()
end

function M.demo()
  local paths = require('forth-stack.paths')
  vim.cmd('split ' .. vim.fn.fnameescape(paths.example))
  M.load(paths.fixture)
end

function M._refresh(entry, bufnr, opts)
  bufnr = buffer(bufnr)
  watch(bufnr)
  analyze(bufnr)
  engine.run(bufnr, entry, function(trace, target)
    M.show(trace, target, vim.fn.getcwd())
  end, opts)
  close_inspect(states[bufnr])
  states[bufnr] = nil
  display.clear(bufnr)
end

function M.failure(trace, bufnr)
  -- Imported failed traces remain forbidden; only validated live Forth failures
  -- may expose successful observations from this exact source snapshot.
  if trace.status == 'forth_error' then
    local ok = pcall(M.show, trace, bufnr, vim.fn.getcwd(), true)
    if not ok then display.clear(bufnr) end
  end
  if not analyses[bufnr] then analyze(bufnr) end
  diagnostics.failure(bufnr, trace)
end

function M.run(entry, bufnr)
  entry = entry or ''
  bufnr = buffer(bufnr)
  reloads[bufnr] = nil
  auto_seen[bufnr] = true
  M._refresh(entry, bufnr)
  live.enable(bufnr, entry)
end

function M.stop(bufnr)
  bufnr = buffer(bufnr)
  reloads[bufnr] = nil
  live.disable(bufnr)
  auto_seen[bufnr] = true
  vim.b[bufnr].forth_stack_status = 'paused'
  return engine.stop(bufnr)
end

function M.status(bufnr)
  bufnr = buffer(bufnr)
  return vim.b[bufnr].forth_stack_status or 'inactive', vim.b[bufnr].forth_stack_error
end

function M.status_view(bufnr)
  bufnr = buffer(bufnr)
  local state, err = M.status(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local lines = { 'Forth Stack — diagnostics', '', 'Status: ' .. state,
    'File: ' .. (filename ~= '' and filename or '(unnamed)'), '',
    'Close: q', 'Save message: :write /tmp/forth-stack-error.txt', '', }
  vim.list_extend(lines, vim.split(err or 'No errors recorded.', '\n', { plain = true }))
  local origin = vim.api.nvim_get_current_win()
  vim.cmd('botright 12new')
  local window = vim.api.nvim_get_current_win()
  local report = vim.api.nvim_get_current_buf()
  vim.bo[report].buftype = 'nofile'
  vim.bo[report].bufhidden = 'wipe'
  vim.bo[report].buflisted = false
  vim.bo[report].swapfile = false
  vim.bo[report].filetype = 'text'
  vim.api.nvim_buf_set_lines(report, 0, -1, false, lines)
  vim.bo[report].modifiable = false
  vim.wo.wrap = true
  vim.wo.linebreak = true
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(window) then vim.api.nvim_win_close(window, true) end
    if vim.api.nvim_win_is_valid(origin) then vim.api.nvim_set_current_win(origin) end
  end, { buffer = report, silent = true })
  return report
end

vim.api.nvim_create_autocmd('BufFilePost', {
  group = vim.api.nvim_create_augroup('ForthStackSource', { clear = true }),
  callback = function(args) M.clear(args.buf) end,
})

vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufEnter', 'WinEnter' }, {
  group = 'ForthStackSource',
  callback = function(args)
    M.auto_start(args.buf)
    M.cursor()
  end,
})

vim.api.nvim_create_autocmd('InsertEnter', {
  group = 'ForthStackSource',
  callback = function(args) live.enter(args.buf); M.cursor() end,
})

vim.api.nvim_create_autocmd('InsertLeave', {
  group = 'ForthStackSource',
  callback = function(args) live.leave(args.buf) end,
})

vim.api.nvim_create_autocmd('BufReadPost', {
  group = 'ForthStackSource',
  callback = function(args)
    if not attached[args.buf] then return end
    engine.stop(args.buf)
    close_inspect(states[args.buf])
    states[args.buf] = nil
    display.clear(args.buf)
    symbolic.clear(args.buf)
    diagnostics.clear(args.buf)
    analyses[args.buf] = nil
    live.changed(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
  group = 'ForthStackSource',
  callback = function(args)
    local name = vim.api.nvim_buf_get_name(args.buf)
    if read_names[args.buf] ~= name then auto_seen[args.buf] = nil end
    read_names[args.buf] = name
    M.auto_start(args.buf)
  end,
})

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = 'ForthStackSource',
  callback = function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do live.disable(bufnr); engine.stop(bufnr) end
  end,
})

return M
