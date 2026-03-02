(* library -- book library management with IDB persistence *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use result as R
#use str as S

(* ============================================================
   Library operations (stubs for Phase 1 — no IDB yet)
   ============================================================ *)

(* Book count in the library *)
#pub fn library_count(): int

(* Check if library is empty *)
#pub fn library_is_empty(): bool

(* ============================================================
   Implementations
   ============================================================ *)

implement library_count () = 0

implement library_is_empty () = true
