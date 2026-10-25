#include "share/atspre_staload.hats"
(* src/crc.bats xor_exists, copied: see gen_vacuity.py.
   Control, the same text unchanged: left even and right odd, in xor_exists (src/crc.bats:334) *)
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
    else sif a == 2*(a/2) then xor_double(go{a/2}())
    else XOR_01(go{a/2}())
in go{a}() end

prfun xor_exists {left,right:nat} .<left+right>. (): [joined:nat] XOR(left, right, joined) =
  sif left == 0 then
    (sif right == 0 then XOR_nil() else xor_zero_left{right}())
  else
    (sif left == 2*(left/2) then
       (sif right == 2*(right/2) then xor_double(xor_exists{left/2,right/2}())
        else XOR_01(xor_exists{left/2,right/2}()))
     else
       (sif right == 2*(right/2) then XOR_10(xor_exists{left/2,right/2}())
        else XOR_11(xor_exists{left/2,right/2}())))
