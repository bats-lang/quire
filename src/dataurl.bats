(* dataurl -- an image given as a data URL in a chapter (EPUB 3.3 §3.2:
   data URLs are allowed for the core image types; the suite's
   pub-data-urls_browsing-context and pub-data-urls_top-level-content).
   The page cannot be given a data: URL as a source (the dom package
   refuses one that is not its placeholder, so no script can run from
   one), so the bytes are decoded here, from base64, and given to the
   image as any entry's bytes are. Only `data:image/<type>;base64,` of a
   type a browser draws: png, jpeg, gif, webp and svg+xml. *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
staload "epub_xml.sats"

(* What a src is: not a data URL of an image Quire shows, or one of these *)
#pub datatype data_image = NoDataImage | DataPng | DataJpeg | DataGif | DataWebp | DataSvg

(* The first position in data[from, stop) of the byte target, else stop *)
fun _index_of {l:agz}{n:pos}{from,stop:nat | from <= stop; stop <= n} .<stop - from>.
  (data: !$A.borrow(byte, l, n), from: int from, stop: int stop, target: int): [j:int | from <= j; j <= stop] int j =
  if from >= stop then from
  else if byte2int0($A.read<byte>(data, from)) = target then from
  else _index_of(data, from + 1, stop, target)

(* Which image a src is, when it is a data URL of one given in base64 *)
#pub fn data_url_kind {l:agz}{n:pos}{offset,len:nat | offset + len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, len: int len): data_image

implement data_url_kind (data, offset, len) = let
  var image_prefix = @[char][11]('d', 'a', 't', 'a', ':', 'i', 'm', 'a', 'g', 'e', '/')
  var base64 = @[char][8](';', 'b', 'a', 's', 'e', '6', '4', ',')
  var png = @[char][3]('p', 'n', 'g')
  var jpeg = @[char][4]('j', 'p', 'e', 'g')
  var gif = @[char][3]('g', 'i', 'f')
  var webp = @[char][4]('w', 'e', 'b', 'p')
  var svg = @[char][7]('s', 'v', 'g', '+', 'x', 'm', 'l')
in
  if len < 23 then NoDataImage()
  else if ~xml_name_eq(data, offset, 11, image_prefix, 11) then NoDataImage()
  else let
    val semicolon = _index_of(data, offset + 11, offset + len, 59)
    val subtype_len = semicolon - (offset + 11)
  in
    if semicolon + 8 > offset + len then NoDataImage()
    else if ~xml_name_eq(data, semicolon, 8, base64, 8) then NoDataImage()
    else if xml_name_eq(data, offset + 11, subtype_len, png, 3) then DataPng()
    else if xml_name_eq(data, offset + 11, subtype_len, jpeg, 4) then DataJpeg()
    else if xml_name_eq(data, offset + 11, subtype_len, gif, 3) then DataGif()
    else if xml_name_eq(data, offset + 11, subtype_len, webp, 4) then DataWebp()
    else if xml_name_eq(data, offset + 11, subtype_len, svg, 7) then DataSvg()
    else NoDataImage()
  end
end

(* Where the base64 text of a data URL data[offset, offset + len) starts,
   counted from offset: after the first comma; len when there is none *)
#pub fn data_url_payload {l:agz}{n:pos}{offset,len:nat | offset + len <= n}
  (data: !$A.borrow(byte, l, n), offset: int offset, len: int len): [from:nat | from <= len] int from

implement data_url_payload (data, offset, len) = let
  val comma = _index_of(data, offset, offset + len, 44)
in if comma >= offset + len then len else comma + 1 - offset end

(* The value of a base64 digit, -1 for white space and padding (skipped),
   -2 for anything else *)
fn _digit (code: int): int =
  if code >= 65 && code <= 90 then code - 65
  else if code >= 97 && code <= 122 then code - 97 + 26
  else if code >= 48 && code <= 57 then code - 48 + 52
  else if code = 43 then 62
  else if code = 47 then 63
  else if code = 61 || code = 32 || code = 9 || code = 10 || code = 13 then ~1
  else ~2

(* The weight of the bits that stay, bits (0, 2 or 4) of them *)
fn _weight (bits: int): int = if bits = 4 then 16 else if bits = 2 then 4 else 1

(* data[i, stop) in base64 decoded into out from out[o]: how many bytes
   were made, or -1 when a character is not base64. Each byte made
   takes a character, so it has room (o <= i - start < stop - start <= m) *)
fun _decode {l,lo:agz}{n,m:pos}{start,stop:nat | start <= stop; stop <= n; stop - start <= m}{i:nat | start <= i; i <= stop}{o:nat | o <= i - start} .<stop - i>.
  (data: !$A.borrow(byte, l, n), out: !$A.arr(byte, lo, m), start: int start, stop: int stop, i: int i, o: int o, acc: int, bits: int): [r:int] int r =
  if i >= stop then o
  else let
    val digit = _digit(byte2int0($A.read<byte>(data, i)))
  in
    if digit = ~1 then _decode(data, out, start, stop, i + 1, o, acc, bits)
    else if digit < 0 then ~1
    else let
      val joined = acc * 64 + digit
      val joined_bits = bits + 6
    in
      if joined_bits >= 8 then let
        val kept = joined_bits - 8
        val weight = _weight(kept)
        val made = joined / weight
        val () = $A.set<byte>(out, o, $A.int2byte($AR.low_byte(made)))
      in _decode(data, out, start, stop, i + 1, o + 1, joined - made * weight, kept) end
      else _decode(data, out, start, stop, i + 1, o, joined, joined_bits)
    end
  end

(* data[from, from + count) in base64 decoded into out[0, m): the length, 0 when it
   is not base64 or has no byte *)
#pub fn base64_decode {l,lo:agz}{n,m:pos}{from,count:nat | from + count <= n; count <= m}
  (data: !$A.borrow(byte, l, n), from: int from, count: int count, out: !$A.arr(byte, lo, m)): [decoded:nat | decoded <= m] int decoded

implement base64_decode (data, from, count, out) = let
  val decoded = _decode(data, out, from, from + count, from, 0, 0, 0)
in
  if decoded <= 0 then 0
  else if decoded > count then 0
  else decoded
end
