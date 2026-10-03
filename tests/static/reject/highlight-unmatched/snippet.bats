(* A kind's mark with the underlined highlight forgotten: it would be
   marked as no style the stylesheet has *)
fn _static_mark (kind: annotation_kind): int =
  case+ kind of
  | Bookmark() => 0
  | YellowHighlight() => 1
  | OrangeHighlight() => 3
