(* publisher_size -- the size most of a book's text is set in, measured when
   the book opens

   quire#431, stage 2. Each of a bounded sample of the book's chapters is
   read: its `<link rel=stylesheet>` sheets (the entries they name, read
   and joined) and its `<style>` texts, matched by src/css_cascade.bats
   against its elements, and the characters set in each size are tallied
   over the sample. The size with the most characters is the book's
   dominant size, kept in memory for the open book (it is derived from the
   book's file by an algorithm that will widen, so it is not stored: a
   stored number would go stale at each change, and re-measuring costs
   the sample's reading, the decision on quire#431). It reaches no page
   yet (stage 3 uses it).

   The sample: at most SAMPLE_MAX chapters at an even stride through the
   spine (all of them in a book of that many or fewer), so front matter
   does not stand for the book. Each chapter's sheets are at most
   SHEET_BYTES_MAX bytes joined; a sheet past that is not read. The chapter
   is read twice when it links to sheets (once to find their entries, once
   to match them): the entries are awaited between, and a chapter's tree
   and bytes do not wait with them. A chapter or sheet that cannot be read
   is passed over, as the measure is a statistic. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use promise as P
#use xml-tree as X
#use zip as Z

staload "xhtml_parse.sats"
staload "paths.sats"
staload "book.sats"
staload "css_size.sats"
staload "css_cascade.sats"

(* The chapters measured at most *)
stadef SAMPLE_MAX = 16
#define SAMPLE_MAX 16

(* The most bytes of style sheets a chapter's are joined to *)
#define SHEET_BYTES_MAX 524288

(* The most bytes of chapters (decompressed) the sample reads in all, and
   the most a chapter may be compressed: a book of one chapter of megabytes
   is not measured (the open waits for the measure) *)
#define SAMPLE_BYTES_MAX 1048576
#define CHAPTER_COMPRESSED_MAX 524288

#pub datatype measured = Measured

implement $P.dispose<measured>(_) = ()

(* ============================================================
   What is kept
   ============================================================ *)

(* The measure's number: a new one drops the answers of the one before *)
val _generation = ref<int>(0)

(* The dominant size of the open book in thousandths of a pixel, 0 when
   none is measured *)
val _dominant = ref<int>(0)

(* The bytes of chapters the sample may still read *)
val _budget = ref<int>(0)

#pub fn publisher_dominant_size (): int

implement publisher_dominant_size () = !_dominant

(* The characters tallied so far, by size, while a book is measured *)
datavtype tally_cell = {count:nat} TallyCell of size_tally(count)

val _tally = ref<tally_cell>(TallyCell(tally_new()))

fn _tally_take (): tally_cell = let
  var cell: tally_cell = TallyCell(tally_new())
  val () = ref_exch_elt<tally_cell>(_tally, cell)
in cell end

fn _tally_put (new_cell: tally_cell): void = let
  var cell: tally_cell = new_cell
  val () = ref_exch_elt<tally_cell>(_tally, cell)
  val+ ~TallyCell(old) = cell
in tally_free(old) end

(* ============================================================
   Style sheets joined
   ============================================================ *)

(* The sheets read so far of a chapter, joined (each ended by a line feed) *)
datavtype sheet_acc =
  | NoSheets of ()
  | {sheet_size:pos}{arena_loc,piece_loc:agz}
    SheetsHeld of (piece_owner(sheet_size, arena_loc), $A.arrx(byte, piece_loc, sheet_size, arena_loc), int sheet_size)

implement $P.dispose<sheet_acc>(acc) =
  case+ acc of
  | ~NoSheets() => ()
  | ~SheetsHeld(owner, held, _) => piece_free(owner, held)

fn _acc_free (acc: sheet_acc): void =
  case+ acc of
  | ~NoSheets() => ()
  | ~SheetsHeld(owner, held, _) => piece_free(owner, held)

(* to[to_at, to_at + len) := from[from_at, from_at + len), from k on *)
fun _copy_range {to_loc:agz}{to_owner:addr}{to_size:pos}{from_loc:agz}{from_size:pos}{to_at,from_at,len:nat | to_at + len <= to_size; from_at + len <= from_size}{k:nat | k <= len} .<len - k>.
  (to: !$A.arrx(byte, to_loc, to_size, to_owner), to_at: int to_at, from: !$A.borrow(byte, from_loc, from_size), from_at: int from_at, len: int len, k: int k): void =
  if k >= len then ()
  else let
    val () = $A.set<byte>(to, to_at + k, $A.read<byte>(from, from_at + k))
  in _copy_range(to, to_at, from, from_at, len, k + 1) end

(* The joined sheets with from[at, at + len) after them; the same when
   there is no room *)
fn _acc_append {from_loc:agz}{from_size:pos}{at,len:nat | at + len <= from_size}
  (acc: sheet_acc, from: !$A.borrow(byte, from_loc, from_size), at: int at, len: int len): sheet_acc =
  if len <= 0 then acc
  else
    (case+ acc of
     | ~NoSheets() => let
         val total = len + 1
       in
         if total > SHEET_BYTES_MAX then NoSheets()
         else if total <= 0 then NoSheets()
         else
           (case+ piece_new(total) of
            | ~NoPiece() => NoSheets()
            | ~Piece(owner, held) => let
                val () = _copy_range(held, 0, from, at, len, 0)
                val () = $A.set<byte>(held, len, $A.int2byte(10))
              in SheetsHeld(owner, held, total) end)
       end
     | ~SheetsHeld(old_owner, old_held, old_size) => let
         val total = old_size + len + 1
       in
         if total > SHEET_BYTES_MAX then SheetsHeld(old_owner, old_held, old_size)
         else if total <= 0 then SheetsHeld(old_owner, old_held, old_size)
         else
           (case+ piece_new(total) of
            | ~NoPiece() => SheetsHeld(old_owner, old_held, old_size)
            | ~Piece(owner, held) => let
                val @(old_frozen, old_view) = $A.freeze<byte>(old_held)
                val () = _copy_range(held, 0, old_view, 0, old_size, 0)
                val () = $A.drop<byte>(old_frozen, old_view)
                val () = piece_free(old_owner, $A.thaw<byte>(old_frozen))
                val () = _copy_range(held, old_size, from, at, len, 0)
                val () = $A.set<byte>(held, old_size + len, $A.int2byte(10))
              in SheetsHeld(owner, held, total) end)
       end)

fun _append_spans {from_loc:agz}{from_size:pos}{count:nat} .<count>.
  (acc: sheet_acc, from: !$A.borrow(byte, from_loc, from_size), spans: !span_list(from_size, count)): sheet_acc =
  case+ spans of
  | SpanNil() => acc
  | SpanCons(at, len, rest) => _append_spans(_acc_append(acc, from, at, len), from, rest)

(* ============================================================
   The sheets a chapter links to
   ============================================================ *)

(* The entries of the sheets a chapter links to, count of them, in the
   document's order *)
datavtype link_entries(file_size:int, count:int) =
  | LinksNil(file_size, 0) of ()
  | {count:nat}{data_offset:nat}{data_size:pos | data_offset + data_size <= file_size; data_size <= 268435456}
    LinksCons(file_size, count + 1) of (int data_offset, int data_size, $Z.compression, link_entries(file_size, count))

(* What was found of a chapter's links in pass pass: nothing was looked for
   (pass 0, the sheets are joined already) or these entries (pass 1) *)
datavtype link_search(file_size:int, pass:int) =
  | LinksSkipped(file_size, 0) of ()
  | {count:nat} LinksFound(file_size, 1) of (link_entries(file_size, count))

datavtype link_entries_found(file_size:int) =
  | {count:nat} LinksListed(file_size) of (link_entries(file_size, count))

fun _entries_free {file_size:int}{count:nat} .<count>. (entries: link_entries(file_size, count)): void =
  case+ entries of
  | ~LinksNil() => ()
  | ~LinksCons(_, _, _, rest) => _entries_free(rest)

fun _entries_reversed {file_size:int}{a,b:nat} .<a>.
  (entries: link_entries(file_size, a), onto: link_entries(file_size, b)): link_entries(file_size, a + b) =
  case+ entries of
  | ~LinksNil() => onto
  | ~LinksCons(offset, size, method, rest) => _entries_reversed(rest, LinksCons(offset, size, method, onto))

(* The entries the hrefs spans name, relative to the chapter whose name
   is at name_offset (dir_len bytes of it are its directory), the last of
   the spans first (so_far reversed) *)
fun _entries_of {file_size:pos}{name_offset,dir_len:nat | name_offset + dir_len <= file_size; dir_len < 65536}{l:agz}{n:pos}{count:nat}{kept:nat} .<count>.
  (serial: int, file_size: int file_size, name_offset: int name_offset, dir_len: int dir_len,
   data: !$A.borrow(byte, l, n), n: int n, spans: !span_list(n, count), so_far: link_entries(file_size, kept)): link_entries_found(file_size) =
  case+ spans of
  | SpanNil() => LinksListed(so_far)
  | SpanCons(at, len, rest) => let
      val path_end = src_end(data, at, len)
    in
      if path_end <= 0 then _entries_of(serial, file_size, name_offset, dir_len, data, n, rest, so_far)
      else
        (case+ book_find_relative(serial, file_size, name_offset, dir_len, data, n, at, path_end) of
         | ~EntryHit(data_offset, data_size, method, _, _) =>
           _entries_of(serial, file_size, name_offset, dir_len, data, n, rest, LinksCons(data_offset, data_size, method, so_far))
         | ~EntryMiss() => _entries_of(serial, file_size, name_offset, dir_len, data, n, rest, so_far))
    end

(* The sheets of the entries, read and added to acc in turn *)
fun _entries_read {file_size:pos}{count:nat} .<count>. (serial: int, file_size: int file_size, entries: link_entries(file_size, count), acc: sheet_acc): $P.promise(sheet_acc, $P.Chained) =
  case+ entries of
  | ~LinksNil() => $P.ret<sheet_acc>(acc)
  | ~LinksCons(data_offset, data_size, method, rest) =>
    (case+ piece_new(data_size) of
     | ~NoPiece() => _entries_read(serial, file_size, rest, acc)
     | ~Piece(compressed_owner, compressed) => let
         val _ = book_read(serial, file_size, data_offset, compressed, data_size)
         val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
         val decompressing = decompress(compressed_bytes, data_size, zip_compression(method))
         val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
         val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))
       in
         $P.and_then<decompressed><sheet_acc>(decompressing, llam(inflated) =>
           case+ take_text(inflated) of
           | ~NoContentBytes() => _entries_read(serial, file_size, rest, acc)
           | ~ContentBytes(owner, held, size) => let
               val @(frozen, view) = $A.freeze<byte>(held)
               val joined = _acc_append(acc, view, 0, size)
               val () = $A.drop<byte>(frozen, view)
               val () = piece_free(owner, $A.thaw<byte>(frozen))
             in _entries_read(serial, file_size, rest, joined) end)
       end)

(* ============================================================
   One chapter
   ============================================================ *)

(* The chapter's characters, tallied by the size they are set in, under
   the sheets joined in acc (freed) and the chapter's own style elements *)
fn _chapter_tallied {l:agz}{n:pos}{sz:nat} (xhtml: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, sz), acc: sheet_acc): void = let
  val styles = sheet_style_spans(xhtml, nodes)
  val joined = _append_spans(acc, xhtml, styles)
  val () = span_list_free(styles)
  val ~TallyCell(tally) = _tally_take()
in
  case+ joined of
  | ~NoSheets() => _tally_put(TallyCell(chapter_tally_unstyled(xhtml, nodes, tally)))
  | ~SheetsHeld(owner, held, size) => let
      val @(frozen, sheet) = $A.freeze<byte>(held)
      val ~SheetRead(_, _, rules) = sheet_rules_read(sheet, size)
      val tally = chapter_tally(xhtml, nodes, sheet, rules, tally)
      val () = css_rules_free(rules)
      val () = $A.drop<byte>(frozen, sheet)
      val () = piece_free(owner, $A.thaw<byte>(frozen))
    in _tally_put(TallyCell(tally)) end
end

(* Whether the sheets a chapter links to are in the joined sheets already,
   or are still to be found (the chapter is then read again) *)
datatype link_pass(pass:int) =
  | LinksUnknown(1)
  | LinksKnown(0)

(* The entries a chapter links to, in the document's order: none when the
   sheets are known already *)
fn _links_found {file_size:pos}{name_offset,dir_len:nat | name_offset + dir_len <= file_size; dir_len < 65536}{l:agz}{n:pos}{sz:nat}{pass:nat}
  (serial: int, file_size: int file_size, name_offset: int name_offset, dir_len: int dir_len,
   xhtml: !$A.borrow(byte, l, n), n: int n, nodes: !$X.xml_node_list(n, sz), links: link_pass(pass)): link_search(file_size, pass) =
  case+ links of
  | LinksKnown() => LinksSkipped()
  | LinksUnknown() => let
      val spans = sheet_link_spans(xhtml, nodes)
      val ~LinksListed(found) = _entries_of(serial, file_size, name_offset, dir_len, xhtml, n, spans, LinksNil())
      val () = span_list_free(spans)
    in LinksFound(_entries_reversed(found, LinksNil())) end

(* Whether a chapter of size bytes is over what the sample may still read
   (only the first reading of a chapter spends it) *)
fn _over_budget {pass:nat} (links: link_pass(pass), size: int): bool =
  case+ links of
  | LinksKnown() => false
  | LinksUnknown() => size > !_budget

fn _budget_spend {pass:nat} (links: link_pass(pass), size: int): void =
  case+ links of
  | LinksKnown() => ()
  | LinksUnknown() => !_budget := !_budget - size

(* Measures chapter chapter_index of book serial *)
fun _chapter_measure {chapter_index:nat}{pass:nat | pass <= 1} .<pass>.
  (serial: int, chapter_index: int chapter_index, generation: int, acc: sheet_acc, links: link_pass(pass)): $P.promise(measured, $P.Chained) =
  if generation <> !_generation then let
    val () = _acc_free(acc)
  in $P.ret<measured>(Measured()) end
  else
    (case+ book_chapter_get(serial, chapter_index) of
     | ~ChaptersUnknown() => let val () = _acc_free(acc) in $P.ret<measured>(Measured()) end
     | ~ChapterNone(_) => let val () = _acc_free(acc) in $P.ret<measured>(Measured()) end
     | ~ChapterGot(file_size, chapter_start, compressed_size, method, name_offset, _, dir_len, _, _) =>
       if compressed_size > CHAPTER_COMPRESSED_MAX then let val () = _acc_free(acc) in $P.ret<measured>(Measured()) end
       else
       (case+ piece_new(compressed_size) of
        | ~NoPiece() => let val () = _acc_free(acc) in $P.ret<measured>(Measured()) end
        | ~Piece(compressed_owner, compressed) => let
            val chapter_sum = book_entry_sum(serial, name_offset)
            val _ = book_read(serial, file_size, chapter_start, compressed, compressed_size)
            val @(compressed_frozen, compressed_bytes) = $A.freeze<byte>(compressed)
            val decompressing = decompress(compressed_bytes, compressed_size, zip_compression(method))
            val () = $A.drop<byte>(compressed_frozen, compressed_bytes)
            val () = piece_free(compressed_owner, $A.thaw<byte>(compressed_frozen))
          in
            $P.and_then<decompressed><measured>(decompressing, llam(inflated) =>
              case+ take_text_sum(inflated, chapter_sum) of
              | ~NoContentBytes() => let val () = _acc_free(acc) in $P.ret<measured>(Measured()) end
              | ~ContentBytes(xhtml_owner, xhtml, xhtml_size) =>
                if generation <> !_generation then let
                  val () = piece_free(xhtml_owner, xhtml)
                  val () = _acc_free(acc)
                in $P.ret<measured>(Measured()) end
                else if _over_budget(links, xhtml_size) then let
                  val () = piece_free(xhtml_owner, xhtml)
                  val () = _acc_free(acc)
                in $P.ret<measured>(Measured()) end
                else let
                  val () = _budget_spend(links, xhtml_size)
                  val @(xhtml_frozen, xhtml_bytes) = $A.freeze<byte>(xhtml)
                  val nodes = xhtml_parse(xhtml_bytes, xhtml_size)
                  val search = _links_found(serial, file_size, name_offset, dir_len, xhtml_bytes, xhtml_size, nodes, links)
                in
                  case+ search of
                  | ~LinksSkipped() => let
                      val () = _chapter_tallied(xhtml_bytes, nodes, acc)
                      val () = $X.free_nodes(nodes)
                      val () = $A.drop<byte>(xhtml_frozen, xhtml_bytes)
                      val () = piece_free(xhtml_owner, $A.thaw<byte>(xhtml_frozen))
                    in $P.ret<measured>(Measured()) end
                  | ~LinksFound(~LinksNil()) => let
                      val () = _chapter_tallied(xhtml_bytes, nodes, acc)
                      val () = $X.free_nodes(nodes)
                      val () = $A.drop<byte>(xhtml_frozen, xhtml_bytes)
                      val () = piece_free(xhtml_owner, $A.thaw<byte>(xhtml_frozen))
                    in $P.ret<measured>(Measured()) end
                  | ~LinksFound(~LinksCons(data_offset, data_size, method, rest)) => let
                      val () = $X.free_nodes(nodes)
                      val () = $A.drop<byte>(xhtml_frozen, xhtml_bytes)
                      val () = piece_free(xhtml_owner, $A.thaw<byte>(xhtml_frozen))
                    in
                      $P.and_then<sheet_acc><measured>(_entries_read(serial, file_size, _entries_reversed(rest, LinksCons(data_offset, data_size, method, LinksNil())), acc), llam(joined) =>
                        _chapter_measure(serial, chapter_index, generation, joined, LinksKnown()))
                    end
                end)
          end))

(* ============================================================
   The sample
   ============================================================ *)

(* The index in the spine of the k-th chapter measured of total chapters *)
fn _sampled (k: int, total: int): int =
  if total <= SAMPLE_MAX then k else (k * total) / SAMPLE_MAX

(* The chapters from the k-th of the sample on, then the answer *)
fun _measure_from {count:nat | count <= SAMPLE_MAX}{k:nat | k <= SAMPLE_MAX} .<SAMPLE_MAX - k>.
  (serial: int, total: int, count: int count, k: int k, generation: int): $P.promise(measured, $P.Chained) =
  if k >= count then let
    val () = (if generation = !_generation then let
        val ~TallyCell(tally) = _tally_take()
        val () = (if tally_chars(tally) > 0 then !_dominant := tally_dominant(tally) else !_dominant := 0)
      in _tally_put(TallyCell(tally)) end
      else ())
  in $P.ret<measured>(Measured()) end
  else let
    val index = g1ofg0(_sampled(k, total))
  in
    if index >= 0 then
      $P.and_then<measured><measured>(_chapter_measure(serial, index, generation, NoSheets(), LinksUnknown()), llam(_) =>
        _measure_from(serial, total, count, k + 1, generation))
    else _measure_from(serial, total, count, k + 1, generation)
  end

(* Measures the open book, book serial of total chapters: the dominant
   size is kept once the sample is read *)
#pub fun publisher_size_measure (serial: int, total: int): $P.promise(measured, $P.Chained)

implement publisher_size_measure (serial, total) = let
  val generation = !_generation + 1
  val () = !_generation := generation
  val () = !_dominant := 0
  val () = !_budget := SAMPLE_BYTES_MAX
  val () = _tally_put(TallyCell(tally_new()))
  val wanted = (if total < SAMPLE_MAX then total else SAMPLE_MAX): int
  val count = g1ofg0(wanted)
in
  if count >= 0 then (if count <= SAMPLE_MAX then _measure_from(serial, total, count, 0, generation) else $P.ret<measured>(Measured()))
  else $P.ret<measured>(Measured())
end

end
