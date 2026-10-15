local M = {}
M.namespace = vim.api.nvim_create_namespace('forth-stack')
M.cursor_namespace = vim.api.nvim_create_namespace('forth-stack-cursor')

function M.stack(values, elements)
  local text = {}
  for i, value in ipairs(values) do
    local label = elements and elements[i] and elements[i].label
    text[#text + 1] = (label and (label .. ':') or '') .. string.format('%.0f', value)
  end
  return #text == 0 and '[ ]' or '[ ' .. table.concat(text, ', ') .. ' ]'
end

function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, M.cursor_namespace, 0, -1)
  end
end

function M.render(bufnr, lines, entry)
  M.clear(bufnr)
  vim.api.nvim_set_hl(0, 'ForthStackValue', { default = true, link = 'Comment' })
  for line, history in pairs(lines) do
    -- In file mode, a body event belongs to a later call, not this source line.
    local last
    for _, event in ipairs(history) do
      if not event.compiled or (type(entry) == 'string' and entry ~= '') then last = event end
    end
    if last then
      local text = {{ M.stack(last.stack, last.elements) .. '  '
        .. (last.phase == 'label' and ('label ' .. last.label) or ('after ' .. last.token)), 'ForthStackValue' }}
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

function M.cursor(bufnr, lines, position)
  vim.api.nvim_buf_clear_namespace(bufnr, M.cursor_namespace, 0, -1)
  local history = M.at_token(lines[position[1]], position[2])
  if not history then return end
  local last = history[#history]
  local text = {{ ' ' .. M.stack(last.stack, last.elements) .. ' ', 'ForthStackValue' }}
  if last.compiled then text[#text + 1] = { '(last call) ', 'ForthStackValue' } end
  vim.api.nvim_buf_set_extmark(bufnr, M.cursor_namespace, position[1] - 1,
    last.column_bytes - 1 + #last.token, {
      virt_text = text,
      virt_text_pos = 'inline', right_gravity = false,
    })
end

function M.inspect(history)
  local last = history[#history]
  local text = { 'Stack: ' .. M.stack(last.stack, last.elements),
    last.phase == 'label' and ('Label: ' .. last.label) or ('After: ' .. last.token),
    'Event: ' .. last.seq, 'Observations on this line: ' .. #history,
    'Top on the right; value types are not inferred.' }
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
