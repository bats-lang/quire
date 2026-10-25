(* text_relation -- what a book's text document needs, as a relation over the
   cells of its bytes (array's cells model), proved (quire#845, quire#608).
   Keyword: text-encoding relation. The detail is in .claude/rules/book-text.md. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A

staload "bytes.sats"

(* BYTEAT(cells, i, value): the byte at i of the cells is value, or -1 when i is outside them *)
#pub dataprop BYTEAT($A.cells, int, int) =
  | {cells:$A.cells}{i:nat}{value:int} BYTEAT_in(cells, i, value) of $A.NTH(cells, i, value)
  | {cells:$A.cells}{i:int | i < 0} BYTEAT_before(cells, i, ~1)
  | {cells:$A.cells}{n:nat}{i:int | i >= n} BYTEAT_after(cells, i, ~1) of $A.CLEN(cells, n)

(* The byte at an index is one value *)
#pub prfun byteat_functional {cells:$A.cells}{i:int}{first,second:int}
  (BYTEAT(cells, i, first), BYTEAT(cells, i, second)): [first == second] void

primplement byteat_functional {cells}{i}{first,second} (one, other) =
  case+ one of
  | BYTEAT_in(cell_one) =>
    (case+ other of
     | BYTEAT_in(cell_other) => $A.nth_functional(cell_one, cell_other)
     | BYTEAT_after(length) => let prval () = $A.nth_in_len(cell_one, length) in () end)
  | BYTEAT_before() => (case+ other of BYTEAT_before() => ())
  | BYTEAT_after(length_one) =>
    (case+ other of
     | BYTEAT_in(cell_other) => let prval () = $A.nth_in_len(cell_other, length_one) in () end
     | BYTEAT_after(length_other) => ())

(* UTF8STEP(cells, from, to, wide): one UTF-8 character is the bytes [from, to) of the cells, valid by the
   Unicode standard's table of well-formed sequences (no overlong form, no surrogate, nothing past U+10FFFF);
   wide is 1 for an ASCII character and 2 for any other *)
#pub dataprop UTF8STEP($A.cells, int, int, int) =
  | {cells:$A.cells}{i:nat}{lead:int | 0 <= lead; lead < 128}
    UTF8STEP_one(cells, i, i + 1, 1) of $A.NTH(cells, i, lead)
  | {cells:$A.cells}{i:nat}{lead,first:int | 194 <= lead; lead < 224; 128 <= first; first < 192}
    UTF8STEP_two(cells, i, i + 2, 2) of ($A.NTH(cells, i, lead), $A.NTH(cells, i + 1, first))
  | {cells:$A.cells}{i:nat}{lead,first,second:int | 224 <= lead; lead < 240; 128 <= first; first < 192;
        lead != 224 || 160 <= first; lead != 237 || first < 160; 128 <= second; second < 192}
    UTF8STEP_three(cells, i, i + 3, 2) of ($A.NTH(cells, i, lead), $A.NTH(cells, i + 1, first), $A.NTH(cells, i + 2, second))
  | {cells:$A.cells}{i:nat}{lead,first,second,third:int | 240 <= lead; lead < 245; 128 <= first; first < 192;
        lead != 240 || 144 <= first; lead != 244 || first < 144; 128 <= second; second < 192; 128 <= third; third < 192}
    UTF8STEP_four(cells, i, i + 4, 2) of ($A.NTH(cells, i, lead), $A.NTH(cells, i + 1, first), $A.NTH(cells, i + 2, second), $A.NTH(cells, i + 3, third))

(* A character at an index is one character *)
#pub prfun utf8step_functional {cells:$A.cells}{i:nat}{first_to,second_to,first_wide,second_wide:int}
  (UTF8STEP(cells, i, first_to, first_wide), UTF8STEP(cells, i, second_to, second_wide))
  : [first_to == second_to && first_wide == second_wide] void

primplement utf8step_functional {cells}{i}{first_to,second_to,first_wide,second_wide} (one, other) =
  case+ one of
  | UTF8STEP_one(lead_one) =>
    (case+ other of
     | UTF8STEP_one(lead_other) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_two(lead_other, _) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_three(lead_other, _, _) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_four(lead_other, _, _, _) => $A.nth_functional(lead_one, lead_other))
  | UTF8STEP_two(lead_one, first_one) =>
    (case+ other of
     | UTF8STEP_one(lead_other) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_two(lead_other, first_other) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_three(lead_other, _, _) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_four(lead_other, _, _, _) => $A.nth_functional(lead_one, lead_other))
  | UTF8STEP_three(lead_one, _, _) =>
    (case+ other of
     | UTF8STEP_one(lead_other) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_two(lead_other, _) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_three(lead_other, _, _) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_four(lead_other, _, _, _) => $A.nth_functional(lead_one, lead_other))
  | UTF8STEP_four(lead_one, _, _, _) =>
    (case+ other of
     | UTF8STEP_one(lead_other) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_two(lead_other, _) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_three(lead_other, _, _) => $A.nth_functional(lead_one, lead_other)
     | UTF8STEP_four(lead_other, _, _, _) => $A.nth_functional(lead_one, lead_other))

(* UTF8RUN(cells, from, to, wide): the bytes [from, to) of the cells are whole UTF-8 characters, one
   after another; wide is 1 when they are all ASCII and 2 when one is not *)
#pub dataprop UTF8RUN($A.cells, int, int, int) =
  | {cells:$A.cells}{i:nat} UTF8RUN_empty(cells, i, i, 1)
  | {cells:$A.cells}{i,k,m:nat | i < k; k <= m}{wide:int}
    UTF8RUN_ascii(cells, i, m, wide) of (UTF8STEP(cells, i, k, 1), UTF8RUN(cells, k, m, wide))
  | {cells:$A.cells}{i,k,m:nat | i < k; k <= m}{rest_wide:int}
    UTF8RUN_wide(cells, i, m, 2) of (UTF8STEP(cells, i, k, 2), UTF8RUN(cells, k, m, rest_wide))

(* A run is one run *)
#pub prfun utf8run_functional {cells:$A.cells}{from,to:nat | from <= to}{first_wide,second_wide:int}
  (UTF8RUN(cells, from, to, first_wide), UTF8RUN(cells, from, to, second_wide)): [first_wide == second_wide] void

prfun _utf8run_functional {cells:$A.cells}{from,to:nat | from <= to}{first_wide,second_wide:int} .<to - from>.
  (one: UTF8RUN(cells, from, to, first_wide), other: UTF8RUN(cells, from, to, second_wide)): [first_wide == second_wide] void =
  case+ one of
  | UTF8RUN_empty() =>
    (case+ other of
     | UTF8RUN_empty() => ()
     | UTF8RUN_ascii(_, _) => ()
     | UTF8RUN_wide(_, _) => ())
  | UTF8RUN_ascii(step_one, rest_one) =>
    (case+ other of
     | UTF8RUN_empty() => ()
     | UTF8RUN_ascii(step_other, rest_other) => let
         prval () = utf8step_functional(step_one, step_other)
       in _utf8run_functional(rest_one, rest_other) end
     | UTF8RUN_wide(step_other, _) => let prval () = utf8step_functional(step_one, step_other) in () end)
  | UTF8RUN_wide(step_one, rest_one) =>
    (case+ other of
     | UTF8RUN_empty() => ()
     | UTF8RUN_ascii(step_other, _) => let prval () = utf8step_functional(step_one, step_other) in () end
     | UTF8RUN_wide(step_other, rest_other) => let
         prval () = utf8step_functional(step_one, step_other)
       in () end)

primplement utf8run_functional {cells}{from,to}{first_wide,second_wide} (one, other) = _utf8run_functional(one, other)

(* UTF8BAD(cells, i): the bytes from i do not begin with a whole UTF-8 character: the lead byte is not one,
   or a byte it needs is not there or is not a continuation byte (the table of well-formed sequences) *)
#pub dataprop UTF8BAD($A.cells, int) =
  | {cells:$A.cells}{i:nat}{lead:int | 128 <= lead; lead < 194 || 245 <= lead}
    UTF8BAD_lead(cells, i) of $A.NTH(cells, i, lead)
  | {cells:$A.cells}{i:nat}{lead,first:int | 194 <= lead; lead < 224; first < 128 || 192 <= first}
    UTF8BAD_two(cells, i) of ($A.NTH(cells, i, lead), BYTEAT(cells, i + 1, first))
  | {cells:$A.cells}{i:nat}{lead,first:int | 224 <= lead; lead < 240;
        first < 128 || 192 <= first || (lead == 224 && first < 160) || (lead == 237 && 160 <= first)}
    UTF8BAD_three_first(cells, i) of ($A.NTH(cells, i, lead), BYTEAT(cells, i + 1, first))
  | {cells:$A.cells}{i:nat}{lead,first,second:int | 224 <= lead; lead < 240; 128 <= first; first < 192;
        lead != 224 || 160 <= first; lead != 237 || first < 160; second < 128 || 192 <= second}
    UTF8BAD_three_second(cells, i) of ($A.NTH(cells, i, lead), $A.NTH(cells, i + 1, first), BYTEAT(cells, i + 2, second))
  | {cells:$A.cells}{i:nat}{lead,first:int | 240 <= lead; lead < 245;
        first < 128 || 192 <= first || (lead == 240 && first < 144) || (lead == 244 && 144 <= first)}
    UTF8BAD_four_first(cells, i) of ($A.NTH(cells, i, lead), BYTEAT(cells, i + 1, first))
  | {cells:$A.cells}{i:nat}{lead,first,second:int | 240 <= lead; lead < 245; 128 <= first; first < 192;
        lead != 240 || 144 <= first; lead != 244 || first < 144; second < 128 || 192 <= second}
    UTF8BAD_four_second(cells, i) of ($A.NTH(cells, i, lead), $A.NTH(cells, i + 1, first), BYTEAT(cells, i + 2, second))
  | {cells:$A.cells}{i:nat}{lead,first,second,third:int | 240 <= lead; lead < 245; 128 <= first; first < 192;
        lead != 240 || 144 <= first; lead != 244 || first < 144; 128 <= second; second < 192; third < 128 || 192 <= third}
    UTF8BAD_four_third(cells, i) of ($A.NTH(cells, i, lead), $A.NTH(cells, i + 1, first), $A.NTH(cells, i + 2, second), BYTEAT(cells, i + 3, third))

(* A character that is not whole begins at a byte of the cells *)
#pub prfun utf8bad_in_len {cells:$A.cells}{i,n:nat} (UTF8BAD(cells, i), $A.CLEN(cells, n)): [i < n] void

primplement utf8bad_in_len {cells}{i,n} (bad, length) =
  case+ bad of
  | UTF8BAD_lead(lead) => $A.nth_in_len(lead, length)
  | UTF8BAD_two(lead, _) => $A.nth_in_len(lead, length)
  | UTF8BAD_three_first(lead, _) => $A.nth_in_len(lead, length)
  | UTF8BAD_three_second(lead, _, _) => $A.nth_in_len(lead, length)
  | UTF8BAD_four_first(lead, _) => $A.nth_in_len(lead, length)
  | UTF8BAD_four_second(lead, _, _) => $A.nth_in_len(lead, length)
  | UTF8BAD_four_third(lead, _, _, _) => $A.nth_in_len(lead, length)

(* Bytes that begin with a whole character do not begin with one that is not *)
#pub prfun utf8step_not_bad {cells:$A.cells}{i:nat}{to,wide:int} (UTF8STEP(cells, i, to, wide), UTF8BAD(cells, i)): FALSEP()

primplement utf8step_not_bad {cells}{i}{to,wide} (step, bad) =
  case+ step of
  | UTF8STEP_one(lead_step) =>
    (case+ bad of
     | UTF8BAD_lead(lead_bad) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_two(lead_bad, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_three_first(lead_bad, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_three_second(lead_bad, _, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_four_first(lead_bad, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_four_second(lead_bad, _, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_four_third(lead_bad, _, _, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end)
  | UTF8STEP_two(lead_step, first_step) =>
    (case+ bad of
     | UTF8BAD_lead(lead_bad) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_two(lead_bad, first_bad) => let
         prval () = $A.nth_functional(lead_step, lead_bad)
         prval () = byteat_functional(BYTEAT_in(first_step), first_bad)
       in contradiction{0}() end
     | UTF8BAD_three_first(lead_bad, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_three_second(lead_bad, _, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_four_first(lead_bad, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_four_second(lead_bad, _, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_four_third(lead_bad, _, _, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end)
  | UTF8STEP_three(lead_step, first_step, second_step) =>
    (case+ bad of
     | UTF8BAD_lead(lead_bad) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_two(lead_bad, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_three_first(lead_bad, first_bad) => let
         prval () = $A.nth_functional(lead_step, lead_bad)
         prval () = byteat_functional(BYTEAT_in(first_step), first_bad)
       in contradiction{0}() end
     | UTF8BAD_three_second(lead_bad, first_bad, second_bad) => let
         prval () = $A.nth_functional(lead_step, lead_bad)
         prval () = $A.nth_functional(first_step, first_bad)
         prval () = byteat_functional(BYTEAT_in(second_step), second_bad)
       in contradiction{0}() end
     | UTF8BAD_four_first(lead_bad, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_four_second(lead_bad, _, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_four_third(lead_bad, _, _, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end)
  | UTF8STEP_four(lead_step, first_step, second_step, third_step) =>
    (case+ bad of
     | UTF8BAD_lead(lead_bad) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_two(lead_bad, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_three_first(lead_bad, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_three_second(lead_bad, _, _) => let prval () = $A.nth_functional(lead_step, lead_bad) in contradiction{0}() end
     | UTF8BAD_four_first(lead_bad, first_bad) => let
         prval () = $A.nth_functional(lead_step, lead_bad)
         prval () = byteat_functional(BYTEAT_in(first_step), first_bad)
       in contradiction{0}() end
     | UTF8BAD_four_second(lead_bad, first_bad, second_bad) => let
         prval () = $A.nth_functional(lead_step, lead_bad)
         prval () = $A.nth_functional(first_step, first_bad)
         prval () = byteat_functional(BYTEAT_in(second_step), second_bad)
       in contradiction{0}() end
     | UTF8BAD_four_third(lead_bad, first_bad, second_bad, third_bad) => let
         prval () = $A.nth_functional(lead_step, lead_bad)
         prval () = $A.nth_functional(first_step, first_bad)
         prval () = $A.nth_functional(second_step, second_bad)
         prval () = byteat_functional(BYTEAT_in(third_step), third_bad)
       in contradiction{0}() end)

(* Whole characters and then one that is not whole are not whole characters to the end of the cells:
   the document is refused only when no reading of it as UTF-8 exists *)
#pub prfun utf8run_bad_not_complete {cells:$A.cells}{from,bad_at,n:nat | from <= bad_at}{leading_wide,wide:int}
  (UTF8RUN(cells, from, bad_at, leading_wide), UTF8BAD(cells, bad_at), UTF8RUN(cells, from, n, wide), $A.CLEN(cells, n)): FALSEP()

prfun _utf8run_bad_not_complete {cells:$A.cells}{from,bad_at,n:nat | from <= bad_at; from <= n}{leading_wide,wide:int} .<bad_at - from>.
  (leading: UTF8RUN(cells, from, bad_at, leading_wide), bad: UTF8BAD(cells, bad_at), whole: UTF8RUN(cells, from, n, wide), length: $A.CLEN(cells, n)): FALSEP() =
  case+ leading of
  | UTF8RUN_empty() =>
    (case+ whole of
     | UTF8RUN_empty() => let prval () = utf8bad_in_len(bad, length) in contradiction{0}() end
     | UTF8RUN_ascii(step, _) => utf8step_not_bad(step, bad)
     | UTF8RUN_wide(step, _) => utf8step_not_bad(step, bad))
  | UTF8RUN_ascii(step_prefix, rest_prefix) =>
    (case+ whole of
     | UTF8RUN_empty() => let prval () = utf8bad_in_len(bad, length) in contradiction{0}() end
     | UTF8RUN_ascii(step_whole, rest_whole) => let
         prval () = utf8step_functional(step_prefix, step_whole)
       in _utf8run_bad_not_complete(rest_prefix, bad, rest_whole, length) end
     | UTF8RUN_wide(step_whole, _) => let prval () = utf8step_functional(step_prefix, step_whole) in contradiction{0}() end)
  | UTF8RUN_wide(step_prefix, rest_prefix) =>
    (case+ whole of
     | UTF8RUN_empty() => let prval () = utf8bad_in_len(bad, length) in contradiction{0}() end
     | UTF8RUN_ascii(step_whole, _) => let prval () = utf8step_functional(step_prefix, step_whole) in contradiction{0}() end
     | UTF8RUN_wide(step_whole, rest_whole) => let
         prval () = utf8step_functional(step_prefix, step_whole)
       in _utf8run_bad_not_complete(rest_prefix, bad, rest_whole, length) end)

primplement utf8run_bad_not_complete {cells}{from,bad_at,n}{leading_wide,wide} (leading, bad, whole, length) =
  let prval () = utf8bad_in_len(bad, length) in _utf8run_bad_not_complete(leading, bad, whole, length) end

(* A byte that is not -1 is a cell *)
#pub prfun byteat_nth {cells:$A.cells}{i:int}{value:int | 0 <= value} (BYTEAT(cells, i, value)): $A.NTH(cells, i, value)

primplement byteat_nth {cells}{i}{value} (byte) =
  case+ byte of
  | BYTEAT_in(cell) => cell
  | BYTEAT_before() =/=> ()
  | BYTEAT_after(_) =/=> ()

(* Whole characters and then one more are whole characters *)
#pub prfun utf8run_snoc {cells:$A.cells}{from,to,after:nat | from <= to; to < after}{wide,step_wide:int}
  (UTF8RUN(cells, from, to, wide), UTF8STEP(cells, to, after, step_wide))
  : [total:int | (step_wide == 1 && total == wide) || (step_wide == 2 && total == 2)] UTF8RUN(cells, from, after, total)

prfun _utf8run_snoc {cells:$A.cells}{from,to,after:nat | from <= to; to < after}{wide,step_wide:int} .<to - from>.
  (run: UTF8RUN(cells, from, to, wide), step: UTF8STEP(cells, to, after, step_wide))
  : [total:int | (step_wide == 1 && total == wide) || (step_wide == 2 && total == 2)] UTF8RUN(cells, from, after, total) =
  case+ run of
  | UTF8RUN_empty() =>
    (case+ step of
     | UTF8STEP_one(lead) => UTF8RUN_ascii(UTF8STEP_one(lead), UTF8RUN_empty())
     | UTF8STEP_two(lead, first) => UTF8RUN_wide(UTF8STEP_two(lead, first), UTF8RUN_empty())
     | UTF8STEP_three(lead, first, second) => UTF8RUN_wide(UTF8STEP_three(lead, first, second), UTF8RUN_empty())
     | UTF8STEP_four(lead, first, second, third) => UTF8RUN_wide(UTF8STEP_four(lead, first, second, third), UTF8RUN_empty()))
  | UTF8RUN_ascii(head, rest) => UTF8RUN_ascii(head, _utf8run_snoc(rest, step))
  | UTF8RUN_wide(head, rest) => UTF8RUN_wide(head, _utf8run_snoc(rest, step))

primplement utf8run_snoc {cells}{from,to,after}{wide,step_wide} (run, step) = _utf8run_snoc(run, step)

(* UTF8SCAN(cells, from, verdict): the bytes of the cells from `from` on are whole UTF-8 characters to their end
   (verdict 1 when ASCII only, 2 when not), or they are whole characters and then one that is not whole (verdict 0).
   The second is the claim that no reading of them as UTF-8 exists (utf8run_bad_not_complete) *)
#pub dataprop UTF8SCAN($A.cells, int, int) =
  | {cells:$A.cells}{from,n:nat}{wide:int | 1 <= wide; wide <= 2}
    UTF8SCAN_whole(cells, from, wide) of ($A.CLEN(cells, n), UTF8RUN(cells, from, n, wide))
  | {cells:$A.cells}{from,bad_at:nat}{leading_wide:int}
    UTF8SCAN_bad(cells, from, 0) of (UTF8RUN(cells, from, bad_at, leading_wide), UTF8BAD(cells, bad_at))

(* The verdict of a scan, as a value *)
#pub datatype utf8_verdict(int) = Utf8Refused(0) | Utf8AsciiOnly(1) | Utf8Wide(2)

(* The byte at i, or -1 outside the cells, with the proof of it *)
fn _byte_at {l:agz}{n:pos}{cells:$A.cells}{i:int}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, i: int i)
  : [value:int | ~1 <= value; value < 256] (BYTEAT(cells, i, value) | int value) =
  if i < 0 then (BYTEAT_before() | ~1)
  else if i >= n then (BYTEAT_after(length) | ~1)
  else let val (cell | value) = $A.cborrow_get(data, i) in (BYTEAT_in(cell) | value) end

(* Whether a byte can continue a character: 128 to 191 *)
fn _is_continuation {value:int} (value: int value): bool(128 <= value && value < 192) =
  if value >= 128 then (if value < 192 then true else false) else false

(* Whether a byte can follow the lead byte of a three-byte character (the table of well-formed sequences) *)
fn _is_first_of_three {lead,value:int} (lead: int lead, value: int value)
  : bool(128 <= value && value < 192 && (lead != 224 || 160 <= value) && (lead != 237 || value < 160)) =
  if value >= 128 then
    (if value < 192 then
       (if lead = 224 then (if value >= 160 then (if lead = 237 then false else true) else false)
        else if lead = 237 then (if value < 160 then true else false) else true)
     else false)
  else false

(* Whether a byte can follow the lead byte of a four-byte character *)
fn _is_first_of_four {lead,value:int} (lead: int lead, value: int value)
  : bool(128 <= value && value < 192 && (lead != 240 || 144 <= value) && (lead != 244 || value < 144)) =
  if value >= 128 then
    (if value < 192 then
       (if lead = 240 then (if value >= 144 then true else false)
        else if lead = 244 then (if value < 144 then true else false) else true)
     else false)
  else false

(* Reads one character at a time from i, with the proof of the characters read *)
fun _utf8_scan_loop {l:agz}{n:pos}{cells:$A.cells}{from,i:nat | from <= i; i <= n}{wide:int | 1 <= wide; wide <= 2} .<n - i>.
  (length: $A.CLEN(cells, n), run: UTF8RUN(cells, from, i, wide) | data: !$A.cborrow(l, n, cells), n: int n, i: int i, wide: int wide)
  : [verdict:int] (UTF8SCAN(cells, from, verdict) | utf8_verdict(verdict)) =
  if i >= n then
    (if wide = 1 then (UTF8SCAN_whole(length, run) | Utf8AsciiOnly()) else (UTF8SCAN_whole(length, run) | Utf8Wide()))
  else let
    val (lead_cell | lead) = $A.cborrow_get(data, i)
  in
    if lead < 128 then let
        prval run_after = utf8run_snoc(run, UTF8STEP_one(lead_cell))
      in _utf8_scan_loop(length, run_after | data, n, i + 1, wide) end
    else if lead < 194 then (UTF8SCAN_bad(run, UTF8BAD_lead(lead_cell)) | Utf8Refused())
    else if lead < 224 then let
        val (first_byte | first) = _byte_at(length | data, n, i + 1)
      in
        if _is_continuation(first) then let
            prval first_cell = byteat_nth(first_byte)
            prval () = $A.nth_in_len(first_cell, length)
            prval run_after = utf8run_snoc(run, UTF8STEP_two(lead_cell, first_cell))
          in _utf8_scan_loop(length, run_after | data, n, i + 2, 2) end
        else (UTF8SCAN_bad(run, UTF8BAD_two(lead_cell, first_byte)) | Utf8Refused())
      end
    else if lead < 240 then let
        val (first_byte | first) = _byte_at(length | data, n, i + 1)
      in
        if _is_first_of_three(lead, first) then let
            prval first_cell = byteat_nth(first_byte)
            val (second_byte | second) = _byte_at(length | data, n, i + 2)
          in
            if _is_continuation(second) then let
                prval second_cell = byteat_nth(second_byte)
                prval () = $A.nth_in_len(second_cell, length)
                prval run_after = utf8run_snoc(run, UTF8STEP_three(lead_cell, first_cell, second_cell))
              in _utf8_scan_loop(length, run_after | data, n, i + 3, 2) end
            else (UTF8SCAN_bad(run, UTF8BAD_three_second(lead_cell, first_cell, second_byte)) | Utf8Refused())
          end
        else (UTF8SCAN_bad(run, UTF8BAD_three_first(lead_cell, first_byte)) | Utf8Refused())
      end
    else if lead < 245 then let
        val (first_byte | first) = _byte_at(length | data, n, i + 1)
      in
        if _is_first_of_four(lead, first) then let
            prval first_cell = byteat_nth(first_byte)
            val (second_byte | second) = _byte_at(length | data, n, i + 2)
          in
            if _is_continuation(second) then let
                prval second_cell = byteat_nth(second_byte)
                val (third_byte | third) = _byte_at(length | data, n, i + 3)
              in
                if _is_continuation(third) then let
                    prval third_cell = byteat_nth(third_byte)
                    prval () = $A.nth_in_len(third_cell, length)
                    prval run_after = utf8run_snoc(run, UTF8STEP_four(lead_cell, first_cell, second_cell, third_cell))
                  in _utf8_scan_loop(length, run_after | data, n, i + 4, 2) end
                else (UTF8SCAN_bad(run, UTF8BAD_four_third(lead_cell, first_cell, second_cell, third_byte)) | Utf8Refused())
              end
            else (UTF8SCAN_bad(run, UTF8BAD_four_second(lead_cell, first_cell, second_byte)) | Utf8Refused())
          end
        else (UTF8SCAN_bad(run, UTF8BAD_four_first(lead_cell, first_byte)) | Utf8Refused())
      end
    else (UTF8SCAN_bad(run, UTF8BAD_lead(lead_cell)) | Utf8Refused())
  end

(* Whether the bytes of the cells from `from` on are UTF-8, with the proof of the answer *)
#pub fn text_utf8_scan {l:agz}{n:pos}{cells:$A.cells}{from:nat | from <= n}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, from: int from)
  : [verdict:int] (UTF8SCAN(cells, from, verdict) | utf8_verdict(verdict))

implement text_utf8_scan {l}{n}{cells}{from} (length | data, n, from) =
  _utf8_scan_loop(length, UTF8RUN_empty() | data, n, from, 1)
