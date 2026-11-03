---
paths:
  - src/text_encoding.bats
  - src/text_tables.bats
  - src/text_relation.bats
  - src/text_proved.bats
  - src/text_labels.bats
  - src/text_codes.bats
  - src/language.bats
  - src/css_size.bats
  - src/css_cascade.bats
  - src/publisher_size.bats
  - src/epub_xml.bats
  - scripts/gen-encodings.py
  - tests/css-size/**
  - e2e/encoding*
  - e2e/languages*
  - e2e/series*
  - e2e/size-books*
  - e2e/publisher-sizes*
---

# Encodings, languages, series and the CSS sizes

## Encodings and languages (#436)

**Text documents are read as UTF-8 whatever they are encoded in**
(`src/text_encoding.bats`, tables in `src/text_tables.bats` made by
`scripts/gen-encodings.py`). Every document that is text (container, package,
navigation document, content document, overlay, encryption.xml; not an image,
font or audio) goes through `take_text` (`src/book.bats`): a byte order mark says
the encoding (UTF-8's is dropped, UTF-16 either way becomes UTF-8), so does `<`
and a null byte; else the XML declaration's `encoding` by the WHATWG labels
(`iso-8859-1`, `latin1`, `us-ascii` are windows-1252, as in a browser) for UTF-8
or a single-byte encoding with a table here (windows-1250 to 1257, ISO-8859-2, 5,
7, 8, 15, KOI8-R); else UTF-8.

* A document that is not UTF-8, or an encoding with no table (Shift_JIS, GBK) in
  a document that is not ASCII only, is refused ("Chapter N of this book could
  not be read", `PlanRefused`): XML calls it fatal, and a guess is mojibake. A
  document that says a single-byte encoding but is valid UTF-8 with non-ASCII
  characters is read as UTF-8. A plain UTF-8 document is not copied (`PlanAsIs`).
* A title, author or series in the package has its references decoded
  (`_span_arr`), and the library sorts by letters (`_fold`: Latin letters without
  their accents, so Łukasz is under L; other scripts by code point).

**Languages.** Quire does not guess a book's language from its text (no reading
system researched does): no `dc:language` is `und`, with the voice automatic, Look
up in English and the direction the package's; the text is set by the Unicode
bidirectional algorithm. `dc:language` and `xml:lang` are normalised to BCP 47 by
`language_normalize` (`src/language.bats`): `EN-us` and `en_US` are `en-US`, `eng`
is `en`, `heb` and `iw` are `he`, the first of several is the book's; the page's
`lang`, the voice and Look up go by it (primary subtag). A chapter's own `xml:lang`
or `lang` on its html or body (`_chapter_lang`, cleared as each chapter is shown)
is the language in force there (`_lang_take`). In the text read aloud an element
that says another language, inside a block, is a block of its own (`_runs_node`,
`_block_lang_add`), said in its language (`script_lang`).
`e2e/encodings.spec.js`, `e2e/languages.spec.js`.

## What a text document needs, as a relation over its cells (#845, a piece of #608)

`src/text_relation.bats` states `text_plan_of`'s decision and the conversion `text_convert_into` makes as
`TEXTOF(cells, plan, output)` over the cells of array's `barr` (`NTH`, `CLEN`), and proves a second
implementation of them that takes a `cborrow`: `text_plan_proved` (the plan and its relation),
`text_convert_size` (how many bytes the conversion makes, with the relation) and `text_convert_fill`
(writes them into an array whose cells then hold them: `HOLDS`). `text_plan_of`, `text_converted_size`
and `text_convert_into` (plain `borrow`, no cells in their types) stay beside them, marked deprecated, until
`take_text` moves to the proved ones (the callers' move is a ticket of its own; `take_text_proved` of #848 is beside `take_text`, below); the removal of the old forms is quire#865 (p2). The two are
separate code with the same structure; that they decide alike is neither proved nor yet tested:
`e2e/encodings.spec.js` reads documents through the old ones, and runs through the proved ones when
`take_text` moves. What is proved is each relation's functionality and that the proved functions return
the relation of the bytes they read and write the bytes the relation says. The output array is the
caller's, as a `barr` (its cells model reaches 1048576 bytes with `barr_alloc`; `barr_of_arr` and
`barr_of_arrx` take any array, whose cells then are not known until they are written).

* **Cases** (the static sort `plan`: `PlanAsIs`, `PlanConvert`, `PlanRefused`, named after `text_plan`'s constructors; the detected source is a `tsrc`, `SrcUtf8`, `SrcUtf16(order)`, `SrcUnsupported` or `SrcTable(page)`, and the verdict of a UTF-8 scan a `scanned`, `ScannedRefused`, `ScannedAscii` or `ScannedOther`). As it is: UTF-8
  with no byte order mark, ASCII only in an unsupported encoding, valid UTF-8 that says a single-byte
  encoding; the output is the bytes of the cells (`HOLDS(cells, 0, octets, n)`). UTF-8 with a byte order
  mark: the bytes from the fourth (`HOLDS(cells, 3, octets, n - 3)`). UTF-16 either way, and a single-byte
  encoding on bytes that are not UTF-8: the output is `CONV`, the UTF-8 bytes of each character one after
  another. Refused (no output): not UTF-8, only a byte order mark, UTF-16 with nothing after its mark, an
  unsupported encoding that is not ASCII only.
* **A character** (`STEPOF`) is a UTF-16 unit that is no half of a pair, a high half and a low half (one
  character beyond U+FFFF), a half alone or a lone byte at the end (U+FFFD), a single-byte encoding's byte
  under 128 (itself) or the table's code point for the others (`TABLEAT`, `src/text_codes.bats`, made from the
  same tables as `text_tables.bats` by `scripts/gen-encodings.py`). `TABLEAT` has one constructor for each
  encoding, carrying that encoding's own `PAGEAT_<page>` (128 constructors): a case over all 1792 byte and
  encoding pairs in one dataprop took patsopt 7.4 GB and 62 seconds for `tableat_functional` (the cost of a
  case grows with the square of the constructors it is checked against), and over 128 at a time 0.7 GB and
  2 seconds, inside the 4096 MB cap of CI (quire#845). A table past a few hundred constructors in one
  dataprop is split by the key of the lemma that reads it. `ENC` is the UTF-8 bytes of a code point,
  stated by the digits of 64 so that no division is stated.
* **Refusal is the claim that no reading exists.** `UTF8SCAN(cells, from, 0)` carries a run of whole
  characters and then `UTF8BAD` (a lead byte that is none, or a byte it needs that is missing or not a
  continuation, by the Unicode table of well-formed sequences: no overlong form, surrogate or code point
  past U+10FFFF), and `utf8run_bad_not_complete` proves that no run of whole characters reaches the end
  of the cells from there. `utf8scan_functional` makes the three verdicts (refused, ASCII only, other
  characters) exclusive.
* **Detection** (`DETECT(cells, source, mark)`: the byte order mark, `<` and a null byte, the XML
  declaration's `encoding` within 256 bytes, else UTF-8; a declaration that says UTF-16 of bytes that are
  text is UTF-8) is built of `BLANKS`/`SKIP`, `NOQUOTE`/`FINDQUOTE`, `ISENCODING`, `DECLARED` and
  `DECLSCAN`, each with its functional lemma, and `LABELSRC` for the label in the quotes.
* **The labels** are a table made with the single-byte tables by `scripts/gen-encodings.py`
  (`src/text_labels.bats`: `LABELENTRY(index, label, source)`, the entries 0 to `LABEL_COUNT - 1` in the order
  `text_source_of_label` tries them). A label is `LABELIS` one entry, or `ALLDIFF` all of them
  (unsupported, source 3); `alldiff_get` and `labelis_not_diff` make the two exclusive. The proved
  `text_label_source` builds each entry as a `blist` and compares it, so it allocates a few small lists for
  a document that declares an encoding. The generator is Python because it already was (quire#436) and holds
  the label list and the tables: a second copy in bats would drift from it.
* **The loops that run over a document are tail recursive** (`_utf8_scan_loop`, `_skip_blank_loop`,
  `_find_quote_loop`, `_size_loop`, `_fill_loop`, `_copy_loop`): the proof is built at the end of the run it
  has read (`utf8run_snoc`, `blanks_snoc`, `noquote_snoc`, `conv_snoc`, `holds_push`) and is erased, so a
  document of any size is read in constant stack. The loops that are not (`_declscan_proved`, 257 deep at
  most; `_label_loop`, 77) are bounded by their metric. The conversion is two passes, as before: the size
  pass proves the whole conversion (`CONV`, built a character at a time by `conv_snoc`), and the fill pass
  carries what is left of it, takes each character from it (`stepof_functional` says the character it reads
  is the one the proof has) and so knows from the proof that every byte it writes is within the array.
  `text_plan_proved` runs the size pass for a document that needs a conversion, because the relation names
  the output bytes and the cells model does not say that a cell is a byte (it says it only for what is read).
* **Not proved:** that `text_label_source` and `text_source_of_label`, and `TABLEAT` and `text_table_code`,
  have one list of labels and one table (both are made from `scripts/gen-encodings.py`'s lists, and the tables
  are Python's codecs' (quire#436): that they are the WHATWG index's is not proved, and `e2e/encodings.spec.js` reads books in a few of the encodings),
  and that the proved functions decide as the old ones do (above).
* The lemmas are mutation-checked (`tests/static/mutation_modules.txt`) and the relations have reject
  fixtures (`tests/static/reject/text-*`).

## A book's place in its series is a position in hundredths (#434)

`opf_series` (`src/epub_xml.bats`) reads the first `belongs-to-collection` that is
a series (one another meta refines as `collection-type` `set` is not) and the
`group-position` that **refines it** (any, when the collection has no id); else
Calibre's `calibre:series` and `calibre:series_index`. A position is a number with
an optional sign, digits and a `.` or `,` with digits after it (`_number_scan`),
kept to two places (3.125 is 3.12), `-99999.99` to `99999.99`; anything else
("II", "2 5", "1e2", empty) is no position, never a refusal. 0 is a prequel and 2.5
a novella: the library sorts a series by the number, 0 and negatives included, and
a book with no number after those that have one, by title.

`series_position_of(hundredths)` is 0 for none, else the hundredths plus 10000001
(as `progress_weighted` is the thousandth plus one), so the order of the ints is
the order of the positions. The card and Book info show it as written without a
trailing zero (`lib_series_line`). A record keeps it in the ancillary group `snum`
(`series_position`), written only when SERI's whole number (`_series_whole`: 2 for
2.5, 0 for none or below 1) does not already say it, so an older Quire reads 2
and keeps `snum` as it keeps `prog`; a record with no `snum` reads as SERI's whole
number (`_series_read`; an absent group is not loss, #497). Neither the backup nor
the sync file holds a book's series (it is read from the file). `e2e/series.spec.js`,
`e2e/library-records.spec.js`.

## The sizes a book's CSS gives (#431)

**Stage 1: `src/css_size.bats` reads a book's `font-size` rules as the format
alone.** Only `font-size`: rules selected by element names, classes, ids and
descendant chains of them (`sheet_rules_read`, at most 4096 rules), an inline
`style` and `<font size>`, in px, pt, pc, in, cm, mm, em, ex, rem, % and keywords;
`calc()`, `clamp()`, `var()`, `vw`, a negative size and `!important` are
`SizeIgnored` with their reason, and a selector with a combinator, pseudo,
attribute or `*` is skipped and counted. Every answer is a `datavtype` matched with
`case+`. The types prove: a size is at most a thousand pixels or times
(`size_declared`, `size_computed`), a proportion to the dominant size is 10 to 60
twentieths (`proportion`: half to three times, as Readium clamps), a rule's
selector lies inside its sheet. Tested, not proved: that the grammar read is CSS's
(`tests/css-size/run.sh`, a CI step beside the codec's, with a fuzz).

**Stage 2: the size most of a book's text is set in.** `src/css_cascade.bats`
matches those rules against a chapter's elements and counts characters by the size
they are set in; `src/publisher_size.bats` reads a sample of the open book's
chapters and keeps the size with the most characters (`publisher_dominant_size`,
thousandths of a pixel; Calibre does the same). `_spine_build` runs it before the
first chapter is shown.

* The cascade (`chapter_tally`): an element's size is its inline `style`, else the
  rule of the highest specificity (the later at the same), else `<font size>` (below
  every rule), else its parent's; em, % and keywords resolve against the parent,
  rem against the html element's computed size (initially 16px). The browser's own
  sizes (h1 at 2em) are not counted. A rule's chain is matched right to left
  (`_match_up`). Text of `head`, `style`, `script`, `title`, `rt` and `rp` is not
  counted; a character is a non-white-space UTF-8 character.
* The tally (`size_tally`) holds at most 64 sizes rounded to a quarter pixel; the
  dominant is the one with the most characters, the smaller on a tie, 16px when
  nothing is counted.
* The sample: at most 16 chapters at an even stride, 1 MiB decompressed in all,
  none compressed over 512 KiB (a book of one huge chapter is not measured). A
  chapter's `<link rel=stylesheet>` sheets (not alternate, media all or screen) and
  `<style>` texts are joined, links first, into one sheet of at most 512 KiB
  (`sheet_acc`).
* Kept in memory per open, not as a record group: derived by an algorithm that will
  widen, so a stored number would go stale. Tested natively
  (`css_cascade_test.bats` in `tests/css-size/run.sh`); the wiring is tested by what
  the page shows (stage 3).

**Stage 3: a book's sizes reach the page.** A reflowed chapter's elements that
its publisher gave a size carry a `data-fs` (`_size_mark`, `src/reader.bats`): the
size against a base in twentieths from 10 to 60, and the stylesheet `style-sizes`
(`src/size_rules.bats`, a sheet of its own proven to fit its budget) gives it
`font-size: calc(var(--reading-size) * step / 20)`, `--reading-size` being the
Size setting (`_apply_type`). The map is made as the chapter is loaded
(`_sizes_load` in `_chapter_open`: `publisher_sizes_load`) and taken a name at a
time by the render (`publisher_sizes_begin`, `_step`, `_end`). A fixed-layout page
is not restyled; a load that cannot make its map shows the chapter without sizes.

* **In proportion (the default)**: the steps are against the book's dominant size,
  the cascade starting from 16px, so body text is the Size setting and headings,
  small print and captions keep their proportion (a book that sets no size has no
  `data-fs`). `html` and `body` are not made as elements, so a size they give goes
  to their children (the rem trick's 62.5%).
* **Respect the publisher's sizes** (`publisher_sizes`: `SizesInProportion |
  SizesAsPublished`; the Look tab's `publisher-sizes-switch`; the device's own,
  after "F" in the "S2" record as "P" and a byte, in the backup as
  `publisherSizes`, reset with the settings). The cascade then starts from the Size
  setting and an absolute size stays absolute (9pt is 12px), a relative one
  relative. Because the map then depends on the Size, the chapter is shown again
  (`reader_sizes_reload`) when the switch turns, when the Size moves while it is on,
  and when the settings are reset or put back. A size under half or over three
  times the Size is held there.
* Calibre rescales to the most common size; KOReader's switches are on or off and
  ignoring sizes also drops heading sizes (koreader#13295); Readium CSS keeps
  relative sizes scaled from the user's and leaves absolute units.

## An entry's text with INFLATES and TEXTOF (#848, a piece of #608; keyword: text-proved)

`src/text_proved.bats` has `take_text_proved`, beside `take_text` (which stays and is not changed): it takes an
entry's data, a `barr` of `n` bytes (at most 1048576, the decoder's bound) whose cells `cs` are in its type, and its
method as `entry_method(kind)` (`entry_method_of` makes it from zip's `compression`), and gives the array back with a
`text_taken(kind, cs)`:

* **Taken** (`TextTaken`): `INFLATES(kind, cs, output)` (zip's relation), `TEXTOF(output, plan, TOUT_bytes(octets))`
  (text_relation's) and the text's array holds exactly the octets (`HOLDS(text, 0, octets, count)`), over the same
  `output` cells. A deflated entry is inflated by zip's `inflate_cells_proved` (the in-memory decoder that returns
  `INFLATES`; the reader and writer form, `inflate_proved`, is native only and quire is wasm); a stored entry
  is a copy of its data (`barr_copy`, `INFLATES_stored`). The document is read by `text_plan_proved`; as it is, the
  text's array is the inflated array itself (`HOLDS` from the `TEXTOF`), and when it needs a conversion
  `text_convert_size` and `text_convert_fill` write it into a new array.
* **The other outcomes** each have a constructor: `TextRefused` (the document is refused, with its `TEXTOF`),
  `TextEmpty` (the data inflates to nothing, with its `INFLATES`), `TextMalformed` (the decoder refuses the data) and
  `TextTooLarge` (the inflated data, or its conversion, is over 1048576 bytes: a branch, not an assertion, since the
  array's size is bounded by its type).
* **Lemma** `text_taken_functional`: the same compressed cells by the same method inflate to the same cells
  (`inflates_functional`), so the `TEXTOF` of the two have one plan and one output (`textof_functional`): two takes of
  one entry's cells are provably the same text, as the same plan and the same octets (`EQPLAN`, `EQB`).
  `tests/static/accept/text-proved-two-takes-one-text` takes one entry twice and applies it;
  `reject/text-proved-functional-other-entry` (two entries' cells), `-other-method` (stored and deflated) and
  `reject/text-proved-held-other-octets` (a text array claimed to hold other octets) refuse the misuse.
* **The array is a `barr`, not an arena piece**, because the decoder's output is one (`barr_alloc`); a caller that
  reads it with a plain borrow freezes it and takes `cborrow_view`. Nothing calls `take_text_proved` yet: moving
  `take_text`'s callers is a ticket of its own, and `take_text` and the platform's `decompress` stay until then.
* **Tested, not proved:** that `inflate_cells_proved` and `text_plan_proved` run as their relations say is each
  package's own (zip's `tests/dynamic/inflate`, this module's functions are the text_relation ones above); the glue
  here (the freeze and thaw, the copy of a stored entry) has no test of its own beyond the static fixtures, because
  no caller reaches it yet.
