prfn _static_utf16_conv_table {cells:$A.cells}{mark,n:nat}{total:bytes}
  (plan: TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), detect: DETECT(cells, SrcTable(Cp1252()), mark), length: $A.CLEN(cells, n)): CONV(cells, SrcTable(Cp1252()), mark, n, total) =
  textof_utf16_conv{cells}{LittleEndian()}{mark}{n}{total}(plan, detect, length)
