#include "share/atspre_staload.hats"
(* arith:src/lib.bats xor_half, copied: see gen_vacuity.py.
   Control, the same text unchanged: the XOR_10 case of xor_half (arith src/lib.bats:220) *)
dataprop XOR(int, int, int) =
  | XOR_nil(0, 0, 0)
  | {a,b,c:nat | a + b > 0} XOR_00(2*a, 2*b, 2*c) of XOR(a, b, c)
  | {a,b,c:nat} XOR_01(2*a, 2*b + 1, 2*c + 1) of XOR(a, b, c)
  | {a,b,c:nat} XOR_10(2*a + 1, 2*b, 2*c + 1) of XOR(a, b, c)
  | {a,b,c:nat} XOR_11(2*a + 1, 2*b + 1, 2*c) of XOR(a, b, c)

extern prfun xor_half {a,b,c:nat} (XOR(a, b, c)): XOR(a/2, b/2, c/2)

primplement xor_half {a,b,c} (p) =
  case+ p of
  | XOR_nil() => XOR_nil()
  | XOR_00(p1) => p1
  | XOR_01(p1) => p1
  | XOR_10(p1) => p1
  | XOR_11(p1) => p1
