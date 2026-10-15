# Value labels and identities

Labels are ordinary Forth comments. Gforth ignores them, so the file can run
without the plugin. The tracer observes their execution position without
rewriting the source.

```forth
: birthday 1+ ;
: can-drive 18 >= ;

17 ( LABEL: age )
dup can-drive drop
dup birthday
can-drive
```

Run `:ForthStackRun`. Expected observations:

| Location | Displayed stack |
| --- | --- |
| Label comment | `[ age:17 ]` |
| `dup can-drive drop` | `[ age:17 ]` |
| `dup birthday` | `[ age:17, age:18 ]` |
| Final `can-drive` | `[ age:17, -1 ]` |

The top is on the right. Comparison results do not inherit their inputs' labels.
Use `:ForthStackInspect` to inspect the last observation and see IDs/copy origins.

## Annotation syntax

`( LABEL: name )` assigns `name` to the current top element. It does not name a
numeric value globally. Put it after the literal or operation producing the
value you want to identify. It can also relabel an existing top element.

- The `LABEL:` marker is uppercase.
- The opening `(` must be a separate Forth token, as in a normal Forth comment.
- The comment must close on the same source line. Multiline comments are still
  handled by Gforth, but are not recognized as label annotations.
- Names match `[A-Za-z_][A-Za-z0-9_-]{0,63}`: 1–64 ASCII characters, starting with
  a letter or underscore.
- An annotation executed with an empty stack reports a label error.
- An invalid recognized name rejects the trace with a diagnostic.
- Strings and backslash comments containing `( LABEL: ... )` are not annotations.

Inside a compiled definition, a label is applied each time execution reaches
its location. A definition that is never called produces no label observation.
The display uses a `label name` suffix at the annotation and `after TOKEN` for
ordinary operation observations.

Editing a label triggers the same automatic refresh as editing code. The source
comment is its persistence mechanism; IDs belong to a run and are not stable
across runs. Clearing or hiding the display does not erase comments. No label
editing command or companion JSON metadata file is required or implemented.

## Parallel identity stack

The Gforth stack is authoritative for values. Python reconstructs a parallel
identity stack from the chronological before/after observations. Each element
snapshot contains:

```json
{"id": 5, "value": 18, "label": "age", "origin": 1}
```

`id` identifies the instance in this run. `origin` is the immediate source ID
when an element was copied; it is null for a freshly created element. A copy has
a distinct ID and initially inherits the source label. Increment/decrement keep
that instance ID while updating its value. Previous event snapshots remain
unchanged. Relabeling a copy does not change its original.

The model does not assign labels by matching numeric values. Two `17` cells can
have different identities and labels, even when a swap leaves the numeric stack
looking identical.

## Propagation rules

| Operation | Rule |
| --- | --- |
| Numeric literal | Creates new unlabeled instance(s), preserving the existing prefix |
| `dup`, `over` | Create a new copy ID with the source's label and origin link |
| `swap`, `rot` | Move existing IDs and labels |
| `drop`, `nip` | Remove the corresponding instance |
| `tuck` | Rearranges instances and creates a distinct copy of the original top |
| `1+`, `1-` | Keep the instance and label, updating its value |
| `x 1 +`, `1 x +`, `x 1 -` | Same as unit increment/decrement when `1` has tracked literal provenance and no label |
| Comparisons | Consume their operands and create a fresh unlabeled result |
| Other supported arithmetic | Preserve untouched lower elements; create fresh unlabeled results |
| Traced user word | Uses its observed internal operations rather than guessing from its name |
| Unknown precompiled word | Clears identities/labels conservatively, even if values are unchanged |
| Opaque immediate/macro | Emits a runtime barrier that clears identities/labels |
| Unexplained stack mismatch | Creates fresh unlabeled instances; does not guess a matching prefix |

Comparison rules include `=`, `<>`, `<`, `>`, `<=`, `>=`, `u<`, `u>`, `0=`,
`0<`, `0>`, and `0<>`. General `+`, `-`, `*`, `/`, `mod`, and `/mod` do not
transfer operand labels except for the unit-offset cases above.

Primitive rules are selected by their original Gforth execution tokens captured
before loading the target. Redefining a word named `dup` does not make its body
behave like native duplication for the tracker. Aliases to the original native
word can still receive that word's rule.

Nested call events are inclusive. A caller's after event does not repeat the
transformations already observed in its body. The actual stack is checked at
boundaries; snapshots that do not agree with the reconstructed values cause
conservative resynchronization.

## Unsupported cases

This is an initial identity model, not semantic inference for all Forth.
Return-stack transfers, memory round-trips, arbitrary arithmetic, floating-point
identity, defining words, and general metaprogramming are not supported label
paths. Labels can disappear across opaque control-flow gaps or unsupported
words. Native control structures keep the existing tracing behavior; unexplained
stack changes discard identities. Opaque user immediates have explicit barriers
so a macro that swaps equal-valued elements cannot silently retain wrong labels.

The existing instrumentation limitations still apply, including custom compiler
hooks, exotic source handling, and VM introspection. IDs and copy origins are
provisional runtime provenance, not a proof of an element's conceptual meaning.
A label comment deliberately modifies the label associated with the top instance;
it does not establish that every later operation preserves that meaning.

## Trace format and validation

Unannotated programs still produce version 1 JSON with numeric `stack` arrays.
Programs with recognized label annotations use `format_version: 2`, retaining
those arrays and adding aligned `elements` arrays to every event.

Version 2 adds these phases:

- `label`: a real snapshot at a label comment. `source.label` holds the name;
  the top element carries it. The event can be rendered as a line observation.
- `opaque`: a conservative identity barrier with a real numeric snapshot. It is
  not displayed as a stack-operation observation.

Sites include an `operation` descriptor resolved by Gforth; annotation sites also
include `label`. The private Gforth stream adds `O site operation` and
`L site hex-name` metadata lines. Label probes use phase 4; barriers use phase 5.
Barriers are stripped and events renumbered when exporting unannotated version 1
traces, preserving compatibility. Numeric execution and probe limits still apply.

Neovim accepts both versions, checks identity counts, unique positive IDs per
snapshot, matching values, copy-origin shape, and label names. Version 2 requires
identities. The loader also checks the actual annotation text for label events,
so changing only `age` to `years` rejects an old imported label trace. This is
still not a complete source-hash guarantee for the entire program.

Identity arrays increase JSON size. The existing 4 MiB trace limit remains in
effect, along with the 10,000-event and 256-cell limits. This does not make the
collector suitable for unbounded workloads.

## Tests

The suite includes Python tests for the proposed example, stack operations,
equal values, identity-preserving increments/decrements, comparisons, compiled
annotations, repeated calls, loops, shadowed primitives, opaque macros, unknown
words, copy relabeling, comment/string handling, invalid annotations, and
unchanged native Gforth behavior/source files.

Headless Neovim tests verify real labeled traces, virtual text, inspection IDs,
hide/show, unsaved value/name changes, stale comment rejection, malformed identity
rejection, snapshot copying, and clearing without modifying source labels.

```sh
bash tests/run.sh
```
