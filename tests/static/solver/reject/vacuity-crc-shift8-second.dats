#include "share/atspre_staload.hats"
(* src/crc.bats shift8, copied: see gen_vacuity.py.
   Change: the second half of shift8 (src/crc.bats:391) *)
dataprop XOR(int, int, int) =
  | XOR_nil(0, 0, 0)
  | {a,b,c:nat | a + b > 0} XOR_00(2*a, 2*b, 2*c) of XOR(a, b, c)
  | {a,b,c:nat} XOR_01(2*a, 2*b + 1, 2*c + 1) of XOR(a, b, c)
  | {a,b,c:nat} XOR_10(2*a + 1, 2*b, 2*c + 1) of XOR(a, b, c)
  | {a,b,c:nat} XOR_11(2*a + 1, 2*b + 1, 2*c) of XOR(a, b, c)

dataprop STEP1(int, int, int, int) =
  | {high_half,carry_bit,low_half:nat | carry_bit < 2; 2*high_half + carry_bit < 65536; 2*low_half < 65536}
    STEP1_even(2*high_half + carry_bit, 2*low_half, high_half, low_half + 32768*carry_bit)
  | {high_half,carry_bit,low_half,high_xored,low_xored:nat | carry_bit < 2; 2*high_half + carry_bit < 65536; 2*low_half + 1 < 65536; high_xored < 65536; low_xored < 65536}
    STEP1_odd(2*high_half + carry_bit, 2*low_half + 1, high_xored, low_xored)
      of (XOR(high_half, 60856, high_xored), XOR(low_half + 32768*carry_bit, 33568, low_xored))

dataprop STEPN(int, int, int, int, int) =
  | {high,low:nat} STEPN_zero(0, high, low, high, low)
  | {count:nat}{high,low,mid_high,mid_low,end_high,end_low:nat}
    STEPN_succ(count+1, high, low, end_high, end_low) of (STEP1(high, low, mid_high, mid_low), STEPN(count, mid_high, mid_low, end_high, end_low))

prfun stepn_append {first,second:nat}{high,low,mid_high,mid_low,end_high,end_low:nat} .<first>.
  (first_steps: STEPN(first, high, low, mid_high, mid_low), second_steps: STEPN(second, mid_high, mid_low, end_high, end_low))
  : STEPN(first + second, high, low, end_high, end_low) =
  case+ first_steps of
  | STEPN_zero() => second_steps
  | STEPN_succ(step, rest) => STEPN_succ(step, stepn_append(rest, second_steps))

prfn shift2 {h,r,l:nat | r < 4; 4*h + r < 65536; 4*l < 65536} ()
  : STEPN(2, 4*h + r, 4*l, h, l + 16384*r) =
  STEPN_succ(STEP1_even{2*h + r/2, r - 2*(r/2), 2*l}(),
    STEPN_succ(STEP1_even{h, r/2, l + 16384*(r - 2*(r/2))}(), STEPN_zero()))

prfn shift4 {h,r,l:nat | r < 16; 16*h + r < 65536; 16*l < 65536} ()
  : STEPN(4, 16*h + r, 16*l, h, l + 4096*r) =
  stepn_append(shift2{4*h + r/4, r - 4*(r/4), 4*l}(), shift2{h, r/4, l + 4096*(r - 4*(r/4))}())

prfn shift8 {h,r,l:nat | r < 256; 256*h + r < 65536; 256*l < 65536} ()
  : STEPN(8, 256*h + r, 256*l, h, l + 256*r) =
  stepn_append(shift4{16*h + r/16, r - 16*(r/16), 16*l}(), (let prval _ : [r/16 == r/16 + 1] void = () in shift4{h, r/16, l + 256*(r - 16*(r/16))}() end))
