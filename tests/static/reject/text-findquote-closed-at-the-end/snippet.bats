prfn _static_closed_at_end {cells:$A.cells}{quote:int}{from,to,n:nat | n <= to} (found: FINDQUOTE(cells, quote, from, to), length: $A.CLEN(cells, n))
  : (NOQUOTE(cells, quote, from, to), $A.NTH(cells, to, quote)) = findquote_closed(found, length)
