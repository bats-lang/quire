(* a group added to the format after the record was written is written as nothing, and reads back absent *)
prfn _static_absent_added_written {known:specs}{tag:bytes}{kinds:layout}{defaults:fvals}{more:specs}{spec_n:nat}{vals:gvals}{kept:extras}{missing:absent}
  (rest: SENC(known, more, spec_n, vals, kept, missing, pnil())): SENC(known, gs_cons(tag, kinds, m_added(), defaults, more), spec_n+1, gv_cons(defaults, vals), kept, ab_cons(tag, missing), pnil()) =
  SENC_absent_end(rest)
