#target native

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use xml-tree as X

staload "css_size.sats"
staload "css_cascade.sats"

(* The cascade of a chapter's sizes (src/css_cascade.bats), played on
   bytes: which rule wins, inheritance, rem against html, the text that is
   counted and the text that is not, the tally and the dominant size, and
   the style sheets a chapter names. What the types prove (an index below a
   length, a size from a pixel to a thousand) is not tested here; what
   they cannot (that the matching is CSS's and the counting is the
   text's) is (quire#431, stage 2). *)

val _failures = ref<int>(0)

fn fail (what: string): void = let
  val () = println! ("FAIL ", what)
in !_failures := !_failures + 1 end

fn expect_int (got: int, wanted: int, what: string): void =
  if got = wanted then () else let
    val () = println! ("  ", what, ": wanted ", wanted, ", got ", got)
  in fail(what) end

fun fill {l:agz}{m:pos}{i:nat | i <= m} .<m - i>.
  (array: !$A.arr(byte, l, m), text: string(m), m: int m, i: int i): void =
  if i >= m then ()
  else let
    val () = $A.set<byte>(array, i, $A.int2byte($AR.low_byte(char2int0(text[i]))))
  in fill(array, text, m, i + 1) end

fn text_array {m:pos | m <= 1048576} (text: string(m), m: int m): [l:agz] $A.arr(byte, l, m) = let
  val array = $A.alloc<byte>(m)
  val () = fill(array, text, m, 0)
in array end

(* The tally of the chapter doc under the style sheet sheet *)
fn chapter_run {n,m:pos | n <= 1048576; m <= 1048576} (doc: string(n), sheet: string(m)): [t:nat] size_tally(t) = let
  val n = g1u2i(string1_length(doc))
  val m = g1u2i(string1_length(sheet))
  val doc_array = text_array(doc, n)
  val @(doc_frozen, doc_view) = $A.freeze<byte>(doc_array)
  val nodes = $X.parse_document(doc_view, n)
  val sheet_array = text_array(sheet, m)
  val @(sheet_frozen, sheet_view) = $A.freeze<byte>(sheet_array)
  val ~SheetRead(_, _, rules) = sheet_rules_read(sheet_view, m)
  val tally = chapter_tally(doc_view, nodes, sheet_view, rules, tally_new())
  val () = css_rules_free(rules)
  val () = $A.drop<byte>(sheet_frozen, sheet_view)
  val () = $A.free<byte>($A.thaw<byte>(sheet_frozen))
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(doc_frozen, doc_view)
  val () = $A.free<byte>($A.thaw<byte>(doc_frozen))
in tally end

fn check_basics (): void = let
  (* nothing set: the browser's 16px, every character not white space *)
  val plain = chapter_run("<html><body><p>hello world</p></body></html>", " ")
  val () = expect_int(tally_chars(plain), 10, "plain: characters")
  val () = expect_int(tally_chars_in(plain, 16000), 10, "plain: in 16px")
  val () = expect_int(tally_dominant(plain), 16000, "plain: dominant")
  val () = tally_free(plain)

  (* an inline style, and the size inherited by what is inside *)
  val inline = chapter_run("<div style=\"font-size:20px\"><p>aa<span>bb</span></p></div><p>cccccc</p>", " ")
  val () = expect_int(tally_chars_in(inline, 20000), 4, "inline: 20px")
  val () = expect_int(tally_chars_in(inline, 16000), 6, "inline: 16px")
  val () = expect_int(tally_dominant(inline), 16000, "inline: dominant")
  val () = tally_free(inline)

  (* an empty chapter has the browser's size *)
  val empty = chapter_run("<html><body/></html>", " ")
  val () = expect_int(tally_chars(empty), 0, "empty: characters")
  val () = expect_int(tally_dominant(empty), 16000, "empty: dominant")
  val () = tally_free(empty)

  (* characters: white space and continuation bytes are not counted *)
  val multibyte = chapter_run("<p>\xc3\xa9 a\n\t b \xe6\x97\xa5\xe6\x9c\xac</p>", " ")
  val () = expect_int(tally_chars(multibyte), 5, "multibyte: characters")
  val () = tally_free(multibyte)
in () end

fn check_rules (): void = let
  (* specificity first, then order *)
  val cascade = chapter_run(
    "<p>aaaa</p><p class=\"big\">bbbbbb</p><p class=\"big\" id=\"x\">cc</p><p class=\"other big\">ddd</p>",
    "p{font-size:10px} .big{font-size:30px} #x{font-size:20px} p{font-size:12px}")
  val () = expect_int(tally_chars_in(cascade, 12000), 4, "cascade: later p rule")
  val () = expect_int(tally_chars_in(cascade, 30000), 9, "cascade: class beats element")
  val () = expect_int(tally_chars_in(cascade, 20000), 2, "cascade: id beats class")
  val () = tally_free(cascade)

  (* a descendant chain: nearest ancestor first, any depth *)
  val descendant = chapter_run(
    "<div><section><p>aa</p></section></div><p>bb</p><section><p>cccc</p></section>",
    "div p{font-size:2em}")
  val () = expect_int(tally_chars_in(descendant, 32000), 2, "descendant: inside div")
  val () = expect_int(tally_chars_in(descendant, 16000), 6, "descendant: outside div")
  val () = tally_free(descendant)

  (* a chain of three, in order *)
  val chain = chapter_run(
    "<div class=\"a\"><p class=\"b\"><span>xx</span></p></div><p class=\"b\"><div class=\"a\"><span>yyy</span></div></p>",
    ".a .b span{font-size:20px}")
  val () = expect_int(tally_chars_in(chain, 20000), 2, "chain: in order")
  val () = expect_int(tally_chars_in(chain, 16000), 3, "chain: out of order")
  val () = tally_free(chain)

  (* element names are matched as in XML, to the letter *)
  val names = chapter_run("<p>aaa</p>", "P{font-size:30px}")
  val () = expect_int(tally_chars_in(names, 16000), 3, "names: case")
  val () = tally_free(names)

  (* a selector css_size does not read selects nothing *)
  val skipped = chapter_run("<div><p>aaa</p></div>", "div > p{font-size:30px} p:hover{font-size:30px} p[x]{font-size:30px}")
  val () = expect_int(tally_chars_in(skipped, 16000), 3, "skipped: unsupported selectors")
  val () = tally_free(skipped)

  (* an inline style beats a rule; font size is below every rule *)
  val inline = chapter_run("<p class=\"c\" style=\"font-size:20px\">aa</p><p class=\"c\">bbb</p><font size=\"1\">cccc</font><font size=\"1\" class=\"c\">dd</font>", ".c{font-size:30px}")
  val () = expect_int(tally_chars_in(inline, 20000), 2, "inline over rule")
  val () = expect_int(tally_chars_in(inline, 30000), 5, "rule over font size")
  val () = expect_int(tally_chars_in(inline, 10000), 4, "font size alone")
  val () = tally_free(inline)

  (* a class is a word of the attribute, not a part of one *)
  val words = chapter_run("<p class=\"bigger\">aa</p><p class=\"x  big\">bb</p><p class=\"bi\">cc</p>", ".big{font-size:30px}")
  val () = expect_int(tally_chars_in(words, 30000), 2, "class: one word")
  val () = expect_int(tally_chars_in(words, 16000), 4, "class: not a part")
  val () = tally_free(words)
in () end

fn check_inheritance (): void = let
  (* quire#431's book A: the rem trick on html *)
  val book_a = chapter_run(
    "<html><head><title>T</title></head><body><h1>Title</h1><p>Body text here <small>tiny</small></p></body></html>",
    "html{font-size:62.5%} p{font-size:1.6rem} h1{font-size:2em} small{font-size:.8em}")
  val () = expect_int(tally_chars_in(book_a, 20000), 5, "book A: h1 is 2em of the html's 10px")
  val () = expect_int(tally_chars_in(book_a, 16000), 12, "book A: p is 1.6rem")
  val () = expect_int(tally_chars_in(book_a, 12800), 4, "book A: small is .8em of p")
  val () = expect_int(tally_dominant(book_a), 16000, "book A: dominant")
  val () = tally_free(book_a)

  (* book B: points *)
  val book_b = chapter_run(
    "<body><h1>Title</h1><p class=\"lead\">The lead paragraph</p><p>Body text of the paragraph, long</p></body>",
    "p{font-size:9pt} h1{font-size:18pt} .lead{font-size:1.25em}")
  val () = expect_int(tally_chars_in(book_b, 24000), 5, "book B: h1 18pt")
  val () = expect_int(tally_chars_in(book_b, 20000), 16, "book B: lead is 1.25em of the body's 16px, over p")
  val () = expect_int(tally_chars_in(book_b, 12000), 27, "book B: p is 9pt")
  val () = tally_free(book_b)

  (* rem is the html element's, and html itself is 16px to start from *)
  val root = chapter_run("<html><body><p>aaaa</p></body></html>", "html{font-size:2rem} p{font-size:1rem}")
  val () = expect_int(tally_chars_in(root, 32000), 4, "rem: html is 2rem of the initial 16px, p is 1rem of html")
  val () = tally_free(root)
in () end

fn check_uncounted (): void = let
  val skipped = chapter_run(
    "<html><head><title>Title text</title><style>p{font-size:30px}</style><script>var x = 1;</script></head><body><p>aa<ruby>b<rp>(</rp><rt>cc</rt><rp>)</rp></ruby></p></body></html>",
    " ")
  val () = expect_int(tally_chars(skipped), 3, "uncounted: only the body text and the ruby base")
  val () = tally_free(skipped)
in () end

fn check_tally (): void = let
  (* a tie is the smaller size; the most characters otherwise *)
  val tie = chapter_run("<p style=\"font-size:20px\">aaa</p><p style=\"font-size:10px\">bbb</p>", " ")
  val () = expect_int(tally_dominant(tie), 10000, "tie: the smaller")
  val () = tally_free(tie)

  (* sizes are rounded to a quarter of a pixel *)
  val rounded = chapter_run("<p style=\"font-size:12.1px\">aaa</p><p style=\"font-size:11.9px\">bb</p>", " ")
  val () = expect_int(tally_sizes(rounded), 1, "rounded: one size")
  val () = expect_int(tally_dominant(rounded), 12000, "rounded: the quarter pixel")
  val () = tally_free(rounded)

  (* the most distinct sizes, the rest not counted *)
  val many = chapter_run(
    "<p style=\"font-size:10px\">a</p><p style=\"font-size:11px\">a</p><p style=\"font-size:12px\">a</p><p style=\"font-size:13px\">a</p><p style=\"font-size:14px\">a</p><p style=\"font-size:15px\">a</p><p style=\"font-size:17px\">a</p><p style=\"font-size:18px\">a</p>",
    " ")
  val () = expect_int(tally_sizes(many), 8, "many: eight sizes")
  val () = tally_free(many)
in () end

(* A tally built by hand *)
fun add_sizes {t:nat}{k:nat | k <= 100} .<100 - k>. (tally: size_tally(t), k: int k): [more:nat] size_tally(more) =
  if k >= 100 then tally
  else let
    val next = tally_add(tally, 1000 + 1000 * k, 1)
  in add_sizes(next, k + 1) end

fn check_most_sizes (): void = let
  val many = add_sizes(tally_new(), 0)
  val () = expect_int(tally_sizes(many), TALLY_MAX, "the most sizes")
  val () = expect_int(tally_chars(many), TALLY_MAX, "the rest are not counted")
  val () = tally_free(many)
in () end

fn spans_check {n:pos}{count:nat} (spans: span_list(n, count), wanted: int, what: string): void = let
  val () = expect_int(let
    fun length {n:int}{count:nat} .<count>. (spans: !span_list(n, count)): int =
      case+ spans of
      | SpanNil() => 0
      | SpanCons(_, _, rest) => 1 + length(rest)
  in length(spans) end, wanted, what)
in span_list_free(spans) end

(* The map of the chapter doc under sheet, sizes against base *)
fn map_run {n,m:pos | n <= 1048576; m <= 1048576} (doc: string(n), sheet: string(m), initial: size_computed, base: size_computed): [c:nat] size_map(c) = let
  val n = g1u2i(string1_length(doc))
  val m = g1u2i(string1_length(sheet))
  val doc_array = text_array(doc, n)
  val @(doc_frozen, doc_view) = $A.freeze<byte>(doc_array)
  val nodes = $X.parse_document(doc_view, n)
  val sheet_array = text_array(sheet, m)
  val @(sheet_frozen, sheet_view) = $A.freeze<byte>(sheet_array)
  val ~SheetRead(_, _, rules) = sheet_rules_read(sheet_view, m)
  val map = chapter_size_map(doc_view, nodes, sheet_view, rules, initial, base)
  val () = css_rules_free(rules)
  val () = $A.drop<byte>(sheet_frozen, sheet_view)
  val () = $A.free<byte>($A.thaw<byte>(sheet_frozen))
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(doc_frozen, doc_view)
  val () = $A.free<byte>($A.thaw<byte>(doc_frozen))
in map end

(* The step of the n-th entry of the map, -1 when it has fewer *)
fun step_nth {c:nat} .<c>. (map: !size_map(c), n: int): int =
  case+ map of
  | MapNil() => ~1
  | MapCons(_, step, rest) => if n <= 0 then step else step_nth(rest, n - 1)

fn check_map (): void = let
  (* book A against its dominant 16px: html is not made, p is the base,
     h1 and small are what they are against it *)
  val map = map_run(
    "<html><body><h1>Title</h1><p>Body <small>tiny</small></p><div>loose</div></body></html>",
    "html{font-size:62.5%} p{font-size:1.6rem} h1{font-size:2em} small{font-size:.8em}", 16000, 16000)
  val () = expect_int(size_map_count(map), 4, "map A: entries")
  val () = expect_int(step_nth(map, 0), 25, "map A: h1 is 2em of the body's 10px, 1.25 of 16px")
  val () = expect_int(step_nth(map, 1), 20, "map A: p is the base")
  val () = expect_int(step_nth(map, 2), 16, "map A: small is .8 of p")
  val () = expect_int(step_nth(map, 3), 13, "map A: a div is shown at the body's 10px")
  val () = size_map_free(map)

  (* a book that sets nothing maps nothing *)
  val map = map_run("<html><body><h1>Title</h1><p>Text <em>here</em></p></body></html>", " ", 16000, 16000)
  val () = expect_int(size_map_count(map), 0, "map: nothing set")
  val () = size_map_free(map)

  (* book B against its dominant 12px (9pt) *)
  val map = map_run(
    "<body><h1>T</h1><h2>S</h2><p class=\"lead\">L</p><p>Body</p><p style=\"font-size:8px\">c</p></body>",
    "p{font-size:9pt} h1{font-size:18pt} h2{font-size:13.5pt} .lead{font-size:11.25pt}", 16000, 12000)
  val () = expect_int(step_nth(map, 0), 40, "map B: h1 is twice")
  val () = expect_int(step_nth(map, 1), 30, "map B: h2 is 1.5")
  val () = expect_int(step_nth(map, 2), 25, "map B: the lead is 1.25")
  val () = expect_int(step_nth(map, 3), 20, "map B: p is the base")
  val () = expect_int(step_nth(map, 4), 13, "map B: the caption, 8px of 12px")
  val () = size_map_free(map)

  (* the floor and the ceiling *)
  val map = map_run("<p style=\"font-size:1px\">a</p><p style=\"font-size:400%\">b</p>", " ", 16000, 16000)
  val () = expect_int(step_nth(map, 0), 10, "map: the floor, half")
  val () = expect_int(step_nth(map, 1), 60, "map: the ceiling, three times")
  val () = size_map_free(map)

  (* respecting the publisher's sizes: the root is the reader's, 24px, and
     the sizes are against it; an absolute size stays absolute *)
  val map = map_run(
    "<html><body><p>a</p><h1>b</h1><p class=\"c\">c</p></body></html>",
    "html{font-size:62.5%} p{font-size:1.6rem} h1{font-size:18pt} .c{font-size:12px}", 24000, 24000)
  val () = expect_int(step_nth(map, 0), 20, "respect: 1.6rem of 62.5% of the root is the root")
  val () = expect_int(step_nth(map, 1), 20, "respect: 18pt is 24px, the root")
  val () = expect_int(step_nth(map, 2), 10, "respect: 12px is half of 24px")
  val () = size_map_free(map)

  (* a map is taken in the document's order *)
  val map = map_run("<p style=\"font-size:20px\">a</p><p style=\"font-size:8px\">b</p>", " ", 16000, 16000)
  val @(first, map) = size_map_take(map, 0)
  val () = expect_int(first, 0, "take: before the first")
  val @(second, map) = size_map_take(map, 1)
  val () = expect_int(second, 25, "take: the first element's name is at 1")
  val () = size_map_free(map)
in () end


(* The alignments of the chapter doc under sheet *)
fn align_run {n,m:pos | n <= 1048576; m <= 1048576} (doc: string(n), sheet: string(m)): [c:nat] align_map(c) = let
  val n = g1u2i(string1_length(doc))
  val m = g1u2i(string1_length(sheet))
  val doc_array = text_array(doc, n)
  val @(doc_frozen, doc_view) = $A.freeze<byte>(doc_array)
  val nodes = $X.parse_document(doc_view, n)
  val sheet_array = text_array(sheet, m)
  val @(sheet_frozen, sheet_view) = $A.freeze<byte>(sheet_array)
  val ~SheetRead(_, _, rules) = sheet_rules_read(sheet_view, m)
  val aligns = sheet_aligns_read(sheet_view, m)
  val @(sizes, map) = chapter_maps(doc_view, nodes, sheet_view, rules, aligns, 16000, 16000)
  val () = size_map_free(sizes)
  val () = css_rules_free(rules)
  val () = align_rules_free(aligns)
  val () = $A.drop<byte>(sheet_frozen, sheet_view)
  val () = $A.free<byte>($A.thaw<byte>(sheet_frozen))
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(doc_frozen, doc_view)
  val () = $A.free<byte>($A.thaw<byte>(doc_frozen))
in map end

(* The alignment of the n-th entry of the map as a word, "none" when it has fewer *)
fun align_nth {c:nat} .<c>. (map: !align_map(c), n: int): string =
  case+ map of
  | AlignMapNil() => "none"
  | AlignMapCons(_, align, rest) =>
    if n <= 0 then
      (case+ align of
       | AlignNone() => "none"
       | AlignLeft() => "left"
       | AlignRight() => "right"
       | AlignCenter() => "center")
    else align_nth(rest, n - 1)

fn expect_text (got: string, wanted: string, what: string): void =
  if got = wanted then () else let
    val () = println! ("  ", what, ": wanted ", wanted, ", got ", got)
  in fail(what) end

fn align_text (align: align_value): string =
  case+ align of
  | AlignNone() => "none"
  | AlignLeft() => "left"
  | AlignRight() => "right"
  | AlignCenter() => "center"

fn check_aligns (): void = let
  (* columns by their place in the row, the more specific rule winning, whitespace between the cells not counted *)
  val map = align_run(
    "<table>\n<tr>\n<td>a</td>\n<td>b</td>\n</tr>\n<tr><td>c</td><td>d</td></tr></table><p>x</p>",
    "td:nth-child(odd){text-align:right} td:nth-child(even){text-align:left} table td:last-child{text-align:-webkit-center} p{text-align:right}")
  val () = expect_int(align_map_count(map), 4, "aligns: four cells, no paragraph")
  val () = expect_text(align_nth(map, 0), "right", "aligns: first column")
  val () = expect_text(align_nth(map, 1), "center", "aligns: last child beats even")
  val () = expect_text(align_nth(map, 2), "right", "aligns: first column of the second row")
  val () = expect_text(align_nth(map, 3), "center", "aligns: second row's last")
  val () = align_map_free(map)

  (* a style attribute beats every rule; MathML's cells and rows are parts of a table too *)
  val map = align_run(
    "<math><mtable><mtr><mtd style=\"text-align:center\">a</mtd><mtd>b</mtd></mtr></mtable></math>",
    "mtable mtd{text-align:left} mtr{text-align:right}")
  val () = expect_int(align_map_count(map), 3, "aligns: mtr and two mtd")
  val () = expect_text(align_nth(map, 0), "right", "aligns: the row")
  val () = expect_text(align_nth(map, 1), "center", "aligns: the style attribute")
  val () = expect_text(align_nth(map, 2), "left", "aligns: the rule")
  val () = align_map_free(map)

  (* the number of the child, and the first child *)
  val map = align_run("<tr><td>a</td><td>b</td><td>c</td></tr>", "td:nth-child(2){text-align:center} td:first-child{text-align:right}")
  val () = expect_int(align_map_count(map), 2, "aligns: two of three cells")
  val () = expect_text(align_nth(map, 0), "right", "aligns: first child")
  val () = expect_text(align_nth(map, 1), "center", "aligns: second child")
  val () = expect_text(align_nth(map, 2), "none", "aligns: third child has none")
  val () = align_map_free(map)

  (* a map is taken in the document's order *)
  val map = align_run("<tr><td style=\"text-align:left\">a</td><td style=\"text-align:right\">b</td></tr>", " ")
  val @(none, map) = align_map_take(map, 0)
  val () = expect_text(align_text(none), "none", "aligns take: before the first")
  val @(first, map) = align_map_take(map, 5)
  val () = expect_text(align_text(first), "left", "aligns take: the first cell's name is at 5")
  val () = align_map_free(map)
in () end

fn check_sources (): void = let
  val doc = "<html><head><link rel=\"stylesheet\" href=\"a.css\"/><link rel=\"alternate stylesheet\" href=\"b.css\"/><link rel=\"stylesheet\" media=\"print\" href=\"c.css\"/><link rel=\"stylesheet\" media=\"screen\" href=\"d.css\"/><link rel=\"icon\" href=\"e.png\"/><link rel=\"stylesheet\"/><style>p{}</style><style>h1{}</style></head><body><p>x</p></body></html>"
  val n = g1u2i(string1_length(doc))
  val array = text_array(doc, n)
  val @(frozen, view) = $A.freeze<byte>(array)
  val nodes = $X.parse_document(view, n)
  val () = spans_check(sheet_link_spans(view, nodes), 2, "links: a and d")
  val () = spans_check(sheet_style_spans(view, nodes), 2, "styles: two")
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

val _state = ref<[seed:nat | seed < 65536] int seed>(4242)

fn next_number (): [value:nat | value < 65536] int value = let
  val state = !_state
  val next = $AR.band_g1(state * 25173 + 13849, 65535)
  val () = !_state := next
in next end

fun copy_text {l:agz}{m:pos}{at,k:nat | at + k <= m}{i:nat | i <= k} .<k - i>.
  (array: !$A.arr(byte, l, m), at: int at, text: string(k), k: int k, i: int i): void =
  if i >= k then ()
  else let
    val () = $A.set<byte>(array, at + i, $A.int2byte($AR.low_byte(char2int0(text[i]))))
  in copy_text(array, at, text, k, i + 1) end

(* text written at at, when it fits; the end of what is written *)
fn put {l:agz}{m:pos}{at,k:nat | at <= m} (array: !$A.arr(byte, l, m), at: int at, m: int m, text: string(k), k: int k): [end_at:nat | end_at <= m] int end_at =
  if at + k > m then at
  else let
    val () = copy_text(array, at, text, k, 0)
  in at + k end

(* one of the pieces a random chapter is made of *)
fn put_piece {l:agz}{m:pos}{at:nat | at <= m} (array: !$A.arr(byte, l, m), at: int at, m: int m, choice: [c:nat] int c): [end_at:nat | end_at <= m] int end_at =
  case+ $AR.band_g1(choice, 15) of
  | 0 => put(array, at, m, "<p>", 3)
  | 1 => put(array, at, m, "</p>", 4)
  | 2 => put(array, at, m, "<div class=\"a\">", 15)
  | 3 => put(array, at, m, "</div>", 6)
  | 4 => put(array, at, m, "<span style=\"font-size:2em\">", 28)
  | 5 => put(array, at, m, "</span>", 7)
  | 6 => put(array, at, m, "word ", 5)
  | 7 => put(array, at, m, "\xc3\xa9\xc3\xa9 ", 5)
  | 8 => put(array, at, m, "<h1 id=\"t\">", 11)
  | 9 => put(array, at, m, "</h1>", 5)
  | 10 => put(array, at, m, "<font size=\"+2\">", 16)
  | 11 => put(array, at, m, "</font>", 7)
  | 12 => put(array, at, m, "<br/>", 5)
  | 13 => put(array, at, m, "<i>", 3)
  | 14 => put(array, at, m, "</i>", 4)
  | _ => put(array, at, m, "text", 4)

fun put_pieces {l:agz}{at:nat | at <= 4096}{count:nat} .<count>.
  (array: !$A.arr(byte, l, 4096), at: int at, count: int count): void =
  if count <= 0 then ()
  else let
    val next = put_piece(array, at, 4096, next_number())
  in put_pieces(array, next, count - 1) end

(* a random chapter under a sheet of rules that match its pieces: the
   tally is within its bounds whatever the chapter is *)
fn fuzz_once (): void = let
  val sheet = "div p{font-size:80%} .a{font-size:1.5em} #t{font-size:30px} i{font-size:.5em} p{font-size:larger} span span{font-size:smaller}"
  val sheet_array = text_array(sheet, 126)
  val @(sheet_frozen, sheet_view) = $A.freeze<byte>(sheet_array)
  val ~SheetRead(_, _, rules) = sheet_rules_read(sheet_view, 126)
  val array = $A.alloc<byte>(4096)
  val start = put(array, 0, 4096, "<html><body>", 12)
  val () = put_pieces(array, start, 1 + $AR.band_g1(next_number(), 255))
  val @(frozen, view) = $A.freeze<byte>(array)
  val nodes = $X.parse_document(view, 4096)
  val tally = chapter_tally(view, nodes, sheet_view, rules, tally_new())
  val () = (if tally_sizes(tally) <= TALLY_MAX then () else fail("more sizes than the most"))
  val () = (if tally_chars(tally) <= 4096 then () else fail("more characters than bytes"))
  val () = (if tally_dominant(tally) >= 1000 then () else fail("a dominant size under a pixel"))
  val () = tally_free(tally)
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
  val () = css_rules_free(rules)
  val () = $A.drop<byte>(sheet_frozen, sheet_view)
in $A.free<byte>($A.thaw<byte>(sheet_frozen)) end

fun fuzz {count:nat} .<count>. (count: int count): void =
  if count <= 0 then () else let val () = fuzz_once() in fuzz(count - 1) end

implement main0 () = let
  val () = check_basics()
  val () = check_rules()
  val () = check_inheritance()
  val () = check_uncounted()
  val () = check_tally()
  val () = check_most_sizes()
  val () = check_sources()
  val () = check_map()
  val () = check_aligns()
  val () = fuzz(5000)
in
  if !_failures = 0 then println! ("all ok")
  else println! (!_failures, " failures")
end
