#include "share/atspre_staload.hats"
(* src/crc.bats step1_exists, copied: see gen_vacuity.py.
   Control, the same text unchanged: an even low half, in step1_exists (src/crc.bats:347) *)
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

dataprop POW2(int, int) =
  | POW2_zero(0, 1)
  | {k,p:nat} POW2_succ(k+1, 2*p) of POW2(k, p)

extern prfun xor_bound {k,p,a,b,c:nat | a < p; b < p} (POW2(k, p), XOR(a, b, c)): [c < p] void

prfun _xor_bound {k,p,a,b,c:nat | a < p; b < p} .<k>. (w: POW2(k, p), x: XOR(a, b, c)): [c < p] void =
  case+ x of
  | XOR_nil() => ()
  | XOR_00(x1) => (case+ w of POW2_succ(w1) => _xor_bound(w1, x1))
  | XOR_01(x1) => (case+ w of POW2_succ(w1) => _xor_bound(w1, x1))
  | XOR_10(x1) => (case+ w of POW2_succ(w1) => _xor_bound(w1, x1))
  | XOR_11(x1) => (case+ w of POW2_succ(w1) => _xor_bound(w1, x1))

primplement xor_bound {k,p,a,b,c} (w, x) = _xor_bound(w, x)

prfn pow2_16(): POW2(16, 65536) =
  POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(
    POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(
    POW2_zero()))))))))))))))))

prfn step1_exists {high,low:nat | high < 65536; low < 65536} ()
  : [next_high,next_low:nat | next_high < 65536; next_low < 65536] STEP1(high, low, next_high, next_low) =
  sif low == 2*(low/2) then STEP1_even{high/2, high - 2*(high/2), low/2}()
  else let
    prval [high_xored:int] high_proof = xor_exists{high/2, 60856}()
    prval () = xor_bound(pow2_16(), high_proof)
    prval [low_xored:int] low_proof = xor_exists{low/2 + 32768*(high - 2*(high/2)), 33568}()
    prval () = xor_bound(pow2_16(), low_proof)
  in STEP1_odd{high/2, high - 2*(high/2), low/2, high_xored, low_xored}(high_proof, low_proof) end
