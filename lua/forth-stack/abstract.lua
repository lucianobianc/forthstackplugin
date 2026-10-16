-- Bounded abstract execution of data-stack operations. Never runs Forth.
local M = {}
local safe = 9007199254740991
local bit_available, bit = pcall(require, 'bit')
local limit = 16
M.max_paths = limit
local function copy(path)
  return { stack = vim.list_slice(path.stack), facts = vim.deepcopy(path.facts), assumed = path.assumed,
    loops = vim.list_slice(path.loops or {}) }
end
local function value(path, cell)
  if cell.value ~= nil then return cell.value end
  if path.facts[cell.id] == 'zero' then return 0 end
end
local function truth(path, cell)
  local n = value(path, cell)
  if n ~= nil then return n ~= 0 end
  if path.facts[cell.id] == 'nonzero' then return true end
end
local function constrain(path, cell, nonzero)
  local known = truth(path, cell)
  if known ~= nil then
    if known == nonzero then return copy(path) end
    return
  end
  local result = copy(path)
  result.facts[cell.id] = nonzero and 'nonzero' or 'zero'
  if cell.predicate then
    local wanted = nonzero == cell.predicate.nonzero
    local fact = wanted and 'nonzero' or 'zero'
    local old = result.facts[cell.predicate.id]
    if old and old ~= fact then return end
    result.facts[cell.predicate.id] = fact
  end
  return result
end
local function integer(n)
  return n and n == n and math.abs(n) <= safe and n == math.floor(n)
end
local function literal(text, base)
  local digits, radix = text, base
  if text:sub(1, 1) == '#' then digits, radix = text:sub(2), 10
  elseif text:sub(1, 1) == '$' then digits, radix = text:sub(2), 16
  elseif text:sub(1, 1) == '%' then digits, radix = text:sub(2), 2 end
  if not digits:match('^[+-]?[%da-fA-F]+$') then return false end
  -- Unprefixed alphabetic names are not assumed to be numbers.
  if digits == text and not digits:match('^[+-]?%d+$') then return false end
  if not radix then return true, nil end
  local n = tonumber(digits, radix)
  if not n then return false end
  return true, integer(n) and n or nil
end
local binary = {}
for _, op in ipairs({ '+', '-', '*', '/', 'mod', '=', '<>', '<', '>', '<=', '>=', 'u<', 'u>', 'and', 'or', 'xor', 'lshift', 'rshift', 'min', 'max' }) do binary[op] = true end
local unary = {}
for _, op in ipairs({ '0=', '0<>', '0<', '0>', 'negate', 'abs', 'invert', '2*', '2/', '1+', '1-' }) do unary[op] = true end
local function fold(op, a, b)
  if a == nil then return end
  local n
  if b ~= nil then
    if op == '+' then n = a + b elseif op == '-' then n = a - b
    elseif op == '*' and (b == 0 or math.abs(a) <= safe / math.abs(b)) then n = a * b
    elseif op == '/' and a >= 0 and b > 0 then n = math.floor(a / b)
    elseif op == 'mod' and a >= 0 and b > 0 then n = a % b
    elseif bit_available and (op == 'and' or op == 'or' or op == 'xor') and a >= -2147483648 and a <= 2147483647
      and b >= -2147483648 and b <= 2147483647 then
      n = op == 'and' and bit.band(a, b) or (op == 'or' and bit.bor(a, b) or bit.bxor(a, b))
    elseif op == 'lshift' and a >= 0 and b >= 0 and b <= 52 and a <= safe / (2 ^ b) then n = a * (2 ^ b)
    elseif op == 'rshift' and a >= 0 and b >= 0 and b < 64 then n = math.floor(a / (2 ^ b))
    elseif op == 'min' then n = math.min(a, b) elseif op == 'max' then n = math.max(a, b)
    elseif op == '=' then n = a == b and -1 or 0 elseif op == '<>' then n = a ~= b and -1 or 0
    elseif op == '<' then n = a < b and -1 or 0 elseif op == '>' then n = a > b and -1 or 0
    elseif op == '<=' then n = a <= b and -1 or 0 elseif op == '>=' then n = a >= b and -1 or 0
    elseif op == 'u<' and a >= 0 and b >= 0 then n = a < b and -1 or 0
    elseif op == 'u>' and a >= 0 and b >= 0 then n = a > b and -1 or 0 end
  else
    if op == '1+' then n = a + 1 elseif op == '1-' then n = a - 1
    elseif op == 'invert' then n = -a - 1
    elseif op == 'negate' then n = -a elseif op == 'abs' then n = math.abs(a)
    elseif op == '2*' then n = a * 2 elseif op == '2/' and a >= 0 then n = math.floor(a / 2)
    elseif op == '0=' then n = a == 0 and -1 or 0 elseif op == '0<>' then n = a ~= 0 and -1 or 0
    elseif op == '0<' then n = a < 0 and -1 or 0 elseif op == '0>' then n = a > 0 and -1 or 0 end
  end
  return integer(n) and n or nil
end

function M.new(diagnostic, budget)
  budget = budget or { steps = 0 }
  local ctx = { count = 0, steps = 0, incomplete = false, warned = false }
  function ctx.cell(text, n, predicate)
    ctx.count = ctx.count + 1
    return { text = #text > 96 and '?' or text, value = n, id = ctx.count, predicate = predicate }
  end
  function ctx.notice(token, message, warning)
    diagnostic(token, message, warning and vim.diagnostic.severity.WARN or vim.diagnostic.severity.INFO)
    if warning then ctx.warned = true else ctx.incomplete = true end
  end
  function ctx.seed(names)
    local path = { stack = {}, facts = {} }
    for _, name in ipairs(names) do path.stack[#path.stack + 1] = ctx.cell(name) end
    return { path }
  end
  local function step(token)
    ctx.steps = ctx.steps + 1
    budget.steps = budget.steps + 1
    if budget.steps > 50000 then
      ctx.notice(token, 'Analysis incomplete: symbolic execution step limit reached (50000)')
      return false
    end
    return true
  end
  local function bounded(paths, token)
    local seen, unique = {}, {}
    for _, path in ipairs(paths) do
      if #path.stack > 256 then ctx.notice(token, 'Symbolic stack exceeds 256 cells'); return end
      local key = {}
      for _, cell in ipairs(path.stack) do
        key[#key + 1] = cell.value ~= nil and ('v' .. string.format('%.0f', cell.value)) or ('s' .. cell.id)
      end
      local facts = {}
      for id, fact in pairs(path.facts) do facts[#facts + 1] = id .. ':' .. fact end
      table.sort(facts)
      for _, frame in ipairs(path.loops or {}) do key[#key + 1] = 'loop:' .. frame.index .. ':' .. frame.limit end
      key = table.concat(key, ',') .. '/' .. table.concat(facts, ',') .. tostring(path.assumed)
      if not seen[key] then unique[#unique + 1], seen[key] = path, true end
    end
    if #unique > limit then
      ctx.notice(token, 'Analysis incomplete: alternative limit reached (' .. limit .. ' paths)')
      return
    end
    return unique
  end
  local function need(paths, n, token)
    local valid, failed = {}, 0
    for _, path in ipairs(paths) do
      if #path.stack < n then failed = failed + 1 else valid[#valid + 1] = path end
    end
    if failed > 0 then
      ctx.notice(token, (failed < #paths and 'Possible stack underflow: ' or 'Documented stack effect provides too few cells: ')
        .. token.token .. ' needs ' .. n .. ' cells; ' .. failed .. ' of ' .. #paths .. ' alternatives fail', true)
    end
    return valid
  end
  local run
  run = function(def, paths, observe, depth, first, last)
    depth, first, last = depth or 0, first or 1, last or #def.code
    if depth > 16 then ctx.notice(def.name, 'Analysis incomplete: call/control nesting limit reached (16)'); return end
    local pc = first
    while pc <= last do
      local t = def.code[pc]
      local op = t.token:lower()
      if not step(t) then return end
      if t.comment then
      elseif t.called ~= nil then
        local called = t.called
        if not called or not called.signature then
          ctx.notice(t, 'Effect unknown: No usable stack effect for ' .. t.token .. '; analysis incomplete'); return
        end
        paths = need(paths, #called.signature.inputs, t)
        local after = {}
        for _, original in ipairs(paths) do
          local prefix = copy(original)
          local args = {}
          for n = #called.signature.inputs, 1, -1 do args[n] = table.remove(prefix.stack) end
          local outputs
          if called.inferable then
            if depth >= 16 then ctx.notice(t, 'Analysis incomplete: call/control nesting limit reached (16)'); return end
            outputs = run(called, {{ stack = args, facts = vim.deepcopy(original.facts), assumed = original.assumed }}, nil, depth + 1)
          elseif called.signature.output_options then
            outputs = {}
            for _, names in ipairs(called.signature.output_options) do
              local assumed = { stack = {}, facts = vim.deepcopy(original.facts), assumed = true }
              for _, name in ipairs(names) do
                local label = name
                -- Numeric output constraints are assumptions of the contract.
                local _, constant = literal(name, 10)
                assumed.stack[#assumed.stack + 1] = ctx.cell(label, constant)
              end
              outputs[#outputs + 1] = assumed
            end
          else ctx.notice(t, 'Effect unknown: variable contract for ' .. t.token .. '; analysis incomplete'); return end
          if not outputs then return end
          for _, output in ipairs(outputs) do
            local joined = copy(prefix)
            vim.list_extend(joined.stack, output.stack)
            joined.facts, joined.assumed = output.facts, output.assumed
            after[#after + 1] = joined
          end
        end
        paths = after
      elseif t.string then
        if op == '."' and t.closed then
          -- Standard dot-quote prints its parsed literal without changing data cells.
        else
          ctx.notice(t, (t.closed == false and 'Unterminated string; ' or 'Effect unknown at string/parsing word ' .. t.token .. '; ') .. 'analysis incomplete'); return
        end
      elseif op == 'do' or op == '?do' then
        local jump = def.jumps[pc]
        if not jump then ctx.notice(t, 'Unclosed counted loop; analysis incomplete'); return end
        if jump.increment ~= 'loop' then ctx.notice(t, 'Analysis incomplete: +LOOP is not supported symbolically'); return end
        if depth >= 16 then ctx.notice(t, 'Analysis incomplete: call/control nesting limit reached (16)'); return end
        paths = need(paths, 2, t)
        local after = {}
        for _, original in ipairs(paths) do
          local path = copy(original)
          local start = value(path, table.remove(path.stack))
          local stop = value(path, table.remove(path.stack))
          if start == nil or stop == nil then
            ctx.notice(t, 'Analysis incomplete: counted loop requires known integer bounds'); return
          end
          local iterations = stop - start
          if iterations <= 0 and not (op == '?do' and iterations == 0) then
            ctx.notice(t, 'Analysis incomplete: DO/LOOP wraparound is not modeled (start must be below limit)'); return
          end
          if iterations > 256 then ctx.notice(t, 'Analysis incomplete: counted loop iteration limit reached (256)'); return end
          if observe and observe(t, { path }) == false then return end
          local active = { path }
          for index = start, stop - 1 do
            if not step(t) then return end
            for _, branch in ipairs(active) do
              branch.loops[#branch.loops + 1] = { index = index, limit = stop }
            end
            active = run(def, active, observe, depth + 1, pc + 1, jump.finish - 1)
            if not active then return end
            for _, branch in ipairs(active) do table.remove(branch.loops) end
            if #active == 0 then break end
            if index < stop - 1 and observe and observe(def.code[jump.finish], active) == false then return end
          end
          vim.list_extend(after, active)
        end
        paths = after
        pc, t = jump.finish, def.code[jump.finish]
      elseif op == 'i' or op == 'j' then
        local offset = op == 'i' and 0 or 1
        local after = {}
        for _, original in ipairs(paths) do
          local path = copy(original)
          local frame = path.loops[#path.loops - offset]
          if not frame then ctx.notice(t, 'Analysis incomplete: ' .. op:upper() .. ' requires an enclosing counted loop'); return end
          path.stack[#path.stack + 1] = ctx.cell(op, frame.index)
          after[#after + 1] = path
        end
        paths = after
      elseif op == 'loop' or op == '+loop' then
        ctx.notice(t, 'Unmatched ' .. op:upper() .. '; analysis incomplete'); return
      elseif op == 'if' then
        if depth >= 16 then ctx.notice(t, 'Analysis incomplete: call/control nesting limit reached (16)'); return end
        local jump = def.jumps[pc]
        if not jump then ctx.notice(t, 'Unclosed conditional; analysis incomplete'); return end
        paths = need(paths, 1, t)
        local yes, no = {}, {}
        for _, original in ipairs(paths) do
          local flag = original.stack[#original.stack]
          local condition = truth(original, flag)
          for _, choice in ipairs({ true, false }) do
            if condition == nil or condition == choice then
              local path = constrain(original, flag, choice)
              if path then table.remove(path.stack); local target = choice and yes or no; target[#target + 1] = path end
            end
          end
        end
        if observe then
          local both = vim.list_slice(yes); vim.list_extend(both, no); if observe(t, both) == false then return end
        end
        local true_end = (jump.otherwise or jump.finish) - 1
        local yes_out = #yes > 0 and run(def, yes, observe, depth + 1, pc + 1, true_end) or yes
        if not yes_out then return end
        if jump.otherwise and observe and #no > 0 and observe(def.code[jump.otherwise], no) == false then return end
        local no_out = no
        if jump.otherwise and #no > 0 then no_out = run(def, no, observe, depth + 1, jump.otherwise + 1, jump.finish - 1) end
        if not no_out then return end
        paths = vim.list_slice(yes_out); vim.list_extend(paths, no_out)
        paths = bounded(paths, t)
        if not paths then return end
        pc, t = jump.finish, def.code[jump.finish]
      elseif op == 'else' or op == 'then' then
        ctx.notice(t, 'Unmatched ' .. op:upper() .. '; analysis incomplete'); return
      elseif op == def.name.token:lower() or op == 'recurse' then
        ctx.notice(t, 'Recursive definition; analysis incomplete'); return
      else
        local is_number, number = literal(t.token, t.base)
        local requirements = { dup = 1, ['?dup'] = 1, drop = 1, swap = 2, over = 2, rot = 3, nip = 2, tuck = 2,
          ['2dup'] = 2, ['2drop'] = 2, ['.'] = 1, emit = 1 }
        local n = requirements[op] or (binary[op] and 2) or (unary[op] and 1)
        if n then paths = need(paths, n, t) end
        if not is_number and not n and op ~= 'true' and op ~= 'false' and op ~= 'cr' and op ~= 'noop' then
          ctx.notice(t, 'Effect unknown: Analysis incomplete at unsupported word ' .. t.token); return
        end
        local after = {}
        for _, original in ipairs(paths) do
          local path = copy(original)
          local stack = path.stack
          if is_number then stack[#stack + 1] = ctx.cell(t.token, number)
          elseif op == 'true' or op == 'false' then stack[#stack + 1] = ctx.cell(op, op == 'true' and -1 or 0)
          elseif op == '?dup' then
            local cell = stack[#stack]
            local nonzero = truth(path, cell)
            if nonzero ~= true then
              local zero = constrain(path, cell, false)
              if zero then after[#after + 1] = zero end
            end
            if nonzero ~= false then
              local other = constrain(path, cell, true)
              if other then other.stack[#other.stack + 1] = cell; after[#after + 1] = other end
            end
            path = nil
          elseif op == 'dup' then stack[#stack + 1] = stack[#stack]
          elseif op == 'drop' or op == '.' or op == 'emit' then table.remove(stack)
          elseif op == 'swap' then stack[#stack], stack[#stack - 1] = stack[#stack - 1], stack[#stack]
          elseif op == 'over' then stack[#stack + 1] = stack[#stack - 1]
          elseif op == 'rot' then local cell = table.remove(stack, #stack - 2); stack[#stack + 1] = cell
          elseif op == 'nip' then table.remove(stack, #stack - 1)
          elseif op == 'tuck' then table.insert(stack, #stack - 1, stack[#stack])
          elseif op == '2dup' then local a, b = stack[#stack - 1], stack[#stack]; stack[#stack + 1] = a; stack[#stack + 1] = b
          elseif op == '2drop' then table.remove(stack); table.remove(stack)
          elseif binary[op] then
            local b, a = table.remove(stack), table.remove(stack)
            local av, bv = value(path, a), value(path, b)
            if (op == '/' or op == 'mod') and bv == 0 then
              ctx.notice(t, 'Division by zero on a symbolic alternative', true); path = nil
            else
              local folded = av ~= nil and bv ~= nil and fold(op, av, bv) or nil
              if a.id == b.id and (op == '=' or op == '<>') then folded = op == '=' and -1 or 0 end
              local predicate
              if op == '=' or op == '<>' then
                local input = bv == 0 and a or (av == 0 and b or nil)
                if input then predicate = { id = input.id, nonzero = op == '<>' } end
              end
              stack[#stack + 1] = ctx.cell('(' .. a.text .. ' ' .. t.token .. ' ' .. b.text .. ')', folded, predicate)
            end
          elseif unary[op] then
            local a = table.remove(stack)
            local folded = fold(op, value(path, a))
            local nonzero = truth(path, a)
            if (op == '0=' or op == '0<>') and nonzero ~= nil then folded = (nonzero == (op == '0<>')) and -1 or 0 end
            local text = (op == '1+' or op == '1-') and ('(' .. a.text .. (op == '1+' and ' + 1)' or ' - 1)')) or (t.token .. '(' .. a.text .. ')')
            stack[#stack + 1] = ctx.cell(text, folded, (op == '0=' or op == '0<>') and { id = a.id, nonzero = op == '0<>' } or nil)
          end
          if path then after[#after + 1] = path end
        end
        paths = after
      end
      paths = bounded(paths, t)
      if not paths then return end
      if #paths == 0 then return {} end
      if observe and not t.comment and observe(t, paths) == false then return end
      pc = pc + 1
    end
    return paths
  end
  ctx.run = run
  function ctx.snapshots(paths)
    local alternatives, seen, known, assumed = {}, {}, {}, false
    for _, path in ipairs(paths) do
      local stack, constants = {}, {}
      for n, cell in ipairs(path.stack) do
        local v = value(path, cell)
        stack[n], constants[n] = v ~= nil and string.format('%.0f', v) or cell.text, v ~= nil
      end
      local key = vim.json.encode(stack)
      if not seen[key] then
        seen[key] = true; alternatives[#alternatives + 1] = stack; known[#known + 1] = constants
      end
      assumed = assumed or path.assumed
    end
    return alternatives, known, assumed == true
  end
  return ctx
end
return M
