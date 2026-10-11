(* an absent group holds its defaults, not other values: else a record would read as values it never held *)
prfn _static_absent_other_values {known:specs}{tag:bytes}{kinds:layout}{defaults,other:fvals}{more:specs}{spec_n:nat}{vals:gvals}{kept:extras}{missing:absent}
  (rest: SENC(known, more, spec_n, vals, kept, missing, pnil())): SENC(known, gs_cons(tag, kinds, m_added(), defaults, more), spec_n+1, gv_cons(other, vals), kept, ab_cons(tag, missing), pnil()) =
  SENC_absent_end(rest)
