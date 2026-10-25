fn _static_size_other_cells {l:agz}{n:pos}{cells,other:$A.cells} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n): text_sized(other) = text_convert_size(length | data, n)
