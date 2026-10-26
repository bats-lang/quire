---
paths:
  - src/cfi.bats
  - tests/cfi/**
---

# EPUB CFI (keyword: cfi, #603, #901)

The EPUB Canonical Fragment Identifier (https://idpf.org/epub/linking/cfi/, EPUB CFI 1.1, ISO/IEC 23736-6)
is how another reading system points into a book. `src/cfi.bats` writes and reads it over a
chapter's parsed tree (`xhtml_parse`); the pieces that use it are #902 (Quire's content nodes and
offsets to a CFI and back), #903 (stored in the record, the backup, the sync file, the export)
and #904 (import). Quire's own anchor (a content node and an offset) stays the primary place; a
CFI is stored beside it, as Readium's locator keeps several location types.

## What others do (searched 2026-10-26)

* The specification: even steps are child elements, odd steps the character data between them
  (0 and n + 2 virtual), `[id]` lets a reader correct a stale path, `!` enters the spine item,
  `:N` is an offset in UTF-16 code units, `[before,after]` and `[;s=b]` are assertions and a side bias,
  a range is `epubcfi(P,S,E)`, `^` escapes `[ ] ( ) , ; =` and `^`.
* Readium's annotations (https://github.com/readium/annotations) keep `P,S,E` without the
  `epubcfi()` wrapper and the resource part, the resource apart as `source`, and say that
  implementations differ on code points against code units. Quire counts UTF-16 units, as the page
  and the annotation offsets already do.
* epub.js writes `epubcfi(/6/4[chap01ref]!/4/2,/10/2[c001p0004]/1:6,/16/2[c001p0007]/1:27)` for a range
  (`test/epubcfi.js`): the common parent first and an `[id]` on each element that has one. KOReader
  writes `epubcfi(/6/10!/4/2/2[section_77306]/4,/80/2/1:0,/82/2/1:27)` (`spec/unit/readerhighlight_spec.lua`)
  and no idref in the spine step; it has no reader of a CFI in the file that makes them
  (`frontend/document/credocument.lua`). Thorium has no CFI (EDRLab, 2025-03: not yet integrated).
  Not found: Kobo's and Apple Books's formats.

## A position is a byte of the chapter

A position is a byte position in the chapter's source: an element is its `name_offset`, a place in
text is a byte boundary of a character (or of a reference such as `&amp;`) in a text node, or its end.
`cfi_of` writes the steps from the document element (the first element of the top level: `/4[body01]/...`)
and `cfi_resolve` reads them back to `@(kind, position)`:

* kind 1, an element; kind 2, a place in text; kind 3, a place in an element that has no text there
  (an empty chunk at offset 0, or the step after the last element); kind 0, nothing.
* The text between two elements is one chunk though the parser makes several text nodes of it where
  a comment was; the offset counts the units of all of them. A place at the start of a text that follows
  a comment in a chunk that has text has the steps of the end of the text before it, so it resolves to
  that end: the same steps, the other byte.
* A unit is a UTF-16 code unit of the text as the page shows it: a reference counts what `entity.bats`
  decodes it to (`&#x1F600;` is two, an unknown `&nosuch;` stays and is eight), a character outside the BMP
  is two. An offset between the two units of one is read as the start of the character; an offset
  past the end of the text is no place.
* An `[id]` that is not the one of the element its step reaches is looked for in the whole chapter
  and the steps go on from the element found; an id that is nowhere is no place (it is a place of
  another version of the chapter, which #904 keeps as "not found in this version" rather than
  guessing from the step). Text assertions, side bias and spatial or temporal offsets are read
  (`cfi_terminal`) and kept in the string, never used to find the place and never written.
* The spine step (`/6/N[idref]!`, the item `N / 2 - 1` of the spine) is the package's: `cfi_put_spine`
  writes it, `cfi_spine` reads it, and the caller finds the chapter.
* Ranges: `cfi_make_range` writes `epubcfi(<spine>P,S,E)`, P being the steps the two ends share up to
  the last step they share whole; `cfi_resolve_range` reads one (a CFI that is not a range gives its place
  twice).

## What is proved and what is tested

Proved by types and termination metrics (no `praxi`, no `assume`, no `$UNSAFE`): every read of the
chapter and of the CFI is at an index inside its array, every walk of the tree and of the steps ends,
the writer never writes past its buffer (a full buffer is a result, -1, not a cut CFI), and a node's
span is inside the chapter (xml-tree's constructors). The module has no lemma of its own, so there is no
statement to make false for the mutation check (`tests/static/mutation_check.py` finds "no lemma to mutate").

Tested (`tests/cfi/run.sh`, native; a `build` step of `check.yml` beside the codec's): the specification's
own examples, epub.js's fixture chapter (`tests/cfi/fixtures/epubjs-chapter1.xhtml`, with the CFIs its tests
assert), KOReader's three CFIs against a chapter shaped to have their steps, an astral character and a reference,
and 399 generated chapters (a printed range of seeds) in which a generator that knows the steps of
each position it makes (text tokens of one to eight units, comments, ids, empty elements, white space)
is checked against `cfi_of` at every one, and `cfi_resolve` of those steps against the position. The
positions inside a tag and a comment must give no steps.

Limits: a path is at most 255 bytes in the tests; `cfi_of`'s buffer needs 11 bytes of room beyond the
steps (a number is written whole or not at all); `cfi_resolve_range` reads a CFI of at most 1048576 bytes
(an array's limit); a number in a step saturates at 10^8.
