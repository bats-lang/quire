(* pages -- the rolling window of page arenas: the arenas of the page
   shown and of the 2 pages before and after it *)

#include "share/atspre_staload.hats"

#use array as A

(* The bytes of a page's arena: generous for a page's text and images *)
#pub stadef PAGE_BYTES = 4194304

(* The arena of page q of a chapter of t pages, with no piece out, so
   it can be released at any time: none for a page outside the chapter,
   or when its memory cannot be had *)
#pub datavtype page_arena(q:int, t:int) =
  | {la:agz}{u:nat | u <= PAGE_BYTES; 0 <= q; q < t}
    PageArena(q, t) of ($A.arena(byte, la, PAGE_BYTES, u, 0))
  | NoPageArena(q, t) of ()

(* The window at page p of t: the arenas of pages p - 2 to p + 2, and
   no others *)
#pub datavtype window(p:int, t:int) =
  | Window(p, t) of (page_arena(p - 2, t), page_arena(p - 1, t),
      page_arena(p, t), page_arena(p + 1, t), page_arena(p + 2, t))

#pub fn page_arena_new {q,t:int} (q: int q, t: int t): page_arena(q, t)

#pub fn page_arena_free {q,t:int} (a: page_arena(q, t)): void

#pub fn window_new {t:pos}{p:nat | p < t} (p: int p, t: int t): window(p, t)

#pub fn window_free {p,t:int} (w: window(p, t)): void

(* The window one page on: page p - 2's arena is released and page
   p + 3's made *)
#pub fn window_forward {p,t:int} (w: window(p, t), p: int p, t: int t): window(p + 1, t)

(* The window one page back: page p + 2's arena is released and page
   p - 3's made *)
#pub fn window_back {p,t:int} (w: window(p, t), p: int p, t: int t): window(p - 1, t)

(* The window at page p of t, from the window at p0 of t0: rotated when
   p is one page from p0 in the same chapter, else released and made
   anew *)
#pub fn window_move {p0,t0:int}{t:pos}{p:nat | p < t}
  (w: window(p0, t0), p0: int p0, t0: int t0, p: int p, t: int t): window(p, t)

(* The reader's window, with the page and page count it is at *)
#pub datavtype reader_window =
  | {t:pos}{p:nat | p < t} ReaderWindow of (int p, int t, window(p, t))
  | NoReaderWindow of ()

(* Moves the reader's window to page p of t, making it if there is
   none *)
#pub fun window_show {t:pos}{p:nat | p < t} (p: int p, t: int t): void

(* Releases the reader's window, when the book is closed *)
#pub fun window_close (): void

implement page_arena_new {q,t} (q, t) =
  if q < 0 then NoPageArena()
  else if q >= t then NoPageArena()
  else (case+ $A.arena_create<byte>(4194304) of
    | ~$A.arena_none() => NoPageArena()
    | ~$A.arena_some(ar) => PageArena(ar))

implement page_arena_free (a) =
  case+ a of
  | ~PageArena(ar) => $A.arena_destroy<byte>(ar)
  | ~NoPageArena() => ()

implement window_new {t}{p} (p, t) =
  Window(page_arena_new(p - 2, t), page_arena_new(p - 1, t),
    page_arena_new(p, t), page_arena_new(p + 1, t), page_arena_new(p + 2, t))

implement window_free (w) = let
  val+ ~Window(a0, a1, a2, a3, a4) = w
  val () = page_arena_free(a0)
  val () = page_arena_free(a1)
  val () = page_arena_free(a2)
  val () = page_arena_free(a3)
in page_arena_free(a4) end

implement window_forward (w, p, t) = let
  val+ ~Window(a0, a1, a2, a3, a4) = w
  val () = page_arena_free(a0)
in Window(a1, a2, a3, a4, page_arena_new(p + 3, t)) end

implement window_back (w, p, t) = let
  val+ ~Window(a0, a1, a2, a3, a4) = w
  val () = page_arena_free(a4)
in Window(page_arena_new(p - 3, t), a0, a1, a2, a3) end

implement window_move (w, p0, t0, p, t) =
  if t0 = t then
    (if p = p0 + 1 then window_forward(w, p0, t0)
     else if p + 1 = p0 then window_back(w, p0, t0)
     else if p = p0 then w
     else let val () = window_free(w) in window_new(p, t) end)
  else let val () = window_free(w) in window_new(p, t) end

fn reader_window_free (rw: reader_window): void =
  case+ rw of
  | ~ReaderWindow(_, _, w) => window_free(w)
  | ~NoReaderWindow() => ()

val _window = ref<reader_window>(NoReaderWindow())

(* The reader's window, taken out of its cell: the cell is left with
   none *)
fn window_take (): reader_window = let
  var rw: reader_window = NoReaderWindow()
  val () = ref_exch_elt<reader_window>(_window, rw)
in rw end

(* Puts rw in the reader's cell, releasing what was there *)
fn window_put (rw: reader_window): void = let
  var cur: reader_window = rw
  val () = ref_exch_elt<reader_window>(_window, cur)
in reader_window_free(cur) end

implement window_show {t}{p} (p, t) = let
  val rw = window_take()
  val w = (case+ rw of
    | ~ReaderWindow(p0, t0, old) => window_move(old, p0, t0, p, t)
    | ~NoReaderWindow() => window_new(p, t)): window(p, t)
in window_put(ReaderWindow(p, t, w)) end

implement window_close () = reader_window_free(window_take())
