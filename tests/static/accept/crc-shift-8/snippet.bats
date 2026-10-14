(* 8 bits shifted out of a register whose low byte is zero: the high half's low byte comes in at the top of the low half *)
prfn _static_shift_8 {h,r,l:nat | r < 256; 256*h + r < 65536; 256*l < 65536} ()
  : STEPN(8, 256*h + r, 256*l, h, l + 256*r) =
  shift8{h, r, l}()
