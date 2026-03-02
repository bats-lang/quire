(* reader -- chapter loading, pagination, navigation *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use result as R

(* ============================================================
   Reader state
   ============================================================ *)

(* Current page within the chapter *)
#pub fn reader_current_page(): int

(* Total pages in current chapter *)
#pub fn reader_total_pages(): int

(* Current chapter index (0-based) *)
#pub fn reader_current_chapter(): int

(* ============================================================
   Navigation
   ============================================================ *)

#pub fn reader_next_page(): void

#pub fn reader_prev_page(): void

#pub fn reader_goto_chapter(idx: int): void

(* ============================================================
   Implementations (stubs)
   ============================================================ *)

implement reader_current_page () = 1

implement reader_total_pages () = 1

implement reader_current_chapter () = 0

implement reader_next_page () = ()

implement reader_prev_page () = ()

implement reader_goto_chapter (idx) = ()
