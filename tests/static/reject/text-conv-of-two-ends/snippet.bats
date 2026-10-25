prfn _static_conv_two_ends {cells:$A.cells}{source:int}{from,first_to,second_to:nat | from <= first_to; from <= second_to}{first,second:bytes}
  (one: CONV(cells, source, from, first_to, first), two: CONV(cells, source, from, second_to, second)): EQB(first, second) = conv_functional(one, two)
