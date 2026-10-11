(* a record without an added group is not read as damaged: only a group the record needs is *)
prfn _static_added_group_missing {known,more:specs}{spec_n:pos}{tag:bytes}{kinds:layout}{defaults:fvals}
  (): SDEC(known, gs_cons(tag, kinds, m_added(), defaults, more), spec_n, pnil(), sd_fail(cause_damaged())) =
  SD_missing_end(MUSTHAVE_req())
