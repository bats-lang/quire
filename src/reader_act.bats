(* reader_act -- what the reader did that takes the bars or the first-book hint away
   (keyword: reader acts, #560) *)

(* The reader's bars and the hint on turning pages go when the reader acts and at no other time:
   hiding either takes the act, so a timer, which has none to pass, does not hide them. The back
   button's own timeout is a different thing (back.bats, TIMED) *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "ui.sats"

#pub datatype reader_act =
  | ActMiddleTap
  | ActPageTurn
  | ActJump
  | ActEscape
  | ActHintTap
  | ActFirstOpen

(* The hint on turning pages goes at the first page turn, however it is made, and on a tap on the
   hint itself; every other act leaves it *)
#pub fun hint_hide (act: reader_act): void

implement hint_hide (act) =
  case+ act of
  | ActPageTurn() => ui_show("turn-hint", false)
  | ActHintTap() => ui_show("turn-hint", false)
  | ActMiddleTap() => ()
  | ActJump() => ()
  | ActEscape() => ()
  | ActFirstOpen() => ()

end (* #target wasm *)
