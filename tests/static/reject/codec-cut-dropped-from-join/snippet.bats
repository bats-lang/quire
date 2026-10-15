(* the loss of a cut record names the cut *)
prfn _static_join_forgets_cut {format_version,least_version:int}{vals:gvals}{kept_extras:extras}{missing:absent}{cause:seqcause}{dropped,lost_groups:lost}{dropped_n:nat}
  (cat: LOSTCAT(dropped, lost_groups, lost_groups, dropped_n))
  : JOIN(format_version, least_version, lt_cut(cause, dropped), sd_loss(vals, kept_extras, lost_groups, missing), rr_loss(rx_mk(format_version, least_version, vals, kept_extras, missing), lost_groups)) =
  JOIN_loss(cat)
