prfn _static_crc_not_checked {tag,data,r,crcb,rest:bytes}{hi,lo,h,l:nat | hi != h}
  (taken: TAKE(4, r, crcb, rest), stored: CRCB(crcb, hi, lo), computed: CRCP(tag, data, h, l))
  : CKD(tag, data, r, ck_ok(tag, data, rest)) = CKD_ok(taken, stored, computed)
