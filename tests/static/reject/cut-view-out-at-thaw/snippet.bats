(* The frozen cells are thawed while the plain view of them is still out *)
fn _static_view_out {l:agz}{n:nat}{cs:$A.cells}
  (frozen: $A.cfrozen(l, n, 1, cs), view: !$A.borrow(byte, l, n)): $A.barr(l, n, cs) = $A.barr_thaw(frozen)
