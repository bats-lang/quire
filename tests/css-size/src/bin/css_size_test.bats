#target native

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR

staload "css_size.sats"

(* The font sizes a book's CSS gives (src/css_size.bats), played on
   bytes: the values, a declaration block, the seven sizes of <font
   size>, a selector's specificity, a whole style sheet, the sizes a
   chain of em and rem comes to, and the proportion to the dominant size
   held from half to three times. What the types prove (the bounds of a
   size and a proportion, a clip's index) is not tested here; what they
   cannot (that the grammar is CSS's) is. *)

val _failures = ref<int>(0)

fn fail (what: string): void = let
  val () = println! ("FAIL ", what)
in !_failures := !_failures + 1 end

fn expect_text (got: string, wanted: string, what: string): void =
  if got = wanted then () else let
    val () = println! ("  ", what, ": wanted ", wanted, ", got ", got)
  in fail(what) end

fn expect_int (got: int, wanted: int, what: string): void =
  if got = wanted then () else let
    val () = println! ("  ", what, ": wanted ", wanted, ", got ", got)
  in fail(what) end

(* ---------------- text in an array ---------------- *)

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

(* ---------------- what a reading says ---------------- *)

fn basis_text (basis: size_basis): string =
  case+ basis of
  | BasisPixels() => "px"
  | BasisParent() => "parent"
  | BasisRoot() => "root"

fn ignored_text (reason: size_ignored): string =
  case+ reason of
  | IgnoredEmpty() => "ignored empty"
  | IgnoredImportant() => "ignored important"
  | IgnoredFunction() => "ignored function"
  | IgnoredNegative() => "ignored negative"
  | IgnoredNumber() => "ignored number"
  | IgnoredUnit() => "ignored unit"
  | IgnoredKeyword() => "ignored keyword"

(* what a reading is: its kind, and a found size's thousandths (else 0) *)
fn read_parts (read: size_read): @(string, int) =
  case+ read of
  | ~SizeFound(declared) => @(basis_text(declared.basis), declared.thousandths)
  | ~SizeNone() => @("none", 0)
  | ~SizeIgnored(reason) => @(ignored_text(reason), 0)

fn expect_read (read: size_read, kind: string, thousandths: int, what: string): void = let
  val @(got_kind, got_thousandths) = read_parts(read)
in
  expect_text(got_kind, kind, what);
  expect_int(got_thousandths, thousandths, what)
end

(* a value alone *)
fn value {m:pos | m <= 1048576} (text: string(m), kind: string, thousandths: int): void = let
  val m = g1u2i(string1_length(text))
  val array = text_array(text, m)
  val @(frozen, view) = $A.freeze<byte>(array)
  val () = expect_read(value_size_read(view, 0, m), kind, thousandths, text)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* a declaration block *)
fn block {m:pos | m <= 1048576} (text: string(m), kind: string, thousandths: int): void = let
  val m = g1u2i(string1_length(text))
  val array = text_array(text, m)
  val @(frozen, view) = $A.freeze<byte>(array)
  val () = expect_read(declarations_size_read(view, 0, m), kind, thousandths, text)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* the attribute of <font size> *)
fn font_size {m:pos | m <= 1048576} (text: string(m), kind: string, thousandths: int): void = let
  val m = g1u2i(string1_length(text))
  val array = text_array(text, m)
  val @(frozen, view) = $A.freeze<byte>(array)
  val () = expect_read(font_size_attribute_read(view, 0, m), kind, thousandths, text)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn check_values (): void = let
  val () = value("16px", "px", 16000)
  val () = value("1.6rem", "root", 1600)
  val () = value("62.5%", "parent", 625)
  val () = value("9pt", "px", 12000)
  val () = value("1.25em", "parent", 1250)
  val () = value("0.8EM", "parent", 800)
  val () = value(".5em", "parent", 500)
  val () = value("+2em", "parent", 2000)
  val () = value("1.2345em", "parent", 1234)
  val () = value("2ex", "parent", 1000)
  val () = value("1in", "px", 96000)
  val () = value("1pc", "px", 16000)
  val () = value("1cm", "px", 37800)
  val () = value("10mm", "px", 37800)
  val () = value("  12px  ", "px", 12000)
  (* a number past what is kept is held to it *)
  val () = value("999999px", "px", 1000000)
  val () = value("4000%", "parent", 10000)
  val () = value("400%", "parent", 4000)
  (* keywords, in either case *)
  val () = value("xx-small", "px", 9000)
  val () = value("x-small", "px", 10000)
  val () = value("small", "px", 13000)
  val () = value("MEDIUM", "px", 16000)
  val () = value("large", "px", 18000)
  val () = value("x-large", "px", 24000)
  val () = value("xx-large", "px", 32000)
  val () = value("xxx-large", "px", 48000)
  val () = value("larger", "parent", 1200)
  val () = value("smaller", "parent", 833)
  val () = value("inherit", "parent", 1000)
  val () = value("unset", "parent", 1000)
  val () = value("initial", "px", 16000)
  (* not read *)
  val () = value("calc(1em + 2px)", "ignored function", 0)
  val () = value("clamp(1rem, 2vw, 3rem)", "ignored function", 0)
  val () = value("var(--size)", "ignored function", 0)
  val () = value("-1em", "ignored negative", 0)
  val () = value("12vw", "ignored unit", 0)
  val () = value("12 px", "ignored unit", 0)
  val () = value("1e3px", "ignored unit", 0)
  val () = value("bigger", "ignored keyword", 0)
  val () = value("px", "ignored keyword", 0)
  val () = value(".", "ignored number", 0)
  val () = value("+", "ignored number", 0)
in () end

fn check_blocks (): void = let
  val () = block("font-size:2em; color:red", "parent", 2000)
  val () = block("color:red;font-size : 3pt", "px", 4000)
  val () = block("Font-Size:12PX", "px", 12000)
  val () = block("font-size:1em !important", "ignored important", 0)
  val () = block("font-size:1em ! important", "ignored important", 0)
  val () = block("font-size:1em;font-size:calc(1px)", "parent", 1000)
  val () = block("font-size:bad;font-size:2em", "parent", 2000)
  val () = block("font-size:bad", "ignored keyword", 0)
  val () = block("font-size:1em;font-size:3em", "parent", 3000)
  val () = block("font-size:1em;font-size:3em !important", "parent", 1000)
  val () = block("color:red", "none", 0)
  val () = block(";;;", "none", 0)
  val () = block("/* font-size:9px */color:red", "none", 0)
  val () = block("font-size:1em;/*x;*/font-size:3em", "parent", 3000)
  val () = block("font-size:/* c */4em", "parent", 4000)
  val () = block("background:url(a;b);font-size:5px", "px", 5000)
  val () = block("font-family:'a;font-size:9px'", "none", 0)
  val () = block("font:12px serif", "none", 0)
  val () = block("font-size-adjust:0.5", "none", 0)
  val () = block("margin:0;font-size:1.5em", "parent", 1500)
in () end

fn check_font_sizes (): void = let
  val () = font_size("1", "px", 10000)
  val () = font_size("2", "px", 13000)
  val () = font_size("3", "px", 16000)
  val () = font_size("4", "px", 18000)
  val () = font_size("5", "px", 24000)
  val () = font_size("6", "px", 32000)
  val () = font_size("7", "px", 48000)
  val () = font_size("+1", "px", 18000)
  val () = font_size("-1", "px", 13000)
  val () = font_size(" +2 ", "px", 24000)
  val () = font_size("+9", "px", 48000)
  val () = font_size("-9", "px", 10000)
  val () = font_size("x", "ignored number", 0)
  val () = font_size("+", "ignored number", 0)
  val () = font_size("3x", "ignored unit", 0)
in () end

(* ---------------- selectors ---------------- *)

(* "supported 102" or why not *)
fn selector_text (read: selector_read): @(string, int) =
  case+ read of
  | ~SelectorSupported(weight) => @("supported", weight)
  | ~SelectorUnsupported(reason) =>
    (case+ reason of
     | UnsupportedEmpty() => @("empty", 0)
     | UnsupportedCombinator() => @("combinator", 0)
     | UnsupportedPseudo() => @("pseudo", 0)
     | UnsupportedAttribute() => @("attribute", 0)
     | UnsupportedUniversal() => @("universal", 0)
     | UnsupportedCharacter() => @("character", 0)
     | UnsupportedTooDeep() => @("too deep", 0))

fn selector {m:pos | m <= 1048576} (text: string(m), kind: string, weight: int): void = let
  val m = g1u2i(string1_length(text))
  val array = text_array(text, m)
  val @(frozen, view) = $A.freeze<byte>(array)
  val @(got_kind, got_weight) = selector_text(selector_specificity_read(view, 0, m))
  val () = expect_text(got_kind, kind, text)
  val () = expect_int(got_weight, weight, text)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn check_selectors (): void = let
  val () = selector("p", "supported", 1)
  val () = selector("html", "supported", 1)
  val () = selector("div.chapter p", "supported", 102)
  val () = selector("#a", "supported", 10000)
  val () = selector(".lead", "supported", 100)
  val () = selector("a.b.c", "supported", 201)
  val () = selector("html body", "supported", 2)
  val () = selector("h1 .a#b", "supported", 10101)
  val () = selector("  p  ", "supported", 1)
  val () = selector("p.Lead_1-x", "supported", 101)
  val () = selector("p > span", "combinator", 0)
  val () = selector("p + span", "combinator", 0)
  val () = selector("p ~ span", "combinator", 0)
  val () = selector("a:hover", "pseudo", 0)
  val () = selector("p:first-child", "supported", 101)
  val () = selector("td:last-child", "supported", 101)
  val () = selector("mtable.aligned mtd:nth-child(odd)", "supported", 202)
  val () = selector("td:nth-child(even)", "supported", 101)
  val () = selector("td:nth-child(3)", "supported", 101)
  val () = selector("td:nth-child(0)", "pseudo", 0)
  val () = selector("td:nth-child(2n)", "pseudo", 0)
  val () = selector("td:nth-child(odd", "pseudo", 0)
  val () = selector("td:nth-child()", "pseudo", 0)
  val () = selector("td:nth-child", "pseudo", 0)
  val () = selector("p::first-line", "pseudo", 0)
  val () = selector("[x]", "attribute", 0)
  val () = selector("a[href]", "attribute", 0)
  val () = selector("*", "universal", 0)
  val () = selector(".", "character", 0)
  val () = selector("#", "character", 0)
  val () = selector("p,q", "character", 0)
  val () = selector(" ", "empty", 0)
  val () = selector("a b c d e f g h", "supported", 8)
  val () = selector("a b c d e f g h i", "too deep", 0)
in () end


(* ---------------- text-align ---------------- *)

fn align_word (align: align_value): string =
  case+ align of
  | AlignNone() => "none"
  | AlignLeft() => "left"
  | AlignRight() => "right"
  | AlignCenter() => "center"

fn align_of {m:pos | m <= 1048576} (block: string(m), wanted: string): void = let
  val m = g1u2i(string1_length(block))
  val array = text_array(block, m)
  val @(frozen, view) = $A.freeze<byte>(array)
  val () = expect_text(align_word(declarations_align_read(view, 0, m)), wanted, block)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn check_aligns (): void = let
  val () = align_of("text-align:right", "right")
  val () = align_of("text-align: -webkit-center", "center")
  val () = align_of(" TEXT-ALIGN : LEFT ; ", "left")
  val () = align_of("color:red;text-align:left;text-align:bogus", "left")
  val () = align_of("text-align:left;text-align:-webkit-right", "right")
  val () = align_of("text-align:right !important", "none")
  val () = align_of("text-align:start", "none")
  val () = align_of("text-align:justify", "none")
  val () = align_of("font-size:2em", "none")
  val () = align_of(" ", "none")
in () end

(* the n-th rule of an alignment sheet: its selector's length and its alignment word *)
fun align_rule_at {sheet_len:int}{count:nat}{i:nat} .<count>.
  (rules: !align_rules(sheet_len, count), i: int i): @(int, string) =
  case+ rules of
  | AlignRulesNil() => @(~1, "none")
  | AlignRulesCons(rule, align, rest) =>
    if i = 0 then @(rule.selector_len, align_word(align)) else align_rule_at(rest, i - 1)

fn check_align_sheets (): void = let
  val sheet = "mtd:nth-child(odd){text-align:right} p{font-size:2em} td.a, th{text-align:center} @media x{td{text-align:left}} td{text-align:start} a:hover{text-align:left}"
  val m = g1u2i(string1_length(sheet))
  val array = text_array(sheet, m)
  val @(frozen, view) = $A.freeze<byte>(array)
  val rules = sheet_aligns_read(view, m)
  val () = expect_int(let
    fun count {s:int}{c:nat} .<c>. (rules: !align_rules(s, c)): int =
      case+ rules of
      | AlignRulesNil() => 0
      | AlignRulesCons(_, _, rest) => 1 + count(rest)
  in count(rules) end, 3, "align sheet: three rules")
  val @(first_len, first) = align_rule_at(rules, 0)
  val () = expect_int(first_len, 18, "align sheet: first selector")
  val () = expect_text(first, "right", "align sheet: first")
  val @(second_len, second) = align_rule_at(rules, 1)
  val () = expect_int(second_len, 4, "align sheet: second selector")
  val () = expect_text(second, "center", "align sheet: second")
  val @(third_len, third) = align_rule_at(rules, 2)
  val () = expect_int(third_len, 2, "align sheet: third selector")
  val () = expect_text(third, "center", "align sheet: third")
  val () = align_rules_free(rules)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* ---------------- style sheets ---------------- *)

(* the nth rule of a sheet as: the selector's length, its specificity,
   its order, the size's basis and thousandths; or all -1 *)
fun rule_at {sheet_len:int}{count:nat}{i:nat} .<count>.
  (rules: !css_rules(sheet_len, count), i: int i): @(int, int, int, string, int) =
  case+ rules of
  | RulesNil() => @(~1, ~1, ~1, "none", ~1)
  | RulesCons(rule, size, rest) =>
    if i = 0 then @(rule.selector_len, rule.specificity, rule.order, basis_text(size.basis), size.thousandths)
    else rule_at(rest, i - 1)

fn sheet_check {m:pos | m <= 1048576} (text: string(m), wanted_count: int, wanted_skipped: int, wanted_end: string): void = let
  val m = g1u2i(string1_length(text))
  val array = text_array(text, m)
  val @(frozen, view) = $A.freeze<byte>(array)
  val ~SheetRead(sheet_end, skipped, rules) = sheet_rules_read(view, m)
  val the_end = (case+ sheet_end of SheetComplete() => "complete" | SheetCutShort() => "cut short")
  val () = expect_int(css_rules_count(rules), wanted_count, text)
  val () = expect_int(skipped, wanted_skipped, text)
  val () = expect_text(the_end, wanted_end, text)
  val () = css_rules_free(rules)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn sheet_rule {m:pos | m <= 1048576}{i:nat} (text: string(m), index: int i, selector_len: int, weight: int, order: int, basis: string, thousandths: int): void = let
  val m = g1u2i(string1_length(text))
  val array = text_array(text, m)
  val @(frozen, view) = $A.freeze<byte>(array)
  val ~SheetRead(_, _, rules) = sheet_rules_read(view, m)
  val @(got_len, got_weight, got_order, got_basis, got_thousandths) = rule_at(rules, index)
  val () = expect_int(got_len, selector_len, text)
  val () = expect_int(got_weight, weight, text)
  val () = expect_int(got_order, order, text)
  val () = expect_text(got_basis, basis, text)
  val () = expect_int(got_thousandths, thousandths, text)
  val () = css_rules_free(rules)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn check_sheets (): void = let
  (* quire#431's book A, with the rem trick on html *)
  val book_a = "html{font-size:62.5%} p{font-size:1.6rem} h1{font-size:2em} h2, h3{font-size:1.5em} small{font-size:.8em}"
  val () = sheet_check(book_a, 6, 0, "complete")
  val () = sheet_rule(book_a, 0, 4, 1, 0, "parent", 625)
  val () = sheet_rule(book_a, 1, 1, 1, 1, "root", 1600)
  val () = sheet_rule(book_a, 3, 2, 1, 3, "parent", 1500)
  val () = sheet_rule(book_a, 4, 2, 1, 4, "parent", 1500)
  val () = sheet_rule(book_a, 5, 5, 1, 5, "parent", 800)
  val () = sheet_rule(book_a, 6, ~1, ~1, ~1, "none", ~1)
  (* quire#431's book B *)
  val book_b = "p{font-size:9pt} h1{font-size:18pt} h2{font-size:13.5pt} small{font-size:7.2pt} .lead{font-size:1.25em}"
  val () = sheet_check(book_b, 5, 0, "complete")
  val () = sheet_rule(book_b, 0, 1, 1, 0, "px", 12000)
  val () = sheet_rule(book_b, 3, 5, 1, 3, "px", 9600)
  val () = sheet_rule(book_b, 4, 5, 100, 4, "parent", 1250)
  (* at-rules are passed over whole *)
  val () = sheet_check("@media print{p{font-size:9px}} @font-face{font-family:x} @import 'a.css'; p{font-size:1em}", 1, 3, "complete")
  (* a rule that is not read is counted, and one with no size is not *)
  val () = sheet_check("p>a{font-size:2em} b{color:red}", 0, 1, "complete")
  val () = sheet_check("b{color:red} i{font-size:bad} u{font-size:2em}", 1, 1, "complete")
  val () = sheet_check("/* a{font-size:1em} */ b{font-size:2em}", 1, 0, "complete")
  val () = sheet_check("a{font-size:1em} /* unterminated", 1, 0, "complete")
  val () = sheet_check("a{font-size:1em", 1, 0, "complete")
  val () = sheet_check("a{font-size:1em} b", 1, 1, "complete")
  val () = sheet_check("a{content:'}';font-size:1em}", 1, 0, "complete")
  val () = sheet_check("}}{{ a{font-size:1em}", 0, 0, "complete")
  (* a selector list shares its block's size *)
  val () = sheet_check("a,b , c{font-size:1em}", 3, 0, "complete")
  val () = sheet_check("a,p>b,c{font-size:1em}", 2, 1, "complete")
in () end

(* ---------------- sizes ---------------- *)

fn declared (basis: size_basis, thousandths: [t:nat | t <= 1000000] int t): size_declared = @{basis= basis, thousandths= thousandths}

fn computed (declared_size: size_declared, parent: size_computed, root: size_computed): size_computed = size_resolve(declared_size, parent, root)

fn check_sizes (): void = let
  (* a pixel size is its own; relative ones are of the parent or the root *)
  val () = expect_int(computed(declared(BasisPixels(), 12000), 16000, 16000), 12000, "9pt")
  val () = expect_int(computed(declared(BasisParent(), 1500), 20000, 16000), 30000, "1.5em of 20px")
  val () = expect_int(computed(declared(BasisRoot(), 2000), 20000, 16000), 32000, "2rem of 16px")
  (* the rem trick, a two step chain: html 62.5% of 16px, p 1.6rem *)
  val html = computed(declared(BasisParent(), 625), 16000, 16000)
  val () = expect_int(html, 10000, "html 62.5%")
  val () = expect_int(size_resolve(declared(BasisRoot(), 1600), 16000, html), 16000, "1.6rem of a root of 10px")
  (* never under a pixel nor over a thousand of them *)
  val () = expect_int(computed(declared(BasisPixels(), 0), 16000, 16000), 1000, "0px")
  val () = expect_int(computed(declared(BasisParent(), 1000000), 1000000, 16000), 1000000, "a thousand times a thousand px")
  val () = expect_int(computed(declared(BasisParent(), 3), 16000, 16000), 1000, "0.003em")
  (* the proportion to the dominant size: twentieths, held from half to three times *)
  val () = expect_int(proportion_of(16000, 16000), 20, "the dominant size")
  val () = expect_int(proportion_of(32000, 16000), 40, "h1 at 2")
  val () = expect_int(proportion_of(24000, 16000), 30, "h2 at 1.5")
  val () = expect_int(proportion_of(12800, 16000), 16, "small at 0.8")
  val () = expect_int(proportion_of(20000, 16000), 25, ".lead at 1.25")
  val () = expect_int(proportion_of(1000, 16000), 10, "font-size:1px is held to half")
  val () = expect_int(proportion_of(64000, 16000), 60, "font-size:400% is held to three times")
  val () = expect_int(proportion_of(1000000, 1000), 60, "the most over the least")
  val () = expect_int(proportion_of(1000, 1000000), 10, "the least under the most")
  val () = expect_int(proportion_of(12000, 12000), 20, "a body of 9pt")
in () end

(* ---------------- many rules, and fuzz ---------------- *)

(* a sheet of 5000 rules gives RULES_MAX of them and says it was cut short *)
fn check_many (): void = let
  val rule = "a{font-size:1em}\n"
  val total = 17 * 5000
  val array = $A.alloc<byte>(total)
  fun fill_rules {l:agz}{i:nat | i <= 5000} .<5000 - i>. (array: !$A.arr(byte, l, 85000), i: int i): void =
    if i >= 5000 then ()
    else let
      fun put {k:nat | k <= 17} .<17 - k>. (array: !$A.arr(byte, l, 85000), k: int k): void =
        if k >= 17 then ()
        else let
          val () = $A.set<byte>(array, 17 * i + k, $A.int2byte($AR.low_byte(char2int0(rule[k]))))
        in put(array, k + 1) end
      val () = put(array, 0)
    in fill_rules(array, i + 1) end
  val () = fill_rules(array, 0)
  val @(frozen, view) = $A.freeze<byte>(array)
  val ~SheetRead(sheet_end, skipped, rules) = sheet_rules_read(view, 85000)
  val () = expect_int(css_rules_count(rules), 4096, "the most rules")
  val () = expect_int(skipped, 904, "the rules past the most")
  val () = expect_text((case+ sheet_end of SheetComplete() => "complete" | SheetCutShort() => "cut short"), "cut short", "the sheet is cut short")
  val () = css_rules_free(rules)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

val _state = ref<[seed:nat | seed < 65536] int seed>(12345)

(* the next number under 65536 (the generator of tests/codec) *)
fn next_number (): [value:nat | value < 65536] int value = let
  val state = !_state
  val product = $AR.mul_g1(state, 25173)
  val next = $AR.band_g1($AR.add_g1(product, 13849), 65535)
  val () = !_state := next
in next end

(* the characters CSS is made of, and the ones that confuse it *)
val _alphabet = "{}();:,.#@*/ !-+%>[]=\\'\"\nabcdpxemrtlfonsizeimportant0123456789qw"

fun fuzz_fill {l:agz}{n:pos}{i:nat | i <= n} .<n - i>. (array: !$A.arr(byte, l, n), n: int n, i: int i): void =
  if i >= n then ()
  else let
    val pick = $AR.band_g1(next_number(), 63)
    val () = $A.set<byte>(array, i, $A.int2byte($AR.low_byte(char2int0(_alphabet[pick]))))
  in fuzz_fill(array, n, i + 1) end

(* random text through every reader: each answers, and a sheet gives at
   most its rules, in the end of its own bytes *)
fn fuzz_once (): void = let
  val n = g1ofg0(1 + $AR.band_g1(next_number(), 255))
in
  if n >= 1 then
    (if n <= 256 then let
       val array = $A.alloc<byte>(n)
       val () = fuzz_fill(array, n, 0)
       val @(frozen, view) = $A.freeze<byte>(array)
       val () = size_read_free(value_size_read(view, 0, n))
       val () = size_read_free(declarations_size_read(view, 0, n))
       val () = size_read_free(font_size_attribute_read(view, 0, n))
       val () = selector_read_free(selector_specificity_read(view, 0, n))
       val ~SheetRead(_, skipped, rules) = sheet_rules_read(view, n)
       val () = (if css_rules_count(rules) <= 4096 then () else fail("more rules than the most"))
       val () = (if skipped >= 0 then () else fail("a negative count"))
       val () = css_rules_free(rules)
       val () = $A.drop<byte>(frozen, view)
     in $A.free<byte>($A.thaw<byte>(frozen)) end
     else ())
  else ()
end

fun fuzz {count:nat} .<count>. (count: int count): void =
  if count <= 0 then () else let val () = fuzz_once() in fuzz(count - 1) end

implement main0 () = let
  val () = check_values()
  val () = check_blocks()
  val () = check_font_sizes()
  val () = check_selectors()
  val () = check_aligns()
  val () = check_align_sheets()
  val () = check_sheets()
  val () = check_sizes()
  val () = check_many()
  val () = fuzz(20000)
in
  if !_failures = 0 then println! ("all ok")
  else println! (!_failures, " failures")
end
