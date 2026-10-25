prfn _static_utf8_of_utf16 {cells:$A.cells} (n0: $A.NTH(cells, 0, 60), n1: $A.NTH(cells, 1, 63), n2: $A.NTH(cells, 2, 120), n3: $A.NTH(cells, 3, 109), n4: $A.NTH(cells, 4, 108), scan: DECLSCAN(cells, 5, SrcUtf16(BigEndian())))
  : DETECT(cells, SrcUtf8(), 0) = DETECT_declared_utf8(n0, n1, n2, n3, n4, scan)
