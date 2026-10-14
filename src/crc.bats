(* crc -- CRC-32, defined in the types: the checksum of a byte string is
   one number, its proof is built as it is computed *)

#target wasm begin

#include "share/atspre_staload.hats"

#use arith as AR
#use array as A

staload "bytes.sats"
staload "bytesarr.sats"

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

(* ===== The table method is the byte step, proved =====

   crc_of_cborrow below computes the CRC-32 of the bytes an array's cells hold
   with a table of 256 registers and a few xors a byte, and says in its type
   that it is crcfrom's fold over those bytes. The proof is in three parts:
   the table's entry i is the register bstep makes from zero (TABLED, built
   as it is filled); the byte step is the register shifted right by 8 bits,
   xored with the entry of its low byte xored with the byte (bstep_by_table:
   the step is linear in xor, and a register whose low byte is zero shifts
   without the polynomial); and the loop's invariant is that the bytes read
   so far are what the cells hold and the register is crcfrom's after them. *)

(* SHIFTED(bits, shifted, base): shifted is base times 2 to the bits *)
dataprop SHIFTED(int, int, int) =
  | {base:nat} SHIFTED_zero(0, base, base)
  | {bits:nat}{shifted,base:nat} SHIFTED_succ(bits+1, 2*shifted, base) of SHIFTED(bits, shifted, base)

(* Numbers under 2 to the bits, each with a number above them (the number times 2 to the bits added), xor
   as the numbers and the numbers above them do *)
prfun xor_cat {bits,width,low_left,low_right,low_both,shifted_left,shifted_right,shifted_both,high_left,high_right,high_both:nat
               | low_left < width; low_right < width; low_both < width} .<bits>.
  (power: $AR.POW2(bits, width), left_shift: SHIFTED(bits, shifted_left, high_left), right_shift: SHIFTED(bits, shifted_right, high_right),
   both_shift: SHIFTED(bits, shifted_both, high_both), low: $AR.XOR(low_left, low_right, low_both), high: $AR.XOR(high_left, high_right, high_both))
  : $AR.XOR(low_left + shifted_left, low_right + shifted_right, low_both + shifted_both) =
  case+ power of
  | $AR.POW2_zero() =>
    (case+ left_shift of SHIFTED_zero() =>
     (case+ right_shift of SHIFTED_zero() =>
      (case+ both_shift of SHIFTED_zero() => high)))
  | $AR.POW2_succ(power_less) =>
    (case+ left_shift of SHIFTED_succ(left_less) =>
     (case+ right_shift of SHIFTED_succ(right_less) =>
      (case+ both_shift of SHIFTED_succ(both_less) =>
       (case+ low of
        | $AR.XOR_nil() => $AR.xor_double(xor_cat(power_less, left_less, right_less, both_less, low, high))
        | $AR.XOR_00(low_less) => $AR.xor_double(xor_cat(power_less, left_less, right_less, both_less, low_less, high))
        | $AR.XOR_01(low_less) => $AR.XOR_01(xor_cat(power_less, left_less, right_less, both_less, low_less, high))
        | $AR.XOR_10(low_less) => $AR.XOR_10(xor_cat(power_less, left_less, right_less, both_less, low_less, high))
        | $AR.XOR_11(low_less) => $AR.XOR_11(xor_cat(power_less, left_less, right_less, both_less, low_less, high))))))

(* left xor right is joined, so left xor joined is right *)
prfun xor_cancel {left,right,joined:nat} .<left+right+joined>. (xored: $AR.XOR(left, right, joined)): $AR.XOR(left, joined, right) =
  case+ xored of
  | $AR.XOR_nil() => $AR.XOR_nil()
  | $AR.XOR_00(rest) => $AR.xor_double(xor_cancel(rest))
  | $AR.XOR_01(rest) => $AR.XOR_01(xor_cancel(rest))
  | $AR.XOR_10(rest) => $AR.XOR_11(xor_cancel(rest))
  | $AR.XOR_11(rest) => $AR.XOR_10(xor_cancel(rest))

(* a polynomial xored into two of three numbers one of which is the xor of the others *)
prfn xor_mix_second_third {first,second,third,poly,second_poly,third_poly:nat}
  (joined: $AR.XOR(first, second, third), second_with: $AR.XOR(second, poly, second_poly), third_with: $AR.XOR(third, poly, third_poly))
  : $AR.XOR(first, second_poly, third_poly) =
  $AR.xor_assoc(joined, third_with, second_with)

prfn xor_mix_first_third {first,second,third,poly,first_poly,third_poly:nat}
  (joined: $AR.XOR(first, second, third), first_with: $AR.XOR(first, poly, first_poly), third_with: $AR.XOR(third, poly, third_poly))
  : $AR.XOR(first_poly, second, third_poly) =
  $AR.xor_comm(xor_mix_second_third($AR.xor_comm(joined), first_with, third_with))

prfn xor_mix_first_second {first,second,third,poly,first_poly,second_poly:nat}
  (joined: $AR.XOR(first, second, third), first_with: $AR.XOR(first, poly, first_poly), second_with: $AR.XOR(second, poly, second_poly))
  : $AR.XOR(first_poly, second_poly, third) = let
  prval poly_first = $AR.xor_comm(first_with)
  prval first_poly_poly = $AR.xor_comm(xor_cancel(poly_first))
  prval poly_second = $AR.xor_comm(second_with)
in $AR.xor_assoc(first_poly_poly, joined, poly_second) end

prfn pow2_15(): $AR.POW2(15, 32768) =
  $AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ(
    $AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ(
    $AR.POW2_zero())))))))))))))))

prfn shift_15 {base:nat}(): SHIFTED(15, 32768*base, base) =
  SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(
    SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(
    SHIFTED_zero())))))))))))))))

(* The xor of low halves with a carry bit each on top *)
prfn carry_cat {first_low,second_low,both_low,first_carry,second_carry,both_carry:nat | first_low < 32768; second_low < 32768; both_low < 32768}
  (low_xor: $AR.XOR(first_low, second_low, both_low), carry_xor: $AR.XOR(first_carry, second_carry, both_carry))
  : $AR.XOR(first_low + 32768*first_carry, second_low + 32768*second_carry, both_low + 32768*both_carry) =
  xor_cat(pow2_15(), shift_15{first_carry}(), shift_15{second_carry}(), shift_15{both_carry}(), low_xor, carry_xor)

(* The halves and the low bits of a xor *)
prfn xor_split {whole_left,whole_right,whole_both,half_left,half_right,half_both,bit_left,bit_right,bit_both:nat
                | whole_left == 2*half_left + bit_left; whole_right == 2*half_right + bit_right; whole_both == 2*half_both + bit_both
                ; bit_left < 2; bit_right < 2; bit_both < 2}
  (xored: $AR.XOR(whole_left, whole_right, whole_both)): ($AR.XOR(half_left, half_right, half_both), $AR.XOR(bit_left, bit_right, bit_both)) =
  case+ xored of
  | $AR.XOR_nil() => ($AR.XOR_nil(), $AR.XOR_nil())
  | $AR.XOR_00(rest) => (rest, $AR.XOR_nil())
  | $AR.XOR_01(rest) => (rest, $AR.XOR_01($AR.XOR_nil()))
  | $AR.XOR_10(rest) => (rest, $AR.XOR_10($AR.XOR_nil()))
  | $AR.XOR_11(rest) => (rest, $AR.XOR_11($AR.XOR_nil()))

(* The step is linear: the step of the xor of two registers is the xor of their steps *)
prfn step1_xor {first_high,first_low,first_next_high,first_next_low,second_high,second_low,second_next_high,second_next_low,third_high,third_low,third_next_high,third_next_low:nat}
  (first_step: STEP1(first_high, first_low, first_next_high, first_next_low), second_step: STEP1(second_high, second_low, second_next_high, second_next_low),
   third_step: STEP1(third_high, third_low, third_next_high, third_next_low),
   high_xor: $AR.XOR(first_high, second_high, third_high), low_xor: $AR.XOR(first_low, second_low, third_low))
  : ($AR.XOR(first_next_high, second_next_high, third_next_high), $AR.XOR(first_next_low, second_next_low, third_next_low)) =
  case+ low_xor of
  | $AR.XOR_nil() =>
    (case+ first_step of STEP1_even{first_high_half,first_carry,first_low_half}() => (case+ second_step of STEP1_even{second_high_half,second_carry,second_low_half}() => (case+ third_step of STEP1_even{third_high_half,third_carry,third_low_half}() => let
      prval (high_half, carries) = xor_split{first_high,second_high,third_high,first_high_half,second_high_half,third_high_half,first_carry,second_carry,third_carry}(high_xor)
      prval (low_half, _) = xor_split{first_low,second_low,third_low,first_low_half,second_low_half,third_low_half,0,0,0}(low_xor)
    in (high_half, carry_cat(low_half, carries)) end)))
  | $AR.XOR_00(_) =>
    (case+ first_step of STEP1_even{first_high_half,first_carry,first_low_half}() => (case+ second_step of STEP1_even{second_high_half,second_carry,second_low_half}() => (case+ third_step of STEP1_even{third_high_half,third_carry,third_low_half}() => let
      prval (high_half, carries) = xor_split{first_high,second_high,third_high,first_high_half,second_high_half,third_high_half,first_carry,second_carry,third_carry}(high_xor)
      prval (low_half, _) = xor_split{first_low,second_low,third_low,first_low_half,second_low_half,third_low_half,0,0,0}(low_xor)
    in (high_half, carry_cat(low_half, carries)) end)))
  | $AR.XOR_01(_) =>
    (case+ first_step of STEP1_even{first_high_half,first_carry,first_low_half}() => (case+ second_step of STEP1_odd{second_high_half,second_carry,second_low_half,second_high_xored,second_low_xored}(second_high_poly, second_low_poly) => (case+ third_step of STEP1_odd{third_high_half,third_carry,third_low_half,third_high_xored,third_low_xored}(third_high_poly, third_low_poly) => let
      prval (high_half, carries) = xor_split{first_high,second_high,third_high,first_high_half,second_high_half,third_high_half,first_carry,second_carry,third_carry}(high_xor)
      prval (low_half, _) = xor_split{first_low,second_low,third_low,first_low_half,second_low_half,third_low_half,0,1,1}(low_xor)
    in (xor_mix_second_third(high_half, second_high_poly, third_high_poly), xor_mix_second_third(carry_cat(low_half, carries), second_low_poly, third_low_poly)) end)))
  | $AR.XOR_10(_) =>
    (case+ first_step of STEP1_odd{first_high_half,first_carry,first_low_half,first_high_xored,first_low_xored}(first_high_poly, first_low_poly) => (case+ second_step of STEP1_even{second_high_half,second_carry,second_low_half}() => (case+ third_step of STEP1_odd{third_high_half,third_carry,third_low_half,third_high_xored,third_low_xored}(third_high_poly, third_low_poly) => let
      prval (high_half, carries) = xor_split{first_high,second_high,third_high,first_high_half,second_high_half,third_high_half,first_carry,second_carry,third_carry}(high_xor)
      prval (low_half, _) = xor_split{first_low,second_low,third_low,first_low_half,second_low_half,third_low_half,1,0,1}(low_xor)
    in (xor_mix_first_third(high_half, first_high_poly, third_high_poly), xor_mix_first_third(carry_cat(low_half, carries), first_low_poly, third_low_poly)) end)))
  | $AR.XOR_11(_) =>
    (case+ first_step of STEP1_odd{first_high_half,first_carry,first_low_half,first_high_xored,first_low_xored}(first_high_poly, first_low_poly) => (case+ second_step of STEP1_odd{second_high_half,second_carry,second_low_half,second_high_xored,second_low_xored}(second_high_poly, second_low_poly) => (case+ third_step of STEP1_even{third_high_half,third_carry,third_low_half}() => let
      prval (high_half, carries) = xor_split{first_high,second_high,third_high,first_high_half,second_high_half,third_high_half,first_carry,second_carry,third_carry}(high_xor)
      prval (low_half, _) = xor_split{first_low,second_low,third_low,first_low_half,second_low_half,third_low_half,1,1,0}(low_xor)
    in (xor_mix_first_second(high_half, first_high_poly, second_high_poly), xor_mix_first_second(carry_cat(low_half, carries), first_low_poly, second_low_poly)) end)))

prfun stepn_xor {count:nat}{first_high,first_low,first_end_high,first_end_low,second_high,second_low,second_end_high,second_end_low,third_high,third_low,third_end_high,third_end_low:nat} .<count>.
  (first_steps: STEPN(count, first_high, first_low, first_end_high, first_end_low), second_steps: STEPN(count, second_high, second_low, second_end_high, second_end_low),
   third_steps: STEPN(count, third_high, third_low, third_end_high, third_end_low),
   high_xor: $AR.XOR(first_high, second_high, third_high), low_xor: $AR.XOR(first_low, second_low, third_low))
  : ($AR.XOR(first_end_high, second_end_high, third_end_high), $AR.XOR(first_end_low, second_end_low, third_end_low)) =
  case+ first_steps of
  | STEPN_zero() => (case+ second_steps of STEPN_zero() => (case+ third_steps of STEPN_zero() => (high_xor, low_xor)))
  | STEPN_succ(first_step, first_rest) =>
    (case+ second_steps of
     | STEPN_succ(second_step, second_rest) =>
       (case+ third_steps of
        | STEPN_succ(third_step, third_rest) => let
            prval (mid_high_xor, mid_low_xor) = step1_xor(first_step, second_step, third_step, high_xor, low_xor)
          in stepn_xor(first_rest, second_rest, third_rest, mid_high_xor, mid_low_xor) end))

(* Every two numbers have an exclusive or *)
prfun xor_exists {left,right:nat} .<left+right>. (): [joined:nat] $AR.XOR(left, right, joined) =
  sif left == 0 then
    (sif right == 0 then $AR.XOR_nil() else $AR.xor_zero_left{right}())
  else
    (sif left == 2*(left/2) then
       (sif right == 2*(right/2) then $AR.xor_double(xor_exists{left/2,right/2}())
        else $AR.XOR_01(xor_exists{left/2,right/2}()))
     else
       (sif right == 2*(right/2) then $AR.XOR_10(xor_exists{left/2,right/2}())
        else $AR.XOR_11(xor_exists{left/2,right/2}())))

prfn pow2_16(): $AR.POW2(16, 65536) =
  $AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ(
    $AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ(
    $AR.POW2_zero()))))))))))))))))

(* Every register has a next one *)
prfn step1_exists {high,low:nat | high < 65536; low < 65536} ()
  : [next_high,next_low:nat | next_high < 65536; next_low < 65536] STEP1(high, low, next_high, next_low) =
  sif low == 2*(low/2) then STEP1_even{high/2, high - 2*(high/2), low/2}()
  else let
    prval [high_xored:int] high_proof = xor_exists{high/2, 60856}()
    prval () = $AR.xor_bound(pow2_16(), high_proof)
    prval [low_xored:int] low_proof = xor_exists{low/2 + 32768*(high - 2*(high/2)), 33568}()
    prval () = $AR.xor_bound(pow2_16(), low_proof)
  in STEP1_odd{high/2, high - 2*(high/2), low/2, high_xored, low_xored}(high_proof, low_proof) end

prfun stepn_exists {count:nat}{high,low:nat | high < 65536; low < 65536} .<count>. ()
  : [end_high,end_low:nat | end_high < 65536; end_low < 65536] STEPN(count, high, low, end_high, end_low) =
  sif count == 0 then STEPN_zero()
  else let
    prval [mid_high:int, mid_low:int] step = step1_exists{high,low}()
    prval rest = stepn_exists{count-1}{mid_high,mid_low}()
  in STEPN_succ(step, rest) end

(* Shifting bits out of a register whose low half is a multiple of 2 to the bits
   never xors the polynomial in. Each statement is in digits (the register's
   high half is h * 2 to the bits + r, its low half l * 2 to the bits) and
   is built from the smaller one, so no index nests a division and the
   solver is given little at a time *)

(* Bits shifted in turn make one run of the steps *)
prfun stepn_append {first,second:nat}{high,low,mid_high,mid_low,end_high,end_low:nat} .<first>.
  (first_steps: STEPN(first, high, low, mid_high, mid_low), second_steps: STEPN(second, mid_high, mid_low, end_high, end_low))
  : STEPN(first + second, high, low, end_high, end_low) =
  case+ first_steps of
  | STEPN_zero() => second_steps
  | STEPN_succ(step, rest) => STEPN_succ(step, stepn_append(rest, second_steps))

(* 2 bits shifted out of a register whose low 2 bits are zero *)
prfn shift2 {h,r,l:nat | r < 4; 4*h + r < 65536; 4*l < 65536} ()
  : STEPN(2, 4*h + r, 4*l, h, l + 16384*r) =
  STEPN_succ(STEP1_even{2*h + r/2, r - 2*(r/2), 2*l}(),
    STEPN_succ(STEP1_even{h, r/2, l + 16384*(r - 2*(r/2))}(), STEPN_zero()))

(* 4 bits *)
prfn shift4 {h,r,l:nat | r < 16; 16*h + r < 65536; 16*l < 65536} ()
  : STEPN(4, 16*h + r, 16*l, h, l + 4096*r) =
  stepn_append(shift2{4*h + r/4, r - 4*(r/4), 4*l}(), shift2{h, r/4, l + 4096*(r - 4*(r/4))}())

(* 8 bits: the polynomial is never xored in *)
prfn shift8 {h,r,l:nat | r < 256; 256*h + r < 65536; 256*l < 65536} ()
  : STEPN(8, 256*h + r, 256*l, h, l + 256*r) =
  stepn_append(shift4{16*h + r/16, r - 16*(r/16), 16*l}(), shift4{h, r/16, l + 256*(r - 16*(r/16))}())

prfn pow2_8(): $AR.POW2(8, 256) =
  $AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ($AR.POW2_succ(
    $AR.POW2_zero()))))))))

prfn shift_8 {base:nat}(): SHIFTED(8, 256*base, base) =
  SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_succ(SHIFTED_zero()))))))))

(* The byte step by the table: the register after a byte is the register shifted right by 8 bits, xored with the
   table's entry for the low byte xored with the byte *)
prfn bstep_by_table {high,low,octet:nat | high < 65536; low < 65536; octet < 256}
  {high_upper,high_lower,low_upper,low_lower:nat | high == 256*high_upper + high_lower; low == 256*low_upper + low_lower; high_lower < 256; low_lower < 256}
  {index,table_high,table_low,next_high,next_low:nat}
  (index_xor: $AR.XOR(low_lower, octet, index), entry: BSTEP(0, 0, index, table_high, table_low),
   high_xor: $AR.XOR(high_upper, table_high, next_high), low_xor: $AR.XOR(low_upper + 256*high_lower, table_low, next_low))
  : BSTEP(high, low, octet, next_high, next_low) = let
  prval () = $AR.xor_bound(pow2_8(), index_xor)
  prval () = (): [low_upper < 256] void
  prval () = (): [index < 256] void
  prval whole_xor = xor_cat(pow2_8(), shift_8{low_upper}(), shift_8{0}(), shift_8{low_upper}(), index_xor, $AR.xor_zero_right{low_upper}())
  prval BSTEP_mk(zero_xor, table_steps) = entry
  prval () = $AR.xor_functional(zero_xor, $AR.xor_zero_left{index}())
  prval whole_index_xor = xor_cat(pow2_8(), shift_8{0}(), shift_8{low_upper}(), shift_8{low_upper}(), $AR.xor_zero_right{index}(), $AR.xor_zero_left{low_upper}())
  prval [full_high:int, full_low:int] full_steps = stepn_exists{8}{high, index + 256*low_upper}()
  prval (full_high_xor, full_low_xor) = stepn_xor(table_steps, shift8{high_upper, high_lower, low_upper}(), full_steps, $AR.xor_zero_left{high}(), whole_index_xor)
  prval () = $AR.xor_functional(full_high_xor, $AR.xor_comm(high_xor))
  prval () = $AR.xor_functional(full_low_xor, $AR.xor_comm(low_xor))
in BSTEP_mk(whole_xor, full_steps) end

(* ENTRY(cells, k, high, low): the table's entry k, 4 bytes from 4k, low half first, is the register (high, low) *)
dataprop ENTRY($A.cells, int, int, int) =
  | {ct:$A.cells}{k:nat}{low0,low1,high0,high1:int | 0 <= low0; low0 < 256; 0 <= low1; low1 < 256; 0 <= high0; high0 < 256; 0 <= high1; high1 < 256}
    ENTRY_mk(ct, k, high0 + 256*high1, low0 + 256*low1)
      of ($A.NTH(ct, 4*k, low0), $A.NTH(ct, 4*k + 1, low1), $A.NTH(ct, 4*k + 2, high0), $A.NTH(ct, 4*k + 3, high1))

(* TABLED(cells, count): the first count entries of the table in cells are the registers the byte step makes from zero *)
dataprop TABLED($A.cells, int) =
  | {ct:$A.cells} TABLED_nil(ct, 0)
  | {ct:$A.cells}{count:nat}{high,low:int}
    TABLED_cons(ct, count + 1) of (TABLED(ct, count), ENTRY(ct, count, high, low), BSTEP(0, 0, count, high, low))

prfun tabled_get {ct:$A.cells}{count,k:nat | k < count} .<count>. (tabled: TABLED(ct, count))
  : [high,low:int] (ENTRY(ct, k, high, low), BSTEP(0, 0, k, high, low)) =
  case+ tabled of
  | TABLED_cons(rest, entry, step) =>
    (sif k == count - 1 then (entry, step) else tabled_get{ct}{count-1,k}(rest))

prfn entry_set {ct,ct_set:$A.cells}{k:nat}{position:nat | 4*k + 3 < position}{value:int}{high,low:int}
  (cells_set: $A.SETC(ct, position, value, ct_set), entry: ENTRY(ct, k, high, low)): ENTRY(ct_set, k, high, low) = let
  prval ENTRY_mk(low0_cell, low1_cell, high0_cell, high1_cell) = entry
in ENTRY_mk($A.setc_nth_other(cells_set, low0_cell), $A.setc_nth_other(cells_set, low1_cell),
            $A.setc_nth_other(cells_set, high0_cell), $A.setc_nth_other(cells_set, high1_cell)) end

(* Setting a cell after the entries leaves them *)
prfun tabled_set {ct,ct_set:$A.cells}{count:nat}{position:nat | 4*count <= position}{value:int} .<count>.
  (cells_set: $A.SETC(ct, position, value, ct_set), tabled: TABLED(ct, count)): TABLED(ct_set, count) =
  case+ tabled of
  | TABLED_nil() => TABLED_nil()
  | TABLED_cons(rest, entry, step) => TABLED_cons(tabled_set(cells_set, rest), entry_set(cells_set, entry), step)

(* The number split at 8 bits *)
fn split8 {number:nat | number < 65536} (number: int number)
  : [upper,lower:nat | number == 256*upper + lower; upper < 256; lower < 256] (int upper, int lower) =
  let val upper = number / 256 in (upper, number - 256 * upper) end

(* The table of the 256 registers the byte step makes from zero (entry i is the register after the byte i, 4 bytes
   an entry, low half first), with the proof that it is *)
fun table_build {l:agz}{ct:$A.cells}{count:nat | count <= 256} .<256 - count>.
  (tabled: TABLED(ct, count) | table: $A.barr(l, 1024, ct), count: int count)
  : [ct_done:$A.cells] (TABLED(ct_done, 256) | $A.barr(l, 1024, ct_done)) =
  if count >= 256 then (tabled | table)
  else let
    val [entry_high:int, entry_low:int] (step | register_high, register_low) = bstep(0, 0, count)
    val (high1, high0) = split8(register_high)
    val (low1, low0) = split8(register_low)
    val (set_low0 | table0) = $A.barr_set(table, 4 * count, low0)
    val (set_low1 | table1) = $A.barr_set(table0, 4 * count + 1, low1)
    val (set_high0 | table2) = $A.barr_set(table1, 4 * count + 2, high0)
    val (set_high1 | table3) = $A.barr_set(table2, 4 * count + 3, high1)
    prval tabled0 = tabled_set(set_low0, tabled)
    prval tabled1 = tabled_set(set_low1, tabled0)
    prval tabled2 = tabled_set(set_high0, tabled1)
    prval tabled3 = tabled_set(set_high1, tabled2)
    prval low0_cell = $A.setc_nth_other(set_high1, $A.setc_nth_other(set_high0, $A.setc_nth_other(set_low1, $A.setc_nth_same(set_low0))))
    prval low1_cell = $A.setc_nth_other(set_high1, $A.setc_nth_other(set_high0, $A.setc_nth_same(set_low1)))
    prval high0_cell = $A.setc_nth_other(set_high1, $A.setc_nth_same(set_high0))
    prval high1_cell = $A.setc_nth_same(set_high1)
  in table_build(TABLED_cons(tabled3, ENTRY_mk(low0_cell, low1_cell, high0_cell, high1_cell), step) | table3, count + 1) end


(* The byte step by the table, with the proof that it is the byte step *)
fn table_step {l:agz}{ct:$A.cells}{high,low,octet:nat | high < 65536; low < 65536; octet < 256}
  (tabled: TABLED(ct, 256) | table: !$A.barr(l, 1024, ct), high: int high, low: int low, octet: int octet)
  : [next_high,next_low:nat | next_high < 65536; next_low < 65536] (BSTEP(high, low, octet, next_high, next_low) | int next_high, int next_low) = let
  val [high_upper:int, high_lower:int] (high_upper, high_lower) = split8(high)
  val [low_upper:int, low_lower:int] (low_upper, low_lower) = split8(low)
  val [index:int] (index_xor | index) = xor16(low_lower, octet)
  prval () = $AR.xor_bound(pow2_8(), index_xor)
  prval [table_high:int, table_low:int] (entry, step) = tabled_get{ct}{256,index}(tabled)
  prval ENTRY_mk(low0_cell, low1_cell, high0_cell, high1_cell) = entry
  val (low0_read | low0) = $A.barr_get(table, 4 * index)
  val (low1_read | low1) = $A.barr_get(table, 4 * index + 1)
  val (high0_read | high0) = $A.barr_get(table, 4 * index + 2)
  val (high1_read | high1) = $A.barr_get(table, 4 * index + 3)
  prval () = $A.nth_functional(low0_read, low0_cell)
  prval () = $A.nth_functional(low1_read, low1_cell)
  prval () = $A.nth_functional(high0_read, high0_cell)
  prval () = $A.nth_functional(high1_read, high1_cell)
  val [next_high:int] (high_xor | next_high) = xor16(high_upper, high0 + 256 * high1)
  val [next_low:int] (low_xor | next_low) = xor16(low_upper + 256 * high_lower, low0 + 256 * low1)
in
  (bstep_by_table{high,low,octet}{high_upper,high_lower,low_upper,low_lower}(index_xor, step, high_xor, low_xor) | next_high, next_low)
end

(* Appending one byte to a list the cells hold from a position makes a list they hold *)
prfun holds_snoc {cells:$A.cells}{position,count:nat}{octets:bytes}{octet:int} .<count>.
  (holds: HOLDS(cells, position, octets, count), cell: $A.NTH(cells, position + count, octet))
  : [joined:bytes] (APPEND(octets, bcons(octet, bnil()), joined), HOLDS(cells, position, joined, count + 1)) =
  case+ holds of
  | HOLDS_nil(cells_len) => let
      prval () = $A.nth_in_len(cell, cells_len)
    in (APPEND_nil(), HOLDS_cons(cell, HOLDS_nil(cells_len))) end
  | HOLDS_cons(first_cell, rest) => let
      prval (rest_append, rest_holds) = holds_snoc(rest, cell)
    in (APPEND_cons(rest_append), HOLDS_cons(first_cell, rest_holds)) end

(* The cells hold as many bytes as the list has *)
prfun holds_len {cells:$A.cells}{position,count:nat}{octets:bytes} .<count>. (holds: HOLDS(cells, position, octets, count)): LEN(octets, count) =
  case+ holds of
  | HOLDS_nil(_) => LEN_nil()
  | HOLDS_cons(_, rest) => LEN_cons(holds_len(rest))

(* The register after bytes and one more *)
prfun crcfrom_snoc {count:nat}{high,low,mid_high,mid_low,end_high,end_low:nat}{octets,joined:bytes}{octet:nat} .<count>.
  (octets_len: LEN(octets, count), appended: APPEND(octets, bcons(octet, bnil()), joined),
   done: CRCFROM(high, low, octets, mid_high, mid_low), step: BSTEP(mid_high, mid_low, octet, end_high, end_low))
  : CRCFROM(high, low, joined, end_high, end_low) =
  case+ appended of
  | APPEND_nil() => (case+ done of CRCFROM_nil() => CRCFROM_cons(step, CRCFROM_nil()))
  | APPEND_cons(rest_append) =>
    (case+ done of
     | CRCFROM_cons(first_step, rest_done) =>
       (case+ octets_len of LEN_cons(rest_len) => CRCFROM_cons(first_step, crcfrom_snoc(rest_len, rest_append, rest_done, step))))


(* The CRC-32 (high and low 16 bits) of the n bytes the cells of an array
   hold, by the table of the 256 registers the byte step above makes from zero
   (entry i is the register after the byte i; 4 bytes an entry, low half
   first): the register after a byte is the register shifted right by 8
   bits, xored with the entry of its low byte xored with the byte, and the
   result is the complement. It costs a byte, not the list cell a byte that
   the fold crcfrom makes of a list, so a chapter of megabytes can be
   checked. It is proved: the bytes
   are a list octets that the cells hold (HOLDS, array's NTH of each cell
   read), and the register after them is crcfrom's fold over that list
   (CRCFROM from 0xFFFFFFFF), the CRC being its complement. The array is a
   barr, borrowed with its cells in the type (array's cborrow); the cells
   are not known beyond the number n of them (CLEN), as barr_of_arr gives
   them, and a caller that knows what they hold has it from holds_functional *)
#pub fun crc_of_cborrow {lb:agz}{n:pos}{cs:$A.cells}
  (cells_len: $A.CLEN(cs, n) | bytes: !$A.cborrow(lb, n, cs), n: int n)
  : [octets:bytes][high,low:nat | high < 65536; low < 65536]
    (HOLDS(cs, 0, octets, n), CRCFROM(65535, 65535, octets, 65535 - high, 65535 - low) | @(int high, int low))

implement crc_of_cborrow {lb}{n}{cs} (cells_len | bytes, n) = let
  val (_ | table0) = $A.barr_alloc(1024)
  val (tabled | table) = table_build(TABLED_nil() | table0, 0)
  fun fold_bytes {l:agz}{ct:$A.cells}{count:nat | count <= n}{octets:bytes}{high,low:nat | high < 65536; low < 65536} .<n - count>.
    (tabled: TABLED(ct, 256), held: HOLDS(cs, 0, octets, count), done: CRCFROM(65535, 65535, octets, high, low)
     | bytes: !$A.cborrow(lb, n, cs), table: !$A.barr(l, 1024, ct), count: int count, high: int high, low: int low)
    : [full:bytes][end_high,end_low:nat | end_high < 65536; end_low < 65536]
      (HOLDS(cs, 0, full, n), CRCFROM(65535, 65535, full, end_high, end_low) | @(int end_high, int end_low)) =
    if count >= n then (held, done | @(high, low))
    else let
      val (cell | octet) = $A.cborrow_get(bytes, count)
      val (step | next_high, next_low) = table_step(tabled | table, high, low, octet)
      prval (appended, held_more) = holds_snoc(held, cell)
      prval done_more = crcfrom_snoc(holds_len(held), appended, done, step)
    in fold_bytes(tabled, held_more, done_more | bytes, table, count + 1, next_high, next_low) end
  val (held, done | @(end_high, end_low)) =
    fold_bytes(tabled, HOLDS_nil(cells_len), CRCFROM_nil() | bytes, table, 0, 65535, 65535)
  val () = $A.barr_free(table)
in (held, done | @(65535 - end_high, 65535 - end_low)) end

end
