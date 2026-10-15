(* a record cut in its framing is not read as whole *)
prfn _static_cut_not_said {format_version,least_version:int}{vals:gvals}{kept_extras:extras}{missing:absent}{cause:seqcause}{more:lost}
  (): JOIN(format_version, least_version, lt_cut(cause, more), sd_ok(vals, kept_extras, missing), rr_ok(rx_mk(format_version, least_version, vals, kept_extras, missing))) = JOIN_ok()
