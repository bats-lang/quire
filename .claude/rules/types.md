---
paths:
  - src/**/*.bats
---

# Linear values and datatypes

## What allocates is linear

wasm has no garbage collector, so outside `$UNSAFE` nothing that
allocates is non-linear (bats-lang/bats#224): a type whose constructor
carries data is a `datavtype`, consumed by a `case+ ~` match (a list
has a `_free` walk); a closure is a `lincloptr1`, made with `llam`.

Quire never frees a closure itself (`cloptr_free` needs `$UNSAFE`):
each one is handed to a library that runs it once and frees it, a
promise (`$P.finish`, `$P.and_then`) or the bridge (a listener of the
`regs` table, `ui_listen_all`). What waits for a later answer keeps a
promise's resolver, not a closure: the Undo offer (`undo_offer`
returns the promise of how it `settled`: `Undone` or `Final`), the
dialog (`modal_open` and `modal_confirm` return the promise of its
`reply`: `Accepted` or `Declined`), a sync's round (`_rounds` in
`src/sync.bats`). The caller hands its continuation to that promise,
and the cell resolves it exactly once, so what would not have run
before (an undo made final, a dialog's other button) still runs,
told so by the value, and is freed. A function that called a closure
for each item takes data that says what to do instead (`lib_nums_set`,
`counted` in `src/annot.bats`, `regroup` in `src/library.bats`).

A promise's payload type implements `$P.dispose`, before its first use
in each module that makes a promise of it (`$P.create`, `$P.ret`,
`$P.resolved`): `bats check` does not catch a missing one, only the C
compile of `bats build` does.

## A choice is a datatype

An int never encodes one of a fixed set of cases (bats-lang/quire#192):
a choice is a datatype matched with `case+`, so a case left out does
not type-check ("pattern match is nonexhaustive"), and "none" is an
option, not -1. Ints are quantities, offsets and indexes. Stored bytes
stay as they are, decoded once as they are read and encoded once as
they are written: a book's `shelf` (`shelf_of_code`, `shelf_code`) and
cover (`image_of_code`, `image_code`), and the library view's
`sort_order`, `layout` and `book_filter` (`lib_state_set`,
`lib_state_get`, which packs them only to be saved with the settings),
and each setting of the "S2" record and the backup (`font`, `alignment`,
`hyphenation`, `image_dimming`, `tap_zones`, `volume_keys`, `readout`,
`page_flow`, `column_count`, `ruby_display`, each with its `_code` and
`_of_code`). The theme chosen is a `theme_choice`, `Auto` or
`Fixed(theme)`, kept apart from the settings record since it is linear;
a `theme` (style's `palette_theme(n)`) is indexed by its number in the
palette, `theme_palette` the one function that gives it, and the theme
rules are written from it (their selectors too), so a theme's colours
and its proofs cannot be another's.
How a sync ended is a `sync_result`, stored as its code in
"sync-state" (`_result_code`, `_result_of_code`); the store's kind a
`store_kind` (`WebDavKind`, `AndroidKind`, `BackupKind`, `DropboxKind`,
`NoStoreKind`);
and an HTTP status is read once into an `http_answer`.
An annotation's kind (`Bookmark`, or a highlight in its
`highlight_style`) is stored as its code in the "QA" record
(`_kind_code`, `_kind_of_code`), the record's version is a
`record_version`, a highlight's mark set a `mark_set`, and the list's
filter a `style_filter`. A kind is one flat datatype, not `Highlight of
highlight_style`: a constructor that carries data would make it linear,
and an annotation's numbers are copied freely.
Opening an archive is done in an `import_mode` (`Reopen`, `AddNew`,
`Replace`) and ends in an `archive_outcome`; an import's promise
resolves with an `import_outcome` (`Added(key)`, `Kept`, `Failed`), the
duplicate question with a `duplicate_answer`, and a chapter's load with
a `load_outcome` (`ChapterShown` or why not, `load_shown`).
A link found on the page is a `link_found` (`NoLink`, `InBook`,
`OutOfBook`); a spine's direction a `spine_progression`; a book's
accessibility metadata an `a11y_feature` each (its bit in the stored
flags made by `a11y_bit` alone, asked by `a11y_has`) and a
`wcag_level`; an OPDS list of links a `link_list`; the catalogue's
fields `entry_field` and `page_field`, and a refused fetch a `refusal`.
A click's target is decoded once, in `src/ui.bats`, into its listener's
own control datatype (`typography_control`, `selection_control`, ...),
each control's id given by its `*_control_id` (which
`tests/static/ids.py` reads: each must be made, none twice), and each
listener matches it with `case+`; a key event is decoded once into a
`key` and its `modifiers` (`ui_key`, `ui_modifiers`).
A dictionary's form (`dict_form`, a record: a .dict.dz, a .syn) is
its byte in "dicts" (`_form_code`, `_form_of_code`); a file to import is
a `dictionary_file`; a lookup finds a `word_match` (`Exact`,
`CaseFolded`, `NotFound`) by stardict's `word_order` (`Before`, `Same`,
`After`); an article's part is a `part_kind`.
`tests/static/case_plus.py` fails on any plain `case` (ATS2 checks only
`case+`), in CI through `tests/static/run.sh`.
