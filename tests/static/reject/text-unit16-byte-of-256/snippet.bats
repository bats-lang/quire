prfn _static_byte_of_256 {cells:$A.cells}{i:nat}{second:int | 0 <= second; second < 256} (one: $A.NTH(cells, i, 256), two: $A.NTH(cells, i + 1, second)): UNIT16(cells, 1, i, 256 + 256 * second) =
  UNIT16_le(one, two)
