#include "share/atspre_staload.hats"
(* quire src/fields.bats fdec_functional, _fdec_functional, copied: see gen_lemmas.py.
   False variant: a reading that comes to fd_ok does not come to fd_bad *)
datasort layout =
  | lo_nil of ()
  | lo_i32 of (layout)
  | lo_str of (layout)

datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

datasort fvals =
  | fv_nil of ()
  | fv_i32 of (int, fvals)
  | fv_str of (bytes, fvals)

datasort fdres =
  | fd_ok of (fvals)
  | fd_bad of ()

dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {octet:int}{octets:bytes}{count:nat} LEN_cons(bcons(octet, octets), count + 1) of LEN(octets, count)

dataprop SHORT(int, bytes) =
  | {count:pos} SHORT_nil(count, bnil())
  | {count:nat}{octet:int}{octets:bytes} SHORT_succ(count+1, bcons(octet, octets)) of SHORT(count, octets)

dataprop TAKE(int, bytes, bytes, bytes) =
  | {octets:bytes} TAKE_zero(0, octets, bnil(), octets)
  | {count:nat}{octet:int}{octets,taken,rest:bytes} TAKE_succ(count+1, bcons(octet, octets), bcons(octet, taken), rest) of TAKE(count, octets, taken, rest)

dataprop LES(int, int, bytes) =
  | {low_byte:int | 0 <= low_byte; low_byte < 128} LES_last(1, low_byte, bcons(low_byte, bnil()))
  | {low_byte:int | 128 <= low_byte; low_byte < 256} LES_last_neg(1, low_byte - 256, bcons(low_byte, bnil()))
  | {byte_count:pos}{rest_number:int}{low_byte:int | 0 <= low_byte; low_byte < 256}{octets:bytes}
    LES_cons(byte_count+1, low_byte + 256*rest_number, bcons(low_byte, octets)) of LES(byte_count, rest_number, octets)

dataprop FDEC(layout, bytes, fdres) =
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

dataprop EQFD(fdres, fdres) =
  | {result:fdres} EQFD_refl(result, result)

extern prfun fdec_functional {kinds:layout}{octets:bytes}{octet_count:nat}{left_result,right_result:fdres} (LEN(octets, octet_count), FDEC(kinds, octets, left_result), FDEC(kinds, octets, right_result)): EQFD(left_result, fd_bad())

dataprop FALSEP() =
  | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()

extern prfun falsep_eqfd {left_result,right_result:fdres} (FALSEP()): EQFD(left_result, right_result)

primplement falsep_eqfd {left_result,right_result} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

extern prfun take_not_short {count:nat}{octets,taken,rest:bytes} (TAKE(count, octets, taken, rest), SHORT(count, octets)): FALSEP()

prfun _take_not_short {count:nat}{octets,taken,rest:bytes} .<count>.
  (take_proof: TAKE(count, octets, taken, rest), short_proof: SHORT(count, octets)): FALSEP() =
  case+ take_proof of
  | TAKE_zero() => (case+ short_proof of SHORT_nil() =/=> ())
  | TAKE_succ(take_rest_proof) => (case+ short_proof of SHORT_succ(short_rest_proof) => _take_not_short(take_rest_proof, short_rest_proof))

primplement take_not_short {count}{octets,taken,rest} (take_proof, short_proof) = _take_not_short(take_proof, short_proof)

dataprop SAME2(bytes, bytes, bytes, bytes) =
  | {first,second:bytes} SAME2_refl(first, second, first, second)

extern prfun take_functional {count:nat}{octets,first_taken,first_rest,second_taken,second_rest:bytes}
  (TAKE(count, octets, first_taken, first_rest), TAKE(count, octets, second_taken, second_rest))
  : SAME2(first_taken, first_rest, second_taken, second_rest)

prfun _take_functional {count:nat}{octets,first_taken,first_rest,second_taken,second_rest:bytes} .<count>.
  (first_proof: TAKE(count, octets, first_taken, first_rest), second_proof: TAKE(count, octets, second_taken, second_rest))
  : SAME2(first_taken, first_rest, second_taken, second_rest) =
  case+ first_proof of
  | TAKE_zero() => (case+ second_proof of TAKE_zero() => SAME2_refl())
  | TAKE_succ(first_rest_proof) =>
    (case+ second_proof of
     | TAKE_succ(second_rest_proof) => (case+ _take_functional(first_rest_proof, second_rest_proof) of SAME2_refl() => SAME2_refl()))

primplement take_functional {count}{octets,first_taken,first_rest,second_taken,second_rest} (first_proof, second_proof) =
  _take_functional(first_proof, second_proof)

dataprop EQI(int, int) =
  | {same:int} EQI_refl(same, same)

extern prfun les_number_functional {byte_count:pos}{left_number,right_number:int}{octets:bytes} (LES(byte_count, left_number, octets), LES(byte_count, right_number, octets)): EQI(left_number, right_number)

prfun _les_number {byte_count:pos}{left_number,right_number:int}{octets:bytes} .<byte_count>. (left: LES(byte_count, left_number, octets), right: LES(byte_count, right_number, octets)): EQI(left_number, right_number) =
  case+ left of
  | LES_last() => (case+ right of LES_last() => EQI_refl())
  | LES_last_neg() => (case+ right of LES_last_neg() => EQI_refl())
  | LES_cons(left_tail) =>
    (case+ right of
     | LES_cons(right_tail) =>
       (case+ _les_number(left_tail, right_tail) of EQI_refl() => EQI_refl()))

primplement les_number_functional {byte_count}{left_number,right_number}{octets} (left, right) = _les_number(left, right)

extern prfun take_rest_len {take_count:nat}{octets,taken,remaining:bytes}{octet_count:nat} (TAKE(take_count, octets, taken, remaining), LEN(octets, octet_count)): [rest_count:nat | rest_count + take_count == octet_count] LEN(remaining, rest_count)

dataprop APPEND(bytes, bytes, bytes) =
  | {back:bytes} APPEND_nil(bnil(), back, back)
  | {octet:int}{front,back,joined:bytes} APPEND_cons(bcons(octet, front), back, bcons(octet, joined)) of APPEND(front, back, joined)

extern prfun take_append {count:nat}{octets,taken,rest:bytes} (TAKE(count, octets, taken, rest)): (APPEND(taken, rest, octets), LEN(taken, count))

prfun _take_append {count:nat}{octets,taken,rest:bytes} .<count>.
  (take_proof: TAKE(count, octets, taken, rest)): (APPEND(taken, rest, octets), LEN(taken, count)) =
  case+ take_proof of
  | TAKE_zero() => (APPEND_nil(), LEN_nil())
  | TAKE_succ(rest_proof) => let
      prval (append_proof, len_proof) = _take_append(rest_proof)
    in (APPEND_cons(append_proof), LEN_cons(len_proof)) end

primplement take_append {count}{octets,taken,rest} (take_proof) = _take_append(take_proof)

extern prfun append_len_rest {front,back,joined:bytes}{front_count,joined_count:nat}
  (APPEND(front, back, joined), LEN(front, front_count), LEN(joined, joined_count))
  : [back_count:nat | back_count + front_count == joined_count] LEN(back, back_count)

prfun _append_len_rest {front,back,joined:bytes}{front_count,joined_count:nat} .<front_count>.
  (append_proof: APPEND(front, back, joined), front_len: LEN(front, front_count), joined_len: LEN(joined, joined_count))
  : [back_count:nat | back_count + front_count == joined_count] LEN(back, back_count) =
  case+ append_proof of
  | APPEND_nil() => (case+ front_len of LEN_nil() => joined_len)
  | APPEND_cons(rest_proof) =>
    (case+ front_len of
     | LEN_cons(front_rest_len) =>
       (case+ joined_len of LEN_cons(joined_rest_len) => _append_len_rest(rest_proof, front_rest_len, joined_rest_len)))

primplement append_len_rest {front,back,joined}{front_count,joined_count} (append_proof, front_len, joined_len) =
  _append_len_rest(append_proof, front_len, joined_len)

primplement take_rest_len {take_count}{octets,taken,remaining}{octet_count} (take_proof, whole) = let
  prval (append_proof, front) = take_append(take_proof)
in append_len_rest(append_proof, front, whole) end

prfun _fdec_functional {kinds:layout}{octets:bytes}{octet_count:nat}{left_result,right_result:fdres} .<octet_count>.
  (whole: LEN(octets, octet_count), left: FDEC(kinds, octets, left_result), right: FDEC(kinds, octets, right_result)): EQFD(left_result, fd_bad()) =
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
