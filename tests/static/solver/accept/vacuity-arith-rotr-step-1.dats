#include "share/atspre_staload.hats"
(* arith:src/lib.bats rotr_digits_1, rotr_cast, copied: see gen_vacuity.py.
   Control, the same text unchanged: the static content of rotr_step_1, which has no copy (arith src/lib.bats) *)
dataprop ROTR1(int, int, int, int) =
  | {a,b:nat | a < 32768; b < 32768}{s,t:nat | s < 2; t < 2}
    ROTR1_mk(2*a + s, 2*b + t, a + 32768*t, b + 32768*s)

dataprop ROTR(int, int, int, int, int) =
  | {h,l:nat} ROTR_zero(0, h, l, h, l)
  | {n:nat}{h,l,h1,l1,h2,l2:nat}
    ROTR_succ(n + 1, h, l, h2, l2) of (ROTR1(h, l, h1, l1), ROTR(n, h1, l1, h2, l2))

extern prfun rotr_digits_1 {a,b,r,t:nat | a < 32768; b < 32768; r < 2; t < 2} ()
  : ROTR(1, 2*a + r, 2*b + t, a + 32768*t, b + 32768*r)

primplement rotr_digits_1 {a,b,r,t} () = ROTR_succ(ROTR1_mk{a,b}{r,t}(), ROTR_zero())

prfn rotr_cast {n,h,l,h2,l2,c,d,c2,d2:nat | h == c; l == d; h2 == c2; l2 == d2}
  (p: ROTR(n, h, l, h2, l2)): ROTR(n, c, d, c2, d2) = p

prfn rotr_step_1_context {h,l:nat | h < 65536; l < 65536} ()
  : ROTR(1, h, l, h/2 + 32768*(l - 2*(l/2)), l/2 + 32768*(h - 2*(h/2))) =
  rotr_cast(rotr_digits_1{h/2, l/2, h - 2*(h/2), l - 2*(l/2)}())
