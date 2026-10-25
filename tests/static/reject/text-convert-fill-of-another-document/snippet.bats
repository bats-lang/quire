fn _static_fill_other_document {l:agz}{n:pos}{cells,other:$A.cells}{total:bytes}{m:nat}{lo:agz}{oc:$A.cells}
  (length: $A.CLEN(cells, n), plan: TEXTOF(other, 1, TOUT_bytes(total)), total_len: LEN(total, m), out_len: $A.CLEN(oc, m + 1)
   | data: !$A.cborrow(l, n, cells), n: int n, out: $A.barr(lo, m + 1, oc), m: int m): [oc2:$A.cells] (HOLDS(oc2, 0, total, m), $A.CLEN(oc2, m + 1) | $A.barr(lo, m + 1, oc2)) =
  text_convert_fill(length, plan, total_len, out_len | data, n, out, m)
