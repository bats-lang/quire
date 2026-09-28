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
  done = Int       (* 1 when the last page was reached *)
}

(* A book: its title and author (1 to 255 bytes) and its numbers *)
#pub datavtype book =
  | {lt,la:agz}{nt,na:pos | nt < 256; na < 256}
    Book of ($A.arr(byte, lt, nt), int nt, $A.arr(byte, la, na), int na, bnums)

#pub stadef LIB_MAX = 100000

#pub datavtype books(int) =
  | books_nil(0) of ()
  | {k:nat} books_cons(k + 1) of (book, books(k))

fn book_free (b: book): void = let
  val+ ~Book(t, _, a, _, _) = b
  val () = $A.free<byte>(t)
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
      val+ Book(_, _, _, _, nums) = b
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
      val+ Book(_, _, _, _, nums) = b
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
    if i = 0 then let val+ Book(_, _, _, _, nums) = b in $R.some(nums) end
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
      val+ @Book(_, _, _, _, nums) = b
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
fun _copy {ls,ld:agz}{ns,nd:nat}{o:nat | o + ns <= nd}{j:nat | j <= ns} .<ns - j>.
  (src: !$A.arr(byte, ls, ns), ns: int ns, dst: !$A.arr(byte, ld, nd), o: int o, j: int j): void =
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
      val+ Book(t, tn, a, an, _) = b
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
#pub fn lib_add {lb:agz}{n:pos}{to,tl,ao,al:nat | to + tl <= n; ao + al <= n}
  (h1: Int, h2: Int, data: !$A.borrow(byte, lb, n), n: int n,
   to: int to, tl: int tl, ao: int ao, al: int al, fsz: Int, cover: Int, now: Int): Int

implement lib_add (h1, h2, data, n, to, tl, ao, al, fsz, cover, now) = let
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
    val nums = @{
      key = key, h1 = h1, h2 = h2, shelf = 0, added = now, opened = 0,
      ch = 0, tch = 0, pg = 0, pgs = 0, anchor = ~1, fsz = fsz, cover = cover, done = 0
    }: bnums
    val () = lib_put(LibCell(books_cons(Book(t, tn, a, an, nums), bs), k + 1))
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
  val () = $A.drop<byte>(f, b)
in $A.free<byte>($A.thaw<byte>(f)) end

(* Sets book i's shelf, and keeps and shows the library *)
#pub fn lib_set_shelf {i:int} (i: int i, shelf: Int): void

implement lib_set_shelf (i, shelf) = let
  val () = lib_update(i, lam(x) => @{
    key = x.key, h1 = x.h1, h2 = x.h2, shelf = shelf, added = x.added, opened = x.opened,
    ch = x.ch, tch = x.tch, pg = x.pg, pgs = x.pgs, anchor = x.anchor,
    fsz = x.fsz, cover = x.cover, done = x.done })
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
      fsz = x.fsz, cover = x.cover, done = x.done })
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
          fsz = x.fsz, cover = x.cover, done = x.done }) else ())
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
fun _less {la,lb:agz}{an,bn:nat}{i:nat | i <= an} .<an - i>.
  (a: !$A.arr(byte, la, an), an: int an, b: !$A.arr(byte, lb, bn), bn: int bn, i: int i): int =
  if i >= an then (if i >= bn then 0 else ~1)
  else if i >= bn then 1
  else let
    val x = _lower(byte2int0($A.get<byte>(a, i)))
    val y = _lower(byte2int0($A.get<byte>(b, i)))
  in if x < y then ~1 else if x > y then 1 else _less(a, an, b, bn, i + 1) end

(* Whether x comes before y in order o *)
fn _before (x: !book, y: !book, o: int): bool = let
  val+ Book(xt, xtn, xa, xan, xn) = x
  val+ Book(yt, ytn, ya, yan, yn) = y
in
  if o = 1 then _less(xt, xtn, yt, ytn, 0) < 0
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
   Storage: key "lib"
   ============================================================ *)

(* "QLB1", then each book: id (2 x i32), title (u8 length, bytes),
   author (u8 length, bytes), then 10 x i32: shelf, added, opened, ch,
   tch, pg, pgs, anchor, fsz, cover | done << 8. At most 560 bytes a
   book. *)

fun _put_bytes {ls,l:agz}{la:addr}{ns:nat}{n:nat}{p:nat | p + ns <= n}{j:nat | j <= ns} .<ns - j>.
  (src: !$A.arr(byte, ls, ns), ns: int ns, out: !$A.arrx(byte, l, n, la), p: int p, j: int j): void =
  if j >= ns then ()
  else let
    val () = $A.write_byte(out, p + j, $AR.low_byte(byte2int0($A.get<byte>(src, j))))
  in _put_bytes(src, ns, out, p, j + 1) end

fun _ser {l:agz}{la:addr}{n:int}{j:nat}{p:nat | p + 560 * j <= n} .<j>.
  (out: !$A.arrx(byte, l, n, la), p: int p, bs: !books(j)): [q:nat | q <= n] int q =
  case+ bs of
  | books_nil() => p
  | books_cons(b, rest) => let
      val+ Book(t, tn, a, an, x) = b
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
    in _ser(out, q + 40, rest) end

(* Stores the library under "lib" *)
#pub fn lib_save (): void

implement lib_save () = let
  val c = lib_take()
  val+ @LibCell(bs, k) = c
  val n = 4 + 560 * k
in
  case+ piece_new(n) of
  | ~NoPiece() => let prval () = fold@(c) in lib_put(c) end
  | ~Piece(ow, out) => let
      val () = $A.write_byte(out, 0, 81) (* Q *)
      val () = $A.write_byte(out, 1, 76) (* L *)
      val () = $A.write_byte(out, 2, 66) (* B *)
      val () = $A.write_byte(out, 3, 49) (* 1 *)
      val m = _ser(out, 4, bs)
      prval () = fold@(c)
      val () = lib_put(c)
      val @(f, b) = $A.freeze<byte>(out)
      val @(used, rest) = $A.borrow_split<byte>(f, b, m)
      val ka = $A.alloc<byte>(3)
      val () = $A.write_byte(ka, 0, 108) (* l *)
      val () = $A.write_byte(ka, 1, 105) (* i *)
      val () = $A.write_byte(ka, 2, 98)  (* b *)
      val @(kf, kb) = $A.freeze<byte>(ka)
      val () = $P.discard<Int>($IDB.idb_put(kb, 3, used, m))
      val () = $A.drop<byte>(kf, kb)
      val () = $A.free<byte>($A.thaw<byte>(kf))
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

fun _bytes_of {l:agz}{la:addr}{n:nat}{p,m:nat | p + m <= n}{lo:agz}{j:nat | j <= m} .<m - j>.
  (buf: !$A.arrx(byte, l, n, la), p: int p, m: int m, out: !$A.arr(byte, lo, m), j: int j): void =
  if j >= m then ()
  else let
    val () = $A.set<byte>(out, j, $A.get<byte>(buf, p + j))
  in _bytes_of(buf, p, m, out, j + 1) end

(* The books stored in buf[p, n), read from an earlier run's bytes and
   checked here, once; onto acc (at most LIB_MAX) *)
fun _parse {l:agz}{la:addr}{n:nat}{p:nat | p <= n}{a:nat | a <= LIB_MAX} .<n - p>.
  (buf: !$A.arrx(byte, l, n, la), n: int n, p: int p, acc: books(a), a: int a)
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
          cover = $AR.low_byte(cd), done = $AR.band_g1($AR.low_byte($AR.bsr_int_int(cd, 8)), 1)
        }: bnums
      in _parse(buf, n, r + 40, books_cons(Book(t, tn, au, an, nums), acc), a + 1) end
    end
  end

(* Reads the library stored under "lib"; the promise resolves with the
   number of books *)
#pub fn lib_load (): $P.promise(int, $P.Chained)

implement lib_load () = let
  val ka = $A.alloc<byte>(3)
  val () = $A.write_byte(ka, 0, 108)
  val () = $A.write_byte(ka, 1, 105)
  val () = $A.write_byte(ka, 2, 98)
  val @(kf, kb) = $A.freeze<byte>(ka)
  val p = $IDB.idb_get(kb, 3)
  val () = $A.drop<byte>(kf, kb)
  val () = $A.free<byte>($A.thaw<byte>(kf))
in
  $P.and_then<Int><int>($P.vow(p), lam(h) =>
    case+ take_content(h) of
    | ~NoContentBytes() => $P.ret<int>(0)
    | ~ContentBytes(ow, buf, n) =>
      if n < 4 then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(buf, 0)) <> 81 then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else if byte2int0($A.get<byte>(buf, 3)) <> 49 then let val () = piece_free(ow, buf) in $P.ret<int>(0) end
      else let
        val @(bs, k) = _parse(buf, n, 4, books_nil(), 0)
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
      val+ Book(t, tn, a, an, _) = b
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
   element k<i>c, unless the view was rendered again since gen *)
fn _show_cover {i:nat} (i: int i, h1: int, h2: int, code: int, gen: int): void = let
  val key = lib_key(99, h1, h2)
  val @(kf, kb) = $A.freeze<byte>(key)
  val p = $IDB.idb_get(kb, 15)
  val () = $A.drop<byte>(kf, kb)
  val () = $A.free<byte>($A.thaw<byte>(kf))
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
        val @(ia, il) = nid_make2("k", i, "c")
        val @(if_, ib) = $A.freeze<byte>(ia)
        val @(df, db) = $A.freeze<byte>(buf)
        val () = $BDOM.set_image_src(ib, il, db, n, mb, ml)
        val () = $A.drop<byte>(df, db)
        val () = piece_free(ow, $A.thaw<byte>(df))
        val () = $A.drop<byte>(if_, ib)
        val () = $A.free<byte>($A.thaw<byte>(if_))
        val () = $A.drop<byte>(mf, mb)
        val () = $A.free<byte>($A.thaw<byte>(mf))
      in $P.ret<int>(0) end))
end

#pub fn lib_show_cover_in {ni:pos | ni < 256} (id: string ni, h1: int, h2: int, code: int): void

implement lib_show_cover_in (id, h1, h2, code) = let
  val key = lib_key(99, h1, h2)
  val @(kf, kb) = $A.freeze<byte>(key)
  val p = $IDB.idb_get(kb, 15)
  val () = $A.drop<byte>(kf, kb)
  val () = $A.free<byte>($A.thaw<byte>(kf))
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
        val () = $A.drop<byte>(if_, ib)
        val () = $A.free<byte>($A.thaw<byte>(if_))
        val () = $A.drop<byte>(mf, mb)
        val () = $A.free<byte>($A.thaw<byte>(mf))
      in $P.ret<int>(0) end))
end

(* Card i for book b: cover, title, author, progress *)
fn _card {i:nat} (b: !book, i: int i, gen: int): void = let
  val+ Book(t, tn, a, an, x) = b
  (* the row: the card, which opens the book, then its More button,
     which opens the book menu; the row is named by the book's title *)
  val @(ri, rl) = nid_make("kr", i)
  val () = ui_add_n("qlst", ri, rl, TDiv)
  val @(ri, rl) = nid_make("kr", i)
  val () = ui_attr_n(ri, rl, AClass, "cardrow")
  val @(pi, pl) = nid_make("kr", i)
  val @(ci, cl) = nid_make("k", i)
  val () = ui_btn_nn(pi, pl, ci, cl, "card")
  val @(pi, pl) = nid_make("kr", i)
  val @(mi, ml) = nid_make("km", i)
  val () = ui_icon_btn_nn(pi, pl, mi, ml, "cmore", IcMore, "Book menu")
  val @(ri, rl) = nid_make("kr", i)
  val @(ti, tl) = nid_make2("k", i, "t")
  val () = ui_labelled_nn(ri, rl, NGroup, ti, tl)
  (* cover: decorative, the title is beside it *)
  val @(pi, pl) = nid_make("k", i)
  val @(vi, vl) = nid_make2("k", i, "c")
  val () = ui_img_nn(pi, pl, vi, vl, (if x.cover > 0 then "cov" else "cov cov0"): [k:pos | k < 256] string k)
  val () = (if x.cover > 0 then _show_cover(i, x.h1, x.h2, x.cover, gen) else ())
  (* title, author *)
  val @(pi, pl) = nid_make("k", i)
  val @(ti, tl) = nid_make2("k", i, "i")
  val () = ui_add_nn(pi, pl, ti, tl, TDiv)
  val @(ti, tl) = nid_make2("k", i, "i")
  val () = ui_attr_n(ti, tl, AClass, "cinfo")
  val @(pi, pl) = nid_make2("k", i, "i")
  val @(ti, tl) = nid_make2("k", i, "t")
  val () = ui_add_nn(pi, pl, ti, tl, TDiv)
  val @(ti, tl) = nid_make2("k", i, "t")
  val () = ui_attr_n(ti, tl, AClass, "bt")
  val tb = $A.alloc<byte>(tn)
  val () = _copy(t, tn, tb, 0, 0)
  val @(ti, tl) = nid_make2("k", i, "t")
  val () = ui_text_n_buf(ti, tl, tb, tn)
  val @(pi, pl) = nid_make2("k", i, "i")
  val @(ai, al) = nid_make2("k", i, "a")
  val () = ui_add_nn(pi, pl, ai, al, TDiv)
  val @(ai, al) = nid_make2("k", i, "a")
  val () = ui_attr_n(ai, al, AClass, "ba")
  val ab = $A.alloc<byte>(an)
  val () = _copy(a, an, ab, 0, 0)
  val @(ai, al) = nid_make2("k", i, "a")
  val () = ui_text_n_buf(ai, al, ab, an)
  (* progress *)
  val @(pi, pl) = nid_make2("k", i, "i")
  val @(gi, gl) = nid_make2("k", i, "p")
  val () = ui_add_nn(pi, pl, gi, gl, TDiv)
  val @(gi, gl) = nid_make2("k", i, "p")
  val () = ui_attr_n(gi, gl, AClass, "prog")
  val per = _progress(x)
in
  if x.done > 0 then let
    val @(gi, gl) = nid_make2("k", i, "p")
  in ui_text_n(gi, gl, "Done") end
  else if x.opened <= 0 then let
    val @(gi, gl) = nid_make2("k", i, "p")
  in ui_text_n(gi, gl, "New") end
  else let
    val @(pi, pl) = nid_make2("k", i, "p")
    val @(bi, bl) = nid_make2("k", i, "b")
    val () = ui_add_nn(pi, pl, bi, bl, TDiv)
    val @(bi, bl) = nid_make2("k", i, "b")
    val () = ui_attr_n(bi, bl, AClass, "pbar")
    val @(pi, pl) = nid_make2("k", i, "b")
    val @(fi, fl) = nid_make2("k", i, "f")
    val () = ui_add_nn(pi, pl, fi, fl, TDiv)
    val @(fi, fl) = nid_make2("k", i, "f")
    val () = ui_attr_n(fi, fl, AClass, "pfill")
    (* "width:N%" *)
    val sb = $A.alloc<byte>(24)
    val () = $A.write_text(sb, 0, $A.text_lit("width:"), 6)
    val off = $S.int_to_str(sb, 6, 24, per)
    val () = $A.set<byte>(sb, off, $A.int2byte(37))
    val @(fi, fl) = nid_make2("k", i, "f")
    val () = ui_attr_n_buf(fi, fl, AStyle, sb, off + 1)
    val @(pi, pl) = nid_make2("k", i, "p")
    val @(xi, xl) = nid_make2("k", i, "x")
    val () = ui_add_nn(pi, pl, xi, xl, TSpan)
    val pb = $A.alloc<byte>(16)
    val k = _percent(pb, per)
    val @(xi, xl) = nid_make2("k", i, "x")
  in ui_text_n_buf(xi, xl, pb, k) end
end

fun _cards {k:nat}{i:nat} .<k>. (bs: !books(k), i: int i, shelf: int, q: !query, gen: int, shown: int): int =
  case+ bs of
  | books_nil() => shown
  | books_cons(b, rest) => let
      val+ Book(_, _, _, _, x) = b
      val vis = (if x.shelf = shelf then _matches(b, q) else false): bool
      val () = (if vis then _card(b, i, gen) else ())
    in _cards(rest, i + 1, shelf, q, gen, (if vis then shown + 1 else shown)) end

(* Renders the library view: the cards of the shelf shown whose title
   or author matches the query, in the sort order *)
#pub fn lib_render (): void

implement lib_render () = let
  val () = !_render_gen := !_render_gen + 1
  val gen = !_render_gen
  val () = ui_clear("qlst")
  val shelf = !_shelf
  val q = query_take()
  val c = lib_take()
  val+ @LibCell(bs, k) = c
  val shown = _cards(bs, 0, shelf, q, gen, 0)
  prval () = fold@(c)
  val () = lib_put(c)
  val has_q = (case+ q of QuerySome(_, _) => true | QueryNone() => false): bool
  val () = query_put(q)
  val () = ui_show("qelb", shown = 0)
in
  if shown > 0 then ()
  else if has_q then ui_text("qelb", "No books match")
  else if shelf = 1 then ui_text("qelb", "No hidden books")
  else if shelf = 2 then ui_text("qelb", "No archived books")
  else if shelf = 3 then ui_text("qelb", "The Trash is empty")
  else ui_text("qelb", "Import an EPUB file to start reading.")
end

(* Shows shelf s (0 the shelf, 1 hidden, 2 archived, 3 the Trash) *)
#pub fn lib_shelf_set (s: int): void

implement lib_shelf_set (s) = let
  val () = !_shelf := s
in
  if s = 1 then ui_text("qshf", "Hidden")
  else if s = 2 then ui_text("qshf", "Archived")
  else if s = 3 then ui_text("qshf", "Trash")
  else ui_text("qshf", "Library")
end

(* The sort button's label for order o *)
#pub fn lib_sort_label (o: int): void

implement lib_sort_label (o) =
  if o = 1 then ui_text("qsrt", "Sort: Title")
  else if o = 2 then ui_text("qsrt", "Sort: Author")
  else if o = 3 then ui_text("qsrt", "Sort: Date added")
  else ui_text("qsrt", "Sort: Last opened")

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
