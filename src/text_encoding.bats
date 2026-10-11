(* text_encoding -- the bytes of a book's text document (a content
   document, the package, the navigation document, an overlay), read as
   UTF-8 whatever they are encoded in (quire#436).

   EPUB 3 requires UTF-8 or UTF-16 (EPUB 3.3 §4.1.1), but EPUB 2 files
   (OPS 2.0.1 allowed any encoding an XML processor reads) and files made
   by hand are in others, and a UTF-8 file may begin with a byte order
   mark. The parsers below this one read UTF-8, so every document comes
   here first and is either left as it is (UTF-8 with no byte order mark,
   by far the most), or made into UTF-8, or refused. The rules, decided by
   what Thorium (Readium: the browser's XML parser), Calibre
   (xml_to_unicode: the byte order mark, then the declaration) and Apple
   Books (WebKit's libxml2) do, and the XML specification (Appendix F):

   - a byte order mark says the encoding (EF BB BF UTF-8, which is dropped;
     FF FE and FE FF UTF-16, which is made UTF-8); so does a document
     that begins with "<" and a null byte, either way round
   - else the XML declaration's encoding="..." names it, by the WHATWG
     Encoding Standard's labels (iso-8859-1 and us-ascii are windows-1252,
     as a browser reads them): UTF-8, or a single-byte encoding Quire has
     the table of (text_tables), or one it has not
   - else UTF-8
   - UTF-8 that is not UTF-8 (a stray byte, a sequence cut short, a
     surrogate or an overlong form) refuses the document: XML says it is a
     fatal error, and a guess at a better encoding is the mojibake this
     avoids
   - a document that says a single-byte encoding but is UTF-8 (valid, with
     non-ASCII characters in it) is read as UTF-8: it is wrong about itself
     and a text that is valid UTF-8 by chance is a text in UTF-8
   - a document of ASCII only is left as it is, whatever it declares
   - an encoding Quire has no table for (Shift_JIS, GBK, ...) refuses a
     document that is not ASCII only *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

staload "text_tables.sats"

(* What a document needs: nothing (it is UTF-8 with no byte order mark), to
   be made into UTF-8, or to be refused *)
#pub datatype text_plan = PlanAsIs | PlanConvert | PlanRefused

(* i as an index in the document: no less than 0 and no more than n *)
fn _clamp {n:pos} (n: int n, i: int): [j:nat | j <= n] int j = let
  val k = g1ofg0(i)
in if k < 0 then 0 else if k > n then n else k end

(* The byte at i, or -1 outside the document *)
fn _byte_or {l:agz}{n:pos}{i:int} (data: !$A.borrow(byte, l, n), n: int n, i: int i): int =
  if i < 0 then ~1
  else if i >= n then ~1
  else byte2int0($A.read<byte>(data, i))

fn _blank (code: int): bool = code = 32 || code = 9 || code = 10 || code = 13

(* Just past the blanks at or after i *)
fun _skip_blank {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, i: int i): [j:int | i <= j; j <= n] int j =
  if i >= n then i
  else if _blank(byte2int0($A.read<byte>(data, i))) then _skip_blank(data, n, i + 1)
  else i

(* Just before the first byte quote at or after i, or n when there is none *)
fun _find_quote {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, i: int i, quote: int): [j:int | i <= j; j <= n] int j =
  if i >= n then i
  else if byte2int0($A.read<byte>(data, i)) = quote then i
  else _find_quote(data, n, i + 1, quote)

(* The encoding named by encoding = "label" after the "encoding" that ends
   at i (UTF-8 when it names none) *)
fn _declared {l:agz}{n:pos}{i:nat | i <= n} (data: !$A.borrow(byte, l, n), n: int n, i: int i): text_source = let
  val equals_at = _skip_blank(data, n, i)
in
  if equals_at >= n then SrcUtf8()
  else if byte2int0($A.read<byte>(data, equals_at)) <> 61 then SrcUtf8()
  else let
    val quote_at = _skip_blank(data, n, equals_at + 1)
  in
    if quote_at >= n then SrcUtf8()
    else let
      val quote = byte2int0($A.read<byte>(data, quote_at))
    in
      if quote <> 34 && quote <> 39 then SrcUtf8()
      else let
        val label_at = quote_at + 1
        val label_end = _find_quote(data, n, label_at, quote)
      in
        if label_end >= n then SrcUtf8()
        else text_source_of_label(data, label_at, label_end - label_at)
      end
    end
  end
end

(* Whether data[i, i + 8) is "encoding" *)
fn _is_encoding {l:agz}{n:pos}{i:nat} (data: !$A.borrow(byte, l, n), n: int n, i: int i): bool =
  _byte_or(data, n, i) = 101 && _byte_or(data, n, i + 1) = 110 && _byte_or(data, n, i + 2) = 99
  && _byte_or(data, n, i + 3) = 111 && _byte_or(data, n, i + 4) = 100 && _byte_or(data, n, i + 5) = 105
  && _byte_or(data, n, i + 6) = 110 && _byte_or(data, n, i + 7) = 103

(* The encoding the XML declaration names, looking from i to the end of the
   declaration ("?>") or 256 bytes, whichever is first *)
fun _declaration {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, i: int i): text_source =
  if i >= n then SrcUtf8()
  else if i > 256 then SrcUtf8()
  else if byte2int0($A.read<byte>(data, i)) = 63 && _byte_or(data, n, i + 1) = 62 then SrcUtf8()
  else if _is_encoding(data, n, i) then
    (if i + 8 <= n then _declared(data, n, i + 8) else SrcUtf8())
  else _declaration(data, n, i + 1)

(* How the document is encoded, and how many bytes at its start are a byte
   order mark *)
fn _detect {l:agz}{n:pos} (data: !$A.borrow(byte, l, n), n: int n): @(text_source, int) = let
  val b0 = _byte_or(data, n, 0)
  val b1 = _byte_or(data, n, 1)
  val b2 = _byte_or(data, n, 2)
in
  if b0 = 239 && b1 = 187 && b2 = 191 then @(SrcUtf8(), 3)
  else if b0 = 255 && b1 = 254 then @(SrcUtf16Le(), 2)
  else if b0 = 254 && b1 = 255 then @(SrcUtf16Be(), 2)
  (* no byte order mark: "<" and a null byte, which no UTF-8 text begins with *)
  else if b0 = 60 && b1 = 0 then @(SrcUtf16Le(), 0)
  else if b0 = 0 && b1 = 60 then @(SrcUtf16Be(), 0)
  else if b0 = 60 && b1 = 63 && b2 = 120 && _byte_or(data, n, 3) = 109 && _byte_or(data, n, 4) = 108 then let
      val declared = _declaration(data, n, _clamp(n, 5))
    in
      (* bytes that are text say UTF-16: they are UTF-8 (or ASCII) that is wrong about itself *)
      case+ declared of
      | SrcUtf16Le() => @(SrcUtf8(), 0)
      | SrcUtf16Be() => @(SrcUtf8(), 0)
      | _ => @(declared, 0)
    end
  else @(SrcUtf8(), 0)
end

(* The next index after i, k further on, no further than n *)
fn _after {n:pos}{i:nat | i < n}{k:pos} (n: int n, i: int i, k: int k): [j:int | i < j; j <= n] int j =
  if i + k >= n then n else i + k

fn _continuation {l:agz}{n:pos}{i:int} (data: !$A.borrow(byte, l, n), n: int n, i: int i, low: int, high: int): bool = let
  val code = _byte_or(data, n, i)
in code >= low && code <= high end

(* Whether data[start, n) is UTF-8: 0 when it is not, 1 when it is ASCII
   only, 2 when it has other characters. found is 1 or 2 so far *)
fun _utf8_scan {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, i: int i, found: int): int =
  if i >= n then found
  else let
    val lead = byte2int0($A.read<byte>(data, i))
  in
    if lead < 128 then _utf8_scan(data, n, i + 1, found)
    else if lead < 194 then 0
    else if lead < 224 then
      (if _continuation(data, n, i + 1, 128, 191) then _utf8_scan(data, n, _after(n, i, 2), 2) else 0)
    else if lead < 240 then
      (if _continuation(data, n, i + 1, (if lead = 224 then 160 else 128), (if lead = 237 then 159 else 191))
          && _continuation(data, n, i + 2, 128, 191)
       then _utf8_scan(data, n, _after(n, i, 3), 2) else 0)
    else if lead < 245 then
      (if _continuation(data, n, i + 1, (if lead = 240 then 144 else 128), (if lead = 244 then 143 else 191))
          && _continuation(data, n, i + 2, 128, 191) && _continuation(data, n, i + 3, 128, 191)
       then _utf8_scan(data, n, _after(n, i, 4), 2) else 0)
    else 0
  end

(* The code point of the UTF-16 unit at i (two bytes, in the order little),
   and the index after the character: a pair of units is one character; a
   unit alone, or half of one, is U+FFFD *)
fn _unit {l:agz}{n:pos}{i:nat | i < n} (data: !$A.borrow(byte, l, n), n: int n, i: int i, little: bool): int = let
  val first = byte2int0($A.read<byte>(data, i))
  val second = _byte_or(data, n, i + 1)
in
  if second < 0 then ~1
  else if little then first + 256 * second
  else 256 * first + second
end

fn _step_16 {l:agz}{n:pos}{i:nat | i < n} (data: !$A.borrow(byte, l, n), n: int n, i: int i, little: bool)
  : [j:int | i < j; j <= n] @(int, int j) = let
  val unit = _unit(data, n, i, little)
in
  if unit < 0 then @(65533, n)
  else if unit >= 55296 && unit < 56320 then let
      val next = (if i + 3 < n then _unit(data, n, i + 2, little) else ~1)
    in
      if next >= 56320 && next < 57344 then @(65536 + (unit - 55296) * 1024 + (next - 56320), _after(n, i, 4))
      else @(65533, _after(n, i, 2))
    end
  else if unit >= 56320 && unit < 57344 then @(65533, _after(n, i, 2))
  else @(unit, _after(n, i, 2))
end

(* The character at i and the index after it, in a source that is not UTF-8 *)
fn _step {l:agz}{n:pos}{i:nat | i < n} (data: !$A.borrow(byte, l, n), n: int n, i: int i, source: text_source)
  : [j:int | i < j; j <= n] @(int, int j) =
  case+ source of
  | SrcUtf16Le() => _step_16(data, n, i, true)
  | SrcUtf16Be() => _step_16(data, n, i, false)
  | _ => let
      val code = byte2int0($A.read<byte>(data, i))
    in if code < 128 then @(code, i + 1) else @(text_table_code(source, code), i + 1) end

fn _utf8_length (code_point: int): int =
  if code_point < 128 then 1 else if code_point < 2048 then 2 else if code_point < 65536 then 3 else 4

(* The bytes of the document from i, in UTF-8 *)
fun _count {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, i: int i, source: text_source, total: int): int =
  if i >= n then total
  else let
    val @(code_point, next) = _step(data, n, i, source)
  in _count(data, n, next, source, total + _utf8_length(code_point)) end

(* Puts byte value at out[at] when it is there: the index after it *)
fn _put {lo:agz}{o:addr}{m:nat} (out: !$A.arrx(byte, lo, m, o), m: int m, at: int, value: int): int = let
  val index = g1ofg0(at)
in
  if index < 0 then at
  else if index >= m then at
  else let val () = $A.set<byte>(out, index, $A.int2byte($AR.low_byte(value))) in index + 1 end
end

fn _put_character {lo:agz}{o:addr}{m:nat} (out: !$A.arrx(byte, lo, m, o), m: int m, at: int, code_point: int): int =
  if code_point < 128 then _put(out, m, at, code_point)
  else if code_point < 2048 then let
      val at = _put(out, m, at, 192 + code_point / 64)
    in _put(out, m, at, 128 + code_point - (code_point / 64) * 64) end
  else if code_point < 65536 then let
      val at = _put(out, m, at, 224 + code_point / 4096)
      val at = _put(out, m, at, 128 + (code_point / 64) - (code_point / 4096) * 64)
    in _put(out, m, at, 128 + code_point - (code_point / 64) * 64) end
  else let
      val at = _put(out, m, at, 240 + code_point / 262144)
      val at = _put(out, m, at, 128 + (code_point / 4096) - (code_point / 262144) * 64)
      val at = _put(out, m, at, 128 + (code_point / 64) - (code_point / 4096) * 64)
    in _put(out, m, at, 128 + code_point - (code_point / 64) * 64) end

fun _fill {l:agz}{n:pos}{i:nat | i <= n}{lo:agz}{o:addr}{m:nat} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, i: int i, source: text_source, out: !$A.arrx(byte, lo, m, o), m: int m, at: int): void =
  if i >= n then ()
  else let
    val @(code_point, next) = _step(data, n, i, source)
  in _fill(data, n, next, source, out, m, _put_character(out, m, at, code_point)) end

fun _copy_from {l:agz}{n:pos}{i:nat | i <= n}{lo:agz}{o:addr}{m:nat} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, i: int i, out: !$A.arrx(byte, lo, m, o), m: int m, at: int): void =
  if i >= n then ()
  else _copy_from(data, n, i + 1, out, m, _put(out, m, at, byte2int0($A.read<byte>(data, i))))

(* What the document needs, and the source and byte order mark it has *)
fn _decide {l:agz}{n:pos} (data: !$A.borrow(byte, l, n), n: int n): @(text_plan, text_source, int) = let
  val @(source, mark) = _detect(data, n)
in
  case+ source of
  | SrcUtf8() =>
    if _utf8_scan(data, n, _clamp(n, mark), 1) = 0 then @(PlanRefused(), source, mark)
    else if mark = 0 then @(PlanAsIs(), source, mark)
    else if n - mark <= 0 then @(PlanRefused(), source, mark)
    else @(PlanConvert(), source, mark)
  | SrcUtf16Le() => if n - mark <= 0 then @(PlanRefused(), source, mark) else @(PlanConvert(), source, mark)
  | SrcUtf16Be() => if n - mark <= 0 then @(PlanRefused(), source, mark) else @(PlanConvert(), source, mark)
  | SrcUnsupported() =>
    (* ASCII only is the same in every encoding that has ASCII *)
    if _utf8_scan(data, n, 0, 1) = 1 then @(PlanAsIs(), source, mark) else @(PlanRefused(), source, mark)
  | _ =>
    (* a single-byte encoding: ASCII only is as it is, and so is UTF-8 that
       says otherwise of itself *)
    if _utf8_scan(data, n, 0, 1) > 0 then @(PlanAsIs(), source, mark) else @(PlanConvert(), source, mark)
end

(* What the document at data[0, n) needs *)
#pub fn text_plan_of {l:agz}{n:pos} (data: !$A.borrow(byte, l, n), n: int n): text_plan

implement text_plan_of (data, n) = let
  val @(plan, _, _) = _decide(data, n)
in plan end

(* The size of the document made into UTF-8 (when text_plan_of says PlanConvert) *)
#pub fn text_converted_size {l:agz}{n:pos} (data: !$A.borrow(byte, l, n), n: int n): [m:nat] int m

implement text_converted_size (data, n) = let
  val @(_, source, mark) = _decide(data, n)
  val size = (case+ source of
    | SrcUtf8() => n - mark
    | _ => _count(data, n, _clamp(n, mark), source, 0)): int
  val m = g1ofg0(size)
in if m >= 0 then m else 0 end

(* The document made into UTF-8, in out[0, m): m is text_converted_size *)
#pub fn text_convert_into {l:agz}{n:pos}{lo:agz}{o:addr}{m:nat}
  (data: !$A.borrow(byte, l, n), n: int n, out: !$A.arrx(byte, lo, m, o), m: int m): void

implement text_convert_into (data, n, out, m) = let
  val @(_, source, mark) = _decide(data, n)
in
  case+ source of
  | SrcUtf8() => _copy_from(data, n, _clamp(n, mark), out, m, 0)
  | _ => _fill(data, n, _clamp(n, mark), source, out, m, 0)
end
