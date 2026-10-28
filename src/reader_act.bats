(* reader acts: what takes the bars or the first-book hint away; a hiding call names the act that did it *)

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

(* reader acts: the hint goes on a page turn or a tap on it *)
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
