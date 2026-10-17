---
paths:
  - src/zipcheck.bats
  - src/crc.bats
  - src/wellformed.bats
  - src/epub_xml.bats
  - src/paths.bats
  - src/book.bats
  - src/toc.bats
  - e2e/containers*
  - e2e/epub2*
  - e2e/epubcheck*
  - e2e/landmarks*
  - e2e/pagelist*
  - e2e/publisher*
  - e2e/drm*
---

# The EPUB format: archive, spine, packages and addresses

### The archive is checked once

`book_begin` opens a book (an import, or a restore from IndexedDB) and
checks its archive then, once: the end record, the central directory
(zip's `cd_refs`) and every entry's local header. What survives is the
book's index (`book_index`): the kept directory and a list of entries
whose data spans are proven inside the file. Reading an entry
(`index_read`, for the container.xml, the OPF, a chapter or an image)
only looks its name up there; nothing in the file is checked again.

A book's chapters are found once too, the first time one is loaded
(`_spine_build` in `src/reader.bats`): the OPF is read and parsed, and
each spine item's href, after the OPF's directory, is looked up in the
index. The chapters (`book_chapters`, each an entry whose data span is
proven, or missing) are kept in the book (`book_spine_set`), so loading
chapter i only walks to it (`book_chapter_get`); the OPF is not read
again.

A chapter's data is checked against its CRC-32 (#529): the central
directory record the index keeps states it (offset 16), `book_entry_sum`
reads it by the chapter's name offset, and `take_text_sum` (in place of
`take_text`) computes the CRC-32 of the inflated bytes, before they are
made UTF-8 (`crc_of_cborrow`, `src/crc.bats`, proved: see "The CRC-32
table method is proved" below; the piece is lent as a `barr` by array's
`barr_of_arrx` and given back to its arena by `barr_to_arrx`), and answers no content for a mismatch or an unknown sum, so the
chapter is `ChapterNotRead` ("Chapter N of this book could not be read")
and the others read. libzip (`ZIP_ER_CRC`), Python's `zipfile`
(`BadZipFile: Bad CRC-32`) and Java's `ZipFile` check the same sum at the
end of the entry. The chapter shown and the facing page of a spread are
checked; the OPF, the container, images and the chapter reads for
search, notes and read aloud are not (yet). `e2e/containers.spec.js`
("a chapter whose CRC is not its data's").

### The CRC-32 table method is proved (#553), and it is the call's

`crc_of_cborrow` (`src/crc.bats`) is `crc_of_borrow`'s table method over
an array whose cells are in its type (array's `barr`, borrowed as
`cborrow(l, n, cs)`, its `cborrow_get` giving `NTH(cs, i, v)`), and its
type is the statement: for the cells `cs` (`CLEN(cs, n)` of them, nothing
else known) the bytes read are a list `octets` that the cells hold
(`HOLDS(cs, 0, octets, n)`, bytesarr's), and the register after them is
the proven fold's (`CRCFROM(65535, 65535, octets, 65535 - high, 65535 -
low)`, the CRC being its complement), so it cannot disagree with the
codec; a caller that knows what the cells hold has it from
`holds_functional`. No `praxi`, `assume` or `$UNSAFE`: the compiler checks

* the table: entry i is the register `bstep` makes from zero
  (`TABLED(cells, count)`, an `ENTRY` of four `NTH`s and the `BSTEP(0, 0,
  i, ...)` for each i < count, kept as the cells are set, `tabled_set`,
  by array's `setc_nth_other`; `tabled_get` finds entry k of a full
  table);
* the byte step (`bstep_by_table`): `BSTEP(high, low, octet, ...)` is
  the register shifted right by 8 bits xored with the entry of the byte
  `(low mod 256) xor octet`. It is built from arith's XOR algebra
  (`xor_comm`, `xor_assoc`, `xor_half`, `xor_double`, #553), `xor_cat`
  (the xor of numbers with numbers above them is the xor of both, by
  induction on the bits, linear in the solver) and `xor_cancel`; the
  step is linear in xor (`step1_xor`, `stepn_xor`, by cases on the
  parities of the three low halves, the polynomial xored into none or two
  of the three); a register whose low byte is zero shifts without the
  polynomial (`shift8`, from `shift4` and `shift2` by `stepn_append`, each
  statement in digits so no index nests a division: eight chained
  `step_even` with `high/256` in their indices did not finish under the
  infinite-precision solver, quire#594); every register has a next one
  (`stepn_exists`, with `xor_exists`), so the step of the whole is
  compared with the table's entry and the pure shift;
* the loop (`crc_of_cborrow`): the invariant is `HOLDS` of the bytes read
  so far (`holds_snoc`, by induction on the list) and `CRCFROM` of them
  (`crcfrom_snoc`), with `table_step` giving each `BSTEP` from the table
  read through `barr_get`.

`tests/codec` still runs it on the check value of "123456789" and arrays
of every length 1 to 300 and 4000 against the fold, as a check of the boundaries, not as the proof
(`tests/static/accept/crc-*` and `reject/crc-*`: a shift of 8 bits whose low half is off, a table entry of another
byte, the step by another byte's entry, a high half not shifted, a loop
step of another byte, the register not complemented and a cell read for
another all fail to type-check).

The call is that one (`take_text_sum`, `_sum_matches` in `src/book.bats`):
the inflated piece, an arena's `arrx(byte, l, n, arena)`, is lent as a
`barr` by array's `barr_of_arrx`, which returns the `arrx_lent(l, n, o)`
proof that keeps its owner (the arena's count of outstanding pieces does
not change while it is lent, so the arena cannot be destroyed, and
`barr_to_arrx` gives it back only as the same piece of the same arena);
the barr is frozen, `crc_of_cborrow` reads it, it is thawed and given back
before the piece is freed or made text. What the proof says of the call is
that the sum compared is the CRC-32 of a list of bytes the cells hold;
the cells are those of `barr_of_arrx`, so nothing relates them to what the
decompressor wrote into the piece (that is outside quire's types, as the
platform's atoms are). `crc_of_borrow` and its helpers are gone;
`tests/codec` checks `crc_of_cborrow` against the proven fold on the check
value of "123456789" and arrays of every length 1 to 300 and 4000, as a
check of the boundaries. This needs array 2026.10.14.60158 or later (the
one `bats.lock` names).

What is proved, then, is that the CRC-32 compared with the entry's sum is
`crcfrom`'s fold over the bytes the arena piece holds, as the production
call computes it. What is trusted, not proved: array's one unsafe core
(`barr_of_arrx` and `barr_to_arrx` are casts that keep the owner,
`cborrow_get` reads the byte it says, tested in array's
`tests/dynamic`), arith's C operators behind `xor_g1` and the prelude's
`/` (tested in arith), the stored sum `book_entry_sum` reads from the
central directory, and that the fold itself is CRC-32 (its polynomial
0xEDB88320 and the check value of "123456789", the latter tested in
`tests/codec`). Nothing in quire uses `praxi`, `assume` or `$UNSAFE` for
it.

## Spine items and fallbacks (#419)

The W3C's EPUB 3 test suite (`reports/quire-w3c-epub-tests.md`) found that
a spine item was read as XHTML whatever its type: a 3 MB PNG as a spine
item killed the page (`lay-pp-images-in-spine`), a JSON or XML one was
shown as text and the fallback its manifest names was never followed.

* **A spine item shows a content document** (`find_chapter_shown_href_n`
  in `src/epub_xml.bats`, used by `_spine_chapters` in `src/reader.bats`):
  the item itself when its media type is `application/xhtml+xml`,
  `image/svg+xml`, `text/html`, an OEB 1 or DTBook document (read through,
  quire#416) or none is given; else the item its `fallback` names, and so on
  down the chain (at most 16 items, so a loop ends), as EPUB 3.3 §3.3
  says. An item with the property `scripted` and a fallback is replaced by
  the fallback too, since Quire runs no scripts (`scr-support-fallback`;
  one with no fallback is shown, scripts unrun). An itemref none of whose
  items is a content document is left out of the chapters, so the reader
  never turns to it and never reads its bytes as XHTML; the book opens at
  the next. Decided by the spec and the suite's reports: EPUB 3.3 (§3.3,
  §3.5.1) makes a foreign resource valid in the spine only with a manifest
  fallback to a content document, and the suite's own pass criterion is
  that the fallback is shown; the W3C working group's minutes (2022-03-11)
  found few reading systems that show it, so the suite's reports hold
  the comparison (`lay-pp-images-in-spine` 2/2, `pub-foreign_json-spine`
  4/9 pass). No documentation of what Thorium or Readium do with a
  spine item they cannot render with no fallback was found (searched:
  the specs, the working group's minutes, Readium's wiki); skipping it is
  chosen because the alternatives are a page of binary text or refusing the
  whole book, and no word of the book is lost. The
  chapters' count is the count kept, not the itemrefs' (`_spine_chapters`
  returns both).
* **An `<img>` whose manifest item is a type no browser draws and has a
  fallback is shown as the fallback** (`pub-foreign_image`): at the
  spine build the items that are not a core image type and have a
  `fallback` are found (`find_image_fallback_n`, `find_image_target`: the
  chain down to a core image, 16 items at most, 256 items at most) and
  their entry paths kept (`image_fallbacks`, replaced by the next book's),
  and `_show_image` shows the target's entry when the image's path is a
  kept one, so the image viewer does too.
* **The title and author are the first `dc:title` and `dc:creator`**
  (`_opf_metadata_node`), as EPUB 3.3 §5.4 makes the first title the main
  one and a reader needs one author (`pkg-title-order`,
  `pkg-creator-order`). EPUB 3's `title-type` refinement is not read.

## The archive and the XML are checked for what EPUB forbids (#419)

* **A zip that EPUB's OCF forbids is refused at import** (`src/zipcheck.bats`,
  called from `book_index_make` in `src/book.bats`; the suite's
  `ocf-zip-comp` and `ocf-zip-mult`, both "MUST treat ... as in error"):
  an archive whose end record names a disk other than 0 (a split
  archive), and one with an entry compressed by a method other than stored
  or Deflate. The zip package leaves such an entry out of its references
  without a word (its own documentation says so), so a book with a bzip2
  chapter used to open with the chapter gone; `zipcheck` reads the end
  record's and the central directory's own fields, `book_refusal` says
  why, and the import banner says it (`ArchiveSplit`,
  `CompressionNotAllowed`: "... is a zip split into segments, which an
  EPUB may not be ..."). The zip package is the tool that could report this
  itself (a refusal in `cd_refs`); until it does, the check is Quire's.
* **A content document that is not well formed is not shown**
  (`src/wellformed.bats`, `xml_well_formed`, called by `_chapter_render`;
  `pub-xml-non-validating_unclosed`, `pub-xml-names`, both "The reading
  system must produce an error", EPUB RS 3.3 §3.1: a non-validating XML
  processor, a fatal error for a document that is not well formed):
  an element not closed by its own end tag, an end tag that closes
  another, and an element name with two colons, a colon at either end, a
  digit first or a character no name has. The chapter is then a chapter
  that could not be read: the banner says "Chapter N of this book could
  not be read" and to open another chapter or import it again with
  Replace. Comments, CDATA, processing instructions, the DOCTYPE and
  quoted attribute values (with a `>` in them) are read over, and entity
  references are not checked: XHTML's named entities are decoded as any
  text's are. Of the reading systems the suite holds, 8 of 9 (unclosed)
  and 9 of 9 (names) pass, Thorium and Apple Books among them. The check
  is on the chapter shown; the chapters read for search, notes or
  narration are not refused. xml-tree builds a tree from any bytes, so it
  reports nothing itself; a well-formedness error from the parser would
  be the better place for it.
* **An image the manifest does not list is shown, by decision**
  (`pkg-manifest-unlisted-resource`, a SHOULD): the zip is read by name.
  11 of the 15 reading systems that answered the suite show the image
  too, hiding it would blank the images of books whose manifest is merely
  incomplete, and nothing is gained, the file being in the book's own
  archive.

## The package's directions and language (#419)

* **A title's and an author's direction are the package's** (`opf_text_directions` in
  `src/epub_xml.bats`; the suite's `pkg-dir_creator-rtl`, `pkg-dir_rtl-root-ltr`,
  `pkg-dir_rtl-root-unset`, `pkg-dir_unset-root-rtl`): the first `dc:title` and the first
  `dc:creator` take their own `dir` (`ltr`, `rtl`, `auto`), else the `package` element's.
  They are kept in the book's record as one number (`text_directions`, title + 4 * author, the
  optional group `tdir`, lower case so an older Quire keeps it as an unknown chunk), set at
  import and again by Replace, decoded once into a `text_direction` (`_direction_of_code`), and
  the library card sets `dir` on its title and author (`ADir`). `dir=auto` is the browser's
  first-strong-character rule; none leaves the page's. A book imported before this has none
  until it is replaced. The backup and sync do not carry it (it comes from the package).
* **The package's language and direction are not the content's, by decision, and the suite's
  `pkg-lang_but_not_content` and `pkg-dir_but_not_content` stay failures.** A chapter that
  names no language is shown in the book's (`_page_book_lang`; "und" when the book names none):
  browsers hyphenate and pick quotation marks only for text whose language is known (MDN on
  `hyphens`; the CSS specification requires hyphenation only where the content language is
  known), and the package's `dc:language` is the only language a book declares. A Hebrew or
  Arabic book whose spine names no direction reads right to left (#416, as Readium reads it): the
  page is one flow of CSS columns whose order is the page's `direction`, so a list or paragraph
  in it inherits it. The suite's criterion (a document that names none stays in the reading
  system's own language and left to right) is met by 11 of the 15 reading systems that answered
  for language and all 13 for direction, which lay each document out on its own; Quire's flow
  cannot without giving up one of those two decisions. They stay listed as policy in the report.

## Addresses and labels in a book (#419)

* **A path-absolute address is the container's** (`href_rooted` in `src/paths.bats`, used by
  `book_find_relative` and `_load_image` in `src/reader.bats`; the suite's
  `ocf-url_link-path-absolute`, "MUST ... resolved from the container's root"): an image's `src`
  or a link's `href` that starts with `/` names the entry of that name from the root of the
  zip, not from the document's directory, so `/OEBPS/images/a.png` in OEBPS/ch1.xhtml is
  OEBPS/images/a.png, not OEBPS/OEBPS/images/a.png. epubcheck calls such an address a
  warning (RSC-026); the reading system still shows it.
* **An image given as a data URL is shown** (`src/dataurl.bats`; `pub-data-urls_browsing-context`
  and `pub-data-urls_top-level-content`, "must display the image rather than opening it in a new
  top-level browsing context"): `data:image/<png|jpeg|gif|webp|svg+xml>;base64,...` is decoded
  by Quire (`base64_decode`) and given to the image as any entry's bytes are (`_load_data_image`),
  because the dom package refuses a `data:` URL as an attribute (a script cannot run from one).
  One over 512 KiB of text (alloc's bound is 1 MiB) or of another type is not shown, and it is not
  offered to the image viewer (it is not an entry).
* **A navigation link holding an image is labelled by the image's alt text, else its title**
  (`_gather_image` in `src/toc.bats`; `nav-non-text_img`, `nav-non-text_img_title`): EPUB 3.3
  asks for alternative text on a link's image, and the label was "Untitled".
* `nav-spine_in-spine-hidden-toc-html` passes: the navigation document in the spine hides an
  entry marked `hidden` (the attribute is kept, #411) and the contents panel, made from the
  nav, lists all.
