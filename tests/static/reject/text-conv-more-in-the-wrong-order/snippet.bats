prfn _static_conv_wrong_order {cells:$A.cells}{source:int}{i,j,m:nat | i < j; j <= m}{point:int}{enc,rest,octets:bytes}
  (step: STEPOF(cells, source, i, j, point), put: ENC(point, enc), conv: CONV(cells, source, j, m, rest), joined: APPEND(rest, enc, octets)): CONV(cells, source, i, m, octets) =
  CONV_more(step, put, conv, joined)
