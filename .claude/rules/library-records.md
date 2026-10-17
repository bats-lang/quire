---
paths:
  - src/libstore.bats
  - src/library.bats
  - src/bookrec.bats
  - src/indexrec.bats
  - src/bookimage.bats
  - src/indeximage.bats
  - src/record.bats
  - src/schema.bats
  - src/chunk.bats
  - src/fields.bats
  - src/unreadable.bats
  - src/import.bats
  - src/file_version.bats
  - src/storage.bats
  - scripts/record_tables.py
  - scripts/gen-record.py
  - tests/codec/**
  - e2e/library-records*
  - e2e/old-library*
  - e2e/legacy-library*
  - e2e/replace*
  - e2e/progress*
  - e2e/storage*
---

# The library as records, reading progress and replacing a file

## The library is stored as records (#354)

The library is not one record any more. Each book is a record,
`library/book/<14 hex digits>` (its id as two 28-bit halves, 7 digits
each), and the collections another, `library/index`. They are read
together by their prefix (`libstore_read`, bridge's `idb_get_prefix`)
and saved one at a time, so a change to one book writes one book's bytes,
and a record damaged in one place costs that record's damaged part and
nothing else.

**The format** is `QREC`, a kind (book, index), the version of the
format that wrote it (1) and the least version that can read it (1, the
reader's `READER`), then chunks as PNG has them: a u32le length under
2 to the 20, a 4-byte tag, the data and a CRC-32 (IEEE, 0xEDB88320, the
check value of "123456789" is 0xCBF43926) as its low 16 bits and then
its high 16 bits, little endian, over the tag and the data; the last
chunk is `IEND`. A record is a set of groups, one chunk each, written
in ascending tag order (a book's: `AUTH BOOK COLL ELSE FNSH ORDR PLCE SERI SHLF
SIZE TIME TITL`, the index's `LEGA NAMS`) and read by tag, in any order
(#510, below); a group the record needs or that every version has
written (`req`, `opt`), when it is lost (absent, its CRC bad or its fields
not parsing), is read with its substitute (`SUBSTITUTES` in
`scripts/record_tables.py`, else 0 and empty) and said to be lost, and the
record is used (`rr_loss`); nothing about a group makes a record unusable.
A chunk of a tag this version does not
know is kept as it is, at the end, when its first letter is lower case
(ancillary, as in PNG), so a newer Quire's addition survives this one's
save; a capital one (critical), or a least version over `READER`, makes
the record `Newer`, and a first four bytes that are not `QREC` make it
`NotQuire`. What a record is decoded to is one of those five outcomes
(`recres`: `rr_ok`, `rr_loss`, `rr_notquire`, `rr_newer`, `rr_damaged`);
a decode never fails to say which. `rr_damaged` is left for a record with
no chunk to keep: one cut inside its 7-byte header (its versions are not
there to read) and one of another kind than the reader's; a cut in the
chunks is a loss (#614, below).

**Chunks are looked up by tag, in any order, a tag twice is a loss that
is used** (#510). Research (written on the issue): protobuf "parsers must
be able to parse fields in any order" and take the last value of a field
twice; PNG fixes the order only of its critical chunks and lets a
decoder pass over an unknown ancillary one; EBML has no order among the
children of an element, ignores what it does not know and reads an absent
element as its default; CBOR leaves a map with a key twice to the
decoder. So the format is a set of chunks found by their tags, and the
order is the writer's, not the format's.

* `CANON` (`src/schema.bats`) puts the chunks of a record in the order of
  the groups before they are read: for each group in turn, `EXT` takes
  every chunk of its tag out of the list wherever it stands and chooses
  the last whole one (else a damaged one, else none); what is left
  follows, as the chunks a newer Quire added. `SDEC` then reads that
  list as it always did. `canon_functional`, `ext_functional` and
  `lostcat_functional` make the result one, `canon_read` is the run time
  one (`ext_read` per group), and `record_read` is total as before.
* A tag twice is damaged but recoverable, not `Damaged`: the later
  whole chunk wins (a later one whose CRC is bad does not hide an earlier
  whole one: protobuf and CBOR take the last because they have no
  checksum to tell which is whole), the earlier ones are dropped from the
  value and their tag is among the `lost` of `rr_loss`, so the book is a
  `LossyBook`, said once, and the next save writes one chunk of each tag
  and keeps the old bytes under `library/damaged/<id>/<crc>`. `JOIN`
  joins the dropped tags to the groups' own losses (`LOSTCAT`).
* A chunk this version does not know (a lower case first letter) is kept
  whole and in order, twice if it was there twice: it is opaque, and a
  repeat can be the newer writer's list (PNG allows several tEXt chunks),
  so it is not for this version to drop one. They are written after the
  groups. One whose tag is a group's is not kept (`NOTKNOWN`).
* What makes the written chunks read back as they were is a proof the
  writer carries: the tags of the groups are all different
  (`SPECSOK`, from each `SPV_cons`, generated by `scripts/gen-record.py`)
  and the tag of a kept chunk is none of the groups' (`extrasv` carries
  it: `EXV_cons(ANC, NOTKNOWN | ...)`), so `senc_canon` shows that the
  chunks written are their own canonical ones (`tests/static/reject/
  codec-group-twice-earlier-wins`, `codec-group-twice-not-said`).
* **A group the record needs, lost, is substituted (stage 2b).** The
  `LOSES(requirement)` constructors of `SDEC` (`SD_garbled_lost`,
  `SD_bad_lost`, `SD_absent_lost_end`, `_good`, `_bad`) are one set for
  `req` and `opt`, a group absent, with a bad CRC or fields that do not
  parse; `added` keeps its own, for which absent is silent. A book whose
  TITL is lost is "Untitled" (the contents panel's word for a label with
  none), whose AUTH is lost has no author, whose BOOK is lost has ids 0
  in the record and the ids of its key in the library. **The key wins**
  (`_read_book`, `_keyed_book` in `src/libstore.bats`): a record found
  under `library/book/<id>` is the book `<id>` whatever ids it holds, and
  its save writes the key's ids. Such a save (`_repaired`) writes the
  library's image whole, every group, and keeps the bytes the record had
  under `library/damaged/<id>/<crc>`, in the same transaction. Research
  (on #510): SQLite's `.recover` keeps what it cannot place in a
  `lost_and_found` table and calls the result a salvage, and Calibre
  rebuilds a lost `metadata.db` from the book folders, so the record
  is salvaged and the book files stay the source of truth (stage 2c, below,
  reads the title and author from the file again).
  `tests/codec` and `e2e/library-records.spec.js` lose each of AUTH, BOOK
  and TITL, absent and damaged.
* **What a record lost and the book's file can say is read again from
  the file (stage 2c).** As a book is reopened from storage (`Reopen` in
  `_opf_store`, `src/import.bats`), where its OPF is parsed anyway,
  `lib_rebuild` (`src/library.bats`) takes from it what a field holds only
  as a placeholder: the title "Untitled", the author "Unknown", a series
  with no name or no position, no direction of the text, no file size. A
  field holding any other value is never changed (the file is the source
  of what a record lost, not of what it holds), and what the reader made
  (place, shelf, collections, finished, minutes, order, notes) is never
  read from a file. Not rebuilt: the cover, the progress weights (the
  reader works them out as the chapters are laid out), the accessibility
  summary. A rebuild that changes something saves the library at once (the
  record is repaired and the old bytes kept); one that changes nothing
  writes nothing. `e2e/old-library.spec.js` removes a real book's title
  and author groups and opens it.
* **The version before (stage 2d).** `library/previous/<id>` holds a
  book's record as it was before a save, and `library/stamp/<id>` when
  the record was last written (4 bytes, seconds since 2025; read once at
  the library's load into memory, `_stamps` in `src/libstore.bats`). A
  save keeps the record it replaces as the previous version only when
  that record was last written 60 seconds ago or more (an unknown stamp
  counts as old) and decodes whole, and writes the stamp on every save,
  in one batch with the record: KOReader's rule (its `.old` is not
  rotated until 60 seconds old, so a crash loop cannot overwrite the good
  copy with a bad one), on the age of the file replaced, so saves a few
  seconds apart never rotate and a bug that damages a record at each save
  leaves the version from before the first. A book whose record is broken
  beyond recovery (`UnusableDamaged`: cut inside its header, or empty or
  over `RECORD_MAX`; or a cut in its chunks that kept none of AUTH, BOOK
  and TITL, #614) and that has a
  previous version is read from it (`_recover`, a `LossyBook`); the save
  of a book whose stored record is not whole writes the library's image
  as a new record and keeps the bytes under `library/damaged` (it used to
  be refused; `NotQuire` and `Newer` still are). Emptying the Trash
  deletes the record, its previous version and its stamp together. The
  stamp is a key of its own, not a group: a group would be a field of
  every image and record, and it is the library's bookkeeping, not the
  book's. A record cut in its framing is no longer one of these (#614,
  below); `UnusableDamaged` is left for what has no chunk to keep. A
  record whose reader state a damage lost needs no
  notice action: a lost group reads as a substitute with the stamp 0, so
  the next sync's merge takes the store's (or the Auto Backup file's)
  value, and the save that follows writes every group and keeps the old
  bytes (#615; `e2e/sync-lost-groups.spec.js` plays a book with its place,
  Hidden shelf, finished mark and a bookmark through WebDAV, Google
  Drive's app data folder and Auto Backup, with PLCE, SHLF, FNSH and SIZE
  absent or with a bad CRC, TITL and AUTH absent, and the notes record
  deleted: 54 tests on desktop and android, and with the store file
  emptied first the shelf, SIZE and combined cases fail, so the spec
  measures the restore. Not played: the collections group, Dropbox,
  Fastmail and Nextcloud, two devices racing, a deleted book record). By
  research (the issue): Anki's answer to a damaged collection is a
  one-way sync that takes the whole collection from AnkiWeb, Firefox's a
  sign-out and sign-in that refills a rebuilt places.sqlite from the
  server, and Calibre's `restore_database` rebuilds from each book's
  metadata.opf and loses what the OPF does not hold; each takes the whole
  database, where Quire's merge takes the lost groups only.
* By the principle for any record that does not decode cleanly (the user's
  rule for #510): recover fanatically; if a bug in Quire damages a record
  the reader must still read the book. In order: (1) usable with
  defaults or substitutes (a lost or absent group, a tag twice, a bad
  CRC, and, from the next stage, a lost required group); (2) said, once,
  in the notice (#507: Copy details with the record's id and what was
  lost); (3) the old bytes kept under `library/damaged/<id>/<crc>` when a
  save repairs it; (4) `Unusable` only for what cannot be read as a
  record at all (`NotQuire`), has no chunk and no header to read (cut inside
  its header) or is a newer Quire's (`Newer`, not damaged). A bug that leaves a record unusable is fixed by widening the
  recovery, not by setting the record aside.
* Tests: `tests/codec` (the chunks in the opposite order, a group twice
  either way), `e2e/library-records.spec.js` (every rotation, the
  reverse and seeded shuffles open as the same book and are not written
  by opening; a group twice; an unknown chunk twice).

**A record cut in its framing is a loss, and keeps the chunks before the
cut** (#614, the last place in #510 where a record was set aside instead of
read). A record whose bytes end before its end chunk, whose chunk has a
length past the record's end or over the limit, that has bytes after the end
chunk, or whose end chunk holds data, is not `rr_damaged`: each chunk is
framed and CRC-checked by itself (PNG's design), so the chunks read whole
before the cut are intact and are kept. The groups they hold are read, those
after the cut are lost with their substitutes (stage 2b), and the record is
`rr_loss`, said once as any loss is, its save writing it whole and keeping the
old bytes. Research (on #614): SQLite's `.recover` salvages "as many database
pages as possible" where `.dump` stops at the first damage, and keeps what
it cannot place; a PNG decoder can "tell the application: this is a broken
PNG, but here is the data that I've been able to retrieve so far" (a libpng
maintainer's words; WebKit's reads PNG progressively and keeps the rows
decoded before a failure); protobuf: nothing found on what a truncated
parse leaves, so none claimed.

* **The sequence carries what was read** (`src/seq.bats`): `seqres` is
  `sq_ok(chunks)` or `sq_cut(chunks, cause)`, the cause a `seqcause`
  (`sc_trunc`, `sc_big`, `sc_trailing`, `sc_end_data`) and the chunks those
  read whole before the cut, in order (a bad one as `pbad`). The failing
  constructors of `SQC` say it in their types (`SQC_short` is
  `sq_cut(pnil(), sc_trunc())`, `SQC_good_fail` is `sq_cut(pgood(tag, data,
  chunks), cause)` of the rest's cut), so a cut cannot claim a chunk it did
  not read (`tests/static/reject/codec-cut-claims-unread-chunk`) nor bytes
  after the end chunk be a record read to its end
  (`codec-cut-trailing-is-complete`). At run time `seq_read` answers
  `SR_cut(.. | chunk_list, causev)` with the chunk list kept; a match that
  leaves the cut out does not type-check (`codec-cut-read-unmatched`).
* **The cut is named in the loss by a constructor of its own**, not a tag:
  `lost` is `lt_nil | lt_cons(tag, lost) | lt_cut(seqcause, lost)`, at run
  time `LTV_cut(causev, ..)`; the cut is put first, ahead of the tags
  dropped and the groups lost (`LOSTCAT_cut`, `codec-cut-lost-another-cause`;
  a match on `lostv` must name it, `codec-cut-lost-unmatched`).
* **What is proved**: `FIN_cut` is `FIN_body` for a cut sequence, with the
  cut among the dropped (`JOIN(.., lt_cut(cause, dropped), ..)`), so a cut
  record is read from the chunks before it by the same `CANON` and `SDEC`; its
  outcome is `JOIN_ok_cut` (every group read: `rr_loss` naming the cut,
  `codec-cut-not-said`, `codec-cut-read-as-damaged`), `JOIN_loss` (some group
  lost too, `codec-cut-dropped-from-join`), or `JOIN_newer` when a chunk that
  must be understood is among those read (a cut does not hide a newer
  Quire's record) or `JOIN_damaged`. `seq_functional`, `lostcat_functional`,
  `join_functional` and `fin_functional` have the new cases; `decodes_functional`
  and `record_read`'s totality follow; `encodes_decodes` and `seq_chains` are
  about whole sequences and do not change.
* **A cut that leaves a required group missing**: the key wins (stage 2b). A
  cut that keeps BOOK keeps its ids, equal to the key's unless the record
  was under another book's key; a cut before BOOK has ids 0 and takes the
  key's, repaired at its next save. Title and author come back from the
  book's file (stage 2c) when it is reopened.
* **Trailing bytes and an end chunk with data are cuts too**: every chunk
  is whole and nothing is lost but the trust in the rest. The loss notice
  ("show as defaults") is then more than the facts need, as it is for a
  tag twice; the next save writes the record clean.
* **The collections' record is cut the same way** (`IR_loss`, `LossyIndex`): its
  collections are shown, and the loss is told with the library's loss notice
  ("Some details of your library were damaged ..."). `_adopt_index` used to
  count a collections record that lost a group as one that could not be read
  and said "Your collections could not be read, so they are left as they are
  and not shown" while showing them; it answers `index_adopted` now.
* **A cut that kept none of the groups the record needs reads the version
  before it, when there is one** (stage 2d, as before #614). `_read_book`
  looks at the loss it got back (`_cut_kept_nothing`): a cut with AUTH,
  BOOK and TITL (the groups of `m_req`) all lost kept nothing the book is
  known by, and the book is an `EmptiedBook`, which `_recover` replaces by
  the previous version (a `LossyBook`) or, with none, keeps as the
  `LossyBook` the cut record is. A cut that kept at least one of the three
  keeps its own groups, newer than the previous version, and says the loss.
  The test is on the tags of the loss list, not a proof: a cut record whose
  kept group's tag was also there twice would count as having kept
  nothing, and the version before it is then read for it. The collections'
  record has no previous version, so it is always read as the cut record.
* Tested: `tests/codec` (a record cut at every length: the chunks before the
  cut are kept and read as the record of those chunks and the end chunk, a
  length past the end, over the limit, bytes after the end chunk),
  `e2e/library-records.spec.js` (each kind of cut, the collections' record,
  and a record cut inside its header, which is still set aside).

**A group added later is not loss when it is absent** (#497).
A group is one of three modes in `scripts/record_tables.py`: `req`
(the record needs it), `opt` (every version of the format has written
it: absent is damage, present and damaged is loss, the defaults), and
`added` (added to the format after records were written: absent is
nothing, the record reads whole and the group has its defaults; present
and damaged is loss as for `opt`). `prog`, `snum` and `tdir` are `added`,
and every group added from now on is. Before this an absent group of
either mode was `Damaged`, so a Quire that added a group made every
record written before it unreadable: the book was shown nowhere, the
banner said it could not be read, and Settings offered to set it aside
(which would have moved it out of the library). By research: a PNG
decoder must not require an ancillary chunk, protobuf reads an absent
field as its default, and SQLite's `ADD COLUMN ... DEFAULT` leaves old
rows unrewritten and valid; none counts a record written before the
addition as damaged. The format version cannot tell them apart (the
records in the wild are all version 1, with any prefix of the groups),
so it is the group's own mode. A chunk cleanly cut out of a record is
the same as one that was never there, as in PNG. The decoded record
says which groups were absent (`rx_mk(format, least, vals, extras,
absent)`, `vals` holding the group's defaults), reading is a proof
about it and writing an absent group writes nothing, with the proof
that the next chunk is not the group's (`SENC_absent_*`, `TAGDIFF`), so
`decodes_encodes` and `encodes_decodes` hold byte for byte for a record
with and without the group. The app only ever writes records with every
group (`record_write` has `ab_nil()`), so the first save of an old
record writes the groups it lacked; opening writes nothing and keeps no
copy (`e2e/library-records.spec.js`, "written before ... existed").

**The rule cannot be forgotten, and every table that shipped opens**
(#515). A group of a record is added only as `added`, never `req` or
`opt` (those are the first table's twelve groups and the index's two),
and a group added is named in `RELEASES` in `scripts/record_tables.py`
with its commit. `tests/static/groups.py` (in `tests/static/run.sh`'s
`checkers`) fails a group of the other modes after the first table, a
group not in `RELEASES`, and a change that does not add the library of
the table before it: `e2e/old-library.spec.js` has one library for each
table that shipped (`SHAPES`: the first table, then each prefix of
`RELEASES`; the real build's library cut of the groups a build before it
did not write, which is byte for byte what that build wrote, since a
chunk's CRC covers its own tag and data), and each opens with every
book, nothing said, nothing to set aside, no record changed or copied on
open, and a save writes the current groups. The QLB1 to QLB6 formats of
the old whole-library record are in `e2e/library-records.spec.js`. The
Settings row "Set aside unreadable records" is absent for every record
that reads (even with loss), in each of those specs.
The flake of the set aside spec (#515) was the specs', not the app's:
on the android project the app syncs as it opens (Auto Backup's file is
merged), and the records it writes (`library/index`, and the books'
`ORDR` renumbered by the save after a merge once a record is missing)
land when that sync ends, not when the books show, so they landed over a
spec's change to the store or after the snapshot it compared with.
`syncEnded` / `reloadSettled` (`e2e/legacy-library.js`) take
"sync-state" away before a reload and wait for the sync's end to write
it (`_end`, after the saves), so a spec changes and snapshots the store
only when the app has stopped writing it.

**The codec is proven** (`src/bytes.bats`, `crc.bats`, `chunk.bats`,
`seq.bats`, `fields.bats`, `schema.bats`, `record.bats`; the book's and
the index's tables are in `scripts/record_tables.py` and
`bookrec.bats`, `indexrec.bats`, `bookimage.bats`, `indeximage.bats` are
generated from them by `scripts/gen-record.py` and `scripts/gen-image.py`,
so a field is added in one place). Byte strings are a datasort
(`bytes`) in the types, `blist(bs, n)` linear lists indexed by them, so a
proof can say what the bytes are. Reading is a relation between bytes
and its result (`DECODES(sp, kind, bs, res)`, built of `CK`, `SEQ`,
`FIN`, `SDEC`), writing another (`ENCODES(sp, kind, x, bs)`, built of
`CKENC`, `CHAINS`, `SENC`), and the laws are lemmas the compiler checks,
so a codec that is not the inverse of itself does not type-check:

* `encodes_decodes`: what is encoded decodes to what was encoded, as
  exactly that record (no padding is accepted, no kept chunk is lost:
  `tests/static/reject/codec-drops-unknown-chunk`);
* `decodes_functional`: bytes decode to one result;
* a record read and saved is never changed in meaning: whatever the
  chunks' order or repeats were, `record_write` of the very values a
  read gave (`vals`, `extras`) is `ENCODES` of the same record, and
  `encodes_decodes` makes that decode to `rr_ok` of it, so
  decode(encode(decode(x))) = decode(x) on the value. The first law of
  an earlier version, `decodes_encodes` (the bytes decode to x, so
  encoding x gives the same bytes), no longer holds and is gone: out of
  order bytes decode to x and are written in ascending order (#510,
  below);
* `record_read` is total: it answers every list of bytes with a result
  and its `DECODES` proof, and `record_write` returns the `ENCODES`
  proof of the bytes it made. The CRC's tables are `CRCP`, a relation
  checked by the same compiler, and the stored sum is compared with it
  before a chunk is `ok` (`CKD_ok` cannot be built from a sum that
  differs).

**The round trip is proved, from the value to the bytes and back.**

* A stored book is a `book_image(x)`, indexed by the book `x` it holds
  (`bookx_mk(author, id_high, ..., title)`): each number is an
  `int32v(n)` (its four bytes and the proof `LES` that they are the
  number `n`), each string a `bstr(bs)`, an array of array's `barr` whose
  cells are proved to hold the bytes `bs` (`HOLDS`, by induction on the
  list over array's own lemmas about `NTH` and `SETC`). `int32_make`
  gives the number `n = x` of an int `x`, or says it is not one of 32 bits.
* `book_record_new` makes a `bookrecord(x, 1, 1, ex_nil())` of an
  image, `book_record_image` an image of the very `x` of a record,
  `book_of_image` and `book_image_of` keep it; the lemma
  `book_roundtrip` (generated with the records: `index_roundtrip` too)
  proves that bytes written from `x` and read back as a book `y` make
  `x = y`, and `book_enc_dec` that they are read back as a book at all.
  `book_image_roundtrip` is the whole of it as a function: an image
  written as a record and read back from the bytes is an image of the
  same book, and the compiler accepts it only by those lemmas
  (`tests/static/reject/image-roundtrip-another-book`). Without the
  lemma it does not type-check.
* The bytes of a record reach an array through `blist_to_buffer`, which
  fills a `barr` whose cells it proves hold the list. What is outside the
  proof is only what is outside quire: bridge's atoms that write an array
  to IndexedDB and fill one from it (JS), the array package's memory
  primitives (`barr_get`, `barr_set`, ..., the one unsafe core), arith's C
  operators (`and_proved`, `or_proved`, and `xor_g1` from them) and the
  prelude's `/`. Each is tested where it lives (array's
  `tests/dynamic/content`, arith's `tests/dynamic/xor`). The copy of
  a library `Book`'s fields into an image and back (`_image_of_book`,
  `_book_of_image` in `src/library.bats`) is a copy of its numbers and
  strings by `book_image_make`, which refuses a number that is not 32 bits.
  `tests/codec` runs the whole on bytes and numbers at the edge (damage to
  every byte, every prefix, fuzz) as a check of those boundaries, not as the
  proof.

**The solver is 32-bit**: a constant or a coefficient of 2 to the 30 or
more in a hypothesis makes the context contradictory, and anything is
then proved. No proof here has one (integers are built from bytes,
`b + 256 * m`, and bounded by 2 to the 28); `tests/static/literals.py`
fails the checkers on a literal of 2 to the 29 or more in `src/`, apart
from a run-time value marked `(* wide *)`.

A context can be contradictory with no large literal at all (#594): a
proof with nested divisions (`h/256 + 256*(l mod 256)`, two deep) made
the solver's elimination overflow, its context contradictory, and the
compiler accepted a false statement (`ROTR(16, h, l, l, h+1)`). It is not
only nested divisions. `tests/static/solver/` (standalone fixtures, run
by `tests/static/solver.py` under any patsopt) holds the cases found with
the `ATS2-Postiats-int-0.4.2` solver (CI built it until it moved to
the infinite-precision build, whose own risk is a proof it cannot answer in
time, not a false one it accepts; the caps of bats's setup action end that): a context of `h < 65536`,
`q == h / 256`, `r == q + 256*h` proves `1 == 2`; so does a pair of
matched copies of arith's `ROTR1` constructor (`rotr1_functional`,
`shr1_functional` and `add32_functional` proved nothing); a product
passing 2^32 does (`b < 2^20`, `v == 4096*b`). The infinite-precision
build rejects all of them. The rules for a proof's arithmetic, which keep
true under either (a proof that only the infinite-precision solver can answer
in time is split, as `date_text` and `add32_functional` were):

* **Keep the magnitudes down, and name the digits.** A statement is made
  of steps that divide (or take `mod`) by a constant of at most 16 at a
  time and numbers built a digit at a time (`b + 256 * m`, as `LE` and
  `STEP1` are), never a closed form with nested `/` or `mod`, a product of
  two variables, or two equations over the same variables with scales
  (1024 and 64 in sha256 stage D). Digit form helps and is not a
  guarantee: the guard is that no bound times a coefficient reaches 2^31
  after elimination, and that is only known by the next rule.
  `tests/static/proofs_audit.py` lists the places that are not (report
  only, a human reads each).
* **A false variant of every lemma.** Each lemma (`prfun`, `prfn`, a
  `primplement` of a `#pub prfun`) has its false variant rejected:
  `tests/static/mutation_check.py` makes them (a numeric index plus one, a
  guard's `==` shifted by one, a bound tightened by one, a byte string
  consed with a byte, an argument of another sort replaced by a fresh
  variable, each part of a tuple result, and `[1 == 2] void` in place of a
  guard) with the lemma's own body, and the compiler must reject each
  (`--root DIR --run WORK file.bats` for another package, `--ats-home DIR`
  for another patsopt, `--inplace` for a recursive `#pub` lemma, whose
  declaration and primplement are changed where they stand and whose
  dependents are checked again: minutes a mutant). An accepted mutant is a
  vacuous proof (or a mutation that is true: `tests/static/mutation_known.txt`),
  and is filed as its own p1 issue with the minimal case. A lemma no
  operator reaches (a `FALSEP`, `EQFD` result) gets its false variant as a
  fixture in `tests/static/solver/reject/`, with its true statement in
  `accept/`. The checker is itself tested (`tests/static/mutation_test.py`,
  a step of the `checkers` member: a stand-in compiler that accepts the
  mutants of a vacuous lemma and rejects those of an honest one, the
  operators, the in-place edit, the choice by a diff). The solver
  fixtures run as the `solver` member (122 files, 38 s under the
  infinite-precision build, all as they should be; the -int build accepts 5
  of the false ones).

* **No `[a | prop]` as the result of a `prfn`.** The issue found that such
  a return silently dropped the proposition; the guards `[p; q] void`
  and `[p && q] void` of crc and arith were all checked by mutants and are
  not dropped, so the rule is kept for the existential with a variable
  only: return a dataprop (an `EQI`, a `LEN`), or state it with a `prfun`.

## How far through the book: by the text's size, to the text's end (#426)

`_progress` (the library card and Book info) counted every spine item the
same, so a book of 3 long chapters and 10 short notes read 23% at the end
of its text, and a cover, a title page and a copyright page started a
book at 20%; the reader's footer and scrubber already weighed chapters by
size (`book_weights`). They are one rule now, written down here first, by
research:

* **By size, not by spine item.** Readium's positions are a resource's
  size in 1024-byte steps (the W3C EPUB working group's thread on page
  lists: Adobe since 2007, Readium-based apps since; some systems divide
  the zip entry's size, as `book_weights` does), and Kobo's percentage
  follows the book's words or size, not its pages (MobileRead users on
  the same book as an EPUB and a KEPUB, where 160 of 405 pages and 812 of
  2607 differ). Kindle's is a location, which is also size. Nothing
  comparable counts spine items, except for a fixed-layout book, where
  every spine item is one page of the same worth and the page indicator
  counts them: `book_weights` gives each chapter 1 when every chapter is a
  fixed page (`book_all_fixed`).
* **The text's end is 100%.** Kindle counts the back matter in the
  percentage, and its readers say what the Mudita forum's reader said
  (64% to 100% on the last page of the text) and keep a bookmark where the
  notes begin; Kindle's own "end of book" is the cure Quire takes. The
  EPUB 3 landmarks' `backmatter` entry (the same nav `toc_start_dest`
  reads `bodymatter` from, `PartEnd` in `src/toc.bats`) names the first
  chapter of the back matter; `toc_build` hands it to
  `book_text_end_set`, and from that chapter on `book_weights` gives
  nothing (before = total, own = 0), so the total is the text's, the
  back matter reads 100%, and the scrubber, the ticks and the time left
  follow. A book with no such landmark counts all of it. `epub:type` inside
  a chapter is not read: that is every chapter opened, for one that is
  not the book's. A `backmatter` landmark at the first chapter is no end.
* **The page's start, but the last page of the text is 100%.** The
  footer has always said where the page starts (a first page is 0%, a
  second "<1%"); the page that holds the text's last line says 100%
  (`_permille`), so the percentage is not 98% on a finished book. The book
  is finished (`done`) when the percentage is 100%, which for a book
  without back matter is the last page, as before, and for one with it is
  the end of the text (`_weighed_stored` >= 1001 in `_record_position`).
* **Stored once, carried with the place.** The library cannot weigh a
  book it has not opened, so the reader keeps the thousandth of the place
  (`progress_weighted`: the thousandth plus one, 0 when never worked out,
  decoded once into a `progress_basis`, `ByChapters | Weighed`, by
  `_progress`) beside the place whenever it saves it. A book not read
  since keeps the old count by chapters until it is. It is the record's
  `prog` group (lower case: ancillary, so a Quire without it keeps it and
  reads the record, as for any unknown chunk; every group before it is
  capital), the backup's and the sync file's `progressWeighted`, slot
  `SLOT_PROGRESS_WEIGHTED` taken whenever the place is (`_take_place`),
  and the 18th number of an orphan record ("QO1"). A file that does not
  have it gives 0, so a place restored or synced from an older Quire is
  counted by chapters until the book is read here.
* The size is the entry's size in the archive, as before: the e2e books
  store their chapters, so it is their bytes. A book whose chapters
  compress very unlike each other weighs them by compressed size; the
  uncompressed size is in the zip's directory and is not carried to the
  chapters yet.

`e2e/progress.spec.js` (books in `e2e/progress-books.js`, checked by
epubcheck) plays each of #426's cases, and backup and sync carrying the
number (`e2e/sync.spec.js`).

## Replace keeps what the reader made (#425)

A book's id is the SHA-256 of its file (`_file_id` in `src/import.bats`),
so the duplicate question (Skip / Replace) is asked only for a file that
is already in the library, byte for byte, and an archived book is put
back by importing it with no question. Replace (`import_mode` `Replace`)
changes the book's file (one `b<id>` entry), size, series and cover (when
the file has one) and nothing else: the place, collections, finished
mark, minutes, annotations and notes, order and id stay, and so does a
hidden book's shelf; only an archived book or one in the Trash comes back
to the Library, as the reader asked for it. `e2e/replace.spec.js` holds
the whole record of the library, the file's size and the card, before and
after, to be the same, and plays a backup, a second device and a second
tab over it. By research (the issue's comment): Apple Books and Kobo make
a corrected file a new book and the notes stay with the old one, which is
what users complain of; so a corrected file of a book in the library is
offered Replace too.

**A corrected file** has another id, so it is not the duplicate question's.
When the OPF of a new file is read (`_opf_done`), its title and author are
compared with the library's (`lib_find_similar`: case and the white space
around them ignored, a title that is empty never matches, a book in the
Trash is not one); a match asks "Newer file of a book?" (`QNewerFile`,
`_ask_newer`): **Replace** or **Add as new book** (also Escape: nothing is
lost either way). Nothing has been stored by then (`BookLooksLike`); after
the answer the OPF is read again as `Replace` (the file, cover and
accessibility data stored under the *book's* id, the id kept) or as
`AddAlone`.

**Chapters are found by name.** The hrefs of a book's chapters (`src/chapter_hrefs.bats`,
the chapters as `_spine_chapters` numbers them, an empty line for one that
names no file) are kept under the key `h<id>`, written when a book is
opened and by every replace. A replace reads the old record, makes a
`chapter_map` with the new file's hrefs (`MapByHref`; `MapByNumber` when
the old file's were not kept, a book not opened since: the same number
when the count is the same) and:

* the place (`_place_moved`): the chapter of its href, at the same page and
  anchor; else the chapter of the same number if there are as many, else
  the first, at its start; the progress weights are counted anew. Nothing
  changes when the hrefs are the same in the same order.
* each note (`annot_reanchor`, `_relocate`): its chapter's new number; one
  whose chapter is not in the new file is kept under `LOST_CHAPTER` + its old
  chapter, which is listed after every chapter under "Not found in this
  version" with its words and note, painted nowhere, leading nowhere,
  exported with that heading. A note's id contains its chapter, so a moved
  note has its old id deleted (a tombstone) and sync passes on a deletion
  and a new note. A note of a chapter that exists but has not the node it
  names is lost the same way when the chapter is shown
  (`annot_chapter_shown`, from the chapter's count of content nodes): the
  nodes of a chapter are known only when it is rendered, and a changed
  word is not noticed (a note is lost when its nodes are gone, not when
  its text changed).

By research for the annotation rule: Kobo keeps an annotation of a
restructured book in the list when it no longer shows in the text; Apple
Books and Kobo lose them when the corrected file is a new book. No
documentation was found of how Thorium or Moon+ match annotations of a
replaced file (searched), so nothing is taken from them.

**Another tab** (`src/file_version.bats`): bridge has no channel between tabs,
so a tab that has a book open asks, when it is shown again
(`visibilitychange`, the moment sync runs; web apps refetch stale data when
a tab regains focus, as TanStack Query does by default with
`refetchOnWindowFocus`), which
file the book is made from: the key `v<id>` holds the file's id when it is
not the book's own (a corrected file; deleted when the book's own file comes
back). If it is not the file the tab opened, the tab goes to the library and
the banner says "This book was replaced with another file in another tab"
with Reopen Quire (`BookReplacedElsewhere`). A tab in a second window
side by side is told when it is shown again, not at once. An identical file
changes nothing, so nothing is said. `e2e/replace-corrected.spec.js` plays
all of it with fixtures that pass epubcheck (`e2e/replace-books.js`).

## A library that cannot be read says why, and offers what fits (#374)

Bridge's IndexedDB read says why it failed: `Unreadable(cause)` carries a
`browser_reason`, the DOMException's name decoded once there
(`Transient` = UnknownError, `StorageBlocked` = SecurityError,
`NewerVersion` = VersionError, `Aborted` = AbortError, `NoErrorGiven`,
`BrowserUnexpected` with the name, a line feed and the message).
`src/unreadable.bats` turns that into a `failure_kind` (flat, copied
freely: `KindTransient`, `KindStorageBlocked`, `KindNewerVersion`,
`KindAborted`, `KindNoReasonGiven`, `KindBytesUnreadable`,
`KindUnexpected`), and the library's read keeps it: `library_content`
(`src/libstore.bats`) matches the lookup itself, where `lookup_content`
folds every cause into `ContentUnreadable`, and `library_read.ReadFailed`
carries a `failure_found` (the kind and, for an unexpected one, the
name and message as text, cut at 4096 bytes, never dropped). No other
read of storage changed: each still folds, as #174 says.

* **Hope is a proof.** `HOPE(failure)` is a dataprop with a constructor
  for `FTransient` alone (the sort `failure` and the witness
  `failure_is(f)` of each kind sit beside the flat `failure_kind`, which
  a cell can hold). The screen's `remedy` is `TryAgain(HOPE(f) | failure_is(f))`
  or `NoRemedy`, made only by `remedy_of`, a total `case+` over the
  kinds, and `ui_try_again_show` needs the `HOPE(f)`: Try again for any
  other kind does not type-check (`tests/static/reject/try-again-without-hope`;
  `accept/try-again-transient` shows the transient one does). `retry_hope`
  (`Hope | NoHope`) is read off `remedy_of`.
* **Aborted has no hope**, by research (the decision is also next to
  `HOPE`): the IndexedDB specification defines only UnknownError as
  transient; AbortError is "a request was aborted", raised when a
  transaction is aborted (by `abort()`, or after a failed request nothing
  handled), and Quire's read never aborts, so something else did and
  nothing says it will not again; Dexie's page on AbortError says only
  that it happens when the transaction was aborted and gives no advice
  to retry, and localForage reconnects and retries once, but on
  InvalidStateError and NotFoundError when a transaction cannot be
  created, not on AbortError.
* **What the screen says** (`library-empty`, `_unreadable_text` in
  `src/library.bats`; every text ends "Quire has not changed anything and
  will not save until it can read your library.", and none says "Import
  an EPUB", which is for an empty library): Transient, "Quire could not
  read your library this time." with Try again (`library-try-again`);
  StorageBlocked, the private window or site data blocked and to allow
  site data for this address, or leave the private window, then reopen
  Quire; NewerVersion, "This device holds data from a newer version of
  Quire. Update Quire."; Aborted, NoReasonGiven and BytesUnreadable, to
  reopen Quire to read it again; Unexpected, an unexpected error with the
  details in the banner. None but Transient has a button. Import is off
  while the library is unreadable (`inert` on `import-file`, and the
  button drawn disabled: muted text on the card, a cursor that says no,
  `#import-button:has(input[inert])` in the stylesheet, a `surf` pair
  proven in each theme; a file handed or dropped is refused with "Books
  cannot be added until Quire can read your library"). Records that can be read but not
  used are another case, below (set aside); a read that failed as a whole
  is not one, since nothing is known of what it holds and a new library
  made beside it could not be seen while the read keeps failing.
* **Records that cannot be used are set aside, not replaced** (the
  follow-up of #374). A library whose read worked can still hold a book's
  record, or the collections', that is not Quire's or has no header to read (cut inside its 7 bytes, empty,
  over `RECORD_MAX`, or of another kind; a cut in the chunks is used, #614, as is every other damage, #510,
  and a book with a version before it is read from it, 2d) is shown nowhere and not
  written over by a read; the collections' record, and a book's of a newer
  Quire or not Quire's, are never written over, so no collection can be made
  while the collections' is one of them, and a book of those cannot be
  imported again (a book whose header is broken can: its import writes the
  library's image over the record, the bytes kept, 2d). Settings shows a row then (`settings-aside`,
  `lib_aside_show`: "Set aside unreadable records",
  `settings-set-aside`), and only then. Pressing it
  (`lib_aside_run`, `lib_set_aside`) reads the library again and, for each
  such record, runs `libstore_set_aside_book` / `libstore_set_aside_index`:
  one `idb_update` transaction that reads the record, decides again with
  the codec (`_read_book`, `_read_index`; what was believed before does
  not decide) and, only for `UnusableDamaged` and `UnusableNotQuire`,
  writes the record's bytes to `library/damaged/<id>/<crc>` and deletes
  the record in the one batch (`_aside_writeback`), so an aborted
  transaction leaves the old record byte for byte
  (`e2e/library-records.spec.js`). A newer Quire's record
  (`UnusableNewer`) is never set aside: it is not damaged, an update of
  Quire reads it (`AsideNewer`). Nothing is lost, so it is not a `harm`
  and has no confirmation; the row then says to import those books again
  and restore a backup, which re-applies their places, shelves and notes.
  By research: Firefox renames a corrupt `places.sqlite` to
  `places.sqlite.corrupt` and starts a new one; Mozilla's application-services
  weighed moving the file aside against deleting it and chose deleting only
  because it acts on confirmed corruption; Roon and Miro tell the user to
  keep the old data folder or back the corrupt database up, then start
  fresh. Quire keeps the copy, as they do, and acts on one record at a time
  instead of the whole library, so what reads is never touched.

* **The banner.** A kind the screen says completely has no banner: the
  screen gives what happened, what Quire did, what to do and the
  browser's name for it ("Details: UnknownError."), which is what a
  report needs. Only an unexpected failure raises one
  (`notice_unexpected`: the name and message as the answer, Copy details,
  Report), since it carries what the screen cannot and its screen has no
  button for it to cover. A banner shown first at the foot of the library
  covered Try again on a short phone (CI, mobile-portrait), and one at
  the top covered the header; over the library the banner is now part of
  the page, above the header, and pushes it down (Material 3: a banner
  sits under the top app bar and moves the content; position relative
  with the base rule's centring), so it is over nothing. `coveredByBanner`
  (`e2e/controls-shown.js`, run by `fits`) reports the header's controls,
  `library-empty` and `library-try-again` under the banner, and Try again
  under anything at its centre, whether a banner is up or not; the layout
  spec runs it on an unreadable library of each sort in every project. A
  banner wraps its buttons under its message on a narrow window instead
  of squeezing Report. Over the reader it is fixed at the top while the
  reader's bars are away, and under the top bar while they are up
  (`.banner.under-bars`: the bar's safe inset,
  44px control and 2px, and 8px), as material.io's, Flutter's and
  Zeta's banners sit under the app bar and none draws over it;
  `e2e/storage.spec.js` raises one over the reader with its bars up and
  runs `coveredByBanner` on both bars.
  A modal layer is over the status (#556), as an Android dialog or drawer
  is over its activity's Snackbar, and the library's menus were already
  over the banner (#507): while a library menu is open the Undo toast is
  drawn under its veil, and while a veiled reader panel is open (Contents,
  highlights) the banner is under the scrim; both are still up, and back
  when the layer closes (an Undo offer lasts until dismissed, #364). The
  layer module says it as attributes of the element it places, as it opens
  and closes (`_open_set`, `_modality_show` in `src/layer.bats`:
  `data-menu` on `undo-toast`, `ui_undo_under_menu`, and `data-veil` on
  `error-banner`, `ui_banner_under_veil`; `data-menu` on the banner is the
  same for #507), and the rules are `#undo-toast[data-menu='1']` and
  `#error-banner[data-veil='1']`: the first version of #556 asked
  `#bats-root:has(...)` of both, which `tests/static/has_root.py` (#538)
  rejects, since a `:has()` on the root that holds the chapter is
  re-evaluated over all of it (#423). A
  panel with no veil and the screens leave them where they are (a screen
  offers an Undo of its own). `coveredByBanner` also checks every control
  of an open menu, panel, sheet or dialog, and `toastClear` every control
  under a toast; `e2e/containers.spec.js` (a failed chapter's banner, then
  Contents) and `e2e/back.spec.js` (the Trash's Undo, then the library
  menu) use them instead of dismissing first. The details of an unexpected
  failure outlive its banner: they are kept in memory (`_details` in
  `src/notice.bats`, replaced by the next such failure, never stored)
  and About shows "Copy last error details" (`about-error-copy`, an
  `about_control` of the screen's one listener, since the table of
  listeners is full) once one is kept, as Firefox keeps its
  troubleshooting information on about:support with a Copy text to
  clipboard button. Start-up with a library that could not be read yet
  does not write over the stored view (`_library_shown(false)`): the
  retry opens the book it names, as the sync that waits for the retry
  runs then (`e2e/storage.spec.js`).
* **One honest retry.** Try again repeats the read start-up makes
  (`lib_load`) through `_library_read`, so the `LIBRARY_READ` proof is
  still only made there. `lib_retry_begin` spends the retry when it
  starts, so a second press does nothing and a failure leaves the screen
  with no button for the rest of the session (it says it tried again).
  When the first read fails for a reason with hope, the start-up steps
  that wait for the read (`_after_read`: files handed to the app, sync, the
  stored search and view) are held and run once when the retry ends,
  whichever way (the bridge keeps the files in their order meanwhile); for
  a reason without hope they run at once, as before (the files are kept,
  not added). The flag that stops every save of the library
  (`storage_savable`) is cleared only by `storage_read_again`, given
  `AttemptRead` by a read that worked (`Readable`); `AttemptFailed`
  leaves it (`StillUnread`). A read made again starts from nothing
  failed (`_read_outcome`), the kind it failed with is `_read_kind`, and
  `library_view` is `ViewBooks | ViewEmpty | ViewUnreadable(failure_kind)`
  (fixture `library-view-unmatched`).
* `e2e/storage.spec.js` stubs the library's read to throw a DOMException
  of each name (`failLibrary`), once or always: each kind's text and
  button, an unlisted name's details, Try again showing the books and a
  later import being kept, and a retry that fails.
