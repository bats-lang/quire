prfn _static_conv_elsewhere {cells:$A.cells}{source:int}{i,j,m:nat | i < j; j <= m}{point:int}{enc,rest,octets:bytes}
  (step: STEPOF(cells, source, i + 1, j, point), put: ENC(point, enc), conv: CONV(cells, source, j, m, rest), joined: APPEND(enc, rest, octets)): CONV(cells, source, i, m, octets) =
  CONV_more(step, put, conv, joined)
