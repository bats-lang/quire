(* of a tag twice the earlier chunk is not the one chosen *)
prfn _static_earlier_chunk_wins {tag,data,later:bytes}{rest,others:pchunks}{dropped:lost}
  (sub: EXT(tag, rest, sel_good(later), others, dropped))
  : EXT(tag, pgood(tag, data, rest), sel_good(data), others, lt_cons(tag, dropped)) =
  EXT_good_shadowed(sub)
