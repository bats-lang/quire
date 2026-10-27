prfn _static_two_lengths {cells:$A.cells}{from,count:nat}{first,second:bytes} (one: LOWERED(cells, from, first), other: LOWERED(cells, from, second), first_len: LEN(first, count), second_len: LEN(second, count + 1))
  : EQB(first, second) = lowered_functional(one, other, first_len, second_len)
