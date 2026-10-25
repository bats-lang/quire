#include "share/atspre_staload.hats"
(* arith:src/lib.bats shr_digits_4, copied: see gen_vacuity.py.
   Change: the result of shr_digits_4 one more: its first and second steps are built with every division of the body (arith src/lib.bats) *)
dataprop SHR1(int, int, int, int) =
  | {a,b:nat | a < 32768; b < 32768}{s,t:nat | s < 2; t < 2}
    SHR1_mk(2*a + s, 2*b + t, a, b + 32768*s)

dataprop SHR(int, int, int, int, int) =
  | {h,l:nat} SHR_zero(0, h, l, h, l)
  | {n:nat}{h,l,h1,l1,h2,l2:nat}
    SHR_succ(n + 1, h, l, h2, l2) of (SHR1(h, l, h1, l1), SHR(n, h1, l1, h2, l2))

extern prfun shr_digits_4 {a,b,r,t:nat | a < 4096; b < 4096; r < 16; t < 16} ()
  : SHR(4, 16*a + r, 16*b + t, a, b + 4096*r + 1)

extern prfun shr_digits_2 {a,b,r,t:nat | a < 16384; b < 16384; r < 4; t < 4} ()
  : SHR(2, 4*a + r, 4*b + t, a, b + 16384*r)

extern prfun shr_digits_1 {a,b,r,t:nat | a < 32768; b < 32768; r < 2; t < 2} ()
  : SHR(1, 2*a + r, 2*b + t, a, b + 32768*r)

primplement shr_digits_1 {a,b,r,t} () = SHR_succ(SHR1_mk{a,b}{r,t}(), SHR_zero())

prfn shr_cast {n,h,l,h2,l2,c,d,c2,d2:nat | h == c; l == d; h2 == c2; l2 == d2}
  (p: SHR(n, h, l, h2, l2)): SHR(n, c, d, c2, d2) = p

extern prfun shr_add {a,b,h,l,h1,l1,h2,l2:nat} (SHR(a, h, l, h1, l1), SHR(b, h1, l1, h2, l2)): SHR(a + b, h, l, h2, l2)

prfun _shr_add {a,b,h,l,h1,l1,h2,l2:nat} .<a>. (p: SHR(a, h, l, h1, l1), q: SHR(b, h1, l1, h2, l2)): SHR(a + b, h, l, h2, l2) =
  case+ p of
  | SHR_zero() => q
  | SHR_succ(once, rest) => SHR_succ(once, _shr_add(rest, q))

primplement shr_add {a,b,h,l,h1,l1,h2,l2} (p, q) = _shr_add(p, q)

primplement shr_digits_2 {a,b,r,t} () = let
  prval first = shr_digits_1{2*a + r/2, 2*b + t/2, r - 2*(r/2), t - 2*(t/2)}()
  prval second = shr_digits_1{a, b + 16384*(r - 2*(r/2)), r/2, t/2}()
in shr_cast(shr_add(first, second)) end

primplement shr_digits_4 {a,b,r,t} () = let
  prval first = shr_digits_2{4*a + r/4, 4*b + t/4, r - 4*(r/4), t - 4*(t/4)}()
  prval second = shr_digits_2{a, b + 4096*(r - 4*(r/4)), r/4, t/4}()
in shr_cast(shr_add(first, second)) end
