prfn _static_letter_quote {cells:$A.cells}{i,equals_at,quote_at,label_end:nat | i <= equals_at; equals_at + 1 <= quote_at; quote_at + 1 <= label_end}
  (skip: SKIP(cells, i, equals_at), equals: $A.NTH(cells, equals_at, 61), skip_quote: SKIP(cells, equals_at + 1, quote_at), quote: $A.NTH(cells, quote_at, 65),
   noquote: NOQUOTE(cells, 65, quote_at + 1, label_end), ended: $A.CLEN(cells, label_end)): DECLARED(cells, i, 0) =
  DECLARED_unclosed(skip, equals, skip_quote, quote, noquote, ended)
