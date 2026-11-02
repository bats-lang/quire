(* what was lost is a tag or a cut: a match that leaves the cut out is refused *)
fn _static_lost_unmatched {lost_tags:lost}{lost_count:nat} (lost: lostv(lost_tags, lost_count)): int =
  case+ lost of
  | ~LTV_nil() => 0
