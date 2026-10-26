(* css_size -- the font sizes a book's CSS gives, read as the format alone

   quire#431: the reader's text size means "my reading size" in every book,
   and every other size in the book keeps its proportion to the book's body
   text. What a book's own style sheet says about sizes is read here; what
   the reader does with it (the dominant size of a book, the classes that
   carry the proportions) comes after, in the reader and the style sheet.

   Only `font-size` is read. The decision (quire#431, the decision record):

   * rules are selected by element name, class and id, and by descendant
     chains of those (so `html`, `body`, `div.chapter p`); a selector with
     a combinator (`>`, `+`, `~`), a pseudo-class or -element, an attribute
     test or `*` is not read, the rule is skipped and counted. An at-rule
     (`@media`, `@font-face`, ...) is skipped whole: nothing in it is read;
   * the values are lengths in px, pt, pc, in, cm, mm, em, ex, rem and %,
     the absolute-size keywords (`xx-small` to `xxx-large`), `smaller`,
     `larger`, `inherit`, `unset` and `initial`. `calc()`, `clamp()`,
     `var()`, `vw` and every other unit or word are not read (the element
     keeps the proportion of its parent), as is a negative size or a
     declaration marked `!important` (the publisher's `!important` rules are
     dropped, quire#411). Every other property, `font` the shorthand too,
     is passed over;
   * a declaration block's last valid `font-size` is its size; an invalid
     one after it does not take it back (CSS 2.1 4.1.8);
   * the same value reader reads an inline `style` and the size of
     `<font size>` (HTML's seven sizes, `+n` and `-n` from the third).

   Everything here reads bytes a book holds, so each is checked as it is
   read; a size is kept in thousandths of a pixel, or of its parent's or
   the root's size, at most a thousand pixels (1000000 thousandths) so
   that no product here is out of 32 bits, and a proportion to the book's
   dominant size is a whole number of twentieths from 10 (half) to 60
   (three times), which the type says: a size of 1px or a 400% rule is
   clamped, as Readium CSS clamps, so no text is unreadable and no word
   wider than a page.

   What stays outside the proof: that the units' ratios (a point is 4/3 of
   a pixel, an inch 96) are the CSS ones, and that the reading of a byte
   string is the grammar's, which tests/codec plays. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR

(* ============================================================
   Sizes
   ============================================================ *)

(* The most a size is kept as, in thousandths: a thousand pixels, or a
   thousand times the parent's size *)
#pub stadef SIZE_MAX = 1000000
#define SIZE_MAX 1000000

(* What a size is relative to: none (pixels), the parent element's size
   (em, ex, %, larger, smaller, inherit), or the root's (rem) *)
#pub datatype size_basis = BasisPixels | BasisParent | BasisRoot

#pub typedef size_declared = [thousandths:nat | thousandths <= SIZE_MAX] @{basis= size_basis, thousandths= int thousandths}

(* A size in the end, in thousandths of a pixel, from a pixel to a
   thousand of them *)
#pub typedef size_computed = [thousandths:int | 1000 <= thousandths; thousandths <= SIZE_MAX] int thousandths

(* Why a declaration was not read *)
#pub datatype size_ignored =
  | IgnoredEmpty
  | IgnoredImportant
  | IgnoredFunction
  | IgnoredNegative
  | IgnoredNumber
  | IgnoredUnit
  | IgnoredKeyword

#pub datavtype size_read =
  | SizeFound of (size_declared)
  | SizeNone of ()
  | SizeIgnored of (size_ignored)

#pub fn size_read_free (read: size_read): void

implement size_read_free (read) =
  case+ read of
  | ~SizeFound(_) => ()
  | ~SizeNone() => ()
  | ~SizeIgnored(_) => ()

(* ============================================================
   Bytes
   ============================================================ *)

fn _code {l:agz}{n:pos}{at:nat | at < n} (data: !$A.borrow(byte, l, n), at: int at): [value:nat | value < 256] int value =
  $AR.low_byte(byte2int0($A.read<byte>(data, at)))

fn _lower (code: int): int = if code >= 65 then (if code <= 90 then code + 32 else code) else code

fn _is_letter (code: int): bool = let
  val lower = _lower(code)
in if lower >= 97 then lower <= 122 else false end

fn _is_digit (code: int): bool = if code >= 48 then code <= 57 else false

fn _is_name (code: int): bool =
  if _is_letter(code) then true else if _is_digit(code) then true
  else if code = 45 then true else if code = 95 then true else code >= 128

fn _is_space (code: int): bool = code <= 32

(* v held from 0 to limit *)
fn _bounded {limit:nat} (value: int, limit: int limit): [kept:nat | kept <= limit] int kept = let
  val indexed = g1ofg0(value)
in if indexed < 0 then 0 else if indexed > limit then limit else indexed end

(* Where white space ends from at *)
fun _space_end {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): [end_at:nat | at <= end_at; end_at <= stop] int end_at =
  if at >= stop then at
  else if _is_space(_code(data, at)) then _space_end(data, at + 1, stop)
  else at

(* Where data[start, stop) ends with its white space at the end left out *)
fun _trimmed_end {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n} .<stop - start>.
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): [end_at:nat | start <= end_at; end_at <= stop] int end_at =
  if stop <= start then stop
  else if _is_space(_code(data, stop - 1)) then _trimmed_end(data, start, stop - 1)
  else stop

(* Whether data[at, at + m) is word, letters in either case *)
fun _spelled {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n}{m:nat}{i:nat | i <= m} .<m - i>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, word: string(m), m: int m, i: int i): bool =
  if i >= m then true
  else if at + i >= stop then false
  else if _lower(_code(data, at + i)) = char2int0(word[i]) then _spelled(data, at, stop, word, m, i + 1)
  else false

(* Whether data[start, stop) is exactly word *)
fn _span_is {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}{m:nat}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop, word: string(m), m: int m): bool =
  if stop - start = m then _spelled(data, start, stop, word, m, 0) else false

(* Where the comment that begins at data[at - 2] ends: after its star and
   slash, or at stop (CSS closes a comment at the end of the file) *)
fun _comment_scan {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): [end_at:nat | at <= end_at; end_at <= stop] int end_at =
  if at + 1 >= stop then stop
  else if _code(data, at) = 42 then (if _code(data, at + 1) = 47 then at + 2 else _comment_scan(data, at + 1, stop))
  else _comment_scan(data, at + 1, stop)

(* Where the comment that begins at data[at] ends *)
fn _comment_after {l:agz}{n:pos}{at,stop:nat | at < stop; stop <= n}
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): [end_at:nat | at < end_at; end_at <= stop] int end_at =
  if at + 2 <= stop then _comment_scan(data, at + 2, stop) else stop

(* Whether a comment begins at data[at] *)
fn _comment_at {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): bool =
  if at + 1 >= stop then false
  else if _code(data, at) = 47 then _code(data, at + 1) = 42 else false

(* Where white space, comments and (with semicolons) semicolons end from at *)
fun _blank_end {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, semicolons: bool): [end_at:nat | at <= end_at; end_at <= stop] int end_at =
  if at >= stop then at
  else if _comment_at(data, at, stop) then _blank_end(data, _comment_after(data, at, stop), stop, semicolons)
  else if _is_space(_code(data, at)) then _blank_end(data, at + 1, stop, semicolons)
  else if semicolons then (if _code(data, at) = 59 then _blank_end(data, at + 1, stop, semicolons) else at)
  else at

(* Where a declaration ends from at: at its semicolon, or at stop; a
   semicolon in a string, in parentheses or in a comment is not its end.
   depth is the parentheses open; quote the quote that opened a string, 0
   outside one *)
fun _declaration_scan {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, depth: int, quote: int): [end_at:nat | at <= end_at; end_at <= stop] int end_at =
  if at >= stop then at
  else let
    val code = _code(data, at)
  in
    if quote > 0 then (if code = quote then _declaration_scan(data, at + 1, stop, depth, 0) else _declaration_scan(data, at + 1, stop, depth, quote))
    else if _comment_at(data, at, stop) then _declaration_scan(data, _comment_after(data, at, stop), stop, depth, 0)
    else if code = 34 then _declaration_scan(data, at + 1, stop, depth, 34)
    else if code = 39 then _declaration_scan(data, at + 1, stop, depth, 39)
    else if code = 40 then _declaration_scan(data, at + 1, stop, depth + 1, 0)
    else if code = 41 then _declaration_scan(data, at + 1, stop, (if depth > 0 then depth - 1 else 0), 0)
    else if code = 59 then (if depth > 0 then _declaration_scan(data, at + 1, stop, depth, 0) else at)
    else _declaration_scan(data, at + 1, stop, depth, 0)
  end

(* Where a colon is in data[at, stop), or stop *)
fun _colon {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): [colon_at:nat | at <= colon_at; colon_at <= stop] int colon_at =
  if at >= stop then at
  else if _code(data, at) = 58 then at
  else _colon(data, at + 1, stop)

(* ============================================================
   Numbers and values
   ============================================================ *)

(* The digits of a number's whole part from at, as the most of a thousand
   (the rest is saturated), and where they end *)
fun _whole {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, value: int): @([end_at:nat | at <= end_at; end_at <= stop] int end_at, [whole:nat | whole <= 1000] int whole) =
  if at >= stop then @(at, _bounded(value, 1000))
  else let
    val code = _code(data, at)
  in
    if _is_digit(code) then
      _whole(data, at + 1, stop, (if value > 1000 then 1000 else value * 10 + (code - 48)))
    else @(at, _bounded(value, 1000))
  end

(* The first three digits of a fraction's from at, as thousandths (place is
   the next one's worth: 100, 10, 1, then 0), and where its digits end *)
fun _fraction_digits {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, thousandths: int, place: int)
  : @([end_at:nat | at <= end_at; end_at <= stop] int end_at, [fraction:nat | fraction <= 999] int fraction) =
  if at >= stop then @(at, _bounded(thousandths, 999))
  else let
    val code = _code(data, at)
  in
    if _is_digit(code) then _fraction_digits(data, at + 1, stop, thousandths + (code - 48) * place, place / 10)
    else @(at, _bounded(thousandths, 999))
  end

(* An unsigned number at data[at, stop): where it ends, its value in
   thousandths (a thousand at the most) and whether it had a digit *)
fn _number {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop)
  : @([end_at:nat | at <= end_at; end_at <= stop] int end_at, [value:nat | value <= SIZE_MAX] int value, bool) = let
  val @(whole_end, whole) = _whole(data, at, stop, 0)
  val has_whole = whole_end > at
in
  if whole_end < stop then
    (if _code(data, whole_end) = 46 then let
       val @(fraction_end, fraction) = _fraction_digits(data, whole_end + 1, stop, 0, 100)
       val value = whole * 1000 + fraction
     in @(fraction_end, _bounded(value, SIZE_MAX), (if has_whole then true else fraction_end > whole_end + 1)) end
     else @(whole_end, _bounded(whole * 1000, SIZE_MAX), has_whole))
  else @(whole_end, _bounded(whole * 1000, SIZE_MAX), has_whole)
end

fn _declared (basis: size_basis, thousandths: int): size_declared = let
  val kept = _bounded(thousandths, 1000000)
in @{basis= basis, thousandths= kept} end

fn _found (basis: size_basis, thousandths: int): size_read = SizeFound(_declared(basis, thousandths))

(* A value of a number and a unit, data[unit_at, stop) being the unit *)
fn _unit_size {l:agz}{n:pos}{unit_at,stop:nat | unit_at <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), unit_at: int unit_at, stop: int stop, value: int): size_read =
  if _span_is(data, unit_at, stop, "px", 2) then _found(BasisPixels, value)
  else if _span_is(data, unit_at, stop, "pt", 2) then _found(BasisPixels, value * 4 / 3)
  else if _span_is(data, unit_at, stop, "pc", 2) then _found(BasisPixels, value * 16)
  else if _span_is(data, unit_at, stop, "in", 2) then _found(BasisPixels, value * 96)
  else if _span_is(data, unit_at, stop, "cm", 2) then _found(BasisPixels, value * 378 / 10)
  else if _span_is(data, unit_at, stop, "mm", 2) then _found(BasisPixels, value * 378 / 100)
  else if _span_is(data, unit_at, stop, "em", 2) then _found(BasisParent, value)
  else if _span_is(data, unit_at, stop, "ex", 2) then _found(BasisParent, value / 2)
  else if _span_is(data, unit_at, stop, "rem", 3) then _found(BasisRoot, value)
  else if _span_is(data, unit_at, stop, "%", 1) then _found(BasisParent, value / 100)
  else SizeIgnored(IgnoredUnit())

(* Whether data[start, stop) has an opening parenthesis *)
fun _has_function {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n} .<stop - start>.
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): bool =
  if start >= stop then false
  else if _code(data, start) = 40 then true
  else _has_function(data, start + 1, stop)

(* The size a keyword names, data[start, stop) being a word *)
fn _keyword_size {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): size_read =
  if _span_is(data, start, stop, "xx-small", 8) then _found(BasisPixels, 9000)
  else if _span_is(data, start, stop, "x-small", 7) then _found(BasisPixels, 10000)
  else if _span_is(data, start, stop, "small", 5) then _found(BasisPixels, 13000)
  else if _span_is(data, start, stop, "medium", 6) then _found(BasisPixels, 16000)
  else if _span_is(data, start, stop, "large", 5) then _found(BasisPixels, 18000)
  else if _span_is(data, start, stop, "x-large", 7) then _found(BasisPixels, 24000)
  else if _span_is(data, start, stop, "xx-large", 8) then _found(BasisPixels, 32000)
  else if _span_is(data, start, stop, "xxx-large", 9) then _found(BasisPixels, 48000)
  else if _span_is(data, start, stop, "initial", 7) then _found(BasisPixels, 16000)
  else if _span_is(data, start, stop, "larger", 6) then _found(BasisParent, 1200)
  else if _span_is(data, start, stop, "smaller", 7) then _found(BasisParent, 833)
  else if _span_is(data, start, stop, "inherit", 7) then _found(BasisParent, 1000)
  else if _span_is(data, start, stop, "unset", 5) then _found(BasisParent, 1000)
  else if _has_function(data, start, stop) then SizeIgnored(IgnoredFunction())
  else SizeIgnored(IgnoredKeyword())

(* The size a value gives, data[start, stop) being the value, trimmed *)
fn _value_size {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): size_read =
  if start >= stop then SizeIgnored(IgnoredEmpty())
  else let
    val first = _code(data, start)
  in
    if _is_letter(first) then _keyword_size(data, start, stop)
    else if first = 45 then
      (if _has_function(data, start, stop) then SizeIgnored(IgnoredFunction()) else SizeIgnored(IgnoredNegative()))
    else let
      val number_at = (if first = 43 then start + 1 else start): [at:nat | start <= at; at <= start + 1] int at
    in
      if number_at >= stop then SizeIgnored(IgnoredNumber())
      else let
        val @(number_end, value, has_digit) = _number(data, number_at, stop)
      in
        if has_digit then _unit_size(data, number_end, stop, value)
        else if _has_function(data, start, stop) then SizeIgnored(IgnoredFunction())
        else SizeIgnored(IgnoredNumber())
      end
    end
  end

(* The size one font-size value gives, data[start, stop) being everything
   after the colon: marked !important, it is not read *)
fn _declared_value {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): size_read = let
  val value_start = _blank_end(data, start, stop, false)
  val value_stop = _trimmed_end(data, value_start, stop)
in
  if value_stop - value_start >= 9 then
    (if _spelled(data, value_stop - 9, value_stop, "important", 9, 0) then let
       val before = _trimmed_end(data, value_start, value_stop - 9)
     in
       if before > value_start then
         (if _code(data, before - 1) = 33 then SizeIgnored(IgnoredImportant()) else _value_size(data, value_start, value_stop))
       else _value_size(data, value_start, value_stop)
     end
     else _value_size(data, value_start, value_stop))
  else _value_size(data, value_start, value_stop)
end

(* A value alone, data[start, stop): "1.6rem", "9pt", "62.5%", "large" *)
#pub fun value_size_read {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): size_read

implement value_size_read (data, start, stop) = _declared_value(data, start, stop)

(* The size of one declaration, data[start, stop) being "name: value" with
   no semicolon: the value when the name is font-size, else none *)
fn _declaration_size {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): size_read = let
  val colon_at = _colon(data, start, stop)
  val name_stop = _trimmed_end(data, start, colon_at)
in
  if colon_at >= stop then SizeNone()
  else if _span_is(data, start, name_stop, "font-size", 9) then _declared_value(data, colon_at + 1, stop)
  else SizeNone()
end

(* The size so far and the size after it: a valid one replaces the one
   before it, an invalid one does not take a valid one back *)
fn _merge (before: size_read, after: size_read): size_read =
  case+ after of
  | ~SizeNone() => before
  | ~SizeFound(declared) => let val () = size_read_free(before) in SizeFound(declared) end
  | ~SizeIgnored(reason) =>
    (case+ before of
     | ~SizeFound(kept) => SizeFound(kept)
     | ~SizeNone() => SizeIgnored(reason)
     | ~SizeIgnored(_) => SizeIgnored(reason))

fun _declarations {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, so_far: size_read): size_read = let
  val [started:int] start = _blank_end(data, at, stop, true)
in
  if start >= stop then so_far
  else let
    val scanned = _declaration_scan(data, start, stop, 0, 0)
    val declaration_stop = (if scanned > start then scanned else start + 1): [e:nat | started < e; e <= stop] int e
    val next = _declaration_size(data, start, declaration_stop)
  in _declarations(data, declaration_stop, stop, _merge(so_far, next)) end
end

(* The font-size of a declaration block, data[start, stop) being what is
   between the braces (or an inline style attribute's value) *)
#pub fun declarations_size_read {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): size_read

implement declarations_size_read (data, start, stop) = _declarations(data, start, stop, SizeNone())

(* The size of <font size="..."> (HTML 15.3.1's seven sizes), data[start,
   stop) being the attribute's value: 1 to 7, or +n and -n from 3 *)
#pub fun font_size_attribute_read {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): size_read

implement font_size_attribute_read (data, start, stop) = let
  val [value_start_at:int] value_start = _space_end(data, start, stop)
  val value_stop = _trimmed_end(data, value_start, stop)
  fn pixels_of_step (step: int): size_read =
    if step <= 1 then _found(BasisPixels, 10000)
    else if step = 2 then _found(BasisPixels, 13000)
    else if step = 3 then _found(BasisPixels, 16000)
    else if step = 4 then _found(BasisPixels, 18000)
    else if step = 5 then _found(BasisPixels, 24000)
    else if step = 6 then _found(BasisPixels, 32000)
    else _found(BasisPixels, 48000)
in
  if value_stop <= value_start then SizeIgnored(IgnoredEmpty())
  else let
    val first = _code(data, value_start)
    val sign = (if first = 43 then 1 else if first = 45 then ~1 else 0): [sign:int | ~1 <= sign; sign <= 1] int sign
    val digits_at = (if sign = 0 then value_start else value_start + 1): [d:nat | value_start_at <= d; d <= value_start_at + 1] int d
  in
    if digits_at >= value_stop then SizeIgnored(IgnoredNumber())
    else let
      val @(digits_end, whole) = _whole(data, digits_at, value_stop, 0)
    in
      if digits_end = digits_at then SizeIgnored(IgnoredNumber())
      else if digits_end < value_stop then SizeIgnored(IgnoredUnit())
      else if sign = 0 then pixels_of_step(whole)
      else pixels_of_step(3 + sign * whole)
    end
  end
end

(* ============================================================
   Resolving a size, and the proportion to the dominant size
   ============================================================ *)

(* parent times factor thousandths, in thousandths of a pixel, with the
   factor held to a hundred times and the result to a pixel to a thousand *)
fn _scaled (base: int, factor: int): size_computed = let
  val kept_factor = _bounded(factor, 100000)
  val kept_base = _bounded(base, SIZE_MAX)
  val product = (kept_base / 1000) * kept_factor + ((kept_base % 1000) * kept_factor) / 1000
in 1000 + _bounded(product - 1000, SIZE_MAX - 1000) end

(* The computed size of an element declared this size, its parent's being
   parent and the root's root *)
#pub fun size_resolve (declared: size_declared, parent: size_computed, root: size_computed): size_computed

implement size_resolve (declared, parent, root) =
  case+ declared.basis of
  | BasisPixels() => _scaled(declared.thousandths, 1000)
  | BasisParent() => _scaled(parent, declared.thousandths)
  | BasisRoot() => _scaled(root, declared.thousandths)

(* The proportion of a size to the dominant size of its book, in twentieths:
   from half (10) to three times (60), whatever the size is *)
#pub typedef proportion = [twentieths:int | 10 <= twentieths; twentieths <= 60] int twentieths

#pub fun proportion_of (size: size_computed, dominant: size_computed): proportion

implement proportion_of (size, dominant) = 10 + _bounded((20 * size + dominant / 2) / dominant - 10, 50)

(* ============================================================
   Alignment of table elements (keyword: publisher alignment, #868)
   ============================================================ *)

(* The alignment a publisher gave a element of a table, by text-align or by
   justify-items (keyword: publisher alignment): the keywords that do not
   depend on the direction of the text, and for justify-items start and end,
   which a math cell sets left to right whatever the book's direction *)
#pub datatype align_value = AlignNone | AlignLeft | AlignRight | AlignCenter

(* The alignment one value gives: a keyword alone (marked !important it is
   not read, as a size is not); start and end only where logical is true *)
fn _align_of_value {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop, logical: bool): align_value = let
  val value_start = _blank_end(data, start, stop, false)
  val value_stop = _trimmed_end(data, value_start, stop)
  val left = (if _span_is(data, value_start, value_stop, "left", 4) then true
    else if logical then _span_is(data, value_start, value_stop, "start", 5) else false)
  val right = (if _span_is(data, value_start, value_stop, "right", 5) then true
    else if logical then _span_is(data, value_start, value_stop, "end", 3) else false)
in
  if left then AlignLeft()
  else if right then AlignRight()
  else if _span_is(data, value_start, value_stop, "center", 6) then AlignCenter()
  else AlignNone()
end

(* The alignment of one declaration, data[start, stop) being "name: value"
   with no semicolon: the value when the name is text-align or justify-items *)
fn _declaration_align {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): align_value = let
  val colon_at = _colon(data, start, stop)
  val name_stop = _trimmed_end(data, start, colon_at)
in
  if colon_at >= stop then AlignNone()
  else if _span_is(data, start, name_stop, "text-align", 10) then _align_of_value(data, colon_at + 1, stop, false)
  else if _span_is(data, start, name_stop, "justify-items", 13) then _align_of_value(data, colon_at + 1, stop, true)
  else AlignNone()
end

(* The alignment so far and the one after it: a valid one replaces the one
   before it *)
fn _align_merge (before: align_value, after: align_value): align_value =
  case+ after of
  | AlignNone() => before
  | AlignLeft() => AlignLeft()
  | AlignRight() => AlignRight()
  | AlignCenter() => AlignCenter()

fun _align_declarations {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, so_far: align_value): align_value = let
  val [started:int] start = _blank_end(data, at, stop, true)
in
  if start >= stop then so_far
  else let
    val scanned = _declaration_scan(data, start, stop, 0, 0)
    val declaration_stop = (if scanned > start then scanned else start + 1): [e:nat | started < e; e <= stop] int e
    val next = _declaration_align(data, start, declaration_stop)
  in _align_declarations(data, declaration_stop, stop, _align_merge(so_far, next)) end
end

(* The alignment of a declaration block, data[start, stop) being what is
   between the braces (or an inline style attribute's value) *)
#pub fun declarations_align_read {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): align_value

implement declarations_align_read (data, start, stop) = _align_declarations(data, start, stop, AlignNone())

(* ============================================================
   Selectors
   ============================================================ *)

(* Why a selector is not read *)
#pub datatype selector_unsupported =
  | UnsupportedEmpty
  | UnsupportedCombinator
  | UnsupportedPseudo
  | UnsupportedAttribute
  | UnsupportedUniversal
  | UnsupportedCharacter
  | UnsupportedTooDeep

(* The most compounds (`div.chapter p` has two) a chain has *)
#pub stadef SELECTOR_DEPTH_MAX = 8
#define SELECTOR_DEPTH_MAX 8

(* The specificity of a selector as ids times 10000, classes times 100 and
   names, each held to 99 *)
#pub typedef specificity = [value:nat | value < 1000000] int value

#pub datavtype selector_read =
  | SelectorSupported of (specificity)
  | SelectorUnsupported of (selector_unsupported)

#pub fn selector_read_free (read: selector_read): void

implement selector_read_free (read) =
  case+ read of
  | ~SelectorSupported(_) => ()
  | ~SelectorUnsupported(_) => ()

fn _cap (count: int): [kept:nat | kept <= 99] int kept = _bounded(count, 99)

fn _specificity (ids: int, classes: int, names: int): specificity = _cap(ids) * 10000 + _cap(classes) * 100 + _cap(names)

(* Where a name's characters end from at *)
fun _name_end {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): [end_at:nat | at <= end_at; end_at <= stop] int end_at =
  if at >= stop then at
  else if _is_name(_code(data, at)) then _name_end(data, at + 1, stop)
  else at

(* The structural pseudo-classes a selector may hold (keyword: publisher
   alignment): the first and last child, and the child by its place *)
#pub datatype pseudo_kind = PseudoFirstChild | PseudoLastChild | PseudoOdd | PseudoEven | PseudoIndex

(* The pseudo-class that begins with its colon at data[at], with where it
   ends and, for PseudoIndex, the place (from 1) *)
#pub datavtype pseudo_read(at:int, stop:int) =
  | PseudoUnsupported(at, stop) of ()
  | {end_at:nat | at < end_at; end_at <= stop} PseudoSupported(at, stop) of (pseudo_kind, int end_at, int)

#pub fun pseudo_read {l:agz}{n:pos}{at,stop:nat | at < stop; stop <= n}
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): pseudo_read(at, stop)

implement pseudo_read (data, at, stop) = let
  val name_stop = _name_end(data, at + 1, stop)
in
  if _span_is(data, at + 1, name_stop, "first-child", 11) then PseudoSupported(PseudoFirstChild(), name_stop, 0)
  else if _span_is(data, at + 1, name_stop, "last-child", 10) then PseudoSupported(PseudoLastChild(), name_stop, 0)
  else if _span_is(data, at + 1, name_stop, "nth-child", 9) then
    (if name_stop >= stop then PseudoUnsupported()
     else if _code(data, name_stop) <> 40 then PseudoUnsupported()
     else let
       val argument_start = name_stop + 1
       val argument_stop = _name_end(data, argument_start, stop)
     in
       if argument_stop >= stop then PseudoUnsupported()
       else if _code(data, argument_stop) <> 41 then PseudoUnsupported()
       else if _span_is(data, argument_start, argument_stop, "odd", 3) then PseudoSupported(PseudoOdd(), argument_stop + 1, 0)
       else if _span_is(data, argument_start, argument_stop, "even", 4) then PseudoSupported(PseudoEven(), argument_stop + 1, 0)
       else let
         val @(digits_end, place) = _whole(data, argument_start, argument_stop, 0)
       in
         if digits_end = argument_stop then
           (if argument_stop > argument_start then (if place >= 1 then PseudoSupported(PseudoIndex(), argument_stop + 1, place) else PseudoUnsupported())
            else PseudoUnsupported())
         else PseudoUnsupported()
       end
     end)
  else PseudoUnsupported()
end

(* A selector, data[at, stop) being what remains of it: fresh when a
   compound begins here, depth the compounds begun *)
fun _selector {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at, 1>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, fresh: bool, depth: int, ids: int, classes: int, names: int): selector_read =
  if at >= stop then SelectorSupported(_specificity(ids, classes, names))
  else let
    val code = _code(data, at)
  in
    if _is_space(code) then let
      val next = _space_end(data, at + 1, stop)
    in
      if next >= stop then SelectorSupported(_specificity(ids, classes, names))
      else _selector(data, next, stop, true, depth, ids, classes, names)
    end
    else if fresh then
      (if depth >= SELECTOR_DEPTH_MAX then SelectorUnsupported(UnsupportedTooDeep())
       else _compound_part(data, at, stop, code, depth + 1, ids, classes, names))
    else _compound_part(data, at, stop, code, depth, ids, classes, names)
  end

(* The part of a compound that begins with code at data[at] *)
and _compound_part {l:agz}{n:pos}{at,stop:nat | at < stop; stop <= n} .<stop - at, 0>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, code: int, depth: int, ids: int, classes: int, names: int): selector_read =
  if code = 35 then let
    val name_stop = _name_end(data, at + 1, stop)
  in
    if name_stop > at + 1 then _selector(data, name_stop, stop, false, depth, ids + 1, classes, names)
    else SelectorUnsupported(UnsupportedCharacter())
  end
  else if code = 46 then let
    val name_stop = _name_end(data, at + 1, stop)
  in
    if name_stop > at + 1 then _selector(data, name_stop, stop, false, depth, ids, classes + 1, names)
    else SelectorUnsupported(UnsupportedCharacter())
  end
  else if code = 58 then
    (case+ pseudo_read(data, at, stop) of
     | ~PseudoUnsupported() => SelectorUnsupported(UnsupportedPseudo())
     | ~PseudoSupported(_, end_at, _) => _selector(data, end_at, stop, false, depth, ids, classes + 1, names))
  else if code = 91 then SelectorUnsupported(UnsupportedAttribute())
  else if code = 42 then SelectorUnsupported(UnsupportedUniversal())
  else if code = 62 then SelectorUnsupported(UnsupportedCombinator())
  else if code = 43 then SelectorUnsupported(UnsupportedCombinator())
  else if code = 126 then SelectorUnsupported(UnsupportedCombinator())
  else if _is_name(code) then let
    val name_stop = _name_end(data, at, stop)
  in
    if name_stop > at then _selector(data, name_stop, stop, false, depth, ids, classes, names + 1)
    else SelectorUnsupported(UnsupportedCharacter())
  end
  else SelectorUnsupported(UnsupportedCharacter())

(* The specificity of a selector, data[start, stop) being it, or why it is
   not read *)
#pub fun selector_specificity_read {l:agz}{n:pos}{start,stop:nat | start <= stop; stop <= n}
  (data: !$A.borrow(byte, l, n), start: int start, stop: int stop): selector_read

implement selector_specificity_read (data, start, stop) = let
  val selector_start = _space_end(data, start, stop)
  val selector_stop = _trimmed_end(data, selector_start, stop)
in
  if selector_stop <= selector_start then SelectorUnsupported(UnsupportedEmpty())
  else _selector(data, selector_start, selector_stop, true, 0, 0, 0, 0)
end

(* ============================================================
   Style sheets
   ============================================================ *)

(* The most rules a style sheet gives; the rest are not read *)
#pub stadef RULES_MAX = 4096
#define RULES_MAX 4096

(* One rule of a sheet of sheet_len bytes: where its selector is in the
   sheet (a selector without a comma), its specificity, and its place
   among the rules (their order in the sheet) *)
#pub typedef css_rule(sheet_len:int) = [at,len:nat | at + len <= sheet_len][value:nat | value < 1000000][order:nat | order < RULES_MAX]
  @{selector_at= int at, selector_len= int len, specificity= int value, order= int order}

(* The rules of a sheet that give a size, in the order of the sheet, each
   with its size *)
#pub datavtype css_rules(sheet_len:int, count:int) =
  | RulesNil(sheet_len, 0) of ()
  | {count:nat} RulesCons(sheet_len, count + 1) of (css_rule(sheet_len), size_declared, css_rules(sheet_len, count))

#pub fun css_rules_free {sheet_len:int}{count:nat} (rules: css_rules(sheet_len, count)): void

implement css_rules_free {sheet_len}{count} (rules) = let
  fun walk {count:nat} .<count>. (rules: css_rules(sheet_len, count)): void =
    case+ rules of
    | ~RulesNil() => ()
    | ~RulesCons(_, _, rest) => walk(rest)
in walk(rules) end

(* Whether the sheet was read to its end, or RULES_MAX rules were given and
   there were more *)
#pub datatype sheet_end = SheetComplete | SheetCutShort

#pub datavtype sheet_read(sheet_len:int) =
  | {count:nat} SheetRead(sheet_len) of (sheet_end, int, css_rules(sheet_len, count))

#pub fun sheet_read_free {sheet_len:int} (read: sheet_read(sheet_len)): void

implement sheet_read_free (read) =
  case+ read of
  | ~SheetRead(_, _, rules) => css_rules_free(rules)

#pub fun css_rules_count {sheet_len:int}{count:nat} (rules: !css_rules(sheet_len, count)): int count

implement css_rules_count {sheet_len}{count} (rules) = let
  fun walk {count:nat} .<count>. (rules: !css_rules(sheet_len, count)): int count =
    case+ rules of
    | RulesNil() => 0
    | RulesCons(_, _, rest) => 1 + walk(rest)
in walk(rules) end

fun _reverse {sheet_len:int}{a,b:nat} .<a>.
  (source: css_rules(sheet_len, a), onto: css_rules(sheet_len, b)): css_rules(sheet_len, a + b) =
  case+ source of
  | ~RulesNil() => onto
  | ~RulesCons(rule, size, rest) => _reverse(rest, RulesCons(rule, size, onto))

(* What has been gathered: the rules given so far (last first), the
   rules not read (those with a selector that is not, and at-rules), and
   how many more the sheet may give *)
datavtype gathered(sheet_len:int) =
  | {count:nat} Gathered(sheet_len) of (int, int, css_rules(sheet_len, count))

(* Where the end of a comma-free selector is in data[at, stop): its comma *)
fun _comma {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): [comma_at:nat | at <= comma_at; comma_at <= stop] int comma_at =
  if at >= stop then at
  else if _code(data, at) = 44 then at
  else _comma(data, at + 1, stop)

(* One selector of a block, read as read says, with size: a rule added
   to what is gathered, or one more not read *)
fn _selector_gathered {n:pos}{count:nat}{at,len:nat | at + len <= n}
  (read: selector_read, budget: int, skipped: int, rules: css_rules(n, count), selector_at: int at, selector_len: int len, size: size_declared): gathered(n) =
  case+ read of
  | ~SelectorUnsupported(_) => Gathered(budget, skipped + 1, rules)
  | ~SelectorSupported(weight) =>
    if budget <= 0 then Gathered(~1, skipped + 1, rules)
    else let
      val order = _bounded(RULES_MAX - budget, RULES_MAX - 1)
      val rule = @{selector_at= selector_at, selector_len= selector_len, specificity= weight, order= order}: css_rule(n)
    in Gathered(budget - 1, skipped, RulesCons(rule, size, rules)) end

(* The selectors of data[at, stop), a comma-separated list, each with
   size, added to what is gathered *)
fun _selectors {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, size: size_declared, so_far: gathered(n)): gathered(n) = let
  val selector_stop = _comma(data, at, stop)
  val selector_start = _space_end(data, at, selector_stop)
  val selector_end = _trimmed_end(data, selector_start, selector_stop)
  val read = selector_specificity_read(data, at, selector_stop)
  val ~Gathered(budget, skipped, rules) = so_far
  val gathered = _selector_gathered(read, budget, skipped, rules, selector_start, selector_end - selector_start, size)
in
  if selector_stop < stop then _selectors(data, selector_stop + 1, stop, size, gathered)
  else gathered
end

(* Where the block that begins at data[at - 1] ends: at its closing brace,
   or at stop; braces in strings and comments do not count, nor do the
   ones nested *)
fun _block_end {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, depth: int, quote: int): [end_at:nat | at <= end_at; end_at <= stop] int end_at =
  if at >= stop then at
  else let
    val code = _code(data, at)
  in
    if quote > 0 then (if code = quote then _block_end(data, at + 1, stop, depth, 0) else _block_end(data, at + 1, stop, depth, quote))
    else if _comment_at(data, at, stop) then _block_end(data, _comment_after(data, at, stop), stop, depth, 0)
    else if code = 34 then _block_end(data, at + 1, stop, depth, 34)
    else if code = 39 then _block_end(data, at + 1, stop, depth, 39)
    else if code = 123 then _block_end(data, at + 1, stop, depth + 1, 0)
    else if code = 125 then (if depth > 0 then _block_end(data, at + 1, stop, depth - 1, 0) else at)
    else _block_end(data, at + 1, stop, depth, 0)
  end

(* Where an opening brace is from at, or a semicolon (an at-rule without a
   block ends there), or stop *)
fun _prelude_end {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, quote: int): [end_at:nat | at <= end_at; end_at <= stop] int end_at =
  if at >= stop then at
  else let
    val code = _code(data, at)
  in
    if quote > 0 then (if code = quote then _prelude_end(data, at + 1, stop, 0) else _prelude_end(data, at + 1, stop, quote))
    else if code = 34 then _prelude_end(data, at + 1, stop, 34)
    else if code = 39 then _prelude_end(data, at + 1, stop, 39)
    else if code = 123 then at
    else if code = 59 then at
    else _prelude_end(data, at + 1, stop, 0)
  end

(* The sheet read to its end: what is gathered, with extra more rules not read *)
fn _finished {n:pos} (end_of: sheet_end, extra: int, so_far: gathered(n)): sheet_read(n) = let
  val ~Gathered(budget, skipped, rules) = so_far
  val the_end = (if budget < 0 then SheetCutShort() else end_of)
in SheetRead(the_end, skipped + extra, _reverse(rules, RulesNil())) end

(* One more rule not read *)
fn _skipped {n:pos} (so_far: gathered(n)): gathered(n) = let
  val ~Gathered(budget, skipped, rules) = so_far
in Gathered(budget, skipped + 1, rules) end

fun _sheet {l:agz}{n:pos}{at:nat | at <= n} .<n - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int n, so_far: gathered(n)): sheet_read(n) = let
  val start = _blank_end(data, at, stop, true)
in
  if start >= stop then _finished(SheetComplete(), 0, so_far)
  else let
    val [prelude_end:int] prelude_stop = _prelude_end(data, start, stop, 0)
  in
    if prelude_stop >= stop then _finished(SheetComplete(), 1, so_far)
    else if _code(data, prelude_stop) = 59 then _sheet(data, prelude_stop + 1, stop, _skipped(so_far))
    else let
      val block_stop = _block_end(data, prelude_stop + 1, stop, 0, 0)
      val after = (if block_stop < stop then block_stop + 1 else stop): [after:nat | prelude_end < after; after <= n] int after
    in
      if _code(data, start) = 64 then _sheet(data, after, stop, _skipped(so_far))
      else
        (case+ declarations_size_read(data, prelude_stop + 1, block_stop) of
         | ~SizeFound(size) => _sheet(data, after, stop, _selectors(data, start, prelude_stop, size, so_far))
         | ~SizeNone() => _sheet(data, after, stop, so_far)
         | ~SizeIgnored(_) => _sheet(data, after, stop, _skipped(so_far)))
    end
  end
end

(* The rules of a style sheet that give a font-size, data[0, sheet_len)
   being the sheet, and how many more it had that were not read *)
#pub fun sheet_rules_read {l:agz}{n:pos} (data: !$A.borrow(byte, l, n), sheet_len: int n): sheet_read(n)

implement sheet_rules_read (data, sheet_len) = _sheet(data, 0, sheet_len, Gathered(RULES_MAX, 0, RulesNil()))

(* ============================================================
   The rules of a sheet that give a text-align (keyword: publisher alignment)
   ============================================================ *)

(* The rules of a sheet that give a text-align, in the order of the sheet,
   each with its alignment (never AlignNone) *)
#pub datavtype align_rules(sheet_len:int, count:int) =
  | AlignRulesNil(sheet_len, 0) of ()
  | {count:nat} AlignRulesCons(sheet_len, count + 1) of (css_rule(sheet_len), align_value, align_rules(sheet_len, count))

#pub fun align_rules_free {sheet_len:int}{count:nat} (rules: align_rules(sheet_len, count)): void

implement align_rules_free {sheet_len}{count} (rules) = let
  fun walk {count:nat} .<count>. (rules: align_rules(sheet_len, count)): void =
    case+ rules of
    | ~AlignRulesNil() => ()
    | ~AlignRulesCons(_, _, rest) => walk(rest)
in walk(rules) end

fun _align_reversed {sheet_len:int}{a,b:nat} .<a>.
  (source: align_rules(sheet_len, a), onto: align_rules(sheet_len, b)): align_rules(sheet_len, a + b) =
  case+ source of
  | ~AlignRulesNil() => onto
  | ~AlignRulesCons(rule, align, rest) => _align_reversed(rest, AlignRulesCons(rule, align, onto))

(* The alignment rules gathered so far (last first) and how many more the sheet may give *)
datavtype align_gathered(sheet_len:int) =
  | {count:nat} AlignGathered(sheet_len) of (int, align_rules(sheet_len, count))

(* The selectors of data[at, stop), a comma-separated list, each with align, added to what is gathered *)
fun _align_selectors {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, align: align_value, so_far: align_gathered(n)): align_gathered(n) = let
  val selector_stop = _comma(data, at, stop)
  val selector_start = _space_end(data, at, selector_stop)
  val selector_end = _trimmed_end(data, selector_start, selector_stop)
  val read = selector_specificity_read(data, at, selector_stop)
  val ~AlignGathered(budget, rules) = so_far
  val gathered = (case+ read of
    | ~SelectorUnsupported(_) => AlignGathered(budget, rules)
    | ~SelectorSupported(weight) =>
      if budget <= 0 then AlignGathered(budget, rules)
      else let
        val order = _bounded(RULES_MAX - budget, RULES_MAX - 1)
        val rule = @{selector_at= selector_start, selector_len= selector_end - selector_start, specificity= weight, order= order}: css_rule(n)
      in AlignGathered(budget - 1, AlignRulesCons(rule, align, rules)) end): align_gathered(n)
in
  if selector_stop < stop then _align_selectors(data, selector_stop + 1, stop, align, gathered)
  else gathered
end

fun _align_sheet {l:agz}{n:pos}{at:nat | at <= n} .<n - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int n, so_far: align_gathered(n)): align_gathered(n) = let
  val start = _blank_end(data, at, stop, true)
in
  if start >= stop then so_far
  else let
    val [prelude_end:int] prelude_stop = _prelude_end(data, start, stop, 0)
  in
    if prelude_stop >= stop then so_far
    else if _code(data, prelude_stop) = 59 then _align_sheet(data, prelude_stop + 1, stop, so_far)
    else let
      val block_stop = _block_end(data, prelude_stop + 1, stop, 0, 0)
      val after = (if block_stop < stop then block_stop + 1 else stop): [after:nat | prelude_end < after; after <= n] int after
    in
      if _code(data, start) = 64 then _align_sheet(data, after, stop, so_far)
      else
        (case+ declarations_align_read(data, prelude_stop + 1, block_stop) of
         | AlignNone() => _align_sheet(data, after, stop, so_far)
         | AlignLeft() => _align_sheet(data, after, stop, _align_selectors(data, start, prelude_stop, AlignLeft(), so_far))
         | AlignRight() => _align_sheet(data, after, stop, _align_selectors(data, start, prelude_stop, AlignRight(), so_far))
         | AlignCenter() => _align_sheet(data, after, stop, _align_selectors(data, start, prelude_stop, AlignCenter(), so_far)))
    end
  end
end

(* The rules of a style sheet that give a text-align, data[0, sheet_len) being the sheet *)
#pub fun sheet_aligns_read {l:agz}{n:pos} (data: !$A.borrow(byte, l, n), sheet_len: int n): [count:nat] align_rules(n, count)

implement sheet_aligns_read (data, sheet_len) = let
  val ~AlignGathered(_, rules) = _align_sheet(data, 0, sheet_len, AlignGathered(RULES_MAX, AlignRulesNil()))
in _align_reversed(rules, AlignRulesNil()) end

end
