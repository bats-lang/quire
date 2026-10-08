fn _static_newer_unmatched {res:recres}{sp:specs} (read: recread(res, sp)): int =
  case+ read of
  | ~RR_ok(_, _, vals, extras) => let val () = gvalsv_free(vals) val () = extrasv_free(extras) in 1 end
  | ~RR_loss(_, _, vals, extras, lost) => let val () = gvalsv_free(vals) val () = extrasv_free(extras) val () = lostv_free(lost) in 2 end
  | ~RR_notquire() => 3
  | ~RR_damaged() => 5
