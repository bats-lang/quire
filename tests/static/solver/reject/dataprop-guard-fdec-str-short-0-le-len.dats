#include "share/atspre_staload.hats"
(* quire src/fields.bats FDEC, copied: see gen_guards.py.
   False variant: the guard atom `0 <= len` of FDEC_str_short shifted by 1: `0 <= (len) + 1` *)
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

prfn probe_0_le_len {kinds:layout}{len:int | 0 <= (len) + 1; len < 256}{after_length:bytes} (premise1: SHORT(len, after_length)): FDEC(lo_str(kinds), bcons(len, after_length), fd_bad()) = FDEC_str_short{kinds}{len}{after_length}(premise1)
