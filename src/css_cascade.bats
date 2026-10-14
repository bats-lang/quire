(* css_cascade -- the size of the text of a chapter, by the cascade, and the
   size most of a book's text is set in

   quire#431, stage 2. src/css_size.bats reads what a book's CSS says about
   font sizes; here the rules are matched against a chapter's elements,
   the declaration that wins is chosen, the size is inherited down the
   tree, and the characters of each size are counted, so that the size
   most of a book's text has (the dominant size, as Calibre's base font
   size is the most common one in the document) can be told. Nothing here
   reaches the page: the reader keeps the number (stage 3 uses it).

   What is matched is what css_size reads: a rule's selector is a chain
   of compounds (an element name, classes and ids) separated by white
   space, so an element matches when its own compound does and each
   earlier compound matches an ancestor, the nearest first (which is
   enough for descendant combinators alone). An element name is matched
   exactly, as in an XML document (an EPUB's content documents are XHTML,
   served as XML), a class as one of the words of the class attribute,
   an id exactly.

   The cascade, for the size of one element: its inline `style`, else the
   rule of the highest specificity (the later one at the same
   specificity), else `<font size>`, which is a presentational hint and so
   below every rule (CSS 2.1 6.4.1, HTML 15.3.1); else the parent's size.
   The browser's own sizes (an h1 at 2em, small at 0.83em) are not counted:
   this is what the publisher declared, because the reader's stylesheet
   gives the headings their scale and only a size the publisher declared
   is put in proportion (stage 3). The root element's size is the html
   element's, which `rem` follows; html itself and everything outside it
   start from 16px, the initial size.

   The text counted is each non-white-space character, in the size of the
   element it is in (a UTF-8 continuation byte is not a character); the
   subtrees of head, style, script, title, rt and rp are not counted. The
   tally holds at most TALLY_MAX distinct sizes, each rounded to a quarter
   of a pixel: the characters of a new size past that are not counted.

   The style sheets of a chapter are joined into one sheet by the caller
   (the `<link>` sheets first, then the `<style>` texts, each in the
   document's order), so one rule order serves them all; the spans of the
   `<style>` texts and the hrefs of the `<link>` elements to read are
   found here. A sheet that ends inside a comment or a block takes the
   sheets after it with it (they are joined); a sheet that does that is
   rare, and what is lost is a size, never a page. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use xml-tree as X

staload "css_size.sats"

(* ============================================================
   Bytes
   ============================================================ *)

fn _code {l:agz}{n:pos}{at:nat | at < n} (data: !$A.borrow(byte, l, n), at: int at): [value:nat | value < 256] int value =
  $AR.low_byte(byte2int0($A.read<byte>(data, at)))

fn _is_space (code: int): bool = code <= 32

fn _is_name (code: int): bool =
  if code >= 97 then (if code <= 122 then true else code >= 128)
  else if code >= 65 then (if code <= 90 then true else code = 95)
  else if code >= 48 then code <= 57
  else code = 45

(* a size from 1 px to the most *)
fn _as_size (value: int): size_computed = let
  val indexed = g1ofg0(value)
in if indexed < 1000 then 1000 else if indexed > 1000000 then 1000000 else indexed end

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

(* Where the characters that are not white space end, from at *)
fun _word_end {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): [end_at:nat | at <= end_at; end_at <= stop] int end_at =
  if at >= stop then at
  else if _is_space(_code(data, at)) then at
  else _word_end(data, at + 1, stop)

(* Where a name's characters end, from at *)
fun _name_end {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop): [end_at:nat | at <= end_at; end_at <= stop] int end_at =
  if at >= stop then at
  else if _is_name(_code(data, at)) then _name_end(data, at + 1, stop)
  else at

(* Whether data[at, at + len) is word, to the letter *)
fun _word_at {l:agz}{n:pos}{at,len:nat | at + len <= n}{m:nat}{i:nat | i <= m} .<m - i>.
  (data: !$A.borrow(byte, l, n), at: int at, len: int len, word: string(m), m: int m, i: int i): bool =
  if i >= m then true
  else if i >= len then false
  else if _code(data, at + i) = char2int0(word[i]) then _word_at(data, at, len, word, m, i + 1)
  else false

fn _is_word {l:agz}{n:pos}{at,len:nat | at + len <= n}{m:nat}
  (data: !$A.borrow(byte, l, n), at: int at, len: int len, word: string(m), m: int m): bool =
  if len = m then _word_at(data, at, len, word, m, 0) else false

(* Whether x[a, a + len) and y[b, b + len) hold the same bytes, from k on *)
fun _same {l1:agz}{n1:pos}{l2:agz}{n2:pos}{a,b,len:nat}{k:nat | k <= len; a + len <= n1; b + len <= n2} .<len - k>.
  (x: !$A.borrow(byte, l1, n1), a: int a, y: !$A.borrow(byte, l2, n2), b: int b, len: int len, k: int k): bool =
  if k >= len then true
  else if _code(x, a + k) = _code(y, b + k) then _same(x, a, y, b, len, k + 1)
  else false

(* Whether the words data[at, stop) (separated by white space) hold the
   token y[b, b + token_len) *)
fun _has_token {l1:agz}{n1:pos}{l2:agz}{n2:pos}{at,stop,b,token_len:nat | at <= stop; stop <= n1; b + token_len <= n2} .<stop - at>.
  (data: !$A.borrow(byte, l1, n1), at: int at, stop: int stop, y: !$A.borrow(byte, l2, n2), b: int b, token_len: int token_len): bool = let
  val start = _space_end(data, at, stop)
in
  if start >= stop then false
  else let
    val word_stop = _word_end(data, start + 1, stop)
  in
    if word_stop - start = token_len then
      (if _same(data, start, y, b, token_len, 0) then true
       else _has_token(data, word_stop, stop, y, b, token_len))
    else _has_token(data, word_stop, stop, y, b, token_len)
  end
end

(* Whether the words data[at, stop) hold word *)
fun _has_word {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n}{m:nat} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, word: string(m), m: int m): bool = let
  val start = _space_end(data, at, stop)
in
  if start >= stop then false
  else let
    val word_stop = _word_end(data, start + 1, stop)
  in
    if _is_word(data, start, word_stop - start, word, m) then true
    else _has_word(data, word_stop, stop, word, m)
  end
end

(* ============================================================
   Attributes and the facts of an element
   ============================================================ *)

(* The value of the attribute named word, as where it is and its length;
   (0, 0) when there is none *)
fun _attr_find {l:agz}{n:pos}{count:nat}{m:nat} .<count>.
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, count), word: string(m), m: int m)
  : [at,len:nat | at + len <= n] @(int at, int len) =
  case+ attrs of
  | $X.xml_attrs_cons(name_at, name_len, value_at, value_len, rest) =>
    if _is_word(data, name_at, name_len, word, m) then @(value_at, value_len)
    else _attr_find(data, rest, word, m)
  | $X.xml_attrs_nil() => @(0, 0)

(* What a selector can ask of an element: where its name, its class
   attribute and its id attribute are in the document of n bytes *)
#pub typedef element_facts(n:int) = [name_at,name_len,class_at,class_len,id_at,id_len:nat |
  name_at + name_len <= n; class_at + class_len <= n; id_at + id_len <= n]
  @(int name_at, int name_len, int class_at, int class_len, int id_at, int id_len)

fn _facts_of {l:agz}{n:pos}{name_at,name_len:nat | name_at + name_len <= n}{count:nat}
  (data: !$A.borrow(byte, l, n), name_at: int name_at, name_len: int name_len, attrs: !$X.xml_attr_list(n, count)): element_facts(n) = let
  val @(class_at, class_len) = _attr_find(data, attrs, "class", 5)
  val @(id_at, id_len) = _attr_find(data, attrs, "id", 2)
in @(name_at, name_len, class_at, class_len, id_at, id_len) end

(* The elements above the one being looked at, the nearest first, depth of them *)
datavtype ancestors(n:int, depth:int) =
  | AncestorsNil(n, 0) of ()
  | {depth:nat} AncestorsCons(n, depth + 1) of (element_facts(n), ancestors(n, depth))

(* ============================================================
   Matching a selector
   ============================================================ *)

(* Whether the compound sheet[at, stop) (names, .classes and #ids with
   nothing between them) holds for an element of these facts *)
fun _compound_matches {ls:agz}{ns:pos}{ld:agz}{nd:pos}{at,stop:nat | at <= stop; stop <= ns} .<stop - at>.
  (sheet: !$A.borrow(byte, ls, ns), at: int at, stop: int stop, data: !$A.borrow(byte, ld, nd), facts: element_facts(nd)): bool =
  if at >= stop then true
  else let
    val code = _code(sheet, at)
    val @(name_at, name_len, class_at, class_len, id_at, id_len) = facts
  in
    if code = 46 then let
      val name_stop = _name_end(sheet, at + 1, stop)
    in
      if name_stop <= at + 1 then false
      else if _has_token(data, class_at, class_at + class_len, sheet, at + 1, name_stop - at - 1)
      then _compound_matches(sheet, name_stop, stop, data, facts)
      else false
    end
    else if code = 35 then let
      val name_stop = _name_end(sheet, at + 1, stop)
    in
      if name_stop <= at + 1 then false
      else if name_stop - at - 1 = id_len then
        (if _same(sheet, at + 1, data, id_at, id_len, 0) then _compound_matches(sheet, name_stop, stop, data, facts) else false)
      else false
    end
    else let
      val name_stop = _name_end(sheet, at, stop)
    in
      if name_stop <= at then false
      else if name_stop - at = name_len then
        (if _same(sheet, at, data, name_at, name_len, 0) then _compound_matches(sheet, name_stop, stop, data, facts) else false)
      else false
    end
  end

(* Where the last compound of sheet[at, stop) begins *)
fun _compound_start {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (sheet: !$A.borrow(byte, l, n), at: int at, stop: int stop): [start:nat | at <= start; start <= stop] int start =
  if stop <= at then stop
  else if _is_space(_code(sheet, stop - 1)) then stop
  else _compound_start(sheet, at, stop - 1)

(* Whether the compounds of sheet[at, stop), the last matched already,
   are held by the ancestors, each by one above the one before it *)
fun _match_up {ls:agz}{ns:pos}{ld:agz}{nd:pos}{at,stop:nat | at <= stop; stop <= ns}{depth:nat} .<depth>.
  (sheet: !$A.borrow(byte, ls, ns), at: int at, stop: int stop, data: !$A.borrow(byte, ld, nd), chain: !ancestors(nd, depth)): bool =
  if stop <= at then true
  else let
    val start = _compound_start(sheet, at, stop)
    val before = _trimmed_end(sheet, at, start)
  in
    case+ chain of
    | AncestorsNil() => false
    | AncestorsCons(facts, rest) =>
      if _compound_matches(sheet, start, stop, data, facts) then _match_up(sheet, at, before, data, rest)
      else _match_up(sheet, at, stop, data, rest)
  end

(* Whether the selector sheet[at, at + len) selects an element *)
fn _selector_matches {ls:agz}{ns:pos}{ld:agz}{nd:pos}{at,len:nat | at + len <= ns}{depth:nat}
  (sheet: !$A.borrow(byte, ls, ns), at: int at, len: int len, data: !$A.borrow(byte, ld, nd), facts: element_facts(nd), chain: !ancestors(nd, depth)): bool = let
  val stop = at + len
  val start = _compound_start(sheet, at, stop)
in
  if _compound_matches(sheet, start, stop, data, facts) then _match_up(sheet, at, _trimmed_end(sheet, at, start), data, chain)
  else false
end

(* ============================================================
   The rule that wins
   ============================================================ *)

typedef best_rule = @{found= bool, specificity= int, order= int, size= size_declared}

fn _beats (specificity: int, order: int, best: best_rule): bool =
  if ~(best.found) then true
  else if specificity > best.specificity then true
  else if specificity < best.specificity then false
  else order >= best.order

fun _best_rule {ls:agz}{ns:pos}{ld:agz}{nd:pos}{count:nat}{depth:nat} .<count>.
  (sheet: !$A.borrow(byte, ls, ns), rules: !css_rules(ns, count), data: !$A.borrow(byte, ld, nd),
   facts: element_facts(nd), chain: !ancestors(nd, depth), best: best_rule): best_rule =
  case+ rules of
  | RulesNil() => best
  | RulesCons(rule, size, rest) => let
      val @{selector_at= selector_at, selector_len= selector_len, specificity= specificity, order= order} = rule
      val wins = (if _beats(specificity, order, best) then _selector_matches(sheet, selector_at, selector_len, data, facts, chain) else false)
    in
      if wins then _best_rule(sheet, rest, data, facts, chain, @{found= true, specificity= specificity, order= order, size= size})
      else _best_rule(sheet, rest, data, facts, chain, best)
    end

(* ============================================================
   The tally: how many characters each size has
   ============================================================ *)

#pub stadef TALLY_MAX = 64
#define TALLY_MAX 64

(* Sizes (rounded to a quarter of a pixel, in thousandths) and the
   characters set in each *)
#pub datavtype size_tally(count:int) =
  | TallyNil(0) of ()
  | {count:nat} TallyCons(count + 1) of (int, int, size_tally(count))

#pub fun tally_new (): size_tally(0)

implement tally_new () = TallyNil()

#pub fun tally_free {count:nat} (tally: size_tally(count)): void

implement tally_free {count} (tally) = let
  fun walk {count:nat} .<count>. (tally: size_tally(count)): void =
    case+ tally of
    | ~TallyNil() => ()
    | ~TallyCons(_, _, rest) => walk(rest)
in walk(tally) end

fun _tally_length {count:nat} .<count>. (tally: !size_tally(count)): int count =
  case+ tally of
  | TallyNil() => 0
  | TallyCons(_, _, rest) => 1 + _tally_length(rest)

fun _tally_has {count:nat} .<count>. (tally: !size_tally(count), size: int): bool =
  case+ tally of
  | TallyNil() => false
  | TallyCons(each, _, rest) => if each = size then true else _tally_has(rest, size)

fun _tally_bumped {count:nat} .<count>. (tally: size_tally(count), size: int, chars: int): [more:nat] size_tally(more) =
  case+ tally of
  | ~TallyNil() => TallyNil()
  | ~TallyCons(each, kept, rest) =>
    if each = size then TallyCons(each, kept + chars, rest)
    else let
      val bumped = _tally_bumped(rest, size, chars)
    in TallyCons(each, kept, bumped) end

(* The size rounded to a quarter of a pixel *)
fn _rounded (size: int): int = ((size + 125) / 250) * 250

(* chars more characters in size *)
#pub fun tally_add {count:nat} (tally: size_tally(count), size: int, chars: int): [more:nat] size_tally(more)

implement tally_add {count} (tally, size, chars) = let
  val key = _rounded(size)
in
  if chars <= 0 then tally
  else if _tally_has(tally, key) then _tally_bumped(tally, key, chars)
  else if _tally_length(tally) >= TALLY_MAX then tally
  else TallyCons(key, chars, tally)
end

(* The characters in all *)
#pub fun tally_chars {count:nat} (tally: !size_tally(count)): int

implement tally_chars {count} (tally) = let
  fun walk {count:nat} .<count>. (tally: !size_tally(count), so_far: int): int =
    case+ tally of
    | TallyNil() => so_far
    | TallyCons(_, chars, rest) => walk(rest, so_far + chars)
in walk(tally, 0) end

(* The characters in size (rounded to a quarter of a pixel as it is kept) *)
#pub fun tally_chars_in {count:nat} (tally: !size_tally(count), size: int): int

implement tally_chars_in {count} (tally, size) = let
  val key = _rounded(size)
  fun walk {count:nat} .<count>. (tally: !size_tally(count), key: int): int =
    case+ tally of
    | TallyNil() => 0
    | TallyCons(each, chars, rest) => if each = key then chars else walk(rest, key)
in walk(tally, key) end

(* The sizes counted *)
#pub fun tally_sizes {count:nat} (tally: !size_tally(count)): int count

implement tally_sizes {count} (tally) = _tally_length(tally)

(* The size most of the characters are in, the smaller of two with as many;
   16px when nothing is counted *)
#pub fun tally_dominant {count:nat} (tally: !size_tally(count)): size_computed

implement tally_dominant {count} (tally) = let
  fun walk {count:nat} .<count>. (tally: !size_tally(count), best_size: int, best_chars: int): int =
    case+ tally of
    | TallyNil() => best_size
    | TallyCons(size, chars, rest) =>
      if chars > best_chars then walk(rest, size, chars)
      else if chars = best_chars then (if size < best_size then walk(rest, size, chars) else walk(rest, best_size, best_chars))
      else walk(rest, best_size, best_chars)
in
  case+ tally of
  | TallyNil() => 16000
  | TallyCons(_, _, _) => _as_size(walk(tally, 0, ~1))
end

(* ============================================================
   Counting a chapter's characters by size
   ============================================================ *)

(* The characters of data[at, stop) that are not white space nor the
   continuation of one *)
fun _count_chars {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n} .<stop - at>.
  (data: !$A.borrow(byte, l, n), at: int at, stop: int stop, so_far: int): int =
  if at >= stop then so_far
  else let
    val code = _code(data, at)
  in
    if code <= 32 then _count_chars(data, at + 1, stop, so_far)
    else if code >= 128 then (if code < 192 then _count_chars(data, at + 1, stop, so_far) else _count_chars(data, at + 1, stop, so_far + 1))
    else _count_chars(data, at + 1, stop, so_far + 1)
  end

(* An element whose text is not counted *)
fn _is_uncounted {l:agz}{n:pos}{at,len:nat | at + len <= n}
  (data: !$A.borrow(byte, l, n), at: int at, len: int len): bool =
  if _is_word(data, at, len, "head", 4) then true
  else if _is_word(data, at, len, "style", 5) then true
  else if _is_word(data, at, len, "script", 6) then true
  else if _is_word(data, at, len, "title", 5) then true
  else if _is_word(data, at, len, "rt", 2) then true
  else _is_word(data, at, len, "rp", 2)

(* The first of three readings that found a size, the others freed *)
fn _first_found (inline: size_read, rule: size_read, hint: size_read): size_read =
  case+ inline of
  | ~SizeFound(size) => let
      val () = size_read_free(rule)
      val () = size_read_free(hint)
    in SizeFound(size) end
  | ~SizeNone() => (case+ rule of
    | ~SizeFound(size) => let val () = size_read_free(hint) in SizeFound(size) end
    | ~SizeNone() => hint
    | ~SizeIgnored(_) => hint)
  | ~SizeIgnored(_) => (case+ rule of
    | ~SizeFound(size) => let val () = size_read_free(hint) in SizeFound(size) end
    | ~SizeNone() => hint
    | ~SizeIgnored(_) => hint)

(* The size an element's inline style gives *)
fn _inline_size {l:agz}{n:pos}{count:nat} (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, count)): size_read = let
  val @(at, len) = _attr_find(data, attrs, "style", 5)
in
  if len = 0 then SizeNone() else declarations_size_read(data, at, at + len)
end

(* The size a font element's size attribute gives *)
fn _hint_size {l:agz}{n:pos}{name_at,name_len:nat | name_at + name_len <= n}{count:nat}
  (data: !$A.borrow(byte, l, n), name_at: int name_at, name_len: int name_len, attrs: !$X.xml_attr_list(n, count)): size_read =
  if _is_word(data, name_at, name_len, "font", 4) then let
    val @(at, len) = _attr_find(data, attrs, "size", 4)
  in
    if len = 0 then SizeNone() else font_size_attribute_read(data, at, at + len)
  end
  else SizeNone()

(* The size from the best rule *)
fn _rule_size (best: best_rule): size_read =
  if best.found then SizeFound(best.size) else SizeNone()

fun _walk_nodes {ld:agz}{nd:pos}{ls:agz}{ns:pos}{sz:nat}{count:nat}{depth:nat}{kinds:nat} .<sz, 1>.
  (data: !$A.borrow(byte, ld, nd), sheet: !$A.borrow(byte, ls, ns), rules: !css_rules(ns, count),
   nodes: !$X.xml_node_list(nd, sz), chain: ancestors(nd, depth), parent: size_computed, root: size_computed, tally: size_tally(kinds))
  : [more:nat] @(ancestors(nd, depth), size_tally(more)) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) => let
      val @(chain, tally) = _walk_node(data, sheet, rules, node, chain, parent, root, tally)
    in _walk_nodes(data, sheet, rules, rest, chain, parent, root, tally) end
  | $X.xml_nodes_nil() => @(chain, tally)

and _walk_node {ld:agz}{nd:pos}{ls:agz}{ns:pos}{sz:pos}{count:nat}{depth:nat}{kinds:nat} .<sz, 0>.
  (data: !$A.borrow(byte, ld, nd), sheet: !$A.borrow(byte, ls, ns), rules: !css_rules(ns, count),
   node: !$X.xml_node(nd, sz), chain: ancestors(nd, depth), parent: size_computed, root: size_computed, tally: size_tally(kinds))
  : [more:nat] @(ancestors(nd, depth), size_tally(more)) =
  case+ node of
  | $X.xml_text(at, len) => let
      val chars = _count_chars(data, at, at + len, 0)
      val tally = tally_add(tally, parent, chars)
    in @(chain, tally) end
  | $X.xml_element(name_at, name_len, attrs, children) =>
    if _is_uncounted(data, name_at, name_len) then @(chain, tally)
    else let
      val facts = _facts_of(data, name_at, name_len, attrs)
      val best = _best_rule(sheet, rules, data, facts, chain, @{found= false, specificity= 0, order= 0, size= @{basis= BasisPixels(), thousandths= 0}})
      val declared = _first_found(_inline_size(data, attrs), _rule_size(best), _hint_size(data, name_at, name_len, attrs))
      val computed = (case+ declared of
        | ~SizeFound(size) => size_resolve(size, parent, root)
        | ~SizeNone() => parent
        | ~SizeIgnored(_) => parent): size_computed
      val below_root = (if _is_word(data, name_at, name_len, "html", 4) then computed else root): size_computed
      val chain = AncestorsCons(facts, chain)
      val @(chain, tally) = _walk_nodes(data, sheet, rules, children, chain, computed, below_root, tally)
      val+ ~AncestorsCons(_, chain) = chain
    in @(chain, tally) end

(* The characters of the chapter data[0, nd), its parsed tree nodes, added to
   tally by the size they are set in, sheet being the joined style sheets of
   the chapter and rules those it gives *)
#pub fun chapter_tally {ld:agz}{nd:pos}{ls:agz}{ns:pos}{sz:nat}{count:nat}{kinds:nat}
  (data: !$A.borrow(byte, ld, nd), nodes: !$X.xml_node_list(nd, sz), sheet: !$A.borrow(byte, ls, ns), rules: !css_rules(ns, count),
   tally: size_tally(kinds)): [more:nat] size_tally(more)

implement chapter_tally (data, nodes, sheet, rules, tally) = let
  val @(chain, tally) = _walk_nodes(data, sheet, rules, nodes, AncestorsNil(), 16000, 16000, tally)
  val+ ~AncestorsNil() = chain
in tally end

(* chapter_tally for a chapter with no style sheet *)
#pub fun chapter_tally_unstyled {ld:agz}{nd:pos}{sz:nat}{kinds:nat}
  (data: !$A.borrow(byte, ld, nd), nodes: !$X.xml_node_list(nd, sz), tally: size_tally(kinds)): [more:nat] size_tally(more)

implement chapter_tally_unstyled (data, nodes, tally) = let
  val blank = $A.alloc<byte>(1)
  val @(blank_frozen, blank_bytes) = $A.freeze<byte>(blank)
  val rules = RulesNil(): css_rules(1, 0)
  val tally = chapter_tally(data, nodes, blank_bytes, rules, tally)
  val () = css_rules_free(rules)
  val () = $A.drop<byte>(blank_frozen, blank_bytes)
  val () = $A.free<byte>($A.thaw<byte>(blank_frozen))
in tally end

(* ============================================================
   Finding a chapter's style sheets
   ============================================================ *)

(* Spans of the document of n bytes, count of them *)
#pub datavtype span_list(n:int, count:int) =
  | SpanNil(n, 0) of ()
  | {count:nat}{at,len:nat | at + len <= n} SpanCons(n, count + 1) of (int at, int len, span_list(n, count))

#pub fun span_list_free {n:int}{count:nat} (spans: span_list(n, count)): void

implement span_list_free {n}{count} (spans) = let
  fun walk {count:nat} .<count>. (spans: span_list(n, count)): void =
    case+ spans of
    | ~SpanNil() => ()
    | ~SpanCons(_, _, rest) => walk(rest)
in walk(spans) end

(* The most spans (and so style sheets) of one kind a chapter gives *)
#pub stadef SOURCES_MAX = 8
#define SOURCES_MAX 8

#pub stadef STYLE_BYTES_MAX = 262144
#define STYLE_BYTES_MAX 262144

fun _spans_reversed {n:int}{a,b:nat} .<a>.
  (spans: span_list(n, a), onto: span_list(n, b)): span_list(n, a + b) =
  case+ spans of
  | ~SpanNil() => onto
  | ~SpanCons(at, len, rest) => _spans_reversed(rest, SpanCons(at, len, onto))

fun _spans_length {n:int}{count:nat} .<count>. (spans: !span_list(n, count)): int count =
  case+ spans of
  | SpanNil() => 0
  | SpanCons(_, _, rest) => 1 + _spans_length(rest)

(* The text nodes in children, a style element's, each added *)
fun _style_texts {nd:pos}{sz:nat}{kept:nat} .<sz>.
  (nodes: !$X.xml_node_list(nd, sz), found: span_list(nd, kept)): [more:nat] span_list(nd, more) =
  case+ nodes of
  | $X.xml_nodes_nil() => found
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_text(at, len) =>
       if len > STYLE_BYTES_MAX then _style_texts(rest, found)
       else if _spans_length(found) >= SOURCES_MAX then _style_texts(rest, found)
       else _style_texts(rest, SpanCons(at, len, found))
     | $X.xml_element(_, _, _, _) => _style_texts(rest, found))

(* The style elements' texts of the nodes, in the document's order *)
fun _styles_in {ld:agz}{nd:pos}{sz:nat}{kept:nat} .<sz, 1>.
  (data: !$A.borrow(byte, ld, nd), nodes: !$X.xml_node_list(nd, sz), found: span_list(nd, kept)): [more:nat] span_list(nd, more) =
  case+ nodes of
  | $X.xml_nodes_nil() => found
  | $X.xml_nodes_cons(node, rest) => let
      val found = _styles_of(data, node, found)
    in _styles_in(data, rest, found) end

and _styles_of {ld:agz}{nd:pos}{sz:pos}{kept:nat} .<sz, 0>.
  (data: !$A.borrow(byte, ld, nd), node: !$X.xml_node(nd, sz), found: span_list(nd, kept)): [more:nat] span_list(nd, more) =
  case+ node of
  | $X.xml_text(_, _) => found
  | $X.xml_element(name_at, name_len, _, children) =>
    if _is_word(data, name_at, name_len, "style", 5) then _style_texts(children, found)
    else _styles_in(data, children, found)

(* Whether a link element is a style sheet to be applied: rel has
   stylesheet and not alternate, and any media is all or screen *)
fn _is_sheet_link {l:agz}{n:pos}{count:nat} (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, count)): bool = let
  val @(rel_at, rel_len) = _attr_find(data, attrs, "rel", 3)
  val @(media_at, media_len) = _attr_find(data, attrs, "media", 5)
in
  if ~(_has_word(data, rel_at, rel_at + rel_len, "stylesheet", 10)) then false
  else if _has_word(data, rel_at, rel_at + rel_len, "alternate", 9) then false
  else if media_len = 0 then true
  else if _is_word(data, media_at, media_len, "all", 3) then true
  else _is_word(data, media_at, media_len, "screen", 6)
end

(* The hrefs of the style sheet links of the nodes, in the document's order *)
fun _links_in {ld:agz}{nd:pos}{sz:nat}{kept:nat} .<sz, 1>.
  (data: !$A.borrow(byte, ld, nd), nodes: !$X.xml_node_list(nd, sz), found: span_list(nd, kept)): [more:nat] span_list(nd, more) =
  case+ nodes of
  | $X.xml_nodes_nil() => found
  | $X.xml_nodes_cons(node, rest) => let
      val found = _links_of(data, node, found)
    in _links_in(data, rest, found) end

and _links_of {ld:agz}{nd:pos}{sz:pos}{kept:nat} .<sz, 0>.
  (data: !$A.borrow(byte, ld, nd), node: !$X.xml_node(nd, sz), found: span_list(nd, kept)): [more:nat] span_list(nd, more) =
  case+ node of
  | $X.xml_text(_, _) => found
  | $X.xml_element(name_at, name_len, attrs, children) =>
    if _is_word(data, name_at, name_len, "link", 4) then let
      val @(href_at, href_len) = _attr_find(data, attrs, "href", 4)
    in
      if href_len = 0 then found
      else if href_len >= 65536 then found
      else if _spans_length(found) >= SOURCES_MAX then found
      else if _is_sheet_link(data, attrs) then SpanCons(href_at, href_len, found)
      else found
    end
    else _links_in(data, children, found)

(* The style sheets a chapter links to (their hrefs), in the document's order *)
#pub fun sheet_link_spans {ld:agz}{nd:pos}{sz:nat}
  (data: !$A.borrow(byte, ld, nd), nodes: !$X.xml_node_list(nd, sz)): [count:nat] span_list(nd, count)

implement sheet_link_spans (data, nodes) = let
  val reversed = _links_in(data, nodes, SpanNil())
in _spans_reversed(reversed, SpanNil()) end

(* The texts of the style elements of a chapter (their spans), in the document's order *)
#pub fun sheet_style_spans {ld:agz}{nd:pos}{sz:nat}
  (data: !$A.borrow(byte, ld, nd), nodes: !$X.xml_node_list(nd, sz)): [count:nat] span_list(nd, count)

implement sheet_style_spans (data, nodes) = let
  val reversed = _styles_in(data, nodes, SpanNil())
in _spans_reversed(reversed, SpanNil()) end

end
