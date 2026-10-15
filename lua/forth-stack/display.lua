local M = {}
M.namespace = vim.api.nvim_create_namespace('forth-stack')

function M.stack(values)
  local text = {}
  for _, value in ipairs(values) do text[#text + 1] = string.format('%.0f', value) end
  return #text == 0 and '[ ]' or '[ ' .. table.concat(text, ', ') .. ' ]'
end

function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
  end
end

function M.render(bufnr, lines)
  M.clear(bufnr)
  vim.api.nvim_set_hl(0, 'ForthStackValue', { default = true, link = 'Comment' })
  for line, history in pairs(lines) do
    local last = history[#history]
    vim.api.nvim_buf_set_extmark(bufnr, M.namespace, line - 1, 0, {
      virt_text = {{ M.stack(last.stack) .. '  after ' .. last.token, 'ForthStackValue' }},
      virt_text_pos = 'eol',
    })
  end
end

function M.inspect(history)
  local last = history[#history]
  local text = { 'Stack: ' .. M.stack(last.stack), 'After: ' .. last.token,
    'Event: ' .. last.seq, 'Observations on this line: ' .. #history,
    'Top on the right; value types are not inferred.' }
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  local width = 1
  for _, line in ipairs(text) do width = math.max(width, vim.fn.strdisplaywidth(line)) end
  return vim.api.nvim_open_win(buf, false, {
    relative = 'cursor', row = 1, col = 0, style = 'minimal', border = 'single',
    width = math.min(width, math.max(1, vim.o.columns - 4)), height = #text,
  })
end

return M
