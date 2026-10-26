(* A browser sign-in's answer with the code bridge never gives left out:
   an unexpected answer would be dropped unsaid (keyword: google-token-answer) *)
fn _static_answer (answer: $GOOGLE.token_answer): bool =
  case+ answer of
  | ~$GOOGLE.TokenGiven(token, account) => let
      val () = (case+ account of ~$R.some(named) => $BD.blob_free(named) | ~$R.none() => ())
      val () = $BD.blob_free(token)
    in true end
  | ~$GOOGLE.TokenCanceled() => false
  | ~$GOOGLE.TokenRefused(text) => (case+ text of ~$R.some(blob) => let val () = $BD.blob_free(blob) in false end | ~$R.none() => false)
  | ~$GOOGLE.TokenNotHere() => false
  | ~$GOOGLE.TokenLoadFailed(text) => (case+ text of ~$R.some(blob) => let val () = $BD.blob_free(blob) in false end | ~$R.none() => false)
  | ~$GOOGLE.TokenThrown(text) => (case+ text of ~$R.some(blob) => let val () = $BD.blob_free(blob) in false end | ~$R.none() => false)
  | ~$GOOGLE.TokenAnswerUnread(text) => (case+ text of ~$R.some(blob) => let val () = $BD.blob_free(blob) in false end | ~$R.none() => false)

