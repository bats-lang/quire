prfn _static_holds_len_one_more {cells:$A.cells}{i,count:nat}{octets:bytes} (holds: HOLDS(cells, i, octets, count)): LEN(octets, count + 1) = holds_len(holds)
