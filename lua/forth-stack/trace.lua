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
function M.lines(trace, bufnr, base, partial)
  assert(type(trace) == 'table' and (trace.format_version == 1 or trace.format_version == 2), 'Unsupported trace format')
  assert((trace.status == 'ok' and trace.complete == true)
    or (partial and trace.status == 'forth_error' and trace.complete == false),
    'Execution is incomplete or failed')
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
    assert(vim.tbl_contains({ 'before', 'after', 'entry', 'return', 'label', 'opaque' }, event.phase), 'Invalid phase')
    local elements
    if event.elements ~= nil then
      assert(vim.islist(event.elements) and #event.elements == #stack, 'Invalid identity stack')
      elements = {}
      local ids = {}
      for i, element in ipairs(event.elements) do
        assert(type(element) == 'table' and integer(element.id, 1) and not ids[element.id]
          and element.value == stack[i], 'Invalid element identity or value')
        ids[element.id] = true
        local label = element.label
        if label == vim.NIL then label = nil end
        assert(label == nil or (type(label) == 'string' and #label <= 64
          and label:match('^[A-Za-z_][A-Za-z0-9_-]*$')), 'Invalid element label')
        local origin = element.origin
        if origin == vim.NIL then origin = nil end
        assert(origin == nil or (integer(origin, 1) and origin ~= element.id), 'Invalid element origin')
        elements[i] = { id = element.id, value = element.value, label = label, origin = origin }
      end
    end
    if trace.format_version == 2 then assert(elements ~= nil, 'Version 2 trace requires identities') end
    if event.phase == 'label' or event.phase == 'opaque' then
      assert(trace.format_version == 2, 'Identity events require trace version 2')
    end
    if event.phase == 'label' then
      assert(elements ~= nil and #elements > 0 and elements[#elements].label ~= nil,
        'Label observation has no labeled element')
    end
    if event.phase == 'before' or event.phase == 'after' or event.phase == 'label' then
      local source = event.source
      assert(type(source) == 'table', 'Event has no source location')
      if resolve(source.file, base) == filename then
        matched = true
        assert(integer(source.line, 1) and source.line <= #contents, 'Line outside the buffer')
        assert(integer(source.column_bytes, 1), 'Invalid column')
        assert(type(source.token) == 'string' and source.token ~= '', 'Missing token')
        assert(source.word == nil or type(source.word) == 'string', 'Invalid source word')
        local text = contents[source.line]
        assert(text:sub(source.column_bytes, source.column_bytes + #source.token - 1) == source.token,
          'Source differs from the trace; generate a new trace')
        if event.phase == 'label' then
          assert(text:sub(source.column_bytes):match('^%(%s*LABEL:%s*([A-Za-z_][A-Za-z0-9_-]*)%s*%)')
            == elements[#elements].label, 'Label comment differs from the trace; generate a new trace')
        end
        if event.phase == 'after' or event.phase == 'label' then
          lines[source.line] = lines[source.line] or {}
          table.insert(lines[source.line], {
            seq = event.seq, token = source.token, stack = stack,
            partial = partial == true,
            compiled = source.word ~= nil and source.word ~= '<top-level>',
            column_bytes = source.column_bytes, elements = elements, phase = event.phase,
            label = event.phase == 'label' and elements[#elements].label or nil,
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
