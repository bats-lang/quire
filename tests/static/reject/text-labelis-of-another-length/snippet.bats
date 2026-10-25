prfn _static_label_another_length {cells:$A.cells}{from,count:nat}{label:bytes} (lowered: LOWERED(cells, from, label), label_len: LEN(label, count)): LABELIS(cells, from, count + 1, label) =
  LABELIS_mk(lowered, label_len)
