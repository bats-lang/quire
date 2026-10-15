(* bytes after the end chunk are not a record read to its end *)
prfn _static_trailing_is_complete {trailing_byte:int | 0 <= trailing_byte; trailing_byte < 256}{trailing_rest:bytes}
  (): SQC(ck_ok(IEND, bnil(), bcons(trailing_byte, trailing_rest)), sq_ok(pnil())) = SQC_trailing()
