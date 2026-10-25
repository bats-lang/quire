fn _static_label_other_cells {l:agz}{n:pos}{cells,other:$A.cells}{from,count:nat | from + count <= n} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, from: int from, count: int count)
  : [source:tsrc] (LABELSRC(other, from, count, source) | label_source(source)) = text_label_source(length | data, n, from, count)
