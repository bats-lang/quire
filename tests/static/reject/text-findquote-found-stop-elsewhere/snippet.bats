prfn _static_stop_elsewhere {cells:$A.cells}{from,to:nat} (noquote: NOQUOTE(cells, 34, from, to), stop: QUOTESTOP(cells, 34, to + 1)): FINDQUOTE(cells, 34, from, to) = FINDQUOTE_found(noquote, stop)
