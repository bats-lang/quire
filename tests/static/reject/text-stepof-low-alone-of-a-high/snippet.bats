prfn _static_low_alone_of_high {cells:$A.cells}{order:byteorder}{i:nat} (one: UNIT16(cells, order, i, 55296)): STEPOF(cells, SrcUtf16(order), i, i + 2, 65533) = STEPOF_low_alone(one)
