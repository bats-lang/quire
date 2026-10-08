fn _static_view_unmatched (view: library_view): int =
  case+ view of
  | ViewBooks() => 1
  | ViewEmpty() => 2
