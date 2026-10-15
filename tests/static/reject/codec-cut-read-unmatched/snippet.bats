(* a chunk list read is whole or cut: a match that leaves the cut out is refused *)
fn _static_cut_unmatched {read_result:seqres} (read: seqread(read_result)): int =
  case+ read of
  | ~SR_ok(_ | chunk_list) => let val () = chunklist_free(chunk_list) in 1 end
