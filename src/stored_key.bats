(* stored_key -- the storage key of a book's file, cover or annotations, or
   of a dictionary's files: a letter and 14 hex digits (a book's id as two
   28-bit halves of 7 digits each). It stands alone, with no dependency on
   a module of quire, so that library.bats, which holds the Empty Trash
   dialog's Accepted branch and so deletes a dictionary's files as it
   deletes a book's (quire#628), and dictionary.bats, which names those
   files, can both use it without staloading each other. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

fn _hex_digit {value:nat | value < 16} (value: int value): [digit:nat | digit < 256] int digit =
  if value < 10 then 48 + value else 87 + value

(* The 7 hex digits of half (its low 28 bits) at buf[offset, offset + 7) *)
fn _put_seven_hex {l:agz}{owner:addr}{n:nat}{offset:nat | offset + 7 <= n}
  (buf: !$A.arrx(byte, l, n, owner), offset: int offset, half: int): void = let
  fn digit_at {i:nat | i < 7} (half: int, i: int i): [digit:nat | digit < 256] int digit =
    _hex_digit($AR.band_g1($AR.low_byte($AR.bsr_int_int(half, 4 * (6 - i))), 15))
  val () = $A.write_byte(buf, offset, digit_at(half, 0))
  val () = $A.write_byte(buf, offset + 1, digit_at(half, 1))
  val () = $A.write_byte(buf, offset + 2, digit_at(half, 2))
  val () = $A.write_byte(buf, offset + 3, digit_at(half, 3))
  val () = $A.write_byte(buf, offset + 4, digit_at(half, 4))
  val () = $A.write_byte(buf, offset + 5, digit_at(half, 5))
in $A.write_byte(buf, offset + 6, digit_at(half, 6)) end

(* The storage key of a book's file ('b'), cover ('c') or annotations
   ('a'): the letter and the book's 14 hex digits *)
#pub fn lib_key {letter:nat | letter < 256} (letter: int letter, id_high: int, id_low: int): [l:agz] $A.arr(byte, l, 15)

implement lib_key (letter, id_high, id_low) = let
  val key = $A.alloc<byte>(15)
  val () = $A.write_byte(key, 0, letter)
  val () = _put_seven_hex(key, 1, id_high)
  val () = _put_seven_hex(key, 8, id_low)
in key end

end (* #target wasm *)
