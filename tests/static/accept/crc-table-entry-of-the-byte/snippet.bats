(* A table entry that is the register the byte's step makes *)
prfn _static_entry_of_the_byte {ct:$A.cells}{count:nat}{high,low:int}
  (tabled: TABLED(ct, count), entry: ENTRY(ct, count, high, low), step: BSTEP(0, 0, count, high, low)): TABLED(ct, count + 1) =
  TABLED_cons(tabled, entry, step)
