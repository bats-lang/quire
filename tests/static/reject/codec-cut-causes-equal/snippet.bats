(* a cut short and a length over the limit are not the same cut *)
prfn _static_cut_causes_equal {chunks:pchunks}
  (): EQSQ(sq_cut(chunks, sc_trunc()), sq_cut(chunks, sc_big())) = EQSQ_refl()
