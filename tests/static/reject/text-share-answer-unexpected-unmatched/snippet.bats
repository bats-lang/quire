(* A text share's answer with the code bridge never gives left out:
   an unexpected answer would be dropped unsaid (keyword: share-text-answer) *)
fn _static_answer (answer: $SH.text_share_answer): bool =
  case+ answer of
  | ~$SH.TextAnswerShared() => true
