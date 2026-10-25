prfn _static_conv_snoc_other_way {cells:$A.cells}{source:tsrc}{from,mid,after:nat | from <= mid; mid < after}{point:int}{octets,enc:bytes}{enc_count:nat}
  (conv: CONV(cells, source, from, mid, octets), step: STEPOF(cells, source, mid, after, point), put: ENC(point, enc), enc_len: LEN(enc, enc_count)): [joined:bytes] CONV(cells, source, from, after, joined) =
  conv_snoc(conv, step, put, append_exists(enc_len))
