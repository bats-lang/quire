(* A browser sign-in's answer with the code bridge never gives left out:
   an unexpected answer would be dropped unsaid (keyword: google-token-answer) *)
fn _static_answer (answer: $GOOGLE.token_answer): bool =
  case+ answer of
  | ~$GOOGLE.TokenCanceled() => false
