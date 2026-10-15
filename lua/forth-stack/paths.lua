local source = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
return { root = root, tracer = root .. '/prototype/trace.py',
  example = root .. '/examples/compiled.fs', fixture = root .. '/tests/fixtures/compiled.json' }
