vim.opt.runtimepath:prepend(vim.fn.getcwd())
local symbolic = require('forth-stack.symbolic')
local display = require('forth-stack.display')
local function analyze(code) return symbolic.analyze(vim.split(code, '\n', { plain = true })) end
local function last(result, row)
  local events = assert(result.lines[row], vim.inspect(result))
  return events[#events]
end
local passed = 0
local function test(name, callback) callback(); passed = passed + 1; print('PASS ' .. name) end
local ok, err = pcall(function()
  test('known counted loops agree with real Gforth including nesting and branches', function()
    for _, body in ipairs({
      '0 3 0 do i + loop', '0 3 0 ?do i + loop', '7 0 0 ?do 99 loop',
      '0 3 1 do i + loop', '0 0 -3 do i + loop',
      '0 3 0 do 2 0 do i j + + loop loop',
      '0 4 0 do i 2 < if 1+ else 2 + then loop',
      '3 0 do i loop', '0 256 0 do 1+ loop',
    }) do
      local result = analyze(': sample ( -- ... ) ' .. body .. ' ;')
      assert(#result.diagnostics == 0, body .. ': ' .. vim.inspect(result.diagnostics))
      local execution = vim.system({ 'gforth', '-e', ': sample ' .. body .. ' ; sample decimal .s bye' }, { text = true }):wait()
      assert(execution.code == 0, execution.stderr)
      local values = assert(execution.stdout:match('<%d+>%s*(.-)%s*$'))
      local actual = {}; for n in values:gmatch('%S+') do actual[#actual + 1] = n end
      assert(vim.deep_equal(last(result, 1).stack, actual), body .. ': ' .. vim.inspect(result))
    end
  end)
  test('observations evolve per iteration without importing later caller values', function()
    local result = analyze(': total ( -- sum )\n0\n3 0 do\ni +\nloop\n;\n999 total')
    assert(#result.diagnostics == 0)
    local states = {}
    for _, e in ipairs(result.lines[4]) do if e.token == '+' then states[#states + 1] = e.stack[1] end end
    assert(vim.deep_equal(states, { '0', '1', '3' }), vim.inspect(states))
    assert(last(result, 5).stack[1] == '3')
    assert(not result.lines[7])
  end)
  test('symbolic inputs alternatives and supported callees survive counted loops', function()
    local result = analyze(': inc ( n -- n ) 1+ ;\n: test ( n -- ... )\n3 0 do inc loop\n?dup\n;')
    assert(#result.diagnostics == 0, vim.inspect(result))
    assert(#last(result, 4).alternatives == 2)
    local branching = analyze(': test ( flag -- ... )\n0 2 0 do over if 1+ else 2 + then loop\n;')
    assert(#branching.diagnostics == 0, vim.inspect(branching))
    assert(display.observation(last(branching, 2), 16) == '[ flag, 2 ] | [ 0, 4 ]')
  end)
  test('unknown wrapping excessive and unsupported loops stop with explicit notices', function()
    for _, case in ipairs({
      { '0 do 1 loop', 'known integer bounds', 'n' },
      { '0 0 do 1 loop', 'wraparound', '' }, { '0 3 do 1 loop', 'wraparound', '' },
      { '257 0 do 1 loop', 'iteration limit', '' },
      { '3 0 do 1 +loop', '+LOOP', '' },
      { '3 0 do leave loop', 'unsupported word leave', '' },
      { 'i', 'enclosing counted loop', '' }, { '3 0 do j loop', 'enclosing counted loop', '' },
      { '3 0 do', 'Unclosed counted loop', '' },
      { '3 0 do if loop then', 'Unclosed counted loop', '' },
    }) do
      local result = analyze(': test ( ' .. case[3] .. ' -- ... )\n' .. case[1] .. '\n99\n;')
      assert(#result.diagnostics > 0 and result.diagnostics[1].message:find(case[2], 1, true), vim.inspect(result))
      assert(not result.lines[3], 'Invented a continuation after ' .. case[1])
    end
  end)
  test('loop underflow warns and source redefinitions override native controls', function()
    local result = analyze(': test ( -- ... )\n3 0 do drop loop\n99\n;')
    assert(result.diagnostics[1].severity == vim.diagnostic.severity.WARN and not result.lines[3])
    local shadow = analyze(': i ( -- n ) 42 ;\n: test ( -- ... ) 2 0 do i loop ;')
    assert(#shadow.diagnostics == 0 and vim.deep_equal(last(shadow, 2).stack, { '42', '42' }))
    local calls = analyze(': sum ( -- n ) 0 3 0 do i + loop ;\n: test ( -- n n ) sum dup ;')
    assert(#calls.diagnostics == 0 and vim.deep_equal(last(calls, 2).stack, { '3', '3' }))
  end)
  test('empty loop iterations consume the shared step budget without observations', function()
    local abstract = require('forth-stack.abstract')
    local token = { token = 'do' }
    local budget = { steps = 49999 }
    local notices = {}
    local ctx = abstract.new(function(_, message) notices[#notices + 1] = message end, budget)
    local paths = ctx.seed({})
    paths[1].stack = { ctx.cell('256', 256), ctx.cell('0', 0) }
    local def = { name = token, code = { token, { token = 'loop' } }, jumps = { { finish = 2, increment = 'loop' } } }
    assert(not ctx.run(def, paths))
    assert(#notices == 1 and notices[1]:find('step limit reached', 1, true))
  end)
end)
if not ok then print(err); vim.cmd('cquit 1') else print(passed .. ' counted-loop tests passed'); vim.cmd('qa!') end
