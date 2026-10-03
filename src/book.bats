(* book -- the open book: its file, and where its OPF is inside it *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use promise as P
#use result as R
#use zip as Z
#use str as S

staload "epub_xml.sats"
staload "pages.sats"
staload "paths.sats"
staload "mem.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"

(* A book's entries, found once when it is opened: an entry's data
   [data_offset, data_offset + data_size) in the file of file_size
   bytes, its method, and its name [name_offset, name_offset + name_len)
   in the book's central directory of directory_size bytes; count
   entries *)
#pub datavtype book_entries(file_size:int, directory_size:int, count:int) =
  | BookEntriesNil(file_size, directory_size, 0) of ()
  | {count:nat}{data_offset:nat}{data_size:pos | data_offset + data_size <= file_size; data_size <= 268435456}{name_offset:nat}{name_len:pos | name_offset + name_len <= directory_size; name_len < 65536}
    BookEntry(file_size, directory_size, count + 1) of (int data_offset, int data_size, $Z.compression, int name_offset, int name_len, book_entries(file_size, directory_size, count))

(* A write's answer no consumer took: nothing to free *)
implement $P.dispose<$IDB.stored>(_) = ()

(* The file's central directory, at directory_offset, kept while the
   book is open (for its entries' names), and its entries: the archive
   checked once, when the book is opened (book_begin) *)
#pub datavtype book_index(file_size:int) =
  | {directory_loc:agz}{directory_size:pos | directory_size <= 1048576}{directory_offset:nat | directory_offset + directory_size <= file_size}{count:nat}
    BookIndex(file_size) of ($A.arr(byte, directory_loc, directory_size), int directory_size, int directory_offset, book_entries(file_size, directory_size, count))

(* The book's chapters, in spine order, each found once in its index
   (the first time a chapter is loaded, book_spine_set): a chapter's
   data [data_offset, data_offset + data_size) in the file of file_size
   bytes, its method, its name [name_offset, name_offset + name_len) in
   the file, the length dir_len of that name's directory part and its
   layout (its itemref's, else the book's: reflowed, or a fixed page)
   and the side of a spread its itemref asks for; missing when its href is empty, over 1 MiB with the OPF's directory,
   or names no entry; count chapters *)
#pub datavtype book_chapters(file_size:int, count:int) =
  | ChaptersNil(file_size, 0) of ()
  | {count:nat}{data_offset:nat}{data_size:pos | data_offset + data_size <= file_size; data_size <= 268435456}{name_offset:nat}{name_len:pos | name_offset + name_len <= file_size; name_len < 65536}{dir_len:nat | dir_len <= name_len}
    Chapter(file_size, count + 1) of (int data_offset, int data_size, $Z.compression, int name_offset, int name_len, int dir_len, rendition_layout, page_spread, book_chapters(file_size, count))
  | {count:nat} ChapterMissing(file_size, count + 1) of (book_chapters(file_size, count))

(* The book's chapters once found, with their count *)
#pub datavtype book_spine(file_size:int) =
  | {count:nat} Spine(file_size) of (book_chapters(file_size, count), int count)
  | NoSpine(file_size) of ()

(* The open book's file and its size; its OPF's compressed data
   [data_offset, data_offset + data_size) and compression method; the
   OPF's name [name_offset, name_offset + name_len) in the file. The regions are proven inside the file, so the
   reader uses them with no check. The book owns its file (a linear
   handle, closed when the book is replaced), and its index. *)
#pub datavtype open_book =
  | {file_size:pos}{data_offset:nat}{data_size:pos | data_offset + data_size <= file_size; data_size <= 268435456}{name_offset:nat}{name_len:pos | name_offset + name_len <= file_size; name_len < 65536}
    OpenBook of ($BF.infile(file_size), int file_size, book_index(file_size), book_spine(file_size), int data_offset, int data_size, $Z.compression, int name_offset, int name_len)
  | {file_size:pos} Importing of ($BF.infile(file_size), int file_size, book_index(file_size))
  | NoBook of ()

(* The open book, taken out of its cell, which is left with none: it
   is put back with book_put *)
#pub fn book_take(): open_book

(* Puts book in the book cell; the book that was there, if any, is closed *)
#pub fn book_put(book: open_book): void

(* Opens book_file, of file_size bytes, as the book being imported,
   with a new serial, which it returns: its archive is checked here,
   once, into its index; when it is not an archive (or its central
   directory is over 1 MiB) book_file is closed and no book is open, so every read with the serial
   finds nothing *)
#pub fn book_begin {file_size:pos} (book_file: $BF.infile(file_size), file_size: int file_size): int

(* The book being imported, book `serial` of file_size bytes, opened
   with its OPF's regions; false when another book is open *)
#pub fn book_finish {file_size:pos}{data_offset:nat}{data_size:pos | data_offset + data_size <= file_size; data_size <= 268435456}{name_offset:nat}{name_len:pos | name_offset + name_len <= file_size; name_len < 65536}
  (serial: int, file_size: int file_size, data_offset: int data_offset, data_size: int data_size, method: $Z.compression, name_offset: int name_offset, name_len: int name_len): bool

(* An entry of the file found by name: its data
   [data_offset, data_offset + data_size), method and name
   [name_offset, name_offset + name_len) *)
#pub datavtype entry_hit(file_size:int) =
  | {data_offset:nat}{data_size:pos | data_offset + data_size <= file_size; data_size <= 268435456}{name_offset:nat}{name_len:pos | name_offset + name_len <= file_size; name_len < 65536}
    EntryHit(file_size) of (int data_offset, int data_size, $Z.compression, int name_offset, int name_len)
  | EntryMiss(file_size) of ()

(* The entry named name[0, name_size) in the index of the open book,
   when it is book `serial` of file_size bytes; a miss when there is none or another book is open *)
#pub fn book_find_entry {file_size:pos}{name_loc:agz}{name_size:pos}
  (serial: int, file_size: int file_size, name: !$A.borrow(byte, name_loc, name_size), name_size: int name_size): entry_hit(file_size)

(* The entry of the open book, book `serial` of file_size bytes, that
   the path data[href_offset, href_offset + href_len) names relative to
   a directory: the first dir_len bytes of the name at dir_name_offset
   in the file (such as a chapter's own name, so an
   href in the chapter is found); "." and ".." are resolved *)
#pub fn book_find_relative {file_size:pos}{dir_name_offset,dir_len:nat | dir_name_offset + dir_len <= file_size; dir_len < 65536}{l:agz}{n:pos}{href_offset,href_len:nat | href_offset + href_len <= n}
  (serial: int, file_size: int file_size, dir_name_offset: int dir_name_offset, dir_len: int dir_len, data: !$A.borrow(byte, l, n), n: int n, href_offset: int href_offset, href_len: int href_len): entry_hit(file_size)

(* Keeps chapters, chapter_count of them, as the chapters of the open
   book, when it is book `serial` of file_size bytes and has none yet; else frees them *)
#pub fn book_spine_set {file_size:pos}{chapter_count:nat}
  (serial: int, file_size: int file_size, chapters: book_chapters(file_size, chapter_count), chapter_count: int chapter_count): void

(* Chapter chapter_index of the open book, book `serial` *)
#pub datavtype chapter_got =
  | {file_size:pos}{data_offset:nat}{data_size:pos | data_offset + data_size <= file_size; data_size <= 268435456}{name_offset:nat}{name_len:pos | name_offset + name_len <= file_size; name_len < 65536}{dir_len:nat | dir_len <= name_len}{chapter_count:nat}
    ChapterGot of (int file_size, int data_offset, int data_size, $Z.compression, int name_offset, int name_len, int dir_len, rendition_layout, int chapter_count)
  (* The book has chapter_count chapters, but not a chapter_index-th one
     that names an entry *)
  | {chapter_count:nat} ChapterNone of (int chapter_count)
  (* The book's chapters are not found yet (or book `serial` is not
     open) *)
  | ChaptersUnknown of ()

#pub fn book_chapter_get {chapter_index:nat} (serial: int, chapter_index: int chapter_index): chapter_got

(* Where a spine item sits in a spread: a fixed page on the left, on the
   right, or across both (alone); or no fixed page (reflowed, missing,
   or past either end of the spine) *)
#pub datatype page_slot =
  | SlotLeft
  | SlotRight
  | SlotCentre
  | SlotNone

(* The slots of chapters chapter_index - 1, chapter_index and
   chapter_index + 1 of the open book, book `serial`, read right to
   left or not. A fixed page takes the side its itemref asks for; one
   that asks for none takes the side after the page before it: a left
   page's right, a right page's left, the first side of a spread (the
   left, or the right read right to left) after a centred one; and the
   first fixed page, or the first after a reflowed one, is alone on the
   right (on the left read right to left), as Apple Books shows a
   cover *)
#pub fn book_chapter_slots (serial: int, chapter_index: int, right_to_left: bool): @(page_slot, page_slot, page_slot)

(* The index of the chapter of the open book, book `serial`, whose
   entry's name is at name_offset in the file; -1 when none is (or book
   `serial` is not open) *)
#pub fn book_chapter_of (serial: int, name_offset: int): [found:int | found >= ~1] int found

(* Where chapter chapter_index of the open book, book `serial`, is in
   the book, by its
   entries' compressed sizes: the sizes of the chapters before it, its
   own, and all of theirs; @(0, 0, 0) when the chapters are unknown *)
#pub fn book_weights (serial: int, chapter_index: int): @([before:nat] int before, [own:nat] int own, [total:nat] int total)

(* Closes the book being imported, book `serial`, when its import fails *)
#pub fn book_abandon (serial: int): void

(* The serial of the open book: a stage of a load started on one book
   reads only while the same book is open *)
#pub fn book_serial(): int

(* The open book's size and the OPF's regions in it *)
#pub typedef book_meta =
  [file_size:pos][data_offset:nat][data_size:pos | data_offset + data_size <= file_size; data_size <= 268435456][name_offset:nat][name_len:pos | name_offset + name_len <= file_size; name_len < 65536]
  @(int file_size, int data_offset, int data_size, $Z.compression, int name_offset, int name_len)

(* The open book's size and regions, or none when no book is open *)
#pub fn book_meta_get(): $R.option(book_meta)

(* Stores the open book's file in IndexedDB under key, from the JS side:
   the promise resolves with whether it was stored (NotStored when no
   book is open) *)
#pub fn book_idb_put {key_loc:agz}{key_size:pos} (key: !$A.borrow(byte, key_loc, key_size), key_size: int key_size): $P.promise($IDB.stored, $P.Chained)

(* out[0, read_len) := bytes [offset, offset + read_len) of the open
   book, when it is book `serial` of file_size bytes; false, with out untouched, when another book is open *)
#pub fn book_read {file_size:pos}{offset,read_len:nat | offset + read_len <= file_size}{out_loc:agz}{out_owner:addr}{out_size:pos | read_len <= out_size}
  (serial: int, file_size: int file_size, offset: int offset, out: !$A.arrx(byte, out_loc, out_size, out_owner), read_len: int read_len): bool

(* A decompressed blob's bytes, at most 1 MiB *)
#pub datavtype blob_bytes =
  | {l:agz}{n:pos | n <= 1048576} BlobBytes of ($A.arr(byte, l, n), int n)
  | NoBlobBytes of ()

(* An event's bytes, read whole and freed: none when it has none, or
   they are over 1 MiB *)
#pub fn take_blob (payload: $EV.event_payload): blob_bytes

(* What a read of storage found, read whole (at most 1 MiB): its bytes;
   nothing stored there; or a read that failed. A failed read is never taken for an empty one:
   what is saved over it would lose what could not be read (#174). One
   too large for the reader's records (over 1 MiB) is unreadable too *)
#pub datavtype stored_bytes =
  | {l:agz}{n:pos | n <= 1048576} StoredBytes of ($A.arr(byte, l, n), int n)
  | NothingStored of ()
  | StoredUnreadable of ()

#pub fn lookup_bytes (found: $IDB.lookup): stored_bytes

(* The arena a piece of piece_size bytes at arena_loc came from: the
   current page's (lent out of the reader's window, see pages.bats), or
   an arena of its own when the page has no room for it *)
#pub datavtype piece_owner(piece_size:int, arena_loc:addr) =
  | {used:nat | used <= PAGE_BYTES}{page,pages:int | 0 <= page; page < pages}
    OwnerPage(piece_size, arena_loc) of ($A.arena(byte, arena_loc, PAGE_BYTES, used, 1), int page, int pages, int used)
  | OwnerOwn(piece_size, arena_loc) of ($A.arena(byte, arena_loc, piece_size, piece_size, 1))

(* piece_size bytes of the book's content (an entry's data, a
   decompressed OPF or chapter, an image), which can be larger than
   alloc's 1 MiB, held only while it is parsed: a piece of the current page's arena when it fits
   there, else the one piece of an arena of its own; freed with
   piece_free *)
#pub datavtype piece(piece_size:int) =
  | {arena_loc,piece_loc:agz} Piece(piece_size) of (piece_owner(piece_size, arena_loc), $A.arrx(byte, piece_loc, piece_size, arena_loc))
  | NoPiece(piece_size) of ()

(* A piece of piece_size bytes, or none when the memory cannot be had *)
#pub fn piece_new {piece_size:pos | piece_size <= 268435456} (piece_size: int piece_size): piece(piece_size)

#pub fn piece_free {arena_loc,piece_loc:agz}{piece_size:pos}
  (owner: piece_owner(piece_size, arena_loc), piece: $A.arrx(byte, piece_loc, piece_size, arena_loc)): void

(* Decompressed content, read whole into a piece *)
#pub datavtype content_bytes =
  | {arena_loc,piece_loc:agz}{content_size:pos} ContentBytes of (piece_owner(content_size, arena_loc), $A.arrx(byte, piece_loc, content_size, arena_loc), int content_size)
  | NoContentBytes of ()

(* What decompress resolves with (bridge's decompressed: the content
   as a blob, or DecompressFailed) *)
#pub vtypedef decompressed = $BD.decompressed

(* The content decompress resolved with, read whole and freed: none
   when decompression failed, the result is empty, or no piece can be
   had for it *)
#pub fn take_decompressed (inflated: decompressed): content_bytes

(* What a read of storage found, as content (in a piece): it, nothing
   stored there, or a read that failed (or no piece could be had) *)
#pub datavtype stored_content =
  | {arena_loc,piece_loc:agz}{content_size:pos} StoredContent of (piece_owner(content_size, arena_loc), $A.arrx(byte, piece_loc, content_size, arena_loc), int content_size)
  | NoStoredContent of ()
  | ContentUnreadable of ()

#pub fn lookup_content (found: $IDB.lookup): stored_content

(* How bridge decompresses a zip entry's data: a deflated entry is raw
   deflate, a stored one is as it is *)
#pub fn zip_compression (method: $Z.compression): $BD.compression

(* Decompresses data[0, data_len) as method says; the promise resolves
   with what came of it, for take_decompressed *)
#pub fn decompress {lb:agz}{n:pos}
  (data: !$A.borrow(byte, lb, n), data_len: int n, method: $BD.compression): $P.promise(decompressed, $P.Chained)

(* An entry of an archive of file_size bytes, read by ranges: its
   compressed bytes (in a piece), method, where they are
   [data_offset, data_offset + data_size) and where its name is
   [name_offset, name_offset + name_len), both proven inside the
   archive *)
#pub datavtype zip_got(file_size:int) =
  | {arena_loc,piece_loc:agz}{data_size:pos | data_size <= 268435456}{data_offset:nat | data_offset + data_size <= file_size}{name_offset:nat}{name_len:pos | name_offset + name_len <= file_size; name_len < 65536}
    ZipGot(file_size) of (piece_owner(data_size, arena_loc), $A.arrx(byte, piece_loc, data_size, arena_loc), int data_size, $Z.compression, int data_offset, int name_offset, int name_len)
  | ZipMissing(file_size) of ()

(* index_read on the open book, when it is book `serial` of file_size
   bytes; missing
   when another book is open *)
#pub fn book_zip_read {file_size:pos}{name_loc:agz}{name_size:pos}
  (serial: int, file_size: int file_size, name: !$A.borrow(byte, name_loc, name_size), name_size: int name_size): zip_got(file_size)

val _book = ref<open_book>(NoBook())

val _book_serial = ref<int>(0)

fun book_entries_free {file_size,directory_size:int}{count:nat} .<count>. (entries: book_entries(file_size, directory_size, count)): void =
  case+ entries of
  | ~BookEntriesNil() => ()
  | ~BookEntry(_, _, _, _, _, rest) => book_entries_free(rest)

fn book_index_free {file_size:int} (index: book_index(file_size)): void = let
  val+ ~BookIndex(directory, _, _, entries) = index
  val () = book_entries_free(entries)
in $A.free<byte>(directory) end

(* entries reversed onto reversed *)
fun book_entries_rev {file_size,directory_size:int}{count,reversed_count:nat} .<count>.
  (entries: book_entries(file_size, directory_size, count), reversed: book_entries(file_size, directory_size, reversed_count)): book_entries(file_size, directory_size, count + reversed_count) =
  case+ entries of
  | ~BookEntriesNil() => reversed
  | ~BookEntry(data_offset, data_size, method, name_offset, name_len, rest) => book_entries_rev(rest, BookEntry(data_offset, data_size, method, name_offset, name_len, reversed))

(* The entries of refs whose local header (read from book_file) is one
   and whose data is inside the file and fits a piece, onto found
   (newest first) *)
fun book_entries_of {file_size:pos}{directory_size:int}{count,found_count:nat} .<count>.
  (book_file: !$BF.infile(file_size), file_size: int file_size, refs: $Z.zip_refs(file_size, directory_size, count), found: book_entries(file_size, directory_size, found_count))
  : [total_count:nat] book_entries(file_size, directory_size, total_count) =
  case+ refs of
  | ~$Z.zip_refs_nil() => found
  | ~$Z.zip_refs_cons(header_offset, compressed_size, method, uncompressed_size, name_offset, name_len, rest) => let
      val header = $A.alloc<byte>(30)
      val () = $BF.file_read(book_file, header_offset, header, 30)
      val span = $Z.find_data_at(header, header_offset, compressed_size, method, uncompressed_size, file_size)
      val () = $A.free<byte>(header)
    in
      case+ span of
      | ~$R.none() => book_entries_of(book_file, file_size, rest, found)
      | ~$R.some(~$Z.zip_span_mk(data_offset, data_size, data_method, _)) =>
        if data_size <= 0 then book_entries_of(book_file, file_size, rest, found)
        else if data_size > 268435456 then book_entries_of(book_file, file_size, rest, found)
        else book_entries_of(book_file, file_size, rest, BookEntry(data_offset, data_size, data_method, name_offset, name_len, found))
    end

(* The file's index: its archive's end, central directory and
   every entry's local header, checked once; none when it is not an
   archive or its directory is over 1 MiB *)
fn book_index_make {file_size:pos} (book_file: !$BF.infile(file_size), file_size: int file_size): $R.option(book_index(file_size)) = let
  val tail_len = (if file_size < 65557 then file_size else 65557): [tail_len:pos | tail_len <= file_size; tail_len <= 65557] int tail_len
  val tail = $A.alloc<byte>(tail_len)
  val () = $BF.file_read(book_file, file_size - tail_len, tail, tail_len)
  val found = $Z.find_cd(tail, tail_len, file_size)
  val () = $A.free<byte>(tail)
in
  case+ found of
  | ~$R.none() => $R.none()
  | ~$R.some(end_record) => let
      val directory_size = $Z.cd_size(end_record)
      val directory_offset = $Z.cd_offset(end_record)
    in
      if directory_size > 1048576 then let
        val+ ~$Z.zip_cd_mk(_, _, _) = end_record
      in $R.none() end
      else let
        val directory = $A.alloc<byte>(directory_size)
        val () = $BF.file_read(book_file, directory_offset, directory, directory_size)
        val refs = $Z.cd_refs(directory, end_record, file_size)
        val+ ~$Z.zip_cd_mk(_, _, _) = end_record
      in
        case+ refs of
        | ~$R.none() => let
            val () = $A.free<byte>(directory)
          in $R.none() end
        | ~$R.some(entry_refs) => let
            val entries = book_entries_of(book_file, file_size, entry_refs, BookEntriesNil())
          in $R.some(BookIndex(directory, directory_size, directory_offset, book_entries_rev(entries, BookEntriesNil()))) end
      end
    end
end

(* An entry found by name: its data [data_offset, data_offset +
   data_size), method, and its name [name_offset, name_offset +
   name_len) in the file *)
datavtype book_hit(file_size:int) =
  | {data_offset:nat}{data_size:pos | data_offset + data_size <= file_size; data_size <= 268435456}{name_offset:nat}{name_len:pos | name_offset + name_len <= file_size; name_len < 65536}
    BookHit(file_size) of (int data_offset, int data_size, $Z.compression, int name_offset, int name_len)
  | BookMiss(file_size) of ()

(* The first of entries named name[0, name_size) in directory, whose
   names are at directory_offset in the file *)
fun book_find {file_size:int}{directory_loc:agz}{directory_size:pos}{directory_offset:nat | directory_offset + directory_size <= file_size}{count:nat}{name_loc:agz}{name_size:pos} .<count>.
  (directory: !$A.arr(byte, directory_loc, directory_size), directory_offset: int directory_offset, entries: !book_entries(file_size, directory_size, count),
   name: !$A.borrow(byte, name_loc, name_size), name_size: int name_size): book_hit(file_size) =
  case+ entries of
  | BookEntriesNil() => BookMiss()
  | @BookEntry(data_offset, data_size, method, name_offset, name_len, rest) =>
    if $Z.cd_name_eq(directory, name_offset, name_len, name, name_size) then let
      val hit = BookHit(data_offset, data_size, method, directory_offset + name_offset, name_len)
      prval () = fold@(entries)
    in hit end
    else let
      val hit = book_find(directory, directory_offset, rest, name, name_size)
      prval () = fold@(entries)
    in hit end

(* The entry named name[0, name_size) of book_file, found in its
   index, its data read into a piece; missing when there is none, or
   when no piece can be had for the data *)
fn index_read {file_size:pos}{name_loc:agz}{name_size:pos}
  (book_file: !$BF.infile(file_size), index: !book_index(file_size), file_size: int file_size, name: !$A.borrow(byte, name_loc, name_size), name_size: int name_size): zip_got(file_size) = let
  val+ @BookIndex(directory, _, directory_offset, entries) = index
  val hit = book_find(directory, directory_offset, entries, name, name_size)
  prval () = fold@(index)
in
  case+ hit of
  | ~BookMiss() => ZipMissing()
  | ~BookHit(data_offset, compressed_size, method, name_offset, name_len) =>
    (case+ piece_new(compressed_size) of
     | ~NoPiece() => ZipMissing()
     | ~Piece(owner, data) => let
         val () = $BF.file_read(book_file, data_offset, data, compressed_size)
       in ZipGot(owner, data, compressed_size, method, data_offset, name_offset, name_len) end)
end

fun book_chapters_free {file_size:int}{count:nat} .<count>. (chapters: book_chapters(file_size, count)): void =
  case+ chapters of
  | ~ChaptersNil() => ()
  | ~Chapter(_, _, _, _, _, _, _, _, rest) => book_chapters_free(rest)
  | ~ChapterMissing(rest) => book_chapters_free(rest)

fn book_spine_free {file_size:int} (spine: book_spine(file_size)): void =
  case+ spine of
  | ~Spine(chapters, _) => book_chapters_free(chapters)
  | ~NoSpine() => ()

(* Chapter chapter_index of chapters, of the book's chapter_count *)
fun book_chapter_at {file_size:pos}{remaining:nat}{chapter_index:nat}{chapter_count:nat} .<remaining>.
  (chapters: !book_chapters(file_size, remaining), file_size: int file_size, chapter_index: int chapter_index, chapter_count: int chapter_count): chapter_got =
  case+ chapters of
  | ChaptersNil() => ChapterNone(chapter_count)
  | @Chapter(data_offset, data_size, method, name_offset, name_len, dir_len, layout, _, rest) =>
    if chapter_index = 0 then let
      val got = ChapterGot(file_size, data_offset, data_size, method, name_offset, name_len, dir_len, layout, chapter_count)
      prval () = fold@(chapters)
    in got end
    else let
      val got = book_chapter_at(rest, file_size, chapter_index - 1, chapter_count)
      prval () = fold@(chapters)
    in got end
  | @ChapterMissing(rest) =>
    if chapter_index = 0 then let
      prval () = fold@(chapters)
    in ChapterNone(chapter_count) end
    else let
      val got = book_chapter_at(rest, file_size, chapter_index - 1, chapter_count)
      prval () = fold@(chapters)
    in got end

implement book_take() = let
  var book: open_book = NoBook()
  val () = ref_exch_elt<open_book>(_book, book)
in book end

implement book_put(book) = let
  var previous: open_book = book
  val () = ref_exch_elt<open_book>(_book, previous)
in
  case+ previous of
  | ~OpenBook(book_file, _, index, spine, _, _, _, _, _) => let
      val () = book_index_free(index)
      val () = book_spine_free(spine)
    in $BF.file_close(book_file) end
  | ~Importing(book_file, _, index) => let
      val () = book_index_free(index)
    in $BF.file_close(book_file) end
  | ~NoBook() => ()
end

implement book_serial() = !_book_serial

implement book_meta_get() = let
  val book = book_take()
in
  case+ book of
  | @OpenBook(_, file_size, _, _, data_offset, data_size, method, name_offset, name_len) => let
      val meta = @(file_size, data_offset, data_size, method, name_offset, name_len)
      prval () = fold@(book)
      val () = book_put(book)
    in $R.some(meta) end
  | _ => let val () = book_put(book) in $R.none() end
end

implement book_idb_put (key, key_size) = let
  val book = book_take()
in
  case+ book of
  | @OpenBook(book_file, _, _, _, _, _, _, _, _) => let
      val stored = $BF.file_idb_put(key, key_size, book_file)
      prval () = fold@(book)
      val () = book_put(book)
    in stored end
  | _ => let
      val () = book_put(book)
    in $P.ret<$IDB.stored>($IDB.NotStored()) end
end

implement book_read {file_size}{offset,read_len}{out_loc}{out_owner}{out_size} (serial, file_size, offset, out, read_len) = let
  val book = book_take()
in
  case+ book of
  | @OpenBook(book_file, open_size, _, _, _, _, _, _, _) =>
    if serial = !_book_serial then
      (if open_size = file_size then let
         val () = $BF.file_read(book_file, offset, out, read_len)
         prval () = fold@(book)
         val () = book_put(book)
       in true end
       else let prval () = fold@(book); val () = book_put(book) in false end)
    else let prval () = fold@(book); val () = book_put(book) in false end
  | @Importing(book_file, open_size, _) =>
    if serial = !_book_serial then
      (if open_size = file_size then let
         val () = $BF.file_read(book_file, offset, out, read_len)
         prval () = fold@(book)
         val () = book_put(book)
       in true end
       else let prval () = fold@(book); val () = book_put(book) in false end)
    else let prval () = fold@(book); val () = book_put(book) in false end
  | NoBook() => let val () = book_put(book) in false end
end

(* A blob's bytes, read whole and freed: none when it is empty or over
   1 MiB *)
fn _blob_bytes {n:nat} (blob: $BD.dblob(n)): blob_bytes = let
  val blob_len = $BD.blob_len(blob)
in
  if blob_len <= 0 then let val () = $BD.blob_free(blob) in NoBlobBytes() end
  else if blob_len > 1048576 then let val () = $BD.blob_free(blob) in NoBlobBytes() end
  else let
    val blob_data = $A.alloc<byte>(blob_len)
    val () = $BD.blob_read(blob, 0, blob_data, blob_len)
    val () = $BD.blob_free(blob)
  in BlobBytes(blob_data, blob_len) end
end

implement take_blob (payload) =
  case+ $EV.event_take(payload) of
  | ~$R.none() => NoBlobBytes()
  | ~$R.some(blob) => _blob_bytes(blob)

implement lookup_bytes (found) =
  case+ found of
  | ~$IDB.Found(blob) =>
    if $BD.blob_len(blob) <= 0 then let val () = $BD.blob_free(blob) in NothingStored() end
    else (case+ _blob_bytes(blob) of
      | ~BlobBytes(bytes, n) => StoredBytes(bytes, n)
      (* over 1 MiB: not one of the reader's records, and not to be
         saved over *)
      | ~NoBlobBytes() => StoredUnreadable())
  | ~$IDB.Absent() => NothingStored()
  | ~$IDB.Unreadable() => StoredUnreadable()

implement piece_new (piece_size) =
  case+ page_lend(piece_size) of
  | ~PageLent(arena, piece, page, pages, used) => Piece(OwnerPage(arena, page, pages, used), piece)
  | ~NoLend() =>
    (case+ $A.arena_create<byte>(piece_size) of
     | ~$A.arena_none() => NoPiece()
     | ~$A.arena_some(arena) => let
         val piece = $A.arena_alloc<byte>(arena, piece_size)
       in Piece(OwnerOwn(arena), piece) end)

implement piece_free (owner, piece) =
  case+ owner of
  | ~OwnerPage(arena, page, pages, used) => page_give_back(arena, piece, page, pages, used)
  | ~OwnerOwn(arena) => let
      val () = $A.arena_return<byte>(arena, piece)
    in $A.arena_destroy<byte>(arena) end

(* A blob's content, read whole into a piece and freed *)
fn _blob_content {n:nat} (blob: $BD.dblob(n)): content_bytes = let
  val content_size = $BD.blob_len(blob)
in
  if content_size <= 0 then let val () = $BD.blob_free(blob) in NoContentBytes() end
  else if content_size > 268435456 then let val () = $BD.blob_free(blob) in NoContentBytes() end
  else (case+ piece_new(content_size) of
    | ~NoPiece() => let val () = $BD.blob_free(blob) in NoContentBytes() end
    | ~Piece(owner, piece) => let
        val () = $BD.blob_read(blob, 0, piece, content_size)
        val () = $BD.blob_free(blob)
      in ContentBytes(owner, piece, content_size) end)
end

implement take_decompressed (inflated) =
  case+ inflated of
  | ~$BD.DecompressFailed() => NoContentBytes()
  | ~$BD.Decompressed(blob) => _blob_content(blob)

implement lookup_content (found) =
  case+ found of
  | ~$IDB.Found(blob) =>
    if $BD.blob_len(blob) <= 0 then let val () = $BD.blob_free(blob) in NoStoredContent() end
    else (case+ _blob_content(blob) of
      | ~ContentBytes(owner, piece, size) => StoredContent(owner, piece, size)
      (* no piece could be had for it: it could not be read *)
      | ~NoContentBytes() => ContentUnreadable())
  | ~$IDB.Absent() => NoStoredContent()
  | ~$IDB.Unreadable() => ContentUnreadable()

implement zip_compression (method) =
  case+ method of
  | $Z.Stored() => $BD.Uncompressed()
  | $Z.Deflated() => $BD.DeflateRaw()

implement decompress (data, data_len, method) =
  $BD.decompress(data, data_len, method)

implement book_begin {file_size} (book_file, file_size) = let
  val () = !_book_serial := !_book_serial + 1
  val () = (case+ book_index_make(book_file, file_size) of
    | ~$R.some(index) => book_put(Importing(book_file, file_size, index))
    | ~$R.none() => let
        val () = $BF.file_close(book_file)
      in book_put(NoBook()) end)
in !_book_serial end

implement book_zip_read {file_size}{name_loc}{name_size} (serial, file_size, name, name_size) = let
  val book = book_take()
in
  case+ book of
  | @OpenBook(book_file, open_size, index, _, _, _, _, _, _) =>
    if serial = !_book_serial then
      (if open_size = file_size then let
         val got = index_read(book_file, index, file_size, name, name_size)
         prval () = fold@(book)
         val () = book_put(book)
       in got end
       else let prval () = fold@(book); val () = book_put(book) in ZipMissing() end)
    else let prval () = fold@(book); val () = book_put(book) in ZipMissing() end
  | @Importing(book_file, open_size, index) =>
    if serial = !_book_serial then
      (if open_size = file_size then let
         val got = index_read(book_file, index, file_size, name, name_size)
         prval () = fold@(book)
         val () = book_put(book)
       in got end
       else let prval () = fold@(book); val () = book_put(book) in ZipMissing() end)
    else let prval () = fold@(book); val () = book_put(book) in ZipMissing() end
  | NoBook() => let val () = book_put(book) in ZipMissing() end
end

implement book_finish (serial, file_size, data_offset, data_size, method, name_offset, name_len) = let
  val book = book_take()
in
  case+ book of
  | ~Importing(book_file, open_size, index) =>
    if serial = !_book_serial then
      (if open_size = file_size then let
         val () = book_put(OpenBook(book_file, open_size, index, NoSpine(), data_offset, data_size, method, name_offset, name_len))
       in true end
       else let val () = book_put(Importing(book_file, open_size, index)) in false end)
    else let val () = book_put(Importing(book_file, open_size, index)) in false end
  | _ => let val () = book_put(book) in false end
end

implement book_find_entry {file_size}{name_loc}{name_size} (serial, file_size, name, name_size) = let
  val book = book_take()
in
  case+ book of
  | @OpenBook(_, open_size, index, _, _, _, _, _, _) =>
    if serial = !_book_serial then
      (if open_size = file_size then let
         val+ @BookIndex(directory, _, directory_offset, entries) = index
         val hit = book_find(directory, directory_offset, entries, name, name_size)
         prval () = fold@(index)
         prval () = fold@(book)
         val () = book_put(book)
       in
         case+ hit of
         | ~BookHit(data_offset, data_size, method, name_offset, name_len) => EntryHit(data_offset, data_size, method, name_offset, name_len)
         | ~BookMiss() => EntryMiss()
       end
       else let prval () = fold@(book); val () = book_put(book) in EntryMiss() end)
    else let prval () = fold@(book); val () = book_put(book) in EntryMiss() end
  | _ => let val () = book_put(book) in EntryMiss() end
end

implement book_spine_set {file_size}{chapter_count} (serial, file_size, chapters, chapter_count) = let
  val book = book_take()
in
  case+ book of
  | @OpenBook(_, open_size, _, spine, _, _, _, _, _) =>
    if serial = !_book_serial then
      (if open_size = file_size then
         (case+ spine of
          | NoSpine() => let
              val () = book_spine_free(spine)
              val () = spine := Spine(chapters, chapter_count)
              prval () = fold@(book)
            in book_put(book) end
          | Spine(_, _) => let
              prval () = fold@(book)
              val () = book_put(book)
            in book_chapters_free(chapters) end)
       else let
         prval () = fold@(book)
         val () = book_put(book)
       in book_chapters_free(chapters) end)
    else let
      prval () = fold@(book)
      val () = book_put(book)
    in book_chapters_free(chapters) end
  | _ => let
      val () = book_put(book)
    in book_chapters_free(chapters) end
end

implement book_chapter_get {chapter_index} (serial, chapter_index) = let
  val book = book_take()
in
  case+ book of
  | @OpenBook(_, open_size, _, spine, _, _, _, _, _) =>
    if serial = !_book_serial then let
      val got = (case+ spine of
        | @Spine(chapters, chapter_count) => let
            val got = book_chapter_at(chapters, open_size, chapter_index, chapter_count)
            prval () = fold@(spine)
          in got end
        | NoSpine() => ChaptersUnknown()): chapter_got
      prval () = fold@(book)
      val () = book_put(book)
    in got end
    else let prval () = fold@(book); val () = book_put(book) in ChaptersUnknown() end
  | _ => let val () = book_put(book) in ChaptersUnknown() end
end

(* The index, from chapter_index, of the first of chapters whose name
   is at name_offset *)
fun book_chapter_find {file_size:pos}{remaining:nat}{chapter_index:nat} .<remaining>.
  (chapters: !book_chapters(file_size, remaining), name_offset: int, chapter_index: int chapter_index): [found:int | found >= ~1] int found =
  case+ chapters of
  | ChaptersNil() => ~1
  | @Chapter(_, _, _, chapter_name_offset, _, _, _, _, rest) =>
    if chapter_name_offset = name_offset then let prval () = fold@(chapters) in chapter_index end
    else let
      val found = book_chapter_find(rest, name_offset, chapter_index + 1)
      prval () = fold@(chapters)
    in found end
  | @ChapterMissing(rest) => let
      val found = book_chapter_find(rest, name_offset, chapter_index + 1)
      prval () = fold@(chapters)
    in found end

implement book_chapter_of (serial, name_offset) = let
  val book = book_take()
in
  case+ book of
  | @OpenBook(_, _, _, spine, _, _, _, _, _) =>
    if serial = !_book_serial then let
      val found = (case+ spine of
        | @Spine(chapters, _) => let
            val found = book_chapter_find(chapters, name_offset, 0)
            prval () = fold@(spine)
          in found end
        | NoSpine() => ~1): [found:int | found >= ~1] int found
      prval () = fold@(book)
      val () = book_put(book)
    in found end
    else let prval () = fold@(book); val () = book_put(book) in ~1 end
  | _ => let val () = book_put(book) in ~1 end
end

(* The slot of a fixed page that asks for asked, after a page in
   previous *)
fn _slot_after (asked: page_spread, previous: page_slot, right_to_left: bool): page_slot =
  case+ asked of
  | SpreadSlotLeft() => SlotLeft()
  | SpreadSlotRight() => SlotRight()
  | SpreadSlotCenter() => SlotCentre()
  | SpreadSlotAny() => (case+ previous of
    | SlotLeft() => SlotRight()
    | SlotRight() => SlotLeft()
    | SlotCentre() => if right_to_left then SlotRight() else SlotLeft()
    | SlotNone() => if right_to_left then SlotLeft() else SlotRight())

(* The slot of the first of chapters, after a page in previous *)
fn book_slot_first {file_size:pos}{remaining:nat}
  (chapters: !book_chapters(file_size, remaining), previous: page_slot, right_to_left: bool): page_slot =
  case+ chapters of
  | ChaptersNil() => SlotNone()
  | @Chapter(_, _, _, _, _, _, layout, asked, _) => let
      val slot = (case+ layout of
        | PrePaginated() => _slot_after(asked, previous, right_to_left)
        | Reflowable() => SlotNone()): page_slot
      prval () = fold@(chapters)
    in slot end
  | ChapterMissing(_) => SlotNone()

(* The slots of the chapters before, at and after chapter_index of
   chapters (which follow a page in previous, before them) *)
fun book_slots_walk {file_size:pos}{remaining:nat} .<remaining>.
  (chapters: !book_chapters(file_size, remaining), chapter_index: int, previous: page_slot, right_to_left: bool): @(page_slot, page_slot, page_slot) =
  case+ chapters of
  | ChaptersNil() => @(SlotNone(), SlotNone(), SlotNone())
  | @Chapter(_, _, _, _, _, _, layout, asked, rest) => let
      val slot = (case+ layout of
        | PrePaginated() => _slot_after(asked, previous, right_to_left)
        | Reflowable() => SlotNone()): page_slot
      val slots = (if chapter_index = 0 then @(previous, slot, book_slot_first(rest, slot, right_to_left))
        else book_slots_walk(rest, chapter_index - 1, slot, right_to_left)): @(page_slot, page_slot, page_slot)
      prval () = fold@(chapters)
    in slots end
  | @ChapterMissing(rest) => let
      val slots = (if chapter_index = 0 then @(previous, SlotNone(), book_slot_first(rest, SlotNone(), right_to_left))
        else book_slots_walk(rest, chapter_index - 1, SlotNone(), right_to_left)): @(page_slot, page_slot, page_slot)
      prval () = fold@(chapters)
    in slots end

implement book_chapter_slots (serial, chapter_index, right_to_left) = let
  val book = book_take()
in
  case+ book of
  | @OpenBook(_, _, _, spine, _, _, _, _, _) =>
    if serial = !_book_serial then let
      val slots = (case+ spine of
        | @Spine(chapters, _) => let
            val slots = (if chapter_index < 0 then @(SlotNone(), SlotNone(), SlotNone())
              else book_slots_walk(chapters, chapter_index, SlotNone(), right_to_left)): @(page_slot, page_slot, page_slot)
            prval () = fold@(spine)
          in slots end
        | NoSpine() => @(SlotNone(), SlotNone(), SlotNone())): @(page_slot, page_slot, page_slot)
      prval () = fold@(book)
      val () = book_put(book)
    in slots end
    else let prval () = fold@(book); val () = book_put(book) in @(SlotNone(), SlotNone(), SlotNone()) end
  | _ => let val () = book_put(book) in @(SlotNone(), SlotNone(), SlotNone()) end
end

(* The sizes of chapters: of the chapters before chapter chapter_index,
   of that chapter, and of all of them, added to before, own and
   total *)
fun book_weigh {file_size:pos}{remaining:nat} .<remaining>.
  (chapters: !book_chapters(file_size, remaining), chapter_index: int, before: Nat, own: Nat, total: Nat): @(Nat, Nat, Nat) =
  case+ chapters of
  | ChaptersNil() => @(before, own, total)
  | @Chapter(_, data_size, _, _, _, _, _, _, rest) => let
      val weights = (if chapter_index > 0 then book_weigh(rest, chapter_index - 1, before + data_size, own, total + data_size)
        else if chapter_index = 0 then book_weigh(rest, chapter_index - 1, before, data_size, total + data_size)
        else book_weigh(rest, chapter_index - 1, before, own, total + data_size)): @(Nat, Nat, Nat)
      prval () = fold@(chapters)
    in weights end
  | @ChapterMissing(rest) => let
      val weights = book_weigh(rest, chapter_index - 1, before, own, total)
      prval () = fold@(chapters)
    in weights end

implement book_weights (serial, chapter_index) = let
  val book = book_take()
in
  case+ book of
  | @OpenBook(_, _, _, spine, _, _, _, _, _) =>
    if serial = !_book_serial then let
      val weights = (case+ spine of
        | @Spine(chapters, _) => let
            val weights = book_weigh(chapters, chapter_index, 0, 0, 0)
            prval () = fold@(spine)
          in weights end
        | NoSpine() => @(0, 0, 0)): @(Nat, Nat, Nat)
      prval () = fold@(book)
      val () = book_put(book)
    in weights end
    else let prval () = fold@(book); val () = book_put(book) in @(0, 0, 0) end
  | _ => let val () = book_put(book) in @(0, 0, 0) end
end

implement book_find_relative (serial, file_size, dir_name_offset, dir_len, data, n, href_offset, href_len) =
  if href_len <= 0 then EntryMiss()
  (* a path of 64 KiB or more names no zip entry: the book's data,
     checked here *)
  else if href_len >= 65536 then EntryMiss()
  else let
    val path_size = dir_len + href_len
    val path = $A.alloc<byte>(path_size)
    val _ = book_read(serial, file_size, dir_name_offset, path, dir_len)
    val () = $S.copy_from_borrow(data, href_offset, n, path, dir_len, path_size, href_len)
    val resolved_len = path_norm(path, path_size)
  in
    if resolved_len <= 0 then let val () = $A.free<byte>(path) in EntryMiss() end
    else let
      val exact = $A.alloc<byte>(resolved_len)
      val path = $S.copy_arr_region(path, 0, path_size, exact, resolved_len, resolved_len)
      val () = $A.free<byte>(path)
      val @(exact_frozen, exact_bytes) = $A.freeze<byte>(exact)
      val hit = book_find_entry(serial, file_size, exact_bytes, resolved_len)
      val () = release_bytes(exact_frozen, exact_bytes)
    in hit end
  end

implement book_abandon (serial) =
  if serial = !_book_serial then let
    val book = book_take()
  in
    case+ book of
    | ~Importing(book_file, _, index) => let
        val () = book_index_free(index)
      in $BF.file_close(book_file) end
    | _ => book_put(book)
  end
  else ()

(* The reader's font size in px: 8 to 48, the range the A- and A+
   buttons step through. *)
#pub typedef font_px = [px:int | 8 <= px; px <= 48] int px

#pub fun font_get(): font_px

#pub fun font_set(px: font_px): void

val _font = ref<font_px>(16)

implement font_get() = !_font

implement font_set(px) = !_font := px

(* Where the reader is: page `page` of the chapter's `pages` (at least
   one), in chapter `chapter` (counted from 1; 0 before one loads) of
   the book's `chapters`.
   A flat tuple, kept in its ref: a datatype's value is allocated on
   every change and never freed. *)
#pub typedef reading =
  [pages:pos][page:nat | page < pages][chapter,chapters:nat] @(int page, int pages, int chapter, int chapters)

#pub fun reading_get(): reading

#pub fun reading_set(place: reading): void

val _reading = ref<reading>(@(0, 1, 0, 0))

implement reading_get() = !_reading

implement reading_set(place) = !_reading := place

end (* #target wasm *)
