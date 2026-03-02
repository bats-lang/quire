(* theme -- CSS generation for quire *)

#include "share/atspre_staload.hats"

#use builder as B

(* ============================================================
   Base CSS for the application
   ============================================================ *)

#pub fn emit_base_css(b: !$B.builder): void

(* ============================================================
   Implementations
   ============================================================ *)

implement emit_base_css (b) = let
  val () = $B.bput(b, "body { margin: 0; font-family: system-ui, sans-serif; }\n")
  val () = $B.bput(b, ".library-list { padding: 16px; }\n")
  val () = $B.bput(b, ".empty-lib { text-align: center; padding: 48px 16px; color: #888; }\n")
  val () = $B.bput(b, ".import-btn { display: inline-block; padding: 12px 24px; background: #4a90d9; color: white; border-radius: 8px; cursor: pointer; }\n")
  val () = $B.bput(b, ".import-btn input[type=file] { display: none; }\n")
in end
