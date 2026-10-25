prfn _static_table_of_another {cells:$A.cells} (n0: $A.NTH(cells, 0, 60), n1: $A.NTH(cells, 1, 63), n2: $A.NTH(cells, 2, 120), n3: $A.NTH(cells, 3, 109), n4: $A.NTH(cells, 4, 108), scan: DECLSCAN(cells, 5, SrcTable(Cp1251())))
  : DETECT(cells, SrcTable(Cp1252()), 0) = DETECT_declared_table(n0, n1, n2, n3, n4, scan)
