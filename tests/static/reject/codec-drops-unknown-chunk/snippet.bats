(* a chunk kept is read back: what is written with kept chunks is not read back without them *)
prfn _static_drops_extras {sp:specs}{kind,ver,minver:int}{vals:gvals}{e:extras}{missing:absent}{bs:bytes}
  (encoded: ENCODES(sp, kind, rx_mk(ver, minver, vals, e, missing), bs)): DECODES(sp, kind, bs, rr_ok(rx_mk(ver, minver, vals, ex_nil(), missing))) = encodes_decodes(encoded)
