(* library -- the books quire keeps: their records, stored and shown *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use str as S

staload "ui.sats"
staload "book.sats"
staload "modal.sats"
staload "undo.sats"
staload "epub_xml.sats"
staload "mem.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload BDOM = "wasm.bats-packages.dev/bridge/src/dom.sats"

(* ============================================================
   Records
   ============================================================ *)

(* A book's numbers. Its id is the first 14 hex digits of its file's
   SHA-256, as two 28-bit halves; its key numbers it in this run (it is
   not stored). Times are minutes since the epoch. *)
#pub typedef bnums = @{
  key = Int,
  h1 = Int, h2 = Int,
  shelf = Int,     (* 0 on the shelf, 1 hidden, 2 archived, 3 in the Trash *)
  added = Int,
  opened = Int,    (* 0 when never read *)
  ch = Int,        (* the chapter read last, from 0 *)
  tch = Int,       (* the book's chapters, 0 when not known yet *)
  pg = Int,        (* the page read last, of pgs in that chapter *)
  pgs = Int,
  anchor = Int,    (* the content node at that page's start, -1 none *)
  fsz = Int,       (* the file's bytes *)
  cover = Int,     (* the cover image's type (mime_str), 0 none *)
  done = Int,      (* 1 when the last page was reached *)
  sidx = Int,      (* its number in its series, 0 when none is given *)
  cols = Int       (* the collections it is in: collection j is bit j *)
}

(* A book: its title and author (1 to 255 bytes), its series' name (0
   to 255 bytes, in an array one longer) and its numbers *)
#pub datavtype book =
  | {lt,la,ls:agz}{nt,na:pos | nt < 256; na < 256}{ns:nat | ns < 256}
    Book of ($A.arr(byte, lt, nt), int nt, $A.arr(byte, la, na), int na,
             $A.arr(byte, ls, ns + 1), int ns, bnums)

#pub stadef LIB_MAX = 100000

#pub datavtype books(int) =
  | books_nil(0) of ()
  | {k:nat} books_cons(k + 1) of (book, books(k))

fn book_free (b: book): void = let
  val+ ~Book(t, _, a, _, sr, _, _) = b
  val () = $A.free<byte>(t)
  val () = $A.free<byte>(sr)
in $A.free<byte>(a) end

fun books_free {k:nat} .<k>. (bs: books(k)): void =
  case+ bs of
  | ~books_nil() => ()
  | ~books_cons(b, rest) => let val () = book_free(b) in books_free(rest) end

(* ============================================================
   The library, and what the library view shows of it
   ============================================================ *)

datavtype lib_cell =
  | {k:nat | k <= LIB_MAX} LibCell of (books(k), int k)

val _lib = ref<lib_cell>(LibCell(books_nil(), 0))
val _next_key = ref<Int>(1)

(* 0 last opened, 1 title, 2 author, 3 date added *)
val _sort_order = ref<int>(0)
(* 0 the shelf, 1 hidden, 2 archived, 3 the Trash *)
val _shelf = ref<int>(0)
(* The library view's render: an image that arrives after another
   render is not shown *)
val _render_gen = ref<int>(0)

(* The search query, lowercased *)
datavtype query =
  | {l:agz}{n:pos | n < 256} QuerySome of ($A.arr(byte, l, n), int n)
  | QueryNone of ()

val _query = ref<query>(QueryNone())

fn lib_take (): lib_cell = let
  var c: lib_cell = LibCell(books_nil(), 0)
  val () = ref_exch_elt<lib_cell>(_lib, c)
in c end

fn lib_put (c: lib_cell): void = let
  var cur: lib_cell = c
  val () = ref_exch_elt<lib_cell>(_lib, cur)
  val+ ~LibCell(bs, _) = cur
in books_free(bs) end

fn query_take (): query = let
  var q: query = QueryNone()
  val () = ref_exch_elt<query>(_query, q)
in q end

fn query_put (q: query): void = let
  var cur: query = q
  val () = ref_exch_elt<query>(_query, cur)
in
  case+ cur of
  | ~QuerySome(a, _) => $A.free<byte>(a)
  | ~QueryNone() => ()
end

#pub fn lib_count (): [k:nat | k <= LIB_MAX] int k

implement lib_count () = let
  val c = lib_take()
  val+ LibCell(_, k) = c
  val () = lib_put(c)
in k end

#pub fn lib_sort_get (): int
implement lib_sort_get () = !_sort_order

#pub fn lib_shelf_get (): int
implement lib_shelf_get () = !_shelf

(* ============================================================
   Ids and keys
   ============================================================ *)

fn _hexd {v:nat | v < 16} (v: int v): [c:nat | c < 256] int c =
  if v < 10 then 48 + v else 87 + v

(* The 7 hex digits of h (its low 28 bits) at buf[p, p + 7) *)
fn _put_hex7 {l:agz}{la:addr}{n:nat}{p:nat | p + 7 <= n}
  (buf: !$A.arrx(byte, l, n, la), p: int p, h: int): void = let
  fn dig {i:nat | i < 7} (h: int, i: int i): [c:nat | c < 256] int c =
    _hexd($AR.band_g1($AR.low_byte($AR.bsr_int_int(h, 4 * (6 - i))), 15))
  val () = $A.write_byte(buf, p, dig(h, 0))
  val () = $A.write_byte(buf, p + 1, dig(h, 1))
  val () = $A.write_byte(buf, p + 2, dig(h, 2))
  val () = $A.write_byte(buf, p + 3, dig(h, 3))
  val () = $A.write_byte(buf, p + 4, dig(h, 4))
  val () = $A.write_byte(buf, p + 5, dig(h, 5))
in $A.write_byte(buf, p + 6, dig(h, 6)) end

(* The storage key of a book's file ('b'), cover ('c') or annotations
   ('a'): the letter and the book's 14 hex digits *)
#pub fn lib_key {c:nat | c < 256} (letter: int c, h1: int, h2: int): [l:agz] $A.arr(byte, l, 15)

implement lib_key (letter, h1, h2) = let
  val k = $A.alloc<byte>(15)
  val () = $A.write_byte(k, 0, letter)
  val () = _put_hex7(k, 1, h1)
  val () = _put_hex7(k, 8, h2)
in k end

(* The value of hex digit c (0 for any other byte) *)
fn _hexv {c:nat | c < 256} (c: int c): [v:nat | v < 16] int v =
  if c >= 48 then (if c <= 57 then c - 48
    else if c >= 97 then (if c <= 102 then c - 87 else 0) else 0)
  else 0

fn _hexat {l:agz}{i:nat | i < 64} (d: !$A.arr(byte, l, 64), i: int i): [v:nat | v < 16] int v =
  _hexv($AR.low_byte(byte2int0($A.get<byte>(d, i))))

(* The 7 hex digits d[o, o + 7) *)
fn _hex7 {l:agz}{o:nat | o + 7 <= 64} (d: !$A.arr(byte, l, 64), o: int o): Int =
  ((((((_hexat(d, o) * 16 + _hexat(d, o + 1)) * 16 + _hexat(d, o + 2)) * 16
    + _hexat(d, o + 3)) * 16 + _hexat(d, o + 4)) * 16 + _hexat(d, o + 5)) * 16
    + _hexat(d, o + 6))

(* A book's id from its SHA-256 in hex *)
#pub fn lib_id_of_hex {l:agz} (d: !$A.arr(byte, l, 64)): @(Int, Int)

implement lib_id_of_hex (d) = @(_hex7(d, 0), _hex7(d, 7))

(* ============================================================
   Finding books
   ============================================================ *)

fun _find {k:nat}{i:nat} .<k>. (bs: !books(k), h1: int, h2: int, i: int i): [r:int | r >= ~1] int r =
  case+ bs of
  | books_nil() => ~1
  | books_cons(b, rest) => let
      val+ Book(_, _, _, _, _, _, nums) = b
    in if nums.h1 = h1 then (if nums.h2 = h2 then i else _find(rest, h1, h2, i + 1))
       else _find(rest, h1, h2, i + 1) end

(* The index of the book with this id, or -1 *)
#pub fn lib_find (h1: int, h2: int): [r:int | r >= ~1] int r

implement lib_find (h1, h2) = let
  val c = lib_take()
  val+ @LibCell(bs, _) = c
  val r = _find(bs, h1, h2, 0)
  prval () = fold@(c)
  val () = lib_put(c)
in r end

fun _find_key {k:nat}{i:nat} .<k>. (bs: !books(k), key: int, i: int i): [r:int | r >= ~1] int r =
  case+ bs of
  | books_nil() => ~1
  | books_cons(b, rest) => let
      val+ Book(_, _, _, _, _, _, nums) = b
    in if nums.key = key then i else _find_key(rest, key, i + 1) end

#pub fn lib_index_of_key (key: int): [r:int | r >= ~1] int r

implement lib_index_of_key (key) = let
  val c = lib_take()
  val+ @LibCell(bs, _) = c
  val r = _find_key(bs, key, 0)
  prval () = fold@(c)
  val () = lib_put(c)
in r end

(* The numbers of book i (when there is one) *)
fun _nums_at {k:nat}{i:nat} .<k>. (bs: !books(k), i: int i): $R.option(bnums) =
  case+ bs of
  | books_nil() => $R.none()
  | books_cons(b, rest) =>
    if i = 0 then let val+ Book(_, _, _, _, _, _, nums) = b in $R.some(nums) end
    else _nums_at(rest, i - 1)

#pub fn lib_nums {i:int} (i: int i): $R.option(bnums)

implement lib_nums (i) =
  if i < 0 then $R.none()
  else let
    val c = lib_take()
    val+ @LibCell(bs, _) = c
    val r = _nums_at(bs, i)
    prval () = fold@(c)
    val () = lib_put(c)
  in r end

(* Changes book i's numbers with f *)
fun _update_at {k:nat}{i:nat} .<k>. (bs: !books(k), i: int i, f: (bnums) -<cloref1> bnums): void =
  case+ bs of
  | books_nil() => ()
  | @books_cons(b, rest) =>
    if i = 0 then let
      val+ @Book(_, _, _, _, _, _, nums) = b
      val () = nums := f(nums)
      prval () = fold@(b)
      prval () = fold@(bs)
    in end
    else let
      val () = _update_at(rest, i - 1, f)
      prval () = fold@(bs)
    in end

#pub fn lib_update {i:int} (i: int i, f: (bnums) -<cloref1> bnums): void

implement lib_update (i, f) =
  if i < 0 then ()
  else let
    val c = lib_take()
    val+ @LibCell(bs, _) = c
    val () = _update_at(bs, i, f)
    prval () = fold@(c)
  in lib_put(c) end

(* Book i's title or author (which: 0 title, 1 author) in a fresh array *)
fun _copy {ls,ld:agz}{ns,ms,nd:nat | ns <= ms}{o:nat | o + ns <= nd}{j:nat | j <= ns} .<ns - j>.
  (src: !$A.arr(byte, ls, ms), ns: int ns, dst: !$A.arr(byte, ld, nd), o: int o, j: int j): void =
  if j >= ns then ()
  else let
    val () = $A.set<byte>(dst, o + j, $A.get<byte>(src, j))
  in _copy(src, ns, dst, o, j + 1) end

fun _text_at {k:nat}{i:nat} .<k>. (bs: !books(k), i: int i, which: int)
  : [l:agz][n:nat | n < 256] @($A.arr(byte, l, n + 1), int n) =
  case+ bs of
  | books_nil() => let val a = $A.alloc<byte>(1) in @(a, 0) end
  | books_cons(b, rest) =>
    if i = 0 then let
      val+ Book(t, tn, a, an, _, _, _) = b
    in
      if which = 0 then let
        val out = $A.alloc<byte>(tn + 1)
        val () = _copy(t, tn, out, 0, 0)
      in @(out, tn) end
      else let
        val out = $A.alloc<byte>(an + 1)
        val () = _copy(a, an, out, 0, 0)
      in @(out, an) end
    end
    else _text_at(rest, i - 1, which)

(* Book i's title (which 0) or author (which 1): the bytes and their
   count (0 when there is no book i) in an array one longer *)
#pub fn lib_text {i:int} (i: int i, which: int): [l:agz][n:nat | n < 256] @($A.arr(byte, l, n + 1), int n)

implement lib_text (i, which) =
  if i < 0 then let val a = $A.alloc<byte>(1) in @(a, 0) end
  else let
    val c = lib_take()
    val+ @LibCell(bs, _) = c
    val r = _text_at(bs, i, which)
    prval () = fold@(c)
    val () = lib_put(c)
  in r end

(* ============================================================
   Adding and removing
   ============================================================ *)

(* A book from span [to, to + tl) and [ao, ao + al) of data for its
   title and author: the fallbacks when a span is empty or too long *)
fun _series_copy {lb,la:agz}{n,na:pos}{o:nat}{m:nat | m < na; o + m <= n}{j:nat | j <= m} .<m - j>.
  (data: !$A.borrow(byte, lb, n), o: int o, a: !$A.arr(byte, la, na), m: int m, j: int j): void =
  if j >= m then ()
  else let
    val () = $A.set<byte>(a, j, $A.read<byte>(data, o + j))
  in _series_copy(data, o, a, m, j + 1) end

(* A series' name from data[o, o + k), at most 255 bytes, in an array one
   longer; empty when there is none *)
(* " · N" after the name at b[0, p) *)
fn _series_num {l:agz}{p:nat} (b: !$A.arr(byte, l, p + 20), p: int p, v: Int): [k:nat | k <= p + 20] int k =
  if v <= 0 then p
  else if v > 99999 then p
  else let
  val () = $A.set<byte>(b, p, $A.int2byte(32))
  val () = $A.set<byte>(b, p + 1, $A.int2byte(194))
  val () = $A.set<byte>(b, p + 2, $A.int2byte(183))
  val () = $A.set<byte>(b, p + 3, $A.int2byte(32))
in $S.int_to_str(b, p + 4, p + 20, v) end

fn _series_arr {lb:agz}{n:pos}{o,k:nat | o + k <= n}
  (data: !$A.borrow(byte, lb, n), n: int n, o: int o, k: int k): [l:agz][m:nat | m < 256] @($A.arr(byte, l, m + 1), int m) = let
  val m = (if k > 255 then 255 else k): [m:nat | m <= k; m < 256] int m
  val a = $A.alloc<byte>(m + 1)
  val () = _series_copy(data, o, a, m, 0)
in @(a, m) end

fn _span_arr {lb:agz}{n:pos}{o,m:nat | o + m <= n}{fl:pos | fl < 256}
  (data: !$A.borrow(byte, lb, n), n: int n, o: int o, m: int m, fallback: string fl)
  : [l:agz][k:pos | k < 256] @($A.arr(byte, l, k), int k) =
  if m <= 0 then let
    val fl = g1u2i(string1_length(fallback))
    val a = $A.alloc<byte>(fl)
    val () = $A.write_text(a, 0, $A.text_lit(fallback), fl)
  in @(a, fl) end
  else if m >= 256 then let
    val a = $A.alloc<byte>(255)
    val () = $S.copy_from_borrow(data, o, n, a, 0, 255, 255)
  in @(a, 255) end
  else let
    val a = $A.alloc<byte>(m)
    val () = $S.copy_from_borrow(data, o, n, a, 0, m, m)
  in @(a, m) end

(* Adds a book: its id, title and author (spans of data), file size and
   cover type; its key. None when the library is full. *)
#pub fn lib_add {lb:agz}{n:pos}{to,tl,ao,al,so,sl:nat | to + tl <= n; ao + al <= n; so + sl <= n}
  (h1: Int, h2: Int, data: !$A.borrow(byte, lb, n), n: int n,
   to: int to, tl: int tl, ao: int ao, al: int al, so: int so, sl: int sl, sidx: Int,
   fsz: Int, cover: Int, now: Int): Int

implement lib_add (h1, h2, data, n, to, tl, ao, al, so, sl, sidx, fsz, cover, now) = let
  val c = lib_take()
  val+ ~LibCell(bs, k) = c
in
  if k >= 100000 then let
    val () = lib_put(LibCell(bs, k))
  in ~1 end
  else let
    val key = !_next_key
    val () = !_next_key := key + 1
    val @(t, tn) = _span_arr(data, n, to, tl, "Imported Book")
    val @(a, an) = _span_arr(data, n, ao, al, "Unknown Author")
    val @(sr, sn) = _series_arr(data, n, so, sl)
    val nums = @{
      key = key, h1 = h1, h2 = h2, shelf = 0, added = now, opened = 0,
      ch = 0, tch = 0, pg = 0, pgs = 0, anchor = ~1, fsz = fsz, cover = cover, done = 0,
      sidx = sidx, cols = 0
    }: bnums
    val () = lib_put(LibCell(books_cons(Book(t, tn, a, an, sr, sn, nums), bs), k + 1))
  in key end
end

fun _remove_at {k:pos}{i:nat | i < k} .<k>. (bs: books(k), i: int i): books(k - 1) = let
  val+ ~books_cons(b, rest) = bs
in
  if i = 0 then let val () = book_free(b) in rest end
  else books_cons(b, _remove_at(rest, i - 1))
end

fun _pull {k:pos}{i:nat | i < k} .<k>. (bs: books(k), i: int i): @(book, books(k - 1)) = let
  val+ ~books_cons(b, rest) = bs
in
  if i = 0 then @(b, rest)
  else let
    val @(x, rest2) = _pull(rest, i - 1)
  in @(x, books_cons(b, rest2)) end
end

(* Book i's series' name, from data[o, o + k) (its file was imported
   again) *)
fun _series_set_at {k:nat}{lb:agz}{n:pos}{o,m:nat | o + m <= n} .<k>.
  (bs: books(k), i: int, data: !$A.borrow(byte, lb, n), n: int n, o: int o, m: int m): books(k) =
  case+ bs of
  | ~books_nil() => books_nil()
  | ~books_cons(b, rest) =>
    if i = 0 then let
      val+ ~Book(t, tn, a, an, sr, _, x) = b
      val () = $A.free<byte>(sr)
      val @(sr2, sn2) = _series_arr(data, n, o, m)
    in books_cons(Book(t, tn, a, an, sr2, sn2, x), rest) end
    else books_cons(b, _series_set_at(rest, i - 1, data, n, o, m))

#pub fn lib_series_set {lb:agz}{n:pos}{o,m:nat | o + m <= n}
  (i: int, data: !$A.borrow(byte, lb, n), n: int n, o: int o, m: int m): void

implement lib_series_set (i, data, n, o, m) = let
  val c = lib_take()
  val+ ~LibCell(bs, k) = c
in lib_put(LibCell(_series_set_at(bs, i, data, n, o, m), k)) end

(* Moves book i to the front of the library: the sort is stable, so of
   the books opened in the same minute, the one opened last comes first *)
#pub fn lib_touch {i:int} (i: int i): void

implement lib_touch (i) = let
  val c = lib_take()
  val+ ~LibCell(bs, k) = c
in
  if i <= 0 then lib_put(LibCell(bs, k))
  else if i >= k then lib_put(LibCell(bs, k))
  else let
    val @(x, rest) = _pull(bs, i)
  in lib_put(LibCell(books_cons(x, rest), k)) end
end

(* Removes book i from the library. Private: a book is removed only
   when the Trash is emptied, the yes of a confirmed dialog
   (lib_ask_empty_trash) *)
fn _remove {i:int} (i: int i): void = let
  val c = lib_take()
  val+ ~LibCell(bs, k) = c
in
  if i < 0 then lib_put(LibCell(bs, k))
  else if k <= 0 then lib_put(LibCell(bs, k))
  else if i >= k then lib_put(LibCell(bs, k))
  else lib_put(LibCell(_remove_at(bs, i), k - 1))
end

(* Deletes the stored data under key letter c of book (h1, h2) *)
fn _idb_del {c:nat | c < 256} (c: int c, h1: int, h2: int): void = let
  val k = lib_key(c, h1, h2)
  val @(f, b) = $A.freeze<byte>(k)
  val () = $P.discard<Int>($IDB.idb_delete(b, 15))
in release_bytes(f, b) end

(* Sets book i's shelf, and keeps and shows the library *)
#pub fn lib_set_shelf {i:int} (i: int i, shelf: Int): void

implement lib_set_shelf (i, shelf) = let
  val () = lib_update(i, lam(x) => @{
    key = x.key, h1 = x.h1, h2 = x.h2, shelf = shelf, added = x.added, opened = x.opened,
    ch = x.ch, tch = x.tch, pg = x.pg, pgs = x.pgs, anchor = x.anchor,
    fsz = x.fsz, cover = x.cover, done = x.done, sidx = x.sidx, cols = x.cols })
  val () = lib_save()
in lib_render() end

(* Moves book i to the Trash at once: nothing of it is lost, and Undo
   (or Restore, from the Trash) puts it back on the shelf it was on *)
#pub fn lib_trash {i:int} (i: int i): void

implement lib_trash (i) =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) => let
      val key = x.key
      val was = x.shelf
      val () = lib_set_shelf(i, 3)
    in
      undo_offer("Moved to Trash", lam () => let
          val j = lib_index_of_key(key)
        in if j >= 0 then lib_set_shelf(j, was) else () end,
        lam () => ())
    end

(* Book i and everything stored for it, deleted *)
fn _delete_book {i:int} (i: int i): void =
  case+ lib_nums(i) of
  | ~$R.none() => ()
  | ~$R.some(x) => let
      val () = _idb_del(98, x.h1, x.h2)
      val () = _idb_del(99, x.h1, x.h2)
      val () = _idb_del(97, x.h1, x.h2)
      val () = _idb_del(121, x.h1, x.h2)
    in _remove(i) end

(* The index of the first book in the Trash from i on, or -1 *)
fun _first_trashed {i,k:nat | i <= k} .<k - i>. (i: int i, k: int k): [r:int | r >= ~1] int r =
  if i >= k then ~1
  else (case+ lib_nums(i) of
    | ~$R.none() => _first_trashed(i + 1, k)
    | ~$R.some(x) => if x.shelf = 3 then i else _first_trashed(i + 1, k))

(* Deletes the books in the Trash, at most n of them *)
fun _empty {n:nat} .<n>. (n: int n): void =
  if n <= 0 then ()
  else let
    val i = _first_trashed(0, lib_count())
  in
    if i < 0 then () else let val () = _delete_book(i) in _empty(n - 1) end
  end

(* Asks about h, with the action that does it; if the answer is yes, it
   is done, then after runs. HEmptyTrash: every book in the Trash and
   everything stored for it go (and any Undo offer, which could only
   put back what is gone) *)
#pub fn lib_ask_harm (h: harm, after: () -<cloref1> void): void

implement lib_ask_harm (h, after) =
  case+ h of
  | HEmptyTrash() => modal_confirm(h, lam () => let
      val () = undo_close()
      val () = _empty(lib_count())
    in after() end)

(* Each book's key and the shelf it was on *)
datatype shelved(int) =
  | ShelvedNil(0)
  | {n:nat} ShelvedCons(n + 1) of (int, Int, shelved(n))

fun _shelves {i,k:nat | i <= k}{m:nat} .<k - i>. (i: int i, k: int k, acc: shelved(m)): [r:nat] shelved(r) =
  if i >= k then acc
  else (case+ lib_nums(i) of
    | ~$R.none() => _shelves(i + 1, k, acc)
    | ~$R.some(x) => _shelves(i + 1, k, ShelvedCons(x.key, x.shelf, acc)))

(* Every book moved to the Trash (nothing of any is lost) *)
fun _trash_all {i,k:nat | i <= k} .<k - i>. (i: int i, k: int k): void =
  if i >= k then ()
  else let
    val () = lib_update(i, lam(x) => @{
      key = x.key, h1 = x.h1, h2 = x.h2, shelf = 3, added = x.added, opened = x.opened,
      ch = x.ch, tch = x.tch, pg = x.pg, pgs = x.pgs, anchor = x.anchor,
      fsz = x.fsz, cover = x.cover, done = x.done, sidx = x.sidx, cols = x.cols })
  in _trash_all(i + 1, k) end

(* Each book of ss put back on its shelf *)
fun _unshelve {n:nat} .<n>. (ss: shelved(n)): void =
  case+ ss of
  | ShelvedNil() => ()
  | ShelvedCons(key, shelf, rest) => let
      val j = lib_index_of_key(key)
      val () = (if j >= 0 then lib_update(j, lam(x) => @{
          key = x.key, h1 = x.h1, h2 = x.h2, shelf = shelf, added = x.added, opened = x.opened,
          ch = x.ch, tch = x.tch, pg = x.pg, pgs = x.pgs, anchor = x.anchor,
          fsz = x.fsz, cover = x.cover, done = x.done, sidx = x.sidx, cols = x.cols }) else ())
    in _unshelve(rest) end

(* A factory reset's part in the library: every book moved to the Trash,
   where it can still be restored. What it returns puts each back on the
   shelf it was on *)
#pub fn lib_trash_all (): () -<cloref1> void

implement lib_trash_all () = let
  val k = lib_count()
  val ss = _shelves(0, k, ShelvedNil())
  val () = _trash_all(0, k)
  val () = lib_save()
  val () = lib_render()
in lam () => let val () = _unshelve(ss) val () = lib_save() in lib_render() end end

(* ============================================================
   Sorting
   ============================================================ *)

fn _lower (c: int): int = if c >= 65 then (if c <= 90 then c + 32 else c) else c

(* a[0, an) before b[0, bn), letters in any case *)
fun _less {la,lb:agz}{an,bn:nat}{na,nb:nat | an <= na; bn <= nb}{i:nat | i <= an} .<an - i>.
  (a: !$A.arr(byte, la, na), an: int an, b: !$A.arr(byte, lb, nb), bn: int bn, i: int i): int =
  if i >= an then (if i >= bn then 0 else ~1)
  else if i >= bn then 1
  else let
    val x = _lower(byte2int0($A.get<byte>(a, i)))
    val y = _lower(byte2int0($A.get<byte>(b, i)))
  in if x < y then ~1 else if x > y then 1 else _less(a, an, b, bn, i + 1) end

(* Whether x comes before y in order o *)
fn _before (x: !book, y: !book, o: int): bool = let
  val+ Book(xt, xtn, xa, xan, xs, xsn, xn) = x
  val+ Book(yt, ytn, ya, yan, ys, ysn, yn) = y
in
  (* by series: each series together, in its numbers' order, then the
     books of none, by title *)
  if o = 4 then (if xsn > 0 then (if ysn > 0 then let
      val c = _less(xs, xsn, ys, ysn, 0)
    in
      if c < 0 then true else if c > 0 then false
      else if xn.sidx <> yn.sidx then xn.sidx < yn.sidx
      else _less(xt, xtn, yt, ytn, 0) < 0
    end else true)
    else (if ysn > 0 then false else _less(xt, xtn, yt, ytn, 0) < 0))
  else if o = 1 then _less(xt, xtn, yt, ytn, 0) < 0
  else if o = 2 then let
    val c = _less(xa, xan, ya, yan, 0)
  in if c < 0 then true else if c > 0 then false else _less(xt, xtn, yt, ytn, 0) < 0 end
  else if o = 3 then xn.added > yn.added
  else (if xn.opened <> yn.opened then xn.opened > yn.opened else xn.added > yn.added)
end

fun _insert {k:nat} .<k>. (x: book, bs: books(k), o: int): books(k + 1) =
  case+ bs of
  | ~books_nil() => books_cons(x, books_nil())
  | ~books_cons(y, rest) =>
    if _before(x, y, o) then books_cons(x, books_cons(y, rest))
    else books_cons(y, _insert(x, rest, o))

fun _sort {k,a:nat} .<k>. (bs: books(k), acc: books(a), o: int): books(k + a) =
  case+ bs of
  | ~books_nil() => acc
  | ~books_cons(x, rest) => _sort(rest, _insert(x, acc, o), o)

(* Sorts the library in order o (and keeps o for later sorts) *)
#pub fn lib_sort (o: int): void

implement lib_sort (o) = let
  val () = !_sort_order := o
  val c = lib_take()
  val+ ~LibCell(bs, k) = c
in lib_put(LibCell(_sort(bs, books_nil(), o), k)) end

(* ============================================================
   Collections: a reader's own groups of books
   ============================================================ *)

(* At most COLL_MAX collections, each named by 1 to COLL_NAME bytes (in
   an array one longer). A book is in collection j when bit j of its
   cols is set, and can be in any number of them *)
#pub stadef COLL_MAX = 8
#pub stadef COLL_NAME = 40

datavtype colls(int) =
  | colls_nil(0) of ()
  | {k:nat}{l:agz}{m:pos | m <= COLL_NAME} colls_cons(k + 1) of ($A.arr(byte, l, m + 1), int m, colls(k))

datavtype coll_cell =
  | {k:nat | k <= COLL_MAX} CollCell of (colls(k), int k)

val _colls = ref<coll_cell>(CollCell(colls_nil(), 0))

(* The collection the library view shows, -1 for none: every book *)
val _coll_shown = ref<int>(~1)

fun colls_free {k:nat} .<k>. (cs: colls(k)): void =
  case+ cs of
  | ~colls_nil() => ()
  | ~colls_cons(a, _, rest) => let val () = $A.free<byte>(a) in colls_free(rest) end

fn colls_take (): coll_cell = let
  var c: coll_cell = CollCell(colls_nil(), 0)
  val () = ref_exch_elt<coll_cell>(_colls, c)
in c end

fn colls_put (c: coll_cell): void = let
  var cur: coll_cell = c
  val () = ref_exch_elt<coll_cell>(_colls, cur)
  val+ ~CollCell(cs, _) = cur
in colls_free(cs) end

#pub fn lib_coll_count (): [k:nat | k <= COLL_MAX] int k
implement lib_coll_count () = let
  val c = colls_take()
  val+ CollCell(_, k) = c
  val () = colls_put(c)
in k end

(* Where a name typed into b[0, k) starts: past the spaces before it *)
fun _name_start {l:agz}{m:pos}{k:nat | k <= m}{i:nat | i <= k} .<k - i>.
  (b: !$A.arr(byte, l, m), k: int k, i: int i): [s:nat | i <= s; s <= k] int s =
  if i >= k then i
  else if byte2int0($A.get<byte>(b, i)) <= 32 then _name_start(b, k, i + 1)
  else i

(* Where it ends: before the spaces after it *)
fun _name_end {l:agz}{m:pos}{s,e:nat | s <= e; e <= m} .<e - s>.
  (b: !$A.arr(byte, l, m), s: int s, e: int e): [r:nat | s <= r; r <= e] int r =
  if e <= s then e
  else if byte2int0($A.get<byte>(b, e - 1)) <= 32 then _name_end(b, s, e - 1)
  else e

(* n, or fewer, so that the n bytes from s (of t there) do not end
   inside a letter: the byte after them does not continue one *)
fun _name_cut {l:agz}{m:pos}{s,n,t:nat | n <= t; s + t <= m} .<n>.
  (b: !$A.arr(byte, l, m), s: int s, n: int n, t: int t): [r:nat | r <= n] int r =
  if n >= t then n
  else if n <= 0 then 0
  else let
    val c = byte2int0($A.get<byte>(b, s + n))
  in if c >= 128 && c < 192 then _name_cut(b, s, n - 1, t) else n end

fun _copy_from {ls,ld:agz}{ms,nd:nat}{s,n:nat | s + n <= ms; n <= nd}{j:nat | j <= n} .<n - j>.
  (src: !$A.arr(byte, ls, ms), s: int s, n: int n, dst: !$A.arr(byte, ld, nd), j: int j): void =
  if j >= n then ()
  else let
    val () = $A.set<byte>(dst, j, $A.get<byte>(src, s + j))
  in _copy_from(src, s, n, dst, j + 1) end

(* t bytes, or a name's most *)
fn _most {t:nat} (t: int t): [x:nat | x <= t; x <= COLL_NAME] int x = if t > 40 then 40 else t

(* The name typed into b[0, k), made a collection's: without the spaces
   around it, and cut to COLL_NAME bytes between letters; 0 bytes when
   nothing is left *)
fn _coll_name {l:agz}{m:pos}{k:nat | k <= m} (b: !$A.arr(byte, l, m), k: int k)
  : [la:agz][n:nat | n <= COLL_NAME] @($A.arr(byte, la, n + 1), int n) = let
  val s = _name_start(b, k, 0)
  val e = _name_end(b, s, k)
  val t = e - s
  val n = _name_cut(b, s, _most(t), t)
  val a = $A.alloc<byte>(n + 1)
  val () = _copy_from(b, s, n, a, 0)
in @(a, n) end

fun _colls_insert {k:nat}{l:agz}{m:pos | m <= COLL_NAME} .<k>.
  (cs: colls(k), j: int, a: $A.arr(byte, l, m + 1), m: int m): colls(k + 1) =
  if j <= 0 then colls_cons(a, m, cs)
  else case+ cs of
  | ~colls_nil() => colls_cons(a, m, colls_nil())
  | ~colls_cons(x, xm, rest) => colls_cons(x, xm, _colls_insert(rest, j - 1, a, m))

(* cs without its collection j, and that collection's name *)
fun _colls_remove {k:pos}{j:nat | j < k} .<k>. (cs: colls(k), j: int j)
  : [l:agz][m:pos | m <= COLL_NAME] @(colls(k - 1), $A.arr(byte, l, m + 1), int m) = let
  val+ ~colls_cons(x, xm, rest) = cs
in
  if j = 0 then @(rest, x, xm)
  else let
    val @(r, a, am) = _colls_remove(rest, j - 1)
  in @(colls_cons(x, xm, r), a, am) end
end

(* cs with collection j named a[0, m) instead *)
fun _colls_rename {k:nat}{l:agz}{m:pos | m <= COLL_NAME} .<k>.
  (cs: colls(k), j: int, a: $A.arr(byte, l, m + 1), m: int m): colls(k) =
  case+ cs of
  | ~colls_nil() => let val () = $A.free<byte>(a) in colls_nil() end
  | ~colls_cons(x, xm, rest) =>
    if j = 0 then let val () = $A.free<byte>(x) in colls_cons(a, m, rest) end
    else colls_cons(x, xm, _colls_rename(rest, j - 1, a, m))

(* Every book's collections, as f makes them from its key and its
   collections now *)
fun _map_cols {k:nat} .<k>. (bs: !books(k), f: (Int, Int) -<cloref1> Int): void =
  case+ bs of
  | books_nil() => ()
  | @books_cons(b, rest) => let
      val+ @Book(_, _, _, _, _, _, x) = b
      val c = f(x.key, x.cols)
      val () = x := @{
        key = x.key, h1 = x.h1, h2 = x.h2, shelf = x.shelf, added = x.added, opened = x.opened,
        ch = x.ch, tch = x.tch, pg = x.pg, pgs = x.pgs, anchor = x.anchor,
        fsz = x.fsz, cover = x.cover, done = x.done, sidx = x.sidx, cols = c }
      prval () = fold@(b)
      val () = _map_cols(rest, f)
      prval () = fold@(bs)
    in end

fn _map_all_cols (f: (Int, Int) -<cloref1> Int): void = let
  val c = lib_take()
  val+ @LibCell(bs, _) = c
  val () = _map_cols(bs, f)
  prval () = fold@(c)
in lib_put(c) end

(* Collection j's bit *)
fn _bit (j: int): Int = g1ofg0($AR.bsl_int_int(1, j))

(* The bits of cols below j *)
fn _below (cols: int, j: int): int = $AR.band_int_int(cols, $AR.sub_int_int($AR.bsl_int_int(1, j), 1))

(* cols without bit j, the bits above it moved down one *)
fn _drop_bit (cols: Int, j: int): Int = let
  val c = g0ofg1(cols)
  val hi = $AR.bsl_int_int($AR.bsr_int_int(c, j + 1), j)
in g1ofg0($AR.add_int_int(_below(c, j), hi)) end

(* cols with a bit j put in (set when on), the bits from j moved up one *)
fn _put_bit (cols: Int, j: int, on: bool): Int = let
  val c = g0ofg1(cols)
  val hi = $AR.bsl_int_int($AR.bsr_int_int(c, j), j + 1)
  val b = (if on then $AR.bsl_int_int(1, j) else 0): int
in g1ofg0($AR.add_int_int($AR.add_int_int(_below(c, j), hi), b)) end

(* The keys of the books in collection j, onto acc *)
datatype keys(int) =
  | KeysNil(0)
  | {n:nat} KeysCons(n + 1) of (Int, keys(n))

fun _keys_in {k:nat}{m:nat} .<k>. (bs: !books(k), j: int, acc: keys(m)): [r:nat] keys(r) =
  case+ bs of
  | books_nil() => acc
  | books_cons(b, rest) => let
      val+ Book(_, _, _, _, _, _, x) = b
    in
      if $AR.band_int_int(x.cols, _bit(j)) <> 0 then _keys_in(rest, j, KeysCons(x.key, acc))
      else _keys_in(rest, j, acc)
    end

fun _keys_has {n:nat} .<n>. (ks: keys(n), key: Int): bool =
  case+ ks of
  | KeysNil() => false
  | KeysCons(x, rest) => if x = key then true else _keys_has(rest, key)

(* The collection the library view shows, or -1 *)
#pub fn lib_coll_shown (): int
implement lib_coll_shown () = !_coll_shown

(* Whether book numbers x are in the collection shown (in any, when
   none is) *)
fn _in_shown (x: bnums): bool = let
  val j = !_coll_shown
in if j < 0 then true else $AR.band_int_int(x.cols, _bit(j)) <> 0 end

(* The name of a collection just deleted, while its Undo is offered *)
datavtype coll_gone =
  | {l:agz}{m:pos | m <= COLL_NAME} CollGone of ($A.arr(byte, l, m + 1), int m)
  | CollNotGone of ()

val _coll_gone = ref<coll_gone>(CollNotGone())
(* Whether _coll_gone holds a name *)
val _coll_gone_held = ref<bool>(false)

fn _gone_take (): coll_gone = let
  val () = !_coll_gone_held := false
  var g: coll_gone = CollNotGone()
  val () = ref_exch_elt<coll_gone>(_coll_gone, g)
in g end

fn _gone_free (g: coll_gone): void =
  case+ g of
  | ~CollGone(a, _) => $A.free<byte>(a)
  | ~CollNotGone() => ()

fn _gone_put (g: coll_gone): void = let
  val () = !_coll_gone_held := (case+ g of CollGone(_, _) => true | CollNotGone() => false)
  var cur: coll_gone = g
  val () = ref_exch_elt<coll_gone>(_coll_gone, cur)
in _gone_free(cur) end

(* Makes a collection named by what was typed, b[0, k) (see _coll_name):
   its number, or -1 when there are COLL_MAX already or no name is
   left *)
#pub fn lib_coll_add {l:agz}{m:pos}{k:nat | k <= m} (b: $A.arr(byte, l, m), k: int k): int

implement lib_coll_add (b, k) = let
  val @(a, n) = _coll_name(b, k)
  val () = $A.free<byte>(b)
  (* a deleted collection's Undo would put it back among numbers that
     have moved on: it is made final first *)
  val () = (if !_coll_gone_held then undo_close() else ())
  val c = colls_take()
  val+ ~CollCell(cs, cn) = c
in
  if n <= 0 then let
    val () = $A.free<byte>(a)
    val () = colls_put(CollCell(cs, cn))
  in ~1 end
  else if cn >= 8 then let
    val () = $A.free<byte>(a)
    val () = colls_put(CollCell(cs, cn))
  in ~1 end
  else let
    val () = colls_put(CollCell(_colls_insert(cs, cn, a, n), cn + 1))
    val () = lib_save()
  in cn end
end

(* Names collection j by what was typed, b[0, k) (kept when no name is
   left) *)
#pub fn lib_coll_rename {l:agz}{m:pos}{k:nat | k <= m} (j: int, b: $A.arr(byte, l, m), k: int k): void

implement lib_coll_rename (j, b, k) = let
  val @(a, n) = _coll_name(b, k)
  val () = $A.free<byte>(b)
in
  if n <= 0 then $A.free<byte>(a)
  else let
    val c = colls_take()
    val+ ~CollCell(cs, cn) = c
    val () = colls_put(CollCell(_colls_rename(cs, j, a, n), cn))
    val () = lib_save()
  in lib_render() end
end

(* Whether a[0, m) and b[0, m) are the same bytes *)
fun _same {la,lb:agz}{na,nb:nat}{m:nat | m <= na; m <= nb}{j:nat | j <= m} .<m - j>.
  (a: !$A.arr(byte, la, na), b: !$A.arr(byte, lb, nb), m: int m, j: int j): bool =
  if j >= m then true
  else if byte2int0($A.get<byte>(a, j)) <> byte2int0($A.get<byte>(b, j)) then false
  else _same(a, b, m, j + 1)

(* The number of the collection named a[0, n) in cs (from j), or -1 *)
fun _colls_find {k:nat}{l:agz}{n:nat} .<k>. (cs: !colls(k), a: !$A.arr(byte, l, n + 1), n: int n, j: int): int =
  case+ cs of
  | colls_nil() => ~1
  | @colls_cons(x, m, rest) => let
      val hit = (if m = n then _same(x, a, n, 0) else false): bool
      val r = (if hit then j else _colls_find(rest, a, n, j + 1)): int
      prval () = fold@(cs)
    in r end

(* The collection named by b[0, k) (as a name typed is, see _coll_name):
   its number, made when there is none so named and there is room; -1
   when there is no room or no name. For a backup's collections *)
#pub fn lib_coll_find_or_add {l:agz}{m:pos}{k:nat | k <= m} (b: $A.arr(byte, l, m), k: int k): int

implement lib_coll_find_or_add (b, k) = let
  val @(a, n) = _coll_name(b, k)
  val c = colls_take()
  val+ @CollCell(cs, _) = c
  val j = (if n > 0 then _colls_find(cs, a, n, 0) else ~1): int
  prval () = fold@(c)
  val () = colls_put(c)
  val () = $A.free<byte>(a)
in if j >= 0 then let val () = $A.free<byte>(b) in j end else lib_coll_add(b, k) end

(* Collection j's name: its bytes (one more) and how many; 0 when there
   is no collection j *)
fun _name_copy {k:nat} .<k>. (cs: !colls(k), j: int): [l:agz][n:nat | n <= COLL_NAME] @($A.arr(byte, l, n + 1), int n) =
  case+ cs of
  | colls_nil() => let val a0 = $A.alloc<byte>(1) in @(a0, 0) end
  | @colls_cons(a, m, rest) =>
    if j = 0 then let
      val t = $A.alloc<byte>(m + 1)
      val () = _copy(a, m, t, 0, 0)
      val mm = m
      prval () = fold@(cs)
    in @(t, mm) end
    else let
      val r = _name_copy(rest, j - 1)
      prval () = fold@(cs)
    in r end

#pub fn lib_coll_name_copy (j: int): [l:agz][n:nat | n <= COLL_NAME] @($A.arr(byte, l, n + 1), int n)

implement lib_coll_name_copy (j) = let
  val c = colls_take()
  val+ @CollCell(cs, _) = c
  val r = _name_copy(cs, j)
  prval () = fold@(c)
  val () = colls_put(c)
in r end

(* Whether book i is in collection j *)
#pub fn lib_coll_has {i:int} (i: int i, j: int): bool

implement lib_coll_has (i, j) =
  if j < 0 then false
  else case+ lib_nums(i) of
  | ~$R.none() => false
  | ~$R.some(x) => $AR.band_int_int(x.cols, _bit(j)) <> 0

(* Puts book i in collection j, or takes it out when it is in it *)
#pub fn lib_coll_toggle {i:int} (i: int i, j: int): void

implement lib_coll_toggle (i, j) =
  if j < 0 then ()
  else if j >= lib_coll_count() then ()
  else let
    val on = lib_coll_has(i, j)
    val () = lib_update(i, lam(x) => @{
      key = x.key, h1 = x.h1, h2 = x.h2, shelf = x.shelf, added = x.added, opened = x.opened,
      ch = x.ch, tch = x.tch, pg = x.pg, pgs = x.pgs, anchor = x.anchor,
      fsz = x.fsz, cover = x.cover, done = x.done, sidx = x.sidx,
      cols = (if on then x.cols - _bit(j) else x.cols + _bit(j)) })
  in lib_save() end

(* Collection j deleted, with an Undo offer that puts it back: its books
   stay where they are, only the group goes *)
#pub fn lib_coll_delete (j: int): void

(* Puts collection j back (named as it was), with the books whose keys
   are ks in it *)
fn _coll_restore (j: int, ks: [n:nat] keys(n)): void =
  case+ _gone_take() of
  | ~CollNotGone() => ()
  | ~CollGone(a, am) => let
      val c = colls_take()
      val+ ~CollCell(cs, cn) = c
    in
      if cn >= 8 then let
        val () = $A.free<byte>(a)
      in colls_put(CollCell(cs, cn)) end
      else let
        val () = colls_put(CollCell(_colls_insert(cs, j, a, am), cn + 1))
        val () = _map_all_cols(lam(key, cols) => _put_bit(cols, j, _keys_has(ks, key)))
        val () = lib_save()
      in lib_render() end
    end

implement lib_coll_delete (j) = let
  val j = g1ofg0(j)
  val c = colls_take()
  val+ ~CollCell(cs, cn) = c
in
  if j < 0 then colls_put(CollCell(cs, cn))
  else if j >= cn then colls_put(CollCell(cs, cn))
  else let
    val @(rest, a, am) = _colls_remove(cs, j)
    val () = colls_put(CollCell(rest, cn - 1))
    val lc = lib_take()
    val+ @LibCell(bs, _) = lc
    val ks = _keys_in(bs, j, KeysNil())
    prval () = fold@(lc)
    val () = lib_put(lc)
    val () = _map_all_cols(lam(_, cols) => _drop_bit(cols, j))
    val s = !_coll_shown
    val () = !_coll_shown := (if s = j then ~1 else if s > j then s - 1 else s)
    val () = _gone_put(CollGone(a, am))
    val () = lib_save()
    val () = lib_render()
  in undo_offer("Collection deleted", lam () => _coll_restore(j, ks), lam () => _gone_put(CollNotGone())) end
end

(* Shows collection j's books only, or every book for -1 *)
#pub fn lib_coll_show (j: int): void

implement lib_coll_show (j) = let
  val () = !_coll_shown := (if j >= 0 then (if j < lib_coll_count() then j else ~1) else ~1)
in lib_render() end

(* The library's collection chips: each collection, pressed when it is
   the one shown *)
fun _chips {k:nat}{j:nat} .<k>. (cs: !colls(k), j: int j, shown: int): void =
  case+ cs of
  | colls_nil() => ()
  | @colls_cons(a, m, rest) => let
      val jj = j
      val @(bi, bl) = nid_make("collection", jj)
      val () = ui_btn_n("collection-chips", bi, bl, "sbtn")
      val t = $A.alloc<byte>(m + 1)
      val () = _copy(a, m, t, 0, 0)
      val @(bi, bl) = nid_make("collection", jj)
      val () = ui_text_n_buf(bi, bl, t, m)
      val @(bi, bl) = nid_make("collection", jj)
      val () = (if j = shown then ui_attr_n(bi, bl, APressed, "true") else ui_attr_n(bi, bl, APressed, "false"))
      val () = _chips(rest, j + 1, shown)
      prval () = fold@(cs)
    in end

(* The collection row: shown when there is a collection, with every
   book's chip and each collection's; renaming and deleting are offered
   for the one shown *)
fn _coll_row (): void = let
  val () = ui_clear("collection-chips")
  val c = colls_take()
  val+ @CollCell(cs, cn) = c
  val shown = !_coll_shown
  val () = ui_text_btn("collection-chips", "collection-all", "sbtn", "All books")
  val () = (if shown < 0 then ui_attr("collection-all", APressed, "true") else ui_attr("collection-all", APressed, "false"))
  val () = _chips(cs, 0, shown)
  val count = cn
  prval () = fold@(c)
  val () = colls_put(c)
  val () = ui_show("collection-row", count > 0)
  val () = ui_show("collection-rename", shown >= 0)
in ui_show("collection-delete", shown >= 0) end

(* The collections panel's toggles for a book in the collections cols
   says *)
fun _toggles {k:nat}{j:nat} .<k>. (cs: !colls(k), j: int j, cols: Int): void =
  case+ cs of
  | colls_nil() => ()
  | @colls_cons(a, m, rest) => let
      val jj = j
      val @(bi, bl) = nid_make("collection-put", jj)
      val () = ui_btn_n("collections-list", bi, bl, "sbtn")
      val t = $A.alloc<byte>(m + 1)
      val () = _copy(a, m, t, 0, 0)
      val @(bi, bl) = nid_make("collection-put", jj)
      val () = ui_text_n_buf(bi, bl, t, m)
      val @(bi, bl) = nid_make("collection-put", jj)
      val () = (if $AR.band_int_int(cols, _bit(j)) <> 0 then ui_attr_n(bi, bl, APressed, "true") else ui_attr_n(bi, bl, APressed, "false"))
      val () = _toggles(rest, j + 1, cols)
      prval () = fold@(cs)
    in end

(* The collections panel for book i: a toggle for each collection,
   pressed when the book is in it *)
#pub fn lib_coll_panel {i:int} (i: int i): void

implement lib_coll_panel (i) = let
  val () = ui_clear("collections-list")
  val cols = (case+ lib_nums(i) of ~$R.none() => 0 | ~$R.some(x) => x.cols): Int
  val c = colls_take()
  val+ @CollCell(cs, cn) = c
  val () = _toggles(cs, 0, cols)
  val count = cn
  prval () = fold@(c)
  val () = colls_put(c)
  val () = ui_show("collections-new", count < 8)
in ui_show("collections-none", count = 0) end

(* Collection j's name, in the dialog's name field *)
fun _name_at {k:nat} .<k>. (cs: !colls(k), j: int): void =
  case+ cs of
  | colls_nil() => ()
  | @colls_cons(a, m, rest) =>
    if j = 0 then let
      val t = $A.alloc<byte>(m + 1)
      val () = _copy(a, m, t, 0, 0)
      val () = modal_name_set(t, m)
      prval () = fold@(cs)
    in end
    else let
      val () = _name_at(rest, j - 1)
      prval () = fold@(cs)
    in end

#pub fn lib_coll_name_show (j: int): void

implement lib_coll_name_show (j) = let
  val c = colls_take()
  val+ @CollCell(cs, _) = c
  val () = _name_at(cs, j)
  prval () = fold@(c)
in colls_put(c) end

(* ============================================================
   Storage: key "lib"
   ============================================================ *)

(* "QLB3", the collections (u8 count, then each name: u8 length,
   bytes), then each book: id (2 x i32), title (u8 length, bytes),
   author (u8 length, bytes), then 10 x i32: shelf, added, opened, ch,
   tch, pg, pgs, anchor, fsz, cover | done << 8; its series (u8 length,
   bytes) and its number in it (i32); the collections it is in (i32).
   At most 824 bytes a book. QLB2 has no collections, before or in the
   books; QLB1 has no series either. *)



fun _put_bytes {ls,l:agz}{la:addr}{ns,ms:nat | ns <= ms}{n:nat}{p:nat | p + ns <= n}{j:nat | j <= ns} .<ns - j>.
  (src: !$A.arr(byte, ls, ms), ns: int ns, out: !$A.arrx(byte, l, n, la), p: int p, j: int j): void =
  if j >= ns then ()
  else let
    val () = $A.write_byte(out, p + j, $AR.low_byte(byte2int0($A.get<byte>(src, j))))
  in _put_bytes(src, ns, out, p, j + 1) end

fun _ser_names {l:agz}{la:addr}{n:int}{j:nat}{p:nat | p + 41 * j <= n} .<j>.
  (out: !$A.arrx(byte, l, n, la), p: int p, cs: !colls(j)): [q:nat | q <= p + 41 * j] int q =
  case+ cs of
  | colls_nil() => p
  | @colls_cons(a, m, rest) => let
      val () = $A.write_byte(out, p, m)
      val () = _put_bytes(a, m, out, p + 1, 0)
      val q = _ser_names(out, p + 1 + m, rest)
      prval () = fold@(cs)
    in q end

fun _ser {l:agz}{la:addr}{n:int}{j:nat}{p:nat | p + 824 * j <= n} .<j>.
  (out: !$A.arrx(byte, l, n, la), p: int p, bs: !books(j)): [q:nat | q <= n] int q =
  case+ bs of
  | books_nil() => p
  | books_cons(b, rest) => let
      val+ Book(t, tn, a, an, sr, sn, x) = b
      val () = $A.write_i32(out, p, x.h1)
      val () = $A.write_i32(out, p + 4, x.h2)
      val () = $A.write_byte(out, p + 8, tn)
      val () = _put_bytes(t, tn, out, p + 9, 0)
      val q = p + 9 + tn
      val () = $A.write_byte(out, q, an)
      val () = _put_bytes(a, an, out, q + 1, 0)
      val q = q + 1 + an
      val () = $A.write_i32(out, q, x.shelf)
      val () = $A.write_i32(out, q + 4, x.added)
      val () = $A.write_i32(out, q + 8, x.opened)
      val () = $A.write_i32(out, q + 12, x.ch)
      val () = $A.write_i32(out, q + 16, x.tch)
      val () = $A.write_i32(out, q + 20, x.pg)
      val () = $A.write_i32(out, q + 24, x.pgs)
      val () = $A.write_i32(out, q + 28, x.anchor)
      val () = $A.write_i32(out, q + 32, x.fsz)
      val () = $A.write_i32(out, q + 36, x.cover + x.done * 256)
      (* QLB2: the series' name and the book's number in it *)
      val q = q + 40
      val () = $A.write_byte(out, q, sn)
      val () = _put_bytes(sr, sn, out, q + 1, 0)
      val () = $A.write_i32(out, q + 1 + sn, x.sidx)
      (* QLB3: the collections it is in *)
      val () = $A.write_i32(out, q + 5 + sn, x.cols)
    in _ser(out, q + 9 + sn, rest) end

(* Stores the library under "lib" *)
#pub fn lib_save (): void

implement lib_save () = let
  val c = lib_take()
  val+ @LibCell(bs, k) = c
  val cc = colls_take()
  val+ @CollCell(cs, cn) = cc
  val n = 333 + 824 * k
in
  case+ piece_new(n) of
  | ~NoPiece() => let
      prval () = fold@(cc)
      val () = colls_put(cc)
      prval () = fold@(c)
    in lib_put(c) end
  | ~Piece(ow, out) => let
      val () = $A.write_text(out, 0, $A.text_lit("QLB3"), 4)
      val () = $A.write_byte(out, 4, cn)
      val q = _ser_names(out, 5, cs)
      prval () = fold@(cc)
      val () = colls_put(cc)
      val m = _ser(out, q, bs)
      prval () = fold@(c)
      val () = lib_put(c)
      val @(f, b) = $A.freeze<byte>(out)
      val @(used, rest) = $A.borrow_split<byte>(f, b, m)
      val ka = $A.alloc<byte>(3)
      val () = $A.write_text(ka, 0, $A.text_lit("lib"), 3)
      val @(kf, kb) = $A.freeze<byte>(ka)
      val () = $P.discard<Int>($IDB.idb_put(kb, 3, used, m))
      val () = release_bytes(kf, kb)
      val b = $A.borrow_join<byte>(f, used, rest)
      val () = $A.drop<byte>(f, b)
    in piece_free(ow, $A.thaw<byte>(f)) end
end

(* The little-endian int at buf[p, p + 4) *)
fn _i32 {l:agz}{la:addr}{n:nat}{p:nat | p + 4 <= n}
  (buf: !$A.arrx(byte, l, n, la), p: int p): Int = let
  val b0 = $AR.low_byte(byte2int0($A.get<byte>(buf, p)))
  val b1 = $AR.low_byte(byte2int0($A.get<byte>(buf, p + 1)))
  val b2 = $AR.low_byte(byte2int0($A.get<byte>(buf, p + 2)))
  val b3 = $AR.low_byte(byte2int0($A.get<byte>(buf, p + 3)))
  val hi = (if b3 < 128 then b3 else b3 - 256): [h:int | ~128 <= h; h < 128] int h
in b0 + b1 * 256 + b2 * 65536 + hi * 16777216 end

(* buf[p, p + m) into out[0, m), out being longer *)
fun _bytes_of_into {l:agz}{la:addr}{n:nat}{p,m:nat | p + m <= n}{lo:agz}{no:pos | m < no}{j:nat | j <= m} .<m - j>.
  (buf: !$A.arrx(byte, l, n, la), p: int p, m: int m, out: !$A.arr(byte, lo, no), j: int j): void =
  if j >= m then ()
  else let
    val () = $A.set<byte>(out, j, $A.get<byte>(buf, p + j))
  in _bytes_of_into(buf, p, m, out, j + 1) end

fun _bytes_of {l:agz}{la:addr}{n:nat}{p,m:nat | p + m <= n}{lo:agz}{j:nat | j <= m} .<m - j>.
  (buf: !$A.arrx(byte, l, n, la), p: int p, m: int m, out: !$A.arr(byte, lo, m), j: int j): void =
  if j >= m then ()
  else let
    val () = $A.set<byte>(out, j, $A.get<byte>(buf, p + j))
  in _bytes_of(buf, p, m, out, j + 1) end

(* The books stored in buf[p, n), read from an earlier run's bytes and
   checked here, once; onto acc (at most LIB_MAX) *)
fun _parse {l:agz}{la:addr}{n:nat}{p:nat | p <= n}{a:nat | a <= LIB_MAX} .<n - p>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, acc: books(a), a: int a, v: int)
  : [k:nat | k <= LIB_MAX] @(books(k), int k) =
  if a >= 100000 then @(acc, a)
  else if p + 9 > n then @(acc, a)
  else let
    val h1 = _i32(buf, p)
    val h2 = _i32(buf, p + 4)
    val tn = $AR.low_byte(byte2int0($A.get<byte>(buf, p + 8)))
  in
    if tn <= 0 then @(acc, a)
    else if p + 9 + tn + 1 > n then @(acc, a)
    else let
      val q = p + 9 + tn
      val an = $AR.low_byte(byte2int0($A.get<byte>(buf, q)))
    in
      if an <= 0 then @(acc, a)
      else if q + 1 + an + 40 > n then @(acc, a)
      else let
        val t = $A.alloc<byte>(tn)
        val () = _bytes_of(buf, p + 9, tn, t, 0)
        val au = $A.alloc<byte>(an)
        val () = _bytes_of(buf, q + 1, an, au, 0)
        val r = q + 1 + an
        val key = !_next_key
        val () = !_next_key := key + 1
        val cd = _i32(buf, r + 36)
        val nums = @{
          key = key, h1 = h1, h2 = h2,
          shelf = _i32(buf, r), added = _i32(buf, r + 4), opened = _i32(buf, r + 8),
          ch = _i32(buf, r + 12), tch = _i32(buf, r + 16), pg = _i32(buf, r + 20),
          pgs = _i32(buf, r + 24), anchor = _i32(buf, r + 28), fsz = _i32(buf, r + 32),
          cover = $AR.low_byte(cd), done = $AR.band_g1($AR.low_byte($AR.bsr_int_int(cd, 8)), 1),
          sidx = 0, cols = 0
        }: bnums
        (* QLB2 has the series after; QLB3, then the collections; QLB1,
           neither *)
        val r = r + 40
        val sn = (if v >= 2 then (if r < n then $AR.low_byte(byte2int0($A.get<byte>(buf, r))) else 0) else 0): [m:nat | m < 256] int m
        val tail = (if v >= 3 then 9 else 5): [e:int | e == 5 || e == 9] int e
      in
        if v < 2 then _parse(buf, n, r, books_cons(Book(t, tn, au, an, $A.alloc<byte>(1), 0, nums), acc), a + 1, v)
        else if r + tail + sn > n then let
          val () = $A.free<byte>(t)
          val () = $A.free<byte>(au)
        in @(acc, a) end
        else let
          val sr = $A.alloc<byte>(sn + 1)
          val () = _bytes_of_into(buf, r + 1, sn, sr, 0)
          val nums = @{
            key = nums.key, h1 = nums.h1, h2 = nums.h2, shelf = nums.shelf, added = nums.added,
            opened = nums.opened, ch = nums.ch, tch = nums.tch, pg = nums.pg, pgs = nums.pgs,
            anchor = nums.anchor, fsz = nums.fsz, cover = nums.cover, done = nums.done,
            sidx = _i32(buf, r + 1 + sn),
            cols = (if v >= 3 then (if r + 9 + sn <= n then g1ofg0($AR.band_int_int(_i32(buf, r + 5 + sn), 255)) else 0) else 0): Int
          }: bnums
        in _parse(buf, n, r + tail + sn, books_cons(Book(t, tn, au, an, sr, sn, nums), acc), a + 1, v) end
      end
    end
  end

(* The collections stored in buf[p, n), left of them still to read,
   after acc's k: where the books start, and the collections *)
fun _parse_names {l:agz}{la:addr}{n:nat}{p:nat | p <= n}{k:nat | k <= COLL_MAX} .<COLL_MAX - k>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, left: int, acc: colls(k), k: int k)
  : [q:nat | q <= n][r:nat | r <= COLL_MAX] @(int q, colls(r), int r) =
  if left <= 0 then @(p, acc, k)
  else if k >= 8 then @(p, acc, k)
  else if p + 1 > n then @(p, acc, k)
  else let
    val m = $AR.low_byte(byte2int0($A.get<byte>(buf, p)))
  in
    if m <= 0 then @(p, acc, k)
    else if m > 40 then @(p, acc, k)
    else if p + 1 + m > n then @(p, acc, k)
    else let
      val a = $A.alloc<byte>(m + 1)
      val () = _bytes_of_into(buf, p + 1, m, a, 0)
    in _parse_names(buf, n, p + 1 + m, left - 1, _colls_insert(acc, k, a, m), k + 1) end
  end

(* The collections of a library stored as version v in buf[0, n),
   and where its books start *)
fn _names_of {l:agz}{la:addr}{n:nat | n >= 4}
  (buf: !$A.arrx(byte, l, n, la), n: int n, v: int)
  : [q:nat | q <= n][r:nat | r <= COLL_MAX] @(int q, colls(r), int r) =
  if v < 3 then @(4, colls_nil(), 0)
  else if n <= 4 then @(n, colls_nil(), 0)
  else _parse_names(buf, n, 5, byte2int0($A.get<byte>(buf, 4)), colls_nil(), 0)

(* Reads the library stored under "lib"; the promise resolves with the
   number of books *)
#pub fn lib_load (): $P.promise(int, $P.Chained)

implement lib_load () = let
  val ka = $A.alloc<byte>(3)
  val () = $A.write_text(ka, 0, $A.text_lit("lib"), 3)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val p = $IDB.idb_get(kb, 3)
  val () = release_bytes(kf, kb)
in
  $P.and_then<Int><int>($P.vow(p), lam(h) =>
    case+ take_content(h) of
    | ~NoContentBytes() => $P.ret<int>(0)
    | ~ContentBytes(ow, buf, n) =>
      if n < 4 then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(buf, 0)) <> 81 then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(buf, 3)) < 49 then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(buf, 3)) > 51 then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else let
        val v = byte2int0($A.get<byte>(buf, 3)) - 48
        val @(p, cs, cn) = _names_of(buf, n, v)
        val () = colls_put(CollCell(cs, cn))
        val @(bs, k) = _parse(buf, n, p, books_nil(), 0, v)
        val () = piece_free(ow, buf)
        val () = lib_put(LibCell(_sort(bs, books_nil(), !_sort_order), k))
      in $P.ret<int>(k) end)
end

(* ============================================================
   The search query
   ============================================================ *)

(* The library view shows only the books whose title or author has
   q[0, n) in it (letters in any case); an empty query shows all *)
#pub fn lib_query_set {l:agz}{m:pos}{n:nat | n <= m} (q: $A.arr(byte, l, m), n: int n): void

fun _lowcopy {ls,ld:agz}{m,n:nat | n <= m}{i:nat | i <= n} .<n - i>.
  (q: !$A.arr(byte, ls, m), d: !$A.arr(byte, ld, n), n: int n, i: int i): void =
  if i >= n then ()
  else let
    val c = $AR.low_byte(byte2int0($A.get<byte>(q, i)))
    val c = (if c >= 65 then (if c <= 90 then c + 32 else c) else c): [c:nat | c < 256] int c
    val () = $A.set<byte>(d, i, $A.int2byte(c))
  in _lowcopy(q, d, n, i + 1) end

implement lib_query_set (q, n) =
  if n <= 0 then let val () = $A.free<byte>(q) in query_put(QueryNone()) end
  else if n >= 256 then let val () = $A.free<byte>(q) in query_put(QueryNone()) end
  else let
    val d = $A.alloc<byte>(n)
    val () = _lowcopy(q, d, n, 0)
    val () = $A.free<byte>(q)
  in query_put(QuerySome(d, n)) end

(* Whether q[0, m) is in s[0, n) at or after i, letters in any case *)
fun _at {ls,lq:agz}{n,m:pos}{i:nat | i + m <= n}{j:nat | j <= m} .<m - j>.
  (s: !$A.arr(byte, ls, n), n: int n, q: !$A.arr(byte, lq, m), m: int m, i: int i, j: int j): bool =
  if j >= m then true
  else if _lower(byte2int0($A.get<byte>(s, i + j))) <> byte2int0($A.get<byte>(q, j)) then false
  else _at(s, n, q, m, i, j + 1)

fun _has {ls,lq:agz}{n,m:pos}{i:nat} .<max(n - i + 1, 0)>.
  (s: !$A.arr(byte, ls, n), n: int n, q: !$A.arr(byte, lq, m), m: int m, i: int i): bool =
  if i + m > n then false
  else if _at(s, n, q, m, i, 0) then true
  else _has(s, n, q, m, i + 1)

fn _matches (b: !book, q: !query): bool =
  case+ q of
  | QueryNone() => true
  | QuerySome(qa, qn) => let
      val+ Book(t, tn, a, an, _, _, _) = b
    in if _has(t, tn, qa, qn, 0) then true else _has(a, an, qa, qn, 0) end

(* ============================================================
   The library view
   ============================================================ *)

(* "N%" for p (0 to 100) in buf, from 0; its length *)
fn _percent {l:agz} (buf: !$A.arr(byte, l, 16), p: [p:nat | p <= 100] int p): [k:pos | k <= 16] int k = let
  val off = $S.int_to_str(buf, 0, 16, p)
  val () = $A.set<byte>(buf, off, $A.int2byte(37))
in off + 1 end

(* How far through the book x is, in percent *)
fn _progress (x: bnums): [p:nat | p <= 100] int p = let
  val tch = x.tch
  val ch0 = x.ch
  val pgs0 = x.pgs
  val pg0 = x.pg
in
  if x.done > 0 then 100
  else if tch <= 0 then 0
  (* a count stored by an earlier run: past these, no book has them *)
  else if tch > 1000000 then 0
  else if pgs0 > 1000000 then 0
  else let
    val ch = (if ch0 >= 0 then (if ch0 < tch then ch0 else tch - 1) else 0): [v:nat | v < 1000000] int v
    val pgs = (if pgs0 > 0 then pgs0 else 1): [v:pos | v <= 1000000] int v
    val pg = (if pg0 >= 0 then (if pg0 < pgs then pg0 else pgs - 1) else 0): [v:nat | v < 1000000] int v
    val per = (ch * 100 + (pg * 100) / pgs) / tch
    val per = (if per >= 0 then (if per <= 100 then per else 100) else 0): [p:nat | p <= 100] int p
  in per end
end

#pub fn lib_progress (x: bnums): [p:nat | p <= 100] int p
implement lib_progress (x) = _progress(x)

(* The image type code of a mime (the types _mime_of gives) *)
#pub fn mime_str (code: int): [sn:pos | sn <= 24] string sn

implement mime_str (code) =
  if code = 1 then "image/png" else if code = 2 then "image/jpeg"
  else if code = 3 then "image/gif" else if code = 4 then "image/svg+xml"
  else if code = 5 then "image/webp" else "application/octet-stream"

(* Shows the cover of the book with this id (stored under 'c') in
   element base<i>-cover, unless the view was rendered again since gen *)
fn _show_cover {nb:pos | nb <= 16}{i:nat} (base: string nb, i: int i, h1: int, h2: int, code: int, gen: int): void = let
  val key = lib_key(99, h1, h2)
  val @(kf, kb) = $A.freeze<byte>(key)
  val p = $IDB.idb_get(kb, 15)
  val () = release_bytes(kf, kb)
in
  $P.discard<int>($P.and_then<Int><int>($P.vow(p), lam(h) =>
    case+ take_content(h) of
    | ~NoContentBytes() => $P.ret<int>(0)
    | ~ContentBytes(ow, buf, n) =>
      if !_render_gen <> gen then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else let
        val mime = mime_str(code)
        val ml = g1u2i(string1_length(mime))
        val ma = $A.alloc<byte>(ml)
        val () = $A.write_text(ma, 0, $A.text_lit(mime), ml)
        val @(mf, mb) = $A.freeze<byte>(ma)
        val @(ia, il) = nid_make2(base, i, "-cover")
        val @(if_, ib) = $A.freeze<byte>(ia)
        val @(df, db) = $A.freeze<byte>(buf)
        val () = $BDOM.set_image_src(ib, il, db, n, mb, ml)
        val () = $A.drop<byte>(df, db)
        val () = piece_free(ow, $A.thaw<byte>(df))
        val () = release_bytes(if_, ib)
        val () = release_bytes(mf, mb)
      in $P.ret<int>(0) end))
end

(* ============================================================
   Book info's accessibility section: the book's metadata (stored under
   'y' at import) in the W3C Publishing Community Group's display
   guidelines' words and order
   ============================================================ *)

fn _bit (f: int, b: int): bool = $AR.band_int_int(f, b) <> 0

(* Line i of the section, with text t; the next line's number *)
fn _a11y_line {i:nat}{nt:pos | nt < 256} (i: int i, t: string nt): [j:nat] int j = let
  val @(a, l) = nid_make("a11y-line", i)
  val () = ui_add_n("book-info-a11y-list", a, l, TDiv)
  val @(a, l) = nid_make("a11y-line", i)
  val () = ui_text_n(a, l, t)
in i + 1 end

(* A group's heading, as line i *)
fn _a11y_group {i:nat}{nt:pos | nt < 256} (i: int i, t: string nt): [j:nat] int j = let
  val j = _a11y_line(i, t)
  val @(a, l) = nid_make("a11y-line", i)
  val () = ui_attr_n(a, l, AClass, "a11yg")
in j end

fn _line_if {i:nat}{nt:pos | nt < 256} (on: bool, i: int i, t: string nt): [j:nat] int j =
  if on then _a11y_line(i, t) else i

fn _group_if {i:nat}{nt:pos | nt < 256} (on: bool, i: int i, t: string nt): [j:nat] int j =
  if on then _a11y_group(i, t) else i

(* The line for the first of a, b that holds, else the last *)
fn _line_of2 {i:nat}{na,nb:pos | na < 256; nb < 256}
  (a: bool, i: int i, ta: string na, tb: string nb): [j:nat] int j =
  if a then _a11y_line(i, ta) else _a11y_line(i, tb)

fn _line_of3 {i:nat}{na,nb,nc:pos | na < 256; nb < 256; nc < 256}
  (a: bool, b: bool, i: int i, ta: string na, tb: string nb, tc: string nc): [j:nat] int j =
  if a then _a11y_line(i, ta) else _line_of2(b, i, tb, tc)

fn _line_of4 {i:nat}{na,nb,nc,nd:pos | na < 256; nb < 256; nc < 256; nd < 256}
  (a: bool, b: bool, c: bool, i: int i, ta: string na, tb: string nb, tc: string nc, td: string nd): [j:nat] int j =
  if a then _a11y_line(i, ta) else _line_of3(b, c, i, tb, tc, td)

(* The statements for flags f, from line i *)
fn _a11y_lines {i:nat} (f: int, i: int i): [j:nat] int j = let
  (* Ways of reading and Conformance are shown even with no metadata *)
  val i = _a11y_group(i, "Ways of reading")
  val i = _line_of2(_bit(f, A11Y_TRANSFORM), i, "Appearance can be modified",
    "No information about appearance modifiability is available")
  val readable = _bit(f, A11Y_SUFF_TEXT) || (_bit(f, A11Y_MODE_TEXT) && ~_bit(f, A11Y_MODE_VISUAL))
  val i = _line_of3(readable, _bit(f, A11Y_MODE_VISUAL), i, "Readable in read aloud or dynamic braille",
    "Not fully readable in read aloud or dynamic braille", "No information about nonvisual reading is available")
  val i = _line_if(_bit(f, A11Y_ALT), i, "Has alternative text")
  val i = _a11y_group(i, "Conformance")
  val level = $AR.band_int_int(f / A11Y_LEVEL, 3)
  val i = _line_of4(level = 3, level = 2, level = 1, i,
    "This publication exceeds accepted accessibility standards",
    "This publication meets accepted accessibility standards",
    "This publication meets minimum accessibility standards", "No information is available")
  val nav = $AR.band_int_int(f, A11Y_TOC + A11Y_INDEX + A11Y_STRUCT + A11Y_PAGES) <> 0
  val i = _group_if(nav, i, "Navigation")
  val i = _line_if(_bit(f, A11Y_TOC), i, "Table of contents")
  val i = _line_if(_bit(f, A11Y_INDEX), i, "Index")
  val i = _line_if(_bit(f, A11Y_STRUCT), i, "Headings")
  val i = _line_if(_bit(f, A11Y_PAGES), i, "Go to page")
  val rich = $AR.band_int_int(f, A11Y_MATHML + A11Y_LONGDESC + A11Y_TRANSCRIPT + A11Y_CAPTIONS) <> 0
  val i = _group_if(rich, i, "Rich content")
  val i = _line_if(_bit(f, A11Y_MATHML), i, "Math as MathML")
  val i = _line_if(_bit(f, A11Y_LONGDESC), i, "Information-rich images are described by extended descriptions")
  val i = _line_if(_bit(f, A11Y_TRANSCRIPT), i, "Transcript(s) provided")
  val i = _line_if(_bit(f, A11Y_CAPTIONS), i, "Videos have closed captions")
  val hz = $AR.band_int_int(f, A11Y_HZ_NONE + A11Y_HZ_FLASH + A11Y_HZ_MOTION + A11Y_HZ_SOUND
    + A11Y_HZ_NOFLASH + A11Y_HZ_NOMOTION + A11Y_HZ_NOSOUND + A11Y_HZ_UNKNOWN) <> 0
  val i = _group_if(hz, i, "Hazards")
  val i = _line_if(_bit(f, A11Y_HZ_NONE), i, "No hazards")
  val i = _line_if(_bit(f, A11Y_HZ_FLASH), i, "Flashing content")
  val i = _line_if(_bit(f, A11Y_HZ_MOTION), i, "Motion simulation")
  val i = _line_if(_bit(f, A11Y_HZ_SOUND), i, "Sounds")
  val i = _line_if(_bit(f, A11Y_HZ_NOFLASH), i, "No flashing hazards")
  val i = _line_if(_bit(f, A11Y_HZ_NOMOTION), i, "No motion simulation hazards")
  val i = _line_if(_bit(f, A11Y_HZ_NOSOUND), i, "No sound hazards")
in _line_if(_bit(f, A11Y_HZ_UNKNOWN), i, "The presence of hazards is unknown") end

(* src[6 + j, 6 + k) into dst[j, k) *)
fun _summary_copy {l,ld:agz}{la:addr}{n:nat}{k:nat | k + 6 <= n}{nd:pos | k <= nd}{j:nat | j <= k} .<k - j>.
  (src: !$A.arrx(byte, l, n, la), dst: !$A.arr(byte, ld, nd), k: int k, j: int j): void =
  if j >= k then ()
  else let
    val () = $A.set<byte>(dst, j, $A.get<byte>(src, 6 + j))
  in _summary_copy(src, dst, k, j + 1) end

(* Fills Book info's accessibility section for book (h1, h2) *)
#pub fn lib_a11y_show (h1: int, h2: int): void

implement lib_a11y_show (h1, h2) = let
  val () = ui_clear("book-info-a11y-list")
  val key = lib_key(121, h1, h2)
  val @(kf, kb) = $A.freeze<byte>(key)
  val p = $IDB.idb_get(kb, 15)
  val () = release_bytes(kf, kb)
in
  $P.discard<int>($P.and_then<Int><int>($P.vow(p), lam(h) =>
    case+ take_content(h) of
    | ~NoContentBytes() => let
        (* imported before this was read *)
        val _ = _a11y_line(0, "Import this book's file again to see its accessibility information.")
      in $P.ret<int>(0) end
    | ~ContentBytes(ow, buf, n) =>
      if n < 6 then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else let
        val f = _i32(buf, 2)
        val i = _a11y_lines(f, 0)
        val k = n - 6
        val () = (if k > 0 then (if k < 65536 then let
            val i = _a11y_group(i, "Accessibility summary")
            val t = $A.alloc<byte>(k)
            val () = _summary_copy(buf, t, k, 0)
            val @(a, l) = nid_make("a11y-line", i)
            val () = ui_add_n("book-info-a11y-list", a, l, TDiv)
            val @(a, l) = nid_make("a11y-line", i)
          in ui_text_n_buf(a, l, t, k) end else ()) else ())
        val () = piece_free(ow, buf)
      in $P.ret<int>(0) end)
  )
end

#pub fn lib_show_cover_in {ni:pos | ni < 256} (id: string ni, h1: int, h2: int, code: int): void

implement lib_show_cover_in (id, h1, h2, code) = let
  val key = lib_key(99, h1, h2)
  val @(kf, kb) = $A.freeze<byte>(key)
  val p = $IDB.idb_get(kb, 15)
  val () = release_bytes(kf, kb)
in
  $P.discard<int>($P.and_then<Int><int>($P.vow(p), lam(h) =>
    case+ take_content(h) of
    | ~NoContentBytes() => $P.ret<int>(0)
    | ~ContentBytes(ow, buf, n) => let
        val mime = mime_str(code)
        val ml = g1u2i(string1_length(mime))
        val ma = $A.alloc<byte>(ml)
        val () = $A.write_text(ma, 0, $A.text_lit(mime), ml)
        val @(mf, mb) = $A.freeze<byte>(ma)
        val il = g1u2i(string1_length(id))
        val ia = $A.alloc<byte>(il)
        val () = $A.write_text(ia, 0, $A.text_lit(id), il)
        val @(if_, ib) = $A.freeze<byte>(ia)
        val @(df, db) = $A.freeze<byte>(buf)
        val () = $BDOM.set_image_src(ib, il, db, n, mb, ml)
        val () = $A.drop<byte>(df, db)
        val () = piece_free(ow, $A.thaw<byte>(df))
        val () = release_bytes(if_, ib)
        val () = release_bytes(mf, mb)
      in $P.ret<int>(0) end))
end

(* The series line of card i: the series' name, and " · N" *)
fn _card_series {nb:pos | nb <= 16}{i:nat}{l:agz}{m:pos}{sn:pos | sn < m; sn < 256}
  (base: string nb, i: int i, sr: !$A.arr(byte, l, m), sn: int sn, sidx: Int): void = let
  val @(pi, pl) = nid_make2(base, i, "-info")
  val @(si, sl) = nid_make2(base, i, "-series")
  val () = ui_add_nn(pi, pl, si, sl, TDiv)
  val @(si, sl) = nid_make2(base, i, "-series")
  val () = ui_attr_n(si, sl, AClass, "bser")
  val b = $A.alloc<byte>(sn + 20)
  val () = _copy(sr, sn, b, 0, 0)
  val k = _series_num(b, sn, sidx)
  val @(si, sl) = nid_make2(base, i, "-series")
in ui_text_n_buf(si, sl, b, k) end

(* Card i for book b: cover, title, author, progress; its elements'
   ids are base<i> (the card), base<i>-cover and so on, in row
   rowp<i> under parent, with its More button (morep<i>) when more *)
fn _card {i:nat}{nb,nr,nm,np:pos | nb <= 16; nr <= 16; nm <= 16; np < 256}
  (b: !book, i: int i, gen: int, base: string nb, rowp: string nr, morep: string nm,
   parent: string np, more: bool): void = let
  val+ Book(t, tn, a, an, sr, sn, x) = b
  (* the row: the card, which opens the book, then its More button,
     which opens the book menu; the row is named by the book's title *)
  val @(ri, rl) = nid_make(rowp, i)
  val () = ui_add_n(parent, ri, rl, TDiv)
  val @(ri, rl) = nid_make(rowp, i)
  val () = ui_attr_n(ri, rl, AClass, "cardrow")
  val @(pi, pl) = nid_make(rowp, i)
  val @(ci, cl) = nid_make(base, i)
  val () = ui_btn_nn(pi, pl, ci, cl, "card")
  val () = (if more then let
      val @(pi, pl) = nid_make(rowp, i)
      val @(mi, ml) = nid_make(morep, i)
    in ui_icon_btn_nn(pi, pl, mi, ml, "cmore", IcMore, "Book menu") end else ())
  val @(ri, rl) = nid_make(rowp, i)
  val @(ti, tl) = nid_make2(base, i, "-title")
  val () = ui_labelled_nn(ri, rl, NGroup, ti, tl)
  (* cover: decorative, the title is beside it *)
  val @(pi, pl) = nid_make(base, i)
  val @(vi, vl) = nid_make2(base, i, "-cover")
  val () = ui_img_nn(pi, pl, vi, vl, (if x.cover > 0 then "cov" else "cov cov0"): [k:pos | k < 256] string k)
  val () = (if x.cover > 0 then _show_cover(base, i, x.h1, x.h2, x.cover, gen) else ())
  (* title, author *)
  val @(pi, pl) = nid_make(base, i)
  val @(ti, tl) = nid_make2(base, i, "-info")
  val () = ui_add_nn(pi, pl, ti, tl, TDiv)
  val @(ti, tl) = nid_make2(base, i, "-info")
  val () = ui_attr_n(ti, tl, AClass, "cinfo")
  val @(pi, pl) = nid_make2(base, i, "-info")
  val @(ti, tl) = nid_make2(base, i, "-title")
  val () = ui_add_nn(pi, pl, ti, tl, TDiv)
  val @(ti, tl) = nid_make2(base, i, "-title")
  val () = ui_attr_n(ti, tl, AClass, "bt")
  val tb = $A.alloc<byte>(tn)
  val () = _copy(t, tn, tb, 0, 0)
  val @(ti, tl) = nid_make2(base, i, "-title")
  val () = ui_text_n_buf(ti, tl, tb, tn)
  val @(pi, pl) = nid_make2(base, i, "-info")
  val @(ai, al) = nid_make2(base, i, "-author")
  val () = ui_add_nn(pi, pl, ai, al, TDiv)
  val @(ai, al) = nid_make2(base, i, "-author")
  val () = ui_attr_n(ai, al, AClass, "ba")
  val ab = $A.alloc<byte>(an)
  val () = _copy(a, an, ab, 0, 0)
  val @(ai, al) = nid_make2(base, i, "-author")
  val () = ui_text_n_buf(ai, al, ab, an)
  (* its series, and its number in it: "Foundation · 2" *)
  val () = (if sn > 0 then _card_series(base, i, sr, sn, x.sidx) else ())
  (* progress *)
  val @(pi, pl) = nid_make2(base, i, "-info")
  val @(gi, gl) = nid_make2(base, i, "-progress")
  val () = ui_add_nn(pi, pl, gi, gl, TDiv)
  val @(gi, gl) = nid_make2(base, i, "-progress")
  val () = ui_attr_n(gi, gl, AClass, "prog")
  val per = _progress(x)
in
  if x.done > 0 then let
    val @(gi, gl) = nid_make2(base, i, "-progress")
  in ui_text_n(gi, gl, "Done") end
  else if x.opened <= 0 then let
    val @(gi, gl) = nid_make2(base, i, "-progress")
  in ui_text_n(gi, gl, "New") end
  else let
    val @(pi, pl) = nid_make2(base, i, "-progress")
    val @(bi, bl) = nid_make2(base, i, "-bar")
    val () = ui_add_nn(pi, pl, bi, bl, TDiv)
    val @(bi, bl) = nid_make2(base, i, "-bar")
    val () = ui_attr_n(bi, bl, AClass, "pbar")
    val @(pi, pl) = nid_make2(base, i, "-bar")
    val @(fi, fl) = nid_make2(base, i, "-fill")
    val () = ui_add_nn(pi, pl, fi, fl, TDiv)
    val @(fi, fl) = nid_make2(base, i, "-fill")
    val () = ui_attr_n(fi, fl, AClass, "pfill")
    val @(fi, fl) = nid_make2(base, i, "-fill")
    val () = ui_place_n(fi, fl, PWidth, per * 10)
    val @(pi, pl) = nid_make2(base, i, "-progress")
    val @(xi, xl) = nid_make2(base, i, "-percent")
    val () = ui_add_nn(pi, pl, xi, xl, TSpan)
    val pb = $A.alloc<byte>(16)
    val k = _percent(pb, per)
    val @(xi, xl) = nid_make2(base, i, "-percent")
  in ui_text_n_buf(xi, xl, pb, k) end
end

(* The library's view: its cards (0 a list, 1 a grid of covers), and
   which books it shows (0 all, 1 unread, 2 reading, 3 finished) *)
val _grid = ref<int>(0)
val _filter = ref<int>(0)

(* Whether a book with numbers x passes the filter *)
fn _passes (x: bnums): bool = let
  val f = !_filter
in
  if f = 1 then x.opened <= 0
  else if f = 2 then (if x.opened > 0 then x.done <= 0 else false)
  else if f = 3 then x.done > 0
  else true
end

fun _cards {k:nat}{i:nat} .<k>. (bs: !books(k), i: int i, shelf: int, q: !query, gen: int, shown: int): int =
  case+ bs of
  | books_nil() => shown
  | books_cons(b, rest) => let
      val+ Book(_, _, _, _, _, _, x) = b
      val vis = (if x.shelf = shelf then (if _passes(x) then (if _in_shown(x) then _matches(b, q) else false) else false) else false): bool
      val () = (if vis then _card(b, i, gen, "book", "book-row", "book-more", "book-list", true) else ())
    in _cards(rest, i + 1, shelf, q, gen, (if vis then shown + 1 else shown)) end

(* The book to continue: the one on the shelf opened last and not
   finished: its index, or -1 (best is the one so far, opened at
   latest_opened) *)
fun _latest {k:nat}{i:nat} .<k>. (bs: !books(k), i: int i, best: int, latest_opened: Int): int =
  case+ bs of
  | books_nil() => best
  | books_cons(b, rest) => let
      val+ Book(_, _, _, _, _, _, x) = b
      val better = (if x.shelf = 0 then (if x.done <= 0 then (if x.opened > 0 then x.opened > latest_opened else false) else false) else false): bool
    in if better then _latest(rest, i + 1, i, x.opened) else _latest(rest, i + 1, best, latest_opened) end

(* Card i of bs, into the Continue reading section *)
fun _continue_card {k:nat}{i:nat} .<k>. (bs: !books(k), i: int i, want: int, gen: int): void =
  case+ bs of
  | books_nil() => ()
  | books_cons(b, rest) =>
    if i = want then _card(b, i, gen, "continue", "continue-row", "continue-more", "continue-list", false)
    else _continue_card(rest, i + 1, want, gen)

(* The view's controls, pressed as the view is *)
fn _view_show (): void = let
  val g = !_grid
  val f = !_filter
  val () = (if g = 1 then ui_attr("book-list", AClass, "list grid") else ui_attr("book-list", AClass, "list"))
  val () = (if g = 1 then ui_attr("view-grid", APressed, "true") else ui_attr("view-grid", APressed, "false"))
  val () = (if g = 1 then ui_attr("view-list", APressed, "false") else ui_attr("view-list", APressed, "true"))
  val () = (if f = 0 then ui_attr("filter-books-all", APressed, "true") else ui_attr("filter-books-all", APressed, "false"))
  val () = (if f = 1 then ui_attr("filter-unread", APressed, "true") else ui_attr("filter-unread", APressed, "false"))
  val () = (if f = 2 then ui_attr("filter-reading", APressed, "true") else ui_attr("filter-reading", APressed, "false"))
in if f = 3 then ui_attr("filter-finished", APressed, "true") else ui_attr("filter-finished", APressed, "false") end

(* The library's view state, kept with the settings: its sort order
   (below 8), plus 8 for a grid, plus 16 times the filter *)
#pub fn lib_state_get (): int
implement lib_state_get () = !_sort_order + 8 * !_grid + 16 * !_filter

(* Sets the view from a kept state (sorts, but does not render) *)
#pub fn lib_state_set (st: int): void
implement lib_state_set (st) = let
  val st = (if st >= 0 then (if st < 64 then st else 0) else 0): int
  val () = !_grid := $AR.band_int_int(st / 8, 1)
  val () = !_filter := $AR.band_int_int(st / 16, 3)
  val () = _view_show()
in lib_sort($AR.band_int_int(st, 7)) end

#pub fn lib_grid_set (g: int): void
implement lib_grid_set (g) = let
  val () = !_grid := (if g = 1 then 1 else 0)
  val () = _view_show()
in lib_render() end

#pub fn lib_filter_set (f: int): void
implement lib_filter_set (f) = let
  val () = !_filter := (if f >= 0 then (if f <= 3 then f else 0) else 0)
  val () = _view_show()
in lib_render() end

#pub fn lib_grid_get (): int
implement lib_grid_get () = !_grid
#pub fn lib_filter_get (): int
implement lib_filter_get () = !_filter

(* ============================================================
   The hint to add Quire to the Home Screen
   ============================================================ *)

(* On iOS Safari there is no install prompt, and what a page keeps is
   cleared after 7 days without a visit, but not for an app on the Home
   Screen. The hint is offered once the library has a book (the
   stylesheet shows it only under the page's pwa-ios-browser class,
   which the page's script sets) until it is dismissed; dismissed until
   the last run's answer is read, so it never shows twice *)
val _install_hint_dismissed = ref<bool>(true)

fn _install_hint_key (): [l:agz] $A.arr(byte, l, 12) = let
  val k = $A.alloc<byte>(12)
  val () = $A.write_text(k, 0, $A.text_lit("install-hint"), 12)
in k end

fn _install_hint_show (): void =
  if !_install_hint_dismissed then ui_attr("install-hint", AClass, "ihint")
  else if lib_count() > 0 then ui_attr("install-hint", AClass, "ihint on")
  else ui_attr("install-hint", AClass, "ihint")

(* Reads whether the hint was dismissed in an earlier run *)
#pub fn lib_install_hint_load (): void
implement lib_install_hint_load () = let
  val @(kf, kb) = $A.freeze<byte>(_install_hint_key())
  val p = $IDB.idb_get(kb, 12)
  val () = release_bytes(kf, kb)
in
  $P.discard<int>($P.and_then<Int><int>($P.vow(p), lam(h) => let
    val () = (case+ take_blob(h) of
      | ~NoBlobBytes() => !_install_hint_dismissed := false
      | ~BlobBytes(b, _) => $A.free<byte>(b))
    val () = _install_hint_show()
  in $P.ret<int>(0) end))
end

(* The hint dismissed, for good *)
#pub fn lib_install_hint_dismiss (): void
implement lib_install_hint_dismiss () = let
  val () = !_install_hint_dismissed := true
  val v = $A.alloc<byte>(1)
  val () = $A.write_byte(v, 0, 1)
  val @(vf, vb) = $A.freeze<byte>(v)
  val @(kf, kb) = $A.freeze<byte>(_install_hint_key())
  val () = $P.discard<Int>($IDB.idb_put(kb, 12, vb, 1))
  val () = release_bytes(kf, kb)
  val () = release_bytes(vf, vb)
in _install_hint_show() end

(* Renders the library view: the cards of the shelf shown whose title
   or author matches the query, in the sort order *)
#pub fn lib_render (): void

implement lib_render () = let
  val () = !_render_gen := !_render_gen + 1
  val gen = !_render_gen
  val () = ui_clear("book-list")
  val () = ui_clear("continue-list")
  val () = _view_show()
  val shelf = !_shelf
  val q = query_take()
  val has_q = (case+ q of QuerySome(_, _) => true | QueryNone() => false): bool
  val c = lib_take()
  val+ @LibCell(bs, k) = c
  val shown = _cards(bs, 0, shelf, q, gen, 0)
  (* the book to continue, above the rest: on the shelf, unsearched, in
     no one collection, and unless only unread or finished books are
     shown *)
  val want = (if shelf = 0 then (if ~has_q then (if !_coll_shown < 0 then (if !_filter = 0 || !_filter = 2 then _latest(bs, 0, ~1, 0) else ~1) else ~1) else ~1) else ~1): int
  val () = (if want >= 0 then _continue_card(bs, 0, want, gen) else ())
  prval () = fold@(c)
  val () = lib_put(c)
  val () = ui_show("continue-reading", want >= 0)
  val () = query_put(q)
  val () = ui_show("library-empty", shown = 0)
  val () = _coll_row()
  val () = _install_hint_show()
in
  if shown > 0 then ()
  else if has_q then ui_text("library-empty", "No books match")
  else if !_coll_shown >= 0 then ui_text("library-empty", "No books in this collection")
  else if !_filter = 1 then ui_text("library-empty", "No unread books")
  else if !_filter = 2 then ui_text("library-empty", "No books being read")
  else if !_filter = 3 then ui_text("library-empty", "No finished books")
  else if shelf = 1 then ui_text("library-empty", "No hidden books")
  else if shelf = 2 then ui_text("library-empty", "No archived books")
  else if shelf = 3 then ui_text("library-empty", "The Trash is empty")
  else ui_text("library-empty", "Import an EPUB file to start reading.")
end

(* Shows shelf s (0 the shelf, 1 hidden, 2 archived, 3 the Trash) *)
#pub fn lib_shelf_set (s: int): void

implement lib_shelf_set (s) = let
  val () = !_shelf := s
in
  if s = 1 then ui_text("shelf-button", "Hidden")
  else if s = 2 then ui_text("shelf-button", "Archived")
  else if s = 3 then ui_text("shelf-button", "Trash")
  else ui_text("shelf-button", "Library")
end

(* The sort button's label for order o *)
#pub fn lib_sort_label (o: int): void

implement lib_sort_label (o) =
  if o = 1 then ui_text("sort-button", "Sort: Title")
  else if o = 2 then ui_text("sort-button", "Sort: Author")
  else if o = 3 then ui_text("sort-button", "Sort: Date added")
  else if o = 4 then ui_text("sort-button", "Sort: Series")
  else ui_text("sort-button", "Sort: Last opened")

(* ============================================================
   Dates and sizes, as text
   ============================================================ *)

(* d as two digits at buf[p, p + 2) (d from 0 to 99) *)
fn _two {l:agz}{n:pos}{p:nat | p + 2 <= n}{d:nat | d < 100} (buf: !$A.arr(byte, l, n), p: int p, d: int d): void = let
  val () = $A.set<byte>(buf, p, $A.int2byte(48 + d / 10))
in $A.set<byte>(buf, p + 1, $A.int2byte(48 + d - (d / 10) * 10)) end

(* The day m (minutes since the epoch, UTC) falls on, as YYYY-MM-DD in
   buf (its length); a civil date by Howard Hinnant's days_from_civil
   inverse *)
#pub fn date_text {l:agz} (buf: !$A.arr(byte, l, 32), m: Int): [k:nat | k <= 32] int k

implement date_text (buf, m) = let
  val days = (if m > 0 then m / 1440 else 0): [v:nat] int v
  (* days up to year 9999, past which no clock this app runs on goes *)
  val days = (if days > 2932896 then 2932896 else days): [v:nat | v <= 2932896] int v
  val z = days + 719468
  val era = z / 146097
  val doe = z - era * 146097
  val yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  val y = yoe + era * 400
  val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  val mp = (5 * doy + 2) / 153
  val d = doy - (153 * mp + 2) / 5 + 1
  val mo = (if mp < 10 then mp + 3 else mp - 9): Int
  val y = (if mo <= 2 then y + 1 else y): Int
  val off = $S.int_to_str(buf, 0, 32, y)
  val mo = (if mo >= 1 then (if mo <= 12 then mo else 12) else 1): [v:nat | v < 100] int v
  val d = (if d >= 1 then (if d <= 31 then d else 31) else 1): [v:nat | v < 100] int v
  val () = $A.set<byte>(buf, off, $A.int2byte(45))
  val () = _two(buf, off + 1, mo)
  val () = $A.set<byte>(buf, off + 3, $A.int2byte(45))
  val () = _two(buf, off + 4, d)
in off + 6 end

(* n bytes as "N KB" or "N.N MB" in buf (its length) *)
#pub fn size_text {l:agz} (buf: !$A.arr(byte, l, 32), n: Int): [k:nat | k <= 32] int k

implement size_text (buf, n) =
  if n < 1048576 then let
    val kb = (if n > 0 then (n + 1023) / 1024 else 0): Int
    val off = $S.int_to_str(buf, 0, 32, kb)
    val () = $A.set<byte>(buf, off, $A.int2byte(32))
    val () = $A.set<byte>(buf, off + 1, $A.int2byte(75))
    val () = $A.set<byte>(buf, off + 2, $A.int2byte(66))
  in off + 3 end
  else let
    val tenths = n / 104858
    val off = $S.int_to_str(buf, 0, 32, tenths / 10)
    val () = $A.set<byte>(buf, off, $A.int2byte(46))
    val r = tenths - (tenths / 10) * 10
    val r = (if r >= 0 then (if r <= 9 then r else 9) else 0): [v:nat | v <= 9] int v
    val () = $A.set<byte>(buf, off + 1, $A.int2byte(48 + r))
    val () = $A.set<byte>(buf, off + 2, $A.int2byte(32))
    val () = $A.set<byte>(buf, off + 3, $A.int2byte(77))
    val () = $A.set<byte>(buf, off + 4, $A.int2byte(66))
  in off + 5 end

end (* #target wasm *)
