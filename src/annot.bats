(* annot -- the open book's bookmarks and highlights, with their notes:
   kept in order of place in the book, stored under the book's "a" key,
   shown in the reader, listed and exported as Markdown *)

(* A place is a content node's number (the reader numbers a chapter's
   nodes the same way each time it is shown) and an offset in its
   text. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S
#use wasm.bats-packages.dev/decompress as DC

staload "book.sats"
staload "ui.sats"
staload "library.sats"
staload "toc.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"
staload BL = "wasm.bats-packages.dev/bridge/src/blob.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* A quote's and a note's most bytes; the most annotations a book has;
   the bytes one takes when stored, at most *)
#define TXT 400
#define NOTE 2000
#define AMAX 400
#define SLOT 2440

(* Each annotation: its kind (0 a bookmark, 1 a highlight), chapter, the
   node and offset it starts at and those it ends at, the page it was
   made on, when (epoch minutes), its text t[0, tl) (a highlight's
   quote, a bookmark's first words) and its note n[0, nl) *)
datavtype ann(int) =
  | ann_nil(0) of ()
  | {k:nat}{l1,l2:agz}{tl:nat | tl <= TXT}{nl:nat | nl <= NOTE}
    ann_cons(k + 1) of (Int, Int, Int, Int, Int, Int, Int, Int,
      $A.arr(byte, l1, tl + 1), int tl, $A.arr(byte, l2, nl + 1), int nl, ann(k))

fun ann_free {k:nat} .<k>. (xs: ann(k)): void =
  case+ xs of
  | ~ann_nil() => ()
  | ~ann_cons(_, _, _, _, _, _, _, _, t, _, n, _, rest) => let
      val () = $A.free<byte>(t)
      val () = $A.free<byte>(n)
    in ann_free(rest) end

datavtype ann_cell =
  | {k:nat | k <= AMAX} AnnCell of (ann(k), int k)

val _cell = ref<ann_cell>(AnnCell(ann_nil(), 0))
(* The book the annotations are of *)
val _h1 = ref<int>(0)
val _h2 = ref<int>(0)

fn _take (): ann_cell = let
  var c: ann_cell = AnnCell(ann_nil(), 0)
  val () = ref_exch_elt<ann_cell>(_cell, c)
in c end

fn _put (c: ann_cell): void = let
  var cur: ann_cell = c
  val () = ref_exch_elt<ann_cell>(_cell, cur)
  val+ ~AnnCell(xs, _) = cur
in ann_free(xs) end

(* dst[j, k) := src[j, k) *)
fun _dup {ls,ld:agz}{ns,nd:pos}{k:nat | k <= ns; k <= nd}{j:nat | j <= k} .<k - j>.
  (src: !$A.arr(byte, ls, ns), dst: !$A.arr(byte, ld, nd), k: int k, j: int j): void =
  if j >= k then ()
  else let
    val () = $A.set<byte>(dst, j, $A.get<byte>(src, j))
  in _dup(src, dst, k, j + 1) end

(* A copy of a[0, k), in k + 1 bytes *)
fn _copy {l:agz}{n:pos}{k:nat | k < n; k < 1048576} (a: !$A.arr(byte, l, n), k: int k): [lc:agz] $A.arr(byte, lc, k + 1) = let
  val b = $A.alloc<byte>(k + 1)
  val () = _dup(a, b, k, 0)
in b end

(* ============================================================
   Order: by chapter, node, offset
   ============================================================ *)

fn _before (c1: int, n1: int, o1: int, c2: int, n2: int, o2: int): bool =
  if c1 <> c2 then c1 < c2
  else if n1 <> n2 then n1 < n2
  else o1 < o2

(* xs with the annotation added in its place *)
fun _insert {k:nat}{l1,l2:agz}{tl:nat | tl <= TXT}{nl:nat | nl <= NOTE} .<k>.
  (kd: Int, ch: Int, sn: Int, so: Int, en: Int, eo: Int, pg: Int, tm: Int,
   t: $A.arr(byte, l1, tl + 1), tl: int tl, n: $A.arr(byte, l2, nl + 1), nl: int nl,
   xs: ann(k)): ann(k + 1) =
  case+ xs of
  | ~ann_nil() => ann_cons(kd, ch, sn, so, en, eo, pg, tm, t, tl, n, nl, ann_nil())
  | ~ann_cons(kd2, ch2, sn2, so2, en2, eo2, pg2, tm2, t2, tl2, n2, nl2, rest) =>
    if _before(ch, sn, so, ch2, sn2, so2) then
      ann_cons(kd, ch, sn, so, en, eo, pg, tm, t, tl, n, nl,
        ann_cons(kd2, ch2, sn2, so2, en2, eo2, pg2, tm2, t2, tl2, n2, nl2, rest))
    else
      ann_cons(kd2, ch2, sn2, so2, en2, eo2, pg2, tm2, t2, tl2, n2, nl2,
        _insert(kd, ch, sn, so, en, eo, pg, tm, t, tl, n, nl, rest))

(* ============================================================
   Storage: the book's key 'a' and its id
   ============================================================ *)

(* "QA1\n", then each annotation: its eight numbers (i32), its text
   (u16 length, bytes) and its note (u16 length, bytes): at most SLOT
   bytes *)

fun _put_bytes {ls,l:agz}{la:addr}{ns:pos}{m:nat | m <= ns}{n:nat}{p:nat | p + m <= n}{j:nat | j <= m} .<m - j>.
  (src: !$A.arr(byte, ls, ns), m: int m, out: !$A.arrx(byte, l, n, la), p: int p, j: int j): void =
  if j >= m then ()
  else let
    val () = $A.write_byte(out, p + j, $AR.low_byte(byte2int0($A.get<byte>(src, j))))
  in _put_bytes(src, m, out, p, j + 1) end

fun _ser {l:agz}{la:addr}{n:int}{j:nat}{p:nat | p + SLOT * j <= n} .<j>.
  (out: !$A.arrx(byte, l, n, la), p: int p, xs: !ann(j)): [q:nat | q <= n] int q =
  case+ xs of
  | ann_nil() => p
  | @ann_cons(kd, ch, sn, so, en, eo, pg, tm, t, tl, nt, nl, rest) => let
      val () = $A.write_i32(out, p, kd)
      val () = $A.write_i32(out, p + 4, ch)
      val () = $A.write_i32(out, p + 8, sn)
      val () = $A.write_i32(out, p + 12, so)
      val () = $A.write_i32(out, p + 16, en)
      val () = $A.write_i32(out, p + 20, eo)
      val () = $A.write_i32(out, p + 24, pg)
      val () = $A.write_i32(out, p + 28, tm)
      val () = $A.write_u16le(out, p + 32, tl)
      val () = _put_bytes(t, tl, out, p + 34, 0)
      val () = $A.write_u16le(out, p + 34 + tl, nl)
      val () = _put_bytes(nt, nl, out, p + 36 + tl, 0)
      val q = _ser(out, p + 36 + tl + nl, rest)
      prval () = fold@(xs)
    in q end

fn _key (): [l:agz] $A.arr(byte, l, 15) = lib_key(97, !_h1, !_h2)

fn _save (): void = let
  val c = _take()
  val+ @AnnCell(xs, k) = c
  val n = 4 + SLOT * k
in
  case+ piece_new(n) of
  | ~NoPiece() => let prval () = fold@(c) in _put(c) end
  | ~Piece(ow, out) => let
      val () = $A.write_byte(out, 0, 81) (* Q *)
      val () = $A.write_byte(out, 1, 65) (* A *)
      val () = $A.write_byte(out, 2, 49) (* 1 *)
      val () = $A.write_byte(out, 3, 10)
      val m = _ser(out, 4, xs)
      prval () = fold@(c)
      val () = _put(c)
      val @(f, b) = $A.freeze<byte>(out)
      val @(used, rest) = $A.borrow_split<byte>(f, b, m)
      val @(kf, kb) = $A.freeze<byte>(_key())
      val () = $P.discard<Int>($IDB.idb_put(kb, 15, used, m))
      val () = $A.drop<byte>(kf, kb)
      val () = $A.free<byte>($A.thaw<byte>(kf))
      val b = $A.borrow_join<byte>(f, used, rest)
      val () = $A.drop<byte>(f, b)
    in piece_free(ow, $A.thaw<byte>(f)) end
end

(* The little-endian numbers at buf[p] *)
fn _i32 {l:agz}{la:addr}{n:nat}{p:nat | p + 4 <= n}
  (buf: !$A.arrx(byte, l, n, la), p: int p): Int = let
  val b0 = $AR.low_byte(byte2int0($A.get<byte>(buf, p)))
  val b1 = $AR.low_byte(byte2int0($A.get<byte>(buf, p + 1)))
  val b2 = $AR.low_byte(byte2int0($A.get<byte>(buf, p + 2)))
  val b3 = $AR.low_byte(byte2int0($A.get<byte>(buf, p + 3)))
  val hi = (if b3 < 128 then b3 else b3 - 256): [h:int | ~128 <= h; h < 128] int h
in b0 + b1 * 256 + b2 * 65536 + hi * 16777216 end

fn _u16 {l:agz}{la:addr}{n:nat}{p:nat | p + 2 <= n}
  (buf: !$A.arrx(byte, l, n, la), p: int p): [v:nat | v < 65536] int v = let
  val b0 = $AR.low_byte(byte2int0($A.get<byte>(buf, p)))
  val b1 = $AR.low_byte(byte2int0($A.get<byte>(buf, p + 1)))
in b0 + b1 * 256 end

(* out[j, m) := buf[p + j, p + m) *)
fun _bytes_of {l:agz}{la:addr}{n:nat}{p,m:nat | p + m <= n}{lo:agz}{no:pos | m <= no}{j:nat | j <= m} .<m - j>.
  (buf: !$A.arrx(byte, l, n, la), p: int p, m: int m, out: !$A.arr(byte, lo, no), j: int j): void =
  if j >= m then ()
  else let
    val () = $A.set<byte>(out, j, $A.get<byte>(buf, p + j))
  in _bytes_of(buf, p, m, out, j + 1) end

(* The annotations stored in buf[p, n), onto acc: read as they were
   stored (the book's data, checked here once) *)
fun _parse {l:agz}{la:addr}{n:nat}{p:nat | p <= n}{a:nat | a <= AMAX} .<n - p>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, acc: ann(a), a: int a)
  : [k:nat | k <= AMAX] @(ann(k), int k) =
  if a >= AMAX then @(acc, a)
  else if p + 36 > n then @(acc, a)
  else let
    val tl = _u16(buf, p + 32)
  in
    if tl > TXT then @(acc, a)
    else if p + 36 + tl > n then @(acc, a)
    else let
      val nl = _u16(buf, p + 34 + tl)
    in
      if nl > NOTE then @(acc, a)
      else if p + 36 + tl + nl > n then @(acc, a)
      else let
        val t = $A.alloc<byte>(tl + 1)
        val () = _bytes_of(buf, p + 34, tl, t, 0)
        val nt = $A.alloc<byte>(nl + 1)
        val () = _bytes_of(buf, p + 36 + tl, nl, nt, 0)
        val xs = _insert(_i32(buf, p), _i32(buf, p + 4), _i32(buf, p + 8), _i32(buf, p + 12),
                   _i32(buf, p + 16), _i32(buf, p + 20), _i32(buf, p + 24), _i32(buf, p + 28),
                   t, tl, nt, nl, acc)
      in _parse(buf, n, p + 36 + tl + nl, xs, a + 1) end
    end
  end

(* Reads the annotations of the book whose id is h1, h2 *)
#pub fn annot_load (h1: int, h2: int): $P.promise(int, $P.Chained)

implement annot_load (h1, h2) = let
  val () = !_h1 := h1
  val () = !_h2 := h2
  val () = _put(AnnCell(ann_nil(), 0))
  val @(kf, kb) = $A.freeze<byte>(_key())
  val p = $IDB.idb_get(kb, 15)
  val () = $A.drop<byte>(kf, kb)
  val () = $A.free<byte>($A.thaw<byte>(kf))
in
  $P.and_then<Int><int>($P.vow(p), lam(h) =>
    case+ take_content(h) of
    | ~NoContentBytes() => $P.ret<int>(0)
    | ~ContentBytes(ow, buf, n) =>
      if n < 4 then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(buf, 1)) <> 65 then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else let
        val @(xs, k) = _parse(buf, n, 4, ann_nil(), 0)
        val () = piece_free(ow, buf)
        (* only while the same book is open *)
      in
        if !_h1 = h1 then (if !_h2 = h2 then let
            val () = _put(AnnCell(xs, k))
          in $P.ret<int>(k) end
          else let val () = ann_free(xs) in $P.ret<int>(0) end)
        else let val () = ann_free(xs) in $P.ret<int>(0) end
      end)
end

(* ============================================================
   In the reader
   ============================================================ *)

(* Marks the highlights of chapter ch *)
fun _marks {k:nat} .<k>. (xs: !ann(k), ch: int): void =
  case+ xs of
  | ann_nil() => ()
  | @ann_cons(kd, c, sn, so, en, eo, _, _, _, _, _, _, rest) => let
      val () = (if kd = 1 then (if c = ch then
        (if sn >= 0 then (if en >= 0 then let
           val @(sa, sl) = nid_pad3("c", sn)
           val @(ea, el) = nid_pad3("c", en)
           val @(sf, sb) = $A.freeze<byte>(sa)
           val @(ef, eb) = $A.freeze<byte>(ea)
           val () = $BDOM.mark_range(1, sb, sl, so, eb, el, eo)
           val () = $A.drop<byte>(ef, eb)
           val () = $A.free<byte>($A.thaw<byte>(ef))
           val () = $A.drop<byte>(sf, sb)
         in $A.free<byte>($A.thaw<byte>(sf)) end else ()) else ()) else ()) else ())
      val () = _marks(rest, ch)
      prval () = fold@(xs)
    in end

(* The chapter the reader is in (from 0) *)
fn _chapter (): [c:nat] int c =
  case+ reading_get() of @(_, _, c, _) => (if c > 0 then c - 1 else 0)

(* Shows the highlights of the chapter shown *)
#pub fn annot_marks (): void

implement annot_marks () = let
  val () = $BDOM.clear_marks(1)
  val c = _take()
  val+ @AnnCell(xs, _) = c
  val () = _marks(xs, _chapter())
  prval () = fold@(c)
in _put(c) end

(* Whether content node i is on the page shown *)
fn _on_page (i: Int): bool =
  if i < 0 then false
  else let
    val @(ia, il) = nid_pad3("c", i)
    val @(fi, bi) = $A.freeze<byte>(ia)
    val r = $DR.measure(bi, il)
    val () = $A.drop<byte>(fi, bi)
    val () = $A.free<byte>($A.thaw<byte>(fi))
  in
    case+ r of
    | ~$R.err(_) => false
    | ~$R.ok(_) => let
        val x = $DR.get_measure_x()
        val () = ui_measure("qcnt")
        val cx = $DR.get_measure_x()
        val cw = $DR.get_measure_w()
      in if x >= cx then x < cx + cw else false end
  end

(* The page shown *)
fn _page (): int = case+ reading_get() of @(p, _, _, _) => p

(* The index of the bookmark of the page shown, or -1 *)
fun _bookmark_here {k:nat} .<k>. (xs: !ann(k), ch: int, i: int): int =
  case+ xs of
  | ann_nil() => ~1
  | @ann_cons(kd, c, sn, _, _, _, pg, _, _, _, _, _, rest) =>
    if (if kd = 0 then (if c = ch then (if sn >= 0 then _on_page(sn) else pg = _page()) else false) else false) then let
      prval () = fold@(xs)
    in i end
    else let
      val r = _bookmark_here(rest, ch, i + 1)
      prval () = fold@(xs)
    in r end

fn _here (): int = let
  val c = _take()
  val+ @AnnCell(xs, _) = c
  val r = _bookmark_here(xs, _chapter(), 0)
  prval () = fold@(c)
  val () = _put(c)
in r end

(* The bookmark button: filled when the page shown has a bookmark *)
#pub fn annot_star (): void

implement annot_star () =
  if _here() >= 0 then let
    val () = ui_text("qbmk", "\xE2\x98\x85")
  in ui_attr("qbmk", "aria-pressed", "true") end
  else let
    val () = ui_text("qbmk", "\xE2\x98\x86")
  in ui_attr("qbmk", "aria-pressed", "false") end

(* xs without its i-th annotation *)
fun _remove {k:nat} .<k>. (xs: ann(k), i: int): [j:nat | j <= k] @(ann(j), int j) =
  case+ xs of
  | ~ann_nil() => @(ann_nil(), 0)
  | ~ann_cons(kd, c, sn, so, en, eo, pg, tm, t, tl, n, nl, rest) =>
    if i = 0 then let
      val () = $A.free<byte>(t)
      val () = $A.free<byte>(n)
      val @(r, j) = _count(rest)
    in @(r, j) end
    else let
      val @(r, j) = _remove(rest, i - 1)
    in @(ann_cons(kd, c, sn, so, en, eo, pg, tm, t, tl, n, nl, r), j + 1) end

and _count {k:nat} .<k>. (xs: ann(k)): @(ann(k), int k) =
  case+ xs of
  | ~ann_nil() => @(ann_nil(), 0)
  | ~ann_cons(kd, c, sn, so, en, eo, pg, tm, t, tl, n, nl, rest) => let
      val @(r, j) = _count(rest)
    in @(ann_cons(kd, c, sn, so, en, eo, pg, tm, t, tl, n, nl, r), j + 1) end

fn _delete (i: int): void = let
  val+ ~AnnCell(xs, _) = _take()
  val @(ys, j) = _remove(xs, i)
  val () = _put(AnnCell(ys, j))
in _save() end

(* a[0, c) := the blob's first c bytes *)
fn _blob_read {k:nat}{l:agz}{n:pos}{c:nat | c <= k; c <= n} (b: !$BD.dblob(k), a: !$A.arr(byte, l, n), c: int c): void =
  if c > 0 then $DC.blob_read(b, 0, a, c) else ()

(* c, or less, so that a[0, c) ends before a character's start *)
fn _utf8_cut {l:agz}{n:pos}{c:nat | c < n} (a: !$A.arr(byte, l, n), c: int c): [r:nat | r <= c] int r =
  if c <= 0 then 0
  else if $AR.band_int_int(byte2int0($A.get<byte>(a, c)), 192) <> 128 then c
  else if c >= 2 then (if $AR.band_int_int(byte2int0($A.get<byte>(a, c - 1)), 192) <> 128 then c - 1
    else if $AR.band_int_int(byte2int0($A.get<byte>(a, c - 2)), 192) <> 128 then c - 2
    else if c >= 3 then c - 3 else 0)
  else 0

(* The first bytes of a blob's text (at most m of them, cut before a
   UTF-8 character's start) in a new array of m + 1 bytes, with their
   count *)
fn _blob_text {k:nat}{m:pos | m <= 2000} (b: $BD.dblob(k), m: int m): [l:agz][t:nat | t <= m] @($A.arr(byte, l, m + 1), int t) = let
  val n = $DC.blob_len(b)
  val c = (if n < m then n else m): [c:nat | c <= m; c <= k] int c
  val a = $A.alloc<byte>(m + 1)
  val () = _blob_read(b, a, c)
  val () = $DC.blob_free(b)
  val r = _utf8_cut(a, c)
in @(a, r) end

(* The first words of content node i *)
fn _node_words (i: Int): [l:agz][t:nat | t <= 120] @($A.arr(byte, l, 121), int t) =
  if i < 0 then let val a0 = $A.alloc<byte>(121) in @(a0, 0) end
  else let
    val @(ia, il) = nid_pad3("c", i)
    val @(fi, bi) = $A.freeze<byte>(ia)
    val r = $DR.read_text_content(bi, il)
    val () = $A.drop<byte>(fi, bi)
    val () = $A.free<byte>($A.thaw<byte>(fi))
  in
    case+ r of
    | ~$R.none() => let val a0 = $A.alloc<byte>(121) in @(a0, 0) end
    | ~$R.some(b) => _blob_text(b, 120)
  end

fn _add {l1,l2:agz}{tl:nat | tl <= TXT}{nl:nat | nl <= NOTE}
  (kd: Int, ch: Int, sn: Int, so: Int, en: Int, eo: Int, pg: Int,
   t: $A.arr(byte, l1, tl + 1), tl: int tl, n: $A.arr(byte, l2, nl + 1), nl: int nl): void = let
  val+ ~AnnCell(xs, k) = _take()
in
  if k >= AMAX then let
    val () = $A.free<byte>(t)
    val () = $A.free<byte>(n)
  in _put(AnnCell(xs, k)) end
  else let
    val () = _put(AnnCell(_insert(kd, ch, sn, so, en, eo, pg, $TM.epoch_minutes(), t, tl, n, nl, xs), k + 1))
  in _save() end
end

(* The page shown's bookmark: removed when it has one, else added, at
   content node anchor (the page's top) *)
#pub fn annot_bookmark_toggle (anchor: Int): void

implement annot_bookmark_toggle (anchor) = let
  val i = _here()
in
  if i >= 0 then let
    val () = _delete(i)
  in annot_star() end
  else let
    val pg = (case+ reading_get() of @(p, _, _, _) => p): Int
    val @(w0, wl) = _node_words(anchor)
    val w = _copy(w0, wl)
    val () = $A.free<byte>(w0)
    val () = _add(0, _chapter(), anchor, 0, anchor, 0, pg, w, wl, $A.alloc<byte>(1), 0)
  in annot_star() end
end

(* The number of a content node id b[0, n) ("c" and digits), or -1 *)
fn _node_num {k:nat} (b: $BD.dblob(k)): [v:int | v >= ~1] int v = let
  val n = $DC.blob_len(b)
in
  if n <= 1 then let val () = $DC.blob_free(b) in ~1 end
  else if n > 16 then let val () = $DC.blob_free(b) in ~1 end
  else let
    val a = $A.alloc<byte>(n)
    val () = $DC.blob_read(b, 0, a, n)
    val () = $DC.blob_free(b)
    val @(f, bb) = $A.freeze<byte>(a)
    val v = nid_parse(bb, n, 0, "c")
    val () = $A.drop<byte>(f, bb)
    val () = $A.free<byte>($A.thaw<byte>(f))
  in v end
end

fn _num_of (o: $R.option([k:nat] $BD.dblob(k))): [v:int | v >= ~1] int v =
  case+ o of
  | ~$R.none() => ~1
  | ~$R.some(b) => _node_num(b)

(* The index of the annotation at chapter ch, node sn, offset so *)
fn _index_of (ch: Int, sn: Int, so: Int): int = let
  fun find {k:nat} .<k>. (xs: !ann(k), i: int): int =
    case+ xs of
    | ann_nil() => ~1
    | @ann_cons(_, c, n, o, _, _, _, _, _, _, _, _, rest) =>
      if (if c = ch then (if n = sn then o = so else false) else false) then let
        prval () = fold@(xs)
      in i end
      else let
        val r = find(rest, i + 1)
        prval () = fold@(xs)
      in r end
  val c = _take()
  val+ @AnnCell(xs, _) = c
  val r = find(xs, 0)
  prval () = fold@(c)
  val () = _put(c)
in r end

(* The selection, as a highlight of the chapter shown: its index, or -1
   when nothing is selected in the chapter's text *)
#pub fn annot_highlight (): int

implement annot_highlight () = let
  val @(so_b, eo_b) = $DR.get_selection_range()
  val so = $DR.get_measure_x()
  val eo = $DR.get_measure_y()
  val sn = _num_of(so_b)
  val en = _num_of(eo_b)
in
  if sn < 0 then ~1
  else if en < 0 then ~1
  else if (if sn = en then so >= eo else sn > en) then ~1
  else (case+ $DR.get_selection_text() of
    | ~$R.none() => ~1
    | ~$R.some(b) => let
        val @(t0, tl) = _blob_text(b, TXT)
        val t = _copy(t0, tl)
        val () = $A.free<byte>(t0)
        val ch = _chapter()
        val pg = (case+ reading_get() of @(p, _, _, _) => p): Int
        val () = _add(1, ch, sn, so, en, eo, pg, t, tl, $A.alloc<byte>(1), 0)
        val () = annot_marks()
      in _index_of(ch, sn, so) end)
end

(* ============================================================
   Notes
   ============================================================ *)

fun _set_note {k:nat}{l:agz}{nl:nat | nl <= NOTE} .<k>.
  (xs: !ann(k), i: int, n: $A.arr(byte, l, nl + 1), nl: int nl): void =
  case+ xs of
  | ann_nil() => $A.free<byte>(n)
  | @ann_cons(_, _, _, _, _, _, _, _, _, _, nt, ntl, rest) =>
    if i = 0 then let
      val () = $A.free<byte>(nt)
      val () = nt := n
      val () = ntl := nl
      prval () = fold@(xs)
    in end
    else let
      val () = _set_note(rest, i - 1, n, nl)
      prval () = fold@(xs)
    in end

(* How much of b[0, k) a note keeps: all of it, or its first NOTE
   bytes (fewer, not to cut a character) *)
fn _note_len {l:agz}{m:pos}{k:nat | k <= m} (b: !$A.arr(byte, l, m), k: int k): [r:nat | r <= k; r <= NOTE] int r =
  if k <= NOTE then k else _utf8_cut(b, NOTE)

(* The note of annotation i: b[0, k), at most NOTE bytes of it *)
#pub fn annot_note_set {l:agz}{m:pos}{k:nat | k <= m} (i: int, b: $A.arr(byte, l, m), k: int k): void

implement annot_note_set (i, b, k) = let
  val nl = _note_len(b, k)
  val n = $A.alloc<byte>(nl + 1)
  val () = _dup(b, n, nl, 0)
  val () = $A.free<byte>(b)
  val c = _take()
  val+ @AnnCell(xs, _) = c
  val () = _set_note(xs, i, n, nl)
  prval () = fold@(c)
  val () = _put(c)
in _save() end

fun _note_at {k:nat} .<k>. (xs: !ann(k), i: int): [l:agz][nl:nat | nl <= NOTE] @($A.arr(byte, l, nl + 1), int nl) =
  case+ xs of
  | ann_nil() => let val a0 = $A.alloc<byte>(1) in @(a0, 0) end
  | @ann_cons(_, _, _, _, _, _, _, _, _, _, nt, nl, rest) =>
    if i = 0 then let
      val b = _copy(nt, nl)
      val n = nl
      prval () = fold@(xs)
    in @(b, n) end
    else let
      val r = _note_at(rest, i - 1)
      prval () = fold@(xs)
    in r end

(* The note of annotation i, in the dialog's text area *)
#pub fn annot_note_show (i: int): void

implement annot_note_show (i) = let
  val c = _take()
  val+ @AnnCell(xs, _) = c
  val @(b, nl) = _note_at(xs, i)
  prval () = fold@(c)
  val () = _put(c)
in ui_text_buf("qmta", b, nl) end

(* Deletes annotation i *)
#pub fn annot_delete (i: int): void

implement annot_delete (i) = let
  val () = _delete(i)
  val () = annot_marks()
in annot_star() end

(* ============================================================
   Where one leads
   ============================================================ *)

fun _dest_at {k:nat} .<k>. (xs: !ann(k), i: int): @(Int, Int, Int) =
  case+ xs of
  | ann_nil() => @(~1, 0, ~1)
  | @ann_cons(_, c, sn, _, _, _, pg, _, _, _, _, _, rest) =>
    if i = 0 then let
      val c0 = c
      val p0 = pg
      val s0 = sn
      prval () = fold@(xs)
    in @((if c0 >= 0 then c0 else 0), (if p0 >= 0 then p0 else 0), (if s0 >= 0 then s0 else ~1)) end
    else let
      val r = _dest_at(rest, i - 1)
      prval () = fold@(xs)
    in r end

(* Annotation i's chapter, page and content node; a chapter of -1 when
   there is no annotation i *)
#pub fn annot_dest (i: int): @(Int, Int, Int)

implement annot_dest (i) = let
  val c = _take()
  val+ @AnnCell(xs, _) = c
  val r = _dest_at(xs, i)
  prval () = fold@(c)
  val () = _put(c)
in r end

(* ============================================================
   The lists
   ============================================================ *)

(* A child element of numbered parent pre1<i>, numbered pre2<i> *)
fn _child {s1,s2:pos | s1 <= 4; s2 <= 4}{i:nat}{tl:pos | tl < 256}{nc:pos | nc < 256}
  (pre1: string s1, pre2: string s2, i: int i, tag: string tl, cls: string nc): void = let
  val @(pa, pl) = nid_make(pre1, i)
  val @(ca, cl) = nid_make(pre2, i)
  val () = ui_add_nn(pa, pl, ca, cl, tag)
  val @(ca, cl) = nid_make(pre2, i)
in ui_attr_n(ca, cl, "class", cls) end

(* Element pre<i>'s text: a[0, k) *)
fn _text_of {sn:pos | sn <= 4}{i:nat}{l:agz}{m:pos}{k:nat | k < m; k < 65536}
  (pre: string sn, i: int i, a: !$A.arr(byte, l, m), k: int k): void = let
  val b = $A.alloc<byte>(k + 1)
  val () = _dup(a, b, k, 0)
  val @(ia, il) = nid_make(pre, i)
in ui_text_n_buf(ia, il, b, k) end

(* The heading of chapter ch's annotations, in the list lst *)
fn _heading {ni:pos | ni < 256}{c:nat} (lst: string ni, ch: int c): void = let
  val @(ga, gl) = nid_make("qg", ch)
  val () = ui_add_n(lst, ga, gl, "div")
  val @(ga, gl) = nid_make("qg", ch)
  val () = ui_attr_n(ga, gl, "class", "grp")
  val @(lb, lk) = toc_label_of(ch)
  val @(ga, gl) = nid_make("qg", ch)
in ui_text_n_buf(ga, gl, lb, lk) end

(* One row of the annotations list: highlight i *)
fn _hrow {i:nat}{l1,l2:agz}{t1,t2:pos}{tl:nat | tl < t1; tl < 65536}{nl:nat | nl < t2; nl < 65536}
  (i: int i, t: !$A.arr(byte, l1, t1), tl: int tl, n: !$A.arr(byte, l2, t2), nl: int nl): void = let
  val @(ra, rl) = nid_make("qr", i)
  val () = ui_add_n("qanl", ra, rl, "div")
  val @(ra, rl) = nid_make("qr", i)
  val () = ui_attr_n(ra, rl, "class", "hrow")
  val () = _child("qr", "qa", i, "button", "hgo")
  val () = _child("qa", "qq", i, "span", "hq")
  val () = _text_of("qq", i, t, tl)
  val () = (if nl > 0 then let
      val () = _child("qa", "qo", i, "span", "hn")
    in _text_of("qo", i, n, nl) end else ())
  val () = _child("qr", "qw", i, "div", "hbtns")
  val () = _child("qw", "qn", i, "button", "hbtn")
  val @(ba, bl) = nid_make("qn", i)
  val () = (if nl > 0 then ui_text_n(ba, bl, "Edit note") else ui_text_n(ba, bl, "Add note"))
  val () = _child("qw", "qd", i, "button", "hbtn")
  val @(ba, bl) = nid_make("qd", i)
in ui_text_n(ba, bl, "Delete") end

fun _hrows {k:nat}{i:nat} .<k>. (xs: !ann(k), i: int i, last: Int): int =
  case+ xs of
  | ann_nil() => i
  | @ann_cons(kd, c, _, _, _, _, _, _, t, tl, n, nl, rest) => let
      val () = (if kd = 1 then let
          val () = (if c <> last then (if c >= 0 then _heading("qanl", c) else ()) else ())
        in _hrow(i, t, tl, n, nl) end else ())
      val last2 = (if kd = 1 then c else last): Int
      val r = _hrows(rest, i + 1, last2)
      prval () = fold@(xs)
    in r end

fun _count_kind {k:nat} .<k>. (xs: !ann(k), kd: Int): int =
  case+ xs of
  | ann_nil() => 0
  | @ann_cons(d, _, _, _, _, _, _, _, _, _, _, _, rest) => let
      val d0 = d
      val r = _count_kind(rest, kd)
      prval () = fold@(xs)
    in if d0 = kd then r + 1 else r end

(* Fills the annotations list: the highlights, by chapter *)
#pub fn annot_render (): void

implement annot_render () = let
  val () = ui_clear("qanl")
  val c = _take()
  val+ @AnnCell(xs, _) = c
  val n = _count_kind(xs, 1)
  val _ = _hrows(xs, 0, ~1)
  prval () = fold@(c)
  val () = _put(c)
in
  if n = 0 then let
    val () = ui_add("qanl", "qane", "div")
    val () = ui_class("qane", "empty")
  in ui_text("qane", "No highlights yet. Select text to highlight it.") end
  else ()
end

(* One row of the bookmarks list: bookmark i *)
fn _brow {i:nat}{c:nat}{l1:agz}{t1:pos}{tl:nat | tl < t1; tl < 65536}
  (i: int i, ch: int c, t: !$A.arr(byte, l1, t1), tl: int tl): void = let
  val @(ra, rl) = nid_make("qbr", i)
  val () = ui_add_n("qtbl", ra, rl, "div")
  val @(ra, rl) = nid_make("qbr", i)
  val () = ui_attr_n(ra, rl, "class", "hrow")
  val () = _child("qbr", "qb", i, "button", "hgo")
  val () = _child("qb", "qy", i, "span", "bt")
  val @(lb, lk) = toc_label_of(ch)
  val @(ya, yl) = nid_make("qy", i)
  val () = ui_text_n_buf(ya, yl, lb, lk)
  val () = (if tl > 0 then let
      val () = _child("qb", "qz", i, "span", "snip")
    in _text_of("qz", i, t, tl) end else ())
  val () = _child("qbr", "qx", i, "button", "hbtn")
  val @(ba, bl) = nid_make("qx", i)
in ui_text_n(ba, bl, "Delete") end

fun _brows {k:nat}{i:nat} .<k>. (xs: !ann(k), i: int i): void =
  case+ xs of
  | ann_nil() => ()
  | @ann_cons(kd, c, _, _, _, _, _, _, t, tl, _, _, rest) => let
      val () = (if kd = 0 then (if c >= 0 then _brow(i, c, t, tl) else ()) else ())
      val () = _brows(rest, i + 1)
      prval () = fold@(xs)
    in end

(* Fills the bookmarks list *)
#pub fn annot_render_bookmarks (): void

implement annot_render_bookmarks () = let
  val () = ui_clear("qtbl")
  val c = _take()
  val+ @AnnCell(xs, _) = c
  val n = _count_kind(xs, 0)
  val () = _brows(xs, 0)
  prval () = fold@(c)
  val () = _put(c)
in
  if n = 0 then let
    val () = ui_add("qtbl", "qtbe", "div")
    val () = ui_class("qtbe", "empty")
  in ui_text("qtbe", "No bookmarks yet. Tap the star to add one.") end
  else ()
end

(* ============================================================
   Export: Markdown
   ============================================================ *)

(* The literal s at out[p] *)
fun _lit_at {l:agz}{la:addr}{n:nat}{sn:nat}{p:nat | p + sn <= n}{j:nat | j <= sn} .<sn - j>.
  (out: !$A.arrx(byte, l, n, la), p: int p, s: string sn, sl: int sn, j: int j): int(p + sn) =
  if j >= sl then p + sl
  else let
    val () = $A.write_byte(out, p + j, $AR.byte_of_char(string_get_at(s, j)))
  in _lit_at(out, p, s, sl, j + 1) end

fn _lit {l:agz}{la:addr}{n:nat}{sn:nat}{p:nat | p + sn <= n}
  (out: !$A.arrx(byte, l, n, la), p: int p, s: string sn): int(p + sn) =
  _lit_at(out, p, s, g1u2i(string1_length(s)), 0)

fn _flat {c:nat | c < 256} (c: int c): [v:nat | v < 256] int v =
  if c = 10 then 32 else if c = 13 then 32 else c

(* src[0, m) at out[p], with its line breaks as spaces *)
fun _flat_at {ls,l:agz}{la:addr}{ns:pos}{m:nat | m <= ns}{n:nat}{p:nat | p + m <= n}{j:nat | j <= m} .<m - j>.
  (src: !$A.arr(byte, ls, ns), m: int m, out: !$A.arrx(byte, l, n, la), p: int p, j: int j): void =
  if j >= m then ()
  else let
    val c = $AR.low_byte(byte2int0($A.get<byte>(src, j)))
    val () = $A.write_byte(out, p + j, _flat(c))
  in _flat_at(src, m, out, p, j + 1) end

fn _md_heading {l:agz}{la:addr}{n:int}{p:nat | p + 206 <= n}
  (out: !$A.arrx(byte, l, n, la), p: int p, c: Int): [q:nat | p <= q; q <= p + 206] int q =
  if c < 0 then p
  else let
    val @(lb, lk) = toc_label_of(c)
    val q = _lit(out, p, "### ")
    val () = _flat_at(lb, lk, out, q, 0)
    val () = $A.free<byte>(lb)
  in _lit(out, q + lk, "\n\n") end

fn _md_note {l:agz}{la:addr}{n:int}{p:nat | p + 2012 <= n}{l2:agz}{t2:pos}{nl:nat | nl < t2; nl <= NOTE}
  (out: !$A.arrx(byte, l, n, la), p: int p, nt: !$A.arr(byte, l2, t2), nl: int nl): [q:nat | p <= q; q <= p + 2012] int q =
  if nl <= 0 then p
  else let
    val q = _lit(out, p, "**Note:** ")
    val () = _flat_at(nt, nl, out, q, 0)
  in _lit(out, q + nl, "\n\n") end

fn _md_head_if {l:agz}{la:addr}{n:int}{p:nat | p + 206 <= n}
  (out: !$A.arrx(byte, l, n, la), p: int p, c: Int, last: Int): [q:nat | p <= q; q <= p + 206] int q =
  if c <> last then _md_heading(out, p, c) else p

(* The highlights as Markdown at out[p]: each after its chapter's
   heading when it is the chapter's first *)
fun _md {l:agz}{la:addr}{n:int}{j:nat}{p:nat | p + 2800 * j + 64 <= n} .<j>.
  (out: !$A.arrx(byte, l, n, la), p: int p, xs: !ann(j), last: Int): [q:nat | q + 64 <= n] int q =
  case+ xs of
  | ann_nil() => p
  | @ann_cons(kd, c, _, _, _, _, _, _, t, tl, nt, nl, rest) =>
    if kd <> 1 then let
      val q = _md(out, p, rest, last)
      prval () = fold@(xs)
    in q end
    else let
      val p1 = _md_head_if(out, p, c, last)
      val p2 = _lit(out, p1, "> ")
      val () = _flat_at(t, tl, out, p2, 0)
      val p3 = _lit(out, p2 + tl, "\n\n")
      val p4 = _md_note(out, p3, nt, nl)
      val q = _md(out, p4, rest, c)
      prval () = fold@(xs)
    in q end

(* Downloads the highlights and notes as a Markdown file, headed by the
   book's title t[0, tn) and author a[0, an) *)
#pub fn annot_export {l1,l2:agz}{m1,m2:pos}{tn:nat | tn < m1; tn < 256}{an:nat | an < m2; an < 256}
  (t: $A.arr(byte, l1, m1), tn: int tn, a: $A.arr(byte, l2, m2), an: int an): void

implement annot_export (t, tn, a, an) = let
  val c = _take()
  val+ @AnnCell(xs, k) = c
  val n = 1024 + 2800 * k
in
  case+ piece_new(n) of
  | ~NoPiece() => let
      prval () = fold@(c)
      val () = _put(c)
      val () = $A.free<byte>(t)
    in $A.free<byte>(a) end
  | ~Piece(ow, out) => let
      val p = _lit(out, 0, "# ")
      val () = _flat_at(t, tn, out, p, 0)
      val p = _lit(out, p + tn, "\n## ")
      val () = _flat_at(a, an, out, p, 0)
      val p = _lit(out, p + an, "\n\n")
      val () = $A.free<byte>(t)
      val () = $A.free<byte>(a)
      val q = _md(out, p, xs, ~1)
      prval () = fold@(c)
      val () = _put(c)
      val q = _lit(out, q, "---\n*Exported from Quire*\n")
      val @(f, b) = $A.freeze<byte>(out)
      val @(used, rest) = $A.borrow_split<byte>(f, b, q)
      val ma = $A.alloc<byte>(13)
      val () = $A.write_text(ma, 0, $A.text_lit("text/markdown"), 13)
      val @(mf, mb) = $A.freeze<byte>(ma)
      val na = $A.alloc<byte>(20)
      val () = $A.write_text(na, 0, $A.text_lit("quire-annotations.md"), 20)
      val @(nf, nb) = $A.freeze<byte>(na)
      val () = $BL.download_blob(used, q, mb, 13, nb, 20)
      val () = $A.drop<byte>(nf, nb)
      val () = $A.free<byte>($A.thaw<byte>(nf))
      val () = $A.drop<byte>(mf, mb)
      val () = $A.free<byte>($A.thaw<byte>(mf))
      val b = $A.borrow_join<byte>(f, used, rest)
      val () = $A.drop<byte>(f, b)
    in piece_free(ow, $A.thaw<byte>(f)) end
end

end (* #target wasm *)
