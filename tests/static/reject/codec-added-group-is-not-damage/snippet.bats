(* a record without an added group is not read as having lost it: only a group the record needs, or that every version has written, is lost *)
prfn _static_added_group_lost {known,more:specs}{spec_n:nat}{tag:bytes}{kinds:layout}{defaults:fvals}{rest_result,whole_result:sdres}
  (sub: SDEC(known, more, spec_n, pnil(), rest_result), prepend: PREPL(defaults, tag, rest_result, whole_result))
  : SDEC(known, gs_cons(tag, kinds, m_added(), defaults, more), spec_n+1, pnil(), whole_result) =
  SD_absent_lost_end(LOSES_req(), sub, prepend)
