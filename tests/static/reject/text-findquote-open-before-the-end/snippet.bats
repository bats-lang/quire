prfn _static_open_before_end {cells:$A.cells}{quote:int}{from,to,n:nat | to < n} (found: FINDQUOTE(cells, quote, from, to), length: $A.CLEN(cells, n))
  : (NOQUOTE(cells, quote, from, to), $A.CLEN(cells, to)) = findquote_open(found, length)
