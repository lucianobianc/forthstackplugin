-- Deliberately bounded source analysis. This never executes Forth.
local M = {}
M.namespace = vim.api.nvim_create_namespace('forth-stack-symbolic')
M.diagnostics = vim.api.nvim_create_namespace('forth-stack-symbolic-diagnostics')

local function words(text)
  local result = {}
  for name in text:gmatch('%S+') do result[#result + 1] = name end
  return result
end

local function lex(lines)
  local text = table.concat(lines, '\n')
  if #text > 4 * 1024 * 1024 then return {}, true end
  local tokens, i, line, col = {}, 1, 1, 1
  local function advance()
    if text:sub(i, i) == '\n' then line, col = line + 1, 1 else col = col + 1 end
    i = i + 1
  end
  while i <= #text and #tokens < 50000 do
    if text:sub(i, i):match('%s') then advance()
    else
      local start, row, column = i, line, col
      while i <= #text and not text:sub(i, i):match('%s') do advance() end
      local value = text:sub(start, i - 1)
      local token = { token = value, line = row, column_bytes = column }
      if value == '\\' then
        while i <= #text and text:sub(i, i) ~= '\n' do advance() end
      elseif value == '(' or value == '.(' then
        local body = i
        while i <= #text and text:sub(i, i) ~= ')' do advance() end
        if value == '(' then token.comment = text:sub(body, i - 1) else token.string = true end
        token.closed = i <= #text
        if i <= #text then advance() end
        tokens[#tokens + 1] = token
      else
        tokens[#tokens + 1] = token
        if value:lower() == 's"' or value:lower() == 'c"' or value == '."' or value:lower() == 'abort"' then
          token.string = true
          while i <= #text and text:sub(i, i) ~= '"' do advance() end
          if i <= #text then advance() end
        elseif ({ ["'"] = true, ["[']"] = true, ['[char]'] = true, char = true, postpone = true, ['[compile]'] = true })[value:lower()] then
          -- These parse the next name; a quoted ':' or ';' is not a delimiter.
          while i <= #text and text:sub(i, i):match('%s') do advance() end
          while i <= #text and not text:sub(i, i):match('%s') do advance() end
        end
      end
    end
  end
  return tokens, i <= #text
end

local function effect(comment)
  if not comment or not comment:find('%-%-') then return end
  local left, right = comment:match('^%s*(.-)%s+%-%-%s*(.-)%s*$')
  if comment:match('^%s*%-%-') then left, right = '', comment:match('^%s*%-%-%s*(.-)%s*$') end
  if not left or right:find('%-%-') then return nil, 'Malformed stack effect' end
  local inputs, outputs = words(left), words(right)
  for _, name in ipairs(words(left .. ' ' .. right)) do
    if #name > 64 then return nil, 'Stack effect names must have at most 64 bytes' end
    if name:find('[:|%[%]{}]') or name == '...' then
      return nil, 'Only fixed data-stack effects are supported (one name per cell)'
    end
  end
  if #inputs > 256 or #outputs > 256 then return nil, 'Stack effect exceeds 256 cells' end
  return { inputs = inputs, outputs = outputs }
end

local binary = {}
for _, op in ipairs({ '+', '-', '*', '/', 'mod', '=', '<>', '<', '>', '<=', '>=', 'u<', 'u>', 'and', 'or', 'xor', 'lshift', 'rshift', 'min', 'max' }) do binary[op] = true end
local unary = {}
for _, op in ipairs({ '0=', '0<>', '0<', '0>', 'negate', 'abs', 'invert', '2*', '2/' }) do unary[op] = true end
local function expression(s)
  return #s > 96 and '?' or s
end

function M.analyze(contents)
  local tokens, limited = lex(contents)
  local result = { lines = {}, diagnostics = {} }
  local vocabulary, dictionary_unknown, last_defined = {}, false, nil
  local function diagnostic(token, message, severity)
    result.diagnostics[#result.diagnostics + 1] = {
      lnum = token.line - 1, col = token.column_bytes - 1,
      end_col = token.column_bytes - 1 + #token.token,
      message = message, severity = severity or vim.diagnostic.severity.INFO,
      source = 'Forth Stack (symbolic)',
    }
  end
  local i = 1
  while i <= #tokens do
    local opening = tokens[i]
    if opening.token == ':' and not opening.comment then
      local name = tokens[i + 1]
      if not name then break end
      local signature, problem, body = nil, nil, i + 2
      while tokens[body] and tokens[body].comment do
        if not signature and tokens[body].comment:find('%-%-') then
          signature, problem = effect(tokens[body].comment)
        end
        body = body + 1
      end
      local finish = body
      while tokens[finish] and (tokens[finish].token ~= ';' or tokens[finish].comment) do finish = finish + 1 end
      local key = name.token:lower()
      -- A newly defined name shadows builtins, even without a usable contract.
      local function analyze_definition()
        if dictionary_unknown and signature then
          diagnostic(name, 'Dictionary-changing source precedes this definition; analysis incomplete'); return
        end
        if problem then diagnostic(name, problem .. '; analysis incomplete'); return end
        if not signature then return end
        if not tokens[finish] then diagnostic(name, 'Incomplete definition; analysis incomplete'); return end
        local stack, branches, observations = vim.deepcopy(signature.inputs), {}, {}
        local failed = false
        local function stop(token, message, severity)
          diagnostic(token, message, severity); failed = true
        end
        local function need(token, count)
          if #stack < count then
            stop(token, 'Documented stack effect provides too few cells for ' .. token.token
              .. ' (needs ' .. count .. ', has ' .. #stack .. ')', vim.diagnostic.severity.WARN)
            return false
          end
          return true
        end
        local function observe(token)
          local event = vim.tbl_extend('force', {}, token, { stack = vim.deepcopy(stack), symbolic = true,
            phase = 'symbolic', seq = #observations, word = name.token })
          observations[#observations + 1] = event
          result.lines[token.line] = result.lines[token.line] or {}
          table.insert(result.lines[token.line], event)
        end
        observe(name)
        observations[1].input = true
        for index = body, finish - 1 do
          local token, op = tokens[index], tokens[index].token:lower()
          if token.comment then
            -- LABEL comments remain runtime labels; input names come from the contract.
          elseif token.string then
            stop(token, 'Analysis incomplete at string/parsing word ' .. token.token)
          elseif vocabulary[op] ~= nil then
            local called = vocabulary[op]
            if not called or not called.inputs then stop(token, 'No usable stack effect for ' .. token.token .. '; analysis incomplete')
            elseif need(token, #called.inputs) then
              local arguments = {}
              for n = #called.inputs, 1, -1 do arguments[n] = table.remove(stack) end
              for _, output in ipairs(called.outputs) do
                -- A preserved input name denotes the corresponding caller symbol.
                local value = output
                for n, input in ipairs(called.inputs) do if output == input then value = arguments[n]; break end end
                stack[#stack + 1] = value
              end
            end
          elseif op == 'if' then
            if need(token, 1) then
              table.remove(stack)
              branches[#branches + 1] = { input = vim.deepcopy(stack) }
            end
          elseif op == 'else' then
            local branch = branches[#branches]
            if not branch or branch.yes then stop(token, 'Unmatched ELSE; analysis incomplete')
            else branch.yes, stack = vim.deepcopy(stack), vim.deepcopy(branch.input) end
          elseif op == 'then' then
            local branch = table.remove(branches)
            if not branch then stop(token, 'Unmatched THEN; analysis incomplete')
            else
              local other = branch.yes or branch.input
              if #other ~= #stack then stop(token, 'Branches leave different stack depths; analysis incomplete', vim.diagnostic.severity.WARN)
              else
                for n = 1, #stack do
                  if stack[n] ~= other[n] then stack[n] = '?' end
                end
              end
            end
          elseif op == key then
            stop(token, 'Recursive definition; analysis incomplete')
          elseif op:match('^[+-]?%d+$') or op:match('^%$[%da-f]+$') or op:match('^%%[01]+$') or op:match('^#%-?%d+$') then
            stack[#stack + 1] = token.token
          elseif op == 'true' or op == 'false' then stack[#stack + 1] = op
          elseif op == 'dup' or op == '?dup' then
            if op == '?dup' then stop(token, 'Value-dependent stack effect at ?dup; analysis incomplete')
            elseif need(token, 1) then stack[#stack + 1] = stack[#stack] end
          elseif op == 'drop' then if need(token, 1) then table.remove(stack) end
          elseif op == 'swap' then
            if need(token, 2) then stack[#stack], stack[#stack - 1] = stack[#stack - 1], stack[#stack] end
          elseif op == 'over' then if need(token, 2) then stack[#stack + 1] = stack[#stack - 1] end
          elseif op == 'rot' then
            if need(token, 3) then local value = table.remove(stack, #stack - 2); stack[#stack + 1] = value end
          elseif op == 'nip' then if need(token, 2) then table.remove(stack, #stack - 1) end
          elseif op == 'tuck' then if need(token, 2) then table.insert(stack, #stack - 1, stack[#stack]) end
          elseif op == '2dup' then
            if need(token, 2) then local a, b = stack[#stack - 1], stack[#stack]; stack[#stack + 1] = a; stack[#stack + 1] = b end
          elseif op == '2drop' then if need(token, 2) then table.remove(stack); table.remove(stack) end
          elseif op == '1+' or op == '1-' then
            if need(token, 1) then stack[#stack] = expression('(' .. stack[#stack] .. (op == '1+' and ' + 1)' or ' - 1)')) end
          elseif binary[op] then
            if need(token, 2) then
              local b, a = table.remove(stack), table.remove(stack)
              stack[#stack + 1] = expression('(' .. a .. ' ' .. token.token .. ' ' .. b .. ')')
            end
          elseif unary[op] then
            if need(token, 1) then stack[#stack] = expression(token.token .. '(' .. stack[#stack] .. ')') end
          elseif op == '.' or op == 'emit' then if need(token, 1) then table.remove(stack) end
          elseif op == 'cr' or op == 'noop' then
          else stop(token, 'Analysis incomplete at unsupported word ' .. token.token) end
          if failed then break end
          if #stack > 256 then stop(token, 'Symbolic stack exceeds 256 cells'); break end
          if not token.comment then observe(token) end
        end
        if not failed and #branches > 0 then stop(name, 'Unclosed conditional; analysis incomplete') end
        if not failed then
          if #stack ~= #signature.outputs then
            diagnostic(tokens[finish], 'Stack effect mismatch: declares ' .. #signature.outputs
              .. ' output cells, body leaves ' .. #stack, vim.diagnostic.severity.WARN)
          elseif #observations > 1 then
            -- The documented names label the verified output positions.
            observations[#observations].stack = vim.deepcopy(signature.outputs)
          end
        end
      end
      -- Recursive calls must not silently use an older definition of this name.
      vocabulary[key] = nil
      analyze_definition()
      vocabulary[key] = signature or false
      last_defined = key
      i = finish + 1
    elseif not opening.comment and opening.token:lower() == 'immediate' then
      if last_defined then vocabulary[last_defined] = false end
      i = i + 1
    elseif not opening.comment and ({ include = true, included = true, require = true, required = true, evaluate = true, vocabulary = true, also = true, previous = true, only = true, definitions = true, ['[if]'] = true, execute = true, catch = true, is = true, ['does>'] = true, [':noname'] = true })[opening.token:lower()] then
      dictionary_unknown = true
      i = i + 1
    elseif not opening.comment and ({ constant = true, variable = true, value = true, create = true, defer = true })[opening.token:lower()] then
      if tokens[i + 1] then vocabulary[tokens[i + 1].token:lower()] = false end
      i = i + 2
    else i = i + 1 end
  end
  if limited then diagnostic(tokens[#tokens] or { line = 1, column_bytes = 1, token = '' },
    'Symbolic source/token limit reached (4 MiB / 50000 tokens); remaining source was not analyzed') end
  return result
end

function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1) end
  vim.diagnostic.reset(M.diagnostics, bufnr)
end

function M.render(bufnr, analysis, runtime)
  M.clear(bufnr)
  vim.api.nvim_set_hl(0, 'ForthStackValue', { default = true, link = 'Comment' })
  local top = {}
  for line, history in pairs(runtime or {}) do
    for _, event in ipairs(history) do if not event.compiled then top[line] = true end end
  end
  for line, history in pairs(analysis.lines) do
    if not top[line] then
      local last = history[#history]
      local stack = #last.stack == 0 and '[ ]' or '[ ' .. table.concat(last.stack, ', ') .. ' ]'
      vim.api.nvim_buf_set_extmark(bufnr, M.namespace, line - 1, 0, {
        virt_text = {{ stack .. (last.input and '  symbolic inputs' or '  symbolic'), 'ForthStackValue' }}, virt_text_pos = 'eol',
      })
    end
  end
  vim.diagnostic.set(M.diagnostics, bufnr, analysis.diagnostics, {
    virtual_text = true, underline = true, signs = true, update_in_insert = true,
  })
end

function M.refresh(bufnr, runtime)
  local analysis = M.analyze(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  M.render(bufnr, analysis, runtime)
  return analysis
end

return M
