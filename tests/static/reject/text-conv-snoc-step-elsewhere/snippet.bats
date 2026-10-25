prfn _static_conv_snoc_elsewhere {cells:$A.cells}{source:tsrc}{from,mid,after:nat | from <= mid; mid < after}{point:int}{octets,enc,joined:bytes}
  (conv: CONV(cells, source, from, mid, octets), step: STEPOF(cells, source, mid + 1, after, point), put: ENC(point, enc), joined: APPEND(octets, enc, joined)): CONV(cells, source, from, after, joined) =
  conv_snoc(conv, step, put, joined)
