prfn _static_push_another_place {cells,cells_after:$A.cells}{p:nat}{value:int}{octets,joined:bytes}
  (holds: HOLDS(cells, 0, octets, p), cells_set: $A.SETC(cells, p + 1, value, cells_after), joined: APPEND(octets, bcons(value, bnil()), joined)): HOLDS(cells_after, 0, joined, p + 1) =
  holds_push(holds, cells_set, joined)
