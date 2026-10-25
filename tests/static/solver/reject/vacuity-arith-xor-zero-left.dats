#include "share/atspre_staload.hats"
(* arith:src/lib.bats xor_zero_left, copied: see gen_vacuity.py.
   Change: the even case of go, in xor_zero_left (arith src/lib.bats) *)
dataprop XOR(int, int, int) =
  | XOR_nil(0, 0, 0)
  | {a,b,c:nat | a + b > 0} XOR_00(2*a, 2*b, 2*c) of XOR(a, b, c)
  | {a,b,c:nat} XOR_01(2*a, 2*b + 1, 2*c + 1) of XOR(a, b, c)
  | {a,b,c:nat} XOR_10(2*a + 1, 2*b, 2*c + 1) of XOR(a, b, c)
  | {a,b,c:nat} XOR_11(2*a + 1, 2*b + 1, 2*c) of XOR(a, b, c)

extern prfun xor_zero_left {a:nat} (): XOR(0, a, a)

extern prfun xor_double {a,b,c:nat} (XOR(a, b, c)): XOR(2*a, 2*b, 2*c)

primplement xor_double {a,b,c} (p) =
  case+ p of
  | XOR_nil() => XOR_nil()
  | XOR_00(p1) => XOR_00(xor_double(p1))
  | XOR_01(p1) => XOR_00(p)
  | XOR_10(p1) => XOR_00(p)
  | XOR_11(p1) => XOR_00(p)

primplement xor_zero_left {a} () = let
  prfun go {a:nat} .<a>. (): XOR(0, a, a) =
    sif a == 0 then XOR_nil()
    else sif a == 2*(a/2) then (let prval _ : [a/2 == a/2 + 1] void = () in xor_double(go{a/2}()) end)
    else XOR_01(go{a/2}())
in go{a}() end
