prfn _static_scan_two_places {cells:$A.cells}{from,other:nat}{first,second:scanned} (one: UTF8SCAN(cells, from, first), two: UTF8SCAN(cells, other, second)): EQSCANNED(first, second) =
  utf8scan_functional(one, two)
