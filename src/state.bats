(* state -- application state for quire e-reader *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B

(* ============================================================
   View enum: which screen is active
   ============================================================ *)

#pub datatype view_t =
  | ViewLibrary
  | ViewReader

(* ============================================================
   Book metadata stored in library
   ============================================================ *)

#pub datatype book_meta =
  | book_meta_mk of (
      int,    (* hash_hi: upper 32 bits of SHA-256 *)
      int,    (* hash_lo: lower 32 bits of SHA-256 *)
      int,    (* title_len *)
      int,    (* author_len *)
      int,    (* spine_count: number of chapters *)
      int,    (* current_chapter *)
      int,    (* current_page *)
      int     (* timestamp: last read time *)
    )

(* ============================================================
   Application state
   ============================================================ *)

#pub datavtype app_state =
  | app_state_mk of (
      view_t,       (* current view *)
      int,          (* book_count *)
      int,          (* sort_mode: 0=recent, 1=title, 2=author *)
      int,          (* active_book_idx: -1 if none *)
      int,          (* settings_font_size *)
      int,          (* settings_theme: 0=light, 1=dark, 2=sepia *)
      int           (* settings_margin *)
    )

(* ============================================================
   Constructors and accessors
   ============================================================ *)

#pub fn state_create(): app_state

#pub fn state_view(s: !app_state): view_t

#pub fn state_set_view(s: !app_state >> _, v: view_t): void

#pub fn state_book_count(s: !app_state): int

#pub fn state_set_book_count(s: !app_state >> _, n: int): void

#pub fn state_active_book(s: !app_state): int

#pub fn state_set_active_book(s: !app_state >> _, idx: int): void

#pub fn state_font_size(s: !app_state): int

#pub fn state_theme(s: !app_state): int

#pub fn state_free(s: app_state): void

(* ============================================================
   Implementations
   ============================================================ *)

implement state_create () =
  app_state_mk(ViewLibrary(), 0, 0, ~1, 16, 0, 20)

implement state_view (s) = let
  val+ app_state_mk(v, _, _, _, _, _, _) = s
in v end

implement state_set_view (s, v) = let
  val+ @app_state_mk(view, _, _, _, _, _, _) = s
  val () = view := v
  prval () = fold@(s)
in end

implement state_book_count (s) = let
  val+ app_state_mk(_, n, _, _, _, _, _) = s
in n end

implement state_set_book_count (s, n) = let
  val+ @app_state_mk(_, bc, _, _, _, _, _) = s
  val () = bc := n
  prval () = fold@(s)
in end

implement state_active_book (s) = let
  val+ app_state_mk(_, _, _, idx, _, _, _) = s
in idx end

implement state_set_active_book (s, idx) = let
  val+ @app_state_mk(_, _, _, ab, _, _, _) = s
  val () = ab := idx
  prval () = fold@(s)
in end

implement state_font_size (s) = let
  val+ app_state_mk(_, _, _, _, fs, _, _) = s
in fs end

implement state_theme (s) = let
  val+ app_state_mk(_, _, _, _, _, th, _) = s
in th end

implement state_free (s) = let
  val+ ~app_state_mk(_, _, _, _, _, _, _) = s
in end
