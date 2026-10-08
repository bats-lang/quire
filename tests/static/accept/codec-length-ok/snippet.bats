prfn _static_length_ok {b0,b1,b2:int | 0 <= b0; b0 < 256; 0 <= b1; b1 < 256; 0 <= b2; b2 < 16}{n:nat}
  (bytes: LE(3, n, bcons(b0, bcons(b1, bcons(b2, bnil()))))): LENOK(bcons(b0, bcons(b1, bcons(b2, bcons(0, bnil())))), n) = LENOK_mk(bytes)
