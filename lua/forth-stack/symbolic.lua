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
  local expecting_name, shadowed = false, {}
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
      local is_name = expecting_name
      expecting_name = value == ':' and not is_name
      if is_name then shadowed[value:lower()] = true end
      if value == '\\' then
        while i <= #text and text:sub(i, i) ~= '\n' do advance() end
      elseif not is_name and not shadowed[value:lower()] and (value == '(' or value == '.(') then
        local body = i
        while i <= #text and text:sub(i, i) ~= ')' do advance() end
        if value == '(' then token.comment = text:sub(body, i - 1) else token.string = true end
        token.closed = i <= #text
        if i <= #text then advance() end
        tokens[#tokens + 1] = token
      else
        tokens[#tokens + 1] = token
        if not is_name and not shadowed[value:lower()] and (value:lower() == 's"' or value:lower() == 'c"' or value == '."' or value:lower() == 'abort"') then
          token.string = true
          while i <= #text and text:sub(i, i) ~= '"' and text:sub(i, i) ~= '\n' do advance() end
          token.closed = text:sub(i, i) == '"'
          if token.closed then advance() end
        elseif not is_name and ({ ["'"] = true, ["[']"] = true, ['[char]'] = true, char = true, postpone = true, ['[compile]'] = true })[value:lower()] then
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
  for _, name in ipairs(inputs) do
    if name == '...' or name:find('[:|%[%]{}]') then return nil, 'Only fixed data-stack inputs are supported (one name per cell)' end
  end
  for _, name in ipairs(words(left .. ' ' .. right)) do
    if #name > 64 then return nil, 'Stack effect names must have at most 64 bytes' end
    if name:find('[:%[%]{}]') then return nil, 'Only data-stack effects are supported' end
  end
  if #inputs > 256 then return nil, 'Stack effect exceeds 256 cells' end
  if right == '...' then return { inputs = inputs, flexible = true } end
  local options, current = {}, {}
  for _, name in ipairs(outputs) do
    if name == '...' then return nil, 'Use ... alone for unspecified outputs' end
    if name == '|' then options[#options + 1], current = current, {}
    else current[#current + 1] = name end
  end
  options[#options + 1] = current
  for _, names in ipairs(options) do if #names > 256 then return nil, 'Stack effect exceeds 256 cells' end end
  return { inputs = inputs, outputs = options[1], output_options = options }
end

function M.analyze(contents)
  local tokens, limited = lex(contents)
  local result = { lines = {}, diagnostics = {} }
  local vocabulary, dictionary_unknown, last_defined, base = {}, false, nil, 10
  local budget = { steps = 0, events = 0, cells = 0, bytes = 0 }
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
    if budget.exhausted or budget.steps > 50000 then break end
    local opening = tokens[i]
    if opening.token == ':' and not opening.comment then
      local name = tokens[i + 1]
      if not name then break end
      local signature, problem, body = nil, nil, i + 2
      while tokens[body] and tokens[body].comment do
        if not signature and tokens[body].comment:find('%-%-') then signature, problem = effect(tokens[body].comment) end
        body = body + 1
      end
      local finish = body
      while tokens[finish] and (tokens[finish].token ~= ';' or tokens[finish].comment) do finish = finish + 1 end
      local key = name.token:lower()
      local def = { name = name, signature = signature, code = {}, jumps = {} }
      local controls = {}
      for index = body, finish - 1 do
        local token = vim.tbl_extend('force', {}, tokens[index], { base = base })
        local op = token.token:lower()
        token.called = vocabulary[op]
        def.code[#def.code + 1] = token
        if not token.comment and not token.string and token.called == nil then
          local pc = #def.code
          if op == 'if' or op == 'do' or op == '?do' then controls[#controls + 1] = { start = pc, kind = op }
          elseif op == 'else' then
            local control = controls[#controls]
            if control and control.kind == 'if' and not control.otherwise then control.otherwise = pc end
          elseif op == 'then' then
            local control = controls[#controls]
            if control and control.kind == 'if' then
              table.remove(controls)
              def.jumps[control.start] = { otherwise = control.otherwise, finish = pc }
            end
          elseif op == 'loop' or op == '+loop' then
            local control = controls[#controls]
            if control and (control.kind == 'do' or control.kind == '?do') then
              table.remove(controls)
              def.jumps[control.start] = { finish = pc, increment = op }
            end
          end
        end
      end
      local function analyze_definition()
        if dictionary_unknown and signature then diagnostic(name, 'Dictionary-changing source precedes this definition; analysis incomplete'); return end
        if problem then diagnostic(name, problem .. '; analysis incomplete'); return end
        if not signature then return end
        if not tokens[finish] then diagnostic(name, 'Incomplete definition; analysis incomplete'); return end
        local ctx = require('forth-stack.abstract').new(diagnostic, budget)
        local observations = {}
        local function observe(token, paths)
          if #paths == 0 then return end
          local alternatives, constants, assumed = ctx.snapshots(paths)
          budget.events = budget.events + 1
          for _, stack in ipairs(alternatives) do
            budget.cells = budget.cells + #stack
            for _, text in ipairs(stack) do budget.bytes = budget.bytes + #text end
          end
          if budget.events > 10000 or budget.cells > 100000 or budget.bytes > 4 * 1024 * 1024 then
            budget.exhausted = true
            ctx.notice(token, 'Analysis incomplete: observation budget reached (10000 events / 100000 cells / 4 MiB)')
            return false
          end
          local event = { token = token.token, line = token.line, column_bytes = token.column_bytes,
            stack = alternatives[1], alternatives = alternatives, constants = constants,
            symbolic = true, phase = 'symbolic', seq = #observations,
            word = name.token, assumed = assumed, valid_paths_only = ctx.warned,
          }
          observations[#observations + 1] = event
          result.lines[token.line] = result.lines[token.line] or {}
          table.insert(result.lines[token.line], event)
        end
        local seeds = ctx.seed(signature.inputs)
        if observe(name, seeds) == false then return end
        observations[1].input = true
        local paths = ctx.run(def, seeds, observe)
        if not paths or #paths == 0 then return end
        local mismatch, depths = false, {}
        if signature.output_options then
          for _, path in ipairs(paths) do
            depths[#path.stack] = true
            local matches = 0
            for _, outputs in ipairs(signature.output_options) do if #outputs == #path.stack then matches = matches + 1 end end
            if matches == 0 then mismatch = true end
          end
          if mismatch then
            local counts = {}; for count in pairs(depths) do counts[#counts + 1] = count end; table.sort(counts)
            diagnostic(tokens[finish], 'Stack effect mismatch: ' .. (#counts > 1 and 'alternatives leave different stack depths (' or 'body leaves ')
              .. table.concat(counts, ' or ') .. (#counts > 1 and ')' or '') .. '; declared outputs do not match', vim.diagnostic.severity.WARN)
          elseif not ctx.incomplete and not ctx.warned and #observations > 1 then
            local event = observations[#observations]
            for n, stack in ipairs(event.alternatives) do
              local matches = {}
              for _, outputs in ipairs(signature.output_options) do if #outputs == #stack then matches[#matches + 1] = outputs end end
              if #matches == 1 then
                for cell, label in ipairs(matches[1]) do
                  if not event.constants[n][cell] then stack[cell] = label end
                end
              end
            end
            event.stack = event.alternatives[1]
          end
        end
        local assumed = false
        for _, path in ipairs(paths) do assumed = assumed or path.assumed end
        def.inferable = not ctx.incomplete and not assumed
        def.verified = def.inferable and not ctx.warned and not mismatch
      end
      analyze_definition()
      vocabulary[key] = def
      last_defined = key
      i = finish + 1
    elseif not opening.comment and opening.token:lower() == 'immediate' then
      if last_defined then vocabulary[last_defined] = false end
      i = i + 1
    elseif not opening.comment and not opening.string and (opening.token:lower() == 'hex' or opening.token:lower() == 'decimal') then
      if vocabulary[opening.token:lower()] ~= nil then dictionary_unknown = true
      else base = opening.token:lower() == 'hex' and 16 or 10 end
      i = i + 1
    elseif not opening.comment and ({ include = true, included = true, require = true, required = true, evaluate = true, vocabulary = true, also = true, previous = true, only = true, definitions = true, ['[if]'] = true, execute = true, catch = true, is = true, ['does>'] = true, [':noname'] = true, base = true })[opening.token:lower()] then
      dictionary_unknown = true
      i = i + 1
    elseif not opening.comment and ({ constant = true, variable = true, value = true, create = true, defer = true })[opening.token:lower()] then
      if tokens[i + 1] then vocabulary[tokens[i + 1].token:lower()] = false end
      i = i + 2
    else
      local called = vocabulary[opening.token:lower()]
      if called and not called.inferable and not opening.comment then dictionary_unknown = true end
      i = i + 1
    end
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
      local stack = require('forth-stack.display').observation(last)
      vim.api.nvim_buf_set_extmark(bufnr, M.namespace, line - 1, 0, {
        virt_text = {{ stack .. '  ' .. require('forth-stack.display').symbolic_context(last), 'ForthStackValue' }}, virt_text_pos = 'eol',
      })
    end
  end
  vim.diagnostic.set(M.diagnostics, bufnr, analysis.diagnostics, {
    virtual_text = true, underline = true, signs = true, update_in_insert = false,
  })
end

function M.refresh(bufnr, runtime)
  local analysis = M.analyze(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  M.render(bufnr, analysis, runtime)
  return analysis
end

return M
