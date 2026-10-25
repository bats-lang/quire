prfn _static_same_length {cells:$A.cells}{from,count:nat}{label:bytes} (label_len: LEN(label, count)): LABELDIFF(cells, from, count, label) = LABELDIFF_length(label_len)
