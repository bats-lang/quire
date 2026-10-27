prfn _static_equals_is_no_equals {cells:$A.cells}{i,equals_at:nat | i <= equals_at} (skip: SKIP(cells, i, equals_at), cell: $A.NTH(cells, equals_at, 61)): DECLARED(cells, i, SrcUtf8()) =
  DECLARED_no_equals(skip, BYTEAT_in(cell))
