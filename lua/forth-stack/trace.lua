local M = {}
local safe_integer = 9007199254740991

local function integer(value, minimum)
  return type(value) == 'number' and value == math.floor(value)
    and value >= minimum and value <= safe_integer
end

local function resolve(path, base)
  assert(type(path) == 'string' and path ~= '', 'Missing source file')
  if path:sub(1, 1) ~= '/' then path = base .. '/' .. path end
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

-- Return only copied, validated events for the requested buffer.
function M.lines(trace, bufnr, base)
  assert(type(trace) == 'table' and trace.format_version == 1, 'Unsupported trace format')
  assert(trace.status == 'ok' and trace.complete == true, 'Execution is incomplete or failed')
  assert(vim.islist(trace.events) and #trace.events <= 10000, 'Event limit: 10000')
  local filename = resolve(vim.api.nvim_buf_get_name(bufnr), vim.fn.getcwd())
  local contents = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lines, matched = {}, false
  for index, event in ipairs(trace.events) do
    assert(type(event) == 'table' and event.seq == index - 1, 'Invalid event sequence')
    assert(vim.islist(event.stack) and #event.stack <= 256, 'Invalid stack or more than 256 cells')
    local stack = {}
    for _, value in ipairs(event.stack) do
      assert(integer(value, -safe_integer), 'Cell outside Lua’s exact integer range (±2^53−1)')
      stack[#stack + 1] = value
    end
    assert(vim.tbl_contains({ 'before', 'after', 'entry', 'return' }, event.phase), 'Invalid phase')
    if event.phase == 'before' or event.phase == 'after' then
      local source = event.source
      assert(type(source) == 'table', 'Event has no source location')
      if resolve(source.file, base) == filename then
        matched = true
        assert(integer(source.line, 1) and source.line <= #contents, 'Line outside the buffer')
        assert(integer(source.column_bytes, 1), 'Invalid column')
        assert(type(source.token) == 'string' and source.token ~= '', 'Missing token')
        local text = contents[source.line]
        assert(text:sub(source.column_bytes, source.column_bytes + #source.token - 1) == source.token,
          'Source differs from the trace; generate a new trace')
        if event.phase == 'after' then
          lines[source.line] = lines[source.line] or {}
          table.insert(lines[source.line], {
            seq = event.seq, token = source.token, stack = stack,
            column_bytes = source.column_bytes,
          })
        end
      end
    end
  end
  assert(matched or (type(trace.source) == 'string' and resolve(trace.source, base) == filename),
    'Trace contains no events for this file')
  return lines
end

function M.read(path)
  local stat = vim.uv.fs_stat(path)
  assert(stat and stat.type == 'file', 'Trace not found')
  assert(stat.size <= 4 * 1024 * 1024, 'Trace limit: 4 MiB')
  return vim.json.decode(table.concat(vim.fn.readfile(path, 'b'), '\n'))
end

return M
