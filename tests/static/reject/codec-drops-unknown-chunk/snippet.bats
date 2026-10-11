prfn _static_drops_extras {sp:specs}{kind,ver,minver:int}{vals:gvals}{e:extras}{missing:absent}{bs:bytes}
  (decoded: DECODES(sp, kind, bs, rr_ok(rx_mk(ver, minver, vals, e, missing)))): ENCODES(sp, kind, rx_mk(ver, minver, vals, ex_nil(), missing), bs) = decodes_encodes(decoded)
