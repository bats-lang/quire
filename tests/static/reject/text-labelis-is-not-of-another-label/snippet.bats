prfn _static_another_label {cells:$A.cells}{from,count:nat}{label,other:bytes} (is: LABELIS(cells, from, count, label), diff: LABELDIFF(cells, from, count, other)): FALSEP() =
  labelis_not_diff(is, diff)
