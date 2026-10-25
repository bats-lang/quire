prfn _static_conv_other_point {cells:$A.cells}{source:int}{i,j,m:nat | i < j; j <= m}{point:int}{enc,rest,octets:bytes}
  (step: STEPOF(cells, source, i, j, point), put: ENC(point + 1, enc), conv: CONV(cells, source, j, m, rest), joined: APPEND(enc, rest, octets)): CONV(cells, source, i, m, octets) =
  CONV_more(step, put, conv, joined)
