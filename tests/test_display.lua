local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.cmd('runtime plugin/forth-stack.lua')
local plugin = require('forth-stack')
local display = require('forth-stack.display')
local trace = require('forth-stack.trace')
local fixture = root .. '/tests/fixtures/compiled.json'
local passed = 0
local function check(condition, message)
  assert(condition, message)
end
local function marks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, display.namespace, 0, -1, { details = true })
end
local function test(name, callback)
  callback()
  passed = passed + 1
  print('PASS ' .. name)
end

local ok, err = pcall(function()
  vim.cmd.edit(root .. '/examples/compiled.fs')
  local buf = vim.api.nvim_get_current_buf()
  local original = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local modified = vim.bo[buf].modified
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  test('comandos registrados e desenho por linha sem editar buffer', function()
    check(vim.fn.exists(':ForthStackLoad') == 2, 'comando ausente')
    vim.cmd('ForthStackLoad ' .. fixture)
    local found = {}
    for _, mark in ipairs(marks(buf)) do found[mark[2] + 1] = mark[4].virt_text[1][1] end
    check(found[3] == '[ 16 ]  após 1+', 'estado interno de birthday incorreto')
    check(found[15] == '[ 21 ]  após +', 'última ocorrência do loop incorreta')
    check(found[10] == nil, 'ramo não executado foi desenhado')
    check(found[9] == '[ 16, 0 ]  após >=', 'último token da linha incorreto')
    check(vim.deep_equal(original, vim.api.nvim_buf_get_lines(buf, 0, -1, false)), 'texto alterado')
    check(vim.bo[buf].modified == modified and vim.api.nvim_buf_get_changedtick(buf) == tick,
      'buffer marcado como alterado')
  end)
  test('toggle preserva registros e clear remove apenas namespace próprio', function()
    local other = vim.api.nvim_create_namespace('other-plugin')
    vim.api.nvim_buf_set_extmark(buf, other, 0, 0, {})
    local count = #marks(buf)
    vim.cmd.ForthStackToggle()
    check(#marks(buf) == 0, 'toggle não ocultou')
    vim.cmd.ForthStackToggle()
    check(#marks(buf) == count, 'toggle perdeu registros')
    vim.cmd.ForthStackClear()
    check(#marks(buf) == 0, 'clear não removeu marcas')
    check(#vim.api.nvim_buf_get_extmarks(buf, other, 0, -1, {}) == 1, 'namespace externo removido')
    check(plugin.toggle() == false, 'clear preservou estado')
  end)
  test('inspect mostra pilha e histórico em janela flutuante', function()
    plugin.load(fixture)
    local win = plugin.inspect(buf, 15)
    check(win and vim.api.nvim_win_is_valid(win), 'janela ausente')
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    check(lines[1] == 'Pilha: [ 21 ]', 'pilha incorreta')
    check(lines[4] == 'Observações nesta linha: 6', 'ocorrências perdidas')
    plugin.clear()
    check(not vim.api.nvim_win_is_valid(win), 'janela obsoleta permaneceu após clear')
    check(plugin.inspect(buf, 1) == nil, 'inventou estado em linha sem evento')
  end)
  test('trace inválido e de outro arquivo não substitui visualização válida', function()
    plugin.load(fixture)
    local count = #marks(buf)
    local data = trace.read(fixture)
    data.complete = false
    check(not pcall(plugin.show, data, buf, root .. '/tests/fixtures'), 'trace incompleto aceito')
    data.complete = true
    data.format_version = 99
    check(not pcall(plugin.show, data, buf), 'versão incompatível aceita')
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(other, root .. '/examples/other.fs')
    check(not pcall(plugin.show, trace.read(fixture), other, root .. '/tests/fixtures'), 'outro arquivo aceito')
    vim.api.nvim_buf_delete(other, { force = true })
    check(#marks(buf) == count, 'falha removeu estado válido')
  end)
  test('posição divergente, sequência inválida e inteiro inexato são rejeitados', function()
    for _, change in ipairs({
      function(data) data.events[3].source.column_bytes = 999 end,
      function(data) data.events[3].seq = 999 end,
      function(data) data.events[3].stack = { 9007199254740992 } end,
      function(data) data.events[3].stack = { '16' } end,
    }) do
      local data = trace.read(fixture)
      change(data)
      check(not pcall(plugin.show, data, buf, root .. '/tests/fixtures'), 'registro inválido aceito')
    end
    check(display.stack({}) == '[ ]', 'pilha vazia incorreta')
    check(display.stack({ -1, 9007199254740991 }) == '[ -1, 9007199254740991 ]', 'inteiros formatados incorretamente')
  end)
  test('edição invalida inclusive enquanto oculto e fecha inspect', function()
    plugin.load(fixture)
    local win = plugin.inspect(buf, 15)
    vim.api.nvim_buf_set_lines(buf, 6, 7, false, { '  99' })
    check(#marks(buf) == 0, 'marcas obsoletas permaneceram')
    vim.wait(100, function() return not vim.api.nvim_win_is_valid(win) end)
    check(not vim.api.nvim_win_is_valid(win), 'inspect obsoleto permaneceu')
    check(plugin.toggle(buf) == false, 'edição não invalidou estado')
    check(not pcall(plugin.load, fixture), 'token alterado aceito')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
    plugin.load(fixture)
    plugin.toggle(buf)
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { '\\ comentário novo' })
    check(plugin.toggle(buf) == false and #marks(buf) == 0, 'estado oculto sobreviveu à edição')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
  end)
  test('buffers independentes e exclusão não ressuscita estado', function()
    plugin.load(fixture)
    vim.api.nvim_buf_set_name(buf, root .. '/examples/renamed.fs')
    check(#marks(buf) == 0 and not plugin.toggle(buf), 'renomeação preservou estado obsoleto')
    vim.api.nvim_buf_set_name(buf, root .. '/examples/compiled.fs')
    plugin.load(fixture)
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(other, root .. '/examples/unrelated.fs')
    plugin.clear(other)
    check(#marks(buf) > 0, 'clear afetou outro buffer')
    vim.api.nvim_buf_delete(other, { force = true })
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
  test('registro real gerado pelo protótipo', function()
    local real = vim.env.FORTH_STACK_TEST_TRACE
    check(real and real ~= '', 'trace real não fornecido')
    vim.cmd.edit(root .. '/examples/compiled.fs')
    plugin.load(real)
    local found = false
    for _, mark in ipairs(marks(vim.api.nvim_get_current_buf())) do
      if mark[2] == 14 and mark[4].virt_text[1][1] == '[ 21 ]  após +' then found = true end
    end
    check(found, 'pipeline Gforth → JSON → Neovim incorreto')
  end)
end)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd('cquit 1')
end
print(passed .. ' testes Neovim passaram')
vim.cmd('qa!')
