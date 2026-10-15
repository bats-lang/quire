(* A cell of the table read for the entry's low half taken for one of its high half *)
prfn _static_read_another_cell {ct:$A.cells}{index:nat}{read,cell:int}
  (low_read: $A.NTH(ct, 4*index, read), high_cell: $A.NTH(ct, 4*index + 2, cell)): [read == cell] void =
  $A.nth_functional(low_read, high_cell)
