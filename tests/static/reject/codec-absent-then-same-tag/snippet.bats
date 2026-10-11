(* a group left out cannot be followed by a chunk of its own tag ("prog"): that chunk would be read as the group *)
prfn _static_absent_then_same_tag {known:specs}{data:bytes}{kinds:layout}{defaults:fvals}{more:specs}{spec_n:nat}{vals:gvals}{kept:extras}{missing:absent}{rest:pchunks}
  (sub: SENC(known, more, spec_n, vals, kept, missing, pgood(bcons(112, bcons(114, bcons(111, bcons(103, bnil())))), data, rest)))
  : SENC(known, gs_cons(bcons(112, bcons(114, bcons(111, bcons(103, bnil())))), kinds, m_added(), defaults, more), spec_n+1, gv_cons(defaults, vals), kept,
         ab_cons(bcons(112, bcons(114, bcons(111, bcons(103, bnil())))), missing), pgood(bcons(112, bcons(114, bcons(111, bcons(103, bnil())))), data, rest)) =
  SENC_absent_good(TAGDIFF_mk(), sub)
