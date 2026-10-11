(* what is written reads back as exactly the record written, not as another *)
prfn _static_reads_as_another {sp:specs}{kind:int}{x,y:rx}{bs:bytes}
  (encoded: ENCODES(sp, kind, x, bs)): DECODES(sp, kind, bs, rr_ok(y)) = encodes_decodes(encoded)
