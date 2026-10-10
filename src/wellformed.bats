(* wellformed -- whether a content document is well formed XML in the two
   ways a reading system must tell (EPUB RS 3.3 §3.1: it is a
   non-validating XML processor, and a document that is not well formed is
   an error): every element is closed by its own end tag, and every
   element name is a name (a prefix and a local part, at most one colon).
   It reads the bytes once and does not parse them: xml-tree, which
   builds the document, accepts both mistakes (quire#419, the suite's
   pub-xml-non-validating_unclosed and pub-xml-names). Entity references
   are not checked: XHTML's named entities are decoded as any text's are. *)

#include "share/atspre_staload.hats"
#use array as A

(* Whether a document is well formed *)
#pub datatype well_formed = WellFormed | Malformed

(* The deepest nesting that is checked: a document deeper than this is
   taken to be malformed *)
#define NESTING 1024

fn _byte {l:agz}{n:pos}{i:nat | i < n} (data: !$A.borrow(byte, l, n), i: int i): int =
  byte2int0($A.read<byte>(data, i))

(* The byte at i, or -1 outside the document *)
fn _byte_or {l:agz}{n:pos}{i:int} (data: !$A.borrow(byte, l, n), n: int n, i: int i): int =
  if i < 0 then ~1
  else if i >= n then ~1
  else _byte(data, i)

fn _blank (code: int): bool = code = 32 || code = 9 || code = 10 || code = 13

(* The searches below start at start, look from i, and answer just past
   what they look for (a position after start), or start when it is not
   there: they are loops, not recursions into the answer *)

(* Just past the first run of a, b, c at or after i *)
fun _find3 {l:agz}{n:pos}{start,i:nat | start <= i; i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, start: int start, i: int i, a: int, b: int, c: int)
  : [j:int | start <= j; j <= n] int j =
  if i + 3 > n then start
  else if _byte(data, i) = a && _byte(data, i + 1) = b && _byte(data, i + 2) = c then i + 3
  else _find3(data, n, start, i + 1, a, b, c)

(* Just past the first run of a, b at or after i *)
fun _find2 {l:agz}{n:pos}{start,i:nat | start <= i; i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, start: int start, i: int i, a: int, b: int)
  : [j:int | start <= j; j <= n] int j =
  if i + 2 > n then start
  else if _byte(data, i) = a && _byte(data, i + 1) = b then i + 2
  else _find2(data, n, start, i + 1, a, b)

(* Just past the first byte a at or after i *)
fun _find1 {l:agz}{n:pos}{start,i:nat | start <= i; i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, start: int start, i: int i, a: int)
  : [j:int | start <= j; j <= n] int j =
  if i >= n then start
  else if _byte(data, i) = a then i + 1
  else _find1(data, n, start, i + 1, a)

(* Just past the end of a <!DOCTYPE ...> that began before i: its '>'
   outside quotes and the brackets of an internal subset *)
fun _doctype_end {l:agz}{n:pos}{start,i:nat | start <= i; i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, start: int start, i: int i, brackets: int, quote: int)
  : [j:int | start <= j; j <= n] int j =
  if i >= n then start
  else let
    val code = _byte(data, i)
    val next_brackets = (if quote <> 0 then brackets else if code = 91 then brackets + 1 else if code = 93 then brackets - 1 else brackets): int
    val next_quote = (if quote <> 0 then (if code = quote then 0 else quote) else if code = 34 || code = 39 then code else 0): int
  in
    if quote = 0 && code = 62 && brackets <= 0 then i + 1
    else _doctype_end(data, n, start, i + 1, next_brackets, next_quote)
  end

(* The first position at or after i where a name ends: a blank, '>' or '/' *)
fun _name_end {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, i: int i): [j:int | i <= j; j <= n] int j =
  if i >= n then i
  else let
    val code = _byte(data, i)
  in if _blank(code) || code = 62 || code = 47 then i else _name_end(data, n, i + 1) end

fun _skip_blanks {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, i: int i): [j:int | i <= j; j <= n] int j =
  if i >= n then i
  else if _blank(_byte(data, i)) then _skip_blanks(data, n, i + 1)
  else i

(* Whether data[position, stop) is, from start, a name: letters, digits,
   '-', '.', '_' and non-ASCII characters, not starting with a digit, '-'
   or '.', and with at most one ':', neither first nor last *)
fun _name_chars {l:agz}{n:pos}{start,position,stop:nat | start <= position; position <= stop; stop <= n} .<stop - position>.
  (data: !$A.borrow(byte, l, n), start: int start, position: int position, stop: int stop, colons: int): bool =
  if position >= stop then true
  else let
    val code = _byte(data, position)
    val letter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code = 95 || code >= 128
    val other = (code >= 48 && code <= 57) || code = 45 || code = 46
  in
    if code = 58 then
      (if colons >= 1 then false
       else if position = start then false
       else if position + 1 >= stop then false
       else _name_chars(data, start, position + 1, stop, colons + 1))
    else if letter then _name_chars(data, start, position + 1, stop, colons)
    else if other then (if position = start then false else _name_chars(data, start, position + 1, stop, colons))
    else false
  end

(* The end of a start tag whose name ended at start: just past its '>';
   start when a '<' comes first or a quote is never closed or the
   document ends *)
fun _tag_end {l:agz}{n:pos}{start,i:nat | start <= i; i <= n} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, start: int start, i: int i)
  : [j:int | start <= j; j <= n] int j =
  if i >= n then start
  else let
    val code = _byte(data, i)
  in
    if code = 34 || code = 39 then let
      val closed = _find1(data, n, i + 1, i + 1, code)
    in if closed <= i + 1 then start else _tag_end(data, n, start, closed) end
    else if code = 62 then i + 1
    else if code = 60 then start
    else _tag_end(data, n, start, i + 1)
  end

(* Whether data[a, a + count) and data[b, b + count) are the same bytes *)
fun _same_name {l:agz}{n:pos}{a,b:int}{count:nat}{k:nat | k <= count} .<count - k>.
  (data: !$A.borrow(byte, l, n), n: int n, a: int a, b: int b, count: int count, k: int k): bool =
  if k >= count then true
  else if _byte_or(data, n, a + k) <> _byte_or(data, n, b + k) then false
  else if _byte_or(data, n, a + k) < 0 then false
  else _same_name(data, n, a, b, count, k + 1)

(* Whether the element names kept in stack[2 * (depth - 1), 2 * depth)
   and data[start, stop) are the same *)
fn _top_is {l:agz}{n:pos}{sl:agz}{depth:pos | depth <= NESTING}{start,stop:nat | start <= stop}
  (data: !$A.borrow(byte, l, n), n: int n, stack: !$A.arr(Int, sl, 2 * NESTING), depth: int depth, start: int start, stop: int stop): bool = let
  val top_start = $A.get<Int>(stack, 2 * (depth - 1))
  val top_len = $A.get<Int>(stack, 2 * (depth - 1) + 1)
in
  if top_len <> stop - start then false
  else _same_name(data, n, top_start, start, stop - start, 0)
end

(* The document data[i, n) from nesting depth: its open elements' names
   are in stack, two numbers each (start, length) *)
fun _scan {l:agz}{n:pos}{sl:agz}{i:nat | i <= n}{depth:nat | depth <= NESTING} .<n - i>.
  (data: !$A.borrow(byte, l, n), n: int n, stack: !$A.arr(Int, sl, 2 * NESTING), i: int i, depth: int depth): well_formed =
  if i >= n then (if depth = 0 then WellFormed() else Malformed())
  else if _byte(data, i) <> 60 then _scan(data, n, stack, i + 1, depth)
  else if i + 1 >= n then Malformed()
  else let
    val next = _byte(data, i + 1)
  in
    if next = 33 then
      (if _byte_or(data, n, i + 2) = 45 && _byte_or(data, n, i + 3) = 45 then let
         val from = (if i + 4 <= n then i + 4 else n): [s:int | i < s; s <= n] int s
         val after = _find3(data, n, from, from, 45, 45, 62)
       in if after <= from then Malformed() else _scan(data, n, stack, after, depth) end
       else if _byte_or(data, n, i + 2) = 91 && _byte_or(data, n, i + 3) = 67 && _byte_or(data, n, i + 8) = 91 then let
         val from = (if i + 9 <= n then i + 9 else n): [s:int | i < s; s <= n] int s
         val after = _find3(data, n, from, from, 93, 93, 62)
       in if after <= from then Malformed() else _scan(data, n, stack, after, depth) end
       else let
         val after = _doctype_end(data, n, i + 2, i + 2, 0, 0)
       in if after <= i + 2 then Malformed() else _scan(data, n, stack, after, depth) end)
    else if next = 63 then let
      val after = _find2(data, n, i + 2, i + 2, 63, 62)
    in if after <= i + 2 then Malformed() else _scan(data, n, stack, after, depth) end
    else if next = 47 then let
      val start = i + 2
      val stop = _name_end(data, n, start)
      val closed = _skip_blanks(data, n, stop)
    in
      if stop = start then Malformed()
      else if ~_name_chars(data, start, start, stop, 0) then Malformed()
      else if closed >= n then Malformed()
      else if _byte(data, closed) <> 62 then Malformed()
      else if depth <= 0 then Malformed()
      else if ~_top_is(data, n, stack, depth, start, stop) then Malformed()
      else _scan(data, n, stack, closed + 1, depth - 1)
    end
    else let
      val start = i + 1
      val stop = _name_end(data, n, start)
    in
      if stop = start then Malformed()
      else if ~_name_chars(data, start, start, stop, 0) then Malformed()
      else let
        val after = _tag_end(data, n, stop, stop)
      in
        if after <= stop then Malformed()
        else if _byte_or(data, n, after - 2) = 47 then _scan(data, n, stack, after, depth)
        else if depth >= NESTING then Malformed()
        else let
          val () = $A.set<Int>(stack, 2 * depth, start)
          val () = $A.set<Int>(stack, 2 * depth + 1, stop - start)
        in _scan(data, n, stack, after, depth + 1) end
      end
    end
  end

(* Whether the n bytes of data are a document whose elements are named as
   names are and closed by their own end tags *)
#pub fn xml_well_formed {l:agz}{n:pos} (data: !$A.borrow(byte, l, n), n: int n): well_formed

implement xml_well_formed (data, n) = let
  val stack = $A.alloc<Int>(2 * NESTING)
  val result = _scan(data, n, stack, 0, 0)
  val () = $A.free<Int>(stack)
in result end
