(* A message that goes by itself, offered with an Undo: a brief life is
   not one undo_offer takes *)
fn _static_brief_offer (): $P.promise(settled, $P.Pending) =
  undo_offer(PlainMessage())

