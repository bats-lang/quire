(* cut -- how a text of 64 KiB or more is cut into pieces, as a function of
   the cells of the array that holds it (#568)

   A page shows a text in pieces of under 64 KiB (a text op's limit), and
   render, search and read aloud each number a text's pieces: a stored
   place is the piece's content node and an offset in it, so the three
   walks must cut a text in the same places. The rule is here once, as a
   relation over the cells of the borrowed array the text is read from
   (array's cborrow, whose cborrow_get gives NTH(cs, i, v) with each byte):

   * BREAKBACK: the cut after the last white space (a space, a tab or a
     line feed) at or before a cell, looking back no further than a floor;
   * CUTC(cs, offset, text_len, cut): the first piece of the text at offset
     is cut bytes long: after the last white space in its last 512 bytes,
     else the longest prefix that ends before a UTF-8 character's start;
   * PIECES(cs, offset, text_len, count): the text is count pieces, each
     cut off by CUTC and the last under 64 KiB.

   Every constructor takes the cells it was decided from (NTH of the cells
   that were read), so a cut cannot be claimed over other cells than the
   ones it was found in. Each relation is functional (breakback_functional,
   cutc_functional, pieces_functional): two cuts, or two counts, of the same
   cells and offset are equal, so two walks over one array cannot disagree.
   The three walks do not read one array: render, search and read aloud each
   take the chapter from a take_text_proved of the entry (#849), and each
   walk takes the proof of that take (text_proved's TAKEN). Two takes of one
   entry by one method hold the same octets (text_taken_functional), and
   pieces_of_taken_functional shows that a count over the cells of one is the
   count over the cells of the other, so the three number a text's pieces
   alike as a proof *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use zip as Z

staload "bytes.sats"
staload "bytesarr.sats"
staload "text_proved.sats"

(* WHITE(code): code is a space, a tab or a line feed; NOTWHITE(code):
   it is none of them (three ranges, so no disjunction is asked of the
   solver) *)
#pub dataprop WHITE(int) =
  | WHITE_space(32)
  | WHITE_tab(9)
  | WHITE_line_feed(10)

#pub dataprop NOTWHITE(int) =
  | {code:int | code <= 8} NOTWHITE_below(code)
  | {code:int | 11 <= code; code <= 31} NOTWHITE_middle(code)
  | {code:int | 33 <= code} NOTWHITE_above(code)

(* STARTS(code): a byte of that value starts a UTF-8 character (is not
   10xxxxxx); CONTINUES(code): it continues one *)
#pub dataprop STARTS(int) =
  | {code:int | code < 128} STARTS_ascii(code)
  | {code:int | 192 <= code} STARTS_lead(code)

#pub dataprop CONTINUES(int) =
  | {code:int | 128 <= code; code < 192} CONTINUES_byte(code)

prfn white_not_white {code:int} (white: WHITE(code), not_white: NOTWHITE(code)): [1 == 0] void =
  case+ white of
  | WHITE_space() => (case+ not_white of NOTWHITE_below() => () | NOTWHITE_middle() => () | NOTWHITE_above() => ())
  | WHITE_tab() => (case+ not_white of NOTWHITE_below() => () | NOTWHITE_middle() => () | NOTWHITE_above() => ())
  | WHITE_line_feed() => (case+ not_white of NOTWHITE_below() => () | NOTWHITE_middle() => () | NOTWHITE_above() => ())

prfn starts_not_continues {code:int} (starts: STARTS(code), continues: CONTINUES(code)): [1 == 0] void =
  case+ starts of
  | STARTS_ascii() => (case+ continues of CONTINUES_byte() => ())
  | STARTS_lead() => (case+ continues of CONTINUES_byte() => ())

(* BREAKBACK(cs, offset, at, floor, back): looking back from cell
   offset + at, no further than floor, the cut is back: after the last
   white space found (at + 1), or -1 when there is none *)
#pub dataprop BREAKBACK($A.cells, int, int, int, int) =
  | {cs:$A.cells}{offset,floor:int} BREAKBACK_start(cs, offset, 0, floor, ~1)
  | {cs:$A.cells}{offset,at,floor:int | 1 <= at; at <= floor} BREAKBACK_floor(cs, offset, at, floor, ~1)
  | {cs:$A.cells}{offset:nat}{at,floor,code:int | 1 <= at; floor < at}
    BREAKBACK_white(cs, offset, at, floor, at + 1) of ($A.NTH(cs, offset + at, code), WHITE(code))
  | {cs:$A.cells}{offset:nat}{at,floor,code,back:int | 1 <= at; floor < at}
    BREAKBACK_other(cs, offset, at, floor, back) of ($A.NTH(cs, offset + at, code), NOTWHITE(code), BREAKBACK(cs, offset, at - 1, floor, back))

#pub prfun breakback_functional {cs:$A.cells}{offset:nat}{at:nat}{floor,first,second:int}
  (BREAKBACK(cs, offset, at, floor, first), BREAKBACK(cs, offset, at, floor, second)): [first == second] void

prfun _breakback_functional {cs:$A.cells}{offset:nat}{at:nat}{floor,first,second:int} .<at>.
  (first_proof: BREAKBACK(cs, offset, at, floor, first), second_proof: BREAKBACK(cs, offset, at, floor, second)): [first == second] void =
  case+ first_proof of
  | BREAKBACK_start() =>
    (case+ second_proof of
     | BREAKBACK_start() => ()
     | BREAKBACK_floor() => ()
     | BREAKBACK_white(_, _) => ()
     | BREAKBACK_other(_, _, _) => ())
  | BREAKBACK_floor() =>
    (case+ second_proof of
     | BREAKBACK_start() => ()
     | BREAKBACK_floor() => ()
     | BREAKBACK_white(_, _) => ()
     | BREAKBACK_other(_, _, _) => ())
  | BREAKBACK_white(first_cell, first_white) =>
    (case+ second_proof of
     | BREAKBACK_start() => ()
     | BREAKBACK_floor() => ()
     | BREAKBACK_white(second_cell, second_white) => ()
     | BREAKBACK_other(second_cell, second_not_white, _) => let
         prval () = $A.nth_functional(first_cell, second_cell)
         prval () = white_not_white(first_white, second_not_white)
       in () end)
  | BREAKBACK_other(first_cell, first_not_white, first_rest) =>
    (case+ second_proof of
     | BREAKBACK_start() => ()
     | BREAKBACK_floor() => ()
     | BREAKBACK_white(second_cell, second_white) => let
         prval () = $A.nth_functional(first_cell, second_cell)
         prval () = white_not_white(second_white, first_not_white)
       in () end
     | BREAKBACK_other(second_cell, second_not_white, second_rest) =>
       _breakback_functional(first_rest, second_rest))

primplement breakback_functional {cs}{offset}{at}{floor,first,second} (first_proof, second_proof) =
  _breakback_functional(first_proof, second_proof)

(* The cut after the last white space at or before cell offset + at,
   looking back no further than floor, with its proof *)
fun _break_back {l:agz}{n:pos}{cs:$A.cells}{offset,text_len:nat | offset + text_len <= n; text_len >= 65536}{at:nat | at <= 65534}{floor:int} .<at>.
  (bytes: !$A.cborrow(l, n, cs), offset: int offset, at: int at, floor: int floor)
  : [back:int | ~1 <= back; back <= 65535] (BREAKBACK(cs, offset, at, floor, back) | int back) =
  if at <= 0 then (BREAKBACK_start{cs}{offset,floor}() | ~1)
  else if at <= floor then (BREAKBACK_floor{cs}{offset,at,floor}() | ~1)
  else let
    val (cell | code) = $A.cborrow_get(bytes, offset + at)
  in
    if code = 32 then (BREAKBACK_white(cell, WHITE_space()) | at + 1)
    else if code = 10 then (BREAKBACK_white(cell, WHITE_line_feed()) | at + 1)
    else if code = 9 then (BREAKBACK_white(cell, WHITE_tab()) | at + 1)
    else if code <= 8 then let
      val (rest | back) = _break_back{l}{n}{cs}{offset,text_len}{at - 1}{floor}(bytes, offset, at - 1, floor)
    in (BREAKBACK_other(cell, NOTWHITE_below(), rest) | back) end
    else if code <= 31 then let
      val (rest | back) = _break_back{l}{n}{cs}{offset,text_len}{at - 1}{floor}(bytes, offset, at - 1, floor)
    in (BREAKBACK_other(cell, NOTWHITE_middle(), rest) | back) end
    else let
      val (rest | back) = _break_back{l}{n}{cs}{offset,text_len}{at - 1}{floor}(bytes, offset, at - 1, floor)
    in (BREAKBACK_other(cell, NOTWHITE_above(), rest) | back) end
  end

(* CUTC(cs, offset, text_len, cut): the first piece of the text of text_len
   bytes (64 KiB or more) at offset of the cells cs is cut bytes long:
   after the last white space in its last 512 bytes (looking back from
   offset + 65534 no further than offset + 65022), else the longest prefix
   that ends before a UTF-8 character's start (65535, 65534 or 65533), else
   65535 when none of those three cells starts a character *)
#pub dataprop CUTC($A.cells, int, int, int) =
  | {cs:$A.cells}{offset:nat}{text_len,back:int | 65536 <= text_len; 65000 <= back; back <= 65535}
    CUTC_break(cs, offset, text_len, back) of (BREAKBACK(cs, offset, 65534, 65022, back))
  | {cs:$A.cells}{offset:nat}{text_len,back,first:int | 65536 <= text_len; back < 65000}
    CUTC_65535(cs, offset, text_len, 65535)
      of (BREAKBACK(cs, offset, 65534, 65022, back), $A.NTH(cs, offset + 65535, first), STARTS(first))
  | {cs:$A.cells}{offset:nat}{text_len,back,first,second:int | 65536 <= text_len; back < 65000}
    CUTC_65534(cs, offset, text_len, 65534)
      of (BREAKBACK(cs, offset, 65534, 65022, back), $A.NTH(cs, offset + 65535, first), CONTINUES(first),
          $A.NTH(cs, offset + 65534, second), STARTS(second))
  | {cs:$A.cells}{offset:nat}{text_len,back,first,second,third:int | 65536 <= text_len; back < 65000}
    CUTC_65533(cs, offset, text_len, 65533)
      of (BREAKBACK(cs, offset, 65534, 65022, back), $A.NTH(cs, offset + 65535, first), CONTINUES(first),
          $A.NTH(cs, offset + 65534, second), CONTINUES(second), $A.NTH(cs, offset + 65533, third), STARTS(third))
  | {cs:$A.cells}{offset:nat}{text_len,back,first,second,third:int | 65536 <= text_len; back < 65000}
    CUTC_none_starts(cs, offset, text_len, 65535)
      of (BREAKBACK(cs, offset, 65534, 65022, back), $A.NTH(cs, offset + 65535, first), CONTINUES(first),
          $A.NTH(cs, offset + 65534, second), CONTINUES(second), $A.NTH(cs, offset + 65533, third), CONTINUES(third))

#pub prfun cutc_functional {cs:$A.cells}{offset:nat}{text_len:int}{first,second:int}
  (CUTC(cs, offset, text_len, first), CUTC(cs, offset, text_len, second)): [first == second] void

prfn _cutc_functional {cs:$A.cells}{offset:nat}{text_len:int}{first,second:int}
  (first_proof: CUTC(cs, offset, text_len, first), second_proof: CUTC(cs, offset, text_len, second)): [first == second] void =
  case+ first_proof of
  | CUTC_break(first_back) =>
    (case+ second_proof of
     | CUTC_break(second_back) => breakback_functional(first_back, second_back)
     | CUTC_65535(second_back, _, _) => breakback_functional(first_back, second_back)
     | CUTC_65534(second_back, _, _, _, _) => breakback_functional(first_back, second_back)
     | CUTC_65533(second_back, _, _, _, _, _, _) => breakback_functional(first_back, second_back)
     | CUTC_none_starts(second_back, _, _, _, _, _, _) => breakback_functional(first_back, second_back))
  | CUTC_65535(first_back, first_cell, first_starts) =>
    (case+ second_proof of
     | CUTC_break(second_back) => breakback_functional(first_back, second_back)
     | CUTC_65535(_, _, _) => ()
     | CUTC_65534(_, second_cell, second_continues, _, _) => let
         prval () = $A.nth_functional(first_cell, second_cell)
         prval () = starts_not_continues(first_starts, second_continues)
       in () end
     | CUTC_65533(_, second_cell, second_continues, _, _, _, _) => let
         prval () = $A.nth_functional(first_cell, second_cell)
         prval () = starts_not_continues(first_starts, second_continues)
       in () end
     | CUTC_none_starts(_, second_cell, second_continues, _, _, _, _) => let
         prval () = $A.nth_functional(first_cell, second_cell)
         prval () = starts_not_continues(first_starts, second_continues)
       in () end)
  | CUTC_65534(first_back, first_cell, first_continues, first_second_cell, first_second_starts) =>
    (case+ second_proof of
     | CUTC_break(second_back) => breakback_functional(first_back, second_back)
     | CUTC_65535(_, second_cell, second_starts) => let
         prval () = $A.nth_functional(first_cell, second_cell)
         prval () = starts_not_continues(second_starts, first_continues)
       in () end
     | CUTC_65534(_, _, _, _, _) => ()
     | CUTC_65533(_, _, _, second_second_cell, second_second_continues, _, _) => let
         prval () = $A.nth_functional(first_second_cell, second_second_cell)
         prval () = starts_not_continues(first_second_starts, second_second_continues)
       in () end
     | CUTC_none_starts(_, _, _, second_second_cell, second_second_continues, _, _) => let
         prval () = $A.nth_functional(first_second_cell, second_second_cell)
         prval () = starts_not_continues(first_second_starts, second_second_continues)
       in () end)
  | CUTC_65533(first_back, first_cell, first_continues, first_second_cell, first_second_continues, first_third_cell, first_third_starts) =>
    (case+ second_proof of
     | CUTC_break(second_back) => breakback_functional(first_back, second_back)
     | CUTC_65535(_, second_cell, second_starts) => let
         prval () = $A.nth_functional(first_cell, second_cell)
         prval () = starts_not_continues(second_starts, first_continues)
       in () end
     | CUTC_65534(_, _, _, second_second_cell, second_second_starts) => let
         prval () = $A.nth_functional(first_second_cell, second_second_cell)
         prval () = starts_not_continues(second_second_starts, first_second_continues)
       in () end
     | CUTC_65533(_, _, _, _, _, _, _) => ()
     | CUTC_none_starts(_, _, _, _, _, second_third_cell, second_third_continues) => let
         prval () = $A.nth_functional(first_third_cell, second_third_cell)
         prval () = starts_not_continues(first_third_starts, second_third_continues)
       in () end)
  | CUTC_none_starts(first_back, first_cell, first_continues, first_second_cell, first_second_continues, first_third_cell, first_third_continues) =>
    (case+ second_proof of
     | CUTC_break(second_back) => breakback_functional(first_back, second_back)
     | CUTC_65535(_, second_cell, second_starts) => let
         prval () = $A.nth_functional(first_cell, second_cell)
         prval () = starts_not_continues(second_starts, first_continues)
       in () end
     | CUTC_65534(_, _, _, second_second_cell, second_second_starts) => let
         prval () = $A.nth_functional(first_second_cell, second_second_cell)
         prval () = starts_not_continues(second_second_starts, first_second_continues)
       in () end
     | CUTC_65533(_, _, _, _, _, second_third_cell, second_third_starts) => let
         prval () = $A.nth_functional(first_third_cell, second_third_cell)
         prval () = starts_not_continues(second_third_starts, first_third_continues)
       in () end
     | CUTC_none_starts(_, _, _, _, _, _, _) => ())

primplement cutc_functional {cs}{offset}{text_len}{first,second} (first_proof, second_proof) =
  _cutc_functional(first_proof, second_proof)

(* The first piece's length of the text of text_len bytes at offset, read
   from the cells *)
#pub fun cut_find {l:agz}{n:pos}{cs:$A.cells}{offset,text_len:nat | offset + text_len <= n; text_len >= 65536}
  (bytes: !$A.cborrow(l, n, cs), offset: int offset, text_len: int text_len)
  : [cut:int | 65000 <= cut; cut <= 65535] (CUTC(cs, offset, text_len, cut) | int cut)

implement cut_find {l}{n}{cs}{offset,text_len} (bytes, offset, text_len) = let
  val (back_proof | back) = _break_back{l}{n}{cs}{offset,text_len}{65534}{65022}(bytes, offset, 65534, 65022)
in
  if back >= 65000 then (CUTC_break(back_proof) | back)
  else let
    val (first_cell | first) = $A.cborrow_get(bytes, offset + 65535)
  in
    if first < 128 then (CUTC_65535(back_proof, first_cell, STARTS_ascii()) | 65535)
    else if first >= 192 then (CUTC_65535(back_proof, first_cell, STARTS_lead()) | 65535)
    else let
      val (second_cell | second) = $A.cborrow_get(bytes, offset + 65534)
    in
      if second < 128 then (CUTC_65534(back_proof, first_cell, CONTINUES_byte(), second_cell, STARTS_ascii()) | 65534)
      else if second >= 192 then (CUTC_65534(back_proof, first_cell, CONTINUES_byte(), second_cell, STARTS_lead()) | 65534)
      else let
        val (third_cell | third) = $A.cborrow_get(bytes, offset + 65533)
      in
        if third < 128 then
          (CUTC_65533(back_proof, first_cell, CONTINUES_byte(), second_cell, CONTINUES_byte(), third_cell, STARTS_ascii()) | 65533)
        else if third >= 192 then
          (CUTC_65533(back_proof, first_cell, CONTINUES_byte(), second_cell, CONTINUES_byte(), third_cell, STARTS_lead()) | 65533)
        else
          (CUTC_none_starts(back_proof, first_cell, CONTINUES_byte(), second_cell, CONTINUES_byte(), third_cell, CONTINUES_byte()) | 65535)
      end
    end
  end
end

(* PIECES(cs, offset, text_len, count): the text of text_len bytes at
   offset of the cells cs is count pieces, each cut off by CUTC and the
   last under 64 KiB *)
#pub dataprop PIECES($A.cells, int, int, int) =
  | {cs:$A.cells}{offset:nat}{text_len:int | text_len < 65536} PIECES_last(cs, offset, text_len, 1)
  | {cs:$A.cells}{offset:nat}{text_len,cut,count:int | 65536 <= text_len; 65000 <= cut; cut <= 65535}
    PIECES_more(cs, offset, text_len, count + 1)
      of (CUTC(cs, offset, text_len, cut), PIECES(cs, offset + cut, text_len - cut, count))

#pub prfun pieces_functional {cs:$A.cells}{offset:nat}{text_len:nat}{first,second:int}
  (PIECES(cs, offset, text_len, first), PIECES(cs, offset, text_len, second)): [first == second] void

prfun _pieces_functional {cs:$A.cells}{offset:nat}{text_len:nat}{first,second:int} .<text_len>.
  (first_proof: PIECES(cs, offset, text_len, first), second_proof: PIECES(cs, offset, text_len, second)): [first == second] void =
  case+ first_proof of
  | PIECES_last() => (case+ second_proof of PIECES_last() => () | PIECES_more(_, _) => ())
  | PIECES_more(first_cut, first_rest) =>
    (case+ second_proof of
     | PIECES_last() => ()
     | PIECES_more(second_cut, second_rest) => let
         prval () = cutc_functional(first_cut, second_cut)
       in _pieces_functional(first_rest, second_rest) end)

primplement pieces_functional {cs}{offset}{text_len}{first,second} (first_proof, second_proof) =
  _pieces_functional(first_proof, second_proof)

fun _pieces_find {l:agz}{n:pos}{cs:$A.cells}{offset,text_len:nat | offset + text_len <= n} .<text_len>.
  (bytes: !$A.cborrow(l, n, cs), offset: int offset, text_len: int text_len)
  : [count:pos] (PIECES(cs, offset, text_len, count) | int count) =
  if text_len < 65536 then (PIECES_last{cs}{offset}{text_len}() | 1)
  else let
    val (cut_proof | cut) = cut_find(bytes, offset, text_len)
    val (rest | count) = _pieces_find(bytes, offset + cut, text_len - cut)
  in (PIECES_more(cut_proof, rest) | count + 1) end

(* fixture: how-many-pieces-the-text-is *)
(* How many pieces the text is: the one count render, search and read
   aloud all take *)
#pub fun pieces_find {l:agz}{n:pos}{cs:$A.cells}{offset,text_len:nat | offset + text_len <= n}
  (bytes: !$A.cborrow(l, n, cs), offset: int offset, text_len: int text_len)
  : [count:pos] (PIECES(cs, offset, text_len, count) | int count)

implement pieces_find {l}{n}{cs}{offset,text_len} (bytes, offset, text_len) =
  _pieces_find(bytes, offset, text_len)

(* ===== two takes of one entry are cut alike (#849) =====
   The cells a relation is decided from are the cells of the array read, and two takes of one entry, by one method, are two
   arrays (the walks of render, search and read aloud each take their own). They hold one list of octets (text_taken_functional),
   so a cell of one is the cell of the other at the same place, and a cut, a count of pieces found over the cells of one is the
   same over the cells of the other. *)

(* The octets a HOLDS says are a list of the count it says *)
prfun _holds_len {cells:$A.cells}{i:nat}{octets:bytes}{count:nat} .<count>.
  (held: HOLDS(cells, i, octets, count)): LEN(octets, count) =
  case+ held of
  | HOLDS_nil(_) => LEN_nil()
  | HOLDS_cons(_, rest) => LEN_cons(_holds_len(rest))

(* A cell of the first cells, within the count they hold the octets for, is the cell of the second cells that holds the octets *)
prfun _nth_across {first_cells,second_cells:$A.cells}{i,at:nat | i <= at}{value:int}{octets:bytes}{count:nat | at < i + count} .<at - i>.
  (first: HOLDS(first_cells, i, octets, count), second: HOLDS(second_cells, i, octets, count), cell: $A.NTH(first_cells, at, value))
  : $A.NTH(second_cells, at, value) =
  case+ first of
  | HOLDS_nil(_) =/=> ()
  | HOLDS_cons(first_cell, first_rest) =>
    (case+ second of
     | HOLDS_cons(second_cell, second_rest) =>
       sif at == i then let
         prval () = $A.nth_functional(first_cell, cell)
       in second_cell end
       else _nth_across(first_rest, second_rest, cell))

prfun _breakback_across {first_cells,second_cells:$A.cells}{offset,at:nat}{floor,back:int}{octets:bytes}{count:nat | offset + at < count} .<at>.
  (first: HOLDS(first_cells, 0, octets, count), second: HOLDS(second_cells, 0, octets, count),
   proof: BREAKBACK(first_cells, offset, at, floor, back)): BREAKBACK(second_cells, offset, at, floor, back) =
  case+ proof of
  | BREAKBACK_start() => BREAKBACK_start()
  | BREAKBACK_floor() => BREAKBACK_floor()
  | BREAKBACK_white(cell, white) => BREAKBACK_white(_nth_across(first, second, cell), white)
  | BREAKBACK_other(cell, not_white, rest) =>
    BREAKBACK_other(_nth_across(first, second, cell), not_white, _breakback_across(first, second, rest))

prfn _cutc_across {first_cells,second_cells:$A.cells}{offset:nat}{text_len,cut:int}{octets:bytes}{count:nat | offset + text_len <= count; 65536 <= text_len}
  (first: HOLDS(first_cells, 0, octets, count), second: HOLDS(second_cells, 0, octets, count),
   proof: CUTC(first_cells, offset, text_len, cut)): CUTC(second_cells, offset, text_len, cut) =
  case+ proof of
  | CUTC_break(back) => CUTC_break(_breakback_across(first, second, back))
  | CUTC_65535(back, cell, starts) =>
    CUTC_65535(_breakback_across(first, second, back), _nth_across(first, second, cell), starts)
  | CUTC_65534(back, cell, continues, second_cell, second_starts) =>
    CUTC_65534(_breakback_across(first, second, back), _nth_across(first, second, cell), continues,
               _nth_across(first, second, second_cell), second_starts)
  | CUTC_65533(back, cell, continues, second_cell, second_continues, third_cell, third_starts) =>
    CUTC_65533(_breakback_across(first, second, back), _nth_across(first, second, cell), continues,
               _nth_across(first, second, second_cell), second_continues, _nth_across(first, second, third_cell), third_starts)
  | CUTC_none_starts(back, cell, continues, second_cell, second_continues, third_cell, third_continues) =>
    CUTC_none_starts(_breakback_across(first, second, back), _nth_across(first, second, cell), continues,
                     _nth_across(first, second, second_cell), second_continues, _nth_across(first, second, third_cell), third_continues)

prfun _pieces_across {first_cells,second_cells:$A.cells}{offset,text_len:nat}{pieces:int}{octets:bytes}{count:nat | offset + text_len <= count} .<text_len>.
  (first: HOLDS(first_cells, 0, octets, count), second: HOLDS(second_cells, 0, octets, count),
   proof: PIECES(first_cells, offset, text_len, pieces)): PIECES(second_cells, offset, text_len, pieces) =
  case+ proof of
  | PIECES_last() => PIECES_last()
  | PIECES_more(cut, rest) => PIECES_more(_cutc_across(first, second, cut), _pieces_across(first, second, rest))

(* A count of the pieces of a text over the cells of one take of an entry is the count over the cells of any other take of it by
   the same method: two takes of one entry, by one method, are cut alike. The cells of the two takes are the arrays of two
   walks, so this is what makes render, search and read aloud number a text's pieces alike (and a stored place, the piece's
   content node and an offset in it, the same place in all three) *)
#pub prfun pieces_of_taken_functional {kind:$Z.inflate_kind}{compressed,first_text,second_text:$A.cells}{first_count,second_count:nat}
  {offset,text_len:nat | offset + text_len <= first_count}{first,second:int}
  (TAKEN(kind, compressed, first_text, first_count), TAKEN(kind, compressed, second_text, second_count),
   PIECES(first_text, offset, text_len, first), PIECES(second_text, offset, text_len, second)): [first == second] void

primplement pieces_of_taken_functional {kind}{compressed,first_text,second_text}{first_count,second_count}{offset,text_len}{first,second}
  (first_taken, second_taken, first_pieces, second_pieces) =
  case+ first_taken of
  | TAKEN_of(first_inflates, first_textof, first_held) =>
    (case+ second_taken of
     | TAKEN_of(second_inflates, second_textof, second_held) => let
         prval (_, EQB_refl()) = text_taken_functional(first_inflates, second_inflates, first_textof, second_textof)
         prval EQI_refl() = len_functional(_holds_len(first_held), _holds_len(second_held))
         prval second_over_first = _pieces_across(second_held, first_held, second_pieces)
       in pieces_functional(first_pieces, second_over_first) end)

(* fixture: pieces-of-taken-text *)

end
