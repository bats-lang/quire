(* a group the record needs, left out of a record, is lost: the record is read, with the group's defaults standing in for it *)
prfn _static_required_group_lost {known,more:specs}{spec_n:nat}{tag:bytes}{kinds:layout}{defaults:fvals}{rest_result,whole_result:sdres}
  (sub: SDEC(known, more, spec_n, pnil(), rest_result), prepend: PREPL(defaults, tag, rest_result, whole_result))
  : SDEC(known, gs_cons(tag, kinds, m_req(), defaults, more), spec_n+1, pnil(), whole_result) =
  SD_absent_lost_end(LOSES_req(), sub, prepend)
