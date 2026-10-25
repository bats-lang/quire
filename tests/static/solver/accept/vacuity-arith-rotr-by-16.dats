#include "share/atspre_staload.hats"
(* arith:src/lib.bats rotr_by_16, copied: see gen_vacuity.py.
   Control, the same text unchanged: the result of rotr_by_16 one more: its first and second steps are built with every division of the body (arith src/lib.bats) *)
dataprop ROTR1(int, int, int, int) =
  | {a,b:nat | a < 32768; b < 32768}{s,t:nat | s < 2; t < 2}
    ROTR1_mk(2*a + s, 2*b + t, a + 32768*t, b + 32768*s)

dataprop ROTR(int, int, int, int, int) =
  | {h,l:nat} ROTR_zero(0, h, l, h, l)
  | {n:nat}{h,l,h1,l1,h2,l2:nat}
    ROTR_succ(n + 1, h, l, h2, l2) of (ROTR1(h, l, h1, l1), ROTR(n, h1, l1, h2, l2))

extern prfun rotr_by_16 {h,l:nat | h < 65536; l < 65536} ()
  : ROTR(16, h, l, l, h)

extern prfun rotr_digits_8 {a,b,r,t:nat | a < 256; b < 256; r < 256; t < 256} ()
  : ROTR(8, 256*a + r, 256*b + t, a + 256*t, b + 256*r)

extern prfun rotr_digits_4 {a,b,r,t:nat | a < 4096; b < 4096; r < 16; t < 16} ()
  : ROTR(4, 16*a + r, 16*b + t, a + 4096*t, b + 4096*r)

extern prfun rotr_digits_2 {a,b,r,t:nat | a < 16384; b < 16384; r < 4; t < 4} ()
  : ROTR(2, 4*a + r, 4*b + t, a + 16384*t, b + 16384*r)

extern prfun rotr_digits_1 {a,b,r,t:nat | a < 32768; b < 32768; r < 2; t < 2} ()
  : ROTR(1, 2*a + r, 2*b + t, a + 32768*t, b + 32768*r)

primplement rotr_digits_1 {a,b,r,t} () = ROTR_succ(ROTR1_mk{a,b}{r,t}(), ROTR_zero())

prfn rotr_cast {n,h,l,h2,l2,c,d,c2,d2:nat | h == c; l == d; h2 == c2; l2 == d2}
  (p: ROTR(n, h, l, h2, l2)): ROTR(n, c, d, c2, d2) = p

extern prfun rotr_add {a,b,h,l,h1,l1,h2,l2:nat} (ROTR(a, h, l, h1, l1), ROTR(b, h1, l1, h2, l2)): ROTR(a + b, h, l, h2, l2)

prfun _rotr_add {a,b,h,l,h1,l1,h2,l2:nat} .<a>. (p: ROTR(a, h, l, h1, l1), q: ROTR(b, h1, l1, h2, l2)): ROTR(a + b, h, l, h2, l2) =
  case+ p of
  | ROTR_zero() => q
  | ROTR_succ(once, rest) => ROTR_succ(once, _rotr_add(rest, q))

primplement rotr_add {a,b,h,l,h1,l1,h2,l2} (p, q) = _rotr_add(p, q)

primplement rotr_digits_2 {a,b,r,t} () = let
  prval first = rotr_digits_1{2*a + r/2, 2*b + t/2, r - 2*(r/2), t - 2*(t/2)}()
  prval second = rotr_digits_1{a + 16384*(t - 2*(t/2)), b + 16384*(r - 2*(r/2)), r/2, t/2}()
in rotr_cast(rotr_add(first, second)) end

primplement rotr_digits_4 {a,b,r,t} () = let
  prval first = rotr_digits_2{4*a + r/4, 4*b + t/4, r - 4*(r/4), t - 4*(t/4)}()
  prval second = rotr_digits_2{a + 4096*(t - 4*(t/4)), b + 4096*(r - 4*(r/4)), r/4, t/4}()
in rotr_cast(rotr_add(first, second)) end

primplement rotr_digits_8 {a,b,r,t} () = let
  prval first = rotr_digits_4{16*a + r/16, 16*b + t/16, r - 16*(r/16), t - 16*(t/16)}()
  prval second = rotr_digits_4{a + 256*(t - 16*(t/16)), b + 256*(r - 16*(r/16)), r/16, t/16}()
in rotr_cast(rotr_add(first, second)) end

primplement rotr_by_16 {h,l} () = let
  prval first = rotr_digits_8{h/256, l/256, h - 256*(h/256), l - 256*(l/256)}()
  prval second = rotr_digits_8{l - 256*(l/256), h - 256*(h/256), h/256, l/256}()
in rotr_cast(rotr_add(first, second)) end
