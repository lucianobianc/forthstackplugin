# Forth Stack Visualizer for Neovim
**Project Specification — Version 0.1**

- **Status:** Initial proposal
- **Plugin language:** Lua
- **Editor:** Neovim
- **Forth engines:** Gforth initially; pForth in the future
- **Primary platform:** Linux

---

## 1. Overview

The project is a Neovim plugin that visualizes the data stack during execution
of Forth programs.

The visualization should appear directly beside source lines, allowing the
programmer to follow values as they change and identify stack elements using
custom labels.

The system will use a real Forth interpreter as its execution engine rather than
relying exclusively on static analysis.

The plugin must not change Forth syntax, semantics, or source files.

### 1.1 Main objective

Make the flow of data in Forth programs immediately understandable by displaying
intermediate stack states.

### 1.2 Principles

1. Preserve the Forth language in full.
2. Use Neovim's native capabilities.
3. Use existing Forth interpreters.
4. Minimize manual configuration.
5. Automate value and label tracking wherever possible.
6. Separate execution, analysis, presentation, and persistence.
7. Develop incrementally, keeping the system functional at each stage.

---

## 2. User experience

### 2.1 Stack visualization

After executing a program, the plugin should show stack states beside the
corresponding lines.

Conceptual example:

```forth
15                 [ AGE: 15 ]
BIRTHDAY           [ AGE: 16 ]
18                 [ AGE: 16, 18 ]
>=                 [ FALSE ]
```

Bracketed contents represent visual elements produced by the plugin. They are
not part of the Forth file. The top of the stack appears on the right.

The representation should distinguish numeric values, logical values, and other
types when there is enough information to do so safely.

### 2.2 Custom labels

The user should be able to name stack elements.

```text
Before: [ 15 ]
After:  [ AGE: 15 ]
```

Labels are assigned through a Neovim interaction without changing the source.
A label conceptually identifies an element, not merely its position or number.

### 2.3 Automatic label propagation

Labels should follow elements through transformations that preserve their
conceptual identity.

```forth
15                 [ AGE: 15 ]
BIRTHDAY           [ AGE: 16 ]
```

When an operation consumes elements and produces a semantically different result,
labels must not be transferred automatically.

```forth
15                 [ AGE: 15 ]
18                 [ AGE: 15, 18 ]
>=                 [ FALSE ]
```

The comparison result does not inherit `AGE`.

**Fundamental rule:** identity preservation cannot be inferred solely from the
number of elements consumed and produced.

The analyzer should combine execution information, propagation rules, and
provenance tracking. For ambiguous cases, the initial policy is not to propagate
the label, avoiding potentially incorrect information.

### 2.4 Stack manipulation

The analyzer should initially understand these operations:

| Word | Expected behavior |
| --- | --- |
| `DUP` | Duplicates an element and its identity information |
| `DROP` | Removes an element and its label |
| `SWAP` | Swaps elements and labels |
| `OVER` | Copies the corresponding element and its label |
| `ROT` | Rearranges elements and labels |
| `NIP` | Removes the corresponding element |
| `TUCK` | Rearranges and duplicates the corresponding elements |

Copies must have distinct instance identities while retaining their origin link.
Arithmetic and logical operations need their own propagation rules; they must
not all be assumed to preserve identity.

---

## 3. Dynamic execution

### 3.1 Forth engine

The first implementation will use Gforth. The architecture should allow other
engines, such as pForth, to be added later. Their internal instrumentation
mechanisms must not be assumed to be equivalent.

### 3.2 Instrumentation

The plugin must obtain enough information to reconstruct intermediate stack
states during execution. Where technically available, this includes:

- The execution location in the source.
- Stack states before and after observed operations.
- The operation executed.
- Chronological execution order.
- Information needed to track element origins.

Inspecting the stack only at the end of the program is insufficient.
Instrumentation of compiled words must be investigated specifically for Gforth.

**Gforth is not assumed to expose all this information through a ready-made API.**
Additional instrumentation may be necessary.

### 3.3 Controlled execution

The user must explicitly start execution:

```vim
:ForthStackRun
```

After starting with `:ForthStackRun` (whole file) or `:ForthStackRun word` (file
plus an additional word call), visualization updates automatically after a pause
in typing, including unsaved changes. Each edit cancels previous runs and
invalidates their results. `:ForthStackStop` pauses tracking. This revision
replaces the original restriction to manual execution only.

The interpreter must run in a process separate from Neovim. The plugin must
support interruption and configurable time and recording-volume limits.
These limits alone do not provide security isolation; untrusted Forth programs
require additional sandboxing.

### 3.4 Multiple executions

A line may execute multiple times, particularly in loops. The system should
preserve observed-state history and allow selection of a particular occurrence.
Initially, it may show only the latest occurrence, provided the architecture
allows future history navigation.

### 3.5 Conditional paths

The analyzer must reflect the path actually taken during execution. It need not
compute all possible paths through static analysis. Displayed results depend on
the input used in the observed execution.

---

## 4. Identity model

Each observed stack element should have an internal representation independent
of its concrete value.

```text
StackElement
    instance_id
    value
    label
    origin
    history
```

- `instance_id`: identifies the observed instance.
- `value`: represents the value obtained during execution.
- `label`: optional user-assigned label.
- `origin`: creation or derivation information.
- `history`: references to recorded transformations.

Instance IDs are valid within one run, not necessarily across different runs.
The model must distinguish:

1. Identity preservation.
2. Copying an element.
3. Transforming an element.
4. Combining elements.
5. Consumption and disposal.
6. Creation of a new element.

### 4.1 Limits of automatic inference

Conceptual identity cannot always be determined from execution alone.
Two words with similar stack effects may represent semantically different
operations. The system must therefore support:

- Known automatic rules.
- Provenance tracking.
- Conservative rules for unknown operations.
- Optional user adjustments, without requiring them for everyday use.

Perfect semantic inference is not required.

---

## 5. Neovim integration

### 5.1 Technology

The plugin will be developed primarily in Lua, using Neovim's native APIs.

### 5.2 Virtual text

Stack states will initially use virtual text. Displayed contents must not alter
the text stored in the buffer.

### 5.3 Extmarks

Extmarks will associate visual information with source positions. They must not
be treated as persistent, infallible instruction identifiers. Associations must
be invalidated or reconciled when code changes.

### 5.4 Initial interface

Proposed commands:

| Command | Function |
| --- | --- |
| `:ForthStackRun` | Execute and collect states |
| `:ForthStackClear` | Remove visualizations |
| `:ForthStackToggle` | Show or hide visualizations |
| `:ForthStackInspect` | Inspect the stack at the selected location |
| `:ForthStackLabel` | Assign or change a label |
| `:ForthStackStop` | Interrupt execution |

Names are provisional. Users must be able to configure shortcuts without the
plugin imposing global keymaps.

### 5.5 Detailed visualization

A floating window may show the entire stack, including contents wider than the
available line. Presentation must remain readable across terminals and color
schemes.

---

## 6. Metadata persistence

Labels and code-related preferences should be stored in separate files.

```text
program.fs
program.stack.json
```

The `.fs` file must remain untouched by the plugin. The companion file may contain:

- User-assigned labels.
- References to element creation locations.
- User-defined propagation rules, when needed.
- File-specific display preferences.

Execution states need not be persisted initially.

### 6.1 Associating labels with code

Storing only line numbers or temporary execution IDs is insufficient. The system
must provide a strategy to find label assignment locations again in later runs.
This may combine file location, syntactic context, and operation identification.

Changes that prevent a reliable association must invalidate or flag the label
rather than silently attaching it to the wrong element.

### 6.2 Format

JSON is the initially proposed format. The final schema will follow validation
of the label association mechanism. A format version identifier must allow
future migrations.

---

## 7. Proposed architecture

```text
forth-stack.nvim/
├── lua/
│   └── forth-stack/
│       ├── init.lua
│       ├── config.lua
│       ├── display.lua
│       ├── labels.lua
│       ├── stack.lua
│       ├── trace.lua
│       ├── persistence.lua
│       └── engine/
│           ├── init.lua
│           └── gforth.lua
├── plugin/
│   └── forth-stack.lua
├── tests/
├── examples/
├── doc/
└── README.md
```

Responsibilities must remain separate:

**Engine:** executes programs and supplies observable events.

**Tracing:** reconstructs states and relationships between elements.

**Labels:** manages names and propagation rules.

**Persistence:** stores and retrieves metadata.

**Interface:** presents results in Neovim.

The engine/analyzer protocol must be documented and independent of presentation.

---

## 8. Initial scope

### Included

- Neovim on Linux.
- Lua plugin.
- Initial Gforth integration.
- Explicit file or word execution and automatic updates with debounce.
- Stack visualization with virtual text.
- Custom labels.
- Companion-file persistence.
- Basic stack-operation tracking.
- Simple arithmetic transformations.
- Recording observed states.
- Error handling and interruption.

### Outside the initial scope

- Developing a new Forth interpreter.
- Simultaneous support for multiple interpreters.
- Complete static analysis.
- Perfect semantic inference.
- Changing Forth syntax.
- A standalone GUI independent of Neovim.
- Full support for every Forth extension.
- Complete return-stack tracking.
- Multiple concurrent Forth tasks.

---

## 9. Development plan

### Phase 1 — Technical investigation

**Objective:** demonstrate the feasibility of Gforth instrumentation.

Investigate observing intermediate states and linking them to source
instructions, including inside compiled words.

Deliverable: a minimal prototype that executes a Forth example and produces a
structured state log.

**Acceptance criterion:** demonstrate tracing inside a user-defined word, not
only between top-level interpreted lines. If the mechanism cannot do this,
document its limitations and evaluate alternatives before proceeding.

### Phase 2 — Neovim visualization

Implement virtual-text stack displays, initially using test execution logs.

**Acceptance criterion:** correctly display different states beside their source
lines without modifying the buffer.

### Phase 3 — Identity model

Implement a parallel stack and basic operation tracking.

**Acceptance criterion:** movements, duplication, and removal correctly preserve
associations between elements and labels.

### Phase 4 — Labels and persistence

Allow interactive label assignment and companion-file storage.

**Acceptance criterion:** close and reopen a file, rerun the program, and recover
labels at reliably identified locations.

### Phase 5 — Functional integration

Integrate execution, tracing, labels, and visualization.

**Acceptance criterion:** run a real Forth program, visualize its states, and
track labels automatically through supported operations.

### Phase 6 — Control structures

Extend tracing to conditionals, loops, and repeated execution.

**Acceptance criterion:** show the path actually executed and distinguish
multiple occurrences on the same line.

### Phase 7 — Extensibility

Document the engine interface and evaluate pForth integration. Actual pForth
support depends on a later decision.

---

## 10. Nonfunctional requirements

### Performance

The plugin must not block Neovim during execution or processing of large logs.
History needs configurable limits to prevent uncontrolled memory growth.

### Reliability

Unexpected interpreter termination must not compromise the Neovim session.
Instrumentation failures must be reported. Incomplete states must not be
presented as complete, reliable logs.

### Compatibility

The minimum Neovim version and supported Gforth versions must be defined and
documented after initial testing.

### Testability

Tracing, label propagation, and persistence components need tests independent
of the interface. Interpreter integration must be tested with small,
reproducible Forth programs.

---

## 11. Open technical questions

The initial investigation must address:

1. Which Gforth mechanism can record operations inside compiled words?
2. What instrumentation granularity is feasible: source word, executed primitive,
   or both?
3. How can states be read reliably without misinterpreting addresses, flags,
   or other value types?
4. How can words with variable stack effects be traced?
5. How can identities be reconstructed for unconventional stack manipulation?
6. How can persistent labels be associated with values created in loops and
   repeated calls?
7. What happens when a word cannot be instrumented?
8. How can event volume be controlled without excessive performance costs?

These questions must not be answered by assumption.

---

## 12. Definition of success

The first functional version is successful when the user can:

1. Open a Forth program in Neovim.
2. Run it using Gforth through the plugin.
3. View intermediate stack states beside the code.
4. Assign a label to an element.
5. See that label follow supported transformations.
6. See the label removed when the element is consumed without identity preservation.
7. Close and reopen the file while keeping labels persisted separately.
8. Do this without changing the language or inserting source annotations.

The result should make Forth's flow of data visible while preserving the
language's simplicity and character.
