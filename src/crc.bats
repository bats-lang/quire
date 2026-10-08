(* crc -- CRC-32, defined in the types: the checksum of a byte string is
   one number, its proof is built as it is computed *)

#target wasm begin

#include "share/atspre_staload.hats"

#use arith as AR

staload "bytes.sats"

(* left xor right under 2 to the 16, with its proof (arith's) *)
#pub fun xor16 {left,right:nat | left < 65536; right < 65536} (left: int left, right: int right)
  : [xored:nat | xored < 65536] ($AR.XOR(left, right, xored) | int xored)

implement xor16 {left,right} (left, right) = let
  val (xor_proof | xored) = $AR.xor_g1(left, right)
  prval pow16 = $AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ(
    $AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ(
    $AR.POW2_zero()))))))))))))))))
  prval () = $AR.xor_bound(pow16, xor_proof)
in (xor_proof | xored) end

(* STEP1(high, low, next_high, next_low): the 32-bit register (high, low)
   shifted right by one bit, and the polynomial 0xEDB88320 xored in when
   the bit shifted out was set *)
#pub dataprop STEP1(int, int, int, int) =
  | {high_half,carry_bit,low_half:nat | carry_bit < 2; 2*high_half + carry_bit < 65536; 2*low_half < 65536}
    STEP1_even(2*high_half + carry_bit, 2*low_half, high_half, low_half + 32768*carry_bit)
  | {high_half,carry_bit,low_half,high_xored,low_xored:nat | carry_bit < 2; 2*high_half + carry_bit < 65536; 2*low_half + 1 < 65536; high_xored < 65536; low_xored < 65536}
    STEP1_odd(2*high_half + carry_bit, 2*low_half + 1, high_xored, low_xored)
      of ($AR.XOR(high_half, 60856, high_xored), $AR.XOR(low_half + 32768*carry_bit, 33568, low_xored))

#pub prfun step1_functional {high,low,first_high,first_low,second_high,second_low:nat}
  (STEP1(high, low, first_high, first_low), STEP1(high, low, second_high, second_low))
  : [first_high == second_high && first_low == second_low] void

prfn _step1_functional {high,low,first_high,first_low,second_high,second_low:nat}
  (first_proof: STEP1(high, low, first_high, first_low), second_proof: STEP1(high, low, second_high, second_low))
  : [first_high == second_high && first_low == second_low] void =
  case+ first_proof of
  | STEP1_even() => (case+ second_proof of STEP1_even() => ())
  | STEP1_odd(first_high_xor, first_low_xor) =>
    (case+ second_proof of
     | STEP1_odd(second_high_xor, second_low_xor) => let
         prval () = $AR.xor_functional(first_high_xor, second_high_xor)
         prval () = $AR.xor_functional(first_low_xor, second_low_xor)
       in () end)

primplement step1_functional {high,low,first_high,first_low,second_high,second_low} (first_proof, second_proof) =
  _step1_functional(first_proof, second_proof)


(* number halved: number = 2 * half + remainder *)
fn halve {number:nat} (number: int number): [half,remainder:nat | number == 2*half + remainder; remainder < 2] (int half, int remainder) =
  let val half = number / 2 in (half, number - 2 * half) end

(* the register shifted by one bit, with its proof *)
#pub fun step1 {high,low:nat | high < 65536; low < 65536} (high: int high, low: int low)
  : [next_high,next_low:nat | next_high < 65536; next_low < 65536] (STEP1(high, low, next_high, next_low) | int next_high, int next_low)

implement step1 {high,low} (high, low) = let
  val [high_half:int, carry_bit:int] (high_half, carry_bit) = halve(high)
  val [low_half:int, low_bit:int] (low_half, low_bit) = halve(low)
  val shifted = low_half + 32768 * carry_bit
in
  if low_bit = 0 then (STEP1_even{high_half,carry_bit,low_half}() | high_half, shifted)
  else let
    val [high_xored:int] (high_proof | high_xor) = xor16(high_half, 60856)
    val [low_xored:int] (low_proof | low_xor) = xor16(shifted, 33568)
  in (STEP1_odd{high_half,carry_bit,low_half,high_xored,low_xored}(high_proof, low_proof) | high_xor, low_xor) end
end

(* STEPN(count, high, low, end_high, end_low): count bits shifted in turn *)
#pub dataprop STEPN(int, int, int, int, int) =
  | {high,low:nat} STEPN_zero(0, high, low, high, low)
  | {count:nat}{high,low,mid_high,mid_low,end_high,end_low:nat}
    STEPN_succ(count+1, high, low, end_high, end_low) of (STEP1(high, low, mid_high, mid_low), STEPN(count, mid_high, mid_low, end_high, end_low))

#pub prfun stepn_functional {count:nat}{high,low,first_high,first_low,second_high,second_low:nat}
  (STEPN(count, high, low, first_high, first_low), STEPN(count, high, low, second_high, second_low))
  : [first_high == second_high && first_low == second_low] void

prfun _stepn_functional {count:nat}{high,low,first_high,first_low,second_high,second_low:nat} .<count>.
  (first_proof: STEPN(count, high, low, first_high, first_low), second_proof: STEPN(count, high, low, second_high, second_low))
  : [first_high == second_high && first_low == second_low] void =
  case+ first_proof of
  | STEPN_zero() => (case+ second_proof of STEPN_zero() => ())
  | STEPN_succ(first_step, first_rest) =>
    (case+ second_proof of
     | STEPN_succ(second_step, second_rest) => let
         prval () = step1_functional(first_step, second_step)
       in _stepn_functional(first_rest, second_rest) end)

primplement stepn_functional {count}{high,low,first_high,first_low,second_high,second_low} (first_proof, second_proof) =
  _stepn_functional(first_proof, second_proof)

#pub fun stepn {count:nat}{high,low:nat | high < 65536; low < 65536} (count: int count, high: int high, low: int low)
  : [end_high,end_low:nat | end_high < 65536; end_low < 65536] (STEPN(count, high, low, end_high, end_low) | int end_high, int end_low)

implement stepn {count}{high,low} (count, high, low) = let
  fun shift_bits {count:nat}{high,low:nat | high < 65536; low < 65536} .<count>. (count: int count, high: int high, low: int low)
    : [end_high,end_low:nat | end_high < 65536; end_low < 65536] (STEPN(count, high, low, end_high, end_low) | int end_high, int end_low) =
    if count = 0 then (STEPN_zero() | high, low)
    else let
      val (step_proof | mid_high, mid_low) = step1(high, low)
      val (rest_proof | end_high, end_low) = shift_bits(count - 1, mid_high, mid_low)
    in (STEPN_succ(step_proof, rest_proof) | end_high, end_low) end
in shift_bits(count, high, low) end

(* BSTEP(high, low, octet, next_high, next_low): the register after the byte octet *)
#pub dataprop BSTEP(int, int, int, int, int) =
  | {high,low,octet,xored_low,next_high,next_low:nat}
    BSTEP_mk(high, low, octet, next_high, next_low) of ($AR.XOR(low, octet, xored_low), STEPN(8, high, xored_low, next_high, next_low))

#pub prfun bstep_functional {high,low,octet,first_high,first_low,second_high,second_low:nat}
  (BSTEP(high, low, octet, first_high, first_low), BSTEP(high, low, octet, second_high, second_low))
  : [first_high == second_high && first_low == second_low] void

prfn _bstep_functional {high,low,octet,first_high,first_low,second_high,second_low:nat}
  (first_proof: BSTEP(high, low, octet, first_high, first_low), second_proof: BSTEP(high, low, octet, second_high, second_low))
  : [first_high == second_high && first_low == second_low] void =
  case+ first_proof of
  | BSTEP_mk(first_xor, first_steps) =>
    (case+ second_proof of
     | BSTEP_mk(second_xor, second_steps) => let
         prval () = $AR.xor_functional(first_xor, second_xor)
       in stepn_functional(first_steps, second_steps) end)

primplement bstep_functional {high,low,octet,first_high,first_low,second_high,second_low} (first_proof, second_proof) =
  _bstep_functional(first_proof, second_proof)

#pub fun bstep {high,low,octet:nat | high < 65536; low < 65536; octet < 256} (high: int high, low: int low, octet: int octet)
  : [next_high,next_low:nat | next_high < 65536; next_low < 65536] (BSTEP(high, low, octet, next_high, next_low) | int next_high, int next_low)

implement bstep {high,low,octet} (high, low, octet) = let
  val (xor_proof | xored_low) = xor16(low, octet)
  val (steps_proof | next_high, next_low) = stepn(8, high, xored_low)
in (BSTEP_mk(xor_proof, steps_proof) | next_high, next_low) end

(* CRCFROM(high, low, octets, end_high, end_low): the register after the bytes octets *)
#pub dataprop CRCFROM(int, int, bytes, int, int) =
  | {high,low:nat} CRCFROM_nil(high, low, bnil(), high, low)
  | {high,low,octet,mid_high,mid_low,end_high,end_low:nat}{octets:bytes}
    CRCFROM_cons(high, low, bcons(octet, octets), end_high, end_low) of (BSTEP(high, low, octet, mid_high, mid_low), CRCFROM(mid_high, mid_low, octets, end_high, end_low))

#pub prfun crcfrom_functional {high,low:nat}{octets:bytes}{byte_count:nat}{first_high,first_low,second_high,second_low:nat}
  (LEN(octets, byte_count), CRCFROM(high, low, octets, first_high, first_low), CRCFROM(high, low, octets, second_high, second_low))
  : [first_high == second_high && first_low == second_low] void

prfun _crcfrom_functional {high,low:nat}{octets:bytes}{byte_count:nat}{first_high,first_low,second_high,second_low:nat} .<byte_count>.
  (len_proof: LEN(octets, byte_count), first_proof: CRCFROM(high, low, octets, first_high, first_low), second_proof: CRCFROM(high, low, octets, second_high, second_low))
  : [first_high == second_high && first_low == second_low] void =
  case+ first_proof of
  | CRCFROM_nil() => (case+ second_proof of CRCFROM_nil() => ())
  | CRCFROM_cons(first_step, first_rest) =>
    (case+ second_proof of
     | CRCFROM_cons(second_step, second_rest) => let
         prval () = bstep_functional(first_step, second_step)
         prval LEN_cons(rest_len) = len_proof
       in _crcfrom_functional(rest_len, first_rest, second_rest) end)

primplement crcfrom_functional {high,low}{octets}{byte_count}{first_high,first_low,second_high,second_low} (len_proof, first_proof, second_proof) =
  _crcfrom_functional(len_proof, first_proof, second_proof)

#pub fun crcfrom {high,low:nat | high < 65536; low < 65536}{octets:bytes}{byte_count:nat} (high: int high, low: int low, octet_list: !blist(octets, byte_count))
  : [end_high,end_low:nat | end_high < 65536; end_low < 65536] (CRCFROM(high, low, octets, end_high, end_low) | int end_high, int end_low)

implement crcfrom {high,low}{octets}{byte_count} (high, low, octet_list) = let
  fun register_after {high,low:nat | high < 65536; low < 65536}{octets:bytes}{byte_count:nat} .<byte_count>.
    (high: int high, low: int low, octet_list: !blist(octets, byte_count))
    : [end_high,end_low:nat | end_high < 65536; end_low < 65536] (CRCFROM(high, low, octets, end_high, end_low) | int end_high, int end_low) =
    case+ octet_list of
    | blist_nil() => (CRCFROM_nil() | high, low)
    | blist_cons(octet, rest) => let
        val (step_proof | mid_high, mid_low) = bstep(high, low, octet)
        val (rest_proof | end_high, end_low) = register_after(mid_high, mid_low, rest)
      in (CRCFROM_cons(step_proof, rest_proof) | end_high, end_low) end
in register_after(high, low, octet_list) end

end
