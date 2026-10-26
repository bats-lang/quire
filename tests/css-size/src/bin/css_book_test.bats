#target native

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use file as F
#use result as R
#use xml-tree as X

staload "css_size.sats"
staload "css_cascade.sats"

(* The real book of quire#868 (e2e/calculus101-mathml-test.epub), unzipped by
   run.sh into book/ and read here with the file package: the chapter, the
   sheets its link elements name, in link order, and the Typst sheet. A file
   is read whole into one array (1048576 bytes at most, the sheets joined 65536);
   one that cannot be read fails the run by its path (keyword: publisher alignment). *)

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

(* A file of the book read whole, or not read (said by its path when it failed) *)
datavtype loaded =
  | {l:agz}{n:pos | n <= 1048576} Loaded of ($A.arr(byte, l, n), int n)
  | NotLoaded of ()

fn not_loaded {lp:agz}{pn:pos} (path: !$A.borrow(byte, lp, pn), path_len: int pn, why: string): loaded = let
  val () = print_string("FAIL ")
  val () = put_span(path, 0, path_len, 0)
  val () = println! (": cannot be read, ", why)
  val () = !_failures := !_failures + 1
in NotLoaded() end

(* The file at path read into one array: opened, sized by its descriptor, read, closed *)
fn read_file {lp:agz}{pn:pos | pn < 1048576} (path: !$A.borrow(byte, lp, pn), path_len: int pn): loaded =
  case+ $F.file_open(path, path_len, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.err(reason) => not_loaded(path, path_len, $F.io_error_text(reason))
  | ~$R.ok(file) => let
      val read = (case+ $F.fd_size(file) of
        | ~$R.err(reason) => not_loaded(path, path_len, $F.io_error_text(reason))
        | ~$R.ok(size) =>
          if size <= 0 then not_loaded(path, path_len, "it is empty")
          else if size > 1048576 then not_loaded(path, path_len, "it is over 1048576 bytes")
          else let
            val array = $A.alloc<byte>(size)
          in
            case+ $F.file_read(file, array, size) of
            | ~$R.err(reason) => let
                val () = $A.free<byte>(array)
              in not_loaded(path, path_len, $F.io_error_text(reason)) end
            | ~$R.ok(count) =>
              if count = size then Loaded(array, size)
              else let
                val () = $A.free<byte>(array)
              in not_loaded(path, path_len, "it was read short") end
          end): loaded
      val () = $R.discard<int><$F.io_error>($F.file_close(file))
    in read end

(* The file named by a literal path, read *)
fn read_named {m:pos | m < 1048576} (name: string(m)): loaded = let
  val m = g1u2i(string1_length(name))
  val path = text_array(name, m)
  val @(frozen, view) = $A.freeze<byte>(path)
  val read = read_file(view, m)
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in read end

(* The text put in the array from off on *)
fun put_text {l:agz}{size:pos}{m:nat}{off:nat | off + m <= size}{j:nat | j <= m} .<m - j>.
  (array: !$A.arr(byte, l, size), text: string(m), m: int m, off: int off, j: int j): void =
  if j >= m then ()
  else let
    val () = $A.set<byte>(array, off + j, $A.int2byte($AR.low_byte(char2int0(text[j]))))
  in put_text(array, text, m, off, j + 1) end

(* The bytes src[at, at + len) put in the array from off on *)
fun put_span_in {ls:agz}{n:pos}{ld:agz}{size:pos}{at,len,off:nat | at + len <= n; off + len <= size}{j:nat | j <= len} .<len - j>.
  (src: !$A.borrow(byte, ls, n), at: int at, len: int len, array: !$A.arr(byte, ld, size), off: int off, j: int j): void =
  if j >= len then ()
  else let
    val () = $A.set<byte>(array, off + j, $A.read<byte>(src, at + j))
  in put_span_in(src, at, len, array, off, j + 1) end

(* Whether data[at, at + len) is word, to the letter *)
fun word_at {l:agz}{n:pos}{at,len:nat | at + len <= n}{m:nat}{i:nat | i <= m} .<m - i>.
  (data: !$A.borrow(byte, l, n), at: int at, len: int len, word: string(m), m: int m, i: int i): bool =
  if i >= m then true
  else if i >= len then false
  else if byte2int0($A.read<byte>(data, at + i)) = char2int0(word[i]) then word_at(data, at, len, word, m, i + 1)
  else false

fn is_word {l:agz}{n:pos}{at,len:nat | at + len <= n}{m:nat}
  (data: !$A.borrow(byte, l, n), at: int at, len: int len, word: string(m), m: int m): bool =
  if len = m then word_at(data, at, len, word, m, 0) else false

(* The value of the attribute named word, as where it is and its length; (0, 0) when there is none *)
fun attribute_value {l:agz}{n:pos}{count:nat}{m:nat} .<count>.
  (data: !$A.borrow(byte, l, n), attrs: !$X.xml_attr_list(n, count), word: string(m), m: int m)
  : [at,len:nat | at + len <= n] @(int at, int len) =
  case+ attrs of
  | $X.xml_attrs_cons(name_at, name_len, value_at, value_len, rest) =>
    if is_word(data, name_at, name_len, word, m) then @(value_at, value_len)
    else attribute_value(data, rest, word, m)
  | $X.xml_attrs_nil() => @(0, 0)

(* The places of the chapter's stylesheet links, in the order of the document *)
datavtype links(n:int, count:int) =
  | LinksNil(n, 0) of ()
  | {count:nat}{at:nat}{len:pos | at + len <= n} LinksCons(n, count + 1) of (int at, int len, links(n, count))

fun links_free {n:int}{count:nat} .<count>. (found: links(n, count)): void =
  case+ found of
  | ~LinksNil() => ()
  | ~LinksCons(_, _, rest) => links_free(rest)

(* The href of every link element whose rel is stylesheet, put before the links of tail in document order *)
fun collect_links {l:agz}{n:pos}{sz:nat}{count:nat} .<sz>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, sz), tail: links(n, count)): [total:nat] links(n, total) =
  case+ nodes of
  | $X.xml_nodes_nil() => tail
  | $X.xml_nodes_cons(node, rest) => let
      val after = collect_links(data, rest, tail)
    in
      case+ node of
      | $X.xml_text(_, _) => after
      | $X.xml_element(name_at, name_len, attrs, children) => let
          val inner = collect_links(data, children, after)
        in
          if is_word(data, name_at, name_len, "link", 4) then let
            val @(rel_at, rel_len) = attribute_value(data, attrs, "rel", 3)
            val @(href_at, href_len) = attribute_value(data, attrs, "href", 4)
          in
            if is_word(data, rel_at, rel_len, "stylesheet", 10) then
              (if href_len > 0 then LinksCons(href_at, href_len, inner) else inner)
            else inner
          end
          else inner
        end
    end

(* Whether the last link is the one named word *)
fun last_link_is {l:agz}{n:pos}{count:nat}{m:nat} .<count>.
  (data: !$A.borrow(byte, l, n), found: !links(n, count), word: string(m), m: int m): bool =
  case+ found of
  | LinksNil() => false
  | LinksCons(at, len, rest) =>
    (case+ rest of
     | LinksNil() => is_word(data, at, len, word, m)
     | LinksCons(_, _, _) => last_link_is(data, rest, word, m))

(* The file a link names, in the book's directory *)
fn read_linked {lc:agz}{nc:pos}{at:nat}{len:pos | at + len <= nc} (chapter: !$A.borrow(byte, lc, nc), at: int at, len: int len): loaded =
  if len + 5 < 1048576 then let
    val path = $A.alloc<byte>(len + 5)
    val () = put_text(path, "book/", 5, 0, 0)
    val () = put_span_in(chapter, at, len, path, 5, 0)
    val @(frozen, view) = $A.freeze<byte>(path)
    val read = read_file(view, len + 5)
    val () = $A.drop<byte>(frozen, view)
    val () = $A.free<byte>($A.thaw<byte>(frozen))
  in read end
  else let
    val () = fail("a stylesheet link of the chapter is over 1048570 bytes")
  in NotLoaded() end

(* The linked sheets put in the array one after the other, each ended by a
   line feed, from used on; the bytes used afterwards *)
fun join_sheets {lc:agz}{nc:pos}{count:nat}{ld:agz}{used:nat | used <= 65536} .<count>.
  (chapter: !$A.borrow(byte, lc, nc), found: !links(nc, count), joined: !$A.arr(byte, ld, 65536), used: int used)
  : [after:nat | after <= 65536] int after =
  case+ found of
  | LinksNil() => used
  | LinksCons(at, len, rest) =>
    (case+ read_linked(chapter, at, len) of
     | ~NotLoaded() => join_sheets(chapter, rest, joined, used)
     | ~Loaded(sheet, size) => let
         val @(frozen, view) = $A.freeze<byte>(sheet)
         val after = (if used + size + 1 <= 65536 then let
             val () = put_span_in(view, 0, size, joined, used, 0)
             val () = $A.set<byte>(joined, used + size, $A.int2byte(10))
           in used + size + 1 end
           else let
             val () = fail("the sheets the chapter links are over 65536 bytes together")
           in used end): [after:nat | after <= 65536] int after
         val () = $A.drop<byte>(frozen, view)
         val () = $A.free<byte>($A.thaw<byte>(frozen))
       in join_sheets(chapter, rest, joined, after) end)

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

fn check_rules {lt:agz}{tn:pos} (typst: !$A.borrow(byte, lt, tn), typst_len: int tn): void = let
  val rules = sheet_aligns_read(typst, typst_len)
  val () = put_rules(typst, rules)
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
in $A.free<byte>($A.thaw<byte>(dropped_frozen)) end

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
fn aligned_check {ld:agz}{n:pos}{ls:agz}{m:pos}{w:nat}
  (doc_view: !$A.borrow(byte, ld, n), n: int n, sheet_view: !$A.borrow(byte, ls, m), m: int m, wanted: string(w), what: string): void = let
  val w = g1u2i(string1_length(wanted))
  val nodes = $X.parse_document(doc_view, n)
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
in $X.free_nodes(nodes) end

(* A document given as text, under the sheet *)
fn aligned_check_text {n:pos | n <= 1048576}{ls:agz}{m:pos}{w:nat}
  (doc: string(n), sheet_view: !$A.borrow(byte, ls, m), m: int m, wanted: string(w), what: string): void = let
  val n = g1u2i(string1_length(doc))
  val doc_array = text_array(doc, n)
  val @(doc_frozen, doc_view) = $A.freeze<byte>(doc_array)
  val () = aligned_check(doc_view, n, sheet_view, m, wanted, what)
  val () = $A.drop<byte>(doc_frozen, doc_view)
in $A.free<byte>($A.thaw<byte>(doc_frozen)) end

(* The classes of the Typst sheet under .typst-math, on a table or on a cell, and a table outside it *)
fn check_classes {lt:agz}{tn:pos} (typst: !$A.borrow(byte, lt, tn), typst_len: int tn): void = let
  val () = aligned_check_text(
    "<div class=\"typst-math\"><math><mtable class=\"right-align\"><mtr><mtd>a</mtd></mtr></mtable><mtable class=\"left-align\"><mtr><mtd>b</mtd><mtd class=\"right-align\">c</mtd></mtr></mtable><mtable><mtr><mtd class=\"left-align\">d</mtd></mtr></mtable></math></div>",
    typst, typst_len, "rlrl", "the classes under typst-math")
in aligned_check_text("<div><math><mtable class=\"cases\"><mtr><mtd>a</mtd></mtr></mtable></math></div>", typst, typst_len, "", "outside typst-math") end

(* The chapter under the sheets it links, joined; the last of them is the Typst sheet *)
fn check_joined {lc:agz}{nc:pos}{count:nat}{ld:agz}{used:nat | used <= 65536}
  (chapter: !$A.borrow(byte, lc, nc), chapter_len: int nc, found: !links(nc, count), joined: $A.arr(byte, ld, 65536), used: int used): void =
  if used <= 0 then let
    val () = fail("book/index.xhtml: no stylesheet link is read")
  in $A.free<byte>(joined) end
  else let
    val () = (if last_link_is(chapter, found, "_static/sphinx-typst-math.css", 29) then ()
      else fail("book/index.xhtml: the last stylesheet link is not _static/sphinx-typst-math.css"))
    val @(frozen, view) = $A.freeze<byte>(joined)
    val @(sheets, rest) = $A.borrow_split<byte>(frozen, view, used)
    val () = aligned_check(chapter, chapter_len, sheets, used, "rlrlllll", "the real chapter, in document order")
    val whole = $A.borrow_join<byte>(frozen, sheets, rest)
    val () = $A.drop<byte>(frozen, whole)
  in $A.free<byte>($A.thaw<byte>(frozen)) end

fn check_chapter {lt:agz}{tn:pos} (typst: !$A.borrow(byte, lt, tn), typst_len: int tn): void =
  case+ read_named("book/index.xhtml") of
  | ~NotLoaded() => ()
  | ~Loaded(array, n) => let
      val @(frozen, view) = $A.freeze<byte>(array)
      val nodes = $X.parse_document(view, n)
      val found = collect_links(view, nodes, LinksNil())
      val joined = $A.alloc<byte>(65536)
      val used = join_sheets(view, found, joined, 0)
      val () = check_joined(view, n, found, joined, used)
      val () = links_free(found)
      val () = $X.free_nodes(nodes)
      val () = $A.drop<byte>(frozen, view)
    in $A.free<byte>($A.thaw<byte>(frozen)) end

implement main0 () = let
  val () = (case+ read_named("book/_static/sphinx-typst-math.css") of
    | ~NotLoaded() => ()
    | ~Loaded(array, size) => let
        val @(frozen, view) = $A.freeze<byte>(array)
        val () = check_rules(view, size)
        val () = check_chapter(view, size)
        val () = check_classes(view, size)
        val () = $A.drop<byte>(frozen, view)
      in $A.free<byte>($A.thaw<byte>(frozen)) end)
in
  if !_failures = 0 then println! ("all ok")
  else println! (!_failures, " failures")
end
