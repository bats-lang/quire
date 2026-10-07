(* crc -- CRC-32, defined in the types: the checksum of a byte string is
   one number, its proof is built as it is computed *)

#target wasm begin

#include "share/atspre_staload.hats"

#use arith as AR

staload "bytes.sats"

(* a xor b under 2 to the 16, with its proof (arith's) *)
#pub fun xor16 {a,b:nat | a < 65536; b < 65536} (a: int a, b: int b)
  : [c:nat | c < 65536] ($AR.XOR(a, b, c) | int c)

implement xor16 {a,b} (a, b) = let
  val (p | c) = $AR.xor_g1(a, b)
  prval pow16 = $AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ(
    $AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ(
    $AR.POW2_zero()))))))))))))))))
  prval () = $AR.xor_bound(pow16, p)
in (p | c) end

(* STEP1(hi, lo, hi', lo'): the 32-bit register (hi, lo) shifted right
   by one bit, and the polynomial 0xEDB88320 xored in when the bit
   shifted out was set *)
#pub dataprop STEP1(int, int, int, int) =
  | {h,t,q:nat | t < 2; 2*h + t < 65536; 2*q < 65536}
    STEP1_even(2*h + t, 2*q, h, q + 32768*t)
  | {h,t,q,hx,lx:nat | t < 2; 2*h + t < 65536; 2*q + 1 < 65536; hx < 65536; lx < 65536}
    STEP1_odd(2*h + t, 2*q + 1, hx, lx) of ($AR.XOR(h, 60856, hx), $AR.XOR(q + 32768*t, 33568, lx))

#pub prfun step1_functional {hi,lo,h1,l1,h2,l2:nat} (STEP1(hi, lo, h1, l1), STEP1(hi, lo, h2, l2))
  : [h1 == h2 && l1 == l2] void

prfn _step1_functional {hi,lo,h1,l1,h2,l2:nat} (p: STEP1(hi, lo, h1, l1), q: STEP1(hi, lo, h2, l2))
  : [h1 == h2 && l1 == l2] void =
  case+ p of
  | STEP1_even() => (case+ q of STEP1_even() => ())
  | STEP1_odd(px, py) =>
    (case+ q of
     | STEP1_odd(qx, qy) => let
         prval () = $AR.xor_functional(px, qx)
         prval () = $AR.xor_functional(py, qy)
       in () end)

primplement step1_functional {hi,lo,h1,l1,h2,l2} (p, q) = _step1_functional(p, q)


(* n halved: n = 2 * q + r *)
fn halve {n:nat} (n: int n): [q,r:nat | n == 2*q + r; r < 2] (int q, int r) = let val q = n / 2 in (q, n - 2 * q) end

(* the register shifted by one bit, with its proof *)
#pub fun step1 {hi,lo:nat | hi < 65536; lo < 65536} (hi: int hi, lo: int lo)
  : [h,l:nat | h < 65536; l < 65536] (STEP1(hi, lo, h, l) | int h, int l)

implement step1 {hi,lo} (hi, lo) = let
  val [h:int, t:int] (h, t) = halve(hi)
  val [q:int, r:int] (q, r) = halve(lo)
  val shifted = q + 32768 * t
in
  if r = 0 then (STEP1_even{h,t,q}() | h, shifted)
  else let
    val [hxs:int] (hp | hx) = xor16(h, 60856)
    val [lxs:int] (lp | lx) = xor16(shifted, 33568)
  in (STEP1_odd{h,t,q,hxs,lxs}(hp, lp) | hx, lx) end
end

(* STEPN(n, hi, lo, hi', lo'): n bits shifted in turn *)
#pub dataprop STEPN(int, int, int, int, int) =
  | {h,l:nat} STEPN_zero(0, h, l, h, l)
  | {n:nat}{h,l,h1,l1,h2,l2:nat} STEPN_succ(n+1, h, l, h2, l2) of (STEP1(h, l, h1, l1), STEPN(n, h1, l1, h2, l2))

#pub prfun stepn_functional {n:nat}{hi,lo,h1,l1,h2,l2:nat} (STEPN(n, hi, lo, h1, l1), STEPN(n, hi, lo, h2, l2))
  : [h1 == h2 && l1 == l2] void

prfun _stepn_functional {n:nat}{hi,lo,h1,l1,h2,l2:nat} .<n>. (p: STEPN(n, hi, lo, h1, l1), q: STEPN(n, hi, lo, h2, l2))
  : [h1 == h2 && l1 == l2] void =
  case+ p of
  | STEPN_zero() => (case+ q of STEPN_zero() => ())
  | STEPN_succ(ps, pr) =>
    (case+ q of
     | STEPN_succ(qs, qr) => let
         prval () = step1_functional(ps, qs)
       in _stepn_functional(pr, qr) end)

primplement stepn_functional {n}{hi,lo,h1,l1,h2,l2} (p, q) = _stepn_functional(p, q)

#pub fun stepn {n:nat}{hi,lo:nat | hi < 65536; lo < 65536} (n: int n, hi: int hi, lo: int lo)
  : [h,l:nat | h < 65536; l < 65536] (STEPN(n, hi, lo, h, l) | int h, int l)

implement stepn {n}{hi,lo} (n, hi, lo) = let
  fun go {n:nat}{hi,lo:nat | hi < 65536; lo < 65536} .<n>. (n: int n, hi: int hi, lo: int lo)
    : [h,l:nat | h < 65536; l < 65536] (STEPN(n, hi, lo, h, l) | int h, int l) =
    if n = 0 then (STEPN_zero() | hi, lo)
    else let
      val (sp | h1, l1) = step1(hi, lo)
      val (rp | h2, l2) = go(n - 1, h1, l1)
    in (STEPN_succ(sp, rp) | h2, l2) end
in go(n, hi, lo) end

(* BSTEP(hi, lo, b, hi', lo'): the register after the byte b *)
#pub dataprop BSTEP(int, int, int, int, int) =
  | {h,l,b,l0,h1,l1:nat} BSTEP_mk(h, l, b, h1, l1) of ($AR.XOR(l, b, l0), STEPN(8, h, l0, h1, l1))

#pub prfun bstep_functional {hi,lo,b,h1,l1,h2,l2:nat} (BSTEP(hi, lo, b, h1, l1), BSTEP(hi, lo, b, h2, l2))
  : [h1 == h2 && l1 == l2] void

prfn _bstep_functional {hi,lo,b,h1,l1,h2,l2:nat} (p: BSTEP(hi, lo, b, h1, l1), q: BSTEP(hi, lo, b, h2, l2))
  : [h1 == h2 && l1 == l2] void =
  case+ p of
  | BSTEP_mk(px, ps) =>
    (case+ q of
     | BSTEP_mk(qx, qs) => let
         prval () = $AR.xor_functional(px, qx)
       in stepn_functional(ps, qs) end)

primplement bstep_functional {hi,lo,b,h1,l1,h2,l2} (p, q) = _bstep_functional(p, q)

#pub fun bstep {hi,lo,b:nat | hi < 65536; lo < 65536; b < 256} (hi: int hi, lo: int lo, b: int b)
  : [h,l:nat | h < 65536; l < 65536] (BSTEP(hi, lo, b, h, l) | int h, int l)

implement bstep {hi,lo,b} (hi, lo, b) = let
  val (xp | l0) = xor16(lo, b)
  val (sp | h1, l1) = stepn(8, hi, l0)
in (BSTEP_mk(xp, sp) | h1, l1) end

(* CRCFROM(hi, lo, bs, hi', lo'): the register after the bytes bs *)
#pub dataprop CRCFROM(int, int, bytes, int, int) =
  | {h,l:nat} CRCFROM_nil(h, l, bnil(), h, l)
  | {h,l,b,h1,l1,h2,l2:nat}{bs:bytes}
    CRCFROM_cons(h, l, bcons(b, bs), h2, l2) of (BSTEP(h, l, b, h1, l1), CRCFROM(h1, l1, bs, h2, l2))

#pub prfun crcfrom_functional {hi,lo:nat}{bs:bytes}{n:nat}{h1,l1,h2,l2:nat}
  (LEN(bs, n), CRCFROM(hi, lo, bs, h1, l1), CRCFROM(hi, lo, bs, h2, l2)): [h1 == h2 && l1 == l2] void

prfun _crcfrom_functional {hi,lo:nat}{bs:bytes}{n:nat}{h1,l1,h2,l2:nat} .<n>. (len: LEN(bs, n), p: CRCFROM(hi, lo, bs, h1, l1), q: CRCFROM(hi, lo, bs, h2, l2))
  : [h1 == h2 && l1 == l2] void =
  case+ p of
  | CRCFROM_nil() => (case+ q of CRCFROM_nil() => ())
  | CRCFROM_cons(ps, pr) =>
    (case+ q of
     | CRCFROM_cons(qs, qr) => let
         prval () = bstep_functional(ps, qs)
         prval LEN_cons(len1) = len
       in _crcfrom_functional(len1, pr, qr) end)

primplement crcfrom_functional {hi,lo}{bs}{n}{h1,l1,h2,l2} (len, p, q) = _crcfrom_functional(len, p, q)

#pub fun crcfrom {hi,lo:nat | hi < 65536; lo < 65536}{bs:bytes}{n:nat} (hi: int hi, lo: int lo, bl: !blist(bs, n))
  : [h,l:nat | h < 65536; l < 65536] (CRCFROM(hi, lo, bs, h, l) | int h, int l)

implement crcfrom {hi,lo}{bs}{n} (hi, lo, bl) = let
  fun go {hi,lo:nat | hi < 65536; lo < 65536}{bs:bytes}{n:nat} .<n>.
    (hi: int hi, lo: int lo, bl: !blist(bs, n))
    : [h,l:nat | h < 65536; l < 65536] (CRCFROM(hi, lo, bs, h, l) | int h, int l) =
    case+ bl of
    | blist_nil() => (CRCFROM_nil() | hi, lo)
    | blist_cons(b, rest) => let
        val (sp | h1, l1) = bstep(hi, lo, b)
        val (rp | h2, l2) = go(h1, l1, rest)
      in (CRCFROM_cons(sp, rp) | h2, l2) end
in go(hi, lo, bl) end

end
