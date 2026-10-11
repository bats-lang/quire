(* a group's chunk is found wherever it stands: after a chunk of another tag it is chosen, and that chunk stays *)
prfn _static_found_after_another {tag,other,data,more:bytes}{rest,others:pchunks}{dropped:lost}
  (different: TAGDIFF(other, tag), sub: EXT(tag, rest, sel_none(), others, dropped))
  : EXT(tag, pgood(other, more, pgood(tag, data, rest)), sel_good(data), pgood(other, more, others), dropped) =
  EXT_skip_good(different, EXT_good_last(sub))

(* a tag twice: the later whole chunk is chosen, and the earlier one is dropped, said once *)
prfn _static_later_chunk_wins {tag,data,later:bytes}{rest,others:pchunks}{dropped:lost}
  (sub: EXT(tag, rest, sel_good(later), others, dropped))
  : EXT(tag, pgood(tag, data, rest), sel_good(later), others, lt_cons(tag, dropped)) =
  EXT_good_shadowed(sub)
