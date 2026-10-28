(* A text share's answer with the code bridge never gives left out:
   an unexpected answer would be dropped unsaid (keyword: share-text-answer) *)
fn _static_answer (answer: $SH.text_share_answer): bool =
  case+ answer of
  | ~$SH.TextAnswerShared() => true
  | ~$SH.TextAnswerCancelled() => false
  | ~$SH.TextAnswerFailed(text) => (case+ text of ~$R.some(blob) => let val () = $BD.blob_free(blob) in false end | ~$R.none() => false)
  | ~$SH.TextAnswerNotHere() => false
  | ~$SH.TextAnswerRejected(text) => (case+ text of ~$R.some(blob) => let val () = $BD.blob_free(blob) in false end | ~$R.none() => false)
  | ~$SH.TextAnswerThrown(text) => (case+ text of ~$R.some(blob) => let val () = $BD.blob_free(blob) in false end | ~$R.none() => false)
