local M = {}
M.namespace = vim.api.nvim_create_namespace('forth-stack')
M.cursor_namespace = vim.api.nvim_create_namespace('forth-stack-cursor')

function M.stack(values, elements)
  local text = {}
  for i, value in ipairs(values) do
    local label = elements and elements[i] and elements[i].label
    text[#text + 1] = (label and (label .. ':') or '') .. (type(value) == 'string' and value or string.format('%.0f', value))
  end
  return #text == 0 and '[ ]' or '[ ' .. table.concat(text, ', ') .. ' ]'
end

function M.symbolic_context(event)
  if event.input then return 'symbolic inputs' end
  local notes = {}
  if event.assumed then notes[#notes + 1] = 'contract assumed' end
  if event.valid_paths_only then notes[#notes + 1] = 'valid paths only' end
  return 'symbolic' .. (#notes > 0 and (' (' .. table.concat(notes, '; ') .. ')') or '')
end

function M.observation(event, maximum)
  if not event.alternatives then return M.stack(event.stack, event.elements) end
  local seen, alternatives = {}, {}
  local minimum, maximum_depth
  for _, stack in ipairs(event.alternatives) do
    local text = M.stack(stack)
    if not seen[text] then
      seen[text] = true; alternatives[#alternatives + 1] = text
      minimum = math.min(minimum or #stack, #stack)
      maximum_depth = math.max(maximum_depth or #stack, #stack)
    end
  end
  local visible = {}
  for n = 1, math.min(#alternatives, maximum or 4) do visible[n] = alternatives[n] end
  if #visible < #alternatives then
    visible[#visible + 1] = string.format('... (%d alternatives; depth %d..%d)', #alternatives, minimum, maximum_depth)
  end
  return table.concat(visible, ' | ')
end

function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, M.cursor_namespace, 0, -1)
  end
end

-- Return the observation already represented by the end-of-line annotation.
function M.line_end(history, entry, symbols)
  local last, top
  for _, event in ipairs(history or {}) do
    if not event.compiled then top = event end
    if not event.compiled or (type(entry) == 'string' and entry ~= '') then last = event end
  end
  if symbols then return top or symbols[#symbols] end
  return last
end

function M.render(bufnr, lines, entry, partial, symbolic)
  M.clear(bufnr)
  vim.api.nvim_set_hl(0, 'ForthStackValue', { default = true, link = 'Comment' })
  for line, history in pairs(lines) do
    -- In file mode, a body event belongs to a later call, not this source line.
    local last = M.line_end(history, entry, symbolic and symbolic.lines[line])
    if last and not last.symbolic then
      local text = {{ M.stack(last.stack, last.elements) .. '  '
        .. (last.phase == 'label' and ('label ' .. last.label) or ('after ' .. last.token)), 'ForthStackValue' }}
      if partial then text[#text + 1] = { '  (before error)', 'ForthStackValue' } end
      if last.compiled then text[#text + 1] = { '  (last call)', 'ForthStackValue' } end
      vim.api.nvim_buf_set_extmark(bufnr, M.namespace, line - 1, 0, {
        virt_text = text, virt_text_pos = 'eol',
      })
    end
  end
end

-- Columns in traces are one-based bytes; Neovim cursor columns are zero-based.
function M.at_token(history, column)
  local selected = {}
  for _, event in ipairs(history or {}) do
    local start = event.column_bytes - 1
    if column >= start and column < start + #event.token then
      selected[#selected + 1] = event
    end
  end
  return #selected > 0 and selected or nil
end

function M.cursor(bufnr, lines, position, line_end)
  vim.api.nvim_buf_clear_namespace(bufnr, M.cursor_namespace, 0, -1)
  local history = M.at_token(lines[position[1]], position[2])
  if not history then return end
  local last = history[#history]
  if last == line_end then return end -- the same observation is already visible
  local text = {{ ' ' .. M.observation(last) .. ' ', 'ForthStackValue' }}
  if last.partial then text[#text + 1] = { '(before error) ', 'ForthStackValue' } end
  if last.symbolic then text[#text + 1] = { '(' .. M.symbolic_context(last) .. ') ', 'ForthStackValue' }
  elseif last.compiled then text[#text + 1] = { '(last call) ', 'ForthStackValue' } end
  vim.api.nvim_buf_set_extmark(bufnr, M.cursor_namespace, position[1] - 1,
    last.column_bytes - 1 + #last.token, {
      virt_text = text,
      virt_text_pos = 'inline', right_gravity = false,
    })
end

function M.inspect(history)
  local last = history[#history]
  local text = { 'Stack: ' .. M.observation(last),
    last.phase == 'label' and ('Label: ' .. last.label) or ('After: ' .. last.token),
    last.symbolic and 'Analysis: symbolic (documented stack effect)' or ('Event: ' .. last.seq), 'Observations on this line: ' .. #history,
    'Top on the right; value types are not inferred.' }
  if last.valid_paths_only then text[#text + 1] = 'Some alternatives fail here or earlier; only surviving paths are shown.' end
  if last.assumed then text[#text + 1] = 'Assumption: a declared callee contract was used; values are not proven.' end
  if last.alternatives and #last.alternatives > 1 then
    text[#text + 1] = 'Possible stacks (top on the right):'
    local seen = {}
    for _, alternative in ipairs(last.alternatives) do
      local formatted = M.stack(alternative)
      if not seen[formatted] then text[#text + 1] = formatted; seen[formatted] = true end
    end
  end
  if last.partial then text[#text + 1] = 'Execution incomplete: state recorded before error.' end
  if last.compiled then
    text[#text + 1] = 'Context: last call; this definition does not execute when declared.'
  end
  if last.elements then
    text[#text + 1] = ''
    for i, element in ipairs(last.elements) do
      text[#text + 1] = string.format('%d. id=%d%s%s', i, element.id,
        element.label and (' label=' .. element.label) or '',
        element.origin and (' copied from id=' .. element.origin) or '')
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  local width = 1
  for _, line in ipairs(text) do width = math.max(width, vim.fn.strdisplaywidth(line)) end
  return vim.api.nvim_open_win(buf, false, {
    relative = 'cursor', row = 1, col = 0, style = 'minimal', border = 'single',
    width = math.min(width, math.max(1, vim.o.columns - 4)), height = math.min(#text, math.max(1, vim.o.lines - 6)),
  })
end

return M
