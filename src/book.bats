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

(* The open book's file and its size; its OPF's
   compressed data [opf_data, opf_data + opf_size) and compression
   method; the OPF's name [opf_name, opf_name + opf_name_len) in the
   central directory. The regions are proven inside the file, so the
   reader uses them with no check. The book owns its file (a linear
   handle, closed when the book is replaced). *)
#pub datavtype open_book =
  | {n:pos}{d:nat}{s:pos | d + s <= n; s <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= n; nl < 65536}
    OpenBook of ($FI.infile(n), int n, int d, int s, int m, int no, int nl)
  | {n:pos} Importing of ($FI.infile(n), int n)
  | NoBook of ()

(* The open book, taken out of its cell, which is left with none: it
   is put back with book_put *)
#pub fn book_take(): open_book

(* Puts b in the book cell; the book that was there, if any, is closed *)
#pub fn book_put(b: open_book): void

(* Opens b as the book: book_put, with a new serial *)
#pub fun book_set(b: open_book): void

(* The book being imported, book s of z bytes, opened with its OPF's
   regions; false when another book is open *)
#pub fn book_finish {z:pos}{d:nat}{sz:pos | d + sz <= z; sz <= 268435456}{m:int | m == 0 || m == 8}{no:nat}{nl:pos | no + nl <= z; nl < 65536}
  (s: int, z: int z, d: int d, sz: int sz, m: int m, no: int no, nl: int nl): bool

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

(* The entry named name[0, nb) of the z-byte file f, reading only the
   archive's end, its central directory, the entry's local header and
   its data; missing when there is none, when the directory is over
   1 MiB, or when no piece can be had for the data (the book's data,
   checked here once) *)
#pub fn zip_read {z:pos}{lb:agz}{nb:pos}
  (f: !$FI.infile(z), z: int z, name: !$A.borrow(byte, lb, nb), nb: int nb): zip_got(z)

(* zip_read on the open book, when it is book s of z bytes; missing
   when another book is open *)
#pub fn book_zip_read {z:pos}{lb:agz}{nb:pos}
  (s: int, z: int z, name: !$A.borrow(byte, lb, nb), nb: int nb): zip_got(z)

val _book = ref<open_book>(NoBook())

val _book_serial = ref<int>(0)

implement book_take() = let
  var b: open_book = NoBook()
  val () = ref_exch_elt<open_book>(_book, b)
in b end

implement book_put(b) = let
  var cur: open_book = b
  val () = ref_exch_elt<open_book>(_book, cur)
in
  case+ cur of
  | ~OpenBook(f, _, _, _, _, _, _) => $FI.close(f)
  | ~Importing(f, _) => $FI.close(f)
  | ~NoBook() => ()
end

implement book_serial() = !_book_serial

implement book_meta_get() = let
  val b = book_take()
in
  case+ b of
  | @OpenBook(_, n, d, sz, m, no, nl) => let
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
  | @OpenBook(f, _, _, _, _, _, _) => let
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
  | @OpenBook(f, n, _, _, _, _, _) =>
    if s = !_book_serial then
      (if n = z then let
         val () = $FI.file_read(f, o, out, k)
         prval () = fold@(b)
         val () = book_put(b)
       in true end
       else let prval () = fold@(b); val () = book_put(b) in false end)
    else let prval () = fold@(b); val () = book_put(b) in false end
  | @Importing(f, n) =>
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

implement book_set(b) = let
  val () = !_book_serial := !_book_serial + 1
in book_put(b) end

implement book_zip_read {z}{lb}{nb} (s, z, name, nb) = let
  val b = book_take()
in
  case+ b of
  | @OpenBook(f, n, _, _, _, _, _) =>
    if s = !_book_serial then
      (if n = z then let
         val r = zip_read(f, z, name, nb)
         prval () = fold@(b)
         val () = book_put(b)
       in r end
       else let prval () = fold@(b); val () = book_put(b) in ZipMissing() end)
    else let prval () = fold@(b); val () = book_put(b) in ZipMissing() end
  | @Importing(f, n) =>
    if s = !_book_serial then
      (if n = z then let
         val r = zip_read(f, z, name, nb)
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
  | ~Importing(f, n) =>
    if s = !_book_serial then
      (if n = z then let
         val () = book_put(OpenBook(f, n, d, sz, m, no, nl))
       in true end
       else let val () = book_put(Importing(f, n)) in false end)
    else let val () = book_put(Importing(f, n)) in false end
  | _ => let val () = book_put(b) in false end
end

implement book_abandon (s) =
  if s = !_book_serial then let
    val b = book_take()
  in
    case+ b of
    | ~Importing(f, _) => $FI.close(f)
    | _ => book_put(b)
  end
  else ()

implement zip_read {z}{lb}{nb} (f, z, name, nb) = let
  val t = (if z < 65557 then z else 65557): [t:pos | t <= z; t <= 65557] int t
  val tail = $A.alloc<byte>(t)
  val () = $FI.file_read(f, z - t, tail, t)
  val found = $Z.find_cd(tail, t, z)
  val () = $A.free<byte>(tail)
in
  case+ found of
  | ~$R.none() => ZipMissing()
  | ~$R.some(dir) => let
      val s = $Z.cd_size(dir)
      val c = $Z.cd_offset(dir)
    in
      if s > 1048576 then let
        val+ ~$Z.zip_cd_mk(_, _, _) = dir
      in ZipMissing() end
      else let
        val cd = $A.alloc<byte>(s)
        val () = $FI.file_read(f, c, cd, s)
        val r = $Z.find_ref(cd, dir, z, name, nb)
        val () = $A.free<byte>(cd)
        val+ ~$Z.zip_cd_mk(_, _, _) = dir
      in
        case+ r of
        | ~$R.none() => ZipMissing()
        | ~$R.some(e) => let
            val hdr = $A.alloc<byte>(30)
            val () = $FI.file_read(f, $Z.ref_header(e), hdr, 30)
            val sp = $Z.find_data(hdr, e, z)
            val () = $A.free<byte>(hdr)
            val+ ~$Z.zip_ref_mk(_, _, _, _, no, nl) = e
          in
            case+ sp of
            | ~$R.none() => ZipMissing()
            | ~$R.some(~$Z.zip_span_mk(d, cs, m, _)) =>
              if cs <= 0 then ZipMissing()
              else if cs > 268435456 then ZipMissing()
              else (case+ piece_new(cs) of
                | ~NoPiece() => ZipMissing()
                | ~Piece(ar, buf) => let
                    val () = $FI.file_read(f, d, buf, cs)
                  in ZipGot(ar, buf, cs, m, d, no, nl) end)
          end
      end
    end
end

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
