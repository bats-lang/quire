#target native

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use xml-tree as X

staload "css_size.sats"
staload "css_cascade.sats"

(* The real book of quire#868 (e2e/calculus101-mathml-test.epub), played on
   bytes: tests/css-size/run.sh puts the book's sheets (the sheets its chapter
   links, joined in order, each ended by a line feed) in BOOK_SHEETS, the
   Typst sheet alone in TYPST_SHEET and the chapter in BOOK_CHAPTER. It prints
   the alignment rules the reader handles, the one it leaves dropped and why,
   and the alignments the cascade gives the chapter's tables
   (keyword: publisher alignment). *)

val _failures = ref<int>(0)

fn fail (what: string): void = let
  val () = println! ("FAIL ", what)
in !_failures := !_failures + 1 end

fn expect_int (got: int, wanted: int, what: string): void =
  if got = wanted then () else let
    val () = println! ("  ", what, ": wanted ", wanted, ", got ", got)
  in fail(what) end

fn expect_text (got: string, wanted: string, what: string): void =
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

fn align_word (align: align_value): string =
  case+ align of
  | AlignNone() => "none"
  | AlignLeft() => "left"
  | AlignRight() => "right"
  | AlignCenter() => "center"

(* the bytes data[at, at + len) printed *)
fun put_span {l:agz}{n:pos}{at,len:nat | at + len <= n}{k:nat | k <= len} .<len - k>.
  (data: !$A.borrow(byte, l, n), at: int at, len: int len, k: int k): void =
  if k >= len then ()
  else let
    val () = print_char(int2char0($AR.low_byte(byte2int0($A.read<byte>(data, at + k)))))
  in put_span(data, at, len, k + 1) end

(* the rules the reader handles, each with its alignment *)
fun put_rules {sheet_len:pos}{count:nat}{l:agz} .<count>.
  (data: !$A.borrow(byte, l, sheet_len), rules: !align_rules(sheet_len, count)): void =
  case+ rules of
  | AlignRulesNil() => ()
  | AlignRulesCons(rule, align, rest) => let
      val () = print_string("  handled: ")
      val () = put_span(data, rule.selector_at, rule.selector_len, 0)
      val () = println! (" -> ", align_word(align))
    in put_rules(data, rest) end

fun count_rules {sheet_len:int}{count:nat} .<count>. (rules: !align_rules(sheet_len, count)): int =
  case+ rules of
  | AlignRulesNil() => 0
  | AlignRulesCons(_, _, rest) => 1 + count_rules(rest)

fun rule_align {sheet_len:int}{count:nat}{i:nat} .<count>. (rules: !align_rules(sheet_len, count), i: int i): string =
  case+ rules of
  | AlignRulesNil() => "none"
  | AlignRulesCons(_, align, rest) => if i = 0 then align_word(align) else rule_align(rest, i - 1)

fn selector_reason (read: selector_read): string =
  case+ read of
  | ~SelectorSupported(_) => "supported"
  | ~SelectorUnsupported(reason) =>
    (case+ reason of
     | UnsupportedEmpty() => "empty"
     | UnsupportedCombinator() => "combinator"
     | UnsupportedPseudo() => "pseudo-class not read"
     | UnsupportedAttribute() => "attribute"
     | UnsupportedUniversal() => "universal"
     | UnsupportedCharacter() => "character"
     | UnsupportedTooDeep() => "too deep")

fn check_rules (): void = let
  val sheet = "@@TYPST_SHEET@@"
  val m = g1u2i(string1_length(sheet))
  val array = text_array(sheet, m)
  val @(frozen, view) = $A.freeze<byte>(array)
  val rules = sheet_aligns_read(view, m)
  val () = put_rules(view, rules)
  val () = expect_int(count_rules(rules), 8, "the Typst sheet: handled alignment rules")
  val () = expect_text(rule_align(rules, 0), "right", "right-align table")
  val () = expect_text(rule_align(rules, 1), "right", "right-align cell")
  val () = expect_text(rule_align(rules, 2), "right", "left-align table, right-align cell")
  val () = expect_text(rule_align(rules, 3), "right", "aligned, odd")
  val () = expect_text(rule_align(rules, 4), "left", "cases")
  val () = expect_text(rule_align(rules, 5), "left", "left-align table")
  val () = expect_text(rule_align(rules, 6), "left", "left-align cell")
  val () = expect_text(rule_align(rules, 7), "left", "aligned, even")
  val () = align_rules_free(rules)
  val dropped = ".typst-math math:is(:not([display])) > mtable.multiline-equation mtd"
  val d = g1u2i(string1_length(dropped))
  val dropped_array = text_array(dropped, d)
  val @(dropped_frozen, dropped_view) = $A.freeze<byte>(dropped_array)
  val () = println! ("  dropped: ", dropped, " (", selector_reason(selector_specificity_read(dropped_view, 0, d)), ")")
  val () = $A.drop<byte>(dropped_frozen, dropped_view)
  val () = $A.free<byte>($A.thaw<byte>(dropped_frozen))
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* The alignments of a map printed, in the order of the document *)
fun put_words {count:nat} .<count>. (map: !align_map(count)): void =
  case+ map of
  | AlignMapNil() => println! ()
  | AlignMapCons(_, align, rest) => let
      val () = print_string(align_word(align))
      val () = print_string(" ")
    in put_words(rest) end

fn letter_of (align: align_value): int =
  case+ align of
  | AlignNone() => 110
  | AlignLeft() => 108
  | AlignRight() => 114
  | AlignCenter() => 99

(* Whether the map holds the alignments wanted, a letter each (l, r or c), from the i-th on *)
fun sequence_is {count:nat}{m:nat}{i:nat | i <= m} .<count>.
  (map: !align_map(count), wanted: string(m), m: int m, i: int i): bool =
  case+ map of
  | AlignMapNil() => i >= m
  | AlignMapCons(_, align, rest) =>
    if i >= m then false
    else if letter_of(align) = char2int0(wanted[i]) then sequence_is(rest, wanted, m, i + 1)
    else false

(* The tables of the document under the sheet, their alignments printed and checked against wanted *)
fn aligned_check {n,m:pos}{w:nat | n <= 1048576; m <= 1048576} (doc: string(n), sheet: string(m), wanted: string(w), what: string): void = let
  val n = g1u2i(string1_length(doc))
  val m = g1u2i(string1_length(sheet))
  val w = g1u2i(string1_length(wanted))
  val doc_array = text_array(doc, n)
  val @(doc_frozen, doc_view) = $A.freeze<byte>(doc_array)
  val nodes = $X.parse_document(doc_view, n)
  val sheet_array = text_array(sheet, m)
  val @(sheet_frozen, sheet_view) = $A.freeze<byte>(sheet_array)
  val ~SheetRead(_, _, rules) = sheet_rules_read(sheet_view, m)
  val aligns = sheet_aligns_read(sheet_view, m)
  val @(sizes, map) = chapter_maps(doc_view, nodes, sheet_view, rules, aligns, 16000, 16000)
  val () = print_string("  ")
  val () = print_string(what)
  val () = print_string(": ")
  val () = put_words(map)
  val () = (if sequence_is(map, wanted, w, 0) then () else fail(what))
  val () = size_map_free(sizes)
  val () = align_map_free(map)
  val () = css_rules_free(rules)
  val () = align_rules_free(aligns)
  val () = $A.drop<byte>(sheet_frozen, sheet_view)
  val () = $A.free<byte>($A.thaw<byte>(sheet_frozen))
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(doc_frozen, doc_view)
in $A.free<byte>($A.thaw<byte>(doc_frozen)) end

fn check_chapter (): void = let
  (* the chapter of the book: the aligned table, then the matrix (no class, no rule) and the cases table *)
  val () = aligned_check("@@CHAPTER@@", "@@BOOK_SHEETS@@", "rlrlllll", "the real chapter, in document order")
  (* the classes of the sheet under .typst-math, on a table or on a cell *)
  val () = aligned_check(
    "<div class=\"typst-math\"><math><mtable class=\"right-align\"><mtr><mtd>a</mtd></mtr></mtable><mtable class=\"left-align\"><mtr><mtd>b</mtd><mtd class=\"right-align\">c</mtd></mtr></mtable><mtable><mtr><mtd class=\"left-align\">d</mtd></mtr></mtable></math></div>",
    "@@TYPST_SHEET@@", "rlrl", "the classes under typst-math")
  (* a table outside .typst-math is not reached by the sheet's rules *)
  val () = aligned_check("<div><math><mtable class=\"cases\"><mtr><mtd>a</mtd></mtr></mtable></math></div>", "@@TYPST_SHEET@@", "", "outside typst-math")
in () end

implement main0 () = let
  val () = check_rules()
  val () = check_chapter()
in
  if !_failures = 0 then println! ("all ok")
  else println! (!_failures, " failures")
end
