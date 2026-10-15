-- nvim -u examples/minimal-init.lua -c ForthStackDemo
local filename = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local root = vim.fs.dirname(vim.fs.dirname(filename))
vim.opt.runtimepath:prepend(root)
require('forth-stack').setup()
