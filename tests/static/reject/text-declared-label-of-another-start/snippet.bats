prfn _static_label_of_another_start {cells:$A.cells}{i,equals_at,quote_at,label_end:nat | i <= equals_at; equals_at + 1 <= quote_at; quote_at + 1 <= label_end}{source:int}
  (skip: SKIP(cells, i, equals_at), equals: $A.NTH(cells, equals_at, 61), skip_quote: SKIP(cells, equals_at + 1, quote_at), quote: $A.NTH(cells, quote_at, 34),
   noquote: NOQUOTE(cells, 34, quote_at + 1, label_end), closing: $A.NTH(cells, label_end, 34), label: LABELSRC(cells, quote_at, label_end - quote_at, source)): DECLARED(cells, i, source) =
  DECLARED_label(skip, equals, skip_quote, quote, noquote, closing, label)
