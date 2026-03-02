(* views -- all UI rendering via widget/dom diff *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B

(* ============================================================
   Library view: empty state with import button
   ============================================================ *)

(* Render the library view into the DOM diff buffer.
   For Phase 1, this just renders the empty library message
   and import button. *)
#pub fn render_library_empty
  {l:agz}
  (buf: !$A.arr(byte, l, 524288)): void

(* ============================================================
   Implementations
   ============================================================ *)

implement render_library_empty (buf) = ()
