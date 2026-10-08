prfn _static_decoded_encodes {sp:specs}{kind:int}{x:rx}{bs:bytes}
  (decoded: DECODES(sp, kind, bs, rr_ok(x))): ENCODES(sp, kind, x, bs) = decodes_encodes(decoded)

prfn _static_encoded_decodes {sp:specs}{kind:int}{x:rx}{bs:bytes}
  (encoded: ENCODES(sp, kind, x, bs)): DECODES(sp, kind, bs, rr_ok(x)) = encodes_decodes(encoded)
