prfn _static_quote_is_no_quote {cells:$A.cells}{i,equals_at,quote_at:nat | i <= equals_at; equals_at + 1 <= quote_at}
  (skip: SKIP(cells, i, equals_at), equals: $A.NTH(cells, equals_at, 61), skip_quote: SKIP(cells, equals_at + 1, quote_at), cell: $A.NTH(cells, quote_at, 34)): DECLARED(cells, i, SrcUtf8()) =
  DECLARED_no_quote(skip, equals, skip_quote, BYTEAT_in(cell))
