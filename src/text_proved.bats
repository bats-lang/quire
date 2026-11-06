(* text_proved -- take_text with its proofs: an entry's data inflated by zip's decoder that returns INFLATES, then read as
   text by text_relation's proved functions, so the text comes with INFLATES and TEXTOF over the same cells (quire#848, a
   piece of quire#608). Keyword: text-proved. The detail is in .claude/rules/book-text.md. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use zip as Z

staload "bytes.sats"
staload "bytesarr.sats"
staload "crc.sats"
staload "text_relation.sats"

(* How an entry's data is stored, as a value of its static index (zip's inflate_kind) *)
#pub datatype entry_method($Z.inflate_kind) =
  | MethodStored($Z.inflate_stored())
  | MethodDeflated($Z.inflate_deflated())

(* The method of an entry, as a value of its static index *)
#pub fn entry_method_of (method: $Z.compression): [kind:$Z.inflate_kind] entry_method(kind)

implement entry_method_of (method) =
  case+ method of
  | $Z.Stored() => MethodStored()
  | $Z.Deflated() => MethodDeflated()

(* What a text's array is given back to: the heap (barr_free), or the arena whose piece it is (a text over 1 MiB, which no barr_alloc
   makes: the copy of an arena's output, #849; keyword: arena-text) *)
#pub datavtype text_owner(l:addr, n:int) =
  | text_owner_heap(l, n) of ()
  | {la:agz}{max,used:nat} text_owner_arena(l, n) of ($A.arrx_lent(l, n, la) | $A.arena(byte, la, max, used, 1))

(* The array of a text, given back to what it came from *)
#pub fn text_give_back {l:agz}{n:nat}{cs:$A.cells} (owner: text_owner(l, n), array: $A.barr(l, n, cs)): void

implement text_give_back {l}{n}{cs} (owner, array) =
  case+ owner of
  | ~text_owner_heap() => $A.barr_free(array)
  | ~text_owner_arena(lent | arena) => let
      val () = $A.arena_return<byte>(arena, $A.barr_to_arrx(lent | array))
    in $A.arena_destroy<byte>(arena) end

(* What taking an entry's data as text gave. The array of the text is a barr (the decoder's own output or a conversion of it, or
   the copy of an arena's output when the entry inflates to more than 1 MiB, up to 16 MiB: text_owner says which it gives back to).
   Taken: the entry inflates by its method to the
   cells output (INFLATES), the document in them needs the plan and becomes the octets (TEXTOF), and the array holds exactly
   those octets (HOLDS). Refused: the document is in the cells and is refused (TEXTOF). Empty: the entry inflates to nothing.
   Malformed: the decoder refuses the data, or (take_text_proved_sum) the sum the archive states is not the CRC-32 of what it
   inflated to. Too large: the text is over 16 MiB (an entry's data over 1 MiB is taken whole, a stored one copied to an arena
   piece, a deflated one inflated into an arena), or the conversion of it is over 1 MiB *)
#pub datavtype text_taken($Z.inflate_kind, $A.cells) =
  | {kind:$Z.inflate_kind}{compressed,output,text:$A.cells}{plan:plan}{octets:bytes}{count:pos}{l:agz}
    TextTaken(kind, compressed) of ($Z.INFLATES(kind, compressed, output), TEXTOF(output, plan, TOUT_bytes(octets)),
      HOLDS(text, 0, octets, count), $A.CLEN(text, count) | text_owner(l, count), $A.barr(l, count, text), int count)
  | {kind:$Z.inflate_kind}{compressed,output:$A.cells}{out:textout}
    TextRefused(kind, compressed) of ($Z.INFLATES(kind, compressed, output), TEXTOF(output, PlanRefused(), out) | )
  | {compressed:$A.cells}
    TextEmpty($Z.inflate_deflated(), compressed) of ($Z.INFLATES($Z.inflate_deflated(), compressed, $A.cnil()) | )
  | {kind:$Z.inflate_kind}{compressed:$A.cells} TextMalformed(kind, compressed) of ()
  | {kind:$Z.inflate_kind}{compressed:$A.cells} TextTooLarge(kind, compressed) of ()

(* TAKEN(kind, compressed, text, count): the first count cells of text hold the text of the document that the entry compressed
   inflates to by kind. It is what a TextTaken says of its array, as one proof, so a walk of the text takes it (reader.bats's
   render, search and read aloud) and two walks are shown to read one text when their proofs are of one entry and one method
   (pieces_of_taken_functional, src/cut.bats). A TAKEN is made of the three proofs of a TextTaken and of nothing else *)
#pub dataprop TAKEN($Z.inflate_kind, $A.cells, $A.cells, int) =
  | {kind:$Z.inflate_kind}{compressed,output,text:$A.cells}{plan:plan}{octets:bytes}{count:int}
    TAKEN_of(kind, compressed, text, count)
      of ($Z.INFLATES(kind, compressed, output), TEXTOF(output, plan, TOUT_bytes(octets)), HOLDS(text, 0, octets, count))

(* A document that needs no conversion is its own text: the bytes of the cells *)
prfn _as_is_holds {cells:$A.cells}{n:pos}{out:textout}
  (plan: TEXTOF(cells, PlanAsIs(), out), length: $A.CLEN(cells, n))
  : [octets:bytes] (TEXTOF(cells, PlanAsIs(), TOUT_bytes(octets)), HOLDS(cells, 0, octets, n)) =
  case+ plan of
  | TEXTOF_utf8_as_is(detect, plan_length, run, held) => let
      prval () = clen_functional(plan_length, length)
    in (TEXTOF_utf8_as_is(detect, plan_length, run, held), held) end
  | TEXTOF_unsupported_as_is(detect, plan_length, run, held) => let
      prval () = clen_functional(plan_length, length)
    in (TEXTOF_unsupported_as_is(detect, plan_length, run, held), held) end
  | TEXTOF_single_as_is(detect, plan_length, run, held) => let
      prval () = clen_functional(plan_length, length)
    in (TEXTOF_single_as_is(detect, plan_length, run, held), held) end

(* The inflated cells, read as text *)
fn _read_text {kind:$Z.inflate_kind}{compressed,output:$A.cells}{n:pos}{l:agz}
  (inflates: $Z.INFLATES(kind, compressed, output), length: $A.CLEN(output, n) | owner: text_owner(l, n), inflated: $A.barr(l, n, output), n: int n)
  : text_taken(kind, compressed) = let
  val @(frozen, view) = $A.barr_freeze(inflated)
  val (plan | which) = text_plan_proved(length | view, n)
in
  case+ which of
  | ProvedAsIs() => let
      prval (as_is, held) = _as_is_holds(plan, length)
      val () = $A.cborrow_drop(frozen, view)
      val back = $A.barr_thaw(frozen)
    in TextTaken(inflates, as_is, held, length | owner, back, n) end
  | ProvedRefused() => let
      val () = $A.cborrow_drop(frozen, view)
      val back = $A.barr_thaw(frozen)
      val () = text_give_back(owner, back)
    in TextRefused(inflates, plan | ) end
  | ProvedConvert() =>
    (case+ text_convert_size(length | view, n) of
     | ~TextNoConversion() => let
         val () = $A.cborrow_drop(frozen, view)
         val back = $A.barr_thaw(frozen)
         val () = text_give_back(owner, back)
       in TextMalformed() end
     | ~TextSized(converting, total_length | count) =>
       if count <= 1048576 then let
         val (text_length | text) = $A.barr_alloc(count)
         val (held, written_length | written) = text_convert_fill(length, converting, total_length, text_length | view, n, text, count)
         val () = $A.cborrow_drop(frozen, view)
         val back = $A.barr_thaw(frozen)
         val () = text_give_back(owner, back)
       in TextTaken(inflates, converting, held, written_length | text_owner_heap(), written, count) end
       else let
         val () = $A.cborrow_drop(frozen, view)
         val back = $A.barr_thaw(frozen)
         val () = text_give_back(owner, back)
       in TextTooLarge() end)
end

(* Whether the CRC-32 of the cells is the sum, high and low 16 bits, the archive states for the entry; crc_of_cborrow's proved
   one, over the cells the proofs of the inflate name *)
fn _sum_is {lb:agz}{n:pos}{cs:$A.cells}
  (length: $A.CLEN(cs, n) | bytes: !$A.cborrow(lb, n, cs), n: int n, want_high: int, want_low: int): bool = let
  val (_, _ | @(sum_high, sum_low)) = crc_of_cborrow(length | bytes, n)
in sum_high = want_high && sum_low = want_low end

(* The inflated cells, read as text when the CRC-32 of them is the sum; else they are freed and the take is malformed *)
fn _read_text_summed {kind:$Z.inflate_kind}{compressed,output:$A.cells}{n:pos}{l:agz}
  (inflates: $Z.INFLATES(kind, compressed, output), length: $A.CLEN(output, n) | owner: text_owner(l, n), inflated: $A.barr(l, n, output), n: int n,
   want_high: int, want_low: int): text_taken(kind, compressed) = let
  val @(frozen, view) = $A.barr_freeze(inflated)
  val matches = _sum_is(length | view, n, want_high, want_low)
  val () = $A.cborrow_drop(frozen, view)
  val back = $A.barr_thaw(frozen)
in
  if matches then _read_text(inflates, length | owner, back, n)
  else let
    val () = text_give_back(owner, back)
  in TextMalformed() end
end

(* The inflated cells read as text, checked against the sum when check *)
fn _read_checked {kind:$Z.inflate_kind}{compressed,output:$A.cells}{n:pos}{l:agz}
  (inflates: $Z.INFLATES(kind, compressed, output), length: $A.CLEN(output, n) | owner: text_owner(l, n), inflated: $A.barr(l, n, output), n: int n,
   check: bool, want_high: int, want_low: int): text_taken(kind, compressed) =
  if check then _read_text_summed(inflates, length | owner, inflated, n, want_high, want_low)
  else _read_text(inflates, length | owner, inflated, n)

(* ===== an arena's output, copied to a piece of its own size (#849; keyword: arena-text) =====
   zip's decode above 1 MiB gives the output in the first size cells of an arena's piece of max cells (APPEND(output, junk, buffer)),
   and the walks of the text read an array of exactly the text's cells (the parser, the cut and the page are indexed by its length).
   The output is copied to a piece of an arena of its own, from the last cell to the first, and AGREED says which cells of the copy
   are the output's; the copy that is whole is the output's cells (CELLS_EQ), so the text is read from it as from any inflated cells *)

(* AGREED(first, second, from, to): cell i of first and of second is one value, for every i from from up to (not including) to *)
dataprop AGREED($A.cells, $A.cells, int, int) =
  | {first,second:$A.cells}{to:nat} AGREED_end(first, second, to, to)
  | {first,second:$A.cells}{from,to:nat | from < to}{value:int}
    AGREED_more(first, second, from, to) of ($A.NTH(first, from, value), $A.NTH(second, from, value), AGREED(first, second, from + 1, to))

(* Setting a cell before the ones agreed on leaves them agreed on *)
prfun _agreed_after_set {first,second,second_after:$A.cells}{at,from,to:nat | at < from; from <= to}{value:int} .<to - from>.
  (cells_set: $A.SETC(second, at, value, second_after), agreed: AGREED(first, second, from, to)): AGREED(first, second_after, from, to) =
  case+ agreed of
  | AGREED_end() => AGREED_end()
  | AGREED_more(first_cell, second_cell, rest) =>
    AGREED_more(first_cell, $A.setc_nth_other(cells_set, second_cell), _agreed_after_set(cells_set, rest))

(* Cells that are agreed on from i + 1 are, after their first cell, agreed on from i *)
prfun _agreed_shift {first_head,second_head:int}{first,second:$A.cells}{from,to:nat | from <= to} .<to - from>.
  (agreed: AGREED($A.ccons(first_head, first), $A.ccons(second_head, second), from + 1, to + 1)): AGREED(first, second, from, to) =
  case+ agreed of
  | AGREED_end() => AGREED_end()
  | AGREED_more(first_cell, second_cell, rest) =>
    (case+ first_cell of
     | $A.NTH_there(first_there) =>
       (case+ second_cell of
        | $A.NTH_there(second_there) => AGREED_more(first_there, second_there, _agreed_shift(rest))))

(* Cells of one length that are agreed on from the first to the last are one list of cells *)
prfun _eq_of_agreed {first,second:$A.cells}{n:nat} .<n>.
  (first_len: $A.CLEN(first, n), second_len: $A.CLEN(second, n), agreed: AGREED(first, second, 0, n)): $A.CELLS_EQ(first, second) =
  case+ first_len of
  | $A.CLEN_nil() => (case+ second_len of $A.CLEN_nil() => $A.CELLS_EQ_refl())
  | $A.CLEN_cons(first_rest) =>
    (case+ second_len of
     | $A.CLEN_cons(second_rest) =>
       (case+ agreed of
        | AGREED_more(first_cell, second_cell, rest) =>
          (case+ first_cell of
           | $A.NTH_here() =>
             (case+ second_cell of
              | $A.NTH_here() => let
                  prval $A.CELLS_EQ_refl() = _eq_of_agreed(first_rest, second_rest, _agreed_shift(rest))
                in $A.CELLS_EQ_refl() end))))

(* The cells of the arena's output, copied from cell i - 1 down to cell 0 into the piece target, whose cells from i on are agreed on *)
fun _copy_down {l,m:agz}{max,n:pos | n <= max}{output,junk,buffer,filled:$A.cells}{i:nat | i <= n} .<i>.
  (output_len: $A.CLEN(output, n), appended: $A.APPEND(output, junk, buffer), filled_len: $A.CLEN(filled, n),
   agreed: AGREED(output, filled, i, n) | source: !$A.barr(l, max, buffer), target: $A.barr(m, n, filled), i: int i)
  : [done:$A.cells] ($A.CLEN(done, n), AGREED(output, done, 0, n) | $A.barr(m, n, done)) =
  if i > 0 then let
    val (found | value) = $Z.inflated_arena_get(output_len, appended | source, i - 1)
    val (updated | target2) = $A.barr_set(target, i - 1, value)
    prval agreed2 = _agreed_after_set(updated, agreed)
    prval agreed3 = AGREED_more(found, $A.setc_nth_same(updated), agreed2)
    prval len2 = $A.setc_len(updated, filled_len)
  in _copy_down(output_len, appended, len2, agreed3 | source, target2, i - 1) end
  else (filled_len, agreed | target)

(* The output of zip's decode above 1 MiB, copied to a piece of its own size and read as text (the arena of the decode is given
   back; a copy that cannot be made is too large) *)
fn _text_of_arena {cs:$A.cells}
  (inflating: $Z.inflated_cells_arena(cs), check: bool, want_high: int, want_low: int)
  : text_taken($Z.inflate_deflated(), cs) =
  case+ inflating of
  | ~$Z.inflated_arena_done(inflates, output_len, appended, lent | arena, buffer, size) =>
    (case+ $A.arena_class_of(size) of
     | ~$A.arena_too_large() => let
         val () = $Z.inflated_arena_release(lent | arena, buffer)
       in TextTooLarge() end
     | ~$A.arena_fits(class | max) =>
       (case+ $A.arena_create_class<byte>(class | max) of
        | ~$A.arena_none() => let
            val () = $Z.inflated_arena_release(lent | arena, buffer)
          in TextTooLarge() end
        | ~$A.arena_some(target_arena) => let
            val piece = $A.arena_alloc<byte>(target_arena, size)
            val (piece_len, piece_lent | target) = $A.barr_of_arrx(piece)
            val (copied_len, agreed | filled) = _copy_down(output_len, appended, piece_len, AGREED_end() | buffer, target, size)
            val () = $Z.inflated_arena_release(lent | arena, buffer)
            prval $A.CELLS_EQ_refl() = _eq_of_agreed(output_len, copied_len, agreed)
          in _read_checked(inflates, output_len | text_owner_arena(piece_lent | target_arena), filled, size, check, want_high, want_low) end))
  | ~$Z.inflated_arena_empty(inflates | ) => TextEmpty(inflates | )
  | ~$Z.inflated_arena_malformed() => TextMalformed()
  | ~$Z.inflated_arena_too_large() => TextTooLarge()
  | ~$Z.inflated_arena_no_memory() => TextTooLarge()

(* A stored entry's data (cells source, n of them), copied from the last cell to the first into the piece target, whose cells from i on are agreed on *)
fun _copy_stored_down {l,m:agz}{n:pos}{source,filled:$A.cells}{i:nat | i <= n} .<i>.
  (filled_len: $A.CLEN(filled, n), agreed: AGREED(source, filled, i, n) | source: !$A.barr(l, n, source), target: $A.barr(m, n, filled), i: int i)
  : [done:$A.cells] ($A.CLEN(done, n), AGREED(source, done, 0, n) | $A.barr(m, n, done)) =
  if i > 0 then let
    val (found | value) = $A.barr_get(source, i - 1)
    val (updated | target2) = $A.barr_set(target, i - 1, value)
    prval agreed2 = _agreed_after_set(updated, agreed)
    prval agreed3 = AGREED_more(found, $A.setc_nth_same(updated), agreed2)
    prval len2 = $A.setc_len(updated, filled_len)
  in _copy_stored_down(len2, agreed3 | source, target2, i - 1) end
  else (filled_len, agreed | target)

(* A stored entry of over 1 MiB (the text is its data, the inflate of INFLATES_stored): copied to a piece of an arena of its own, as
   an arena's output is (a data over 16 MiB is too large) *)
fn _text_of_stored_big {l:agz}{n:pos | 1048576 < n}{cs:$A.cells}
  (length: $A.CLEN(cs, n) | compressed: !$A.barr(l, n, cs), n: int n, check: bool, want_high: int, want_low: int)
  : text_taken($Z.inflate_stored(), cs) =
  case+ $A.arena_class_of(n) of
  | ~$A.arena_too_large() => TextTooLarge()
  | ~$A.arena_fits(class | max) =>
    (case+ $A.arena_create_class<byte>(class | max) of
     | ~$A.arena_none() => TextTooLarge()
     | ~$A.arena_some(target_arena) => let
         val piece = $A.arena_alloc<byte>(target_arena, n)
         val (piece_len, piece_lent | target) = $A.barr_of_arrx(piece)
         val (copied_len, agreed | filled) = _copy_stored_down(piece_len, AGREED_end() | compressed, target, n)
         prval $A.CELLS_EQ_refl() = _eq_of_agreed(length, copied_len, agreed)
       in _read_checked($Z.INFLATES_stored{cs}(), length | text_owner_arena(piece_lent | target_arena), filled, n, check, want_high, want_low) end)

(* A deflated entry inflated into an arena of 16 MiB, the largest class (zip#95), and read as text; the data is given back as it was *)
fn _take_deflated_arena {l:agz}{n:pos}{cs:$A.cells}
  (length: $A.CLEN(cs, n) | compressed: $A.barr(l, n, cs), n: int n, check: bool, want_high: int, want_low: int)
  : @($A.barr(l, n, cs), text_taken($Z.inflate_deflated(), cs)) = let
  val @(frozen, view) = $A.barr_freeze(compressed)
  val big = $Z.inflate_cells_arena_proved(length, $A.Arena16MiB() | view, n, 16777216)
  val () = $A.cborrow_drop(frozen, view)
in @($A.barr_thaw(frozen), _text_of_arena(big, check, want_high, want_low)) end

(* An entry of 1048576 bytes or fewer of data, taken as text (a text that inflates to over 1 MiB goes to an arena) *)
fn _take_small {kind:$Z.inflate_kind}{l:agz}{n:pos | n <= 1048576}{cs:$A.cells}
  (length: $A.CLEN(cs, n) | method: entry_method(kind), compressed: $A.barr(l, n, cs), n: int n,
   check: bool, want_high: int, want_low: int): @($A.barr(l, n, cs), text_taken(kind, cs)) =
  case+ method of
  | MethodStored() => let
      val copy = $A.barr_copy(compressed, n)
    in @(compressed, _read_checked($Z.INFLATES_stored{cs}(), length | text_owner_heap(), copy, n, check, want_high, want_low)) end
  | MethodDeflated() => let
      val @(frozen, view) = $A.barr_freeze(compressed)
      val inflating = $Z.inflate_cells_proved(length | view, n)
      val () = $A.cborrow_drop(frozen, view)
      val back = $A.barr_thaw(frozen)
    in
      case+ inflating of
      | ~$Z.inflated_cells_done(inflates, output_length | output, size) =>
        @(back, _read_checked(inflates, output_length | text_owner_heap(), output, size, check, want_high, want_low))
      | ~$Z.inflated_cells_empty(inflates | ) => @(back, TextEmpty(inflates | ))
      | ~$Z.inflated_cells_malformed() => @(back, TextMalformed())
      (* over 1 MiB inflated: into an arena of 16 MiB *)
      | ~$Z.inflated_cells_too_large() => _take_deflated_arena(length | back, n, check, want_high, want_low)
    end

(* take_text_proved and take_text_proved_sum are this: the sum is checked when check. An entry of over 1 MiB of data (a stored
   chapter, or a deflated one) is taken whole too (arena-text) *)
fn _take {kind:$Z.inflate_kind}{l:agz}{n:pos}{cs:$A.cells}
  (length: $A.CLEN(cs, n) | method: entry_method(kind), compressed: $A.barr(l, n, cs), n: int n,
   check: bool, want_high: int, want_low: int): @($A.barr(l, n, cs), text_taken(kind, cs)) =
  if n <= 1048576 then _take_small(length | method, compressed, n, check, want_high, want_low)
  else
    (case+ method of
     | MethodStored() => let
         val taken = _text_of_stored_big(length | compressed, n, check, want_high, want_low)
       in @(compressed, taken) end
     | MethodDeflated() => _take_deflated_arena(length | compressed, n, check, want_high, want_low))

(* An entry's data (the array `compressed`, whose cells are cs) taken as text: inflated by zip's decoder that proves INFLATES
   (a stored entry is a copy of its data), read by text_plan_proved and, when it needs one, converted by text_convert_fill. The
   array is given back as it was *)
#pub fn take_text_proved {kind:$Z.inflate_kind}{l:agz}{n:pos}{cs:$A.cells}
  (length: $A.CLEN(cs, n) | method: entry_method(kind), compressed: $A.barr(l, n, cs), n: int n)
  : @($A.barr(l, n, cs), text_taken(kind, cs))

implement take_text_proved {kind}{l}{n}{cs} (length | method, compressed, n) = _take(length | method, compressed, n, false, 0, 0)

(* take_text_proved, but only when the CRC-32 of the inflated cells, before they are read as text, is the sum the archive states
   for the entry (want_high and want_low, the high and low 16 bits, as book_entry_sum gives them): the sum is compared on the
   cells INFLATES names, so the walks of the text read the cells that were checked. An entry whose data is not what its sum says
   is TextMalformed, as an unreadable one is (take_text_sum's none) *)
#pub fn take_text_proved_sum {kind:$Z.inflate_kind}{l:agz}{n:pos}{cs:$A.cells}
  (length: $A.CLEN(cs, n) | method: entry_method(kind), compressed: $A.barr(l, n, cs), n: int n, want_high: int, want_low: int)
  : @($A.barr(l, n, cs), text_taken(kind, cs))

implement take_text_proved_sum {kind}{l}{n}{cs} (length | method, compressed, n, want_high, want_low) =
  _take(length | method, compressed, n, true, want_high, want_low)

(* Two decodes of one entry's cells, by one method, give the same text: the same plan and the same bytes *)
#pub prfun text_taken_functional {kind:$Z.inflate_kind}{compressed,first,second:$A.cells}{first_plan,second_plan:plan}{first_octets,second_octets:bytes}
  ($Z.INFLATES(kind, compressed, first), $Z.INFLATES(kind, compressed, second),
   TEXTOF(first, first_plan, TOUT_bytes(first_octets)), TEXTOF(second, second_plan, TOUT_bytes(second_octets)))
  : (EQPLAN(first_plan, second_plan), EQB(first_octets, second_octets))

primplement text_taken_functional {kind}{compressed,first,second}{first_plan,second_plan}{first_octets,second_octets}
  (first_inflates, second_inflates, first_text, second_text) =
  case+ $Z.inflates_functional(first_inflates, second_inflates) of
  | $Z.CELLS_EQ_refl() => let
      prval (same_plan, EQOUT_refl()) = textof_functional(first_text, second_text)
    in (same_plan, EQB_refl()) end

(* The array and the proofs of a taken text are not wanted *)
#pub fn text_taken_free {kind:$Z.inflate_kind}{cs:$A.cells} (taken: text_taken(kind, cs)): void

implement text_taken_free {kind}{cs} (taken) =
  case+ taken of
  | ~TextTaken(_, _, _, _ | owner, array, _) => text_give_back(owner, array)
  | ~TextRefused(_, _ | ) => ()
  | ~TextEmpty(_ | ) => ()
  | ~TextMalformed() => ()
  | ~TextTooLarge() => ()

(* fixture: the-end-of-text-proved *)
(* The end of text_proved: the static fixtures of tests/static/reject named text-proved are put before this line *)

end (* #target wasm *)
