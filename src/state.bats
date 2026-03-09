(* state -- application state types for quire *)

#include "share/atspre_staload.hats"

(* ============================================================
   Book info
   ============================================================ *)

#pub datatype book_info =
  | BookInfo of (string, string)  (* title, author *)

(* ============================================================
   Book list
   ============================================================ *)

#pub datatype book_list =
  | BNil
  | BCons of (book_info, book_list)

(* ============================================================
   App state
   ============================================================ *)

#pub datatype app_state =
  | AppState of (book_list)

(* ============================================================
   Constructors
   ============================================================ *)

#pub fun empty_state(): app_state

implement empty_state() = AppState(BNil())

(* ============================================================
   Queries
   ============================================================ *)

#pub fun is_library_empty(st: app_state): bool

implement is_library_empty(st) =
  case+ st of
  | AppState(BNil()) => true
  | AppState(BCons(_, _)) => false

(* ============================================================
   Mutations
   ============================================================ *)

#pub fun add_book(st: app_state, b: book_info): app_state

implement add_book(st, b) =
  case+ st of
  | AppState(bl) => AppState(BCons(b, bl))
