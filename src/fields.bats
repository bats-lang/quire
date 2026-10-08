(* fields -- the values inside a chunk: numbers of 32 bits and strings
   of up to 255 bytes, one after another *)

#target wasm begin

#include "share/atspre_staload.hats"

staload "bytes.sats"

(* LES(byte_count, number, octets): octets are the byte_count bytes of the number, least significant
   first, the last byte holding the sign *)
#pub dataprop LES(int, int, bytes) =
  | {low_byte:int | 0 <= low_byte; low_byte < 128} LES_last(1, low_byte, bcons(low_byte, bnil()))
  | {low_byte:int | 128 <= low_byte; low_byte < 256} LES_last_neg(1, low_byte - 256, bcons(low_byte, bnil()))
  | {byte_count:pos}{rest_number:int}{low_byte:int | 0 <= low_byte; low_byte < 256}{octets:bytes}
    LES_cons(byte_count+1, low_byte + 256*rest_number, bcons(low_byte, octets)) of LES(byte_count, rest_number, octets)

#pub prfun les_bytes_functional {byte_count:pos}{number:int}{left_octets,right_octets:bytes} (LES(byte_count, number, left_octets), LES(byte_count, number, right_octets)): EQB(left_octets, right_octets)

prfun _les_bytes {byte_count:pos}{number:int}{left_octets,right_octets:bytes} .<byte_count>. (left: LES(byte_count, number, left_octets), right: LES(byte_count, number, right_octets)): EQB(left_octets, right_octets) =
  case+ left of
  | LES_last() => (case+ right of LES_last() => EQB_refl())
  | LES_last_neg() => (case+ right of LES_last_neg() => EQB_refl())
  | LES_cons(left_tail) =>
    (case+ right of
     | LES_cons(right_tail) =>
       (case+ _les_bytes(left_tail, right_tail) of EQB_refl() => EQB_refl()))

primplement les_bytes_functional {byte_count}{number}{left_octets,right_octets} (left, right) = _les_bytes(left, right)

#pub prfun les_number_functional {byte_count:pos}{left_number,right_number:int}{octets:bytes} (LES(byte_count, left_number, octets), LES(byte_count, right_number, octets)): EQI(left_number, right_number)

prfun _les_number {byte_count:pos}{left_number,right_number:int}{octets:bytes} .<byte_count>. (left: LES(byte_count, left_number, octets), right: LES(byte_count, right_number, octets)): EQI(left_number, right_number) =
  case+ left of
  | LES_last() => (case+ right of LES_last() => EQI_refl())
  | LES_last_neg() => (case+ right of LES_last_neg() => EQI_refl())
  | LES_cons(left_tail) =>
    (case+ right of
     | LES_cons(right_tail) =>
       (case+ _les_number(left_tail, right_tail) of EQI_refl() => EQI_refl()))

primplement les_number_functional {byte_count}{left_number,right_number}{octets} (left, right) = _les_number(left, right)


(* the fields of a group: their kinds, and their values *)
#pub datasort layout =
  | lo_nil of ()
  | lo_i32 of (layout)
  | lo_str of (layout)

#pub datasort fvals =
  | fv_nil of ()
  | fv_i32 of (int, fvals)
  | fv_str of (bytes, fvals)

(* STRB(text, prefixed): prefixed is text with its length in front, under 256 *)
#pub dataprop STRB(bytes, bytes) =
  | {len:int | 0 <= len; len < 256}{text:bytes} STRB_mk(text, bcons(len, text)) of LEN(text, len)

(* FENC(kinds, contents, octets): octets hold the contents, of kinds, one after another *)
#pub dataprop FENC(layout, fvals, bytes) =
  | FENC_nil(lo_nil(), fv_nil(), bnil())
  | {number:int}{kinds:layout}{contents:fvals}{four_octets,rest,out:bytes}
    FENC_i32(lo_i32(kinds), fv_i32(number, contents), out) of (LES(4, number, four_octets), FENC(kinds, contents, rest), APPEND(four_octets, rest, out))
  | {text:bytes}{kinds:layout}{contents:fvals}{prefixed,rest,out:bytes}
    FENC_str(lo_str(kinds), fv_str(text, contents), out) of (STRB(text, prefixed), FENC(kinds, contents, rest), APPEND(prefixed, rest, out))

(* what reading values comes to *)
#pub datasort fdres =
  | fd_ok of (fvals)
  | fd_bad of ()

#pub dataprop EQFD(fdres, fdres) =
  | {result:fdres} EQFD_refl(result, result)

(* FDEC(kinds, octets, result): reading values of kinds from octets comes to result *)
#pub dataprop FDEC(layout, bytes, fdres) =
  | FDEC_nil(lo_nil(), bnil(), fd_ok(fv_nil()))
  | {first_byte:int | 0 <= first_byte; first_byte < 256}{after_first:bytes} FDEC_nil_extra(lo_nil(), bcons(first_byte, after_first), fd_bad())
  | {kinds:layout}{octets:bytes} FDEC_i32_short(lo_i32(kinds), octets, fd_bad()) of SHORT(4, octets)
  | {number:int}{kinds:layout}{contents:fvals}{octets,four_octets,rest:bytes}
    FDEC_i32_ok(lo_i32(kinds), octets, fd_ok(fv_i32(number, contents))) of (TAKE(4, octets, four_octets, rest), LES(4, number, four_octets), FDEC(kinds, rest, fd_ok(contents)))
  | {number:int}{kinds:layout}{octets,four_octets,rest:bytes}
    FDEC_i32_bad(lo_i32(kinds), octets, fd_bad()) of (TAKE(4, octets, four_octets, rest), LES(4, number, four_octets), FDEC(kinds, rest, fd_bad()))
  | {kinds:layout} FDEC_str_empty(lo_str(kinds), bnil(), fd_bad())
  | {kinds:layout}{len:int | 0 <= len; len < 256}{after_length:bytes}
    FDEC_str_short(lo_str(kinds), bcons(len, after_length), fd_bad()) of SHORT(len, after_length)
  | {kinds:layout}{len:int | 0 <= len; len < 256}{after_length,text,rest:bytes}{contents:fvals}
    FDEC_str_ok(lo_str(kinds), bcons(len, after_length), fd_ok(fv_str(text, contents))) of (TAKE(len, after_length, text, rest), FDEC(kinds, rest, fd_ok(contents)))
  | {kinds:layout}{len:int | 0 <= len; len < 256}{after_length,text,rest:bytes}
    FDEC_str_bad(lo_str(kinds), bcons(len, after_length), fd_bad()) of (TAKE(len, after_length, text, rest), FDEC(kinds, rest, fd_bad()))


(* what is left after taking take_count bytes has a known length *)
#pub prfun take_rest_len {take_count:nat}{octets,taken,remaining:bytes}{octet_count:nat} (TAKE(take_count, octets, taken, remaining), LEN(octets, octet_count)): [rest_count:nat | rest_count + take_count == octet_count] LEN(remaining, rest_count)

primplement take_rest_len {take_count}{octets,taken,remaining}{octet_count} (take_proof, whole) = let
  prval (append_proof, front) = take_append(take_proof)
in append_len_rest(append_proof, front, whole) end

#pub prfun falsep_eqfd {left_result,right_result:fdres} (FALSEP()): EQFD(left_result, right_result)

primplement falsep_eqfd {left_result,right_result} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

#pub prfun fdec_functional {kinds:layout}{octets:bytes}{octet_count:nat}{left_result,right_result:fdres} (LEN(octets, octet_count), FDEC(kinds, octets, left_result), FDEC(kinds, octets, right_result)): EQFD(left_result, right_result)

prfun _fdec_functional {kinds:layout}{octets:bytes}{octet_count:nat}{left_result,right_result:fdres} .<octet_count>.
  (whole: LEN(octets, octet_count), left: FDEC(kinds, octets, left_result), right: FDEC(kinds, octets, right_result)): EQFD(left_result, right_result) =
  case+ left of
  | FDEC_nil() => (case+ right of FDEC_nil() => EQFD_refl())
  | FDEC_nil_extra() => (case+ right of FDEC_nil_extra() => EQFD_refl())
  | FDEC_i32_short(left_short) =>
    (case+ right of
     | FDEC_i32_short(_) => EQFD_refl()
     | FDEC_i32_ok(right_take, _, _) => falsep_eqfd(take_not_short(right_take, left_short))
     | FDEC_i32_bad(right_take, _, _) => falsep_eqfd(take_not_short(right_take, left_short)))
  | FDEC_i32_ok(left_take, left_number, left_tail) =>
    (case+ right of
     | FDEC_i32_short(right_short) => falsep_eqfd(take_not_short(left_take, right_short))
     | FDEC_i32_ok(right_take, right_number, right_tail) => let
         prval SAME2_refl() = take_functional(left_take, right_take)
         prval EQI_refl() = les_number_functional(left_number, right_number)
         prval rest_len = take_rest_len(left_take, whole)
       in (case+ _fdec_functional(rest_len, left_tail, right_tail) of EQFD_refl() => EQFD_refl()) end
     | FDEC_i32_bad(right_take, right_number, right_tail) => let
         prval SAME2_refl() = take_functional(left_take, right_take)
         prval rest_len = take_rest_len(left_take, whole)
       in (case+ _fdec_functional(rest_len, left_tail, right_tail) of EQFD_refl() =/=> ()) end)
  | FDEC_i32_bad(left_take, left_number, left_tail) =>
    (case+ right of
     | FDEC_i32_short(right_short) => falsep_eqfd(take_not_short(left_take, right_short))
     | FDEC_i32_ok(right_take, right_number, right_tail) => let
         prval SAME2_refl() = take_functional(left_take, right_take)
         prval rest_len = take_rest_len(left_take, whole)
       in (case+ _fdec_functional(rest_len, left_tail, right_tail) of EQFD_refl() =/=> ()) end
     | FDEC_i32_bad(right_take, right_number, right_tail) => EQFD_refl())
  | FDEC_str_empty() => (case+ right of FDEC_str_empty() => EQFD_refl())
  | FDEC_str_short(left_short) =>
    (case+ right of
     | FDEC_str_short(_) => EQFD_refl()
     | FDEC_str_ok(right_take, _) => falsep_eqfd(take_not_short(right_take, left_short))
     | FDEC_str_bad(right_take, _) => falsep_eqfd(take_not_short(right_take, left_short)))
  | FDEC_str_ok(left_take, left_tail) =>
    (case+ right of
     | FDEC_str_short(right_short) => falsep_eqfd(take_not_short(left_take, right_short))
     | FDEC_str_ok(right_take, right_tail) => let
         prval SAME2_refl() = take_functional(left_take, right_take)
         prval LEN_cons(tail_len) = whole
         prval rest_len = take_rest_len(left_take, tail_len)
       in (case+ _fdec_functional(rest_len, left_tail, right_tail) of EQFD_refl() => EQFD_refl()) end
     | FDEC_str_bad(right_take, right_tail) => let
         prval SAME2_refl() = take_functional(left_take, right_take)
         prval LEN_cons(tail_len) = whole
         prval rest_len = take_rest_len(left_take, tail_len)
       in (case+ _fdec_functional(rest_len, left_tail, right_tail) of EQFD_refl() =/=> ()) end)
  | FDEC_str_bad(left_take, left_tail) =>
    (case+ right of
     | FDEC_str_short(right_short) => falsep_eqfd(take_not_short(left_take, right_short))
     | FDEC_str_ok(right_take, right_tail) => let
         prval SAME2_refl() = take_functional(left_take, right_take)
         prval LEN_cons(tail_len) = whole
         prval rest_len = take_rest_len(left_take, tail_len)
       in (case+ _fdec_functional(rest_len, left_tail, right_tail) of EQFD_refl() =/=> ()) end
     | FDEC_str_bad(right_take, right_tail) => EQFD_refl())

primplement fdec_functional {kinds}{octets}{octet_count}{left_result,right_result} (whole, left, right) = _fdec_functional(whole, left, right)


#pub prfun les_len {byte_count:pos}{number:int}{octets:bytes} (LES(byte_count, number, octets)): LEN(octets, byte_count)

prfun _les_len {byte_count:pos}{number:int}{octets:bytes} .<byte_count>. (number_proof: LES(byte_count, number, octets)): LEN(octets, byte_count) =
  case+ number_proof of
  | LES_last() => LEN_cons(LEN_nil())
  | LES_last_neg() => LEN_cons(LEN_nil())
  | LES_cons(tail_proof) => LEN_cons(_les_len(tail_proof))

primplement les_len {byte_count}{number}{octets} (number_proof) = _les_len(number_proof)

(* values written are read back as they were *)
#pub prfun fenc_fdec {kinds:layout}{contents:fvals}{octets:bytes}{octet_count:nat} (LEN(octets, octet_count), FENC(kinds, contents, octets)): FDEC(kinds, octets, fd_ok(contents))

prfun _fenc_fdec {kinds:layout}{contents:fvals}{octets:bytes}{octet_count:nat} .<octet_count>. (whole: LEN(octets, octet_count), encoding: FENC(kinds, contents, octets)): FDEC(kinds, octets, fd_ok(contents)) =
  case+ encoding of
  | FENC_nil() => FDEC_nil()
  | FENC_i32(number_proof, rest_encoding, append_proof) => let
      prval take_proof = append_take(append_proof, les_len(number_proof))
      prval rest_len = take_rest_len(take_proof, whole)
    in FDEC_i32_ok(take_proof, number_proof, _fenc_fdec(rest_len, rest_encoding)) end
  | FENC_str(STRB_mk(length_proof), rest_encoding, append_proof) =>
    (case+ append_proof of
     | APPEND_cons(inner) => let
         prval take_proof = append_take(inner, length_proof)
         prval LEN_cons(tail_len) = whole
         prval rest_len = take_rest_len(take_proof, tail_len)
       in FDEC_str_ok(take_proof, _fenc_fdec(rest_len, rest_encoding)) end)

primplement fenc_fdec {kinds}{contents}{octets}{octet_count} (whole, encoding) = _fenc_fdec(whole, encoding)

(* and values read were written *)
#pub prfun fdec_fenc {kinds:layout}{contents:fvals}{octets:bytes}{octet_count:nat} (LEN(octets, octet_count), FDEC(kinds, octets, fd_ok(contents))): FENC(kinds, contents, octets)

prfun _fdec_fenc {kinds:layout}{contents:fvals}{octets:bytes}{octet_count:nat} .<octet_count>. (whole: LEN(octets, octet_count), decoding: FDEC(kinds, octets, fd_ok(contents))): FENC(kinds, contents, octets) =
  case+ decoding of
  | FDEC_nil() => FENC_nil()
  | FDEC_i32_ok(take_proof, number_proof, sub) => let
      prval (append_proof, _) = take_append(take_proof)
      prval rest_len = take_rest_len(take_proof, whole)
    in FENC_i32(number_proof, _fdec_fenc(rest_len, sub), append_proof) end
  | FDEC_str_ok(take_proof, sub) => let
      prval (append_proof, length_proof) = take_append(take_proof)
      prval LEN_cons(tail_len) = whole
      prval rest_len = take_rest_len(take_proof, tail_len)
    in FENC_str(STRB_mk(length_proof), _fdec_fenc(rest_len, sub), APPEND_cons(append_proof)) end

primplement fdec_fenc {kinds}{contents}{octets}{octet_count} (whole, decoding) = _fdec_fenc(whole, decoding)


(* A 32-bit number at run time, with its four bytes, least significant
   first, and the proof that they are its. The number comes from an int
   that is one (a machine's int has 32 bits); that the int is the number
   the bytes make is the one thing the types do not prove here: it is
   checked by running every int (tests/int32) *)
#pub datavtype int32v(int) =
  | {value:int}{octets:bytes} I32V(value) of (LES(4, value, octets) | int value, blist(octets, 4))

(* number taken apart by 256: number = 256 quotient + remainder *)
fn _split {number:int} (number: int number): [quotient,remainder:int | number == 256*quotient + remainder; 0 <= remainder; remainder < 256] (int quotient, int remainder) = let
  val truncated = number / 256
  val remainder = number - 256 * truncated
in
  if remainder >= 0 then (truncated, remainder) else (truncated - 1, remainder + 256)
end

(* A number made of an int: that same number, or, when it is not one of 32 bits, none *)
#pub datavtype int32_made(int) =
  | {given:int} I32_made(given) of int32v(given)
  | {given:int} I32_unrepresentable(given) of ()

#pub fun int32_make {given:int} (given: int given): int32_made(given)

implement int32_make {given} (given) = let
  val (after_first, first_byte) = _split(given)
  val (after_second, second_byte) = _split(after_first)
  val (after_third, third_byte) = _split(after_second)
  val (after_fourth, fourth_byte) = _split(after_third)
in
  if after_fourth = 0 then
    (if fourth_byte < 128 then
       I32_made(I32V(LES_cons(LES_cons(LES_cons(LES_last()))) | given, blist_cons(first_byte, blist_cons(second_byte, blist_cons(third_byte, blist_cons(fourth_byte, blist_nil()))))))
     else I32_unrepresentable())
  else if after_fourth = ~1 then
    (if fourth_byte >= 128 then
       I32_made(I32V(LES_cons(LES_cons(LES_cons(LES_last_neg()))) | given, blist_cons(first_byte, blist_cons(second_byte, blist_cons(third_byte, blist_cons(fourth_byte, blist_nil()))))))
     else I32_unrepresentable())
  else I32_unrepresentable()
end

(* The number made of four bytes read, with the proof *)
#pub fun int32_of_bytes {octets:bytes} (four: blist(octets, 4)): [value:int] (LES(4, value, octets) | int32v(value))

implement int32_of_bytes {octets} (four) =
  case+ four of
  | ~blist_cons(first_byte, ~blist_cons(second_byte, ~blist_cons(third_byte, ~blist_cons(fourth_byte, ~blist_nil())))) =>
    if fourth_byte < 128 then let
      prval number = LES_cons(LES_cons(LES_cons(LES_last())))
    in (number | I32V(number | first_byte + 256 * (second_byte + 256 * (third_byte + 256 * fourth_byte)), blist_cons(first_byte, blist_cons(second_byte, blist_cons(third_byte, blist_cons(fourth_byte, blist_nil())))))) end
    else let
      prval number = LES_cons(LES_cons(LES_cons(LES_last_neg())))
    in (number | I32V(number | first_byte + 256 * (second_byte + 256 * (third_byte + 256 * (fourth_byte - 256))), blist_cons(first_byte, blist_cons(second_byte, blist_cons(third_byte, blist_cons(fourth_byte, blist_nil())))))) end

#pub fun int32_zero (): int32v(0)

implement int32_zero () =
  I32V(LES_cons(LES_cons(LES_cons(LES_last()))) | 0, blist_cons(0, blist_cons(0, blist_cons(0, blist_cons(0, blist_nil())))))

#pub fun int32_value {value:int} (number: !int32v(value)): int value

implement int32_value {value} (number) =
  case+ number of I32V(_ | value, _) => value

#pub fun int32_bytes {value:int} (number: !int32v(value)): [octets:bytes] (LES(4, value, octets) | blist(octets, 4))

implement int32_bytes {value} (number) =
  case+ number of I32V(proof | _, four) => (proof | blist_copy(four))

#pub fun int32_copy {value:int} (number: !int32v(value)): int32v(value)

implement int32_copy {value} (number) =
  case+ number of I32V(proof | value, four) => I32V(proof | value, blist_copy(four))

#pub fun int32_free {value:int} (number: int32v(value)): void

implement int32_free {value} (number) =
  case+ number of ~I32V(_ | _, four) => blist_free(four)

(* The kinds of the fields, at run time, k of them *)
#pub datavtype layoutv(layout, int) =
  | LYV_nil(lo_nil(), 0)
  | {kinds:layout}{field_count:nat} LYV_i32(lo_i32(kinds), field_count+1) of layoutv(kinds, field_count)
  | {kinds:layout}{field_count:nat} LYV_str(lo_str(kinds), field_count+1) of layoutv(kinds, field_count)

(* Values, at run time *)
#pub datavtype fvalsv(layout, fvals, int) =
  | FVV_nil(lo_nil(), fv_nil(), 0)
  | {value:int}{kinds:layout}{contents:fvals}{field_count:nat}
    FVV_i32(lo_i32(kinds), fv_i32(value, contents), field_count+1) of (int32v(value), fvalsv(kinds, contents, field_count))
  | {len:nat | len < 256}{text:bytes}{kinds:layout}{contents:fvals}{field_count:nat}
    FVV_str(lo_str(kinds), fv_str(text, contents), field_count+1) of (blist(text, len), fvalsv(kinds, contents, field_count))

#pub fun layoutv_free {kinds:layout}{field_count:nat} (layout: layoutv(kinds, field_count)): void

implement layoutv_free {kinds}{field_count} (layout) = let
  fun free_kinds {kinds:layout}{field_count:nat} .<field_count>. (layout: layoutv(kinds, field_count)): void =
    case+ layout of
    | ~LYV_nil() => ()
    | ~LYV_i32(rest) => free_kinds(rest)
    | ~LYV_str(rest) => free_kinds(rest)
in free_kinds(layout) end

#pub fun layoutv_copy {kinds:layout}{field_count:nat} (layout: !layoutv(kinds, field_count)): layoutv(kinds, field_count)

implement layoutv_copy {kinds}{field_count} (layout) = let
  fun copy_kinds {kinds:layout}{field_count:nat} .<field_count>. (layout: !layoutv(kinds, field_count)): layoutv(kinds, field_count) =
    case+ layout of
    | LYV_nil() => LYV_nil()
    | LYV_i32(rest) => LYV_i32(copy_kinds(rest))
    | LYV_str(rest) => LYV_str(copy_kinds(rest))
in copy_kinds(layout) end

#pub fun fvalsv_free {kinds:layout}{contents:fvals}{field_count:nat} (values: fvalsv(kinds, contents, field_count)): void

implement fvalsv_free {kinds}{contents}{field_count} (values) = let
  fun free_values {kinds:layout}{contents:fvals}{field_count:nat} .<field_count>. (values: fvalsv(kinds, contents, field_count)): void =
    case+ values of
    | ~FVV_nil() => ()
    | ~FVV_i32(number, rest) => let val () = int32_free(number) in free_values(rest) end
    | ~FVV_str(text, rest) => let val () = blist_free(text) in free_values(rest) end
in free_values(values) end

#pub fun fvalsv_copy {kinds:layout}{contents:fvals}{field_count:nat} (values: !fvalsv(kinds, contents, field_count)): fvalsv(kinds, contents, field_count)

implement fvalsv_copy {kinds}{contents}{field_count} (values) = let
  fun copy_values {kinds:layout}{contents:fvals}{field_count:nat} .<field_count>. (values: !fvalsv(kinds, contents, field_count)): fvalsv(kinds, contents, field_count) =
    case+ values of
    | FVV_nil() => FVV_nil()
    | FVV_i32(number, rest) => FVV_i32(int32_copy(number), copy_values(rest))
    | FVV_str(text, rest) => FVV_str(blist_copy(text), copy_values(rest))
in copy_values(values) end

(* The values written, with the proof *)
#pub fun fields_write {kinds:layout}{contents:fvals}{field_count:nat} (values: !fvalsv(kinds, contents, field_count))
  : [out:bytes][out_count:nat | out_count <= 260 * field_count] (FENC(kinds, contents, out) | blist(out, out_count))

implement fields_write {kinds}{contents}{field_count} (values) = let
  fun write_values {kinds:layout}{contents:fvals}{field_count:nat} .<field_count>. (values: !fvalsv(kinds, contents, field_count))
    : [out:bytes][out_count:nat | out_count <= 260 * field_count] (FENC(kinds, contents, out) | blist(out, out_count)) =
    case+ values of
    | FVV_nil() => (FENC_nil() | blist_nil())
    | FVV_i32(stored_number, rest) => let
        val (number | four) = int32_bytes(stored_number)
        val (rest_encoding | rest_octets) = write_values(rest)
        val (append_proof | out) = blist_append(four, rest_octets)
      in (FENC_i32(number, rest_encoding, append_proof) | out) end
    | FVV_str(text, rest) => let
        val (length_proof | len) = blist_len(text)
        val (rest_encoding | rest_octets) = write_values(rest)
        val (append_proof | out) = blist_append(blist_cons(len, blist_copy(text)), rest_octets)
      in (FENC_str(STRB_mk(length_proof), rest_encoding, append_proof) | out) end
in write_values(values) end


(* Values read *)
#pub datavtype fdread(fdres, layout, int) =
  | {kinds:layout}{field_count:nat} FDR_bad(fd_bad(), kinds, field_count)
  | {kinds:layout}{contents:fvals}{field_count:nat} FDR_ok(fd_ok(contents), kinds, field_count) of fvalsv(kinds, contents, field_count)

#pub fun fields_read {kinds:layout}{field_count:nat}{octets:bytes}{octet_count:nat} (layout: !layoutv(kinds, field_count), list: blist(octets, octet_count))
  : [result:fdres] (FDEC(kinds, octets, result) | fdread(result, kinds, field_count))

implement fields_read {kinds}{field_count}{octets}{octet_count} (layout, list) = let
  fun read_values {kinds:layout}{field_count:nat}{octets:bytes}{octet_count:nat} .<field_count>. (layout: !layoutv(kinds, field_count), list: blist(octets, octet_count))
    : [result:fdres] (FDEC(kinds, octets, result) | fdread(result, kinds, field_count)) =
    case+ layout of
    | LYV_nil() =>
      (case+ list of
       | ~blist_nil() => (FDEC_nil() | FDR_ok(FVV_nil()))
       | ~blist_cons(_, rest) => let val () = blist_free(rest) in (FDEC_nil_extra() | FDR_bad()) end)
    | LYV_i32(more) =>
      (case+ blist_take(4, list) of
       | ~TakeShort(short_proof | ) => (FDEC_i32_short(short_proof) | FDR_bad())
       | ~TakeOk(take_proof | four, rest) => let
           val (number | read_number) = int32_of_bytes(four)
           val (sub | rest_result) = read_values(more, rest)
         in
           case+ rest_result of
           | ~FDR_ok(values) => (FDEC_i32_ok(take_proof, number, sub) | FDR_ok(FVV_i32(read_number, values)))
           | ~FDR_bad() => let val () = int32_free(read_number) in (FDEC_i32_bad(take_proof, number, sub) | FDR_bad()) end
         end)
    | LYV_str(more) =>
      (case+ list of
       | ~blist_nil() => (FDEC_str_empty() | FDR_bad())
       | ~blist_cons(len, after_length) =>
         (case+ blist_take(len, after_length) of
          | ~TakeShort(short_proof | ) => (FDEC_str_short(short_proof) | FDR_bad())
          | ~TakeOk(take_proof | text, rest) => let
              val (sub | rest_result) = read_values(more, rest)
            in
              case+ rest_result of
              | ~FDR_ok(values) => (FDEC_str_ok(take_proof, sub) | FDR_ok(FVV_str(text, values)))
              | ~FDR_bad() => let val () = blist_free(text) in (FDEC_str_bad(take_proof, sub) | FDR_bad()) end
            end))
in read_values(layout, list) end

end
