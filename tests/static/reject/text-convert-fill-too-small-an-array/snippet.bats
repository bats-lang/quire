fn _static_fill_too_small {l:agz}{n:pos}{cells:$A.cells}{total:bytes}{m:nat}{lo:agz}{oc:$A.cells}
  (length: $A.CLEN(cells, n), plan: TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), total_len: LEN(total, m), out_len: $A.CLEN(oc, m)
   | data: !$A.cborrow(l, n, cells), n: int n, out: $A.barr(lo, m, oc), m: int m): [oc2:$A.cells] (HOLDS(oc2, 0, total, m), $A.CLEN(oc2, m) | $A.barr(lo, m, oc2)) =
  text_convert_fill(length, plan, total_len, out_len | data, n, out, m)
