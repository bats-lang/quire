(* pages -- the rolling window of page arenas: the arenas of the page
   shown and of the 2 pages before and after it *)

#include "share/atspre_staload.hats"

#use array as A

(* The bytes of a page's arena: generous for a page's text and images *)
#pub stadef PAGE_BYTES = 4194304

(* The arena of page `page` of a chapter of `pages` pages, with no piece
   out, so it can be released at any time, and the `used` bytes of it
   handed out: none for a page outside the chapter, or when its memory
   cannot be had; lent while a buffer holds a piece of it (page_lend) *)
#pub datavtype page_arena(page:int, pages:int) =
  | {arena_loc:agz}{used:nat | used <= PAGE_BYTES; 0 <= page; page < pages}
    PageArena(page, pages) of ($A.arena(byte, arena_loc, PAGE_BYTES, used, 0), int used)
  | {0 <= page; page < pages} Lent(page, pages) of ()
  | NoPageArena(page, pages) of ()

(* The window at page `page` of `pages`: the arenas of pages page - 2 to
   page + 2, and no others *)
#pub datavtype window(page:int, pages:int) =
  | Window(page, pages) of (page_arena(page - 2, pages), page_arena(page - 1, pages),
      page_arena(page, pages), page_arena(page + 1, pages), page_arena(page + 2, pages))

#pub fn page_arena_new {page,pages:int} (page: int page, pages: int pages): page_arena(page, pages)

#pub fn page_arena_free {page,pages:int} (slot: page_arena(page, pages)): void

#pub fn window_new {pages:pos}{page:nat | page < pages} (page: int page, pages: int pages): window(page, pages)

#pub fn window_free {page,pages:int} (window: window(page, pages)): void

(* The window one page on: page page - 2's arena is released and page
   page + 3's made *)
#pub fn window_forward {page,pages:int} (window: window(page, pages), page: int page, pages: int pages): window(page + 1, pages)

(* The window one page back: page page + 2's arena is released and page
   page - 3's made *)
#pub fn window_back {page,pages:int} (window: window(page, pages), page: int page, pages: int pages): window(page - 1, pages)

(* The window at page `page` of `pages`, from the window at old_page of
   old_pages: rotated when page is one page from old_page in the same
   chapter, else released and made anew *)
#pub fn window_move {old_page,old_pages:int}{pages:pos}{page:nat | page < pages}
  (window: window(old_page, old_pages), old_page: int old_page, old_pages: int old_pages,
   page: int page, pages: int pages): window(page, pages)

(* The reader's window, with the page and page count it is at *)
#pub datavtype reader_window =
  | {pages:pos}{page:nat | page < pages} ReaderWindow of (int page, int pages, window(page, pages))
  | NoReaderWindow of ()

(* Moves the reader's window to page `page` of `pages`, making it if
   there is none *)
#pub fun window_show {pages:pos}{page:nat | page < pages} (page: int page, pages: int pages): void

(* Releases the reader's window, when the book is closed *)
#pub fun window_close (): void

(* A piece of piece_size bytes of the current page's arena, and that
   arena, with the page `page` of `pages` it belongs to and the bytes
   `used` of it handed out: the arena is out of the window (its slot
   Lent) until page_give_back *)
#pub datavtype page_lend(piece_size:int) =
  | {arena_loc,piece_loc:agz}{used:nat | used <= PAGE_BYTES}{page,pages:int | 0 <= page; page < pages}
    PageLent(piece_size) of ($A.arena(byte, arena_loc, PAGE_BYTES, used, 1),
      $A.arrx(byte, piece_loc, piece_size, arena_loc), int page, int pages, int used)
  | NoLend(piece_size) of ()

(* piece_size bytes of the current page's arena: none when there is no
   window, the page has no arena, it is lent, or the bytes do not fit *)
#pub fun page_lend {piece_size:pos} (piece_size: int piece_size): page_lend(piece_size)

(* Gives the piece back to its page's arena, and the arena back to its
   slot when the window is still at page `page` of `pages`; otherwise
   (the window moved while the arena was out) the arena is released *)
#pub fun page_give_back {arena_loc,piece_loc:agz}{piece_size:nat}{used:nat | used <= PAGE_BYTES}
  {page,pages:int | 0 <= page; page < pages}
  (arena: $A.arena(byte, arena_loc, PAGE_BYTES, used, 1), piece: $A.arrx(byte, piece_loc, piece_size, arena_loc),
   page: int page, pages: int pages, used: int used): void

implement page_arena_new {page,pages} (page, pages) =
  if page < 0 then NoPageArena()
  else if page >= pages then NoPageArena()
  else (case+ $A.arena_create<byte>(4194304) of
    | ~$A.arena_none() => NoPageArena()
    | ~$A.arena_some(arena) => PageArena(arena, 0))

implement page_arena_free (slot) =
  case+ slot of
  | ~PageArena(arena, _) => $A.arena_destroy<byte>(arena)
  | ~Lent() => ()
  | ~NoPageArena() => ()

implement window_new {pages}{page} (page, pages) =
  Window(page_arena_new(page - 2, pages), page_arena_new(page - 1, pages),
    page_arena_new(page, pages), page_arena_new(page + 1, pages), page_arena_new(page + 2, pages))

implement window_free (window) = let
  val+ ~Window(two_back, one_back, current, one_on, two_on) = window
  val () = page_arena_free(two_back)
  val () = page_arena_free(one_back)
  val () = page_arena_free(current)
  val () = page_arena_free(one_on)
in page_arena_free(two_on) end

implement window_forward (window, page, pages) = let
  val+ ~Window(two_back, one_back, current, one_on, two_on) = window
  val () = page_arena_free(two_back)
in Window(one_back, current, one_on, two_on, page_arena_new(page + 3, pages)) end

implement window_back (window, page, pages) = let
  val+ ~Window(two_back, one_back, current, one_on, two_on) = window
  val () = page_arena_free(two_on)
in Window(page_arena_new(page - 3, pages), two_back, one_back, current, one_on) end

implement window_move (window, old_page, old_pages, page, pages) =
  if old_pages = pages then
    (if page = old_page + 1 then window_forward(window, old_page, old_pages)
     else if page + 1 = old_page then window_back(window, old_page, old_pages)
     else if page = old_page then window
     else let val () = window_free(window) in window_new(page, pages) end)
  else let val () = window_free(window) in window_new(page, pages) end

fn reader_window_free (held: reader_window): void =
  case+ held of
  | ~ReaderWindow(_, _, window) => window_free(window)
  | ~NoReaderWindow() => ()

val _window = ref<reader_window>(NoReaderWindow())

(* The reader's window, taken out of its cell: the cell is left with
   none *)
fn window_take (): reader_window = let
  var held: reader_window = NoReaderWindow()
  val () = ref_exch_elt<reader_window>(_window, held)
in held end

(* Puts `held` in the reader's cell, releasing what was there *)
fn window_put (held: reader_window): void = let
  var previous: reader_window = held
  val () = ref_exch_elt<reader_window>(_window, previous)
in reader_window_free(previous) end

implement window_show {pages}{page} (page, pages) = let
  val held = window_take()
  val window = (case+ held of
    | ~ReaderWindow(old_page, old_pages, old_window) => window_move(old_window, old_page, old_pages, page, pages)
    | ~NoReaderWindow() => window_new(page, pages)): window(page, pages)
in window_put(ReaderWindow(page, pages, window)) end

implement window_close () = reader_window_free(window_take())

implement page_lend {piece_size} (piece_size) = let
  val held = window_take()
in
  case+ held of
  | ~NoReaderWindow() => let
      val () = window_put(NoReaderWindow())
    in NoLend() end
  | ~ReaderWindow(page, pages, window) => let
      val+ ~Window(two_back, one_back, current, one_on, two_on) = window
    in
      case+ current of
      | ~PageArena(arena, used) =>
        if used + piece_size <= 4194304 then let
          val piece = $A.arena_alloc<byte>(arena, piece_size)
          val () = window_put(ReaderWindow(page, pages, Window(two_back, one_back, Lent(), one_on, two_on)))
        in PageLent(arena, piece, page, pages, used + piece_size) end
        else let
          val () = window_put(ReaderWindow(page, pages, Window(two_back, one_back, PageArena(arena, used), one_on, two_on)))
        in NoLend() end
      | current => let
          val () = window_put(ReaderWindow(page, pages, Window(two_back, one_back, current, one_on, two_on)))
        in NoLend() end
    end
end

implement page_give_back (arena, piece, page, pages, used) = let
  val () = $A.arena_return<byte>(arena, piece)
  val held = window_take()
in
  case+ held of
  | ~NoReaderWindow() => let
      val () = $A.arena_destroy<byte>(arena)
    in window_put(NoReaderWindow()) end
  | ~ReaderWindow(window_page, window_pages, window) =>
    if window_page = page then
      (if window_pages = pages then let
         val+ ~Window(two_back, one_back, current, one_on, two_on) = window
       in
         case+ current of
         | ~Lent() => window_put(ReaderWindow(window_page, window_pages,
             Window(two_back, one_back, PageArena(arena, used), one_on, two_on)))
         | current => let
             val () = $A.arena_destroy<byte>(arena)
           in window_put(ReaderWindow(window_page, window_pages, Window(two_back, one_back, current, one_on, two_on))) end
       end
       else let
         val () = $A.arena_destroy<byte>(arena)
       in window_put(ReaderWindow(window_page, window_pages, window)) end)
    else let
      val () = $A.arena_destroy<byte>(arena)
    in window_put(ReaderWindow(window_page, window_pages, window)) end
end
