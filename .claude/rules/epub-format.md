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

## The archive is checked once

`book_begin` opens a book (an import, or a restore from IndexedDB) and checks its
archive then, once: the end record, the central directory (zip's `cd_refs`) and
every entry's local header. What survives is the book's index (`book_index`): the
kept directory and a list of entries whose data spans are proven inside the file.
`index_read` (container.xml, OPF, chapter, image) only looks a name up there;
nothing in the file is checked again.

A book's chapters are found once too, the first time one is loaded (`_spine_build`
in `src/reader.bats`): the OPF is parsed and each spine item's href, after the
OPF's directory, is looked up in the index. The chapters (`book_chapters`, each an
entry whose data span is proven, or missing) are kept in the book
(`book_spine_set`); the OPF is not read again.

**A chapter's data is checked against its CRC-32** (#529): the central directory
record states it (offset 16, `book_entry_sum`), and `take_text_sum` (in place of
`take_text`) computes the CRC-32 of the inflated bytes before they are made UTF-8
and answers no content for a mismatch or an unknown sum, so the chapter is
`ChapterNotRead` and the others read (libzip, Python's `zipfile` and Java's
`ZipFile` check the same sum). The chapter shown and the facing page are checked;
the OPF, container, images and the chapter reads for search, notes and read aloud
are not (yet). `e2e/containers.spec.js` ("a chapter whose CRC is not its data's").

### The CRC-32 table method is proved (#553), and it is the call's

`crc_of_cborrow` (`src/crc.bats`) is the table method over an array whose cells are
in its type (array's `barr`, borrowed as `cborrow(l, n, cs)`, `cborrow_get` giving
`NTH(cs, i, v)`). **Its type is the statement**: the bytes read are a list `octets`
that the cells hold (`HOLDS(cs, 0, octets, n)`), and the register after them is the
proven fold's (`CRCFROM(65535, 65535, octets, ...)`), so it cannot disagree with the
codec. No `praxi`, `assume` or `$UNSAFE`: the compiler checks the table (`TABLED`,
each entry the register `bstep` makes from zero), the byte step (`bstep_by_table`,
built from arith's XOR algebra `xor_comm`, `xor_assoc`, `xor_cat`, `xor_cancel`
and the linearity of the step, `step1_xor`, `stepn_xor`, `shift8`) and the loop
(`holds_snoc`, `crcfrom_snoc`, `table_step`). Statements are written in digits so
no index nests a division: eight chained `step_even` with `high/256` in their
indices did not finish under the infinite-precision solver (quire#594).
`tests/static/accept/crc-*` and `reject/crc-*` (a shift off by a bit, a table entry
of another byte, a register not complemented, a cell read for another) fail to
type-check; `tests/codec` runs the check value of "123456789" and arrays of every
length 1 to 300 and 4000 against the fold, as a check of the boundaries, not as the
proof.

The call (`take_text_sum`, `_sum_matches` in `src/book.bats`): the inflated piece, an
arena's `arrx(byte, l, n, arena)`, is lent as a `barr` by array's `barr_of_arrx`
(its `arrx_lent` proof keeps the owner: the arena cannot be destroyed while lent,
and `barr_to_arrx` gives it back only as the same piece), frozen, read, thawed and
given back before the piece is freed or made text. **Proved**: the sum compared
with the entry's is `crcfrom`'s fold over the bytes the piece holds. **Trusted, not
proved**: array's unsafe core (`barr_of_arrx`, `barr_to_arrx`, `cborrow_get`, tested
in array), arith's C operators behind `xor_g1` and the prelude's `/` (tested in
arith), the stored sum `book_entry_sum` reads, that the fold is CRC-32 (polynomial
0xEDB88320, tested on the check value), and that the decompressor wrote what the
cells hold (outside quire's types, as the platform's atoms are).

## Spine items and fallbacks (#419)

The W3C EPUB 3 test suite (`reports/quire-w3c-epub-tests.md`) found a spine item was
read as XHTML whatever its type (a 3 MB PNG killed the page, a JSON one was shown as
text and its fallback never followed).

* **A spine item shows a content document** (`find_chapter_shown_href_n` in
  `src/epub_xml.bats`, used by `_spine_chapters`): the item itself when its media
  type is `application/xhtml+xml`, `image/svg+xml`, `text/html`, an OEB 1 or DTBook
  document (read through, quire#416) or none is given; else the item its `fallback`
  names, down the chain (at most 16 items), as EPUB 3.3 §3.3 says. An item with the
  property `scripted` and a fallback is replaced by the fallback too (Quire runs no
  scripts; with no fallback it is shown, scripts unrun). **An itemref none of whose
  items is a content document is left out of the chapters**, so the reader never
  reads its bytes as XHTML and the book opens at the next; the chapters' count is
  the count kept (`_spine_chapters` returns both). No documentation was found of
  what Thorium or Readium do with such an item (searched: the specs, the working
  group's minutes, Readium's wiki); skipping is chosen because the alternatives are
  a page of binary text or refusing the book.
* **An `<img>` whose manifest item is a type no browser draws and has a fallback is
  shown as the fallback** (`pub-foreign_image`): the spine build finds those items
  (`find_image_fallback_n`, `find_image_target`: the chain down to a core image, 16
  items at most) and keeps their entry paths (`image_fallbacks`); `_show_image`
  shows the target's entry, so the image viewer does too.
* **The title and author are the first `dc:title` and `dc:creator`**
  (`_opf_metadata_node`; EPUB 3.3 §5.4). `title-type` is not read.

## The archive and the XML are checked for what EPUB forbids (#419)

* **A zip that EPUB's OCF forbids is refused at import** (`src/zipcheck.bats`,
  called from `book_index_make`; `ocf-zip-comp`, `ocf-zip-mult`): an end record
  naming a disk other than 0, and an entry compressed by a method other than stored
  or Deflate. The zip package leaves such an entry out of its references without a
  word, so a bzip2 chapter used to open with the chapter gone; `zipcheck` reads the
  end record's and the directory's own fields and `book_refusal` says why
  (`ArchiveSplit`, `CompressionNotAllowed`). A refusal in zip's `cd_refs` would be
  the better place.
* **A content document that is not well formed is not shown**
  (`src/wellformed.bats`, `xml_well_formed`, called by `_chapter_render`; EPUB RS 3.3
  §3.1): an element not closed by its own end tag, an end tag that closes another,
  an element name with two colons, a colon at either end, a digit first or a
  character no name has. The chapter is then "could not be read" (open another or
  Replace). Comments, CDATA, processing instructions, the DOCTYPE and quoted
  attribute values are read over; entity references are not checked (XHTML's named
  entities are decoded as any text's are). Only the chapter shown is checked, not
  those read for search, notes or narration. xml-tree builds a tree from any bytes,
  so it reports nothing itself.
* **An image the manifest does not list is shown, by decision**
  (`pkg-manifest-unlisted-resource`, a SHOULD): the zip is read by name, 11 of 15
  reading systems show it too, hiding it would blank the images of books whose
  manifest is merely incomplete.

## The package's directions and language (#419)

* **A title's and an author's direction are the package's** (`opf_text_directions`
  in `src/epub_xml.bats`): the first `dc:title` and `dc:creator` take their own `dir`
  (`ltr`, `rtl`, `auto`), else the `package` element's. Kept in the book's record as
  one number (`text_directions`, title + 4 * author, the optional group `tdir`, lower
  case so an older Quire keeps it as an unknown chunk), set at import and by Replace,
  decoded once into a `text_direction` (`_direction_of_code`); the card sets `dir` on
  its title and author (`ADir`). A book imported before this has none until replaced.
  The backup and sync do not carry it.
* **The package's language and direction are not the content's, by decision; the
  suite's `pkg-lang_but_not_content` and `pkg-dir_but_not_content` stay failures.** A
  chapter that names no language is shown in the book's (`_page_book_lang`; "und"
  when none): browsers hyphenate and pick quotation marks only for text whose
  language is known, and `dc:language` is the only language a book declares. A Hebrew
  or Arabic book whose spine names no direction reads right to left (#416, as Readium
  reads it): the page is one flow of CSS columns whose order is the page's
  `direction`. The suite's criterion (a document that names none stays in the reading
  system's own language and left to right) is met by 11 of 15 reading systems for
  language and all 13 for direction, which lay each document out on its own; Quire's
  flow cannot without giving up one of those two decisions.

## Addresses and labels in a book (#419)

* **A path-absolute address is the container's** (`href_rooted`, `src/paths.bats`,
  used by `book_find_relative` and `_load_image`): an image's `src` or a link's
  `href` that starts with `/` names the entry from the root of the zip, not from the
  document's directory (`ocf-url_link-path-absolute`).
* **An image given as a data URL is shown** (`src/dataurl.bats`):
  `data:image/<png|jpeg|gif|webp|svg+xml>;base64,...` is decoded by Quire
  (`base64_decode`, `_load_data_image`) because the dom package refuses a `data:` URL
  as an attribute. One over 512 KiB of text (alloc's bound is 1 MiB) or of another
  type is not shown, and is not offered to the image viewer.
* **A navigation link holding an image is labelled by the image's alt text, else its
  title** (`_gather_image` in `src/toc.bats`), not "Untitled".
* A navigation document in the spine hides an entry marked `hidden` (the attribute is
  kept, #411); the contents panel, made from the nav, lists all.
