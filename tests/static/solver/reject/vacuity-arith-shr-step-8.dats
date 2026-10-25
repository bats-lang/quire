#include "share/atspre_staload.hats"
(* arith:src/lib.bats shr_digits_8, shr_cast, copied: see gen_vacuity.py.
   Change: the second half of the result one more: the static content of shr_step_8, which has no copy (arith src/lib.bats) *)
dataprop SHR1(int, int, int, int) =
  | {a,b:nat | a < 32768; b < 32768}{s,t:nat | s < 2; t < 2}
    SHR1_mk(2*a + s, 2*b + t, a, b + 32768*s)

dataprop SHR(int, int, int, int, int) =
  | {h,l:nat} SHR_zero(0, h, l, h, l)
  | {n:nat}{h,l,h1,l1,h2,l2:nat}
    SHR_succ(n + 1, h, l, h2, l2) of (SHR1(h, l, h1, l1), SHR(n, h1, l1, h2, l2))

extern prfun shr_digits_8 {a,b,r,t:nat | a < 256; b < 256; r < 256; t < 256} ()
  : SHR(8, 256*a + r, 256*b + t, a, b + 256*r)

extern prfun shr_digits_4 {a,b,r,t:nat | a < 4096; b < 4096; r < 16; t < 16} ()
  : SHR(4, 16*a + r, 16*b + t, a, b + 4096*r)

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

primplement shr_digits_8 {a,b,r,t} () = let
  prval first = shr_digits_4{16*a + r/16, 16*b + t/16, r - 16*(r/16), t - 16*(t/16)}()
  prval second = shr_digits_4{a, b + 256*(r - 16*(r/16)), r/16, t/16}()
in shr_cast(shr_add(first, second)) end

prfn shr_step_8_context {h,l:nat | h < 65536; l < 65536} ()
  : SHR(8, h, l, h/256, l/256 + 256*(h - 256*(h/256)) + 1) =
  shr_cast(shr_digits_8{h/256, l/256, h - 256*(h/256), l - 256*(l/256)}())
