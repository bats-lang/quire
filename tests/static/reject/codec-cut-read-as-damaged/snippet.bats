(* the groups read before a cut are used: the record is not damaged *)
prfn _static_cut_read_as_damaged {spec_list:specs}{spec_n:nat}{format_version,least_version:int}{chunks,canonical:pchunks}{chunk_count,canonical_count:nat}{dropped:lost}{vals:gvals}{kept_extras:extras}{missing:absent}{cause:seqcause}
  (specn: SPECN(spec_list, spec_n), count: PCN(chunk_count, chunks), canon: CANON(spec_list, spec_n, chunks, canonical, dropped), canonical_count_proof: PCN(canonical_count, canonical),
   schema: SDEC(spec_list, spec_list, spec_n, canonical, sd_ok(vals, kept_extras, missing)))
  : FIN(spec_list, format_version, least_version, sq_cut(chunks, cause), rr_damaged()) =
  FIN_cut(specn, count, canon, canonical_count_proof, schema, JOIN_ok_cut())
