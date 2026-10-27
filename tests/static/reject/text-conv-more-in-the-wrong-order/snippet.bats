prfn _static_conv_wrong_order {cells:$A.cells}{source:tsrc}{i,j,m:nat | i < j; j <= m}{point:int}{enc,rest:bytes}{rest_count:nat}
  (step: STEPOF(cells, source, i, j, point), put: ENC(point, enc), conv: CONV(cells, source, j, m, rest), rest_len: LEN(rest, rest_count)): [octets:bytes] CONV(cells, source, i, m, octets) =
  CONV_more(step, put, conv, append_exists(rest_len))
