(* a record cut before any chunk was read has read no chunk *)
prfn _static_cut_claims_unread_chunk {tag,data:bytes}
  (): SQC(ck_trunc(), sq_cut(pgood(tag, data, pnil()), sc_trunc())) = SQC_short()
