prfn _static_no_with_the_letters {cells:$A.cells}{i:nat} (p0: BYTEAT(cells, i, 101), p1: BYTEAT(cells, i + 1, 110), p2: BYTEAT(cells, i + 2, 99), p3: BYTEAT(cells, i + 3, 111),
  p4: BYTEAT(cells, i + 4, 100), p5: BYTEAT(cells, i + 5, 105), p6: BYTEAT(cells, i + 6, 110), p7: BYTEAT(cells, i + 7, 103)): ISENCODING(cells, i, false) =
  ISENCODING_no(p0, p1, p2, p3, p4, p5, p6, p7)
