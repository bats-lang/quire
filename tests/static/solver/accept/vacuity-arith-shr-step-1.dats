#include "share/atspre_staload.hats"
(* arith:src/lib.bats shr_digits_1, shr_cast, copied: see gen_vacuity.py.
   Control, the same text unchanged: the static content of shr_step_1, which has no copy (arith src/lib.bats) *)
dataprop SHR1(int, int, int, int) =
  | {a,b:nat | a < 32768; b < 32768}{s,t:nat | s < 2; t < 2}
    SHR1_mk(2*a + s, 2*b + t, a, b + 32768*s)

dataprop SHR(int, int, int, int, int) =
  | {h,l:nat} SHR_zero(0, h, l, h, l)
  | {n:nat}{h,l,h1,l1,h2,l2:nat}
    SHR_succ(n + 1, h, l, h2, l2) of (SHR1(h, l, h1, l1), SHR(n, h1, l1, h2, l2))

extern prfun shr_digits_1 {a,b,r,t:nat | a < 32768; b < 32768; r < 2; t < 2} ()
  : SHR(1, 2*a + r, 2*b + t, a, b + 32768*r)

primplement shr_digits_1 {a,b,r,t} () = SHR_succ(SHR1_mk{a,b}{r,t}(), SHR_zero())

prfn shr_cast {n,h,l,h2,l2,c,d,c2,d2:nat | h == c; l == d; h2 == c2; l2 == d2}
  (p: SHR(n, h, l, h2, l2)): SHR(n, c, d, c2, d2) = p

prfn shr_step_1_context {h,l:nat | h < 65536; l < 65536} ()
  : SHR(1, h, l, h/2, l/2 + 32768*(h - 2*(h/2))) =
  shr_cast(shr_digits_1{h/2, l/2, h - 2*(h/2), l - 2*(l/2)}())
