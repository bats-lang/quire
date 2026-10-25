fn _static_detect_other_cells {l:agz}{n:pos}{cells,other:$A.cells} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n)
  : [source,mark:int] (DETECT(other, source, mark) | label_source(source), int mark) = text_detect(length | data, n)
