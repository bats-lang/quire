(* 8 bits shifted out, but the high half's low byte placed one bit too low in the low half *)
prfn _static_shift_8_wrong_low {h,r,l:nat | r < 256; 256*h + r < 65536; 256*l < 65536} ()
  : STEPN(8, 256*h + r, 256*l, h, l + 128*r) =
  shift8{h, r, l}()
