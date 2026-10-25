prfn _static_little_as_big {cells:$A.cells}{i:nat}{first,second:int | 0 <= first; first < 256; 0 <= second; second < 256}
  (one: $A.NTH(cells, i, first), two: $A.NTH(cells, i + 1, second)): UNIT16(cells, BigEndian(), i, first + 256 * second) = UNIT16_le(one, two)
