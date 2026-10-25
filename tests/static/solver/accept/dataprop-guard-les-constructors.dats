#include "share/atspre_staload.hats"
(* quire src/fields.bats LES, copied: see gen_guards.py.
   Control: the constructors with a guard, stated with the guards as they are (reject/dataprop-guard-* shift one atom each) *)
datasort bytes =
  | bnil of ()
  | bcons of (int, bytes)

dataprop LES(int, int, bytes) =
  | {low_byte:int | 0 <= low_byte; low_byte < 128} LES_last(1, low_byte, bcons(low_byte, bnil()))
  | {low_byte:int | 128 <= low_byte; low_byte < 256} LES_last_neg(1, low_byte - 256, bcons(low_byte, bnil()))
  | {byte_count:pos}{rest_number:int}{low_byte:int | 0 <= low_byte; low_byte < 256}{octets:bytes}
    LES_cons(byte_count+1, low_byte + 256*rest_number, bcons(low_byte, octets)) of LES(byte_count, rest_number, octets)

prfn control_les_last {low_byte:int | 0 <= low_byte; low_byte < 128} (): LES(1, low_byte, bcons(low_byte, bnil())) = LES_last{low_byte}()
prfn control_les_last_neg {low_byte:int | 128 <= low_byte; low_byte < 256} (): LES(1, low_byte - 256, bcons(low_byte, bnil())) = LES_last_neg{low_byte}()
prfn control_les_cons {byte_count:pos}{rest_number:int}{low_byte:int | 0 <= low_byte; low_byte < 256}{octets:bytes} (premise1: LES(byte_count, rest_number, octets)): LES(byte_count+1, low_byte + 256*rest_number, bcons(low_byte, octets)) = LES_cons{byte_count}{rest_number}{low_byte}{octets}(premise1)
