---
paths:
  - src/**/*.bats
---

# Linear values and datatypes

## What allocates is linear

wasm has no garbage collector, so outside `$UNSAFE` nothing that allocates is
non-linear (bats-lang/bats#224): a type whose constructor carries data is a
`datavtype`, consumed by a `case+ ~` match; a closure is a `lincloptr1`, made
with `llam`.

Quire never frees a closure itself (`cloptr_free` needs `$UNSAFE`): each one is
handed to a library that runs it once and frees it, a promise (`$P.finish`,
`$P.and_then`) or the bridge (a listener of the `regs` table). What waits for a
later answer keeps a promise's resolver, not a closure: the Undo offer
(`undo_offer` returns the promise of how it `settled`), the dialog
(`modal_confirm` returns the promise of its `reply`), a sync's round (`_rounds`
in `src/sync.bats`). The caller hands its continuation to that promise, and the
cell resolves it exactly once, so what would not have run before (an undo made
final, a dialog's other button) still runs, told so by the value, and is freed.
A function that called a closure for each item takes data that says what to do
instead (`lib_nums_set`, `regroup` in `src/library.bats`).

A promise's payload type implements `$P.dispose`, before its first use in each
module that makes a promise of it (`$P.create`, `$P.ret`, `$P.resolved`): `bats
check` does not catch a missing one, only the C compile of `bats build` does.

No promise's value is dropped unread (`$P.discard` is not used): a chain ends
with `$P.finish`, and a value it ignores is written `llam(_) => ()` with a
comment saying why losing it is harmless.

## A choice is a datatype

An int never encodes one of a fixed set of cases (bats-lang/quire#192): a choice
is a datatype matched with `case+` (`tests/static/case_plus.py` fails any plain
`case`, since ATS2 checks only `case+`), so a case left out does not type-check,
and "none" is an option, not -1. Ints are quantities, offsets and indexes.

* Stored bytes stay as they are, decoded once as they are read and encoded once
  as they are written (`shelf_of_code`/`shelf_code`, `image_of_code`, the "S2"
  settings' `_code`/`_of_code`, `_result_code` for "sync-state", `_form_code` for
  a dictionary's form, `_kind_code` for an annotation's kind).
* A datatype that is copied freely (an annotation's kind, a `store_kind`, a
  `sort_order`) is flat: a constructor that carries data would make it linear
  (`Highlight of highlight_style` is why a kind is one flat datatype).
* A click's target is decoded once, in `src/ui.bats`, into its listener's own
  control datatype, each control's id given by its `*_control_id`
  (`tests/static/ids.py`: each must be made, none twice); a key event is decoded
  once into a `key` and its `modifiers`.
* The theme chosen is a `theme_choice`, `Auto` or `Fixed(theme)`, kept apart
  from the settings record since it is linear; a `theme` is indexed by its
  number in the palette (`theme_palette` is the one function that gives it), so
  a theme's colours and its proofs cannot be another's.
