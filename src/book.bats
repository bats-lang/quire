(* book -- the open book: its file, and where its OPF is inside it *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/decompress as DC
#use wasm.bats-packages.dev/file-input as FI
#use zip as Z

staload "pages.sats"

(* A book's entries, found once when it is opened: an entry's data
   [d, d + s) in the n-byte file, its method m, and its name [no, no + nl)
   in the book's central directory of c bytes; k entries *)
#pub datavtype book_entries(n:int, c:int, k:int) =
  | BookEntriesNil(n, c, 0) of ()
  | {k:nat}{d:nat}{s:pos | d + s <= n; s <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= c; nl < 65536}
    BookEntry(n, c, k + 1) of (int d, int s, int m, int no, int nl, book_entries(n, c, k))

(* The n-byte file's central directory, at co, kept while the book is
   open (for its entries' names), and its entries: the archive checked
   once, when the book is opened (book_begin) *)
#pub datavtype book_index(n:int) =
  | {lc:agz}{c:pos | c <= 1048576}{co:nat | co + c <= n}{k:nat}
    BookIndex(n) of ($A.arr(byte, lc, c), int c, int co, book_entries(n, c, k))

(* The book's chapters, in spine order, each found once in its index
   (the first time a chapter is loaded, book_spine_set): a chapter's
   data [d, d + s) in the n-byte file, its method m, its name
   [no, no + nl) in the file and the length dl of that name's
   directory part; missing when its href is empty, over 1 MiB with the
   OPF's directory, or names no entry; k chapters *)
#pub datavtype book_chapters(n:int, k:int) =
  | ChaptersNil(n, 0) of ()
  | {k:nat}{d:nat}{s:pos | d + s <= n; s <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= n; nl < 65536}{dl:nat | dl <= nl}
    Chapter(n, k + 1) of (int d, int s, int m, int no, int nl, int dl, book_chapters(n, k))
  | {k:nat} ChapterMissing(n, k + 1) of (book_chapters(n, k))

(* The book's chapters once found, with their count *)
#pub datavtype book_spine(n:int) =
  | {k:nat} Spine(n) of (book_chapters(n, k), int k)
  | NoSpine(n) of ()

(* The open book's file and its size; its OPF's
   compressed data [opf_data, opf_data + opf_size) and compression
   method; the OPF's name [opf_name, opf_name + opf_name_len) in the
   central directory. The regions are proven inside the file, so the
   reader uses them with no check. The book owns its file (a linear
   handle, closed when the book is replaced), and its index. *)
#pub datavtype open_book =
  | {n:pos}{d:nat}{s:pos | d + s <= n; s <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= n; nl < 65536}
    OpenBook of ($FI.infile(n), int n, book_index(n), book_spine(n), int d, int s, int m, int no, int nl)
  | {n:pos} Importing of ($FI.infile(n), int n, book_index(n))
  | NoBook of ()

(* The open book, taken out of its cell, which is left with none: it
   is put back with book_put *)
#pub fn book_take(): open_book

(* Puts b in the book cell; the book that was there, if any, is closed *)
#pub fn book_put(b: open_book): void

(* Opens the n-byte file f as the book being imported, with a new
   serial, which it returns: its archive is checked here, once, into its
   index; when it is not an archive (or its central directory is over
   1 MiB) f is closed and no book is open, so every read with the serial
   finds nothing *)
#pub fn book_begin {n:pos} (f: $FI.infile(n), n: int n): int

(* The book being imported, book s of z bytes, opened with its OPF's
   regions; false when another book is open *)
#pub fn book_finish {z:pos}{d:nat}{sz:pos | d + sz <= z; sz <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= z; nl < 65536}
  (s: int, z: int z, d: int d, sz: int sz, m: int m, no: int no, nl: int nl): bool

(* An entry of the n-byte file found by name: its data [d, d + s),
   method m and name [no, no + nl) *)
#pub datavtype entry_hit(n:int) =
  | {d:nat}{s:pos | d + s <= n; s <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= n; nl < 65536}
    EntryHit(n) of (int d, int s, int m, int no, int nl)
  | EntryMiss(n) of ()

(* The entry named name[0, nb) in the index of the open book, when it is
   book s of z bytes; a miss when there is none or another book is open *)
#pub fn book_find_entry {z:pos}{lb:agz}{nb:pos}
  (s: int, z: int z, name: !$A.borrow(byte, lb, nb), nb: int nb): entry_hit(z)

(* Keeps chs, k chapters, as the chapters of the open book, when it is
   book s of z bytes and has none yet; else frees them *)
#pub fn book_spine_set {z:pos}{k:nat}
  (s: int, z: int z, chs: book_chapters(z, k), k: int k): void

(* Chapter i of the open book, book s *)
#pub datavtype chapter_got =
  | {n:pos}{d:nat}{sz:pos | d + sz <= n; sz <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= n; nl < 65536}{dl:nat | dl <= nl}{k:nat}
    ChapterGot of (int n, int d, int sz, int m, int no, int nl, int dl, int k)
  (* The book has k chapters, but not an i-th one that names an entry *)
  | {k:nat} ChapterNone of (int k)
  (* The book's chapters are not found yet (or book s is not open) *)
  | ChaptersUnknown of ()

#pub fn book_chapter_get {i:nat} (s: int, i: int i): chapter_got

(* Closes the book being imported, book s, when its import fails *)
#pub fn book_abandon (s: int): void

(* The serial of the open book: a stage of a load started on one book
   reads only while the same book is open *)
#pub fn book_serial(): int

(* The open book's size and the OPF's regions in it *)
#pub typedef book_meta =
  [n:pos][d:nat][s:pos | d + s <= n; s <= 268435456][m:int | m == 0 || m == 8][no:nat][nl:pos | no + nl <= n; nl < 65536]
  @(int n, int d, int s, int m, int no, int nl)

(* The open book's size and regions, or none when no book is open *)
#pub fn book_meta_get(): $R.option(book_meta)

(* Stores the open book's file in IndexedDB under key, from the JS side;
   nothing when no book is open *)
#pub fn book_idb_put {lk:agz}{nk:pos} (key: !$A.borrow(byte, lk, nk), nk: int nk): void

(* out[0, k) := bytes [o, o + k) of the open book, when it is book s of
   z bytes; false, with out untouched, when another book is open *)
#pub fn book_read {z:pos}{o,k:nat | o + k <= z}{l:agz}{ow:addr}{m:pos | k <= m}
  (s: int, z: int z, o: int o, out: !$A.arrx(byte, l, m, ow), k: int k): bool

(* A decompressed blob's bytes, at most 1 MiB *)
#pub datavtype blob_bytes =
  | {l:agz}{n:pos | n <= 1048576} BlobBytes of ($A.arr(byte, l, n), int n)
  | NoBlobBytes of ()

(* The blob a decompress promise resolved with, read whole and freed:
   none when decompression failed, or the result is empty or over 1 MiB
   (the book's data, checked here once) *)
#pub fn take_blob (handle: Int): blob_bytes

(* The arena a piece of n bytes at la came from: the current page's
   (lent out of the reader's window, see pages.bats), or an arena of its
   own when the page has no room for it *)
#pub datavtype piece_owner(n:int, la:addr) =
  | {u:nat | u <= PAGE_BYTES}{q,t:int | 0 <= q; q < t}
    OwnerPage(n, la) of ($A.arena(byte, la, PAGE_BYTES, u, 1), int q, int t, int u)
  | OwnerOwn(n, la) of ($A.arena(byte, la, n, n, 1))

(* n bytes of the book's content (an entry's data, a decompressed OPF or
   chapter, an image), which can be larger than alloc's 1 MiB, held only
   while it is parsed: a piece of the current page's arena when it fits
   there, else the one piece of an arena of its own; freed with
   piece_free *)
#pub datavtype piece(n:int) =
  | {la,l:agz} Piece(n) of (piece_owner(n, la), $A.arrx(byte, l, n, la))
  | NoPiece(n) of ()

(* A piece of n bytes, or none when the memory cannot be had *)
#pub fn piece_new {n:pos | n <= 268435456} (n: int n): piece(n)

#pub fn piece_free {la,l:agz}{n:pos}
  (ar: piece_owner(n, la), p: $A.arrx(byte, l, n, la)): void

(* Decompressed content, read whole into a piece *)
#pub datavtype content_bytes =
  | {la,l:agz}{n:pos} ContentBytes of (piece_owner(n, la), $A.arrx(byte, l, n, la), int n)
  | NoContentBytes of ()

(* The content a decompress promise resolved with, read whole and
   freed: none when decompression failed, the result is empty, or no
   piece can be had for it *)
#pub fn take_content (handle: Int): content_bytes

(* An entry of a z-byte archive, read by ranges: its compressed bytes
   (in a piece), method, where they are [d, d + s) and where its
   name is [no, no + nl), both proven inside the archive *)
#pub datavtype zip_got(z:int) =
  | {la,l:agz}{s:pos | s <= 268435456}{m:int | m == 0 || m == 8}{d:nat | d + s <= z}{no:nat}{nl:pos | no + nl <= z; nl < 65536}
    ZipGot(z) of (piece_owner(s, la), $A.arrx(byte, l, s, la), int s, int m, int d, int no, int nl)
  | ZipMissing(z) of ()

(* index_read on the open book, when it is book s of z bytes; missing
   when another book is open *)
#pub fn book_zip_read {z:pos}{lb:agz}{nb:pos}
  (s: int, z: int z, name: !$A.borrow(byte, lb, nb), nb: int nb): zip_got(z)

val _book = ref<open_book>(NoBook())

val _book_serial = ref<int>(0)

fun book_entries_free {n,c:int}{k:nat} .<k>. (es: book_entries(n, c, k)): void =
  case+ es of
  | ~BookEntriesNil() => ()
  | ~BookEntry(_, _, _, _, _, rest) => book_entries_free(rest)

fn book_index_free {n:int} (ix: book_index(n)): void = let
  val+ ~BookIndex(cd, _, _, es) = ix
  val () = book_entries_free(es)
in $A.free<byte>(cd) end

(* es reversed onto acc *)
fun book_entries_rev {n,c:int}{k,a:nat} .<k>.
  (es: book_entries(n, c, k), acc: book_entries(n, c, a)): book_entries(n, c, k + a) =
  case+ es of
  | ~BookEntriesNil() => acc
  | ~BookEntry(d, sz, m, no, nl, rest) => book_entries_rev(rest, BookEntry(d, sz, m, no, nl, acc))

(* The entries of rs whose local header (read from f) is one and whose
   data is inside the file and fits a piece, onto acc (newest first) *)
fun book_entries_of {n:pos}{c:int}{k,a:nat} .<k>.
  (f: !$FI.infile(n), n: int n, rs: $Z.zip_refs(n, c, k), acc: book_entries(n, c, a))
  : [j:nat] book_entries(n, c, j) =
  case+ rs of
  | ~$Z.zip_refs_nil() => acc
  | ~$Z.zip_refs_cons(h, cs, m, u, no, nl, rest) => let
      val hdr = $A.alloc<byte>(30)
      val () = $FI.file_read(f, h, hdr, 30)
      val sp = $Z.find_data_at(hdr, h, cs, m, u, n)
      val () = $A.free<byte>(hdr)
    in
      case+ sp of
      | ~$R.none() => book_entries_of(f, n, rest, acc)
      | ~$R.some(~$Z.zip_span_mk(d, dsz, dm, _)) =>
        if dsz <= 0 then book_entries_of(f, n, rest, acc)
        else if dsz > 268435456 then book_entries_of(f, n, rest, acc)
        else book_entries_of(f, n, rest, BookEntry(d, dsz, dm, no, nl, acc))
    end

(* The n-byte file's index: its archive's end, central directory and
   every entry's local header, checked once; none when it is not an
   archive or its directory is over 1 MiB *)
fn book_index_make {n:pos} (f: !$FI.infile(n), n: int n): $R.option(book_index(n)) = let
  val t = (if n < 65557 then n else 65557): [t:pos | t <= n; t <= 65557] int t
  val tail = $A.alloc<byte>(t)
  val () = $FI.file_read(f, n - t, tail, t)
  val found = $Z.find_cd(tail, t, n)
  val () = $A.free<byte>(tail)
in
  case+ found of
  | ~$R.none() => $R.none()
  | ~$R.some(dir) => let
      val c = $Z.cd_size(dir)
      val co = $Z.cd_offset(dir)
    in
      if c > 1048576 then let
        val+ ~$Z.zip_cd_mk(_, _, _) = dir
      in $R.none() end
      else let
        val cd = $A.alloc<byte>(c)
        val () = $FI.file_read(f, co, cd, c)
        val refs = $Z.cd_refs(cd, dir, n)
        val+ ~$Z.zip_cd_mk(_, _, _) = dir
      in
        case+ refs of
        | ~$R.none() => let
            val () = $A.free<byte>(cd)
          in $R.none() end
        | ~$R.some(rs) => let
            val es = book_entries_of(f, n, rs, BookEntriesNil())
          in $R.some(BookIndex(cd, c, co, book_entries_rev(es, BookEntriesNil()))) end
      end
    end
end

(* An entry found by name: its data [d, d + s), method m, and its name
   [no, no + nl) in the n-byte file *)
datavtype book_hit(n:int) =
  | {d:nat}{s:pos | d + s <= n; s <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= n; nl < 65536}
    BookHit(n) of (int d, int s, int m, int no, int nl)
  | BookMiss(n) of ()

(* The first of es named name[0, nb) in cd, whose names are at co in
   the file *)
fun book_find {n:int}{lc:agz}{c:pos}{co:nat | co + c <= n}{k:nat}{lb:agz}{nb:pos} .<k>.
  (cd: !$A.arr(byte, lc, c), co: int co, es: !book_entries(n, c, k),
   name: !$A.borrow(byte, lb, nb), nb: int nb): book_hit(n) =
  case+ es of
  | BookEntriesNil() => BookMiss()
  | @BookEntry(d, sz, m, no, nl, rest) =>
    if $Z.cd_name_eq(cd, no, nl, name, nb) then let
      val r = BookHit(d, sz, m, co + no, nl)
      prval () = fold@(es)
    in r end
    else let
      val r = book_find(cd, co, rest, name, nb)
      prval () = fold@(es)
    in r end

(* The entry named name[0, nb) of the z-byte file f, found in its
   index ix, its data read into a piece; missing when there is none, or
   when no piece can be had for the data *)
fn index_read {z:pos}{lb:agz}{nb:pos}
  (f: !$FI.infile(z), ix: !book_index(z), z: int z, name: !$A.borrow(byte, lb, nb), nb: int nb): zip_got(z) = let
  val+ @BookIndex(cd, _, co, es) = ix
  val hit = book_find(cd, co, es, name, nb)
  prval () = fold@(ix)
in
  case+ hit of
  | ~BookMiss() => ZipMissing()
  | ~BookHit(d, cs, m, no, nl) =>
    (case+ piece_new(cs) of
     | ~NoPiece() => ZipMissing()
     | ~Piece(ar, buf) => let
         val () = $FI.file_read(f, d, buf, cs)
       in ZipGot(ar, buf, cs, m, d, no, nl) end)
end

fun book_chapters_free {n:int}{k:nat} .<k>. (chs: book_chapters(n, k)): void =
  case+ chs of
  | ~ChaptersNil() => ()
  | ~Chapter(_, _, _, _, _, _, rest) => book_chapters_free(rest)
  | ~ChapterMissing(rest) => book_chapters_free(rest)

fn book_spine_free {n:int} (sp: book_spine(n)): void =
  case+ sp of
  | ~Spine(chs, _) => book_chapters_free(chs)
  | ~NoSpine() => ()

(* Chapter i of chs, of the book's k *)
fun book_chapter_at {n:pos}{j:nat}{i:nat}{k:nat} .<j>.
  (chs: !book_chapters(n, j), n: int n, i: int i, k: int k): chapter_got =
  case+ chs of
  | ChaptersNil() => ChapterNone(k)
  | @Chapter(d, sz, m, no, nl, dl, rest) =>
    if i = 0 then let
      val r = ChapterGot(n, d, sz, m, no, nl, dl, k)
      prval () = fold@(chs)
    in r end
    else let
      val r = book_chapter_at(rest, n, i - 1, k)
      prval () = fold@(chs)
    in r end
  | @ChapterMissing(rest) =>
    if i = 0 then let
      prval () = fold@(chs)
    in ChapterNone(k) end
    else let
      val r = book_chapter_at(rest, n, i - 1, k)
      prval () = fold@(chs)
    in r end

implement book_take() = let
  var b: open_book = NoBook()
  val () = ref_exch_elt<open_book>(_book, b)
in b end

implement book_put(b) = let
  var cur: open_book = b
  val () = ref_exch_elt<open_book>(_book, cur)
in
  case+ cur of
  | ~OpenBook(f, _, ix, sp, _, _, _, _, _) => let
      val () = book_index_free(ix)
      val () = book_spine_free(sp)
    in $FI.close(f) end
  | ~Importing(f, _, ix) => let
      val () = book_index_free(ix)
    in $FI.close(f) end
  | ~NoBook() => ()
end

implement book_serial() = !_book_serial

implement book_meta_get() = let
  val b = book_take()
in
  case+ b of
  | @OpenBook(_, n, _, _, d, sz, m, no, nl) => let
      val r = @(n, d, sz, m, no, nl)
      prval () = fold@(b)
      val () = book_put(b)
    in $R.some(r) end
  | _ => let val () = book_put(b) in $R.none() end
end

implement book_idb_put (key, nk) = let
  val b = book_take()
in
  case+ b of
  | @OpenBook(f, _, _, _, _, _, _, _, _) => let
      val p = $FI.idb_put(key, nk, f)
      val () = $P.discard<Int>(p)
      prval () = fold@(b)
    in book_put(b) end
  | _ => book_put(b)
end

implement book_read {z}{o,k}{l}{ow}{m} (s, z, o, out, k) = let
  val b = book_take()
in
  case+ b of
  | @OpenBook(f, n, _, _, _, _, _, _, _) =>
    if s = !_book_serial then
      (if n = z then let
         val () = $FI.file_read(f, o, out, k)
         prval () = fold@(b)
         val () = book_put(b)
       in true end
       else let prval () = fold@(b); val () = book_put(b) in false end)
    else let prval () = fold@(b); val () = book_put(b) in false end
  | @Importing(f, n, _) =>
    if s = !_book_serial then
      (if n = z then let
         val () = $FI.file_read(f, o, out, k)
         prval () = fold@(b)
         val () = book_put(b)
       in true end
       else let prval () = fold@(b); val () = book_put(b) in false end)
    else let prval () = fold@(b); val () = book_put(b) in false end
  | NoBook() => let val () = book_put(b) in false end
end

implement take_blob (handle) =
  case+ $DC.blob_claim(handle) of
  | ~$R.none() => NoBlobBytes()
  | ~$R.some(b) => let
      val n = $DC.blob_len(b)
    in
      if n <= 0 then let val () = $DC.blob_free(b) in NoBlobBytes() end
      else if n > 1048576 then let val () = $DC.blob_free(b) in NoBlobBytes() end
      else let
        val buf = $A.alloc<byte>(n)
        val () = $DC.blob_read(b, 0, buf, n)
        val () = $DC.blob_free(b)
      in BlobBytes(buf, n) end
    end

implement piece_new (n) =
  case+ page_lend(n) of
  | ~PageLent(ar, p, q, t, u) => Piece(OwnerPage(ar, q, t, u), p)
  | ~NoLend() =>
    (case+ $A.arena_create<byte>(n) of
     | ~$A.arena_none() => NoPiece()
     | ~$A.arena_some(ar) => let
         val p = $A.arena_alloc<byte>(ar, n)
       in Piece(OwnerOwn(ar), p) end)

implement piece_free (owner, p) =
  case+ owner of
  | ~OwnerPage(ar, q, t, u) => page_give_back(ar, p, q, t, u)
  | ~OwnerOwn(ar) => let
      val () = $A.arena_return<byte>(ar, p)
    in $A.arena_destroy<byte>(ar) end

implement take_content (handle) =
  case+ $DC.blob_claim(handle) of
  | ~$R.none() => NoContentBytes()
  | ~$R.some(b) => let
      val n = $DC.blob_len(b)
    in
      if n <= 0 then let val () = $DC.blob_free(b) in NoContentBytes() end
      else if n > 268435456 then let val () = $DC.blob_free(b) in NoContentBytes() end
      else (case+ piece_new(n) of
        | ~NoPiece() => let val () = $DC.blob_free(b) in NoContentBytes() end
        | ~Piece(ar, p) => let
            val () = $DC.blob_read(b, 0, p, n)
            val () = $DC.blob_free(b)
          in ContentBytes(ar, p, n) end)
    end

implement book_begin {n} (f, n) = let
  val () = !_book_serial := !_book_serial + 1
  val () = (case+ book_index_make(f, n) of
    | ~$R.some(ix) => book_put(Importing(f, n, ix))
    | ~$R.none() => let
        val () = $FI.close(f)
      in book_put(NoBook()) end)
in !_book_serial end

implement book_zip_read {z}{lb}{nb} (s, z, name, nb) = let
  val b = book_take()
in
  case+ b of
  | @OpenBook(f, n, ix, _, _, _, _, _, _) =>
    if s = !_book_serial then
      (if n = z then let
         val r = index_read(f, ix, z, name, nb)
         prval () = fold@(b)
         val () = book_put(b)
       in r end
       else let prval () = fold@(b); val () = book_put(b) in ZipMissing() end)
    else let prval () = fold@(b); val () = book_put(b) in ZipMissing() end
  | @Importing(f, n, ix) =>
    if s = !_book_serial then
      (if n = z then let
         val r = index_read(f, ix, z, name, nb)
         prval () = fold@(b)
         val () = book_put(b)
       in r end
       else let prval () = fold@(b); val () = book_put(b) in ZipMissing() end)
    else let prval () = fold@(b); val () = book_put(b) in ZipMissing() end
  | NoBook() => let val () = book_put(b) in ZipMissing() end
end

implement book_finish (s, z, d, sz, m, no, nl) = let
  val b = book_take()
in
  case+ b of
  | ~Importing(f, n, ix) =>
    if s = !_book_serial then
      (if n = z then let
         val () = book_put(OpenBook(f, n, ix, NoSpine(), d, sz, m, no, nl))
       in true end
       else let val () = book_put(Importing(f, n, ix)) in false end)
    else let val () = book_put(Importing(f, n, ix)) in false end
  | _ => let val () = book_put(b) in false end
end

implement book_find_entry {z}{lb}{nb} (s, z, name, nb) = let
  val b = book_take()
in
  case+ b of
  | @OpenBook(_, n, ix, _, _, _, _, _, _) =>
    if s = !_book_serial then
      (if n = z then let
         val+ @BookIndex(cd, _, co, es) = ix
         val hit = book_find(cd, co, es, name, nb)
         prval () = fold@(ix)
         prval () = fold@(b)
         val () = book_put(b)
       in
         case+ hit of
         | ~BookHit(d, sz, m, no, nl) => EntryHit(d, sz, m, no, nl)
         | ~BookMiss() => EntryMiss()
       end
       else let prval () = fold@(b); val () = book_put(b) in EntryMiss() end)
    else let prval () = fold@(b); val () = book_put(b) in EntryMiss() end
  | _ => let val () = book_put(b) in EntryMiss() end
end

implement book_spine_set {z}{k} (s, z, chs, k) = let
  val b = book_take()
in
  case+ b of
  | @OpenBook(_, n, _, sp, _, _, _, _, _) =>
    if s = !_book_serial then
      (if n = z then
         (case+ sp of
          | NoSpine() => let
              val () = book_spine_free(sp)
              val () = sp := Spine(chs, k)
              prval () = fold@(b)
            in book_put(b) end
          | Spine(_, _) => let
              prval () = fold@(b)
              val () = book_put(b)
            in book_chapters_free(chs) end)
       else let
         prval () = fold@(b)
         val () = book_put(b)
       in book_chapters_free(chs) end)
    else let
      prval () = fold@(b)
      val () = book_put(b)
    in book_chapters_free(chs) end
  | _ => let
      val () = book_put(b)
    in book_chapters_free(chs) end
end

implement book_chapter_get {i} (s, i) = let
  val b = book_take()
in
  case+ b of
  | @OpenBook(_, n, _, sp, _, _, _, _, _) =>
    if s = !_book_serial then let
      val r = (case+ sp of
        | @Spine(chs, k) => let
            val r = book_chapter_at(chs, n, i, k)
            prval () = fold@(sp)
          in r end
        | NoSpine() => ChaptersUnknown()): chapter_got
      prval () = fold@(b)
      val () = book_put(b)
    in r end
    else let prval () = fold@(b); val () = book_put(b) in ChaptersUnknown() end
  | _ => let val () = book_put(b) in ChaptersUnknown() end
end

implement book_abandon (s) =
  if s = !_book_serial then let
    val b = book_take()
  in
    case+ b of
    | ~Importing(f, _, ix) => let
        val () = book_index_free(ix)
      in $FI.close(f) end
    | _ => book_put(b)
  end
  else ()

(* The reader's font size in px: 8 to 48, the range the A- and A+
   buttons step through. *)
#pub typedef font_px = [s:int | 8 <= s; s <= 48] int s

#pub fun font_get(): font_px

#pub fun font_set(s: font_px): void

val _font = ref<font_px>(16)

implement font_get() = !_font

implement font_set(s) = !_font := s

(* Where the reader is: page p of the chapter's t pages (at least one),
   in chapter c (counted from 1; 0 before one loads) of the book's tc.
   A flat tuple, kept in its ref: a datatype's value is allocated on
   every change and never freed. *)
#pub typedef reading =
  [t:pos][p:nat | p < t][c,tc:nat] @(int p, int t, int c, int tc)

#pub fun reading_get(): reading

#pub fun reading_set(r: reading): void

val _reading = ref<reading>(@(0, 1, 0, 0))

implement reading_get() = !_reading

implement reading_set(r) = !_reading := r

end (* #target wasm *)
