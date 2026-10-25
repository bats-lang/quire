prfn _static_set_inside_the_held {cells,cells_after:$A.cells}{i,count,at:nat | at < i + count}{value:int}{octets:bytes}
  (cells_set: $A.SETC(cells, at, value, cells_after), holds: HOLDS(cells, i, octets, count)): HOLDS(cells_after, i, octets, count) = holds_after_set_later(cells_set, holds)
