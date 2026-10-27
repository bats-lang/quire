prfn _static_snoc_quote {cells:$A.cells}{from,to:nat | from <= to} (noquote: NOQUOTE(cells, 39, from, to), cell: $A.NTH(cells, to, 39)): NOQUOTE(cells, 39, from, to + 1) =
  noquote_snoc(noquote, cell)
