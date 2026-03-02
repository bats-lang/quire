(* epub -- EPUB import pipeline *)
(* Steps: file_input → sha256 → zip parse → xml parse → IDB store *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use result as R
#use str as S

(* ============================================================
   EPUB import result
   ============================================================ *)

#pub datatype epub_meta =
  | epub_meta_mk of (
      int,    (* title_len *)
      int,    (* author_len *)
      int     (* spine_count *)
    )

(* ============================================================
   Import entry point (stub — will be async with promises)
   ============================================================ *)

(* Start EPUB import from file data.
   Returns metadata on success. *)
#pub fn epub_import_start(): void

(* ============================================================
   Implementations (stubs for now)
   ============================================================ *)

implement epub_import_start () = ()
