(* a chunk dropped because its tag is twice is said: the tag is among those dropped *)
prfn _static_dropped_unsaid {tag,data,later:bytes}{rest,others:pchunks}{dropped:lost}
  (sub: EXT(tag, rest, sel_good(later), others, dropped))
  : EXT(tag, pgood(tag, data, rest), sel_good(later), others, dropped) =
  EXT_good_shadowed(sub)
