(* bytes -- the static model of a byte string, and the lists that carry
   one at run time *)

#target wasm begin

#include "share/atspre_staload.hats"

#pub datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

(* APPEND(front, back, joined): joined is front followed by back *)
#pub dataprop APPEND(bytes, bytes, bytes) =
  | {back:bytes} APPEND_nil(bnil(), back, back)
  | {octet:int}{front,back,joined:bytes} APPEND_cons(bcons(octet, front), back, bcons(octet, joined)) of APPEND(front, back, joined)

(* LEN(octets, count): octets has count bytes *)
#pub dataprop LEN(bytes, int) =
  | LEN_nil(bnil(), 0)
  | {octet:int}{octets:bytes}{count:nat} LEN_cons(bcons(octet, octets), count + 1) of LEN(octets, count)

(* Two values are one: equality of byte strings and of numbers is a
   proposition, since the solver reasons only about numbers *)
#pub dataprop EQB(bytes, bytes) =
  | {same:bytes} EQB_refl(same, same)

#pub dataprop EQI(int, int) =
  | {same:int} EQI_refl(same, same)

#pub prfun append_functional {front,back,first_joined,second_joined:bytes}
  (APPEND(front, back, first_joined), APPEND(front, back, second_joined)): EQB(first_joined, second_joined)

primplement append_functional {front,back,first_joined,second_joined} (first_proof, second_proof) =
  case+ first_proof of
  | APPEND_nil() => (case+ second_proof of APPEND_nil() => EQB_refl())
  | APPEND_cons(first_rest_proof) =>
    (case+ second_proof of
     | APPEND_cons(second_rest_proof) =>
       (case+ append_functional(first_rest_proof, second_rest_proof) of EQB_refl() => EQB_refl()))

#pub prfun len_functional {octets:bytes}{count,other_count:nat} (LEN(octets, count), LEN(octets, other_count)): EQI(count, other_count)

primplement len_functional {octets}{count,other_count} (first_proof, second_proof) =
  case+ first_proof of
  | LEN_nil() => (case+ second_proof of LEN_nil() => EQI_refl())
  | LEN_cons(first_rest_proof) =>
    (case+ second_proof of
     | LEN_cons(second_rest_proof) =>
       (case+ len_functional(first_rest_proof, second_rest_proof) of EQI_refl() => EQI_refl()))

(* front followed by back has the lengths added *)
#pub prfun append_len {front,back,joined:bytes}{front_count,back_count:nat}
  (APPEND(front, back, joined), LEN(front, front_count), LEN(back, back_count)): LEN(joined, front_count + back_count)

prfun _append_len {front,back,joined:bytes}{front_count,back_count:nat} .<front_count>.
  (append_proof: APPEND(front, back, joined), front_len: LEN(front, front_count), back_len: LEN(back, back_count))
  : LEN(joined, front_count + back_count) =
  case+ append_proof of
  | APPEND_nil() => (case+ front_len of LEN_nil() => back_len)
  | APPEND_cons(rest_proof) => (case+ front_len of LEN_cons(front_rest_len) => LEN_cons(_append_len(rest_proof, front_rest_len, back_len)))

primplement append_len {front,back,joined}{front_count,back_count} (append_proof, front_len, back_len) =
  _append_len(append_proof, front_len, back_len)

(* LE(width, value, octets): octets are the width bytes of the number
   value, least significant first. Built a byte at a time: a sum with a
   big coefficient is not safe to state, the solver accepted a wrong one *)
#pub dataprop LE(int, int, bytes) =
  | LE_nil(0, 0, bnil())
  | {width,rest_value:nat}{octet:int | 0 <= octet; octet < 256}{octets:bytes}
    LE_cons(width+1, octet + 256*rest_value, bcons(octet, octets)) of LE(width, rest_value, octets)

(* the number determines the bytes *)
#pub prfun le_bytes_functional {width,value:nat}{first_octets,second_octets:bytes}
  (LE(width, value, first_octets), LE(width, value, second_octets)): EQB(first_octets, second_octets)

prfun _le_bytes {width,value:nat}{first_octets,second_octets:bytes} .<width>.
  (first_proof: LE(width, value, first_octets), second_proof: LE(width, value, second_octets)): EQB(first_octets, second_octets) =
  case+ first_proof of
  | LE_nil() => (case+ second_proof of LE_nil() => EQB_refl())
  | LE_cons(first_rest_proof) =>
    (case+ second_proof of
     | LE_cons(second_rest_proof) =>
       (case+ _le_bytes(first_rest_proof, second_rest_proof) of EQB_refl() => EQB_refl()))

primplement le_bytes_functional {width,value}{first_octets,second_octets} (first_proof, second_proof) =
  _le_bytes(first_proof, second_proof)

(* the bytes determine the number *)
#pub prfun le_number_functional {width,first_value,second_value:nat}{octets:bytes}
  (LE(width, first_value, octets), LE(width, second_value, octets)): EQI(first_value, second_value)

prfun _le_number {width,first_value,second_value:nat}{octets:bytes} .<width>.
  (first_proof: LE(width, first_value, octets), second_proof: LE(width, second_value, octets)): EQI(first_value, second_value) =
  case+ first_proof of
  | LE_nil() => (case+ second_proof of LE_nil() => EQI_refl())
  | LE_cons(first_rest_proof) =>
    (case+ second_proof of
     | LE_cons(second_rest_proof) =>
       (case+ _le_number(first_rest_proof, second_rest_proof) of EQI_refl() => EQI_refl()))

primplement le_number_functional {width,first_value,second_value}{octets} (first_proof, second_proof) =
  _le_number(first_proof, second_proof)

(* the width bytes are width long *)
#pub prfun le_len {width,value:nat}{octets:bytes} (LE(width, value, octets)): LEN(octets, width)

prfun _le_len {width,value:nat}{octets:bytes} .<width>. (le_proof: LE(width, value, octets)): LEN(octets, width) =
  case+ le_proof of
  | LE_nil() => LEN_nil()
  | LE_cons(rest_proof) => LEN_cons(_le_len(rest_proof))

primplement le_len {width,value}{octets} (le_proof) = _le_len(le_proof)

(* A byte string at run time: a linear list, its bytes and its length
   in its type *)
#pub datavtype blist(bytes, int) =
  | blist_nil(bnil(), 0)
  | {octet:int | 0 <= octet; octet < 256}{octets:bytes}{count:nat} blist_cons(bcons(octet, octets), count + 1) of (int octet, blist(octets, count))


#pub fun blist_free {octets:bytes}{count:nat} (list: blist(octets, count)): void

implement blist_free {octets}{count} (list) = let
  fun free_all {octets:bytes}{count:nat} .<count>. (list: blist(octets, count)): void =
    case+ list of
    | ~blist_nil() => ()
    | ~blist_cons(_, rest) => free_all(rest)
in free_all(list) end


(* TAKE(count, octets, taken, rest): the first count bytes of octets are taken, and rest is the rest *)
#pub dataprop TAKE(int, bytes, bytes, bytes) =
  | {octets:bytes} TAKE_zero(0, octets, bnil(), octets)
  | {count:nat}{octet:int}{octets,taken,rest:bytes} TAKE_succ(count+1, bcons(octet, octets), bcons(octet, taken), rest) of TAKE(count, octets, taken, rest)

(* SHORT(count, octets): octets has fewer than count bytes *)
#pub dataprop SHORT(int, bytes) =
  | {count:pos} SHORT_nil(count, bnil())
  | {count:nat}{octet:int}{octets:bytes} SHORT_succ(count+1, bcons(octet, octets)) of SHORT(count, octets)

(* Two pairs of byte strings are one pair each *)
#pub dataprop SAME2(bytes, bytes, bytes, bytes) =
  | {first,second:bytes} SAME2_refl(first, second, first, second)

(* taking count bytes is one answer *)
#pub prfun take_functional {count:nat}{octets,first_taken,first_rest,second_taken,second_rest:bytes}
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

(* A proof of a contradiction: it has no constructor that can be made *)
#pub dataprop FALSEP() =
  | {impossible:int | impossible < 0; impossible > 0} FALSEP_mk() of ()

(* In a context that is false, there is a proof of it *)
#pub prfun contradiction {impossible:int | impossible < 0; impossible > 0} (): FALSEP()

primplement contradiction {impossible} () = FALSEP_mk{impossible}()

(* From a contradiction, equal byte strings and equal numbers *)
#pub prfun falsep_eqb {first,second:bytes} (FALSEP()): EQB(first, second)

primplement falsep_eqb {first,second} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

(* octets cannot both have count bytes to take and be short of count *)
#pub prfun take_not_short {count:nat}{octets,taken,rest:bytes} (TAKE(count, octets, taken, rest), SHORT(count, octets)): FALSEP()

prfun _take_not_short {count:nat}{octets,taken,rest:bytes} .<count>.
  (take_proof: TAKE(count, octets, taken, rest), short_proof: SHORT(count, octets)): FALSEP() =
  case+ take_proof of
  | TAKE_zero() => (case+ short_proof of SHORT_nil() =/=> ())
  | TAKE_succ(take_rest_proof) => (case+ short_proof of SHORT_succ(short_rest_proof) => _take_not_short(take_rest_proof, short_rest_proof))

primplement take_not_short {count}{octets,taken,rest} (take_proof, short_proof) = _take_not_short(take_proof, short_proof)

(* what is taken followed by the rest is the whole, and is count long *)
#pub prfun take_append {count:nat}{octets,taken,rest:bytes} (TAKE(count, octets, taken, rest)): (APPEND(taken, rest, octets), LEN(taken, count))

prfun _take_append {count:nat}{octets,taken,rest:bytes} .<count>.
  (take_proof: TAKE(count, octets, taken, rest)): (APPEND(taken, rest, octets), LEN(taken, count)) =
  case+ take_proof of
  | TAKE_zero() => (APPEND_nil(), LEN_nil())
  | TAKE_succ(rest_proof) => let
      prval (append_proof, len_proof) = _take_append(rest_proof)
    in (APPEND_cons(append_proof), LEN_cons(len_proof)) end

primplement take_append {count}{octets,taken,rest} (take_proof) = _take_append(take_proof)

(* and conversely *)
#pub prfun append_take {count:nat}{front,back,joined:bytes} (APPEND(front, back, joined), LEN(front, count)): TAKE(count, joined, front, back)

prfun _append_take {count:nat}{front,back,joined:bytes} .<count>.
  (append_proof: APPEND(front, back, joined), front_len: LEN(front, count)): TAKE(count, joined, front, back) =
  case+ append_proof of
  | APPEND_nil() => (case+ front_len of LEN_nil() => TAKE_zero())
  | APPEND_cons(rest_proof) => (case+ front_len of LEN_cons(front_rest_len) => TAKE_succ(_append_take(rest_proof, front_rest_len)))

primplement append_take {count}{front,back,joined} (append_proof, front_len) = _append_take(append_proof, front_len)


(* append is associative: (first second) third = first (second third) *)
#pub prfun append_assoc {first,second,first_second,third,all:bytes}
  (APPEND(first, second, first_second), APPEND(first_second, third, all))
  : [second_third:bytes] (APPEND(second, third, second_third), APPEND(first, second_third, all))

prfun _append_assoc {first,second,first_second,third,all:bytes} .<first>.
  (first_proof: APPEND(first, second, first_second), second_proof: APPEND(first_second, third, all))
  : [second_third:bytes] (APPEND(second, third, second_third), APPEND(first, second_third, all)) =
  case+ first_proof of
  | APPEND_nil() => (second_proof, APPEND_nil())
  | APPEND_cons(first_rest_proof) => (case+ second_proof of APPEND_cons(second_rest_proof) => let
      prval (second_third_proof, first_all_proof) = _append_assoc(first_rest_proof, second_rest_proof)
    in (second_third_proof, APPEND_cons(first_all_proof)) end)

primplement append_assoc {first,second,first_second,third,all} (first_proof, second_proof) =
  _append_assoc(first_proof, second_proof)

(* A list copied *)
#pub fun blist_copy {octets:bytes}{count:nat} (list: !blist(octets, count)): blist(octets, count)

implement blist_copy {octets}{count} (list) = let
  fun copy_all {octets:bytes}{count:nat} .<count>. (list: !blist(octets, count)): blist(octets, count) =
    case+ list of
    | blist_nil() => blist_nil()
    | blist_cons(octet, rest) => blist_cons(octet, copy_all(rest))
in copy_all(list) end

(* Two lists joined *)
#pub fun blist_append {front,back:bytes}{front_count,back_count:nat} (first: blist(front, front_count), second: blist(back, back_count))
  : [joined:bytes] (APPEND(front, back, joined) | blist(joined, front_count + back_count))

implement blist_append {front,back}{front_count,back_count} (first, second) = let
  fun join_all {front,back:bytes}{front_count,back_count:nat} .<front_count>.
    (first: blist(front, front_count), second: blist(back, back_count))
    : [joined:bytes] (APPEND(front, back, joined) | blist(joined, front_count + back_count)) =
    case+ first of
    | ~blist_nil() => (APPEND_nil() | second)
    | ~blist_cons(octet, rest) => let
        val (append_proof | joined) = join_all(rest, second)
      in (APPEND_cons(append_proof) | blist_cons(octet, joined)) end
in join_all(first, second) end

(* The first count bytes of a list, and the rest *)
#pub datavtype takeres(bytes, int, int) =
  | {octets:bytes}{count,list_count:nat} TakeShort(octets, count, list_count) of (SHORT(count, octets) | )
  | {octets:bytes}{count,list_count:nat}{taken,rest:bytes}{rest_count:nat | rest_count + count == list_count}
    TakeOk(octets, count, list_count) of (TAKE(count, octets, taken, rest) | blist(taken, count), blist(rest, rest_count))

#pub fun blist_take {octets:bytes}{list_count,count:nat} (count: int count, list: blist(octets, list_count)): takeres(octets, count, list_count)

implement blist_take {octets}{list_count,count} (count, list) = let
  fun take_front {octets:bytes}{list_count,count:nat} .<count>.
    (count: int count, list: blist(octets, list_count)): takeres(octets, count, list_count) =
    if count = 0 then TakeOk(TAKE_zero() | blist_nil(), list)
    else
      case+ list of
      | ~blist_nil() => TakeShort(SHORT_nil() | )
      | ~blist_cons(octet, rest) =>
        (case+ take_front(count - 1, rest) of
         | ~TakeShort(short_proof | ) => TakeShort(SHORT_succ(short_proof) | )
         | ~TakeOk(take_proof | taken, remaining) => TakeOk(TAKE_succ(take_proof) | blist_cons(octet, taken), remaining))
in take_front(count, list) end


(* and the other way: first (second third) = (first second) third *)
#pub prfun append_assoc_rev {first,second,third,second_third,all:bytes}
  (APPEND(second, third, second_third), APPEND(first, second_third, all))
  : [first_second:bytes] (APPEND(first, second, first_second), APPEND(first_second, third, all))

prfun _append_assoc_rev {first,second,third,second_third,all:bytes} .<first>.
  (second_proof: APPEND(second, third, second_third), first_proof: APPEND(first, second_third, all))
  : [first_second:bytes] (APPEND(first, second, first_second), APPEND(first_second, third, all)) =
  case+ first_proof of
  | APPEND_nil() => (APPEND_nil(), second_proof)
  | APPEND_cons(first_rest_proof) => let
      prval (first_second_proof, all_proof) = _append_assoc_rev(second_proof, first_rest_proof)
    in (APPEND_cons(first_second_proof), APPEND_cons(all_proof)) end

primplement append_assoc_rev {first,second,third,second_third,all} (second_proof, first_proof) =
  _append_assoc_rev(second_proof, first_proof)


(* A list's length, with its proof *)
#pub fun blist_len {octets:bytes}{count:nat} (list: !blist(octets, count)): (LEN(octets, count) | int count)

implement blist_len {octets}{count} (list) = let
  fun count_all {octets:bytes}{count:nat} .<count>. (list: !blist(octets, count)): (LEN(octets, count) | int count) =
    case+ list of
    | blist_nil() => (LEN_nil() | 0)
    | blist_cons(_, rest) => let
        val (rest_len | rest_count) = count_all(rest)
      in (LEN_cons(rest_len) | rest_count + 1) end
in count_all(list) end


(* what is left after a known front has a known length *)
#pub prfun append_len_rest {front,back,joined:bytes}{front_count,joined_count:nat}
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


(* nothing after a byte string leaves it as it is *)
#pub prfun append_nil {octets:bytes}{count:nat} (LEN(octets, count)): APPEND(octets, bnil(), octets)

prfun _append_nil {octets:bytes}{count:nat} .<count>. (len_proof: LEN(octets, count)): APPEND(octets, bnil(), octets) =
  case+ len_proof of
  | LEN_nil() => APPEND_nil()
  | LEN_cons(rest_len) => APPEND_cons(_append_nil(rest_len))

primplement append_nil {octets}{count} (len_proof) = _append_nil(len_proof)

(* and what is followed by nothing is itself *)
#pub prfun append_nil_eq {front,joined:bytes}{count:nat} (LEN(front, count), APPEND(front, bnil(), joined)): EQB(front, joined)

prfun _append_nil_eq {front,joined:bytes}{count:nat} .<count>.
  (len_proof: LEN(front, count), append_proof: APPEND(front, bnil(), joined)): EQB(front, joined) =
  case+ append_proof of
  | APPEND_nil() => EQB_refl()
  | APPEND_cons(rest_proof) =>
    (case+ len_proof of LEN_cons(rest_len) => (case+ _append_nil_eq(rest_len, rest_proof) of EQB_refl() => EQB_refl()))

primplement append_nil_eq {front,joined}{count} (len_proof, append_proof) = _append_nil_eq(len_proof, append_proof)

end
