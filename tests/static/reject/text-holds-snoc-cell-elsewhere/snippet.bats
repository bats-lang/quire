prfn _static_snoc_cell_elsewhere {cells:$A.cells}{i,count:nat}{value:int}{octets,joined:bytes}
  (holds: HOLDS(cells, i, octets, count), cell: $A.NTH(cells, i + count + 1, value), joined: APPEND(octets, bcons(value, bnil()), joined)): HOLDS(cells, i, joined, count + 1) = holds_snoc(holds, cell, joined)
