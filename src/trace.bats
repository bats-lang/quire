(* trace -- a diagnostic line in the page's console (the Android app's
   logcat), for the smoke test's evidence (quire#184's smoke failure) *)

#include "share/atspre_staload.hats"
#use array as A
staload WN = "wasm.bats-packages.dev/bridge/src/window.sats"
staload "mem.sats"

#target wasm begin

(* Writes "quire-trace: " and what to the console *)
#pub fn trace {n:pos | n < 256} (what: string n): void

implement trace (what) = let
  val n = g1u2i(string1_length(what))
  val line = $A.alloc<byte>(n + 13)
  val () = $A.write_text(line, 0, $A.text_lit("quire-trace: "), 13)
  val () = $A.write_text(line, 13, $A.text_lit(what), n)
  val @(frozen, borrowed) = $A.freeze<byte>(line)
  val () = $WN.log($WN.Info(), borrowed, n + 13)
in release_bytes(frozen, borrowed) end

end (* #target wasm *)
