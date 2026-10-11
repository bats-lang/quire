(* language -- a language tag as dc:language and xml:lang write it, made a BCP 47 tag (quire#436).

   Books write the language of their text as "EN-us", "en_US", "eng" (ISO 639-2), "heb", "zh-Hant-TW",
   "iw" (the code Hebrew had before 1989). The tag the reader keeps, and that the reading face, the
   voice, the dictionary and the page's lang attribute go by, is BCP 47's (RFC 5646 §2.1.1): the
   language in lower case, a script of 4 letters with its first capital, a region of 2 letters in
   capitals, the rest in lower case, subtags joined by hyphens. A three-letter code that has a two-letter
   one is that one (eng is en: BCP 47 says to use the shortest, "Suppress-Script" and its relatives
   being for the registry; what comparable software does: Android's Locale, Chrome and ICU all
   canonicalise "eng" to "en"). A tag that is not made of letters, digits, hyphens and underscores is
   not a language. *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

fn _lower (code: int): int =
  if code >= 65 then (if code <= 90 then code + 32 else code) else code

fn _upper (code: int): int =
  if code >= 97 then (if code <= 122 then code - 32 else code) else code

fn _letter (code: int): bool = (code >= 65 && code <= 90) || (code >= 97 && code <= 122)

fn _digit (code: int): bool = code >= 48 && code <= 57

fn _is_three (first: int, second: int, third: int, code: string 3): bool =
  first = char2int0(string_get_at(code, 0)) && second = char2int0(string_get_at(code, 1)) && third = char2int0(string_get_at(code, 2))

fn _pair (first: int, second: int): int = first * 256 + second

(* The two letters of a three-letter code in lower case (as first * 256 + second), or 0 *)
fn _two_letters (first: int, second: int, third: int): int =
  if _is_three(first, second, third, "eng") then _pair(101, 110)
  else if _is_three(first, second, third, "heb") then _pair(104, 101)
  else if _is_three(first, second, third, "fra") then _pair(102, 114)
  else if _is_three(first, second, third, "fre") then _pair(102, 114)
  else if _is_three(first, second, third, "deu") then _pair(100, 101)
  else if _is_three(first, second, third, "ger") then _pair(100, 101)
  else if _is_three(first, second, third, "spa") then _pair(101, 115)
  else if _is_three(first, second, third, "ita") then _pair(105, 116)
  else if _is_three(first, second, third, "por") then _pair(112, 116)
  else if _is_three(first, second, third, "rus") then _pair(114, 117)
  else if _is_three(first, second, third, "jpn") then _pair(106, 97)
  else if _is_three(first, second, third, "zho") then _pair(122, 104)
  else if _is_three(first, second, third, "chi") then _pair(122, 104)
  else if _is_three(first, second, third, "kor") then _pair(107, 111)
  else if _is_three(first, second, third, "ara") then _pair(97, 114)
  else if _is_three(first, second, third, "nld") then _pair(110, 108)
  else if _is_three(first, second, third, "dut") then _pair(110, 108)
  else if _is_three(first, second, third, "pol") then _pair(112, 108)
  else if _is_three(first, second, third, "tur") then _pair(116, 114)
  else if _is_three(first, second, third, "ell") then _pair(101, 108)
  else if _is_three(first, second, third, "gre") then _pair(101, 108)
  else if _is_three(first, second, third, "swe") then _pair(115, 118)
  else if _is_three(first, second, third, "nor") then _pair(110, 111)
  else if _is_three(first, second, third, "dan") then _pair(100, 97)
  else if _is_three(first, second, third, "fin") then _pair(102, 105)
  else if _is_three(first, second, third, "ces") then _pair(99, 115)
  else if _is_three(first, second, third, "cze") then _pair(99, 115)
  else if _is_three(first, second, third, "hun") then _pair(104, 117)
  else if _is_three(first, second, third, "ron") then _pair(114, 111)
  else if _is_three(first, second, third, "rum") then _pair(114, 111)
  else if _is_three(first, second, third, "ukr") then _pair(117, 107)
  else if _is_three(first, second, third, "hin") then _pair(104, 105)
  else if _is_three(first, second, third, "tha") then _pair(116, 104)
  else if _is_three(first, second, third, "vie") then _pair(118, 105)
  else if _is_three(first, second, third, "ind") then _pair(105, 100)
  else if _is_three(first, second, third, "fas") then _pair(102, 97)
  else if _is_three(first, second, third, "per") then _pair(102, 97)
  else if _is_three(first, second, third, "yid") then _pair(121, 105)
  else if _is_three(first, second, third, "lat") then _pair(108, 97)
  else if _is_three(first, second, third, "cat") then _pair(99, 97)
  else if _is_three(first, second, third, "bul") then _pair(98, 103)
  else if _is_three(first, second, third, "hrv") then _pair(104, 114)
  else if _is_three(first, second, third, "srp") then _pair(115, 114)
  else if _is_three(first, second, third, "slk") then _pair(115, 107)
  else if _is_three(first, second, third, "slo") then _pair(115, 107)
  else if _is_three(first, second, third, "slv") then _pair(115, 108)
  else if _is_three(first, second, third, "lit") then _pair(108, 116)
  else if _is_three(first, second, third, "lav") then _pair(108, 118)
  else if _is_three(first, second, third, "est") then _pair(101, 116)
  else if _is_three(first, second, third, "isl") then _pair(105, 115)
  else if _is_three(first, second, third, "ice") then _pair(105, 115)
  else if _is_three(first, second, third, "gle") then _pair(103, 97)
  else if _is_three(first, second, third, "cym") then _pair(99, 121)
  else if _is_three(first, second, third, "wel") then _pair(99, 121)
  else if _is_three(first, second, third, "eus") then _pair(101, 117)
  else if _is_three(first, second, third, "baq") then _pair(101, 117)
  else if _is_three(first, second, third, "glg") then _pair(103, 108)
  else if _is_three(first, second, third, "ben") then _pair(98, 110)
  else if _is_three(first, second, third, "tam") then _pair(116, 97)
  else if _is_three(first, second, third, "urd") then _pair(117, 114)
  else if _is_three(first, second, third, "msa") then _pair(109, 115)
  else if _is_three(first, second, third, "may") then _pair(109, 115)
  else if _is_three(first, second, third, "afr") then _pair(97, 102)
  else if _is_three(first, second, third, "swa") then _pair(115, 119)
  else if _is_three(first, second, third, "hbo") then _pair(104, 101)
  else 0

(* Puts value at out[at] when at is in the tag's 35 bytes: the index after it *)
fn _emit {lo:agz} (out: !$A.arr(byte, lo, 35), at: int, value: int): int = let
  val index = g1ofg0(at)
in
  if index < 0 then at
  else if index >= 35 then at
  else let val () = $A.set<byte>(out, index, $A.int2byte($AR.low_byte(value))) in index + 1 end
end

(* The end of the subtag that begins at i: the first hyphen or underscore, or the end of the tag *)
fun _subtag_end {l:agz}{n:pos}{offset,tag_len:nat | offset + tag_len <= n}{i:nat | i <= tag_len} .<tag_len - i>.
  (data: !$A.borrow(byte, l, n), offset: int offset, tag_len: int tag_len, i: int i): [j:int | i <= j; j <= tag_len] int j =
  if i >= tag_len then i
  else let
    val code = byte2int0($A.read<byte>(data, offset + i))
  in if code = 45 || code = 95 then i else _subtag_end(data, offset, tag_len, i + 1) end

(* Whether the subtag data[offset + i, offset + stop) is made of letters (letters) or digits (not) *)
fun _all_of {l:agz}{n:pos}{offset,tag_len:nat | offset + tag_len <= n}{i,stop:nat | i <= stop; stop <= tag_len} .<stop - i>.
  (data: !$A.borrow(byte, l, n), offset: int offset, tag_len: int tag_len, i: int i, stop: int stop, letters: bool): bool =
  if i >= stop then true
  else let
    val code = byte2int0($A.read<byte>(data, offset + i))
    val ok = (if letters then _letter(code) else _digit(code))
  in if ok then _all_of(data, offset, tag_len, i + 1, stop, letters) else false end

(* The subtag data[offset + i, offset + stop) written to out from at, in the form its place calls for
   (k is its place: 0 the language): the index after it *)
fun _write_subtag {l:agz}{n:pos}{offset,tag_len:nat | offset + tag_len <= n}{i,stop:nat | i <= stop; stop <= tag_len}{lo:agz} .<stop - i>.
  (data: !$A.borrow(byte, l, n), offset: int offset, tag_len: int tag_len, i: int i, stop: int stop,
   out: !$A.arr(byte, lo, 35), at: int, form: int, first: int): int =
  if i >= stop then at
  else let
    val code = byte2int0($A.read<byte>(data, offset + i))
    (* form 0 lower case, 1 the first letter in capitals, 2 all in capitals *)
    val written = (if form = 2 then _upper(code) else if form = 1 then (if i = first then _upper(code) else _lower(code)) else _lower(code)): int
  in _write_subtag(data, offset, tag_len, i + 1, stop, out, _emit(out, at, written), form, first) end

(* The subtags from i on, k being the place of the first *)
fun _subtags {l:agz}{n:pos}{offset,tag_len:nat | offset + tag_len <= n}{i:nat | i <= tag_len}{lo:agz} .<tag_len - i>.
  (data: !$A.borrow(byte, l, n), offset: int offset, tag_len: int tag_len, i: int i,
   out: !$A.arr(byte, lo, 35), at: int, k: int): int = let
  val stop = _subtag_end(data, offset, tag_len, i)
in
  if stop <= i then ~1
  else let
    val sublen = stop - i
    (* the language: a three-letter code that has a two-letter one is that *)
    val language_form = (k = 0)
    val letters = _all_of(data, offset, tag_len, i, stop, true)
    val digits = _all_of(data, offset, tag_len, i, stop, false)
    val shorter = (if language_form then (if sublen = 3 then (if letters then _two_letters(_lower(byte2int0($A.read<byte>(data, offset + i))), _lower(byte2int0($A.read<byte>(data, offset + i + 1))), _lower(byte2int0($A.read<byte>(data, offset + i + 2)))) else 0) else 0) else 0): int
    val after = (if shorter > 0 then _emit(out, _emit(out, at, shorter / 256), shorter - (shorter / 256) * 256)
      else if language_form then _write_subtag(data, offset, tag_len, i, stop, out, at, 0, i)
      else if sublen = 4 then (if letters then _write_subtag(data, offset, tag_len, i, stop, out, at, 1, i) else _write_subtag(data, offset, tag_len, i, stop, out, at, 0, i))
      else if sublen = 2 then (if letters then _write_subtag(data, offset, tag_len, i, stop, out, at, 2, i) else _write_subtag(data, offset, tag_len, i, stop, out, at, 0, i))
      else _write_subtag(data, offset, tag_len, i, stop, out, at, 0, i)): int
  in
    if stop >= tag_len then after
    else _subtags(data, offset, tag_len, stop + 1, out, _emit(out, after, 45), k + 1)
  end
end

(* Whether data[offset + i, offset + tag_len) is made of letters, digits, hyphens and underscores *)
fun _plain {l:agz}{n:pos}{offset,tag_len:nat | offset + tag_len <= n}{i:nat | i <= tag_len} .<tag_len - i>.
  (data: !$A.borrow(byte, l, n), offset: int offset, tag_len: int tag_len, i: int i): bool =
  if i >= tag_len then true
  else let
    val code = byte2int0($A.read<byte>(data, offset + i))
  in if _letter(code) || _digit(code) || code = 45 || code = 95 then _plain(data, offset, tag_len, i + 1) else false end

(* The BCP 47 tag of data[offset, offset + tag_len) in out[0, m): m is 0 when it is not a language tag
   (empty, longer than 35 bytes, with an empty subtag or a character a tag does not have) *)
#pub fn language_normalize {l:agz}{n:pos}{offset,tag_len:nat | offset + tag_len <= n}{lo:agz}
  (data: !$A.borrow(byte, l, n), offset: int offset, tag_len: int tag_len, out: !$A.arr(byte, lo, 35)): [m:nat | m <= 35] int m

implement language_normalize (data, offset, tag_len, out) =
  if tag_len < 1 then 0
  else if tag_len > 35 then 0
  else if ~_plain(data, offset, tag_len, 0) then 0
  else let
    val written = _subtags(data, offset, tag_len, 0, out, 0, 0)
    val m = g1ofg0(written)
  in if m < 0 then 0 else if m > 35 then 0 else m end
