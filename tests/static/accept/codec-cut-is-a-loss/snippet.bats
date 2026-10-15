(* a record cut in its framing whose groups before the cut are read is a loss that names the cut *)
prfn _accept_cut_is_a_loss {spec_list:specs}{spec_n:nat}{format_version,least_version:int}{chunks,canonical:pchunks}{chunk_count,canonical_count:nat}{dropped:lost}{vals:gvals}{kept_extras:extras}{missing:absent}{cause:seqcause}
  (specn: SPECN(spec_list, spec_n), count: PCN(chunk_count, chunks), canon: CANON(spec_list, spec_n, chunks, canonical, dropped), canonical_count_proof: PCN(canonical_count, canonical),
   schema: SDEC(spec_list, spec_list, spec_n, canonical, sd_ok(vals, kept_extras, missing)))
  : FIN(spec_list, format_version, least_version, sq_cut(chunks, cause), rr_loss(rx_mk(format_version, least_version, vals, kept_extras, missing), lt_cut(cause, dropped))) =
  FIN_cut(specn, count, canon, canonical_count_proof, schema, JOIN_ok_cut())
