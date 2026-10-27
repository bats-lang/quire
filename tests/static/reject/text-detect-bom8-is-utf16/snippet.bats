prfn _static_bom8_is_utf16 {cells:$A.cells} (first: $A.NTH(cells, 0, 239), second: $A.NTH(cells, 1, 187), third: $A.NTH(cells, 2, 191)): DETECT(cells, SrcUtf16(LittleEndian()), 3) =
  DETECT_bom8(first, second, third)
