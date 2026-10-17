---
paths:
  - src/text_encoding.bats
  - src/text_tables.bats
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
