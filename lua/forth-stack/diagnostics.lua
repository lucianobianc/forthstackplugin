local M = {}
M.namespace = vim.api.nvim_create_namespace('forth-stack-runtime-diagnostics')

function M.clear(bufnr) vim.diagnostic.reset(M.namespace, bufnr) end

function M.failure(bufnr, trace)
  local location = trace.error_location
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local line, column, end_column = 0, 0, nil
  local message = type(trace.diagnostic) == 'string' and trace.diagnostic or 'Forth execution failed'
  if type(location) == 'table' and type(location.file) == 'string'
    and (vim.uv.fs_realpath(location.file) or vim.fs.normalize(location.file))
      == (vim.uv.fs_realpath(filename) or vim.fs.normalize(filename))
    and type(location.line) == 'number' and location.line == math.floor(location.line) and location.line >= 1
    and location.line <= vim.api.nvim_buf_line_count(bufnr)
    and type(location.column_bytes) == 'number' and location.column_bytes == math.floor(location.column_bytes) and location.column_bytes >= 1
    and type(location.token) == 'string' then
    local text = vim.api.nvim_buf_get_lines(bufnr, location.line - 1, location.line, false)[1]
    if text:sub(location.column_bytes, location.column_bytes + #location.token - 1) == location.token then
      line, column = location.line - 1, location.column_bytes - 1
      end_column = column + #location.token
    end
  end
  if trace.forth_code == -4 then
    message = 'Stack underflow' .. (message:match('^stack underflow(.*)$') or (': ' .. message))
  end
  vim.diagnostic.set(M.namespace, bufnr, {{
    lnum = line, col = column, end_col = end_column, severity = vim.diagnostic.severity.ERROR,
    message = message, source = 'Forth Stack (runtime)',
  }}, { virtual_text = true, underline = true, signs = true, update_in_insert = false })
end

return M
