fn _static_skip_other_cells {l:agz}{n:pos}{cells,other:$A.cells}{from:nat | from <= n} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, from: int from)
  : [to:nat | from <= to; to <= n] (SKIP(other, from, to) | int to) = text_skip_blank(length | data, n, from)
