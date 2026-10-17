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
`scripts/gen-encodings.py`). Every document that is text (the container, the
package, the navigation document, a content document, an overlay,
encryption.xml; not an image, font or audio) goes through `take_text`
(`src/book.bats`) instead of `take_decompressed`: a byte order mark says the
encoding (UTF-8's is dropped, UTF-16 either way becomes UTF-8), so does `<` and
a null byte; else the XML declaration's `encoding` by the WHATWG labels
(`iso-8859-1`, `latin1` and `us-ascii` are windows-1252, as in a browser) for
UTF-8 or a single-byte encoding with a table here (windows-1250 to 1257,
ISO-8859-2, 5, 7, 8, 15, KOI8-R); else UTF-8. UTF-8 that is not UTF-8, or an
encoding with no table (Shift_JIS, GBK) in a document that is not ASCII only,
refuses the document ("Chapter N of this book could not be read", a
`PlanRefused`): XML calls it fatal, and a guess is mojibake. A document that
says a single-byte encoding but is valid UTF-8 with non-ASCII characters is read
as UTF-8 (it is wrong about itself). A plain UTF-8 document is not copied
(`PlanAsIs`). The research is in the issue: Thorium and Apple Books use a
browser's XML parser, Calibre the mark and the declaration and then a guess.
A title, author or series in the package has its references decoded
(`_span_arr`), and the library sorts by letters (`_fold`: Latin letters without
their accents, so Łukasz is under L; other scripts by code point).

**Languages.** Quire does not guess a book's language from its text (no reading
system researched does): no `dc:language` is `und`, with the voice automatic,
Look up in English and the direction the package's; the text is set by the
Unicode bidirectional algorithm. `dc:language` and `xml:lang` are normalised
to BCP 47 by `language_normalize` (`src/language.bats`): `EN-us` and `en_US` are
`en-US`, `eng` is `en`, `heb` and `iw` are `he`, the first of several is the
book's; the page's `lang`, the voice and Look up go by it (primary subtag).
A chapter's own `xml:lang` or `lang` on its html or body (`_chapter_lang`, cleared
as each chapter is shown) is the language in force there, for the page, the
voice and Look up (`_lang_take`). In the text read aloud an element that says a
language other than the one in force, inside a block, is a block of its own
(`_runs_node`, `_block_lang_add`): a sentence of its own, said in its language
(`SentenceOf`'s `book_lang`, `script_lang`). `e2e/encodings.spec.js`,
`e2e/languages.spec.js` and their `*-books.js` test it.
## A book's place in its series is a position in hundredths (#434)

`opf_series` (`src/epub_xml.bats`) reads a book's series and position: the
first `belongs-to-collection` that is a series (one another meta refines as
`collection-type` `set` is not), and the `group-position` that **refines it**
(any, when the collection has no id); else Calibre's `calibre:series` and
`calibre:series_index`. A position is a number with an optional sign, digits
and a `.` or `,` with digits after it, spaces around it ignored (`_number_scan`),
kept to two places (3.125 is 3.12), `-99999.99` to `99999.99`; anything else
("II", "Part Two", "2 5", "1e2", empty) is no position, never a refusal. Calibre
keeps `series_index` as a float, so 0 is a prequel and 2.5 a novella between
volumes 2 and 3: the library sorts a series by the number, 0 and negatives
included, and a book of the series with no number after those that have one,
by title.

`bnums.series_position` is `series_position_of(hundredths)`: 0 for none, else
the hundredths plus 10000001 (as `progress_weighted` is the thousandth plus one),
so the order of the ints is the order of the positions. The card and Book info
(a Series row, `lib_series_line`) show it as written without a trailing zero
(`Foundation · 2.5`, `· 2`, `· 1.25`, `· 0`, `· -1`). A record keeps it in an
ancillary group `snum` (`series_position`), written only when SERI's whole number
does not already say it; SERI keeps the **whole number** (`_series_whole`: 2 for
2.5, 0 for none or below 1), so an older Quire reads 2 and keeps `snum` as it
keeps `prog`, and a record with no `snum` reads as SERI's whole number
(`_series_read`), as the records written before it do (they read whole: a
group that is absent from a record written before it existed is not loss, #497). Neither the backup nor the
sync file holds a book's series (it is the book's own, read from its file, so a
second device or a restore shows what the file says). `e2e/series.spec.js`,
`e2e/series-books.js` and `e2e/library-records.spec.js` test it.

## The sizes a book's CSS gives (#431, stage 1)

`src/css_size.bats` reads a book's `font-size` rules as the format alone
(nothing of it reaches the page yet; stages 2 and 3 of #431 measure a book's
dominant size and apply the proportions). Only `font-size` is read: rules
selected by element names, classes, ids and descendant chains of them
(`sheet_rules_read`, at most 4096 rules, each with its selector's span in the
sheet, specificity and order), an inline `style` and `<font size>`
(`declarations_size_read`, `font_size_attribute_read`), in px, pt, pc, in, cm,
mm, em, ex, rem, % and keywords; `calc()`, `clamp()`, `var()`, `vw`, a
negative size and `!important` are `SizeIgnored` with their reason, and a
selector with a combinator, pseudo, attribute or `*` is skipped and counted.
Every answer is a `datavtype` matched with `case+` (`size_read`,
`selector_read`, `sheet_read`). What the types prove: a size is at most a
thousand pixels or times (`size_declared`), a computed one is a pixel to a
thousand of them (`size_computed`), a proportion to the dominant size is from
10 to 60 twentieths (`proportion`, so `font-size:1px` and `font-size:400%` are
held to half and three times, as Readium clamps), a rule's selector lies inside
its sheet, and its order is below the most. What is tested, not proved
(`tests/css-size/run.sh`, a CI step beside the codec's, on bytes, with a fuzz):
that the grammar read is CSS's. The `rem` trick of the fixtures is on `html`
(`e2e/size-books.js`).

### The size most of a book's text is set in (#431, stage 2)

`src/css_cascade.bats` matches those rules against a chapter's elements
and counts its characters by the size they are set in; `src/publisher_size.bats`
reads a sample of the open book's chapters and keeps the size with the most
characters (`publisher_dominant_size`, thousandths of a pixel, 0 when none).
`_spine_build` runs the measure before the first chapter is shown. Nothing
reaches the page yet (stage 3).

* The cascade (`chapter_tally`): an element's size is its inline `style`, else
  the rule of the highest specificity (the later one at the same), else
  `<font size>` (a presentational hint, below every rule), else its parent's;
  em, % and keywords resolve against the parent, rem against the html
  element's computed size (html itself against the initial 16px). The
  browser's own sizes (h1 at 2em) are not counted, only what the publisher
  declared. A rule's chain of compounds is matched right to left, the nearest
  ancestor first (`_match_up`); an element name is matched exactly, as in XML.
  Text of `head`, `style`, `script`, `title`, `rt` and `rp` is not counted; a
  character is a non-white-space UTF-8 character.
* The tally (`size_tally`) holds at most 64 sizes, each rounded to a quarter
  of a pixel; the dominant size is the one with the most characters, the
  smaller on a tie, 16px when nothing is counted. By research (on the issue):
  Calibre's base font size is the most common font size in the document.
* The sample: at most 16 chapters at an even stride through the spine, 1 MiB of
  decompressed chapters in all, none compressed over 512 KiB (so the open of
  a book of one huge chapter is not made to wait: it is not measured). A
  chapter's `<link rel=stylesheet>` sheets (not alternate, media all or
  screen), read by `book_find_relative`, and its `<style>` texts are joined,
  links first, into one sheet of at most 512 KiB (`sheet_acc`), so one rule
  order serves them; a chapter that links to sheets is read twice (the sheets
  are awaited between). A sheet with an unclosed comment or block takes the
  ones joined after it with it.
* Kept in memory per open, not as a record group: derived from the file by an
  algorithm that will widen, so a stored number would go stale at every change.
* Tested: `tests/css-size/run.sh` natively (`css_cascade_test.bats`: the
  cascade, inheritance, the book A and B fixtures' rules, the tally, a fuzz).
  The wiring (links read stored and deflated, the three size books measured
  16px, 12px and 12px, a plain book 16px) was checked by hand with a
  temporary attribute and is not a permanent e2e: nothing of it is visible
  until stage 3, which tests it by what the page shows.

### A book's sizes reach the page (#431, stage 3)

A reflowed chapter's elements that its publisher gave a size carry a
`data-fs` (`_size_mark` in `src/reader.bats`): the element's size against a
base, in twentieths from 10 to 60 (`proportion`, so half to three times,
as Readium clamps), and the stylesheet `style-sizes` (`src/size_rules.bats`,
a sheet of its own, 51 rules proven to fit its budget, each one a
selector of 19 bytes and a value of 30) gives it
`font-size: calc(var(--reading-size) * step / 20)`, where `--reading-size`
is the Size setting (written by `_apply_type`). The map of a chapter's
elements and steps is made as the chapter is loaded (`_sizes_load` after
`_overlay_load`, in `_chapter_open`: `publisher_sizes_load`, which reads the
chapter and its sheets again, like the measure does) and taken a name at a
time by the render (`publisher_sizes_begin`, `publisher_sizes_step`,
`publisher_sizes_end`: an element is known by where its name is in the
document, and the render asks in the document's order). A fixed-layout
page is not restyled, and a chapter's load that cannot make its map shows
the chapter without sizes.

* **In proportion (the default).** The steps are against the book's
  dominant size (`publisher_dominant_size`), the cascade starting from the
  browser's 16px, so the body text of every book is the Size setting
  and a book's headings, small print, captions, notes and lead
  paragraph keep their proportion to it (a book that sets no size has
  no `data-fs`, and its headings are Quire's own, as before). An element is
  marked when it was given a size or its size differs from the one it is
  shown in (`html` and `body` are not made as elements, so a size they give
  is given to their children: the rem trick's 62.5%).
* **Respect the publisher's sizes** (`publisher_sizes`, `SizesInProportion |
  SizesAsPublished`; the Look tab's switch, `publisher-sizes-switch`; the
  device's own, kept in the "S2" record after "F" as "P" and a byte, in the
  backup as `publisherSizes`, reset with the settings and brought back by their
  Undo). The cascade then starts from the Size setting as the root and the
  steps are against it: the publisher's sizes as a browser would draw them
  with that root, an absolute size absolute (B's 9pt is 12px) and a
  relative one relative (A's 1.6rem is the setting). Because an absolute size is
  against the setting, the map depends on it: the chapter is shown again (at its
  place, `reader_sizes_reload`) when the switch turns, when the Size moves
  while it is on, and when the settings are reset or put back. A step is a
  twentieth of the base, so a size is within 2.5% of the publisher's, and
  one under half or over three times the Size is held there (12px at a
  Size of 32).
* By research (on the issue): Calibre rescales to a base font size
  that is the most common size in the document; KOReader's two switches
  (Embedded Style, Ignore publisher font sizes) are on or off and its
  tracker records that ignoring sizes also drops the engine's heading
  sizes (koreader#13295); Readium CSS keeps relative publisher sizes
  scaled from the user's size and leaves absolute units as they are.
* Tested: `tests/css-size` (the map: A's and B's books, the floor and the
  ceiling, respecting) and `e2e/publisher-sizes.spec.js` (the books of
  `e2e/size-books.js`: the body text at the setting in each at 12, 20
  and 32, the ratios 2, 1.5, 0.8 and 1.25 in both, a size on body, on a div,
  by html and rem and by calc(), a title page of headings, the floor and
  ceiling, only the size read, a linked sheet, and the switch on, kept,
  backed up, reset and undone). `e2e/publisher.spec.js`'s sizes test now expects the
  point size inline to keep its proportion (it expected every size equal while the book's
  sizes were dropped); the `!important` sizes are still not read.
