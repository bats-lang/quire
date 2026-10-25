fn _static_scan_other_cells {l:agz}{n:pos}{cells,other:$A.cells}{from:nat | from <= n} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, from: int from)
  : [verdict:int] (UTF8SCAN(other, from, verdict) | utf8_verdict(verdict)) = text_utf8_scan(length | data, n, from)
