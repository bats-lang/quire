prfn _static_reencode_differs {sp:specs}{kind:int}{x:rx}{bs,other:bytes}
  (decoded: DECODES(sp, kind, bs, rr_ok(x))): ENCODES(sp, kind, x, other) = decodes_encodes(decoded)
