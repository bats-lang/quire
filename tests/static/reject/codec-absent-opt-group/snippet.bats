(* a group every version has written (opt) is not absent without being damage: no record holds none *)
prfn _static_absent_opt_group {known:specs}{tag:bytes}{kinds:layout}{defaults:fvals}{more:specs}{spec_n:nat}{vals:gvals}{kept:extras}{missing:absent}
  (rest: SENC(known, more, spec_n, vals, kept, missing, pnil())): SENC(known, gs_cons(tag, kinds, m_opt(), defaults, more), spec_n+1, gv_cons(defaults, vals), kept, ab_cons(tag, missing), pnil()) =
  SENC_absent_end(rest)
