(* A snapshot taken before a restore and then forgotten: the Undo that
   would put it back is never offered, and what the restore replaced is
   lost (#362) *)
fn _static_snapshot_forgotten (made: snapshot_result): void =
  case+ made of
  | ~SnapshotMade(_) => ()
  | ~SnapshotNotMade(_) => ()
