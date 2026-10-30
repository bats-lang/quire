fn _static_newer_unmatched {res:recres}{sp:specs} (read: recread(res, sp)): int =
  case+ read of
  | ~RR_notquire() => 3
