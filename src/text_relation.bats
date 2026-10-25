(* text_relation -- what a book's text document needs, as a relation over the
   cells of its bytes (array's cells model), proved (quire#845, quire#608).
   Keyword: text-encoding relation. The detail is in .claude/rules/book-text.md. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A

staload "bytes.sats"
staload "text_labels.sats"

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

(* BLANKS(cells, from, to): the bytes [from, to) of the cells are blanks (space, tab, line feed, carriage return) *)
#pub dataprop BLANKS($A.cells, int, int) =
  | {cells:$A.cells}{i:nat} BLANKS_none(cells, i, i)
  | {cells:$A.cells}{i,m:nat | i < m}{value:int | value == 32 || value == 9 || value == 10 || value == 13}
    BLANKS_more(cells, i, m) of ($A.NTH(cells, i, value), BLANKS(cells, i + 1, m))

(* One more blank after blanks *)
#pub prfun blanks_snoc {cells:$A.cells}{from,to:nat | from <= to}{value:int | value == 32 || value == 9 || value == 10 || value == 13}
  (BLANKS(cells, from, to), $A.NTH(cells, to, value)): BLANKS(cells, from, to + 1)

prfun _blanks_snoc {cells:$A.cells}{from,to:nat | from <= to}{value:int | value == 32 || value == 9 || value == 10 || value == 13} .<to - from>.
  (blanks: BLANKS(cells, from, to), cell: $A.NTH(cells, to, value)): BLANKS(cells, from, to + 1) =
  case+ blanks of
  | BLANKS_none() => BLANKS_more(cell, BLANKS_none())
  | BLANKS_more(head, rest) => BLANKS_more(head, _blanks_snoc(rest, cell))

primplement blanks_snoc {cells}{from,to}{value} (blanks, cell) = _blanks_snoc(blanks, cell)

(* SKIP(cells, from, to): to is the first index from `from` on that is not a blank, or the end of the cells *)
#pub dataprop SKIP($A.cells, int, int) =
  | {cells:$A.cells}{from,to:nat}{value:int | value != 32; value != 9; value != 10; value != 13}
    SKIP_stop(cells, from, to) of (BLANKS(cells, from, to), BYTEAT(cells, to, value))

(* Skipping blanks ends in one place *)
#pub prfun skip_functional {cells:$A.cells}{from,first_to,second_to:nat | from <= first_to; from <= second_to}
  (SKIP(cells, from, first_to), SKIP(cells, from, second_to)): [first_to == second_to] void

prfun _skip_functional {cells:$A.cells}{from,first_to,second_to:nat | from <= first_to; from <= second_to}
  {first_value,second_value:int | first_value != 32; first_value != 9; first_value != 10; first_value != 13;
   second_value != 32; second_value != 9; second_value != 10; second_value != 13} .<first_to - from>.
  (one: BLANKS(cells, from, first_to), one_end: BYTEAT(cells, first_to, first_value),
   other: BLANKS(cells, from, second_to), other_end: BYTEAT(cells, second_to, second_value)): [first_to == second_to] void =
  case+ one of
  | BLANKS_none() =>
    (case+ other of
     | BLANKS_none() => ()
     | BLANKS_more(cell, _) => byteat_functional(one_end, BYTEAT_in(cell)))
  | BLANKS_more(cell_one, rest_one) =>
    (case+ other of
     | BLANKS_none() => byteat_functional(other_end, BYTEAT_in(cell_one))
     | BLANKS_more(cell_other, rest_other) => let
         prval () = $A.nth_functional(cell_one, cell_other)
       in _skip_functional(rest_one, one_end, rest_other, other_end) end)

primplement skip_functional {cells}{from,first_to,second_to} (one, other) =
  case+ one of
  | SKIP_stop(blanks_one, end_one) =>
    (case+ other of
     | SKIP_stop(blanks_other, end_other) => _skip_functional(blanks_one, end_one, blanks_other, end_other))

(* NOQUOTE(cells, quote, from, to): none of the bytes [from, to) of the cells is the byte quote *)
#pub dataprop NOQUOTE($A.cells, int, int, int) =
  | {cells:$A.cells}{quote:int}{i:nat} NOQUOTE_none(cells, quote, i, i)
  | {cells:$A.cells}{quote:int}{i,m:nat | i < m}{value:int | value != quote}
    NOQUOTE_more(cells, quote, i, m) of ($A.NTH(cells, i, value), NOQUOTE(cells, quote, i + 1, m))

(* One more byte that is not the quote after those that are not *)
#pub prfun noquote_snoc {cells:$A.cells}{quote:int}{from,to:nat | from <= to}{value:int | value != quote}
  (NOQUOTE(cells, quote, from, to), $A.NTH(cells, to, value)): NOQUOTE(cells, quote, from, to + 1)

prfun _noquote_snoc {cells:$A.cells}{quote:int}{from,to:nat | from <= to}{value:int | value != quote} .<to - from>.
  (noquote: NOQUOTE(cells, quote, from, to), cell: $A.NTH(cells, to, value)): NOQUOTE(cells, quote, from, to + 1) =
  case+ noquote of
  | NOQUOTE_none() => NOQUOTE_more(cell, NOQUOTE_none())
  | NOQUOTE_more(head, rest) => NOQUOTE_more(head, _noquote_snoc(rest, cell))

primplement noquote_snoc {cells}{quote}{from,to}{value} (noquote, cell) = _noquote_snoc(noquote, cell)

(* QUOTESTOP(cells, quote, at): the byte at `at` is the quote, or `at` is the end of the cells *)
#pub dataprop QUOTESTOP($A.cells, int, int) =
  | {cells:$A.cells}{quote:int}{at:nat} QUOTESTOP_hit(cells, quote, at) of $A.NTH(cells, at, quote)
  | {cells:$A.cells}{quote:int}{at:nat} QUOTESTOP_end(cells, quote, at) of $A.CLEN(cells, at)

(* FINDQUOTE(cells, quote, from, to): to is the first index from `from` on that holds the byte quote, or the end of the cells *)
#pub dataprop FINDQUOTE($A.cells, int, int, int) =
  | {cells:$A.cells}{quote:int}{from,to:nat}
    FINDQUOTE_found(cells, quote, from, to) of (NOQUOTE(cells, quote, from, to), QUOTESTOP(cells, quote, to))

(* Looking for a quote ends in one place *)
#pub prfun findquote_functional {cells:$A.cells}{quote:int}{from,first_to,second_to:nat | from <= first_to; from <= second_to}
  (FINDQUOTE(cells, quote, from, first_to), FINDQUOTE(cells, quote, from, second_to)): [first_to == second_to] void

prfun _findquote_functional {cells:$A.cells}{quote:int}{from,first_to,second_to:nat | from <= first_to; from <= second_to} .<first_to - from>.
  (one: NOQUOTE(cells, quote, from, first_to), one_stop: QUOTESTOP(cells, quote, first_to),
   other: NOQUOTE(cells, quote, from, second_to), other_stop: QUOTESTOP(cells, quote, second_to)): [first_to == second_to] void =
  case+ one of
  | NOQUOTE_none() =>
    (case+ other of
     | NOQUOTE_none() => ()
     | NOQUOTE_more(cell, _) =>
       (case+ one_stop of
        | QUOTESTOP_hit(hit) => $A.nth_functional(hit, cell)
        | QUOTESTOP_end(length) => $A.nth_in_len(cell, length)))
  | NOQUOTE_more(cell_one, rest_one) =>
    (case+ other of
     | NOQUOTE_none() =>
       (case+ other_stop of
        | QUOTESTOP_hit(hit) => $A.nth_functional(hit, cell_one)
        | QUOTESTOP_end(length) => $A.nth_in_len(cell_one, length))
     | NOQUOTE_more(_, rest_other) => _findquote_functional(rest_one, one_stop, rest_other, other_stop))

primplement findquote_functional {cells}{quote}{from,first_to,second_to} (one, other) =
  case+ one of
  | FINDQUOTE_found(noquote_one, stop_one) =>
    (case+ other of
     | FINDQUOTE_found(noquote_other, stop_other) => _findquote_functional(noquote_one, stop_one, noquote_other, stop_other))

(* Whether a byte is a blank *)
fn _is_blank {value:int} (value: int value): bool(value == 32 || value == 9 || value == 10 || value == 13) =
  if value = 32 then true else if value = 9 then true else if value = 10 then true else if value = 13 then true else false

fun _skip_blank_loop {l:agz}{n:pos}{cells:$A.cells}{from,i:nat | from <= i; i <= n} .<n - i>.
  (length: $A.CLEN(cells, n), blanks: BLANKS(cells, from, i) | data: !$A.cborrow(l, n, cells), n: int n, i: int i)
  : [to:nat | from <= to; to <= n] (SKIP(cells, from, to) | int to) =
  if i >= n then (SKIP_stop(blanks, BYTEAT_after(length)) | i)
  else let
    val (cell | value) = $A.cborrow_get(data, i)
  in
    if _is_blank(value) then _skip_blank_loop(length, blanks_snoc(blanks, cell) | data, n, i + 1)
    else (SKIP_stop(blanks, BYTEAT_in(cell)) | i)
  end

(* Just past the blanks at or after i, with the proof of it *)
#pub fn text_skip_blank {l:agz}{n:pos}{cells:$A.cells}{from:nat | from <= n}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, from: int from)
  : [to:nat | from <= to; to <= n] (SKIP(cells, from, to) | int to)

implement text_skip_blank {l}{n}{cells}{from} (length | data, n, from) =
  _skip_blank_loop(length, BLANKS_none() | data, n, from)

fun _find_quote_loop {l:agz}{n:pos}{cells:$A.cells}{quote:int}{from,i:nat | from <= i; i <= n} .<n - i>.
  (length: $A.CLEN(cells, n), noquote: NOQUOTE(cells, quote, from, i) | data: !$A.cborrow(l, n, cells), n: int n, i: int i, quote: int quote)
  : [to:nat | from <= to; to <= n] (FINDQUOTE(cells, quote, from, to) | int to) =
  if i >= n then (FINDQUOTE_found(noquote, QUOTESTOP_end(length)) | i)
  else let
    val (cell | value) = $A.cborrow_get(data, i)
  in
    if value = quote then (FINDQUOTE_found(noquote, QUOTESTOP_hit(cell)) | i)
    else _find_quote_loop(length, noquote_snoc(noquote, cell) | data, n, i + 1, quote)
  end

(* The first index at or after `from` that holds the byte quote, or n, with the proof of it *)
#pub fn text_find_quote {l:agz}{n:pos}{cells:$A.cells}{quote:int}{from:nat | from <= n}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, from: int from, quote: int quote)
  : [to:nat | from <= to; to <= n] (FINDQUOTE(cells, quote, from, to) | int to)

implement text_find_quote {l}{n}{cells}{quote}{from} (length | data, n, from, quote) =
  _find_quote_loop(length, NOQUOTE_none() | data, n, from, quote)


(* LOWER(raw, lowered): lowered is the byte raw in lower case (A to Z become a to z) *)
#pub dataprop LOWER(int, int) =
  | {raw:int | raw < 65 || 90 < raw} LOWER_same(raw, raw)
  | {raw:int | 65 <= raw; raw <= 90} LOWER_shift(raw, raw + 32)

(* A byte has one lower case *)
#pub prfun lower_functional {raw,first,second:int} (LOWER(raw, first), LOWER(raw, second)): [first == second] void

primplement lower_functional {raw,first,second} (one, other) =
  case+ one of
  | LOWER_same() => (case+ other of LOWER_same() => () | LOWER_shift() => ())
  | LOWER_shift() => (case+ other of LOWER_same() => () | LOWER_shift() => ())

(* LOWERED(cells, from, label): the bytes of the cells from `from` on, in lower case, begin with the bytes label *)
#pub dataprop LOWERED($A.cells, int, bytes) =
  | {cells:$A.cells}{from:nat} LOWERED_nil(cells, from, bnil())
  | {cells:$A.cells}{from:nat}{raw,low:int}{rest:bytes}
    LOWERED_cons(cells, from, bcons(low, rest)) of ($A.NTH(cells, from, raw), LOWER(raw, low), LOWERED(cells, from + 1, rest))

(* LABELIS(cells, from, count, label): the count bytes of the cells from `from`, in lower case, are the bytes label *)
#pub dataprop LABELIS($A.cells, int, int, bytes) =
  | {cells:$A.cells}{from,count:nat}{label:bytes}
    LABELIS_mk(cells, from, count, label) of (LOWERED(cells, from, label), LEN(label, count))

(* The lower case of the same bytes is one byte string, when it is of one length *)
#pub prfun lowered_functional {cells:$A.cells}{from,count:nat}{first,second:bytes}
  (LOWERED(cells, from, first), LOWERED(cells, from, second), LEN(first, count), LEN(second, count)): EQB(first, second)

prfun _lowered_functional {cells:$A.cells}{from,count:nat}{first,second:bytes} .<count>.
  (lowered_first: LOWERED(cells, from, first), lowered_second: LOWERED(cells, from, second), len_first: LEN(first, count), len_second: LEN(second, count)): EQB(first, second) =
  case+ len_first of
  | LEN_nil() => (case+ len_second of LEN_nil() => EQB_refl())
  | LEN_cons(rest_len_first) =>
    (case+ len_second of
     | LEN_cons(rest_len_second) =>
       (case+ lowered_first of
        | LOWERED_cons(cell_first, lower_first, rest_first) =>
          (case+ lowered_second of
           | LOWERED_cons(cell_second, lower_second, rest_second) => let
               prval () = $A.nth_functional(cell_first, cell_second)
               prval () = lower_functional(lower_first, lower_second)
               prval EQB_refl() = _lowered_functional(rest_first, rest_second, rest_len_first, rest_len_second)
             in EQB_refl() end)))

primplement lowered_functional {cells}{from,count}{first,second} (lowered_first, lowered_second, len_first, len_second) =
  _lowered_functional(lowered_first, lowered_second, len_first, len_second)

(* DIFFFROM(cells, from, label): the bytes of the cells from `from` on, in lower case, differ from label at some byte *)
#pub dataprop DIFFFROM($A.cells, int, bytes) =
  | {cells:$A.cells}{from:nat}{raw,low,expected:int | low != expected}{rest:bytes}
    DIFFFROM_head(cells, from, bcons(expected, rest)) of ($A.NTH(cells, from, raw), LOWER(raw, low))
  | {cells:$A.cells}{from:nat}{raw,expected:int}{rest:bytes}
    DIFFFROM_tail(cells, from, bcons(expected, rest)) of ($A.NTH(cells, from, raw), LOWER(raw, expected), DIFFFROM(cells, from + 1, rest))

(* LABELDIFF(cells, from, count, label): the count bytes of the cells from `from`, in lower case, are not the bytes
   label: label is of another length, or a byte differs *)
#pub dataprop LABELDIFF($A.cells, int, int, bytes) =
  | {cells:$A.cells}{from,count:nat}{label:bytes}{label_count:nat | label_count != count}
    LABELDIFF_length(cells, from, count, label) of LEN(label, label_count)
  | {cells:$A.cells}{from,count:nat}{label:bytes}
    LABELDIFF_byte(cells, from, count, label) of DIFFFROM(cells, from, label)

prfun _lowered_not_diff {cells:$A.cells}{from,count:nat}{label:bytes} .<count>.
  (lowered: LOWERED(cells, from, label), diff: DIFFFROM(cells, from, label), label_len: LEN(label, count)): FALSEP() =
  case+ label_len of
  | LEN_nil() => (case+ lowered of LOWERED_nil() => (case+ diff of DIFFFROM_head(_, _) =/=> () | DIFFFROM_tail(_, _, _) =/=> ()))
  | LEN_cons(rest_len) =>
    (case+ lowered of
     | LOWERED_cons(cell, lower, rest_lowered) =>
       (case+ diff of
        | DIFFFROM_head(cell_diff, lower_diff) => let
            prval () = $A.nth_functional(cell, cell_diff)
            prval () = lower_functional(lower, lower_diff)
          in contradiction{0}() end
        | DIFFFROM_tail(cell_diff, lower_diff, rest_diff) => _lowered_not_diff(rest_lowered, rest_diff, rest_len)))

(* Bytes are not both the label and not the label *)
#pub prfun labelis_not_diff {cells:$A.cells}{from,count:nat}{label:bytes}
  (LABELIS(cells, from, count, label), LABELDIFF(cells, from, count, label)): FALSEP()

primplement labelis_not_diff {cells}{from,count}{label} (is, diff) =
  case+ is of
  | LABELIS_mk(lowered, label_len) =>
    (case+ diff of
     | LABELDIFF_length(other_len) => let prval EQI_refl() = len_functional(label_len, other_len) in contradiction{0}() end
     | LABELDIFF_byte(different) => _lowered_not_diff(lowered, different, label_len))

(* ALLDIFF(cells, from, count, tried): the bytes are none of the first `tried` labels of the table *)
#pub dataprop ALLDIFF($A.cells, int, int, int) =
  | {cells:$A.cells}{from,count:nat} ALLDIFF_none(cells, from, count, 0)
  | {cells:$A.cells}{from,count:nat}{tried:nat | tried < LABEL_COUNT}{label:bytes}{source:int}
    ALLDIFF_more(cells, from, count, tried + 1) of (ALLDIFF(cells, from, count, tried), ENTRY(tried, label, source), LABELDIFF(cells, from, count, label))

(* Bytes that are none of the labels tried are not any one of them *)
#pub prfun alldiff_get {cells:$A.cells}{from,count:nat}{tried,index:nat | index < tried}{label:bytes}{source:int}
  (ALLDIFF(cells, from, count, tried), ENTRY(index, label, source)): LABELDIFF(cells, from, count, label)

prfun _alldiff_get {cells:$A.cells}{from,count:nat}{tried,index:nat | index < tried}{label:bytes}{source:int} .<tried>.
  (all: ALLDIFF(cells, from, count, tried), entry: ENTRY(index, label, source)): LABELDIFF(cells, from, count, label) =
  case+ all of
  | ALLDIFF_none() =/=> ()
  | ALLDIFF_more(rest, last_entry, last_diff) =>
    sif index == tried - 1 then let
        prval (EQB_refl(), _) = entry_functional(last_entry, entry)
      in last_diff end
    else _alldiff_get(rest, entry)

primplement alldiff_get {cells}{from,count}{tried,index}{label}{source} (all, entry) = _alldiff_get(all, entry)

(* LABELSRC(cells, from, count, source): the count bytes of the cells from `from` name the source with that number:
   a label of the table, or none of them (3, the encodings Quire has no table for) *)
#pub dataprop LABELSRC($A.cells, int, int, int) =
  | {cells:$A.cells}{from,count:nat}{index:nat | index < LABEL_COUNT}{label:bytes}{source:int}
    LABELSRC_listed(cells, from, count, source) of (ENTRY(index, label, source), LABELIS(cells, from, count, label))
  | {cells:$A.cells}{from,count:nat}
    LABELSRC_unsupported(cells, from, count, 3) of ALLDIFF(cells, from, count, LABEL_COUNT)

(* The bytes of a label name one source *)
#pub prfun labelsrc_functional {cells:$A.cells}{from,count:nat}{first,second:int}
  (LABELSRC(cells, from, count, first), LABELSRC(cells, from, count, second)): [first == second] void

primplement labelsrc_functional {cells}{from,count}{first,second} (one, other) =
  case+ one of
  | LABELSRC_listed(entry_one, is_one) =>
    (case+ other of
     | LABELSRC_listed(entry_other, is_other) =>
       (case+ is_one of
        | LABELIS_mk(lowered_one, len_one) =>
          (case+ is_other of
           | LABELIS_mk(lowered_other, len_other) => let
               prval EQB_refl() = lowered_functional(lowered_one, lowered_other, len_one, len_other)
               prval EQI_refl() = entry_label_injective(entry_one, entry_other)
               prval (_, EQI_refl()) = entry_functional(entry_one, entry_other)
             in () end))
     | LABELSRC_unsupported(all) => let
         prval () = entry_below_count(entry_one)
         prval different = alldiff_get(all, entry_one)
       in case+ labelis_not_diff(is_one, different) of FALSEP_mk() =/=> () end)
  | LABELSRC_unsupported(all) =>
    (case+ other of
     | LABELSRC_listed(entry_other, is_other) => let
         prval () = entry_below_count(entry_other)
         prval different = alldiff_get(all, entry_other)
       in case+ labelis_not_diff(is_other, different) of FALSEP_mk() =/=> () end
     | LABELSRC_unsupported(_) => ())

(* The lower case of a byte, with the proof of it *)
fn _lower {raw:int} (raw: int raw): [low:int] (LOWER(raw, low) | int low) =
  if raw >= 65 then (if raw <= 90 then (LOWER_shift() | raw + 32) else (LOWER_same() | raw))
  else (LOWER_same() | raw)

(* LOWEREDCMP(cells, from, label, same): the bytes from `from`, in lower case, begin with label (same) or differ from it *)
#pub dataprop LOWEREDCMP($A.cells, int, bytes, bool) =
  | {cells:$A.cells}{from:nat}{label:bytes} LOWEREDCMP_same(cells, from, label, true) of LOWERED(cells, from, label)
  | {cells:$A.cells}{from:nat}{label:bytes} LOWEREDCMP_diff(cells, from, label, false) of DIFFFROM(cells, from, label)

fun _lowered_compare {l:agz}{n:pos}{cells:$A.cells}{from:nat}{label:bytes}{count:nat | from + count <= n} .<count>.
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, from: int from, text: !blist(label, count))
  : [same:bool] (LOWEREDCMP(cells, from, label, same) | bool same) =
  case+ text of
  | blist_nil() => (LOWEREDCMP_same(LOWERED_nil()) | true)
  | blist_cons(expected, rest) => let
      val (cell | raw) = $A.cborrow_get(data, from)
      val (lower | low) = _lower(raw)
    in
      if low = expected then let
          val (rest_compare | same) = _lowered_compare(length | data, n, from + 1, rest)
        in
          if same then let prval LOWEREDCMP_same(rest_lowered) = rest_compare
            in (LOWEREDCMP_same(LOWERED_cons(cell, lower, rest_lowered)) | true) end
          else let prval LOWEREDCMP_diff(rest_different) = rest_compare
            in (LOWEREDCMP_diff(DIFFFROM_tail(cell, lower, rest_different)) | false) end
        end
      else (LOWEREDCMP_diff(DIFFFROM_head(cell, lower)) | false)
    end

(* LABELCMP(cells, from, count, label, same): the count bytes from `from` are the label (same) or are not *)
#pub dataprop LABELCMP($A.cells, int, int, bytes, bool) =
  | {cells:$A.cells}{from,count:nat}{label:bytes} LABELCMP_is(cells, from, count, label, true) of LABELIS(cells, from, count, label)
  | {cells:$A.cells}{from,count:nat}{label:bytes} LABELCMP_diff(cells, from, count, label, false) of LABELDIFF(cells, from, count, label)

fn _label_compare {l:agz}{n:pos}{cells:$A.cells}{from,count:nat | from + count <= n}{label:bytes}{label_count:nat}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, from: int from, count: int count, text: !blist(label, label_count))
  : [same:bool] (LABELCMP(cells, from, count, label, same) | bool same) = let
  val (text_len | text_count) = blist_len(text)
in
  if text_count <> count then (LABELCMP_diff(LABELDIFF_length(text_len)) | false)
  else let
      val (compare | same) = _lowered_compare(length | data, n, from, text)
    in
      if same then let prval LOWEREDCMP_same(lowered) = compare in (LABELCMP_is(LABELIS_mk(lowered, text_len)) | true) end
      else let prval LOWEREDCMP_diff(different) = compare in (LABELCMP_diff(LABELDIFF_byte(different)) | false) end
    end
end

fun _label_loop {l:agz}{n:pos}{cells:$A.cells}{from,count:nat | from + count <= n}{tried:nat | tried <= LABEL_COUNT} .<LABEL_COUNT - tried>.
  (length: $A.CLEN(cells, n), all: ALLDIFF(cells, from, count, tried) | data: !$A.cborrow(l, n, cells), n: int n, from: int from, count: int count, tried: int tried)
  : [source:int] (LABELSRC(cells, from, count, source) | label_source(source)) =
  if tried >= text_label_total() then (LABELSRC_unsupported(all) | LabelUnsupported())
  else let
    val (entry | text, source) = text_entry_label(tried)
    val (compare | same) = _label_compare(length | data, n, from, count, text)
    val () = blist_free(text)
  in
    if same then let prval LABELCMP_is(is) = compare in (LABELSRC_listed(entry, is) | source) end
    else let prval LABELCMP_diff(different) = compare
      in _label_loop(length, ALLDIFF_more(all, entry, different) | data, n, from, count, tried + 1) end
  end

(* The encoding the count bytes at `from` name, with the proof of it *)
#pub fn text_label_source {l:agz}{n:pos}{cells:$A.cells}{from,count:nat | from + count <= n}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, from: int from, count: int count)
  : [source:int] (LABELSRC(cells, from, count, source) | label_source(source))

implement text_label_source {l}{n}{cells}{from,count} (length | data, n, from, count) =
  _label_loop(length, ALLDIFF_none() | data, n, from, count, 0)

(* ISENCODING(cells, i, same): the bytes at i are "encoding" (same), or one of them is another byte *)
#pub dataprop ISENCODING($A.cells, int, bool) =
  | {cells:$A.cells}{i:nat}
    ISENCODING_yes(cells, i, true) of ($A.NTH(cells, i, 101), $A.NTH(cells, i + 1, 110), $A.NTH(cells, i + 2, 99), $A.NTH(cells, i + 3, 111),
      $A.NTH(cells, i + 4, 100), $A.NTH(cells, i + 5, 105), $A.NTH(cells, i + 6, 110), $A.NTH(cells, i + 7, 103))
  | {cells:$A.cells}{i:nat}{b0,b1,b2,b3,b4,b5,b6,b7:int | b0 != 101 || b1 != 110 || b2 != 99 || b3 != 111 || b4 != 100 || b5 != 105 || b6 != 110 || b7 != 103}
    ISENCODING_no(cells, i, false) of (BYTEAT(cells, i, b0), BYTEAT(cells, i + 1, b1), BYTEAT(cells, i + 2, b2), BYTEAT(cells, i + 3, b3),
      BYTEAT(cells, i + 4, b4), BYTEAT(cells, i + 5, b5), BYTEAT(cells, i + 6, b6), BYTEAT(cells, i + 7, b7))

(* Bytes are "encoding" or are not *)
#pub prfun isencoding_functional {cells:$A.cells}{i:nat}{first,second:bool}
  (ISENCODING(cells, i, first), ISENCODING(cells, i, second)): [first == second] void

primplement isencoding_functional {cells}{i}{first,second} (one, other) =
  case+ one of
  | ISENCODING_yes(a0, a1, a2, a3, a4, a5, a6, a7) =>
    (case+ other of
     | ISENCODING_yes(_, _, _, _, _, _, _, _) => ()
     | ISENCODING_no(c0, c1, c2, c3, c4, c5, c6, c7) => let
         prval () = byteat_functional(BYTEAT_in(a0), c0)
         prval () = byteat_functional(BYTEAT_in(a1), c1)
         prval () = byteat_functional(BYTEAT_in(a2), c2)
         prval () = byteat_functional(BYTEAT_in(a3), c3)
         prval () = byteat_functional(BYTEAT_in(a4), c4)
         prval () = byteat_functional(BYTEAT_in(a5), c5)
         prval () = byteat_functional(BYTEAT_in(a6), c6)
         prval () = byteat_functional(BYTEAT_in(a7), c7)
       in () end)
  | ISENCODING_no(c0, c1, c2, c3, c4, c5, c6, c7) =>
    (case+ other of
     | ISENCODING_yes(a0, a1, a2, a3, a4, a5, a6, a7) => let
         prval () = byteat_functional(BYTEAT_in(a0), c0)
         prval () = byteat_functional(BYTEAT_in(a1), c1)
         prval () = byteat_functional(BYTEAT_in(a2), c2)
         prval () = byteat_functional(BYTEAT_in(a3), c3)
         prval () = byteat_functional(BYTEAT_in(a4), c4)
         prval () = byteat_functional(BYTEAT_in(a5), c5)
         prval () = byteat_functional(BYTEAT_in(a6), c6)
         prval () = byteat_functional(BYTEAT_in(a7), c7)
       in () end
     | ISENCODING_no(_, _, _, _, _, _, _, _) => ())

(* DECLARED(cells, i, source): the XML declaration's text from i, just past "encoding", says the source with that number: UTF-8
   (0) when it says none (no "=", no quote, no closing quote), else what the label in the quotes names *)
#pub dataprop DECLARED($A.cells, int, int) =
  | {cells:$A.cells}{i,equals_at:nat | i <= equals_at}{value:int | value != 61}
    DECLARED_no_equals(cells, i, 0) of (SKIP(cells, i, equals_at), BYTEAT(cells, equals_at, value))
  | {cells:$A.cells}{i,equals_at,quote_at:nat | i <= equals_at; equals_at + 1 <= quote_at}{quote:int | quote != 34; quote != 39}
    DECLARED_no_quote(cells, i, 0) of (SKIP(cells, i, equals_at), $A.NTH(cells, equals_at, 61), SKIP(cells, equals_at + 1, quote_at), BYTEAT(cells, quote_at, quote))
  | {cells:$A.cells}{i,equals_at,quote_at,label_end:nat | i <= equals_at; equals_at + 1 <= quote_at; quote_at + 1 <= label_end}{quote:int | quote == 34 || quote == 39}
    DECLARED_unclosed(cells, i, 0) of (SKIP(cells, i, equals_at), $A.NTH(cells, equals_at, 61), SKIP(cells, equals_at + 1, quote_at),
      $A.NTH(cells, quote_at, quote), NOQUOTE(cells, quote, quote_at + 1, label_end), $A.CLEN(cells, label_end))
  | {cells:$A.cells}{i,equals_at,quote_at,label_end:nat | i <= equals_at; equals_at + 1 <= quote_at; quote_at + 1 <= label_end}{quote:int | quote == 34 || quote == 39}{source:int}
    DECLARED_label(cells, i, source) of (SKIP(cells, i, equals_at), $A.NTH(cells, equals_at, 61), SKIP(cells, equals_at + 1, quote_at),
      $A.NTH(cells, quote_at, quote), NOQUOTE(cells, quote, quote_at + 1, label_end), $A.NTH(cells, label_end, quote),
      LABELSRC(cells, quote_at + 1, label_end - (quote_at + 1), source))

(* The cells have one length *)
#pub prfun clen_functional {cells:$A.cells}{first,second:nat} ($A.CLEN(cells, first), $A.CLEN(cells, second)): [first == second] void

prfun _clen_functional {cells:$A.cells}{first,second:nat} .<first>.
  (one: $A.CLEN(cells, first), other: $A.CLEN(cells, second)): [first == second] void =
  case+ one of
  | $A.CLEN_nil() => (case+ other of $A.CLEN_nil() => ())
  | $A.CLEN_cons(rest_one) => (case+ other of $A.CLEN_cons(rest_other) => _clen_functional(rest_one, rest_other))

primplement clen_functional {cells}{first,second} (one, other) = _clen_functional(one, other)

(* A search for a quote that ends at or past the end of the cells ended because the cells did *)
#pub prfun findquote_open {cells:$A.cells}{quote:int}{from,to,n:nat | n <= to}
  (FINDQUOTE(cells, quote, from, to), $A.CLEN(cells, n)): (NOQUOTE(cells, quote, from, to), $A.CLEN(cells, to))

primplement findquote_open {cells}{quote}{from,to,n} (found, length) =
  case+ found of
  | FINDQUOTE_found(noquote, stop) =>
    (case+ stop of
     | QUOTESTOP_hit(hit) => let
         prval () = $A.nth_in_len(hit, length)
       in case+ contradiction{0}() of FALSEP_mk() =/=> () end
     | QUOTESTOP_end(ended) => (noquote, ended))

(* A search for a quote that ends before the end of the cells ended at the quote *)
#pub prfun findquote_closed {cells:$A.cells}{quote:int}{from,to,n:nat | to < n}
  (FINDQUOTE(cells, quote, from, to), $A.CLEN(cells, n)): (NOQUOTE(cells, quote, from, to), $A.NTH(cells, to, quote))

primplement findquote_closed {cells}{quote}{from,to,n} (found, length) =
  case+ found of
  | FINDQUOTE_found(noquote, stop) =>
    (case+ stop of
     | QUOTESTOP_hit(hit) => (noquote, hit)
     | QUOTESTOP_end(ended) => let
         prval () = clen_functional(ended, length)
       in case+ contradiction{0}() of FALSEP_mk() =/=> () end)

(* Whether a byte is a quote *)
fn _is_quote {value:int} (value: int value): bool(value == 34 || value == 39) =
  if value = 34 then true else if value = 39 then true else false

(* The encoding the XML declaration's text from i, just past "encoding", names (UTF-8 when it names none) *)
fn _declared_proved {l:agz}{n:pos}{cells:$A.cells}{i:nat | i <= n}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, i: int i)
  : [source:int] (DECLARED(cells, i, source) | label_source(source)) = let
  val (skip_equals | equals_at) = text_skip_blank(length | data, n, i)
  val (equals_byte | equals_value) = _byte_at(length | data, n, equals_at)
in
  if equals_value <> 61 then (DECLARED_no_equals(skip_equals, equals_byte) | LabelUtf8())
  else let
      prval equals_cell = byteat_nth(equals_byte)
      prval () = $A.nth_in_len(equals_cell, length)
      val (skip_quote | quote_at) = text_skip_blank(length | data, n, equals_at + 1)
      val (quote_byte | quote) = _byte_at(length | data, n, quote_at)
    in
      if _is_quote(quote) then let
          prval quote_cell = byteat_nth(quote_byte)
          prval () = $A.nth_in_len(quote_cell, length)
          val (found | label_end) = text_find_quote(length | data, n, quote_at + 1, quote)
        in
          if label_end >= n then let
              prval (noquote, ended) = findquote_open(found, length)
            in (DECLARED_unclosed(skip_equals, equals_cell, skip_quote, quote_cell, noquote, ended) | LabelUtf8()) end
          else let
              prval (noquote, closing) = findquote_closed(found, length)
              val (label_source | source) = text_label_source(length | data, n, quote_at + 1, label_end - (quote_at + 1))
            in (DECLARED_label(skip_equals, equals_cell, skip_quote, quote_cell, noquote, closing, label_source) | source) end
        end
      else (DECLARED_no_quote(skip_equals, equals_cell, skip_quote, quote_byte) | LabelUtf8())
    end
end

(* A declaration's text names one source *)
#pub prfun declared_functional {cells:$A.cells}{i:nat}{first,second:int}
  (DECLARED(cells, i, first), DECLARED(cells, i, second)): [first == second] void

primplement declared_functional {cells}{i}{first,second} (one, other) =
  case+ one of
  | DECLARED_no_equals(skip_one, byte_one) =>
    (case+ other of
     | DECLARED_no_equals(_, _) => ()
     | DECLARED_no_quote(skip_other, equals_other, _, _) => let
         prval () = skip_functional(skip_one, skip_other)
       in byteat_functional(byte_one, BYTEAT_in(equals_other)) end
     | DECLARED_unclosed(skip_other, equals_other, _, _, _, _) => let
         prval () = skip_functional(skip_one, skip_other)
       in byteat_functional(byte_one, BYTEAT_in(equals_other)) end
     | DECLARED_label(skip_other, equals_other, _, _, _, _, _) => let
         prval () = skip_functional(skip_one, skip_other)
       in byteat_functional(byte_one, BYTEAT_in(equals_other)) end)
  | DECLARED_no_quote(skip_one, equals_one, quote_skip_one, quote_byte_one) =>
    (case+ other of
     | DECLARED_no_equals(skip_other, byte_other) => let
         prval () = skip_functional(skip_one, skip_other)
       in byteat_functional(byte_other, BYTEAT_in(equals_one)) end
     | DECLARED_no_quote(_, _, _, _) => ()
     | DECLARED_unclosed(skip_other, _, quote_skip_other, quote_other, _, _) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
       in byteat_functional(quote_byte_one, BYTEAT_in(quote_other)) end
     | DECLARED_label(skip_other, _, quote_skip_other, quote_other, _, _, _) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
       in byteat_functional(quote_byte_one, BYTEAT_in(quote_other)) end)
  | DECLARED_unclosed(skip_one, equals_one, quote_skip_one, quote_one, noquote_one, ended_one) =>
    (case+ other of
     | DECLARED_no_equals(skip_other, byte_other) => let
         prval () = skip_functional(skip_one, skip_other)
       in byteat_functional(byte_other, BYTEAT_in(equals_one)) end
     | DECLARED_no_quote(skip_other, _, quote_skip_other, quote_byte_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
       in byteat_functional(quote_byte_other, BYTEAT_in(quote_one)) end
     | DECLARED_unclosed(_, _, _, _, _, _) => ()
     | DECLARED_label(skip_other, _, quote_skip_other, quote_other, noquote_other, closing_other, _) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
         prval () = $A.nth_functional(quote_one, quote_other)
         prval () = findquote_functional(FINDQUOTE_found(noquote_one, QUOTESTOP_end(ended_one)), FINDQUOTE_found(noquote_other, QUOTESTOP_hit(closing_other)))
         prval () = $A.nth_in_len(closing_other, ended_one)
       in () end)
  | DECLARED_label(skip_one, equals_one, quote_skip_one, quote_one, noquote_one, closing_one, label_one) =>
    (case+ other of
     | DECLARED_no_equals(skip_other, byte_other) => let
         prval () = skip_functional(skip_one, skip_other)
       in byteat_functional(byte_other, BYTEAT_in(equals_one)) end
     | DECLARED_no_quote(skip_other, _, quote_skip_other, quote_byte_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
       in byteat_functional(quote_byte_other, BYTEAT_in(quote_one)) end
     | DECLARED_unclosed(skip_other, _, quote_skip_other, quote_other, noquote_other, ended_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
         prval () = $A.nth_functional(quote_one, quote_other)
         prval () = findquote_functional(FINDQUOTE_found(noquote_one, QUOTESTOP_hit(closing_one)), FINDQUOTE_found(noquote_other, QUOTESTOP_end(ended_other)))
         prval () = $A.nth_in_len(closing_one, ended_other)
       in () end
     | DECLARED_label(skip_other, _, quote_skip_other, quote_other, noquote_other, closing_other, label_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
         prval () = $A.nth_functional(quote_one, quote_other)
         prval () = findquote_functional(FINDQUOTE_found(noquote_one, QUOTESTOP_hit(closing_one)), FINDQUOTE_found(noquote_other, QUOTESTOP_hit(closing_other)))
       in labelsrc_functional(label_one, label_other) end)

(* DECLSCAN(cells, i, source): looking from i for the XML declaration's encoding, up to its end ("?>"), the end of the cells
   or 256 bytes: the source with that number (UTF-8, number 0, when it says none) *)
#pub dataprop DECLSCAN($A.cells, int, int) =
  | {cells:$A.cells}{i,n:nat | n <= i} DECLSCAN_end(cells, i, 0) of $A.CLEN(cells, n)
  | {cells:$A.cells}{i:nat | 256 < i} DECLSCAN_limit(cells, i, 0)
  | {cells:$A.cells}{i,n:nat | i < n; i <= 256}
    DECLSCAN_mark(cells, i, 0) of ($A.CLEN(cells, n), $A.NTH(cells, i, 63), BYTEAT(cells, i + 1, 62))
  | {cells:$A.cells}{i,n:nat | i < n; i <= 256}{source:int}
    DECLSCAN_encoding(cells, i, source) of ($A.CLEN(cells, n), ISENCODING(cells, i, true), DECLARED(cells, i + 8, source))
  | {cells:$A.cells}{i,n:nat | i < n; i <= 256}{first,second:int | first != 63 || second != 62}{source:int}
    DECLSCAN_next(cells, i, source) of ($A.CLEN(cells, n), BYTEAT(cells, i, first), BYTEAT(cells, i + 1, second), ISENCODING(cells, i, false), DECLSCAN(cells, i + 1, source))

prfun _declscan_functional {cells:$A.cells}{i:nat | i <= 257}{first,second:int} .<257 - i>.
  (one: DECLSCAN(cells, i, first), other: DECLSCAN(cells, i, second)): [first == second] void =
  case+ one of
  | DECLSCAN_end(length_one) =>
    (case+ other of
     | DECLSCAN_end(_) => ()
     | DECLSCAN_limit() => ()
     | DECLSCAN_mark(length_other, _, _) => clen_functional(length_one, length_other)
     | DECLSCAN_encoding(length_other, _, _) => clen_functional(length_one, length_other)
     | DECLSCAN_next(length_other, _, _, _, _) => clen_functional(length_one, length_other))
  | DECLSCAN_limit() =>
    (case+ other of
     | DECLSCAN_end(_) => ()
     | DECLSCAN_limit() => ()
     | DECLSCAN_mark(_, _, _) => ()
     | DECLSCAN_encoding(_, _, _) => ()
     | DECLSCAN_next(_, _, _, _, _) => ())
  | DECLSCAN_mark(length_one, mark_one, close_one) =>
    (case+ other of
     | DECLSCAN_end(length_other) => clen_functional(length_one, length_other)
     | DECLSCAN_limit() => ()
     | DECLSCAN_mark(_, _, _) => ()
     | DECLSCAN_encoding(_, encoding_other, _) =>
       (case+ encoding_other of ISENCODING_yes(first_byte, _, _, _, _, _, _, _) => $A.nth_functional(mark_one, first_byte))
     | DECLSCAN_next(_, first_other, second_other, _, _) => let
         prval () = byteat_functional(first_other, BYTEAT_in(mark_one))
         prval () = byteat_functional(second_other, close_one)
       in () end)
  | DECLSCAN_encoding(length_one, encoding_one, declared_one) =>
    (case+ other of
     | DECLSCAN_end(length_other) => clen_functional(length_one, length_other)
     | DECLSCAN_limit() => ()
     | DECLSCAN_mark(_, mark_other, _) =>
       (case+ encoding_one of ISENCODING_yes(first_byte, _, _, _, _, _, _, _) => $A.nth_functional(mark_other, first_byte))
     | DECLSCAN_encoding(_, _, declared_other) => declared_functional(declared_one, declared_other)
     | DECLSCAN_next(_, _, _, plain_other, _) => isencoding_functional(encoding_one, plain_other))
  | DECLSCAN_next(length_one, first_one, second_one, plain_one, rest_one) =>
    (case+ other of
     | DECLSCAN_end(length_other) => clen_functional(length_one, length_other)
     | DECLSCAN_limit() => ()
     | DECLSCAN_mark(_, mark_other, close_other) => let
         prval () = byteat_functional(first_one, BYTEAT_in(mark_other))
         prval () = byteat_functional(second_one, close_other)
       in () end
     | DECLSCAN_encoding(_, encoding_other, _) => isencoding_functional(plain_one, encoding_other)
     | DECLSCAN_next(_, _, _, _, rest_other) => _declscan_functional(rest_one, rest_other))

(* A scan of a declaration names one source *)
#pub prfun declscan_functional {cells:$A.cells}{i:nat | i <= 257}{first,second:int}
  (DECLSCAN(cells, i, first), DECLSCAN(cells, i, second)): [first == second] void

primplement declscan_functional {cells}{i}{first,second} (one, other) = _declscan_functional(one, other)

(* Whether the bytes at i are "encoding", with the proof of the answer *)
fn _is_encoding_at {l:agz}{n:pos}{cells:$A.cells}{i:nat}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, i: int i)
  : [same:bool] (ISENCODING(cells, i, same) | bool same) = let
  val (p0 | a0) = _byte_at(length | data, n, i)
  val (p1 | a1) = _byte_at(length | data, n, i + 1)
  val (p2 | a2) = _byte_at(length | data, n, i + 2)
  val (p3 | a3) = _byte_at(length | data, n, i + 3)
  val (p4 | a4) = _byte_at(length | data, n, i + 4)
  val (p5 | a5) = _byte_at(length | data, n, i + 5)
  val (p6 | a6) = _byte_at(length | data, n, i + 6)
  val (p7 | a7) = _byte_at(length | data, n, i + 7)
in
  if a0 = 101 then
    (if a1 = 110 then
       (if a2 = 99 then
          (if a3 = 111 then
             (if a4 = 100 then
                (if a5 = 105 then
                   (if a6 = 110 then
                      (if a7 = 103 then
                         (ISENCODING_yes(byteat_nth(p0), byteat_nth(p1), byteat_nth(p2), byteat_nth(p3), byteat_nth(p4), byteat_nth(p5), byteat_nth(p6), byteat_nth(p7)) | true)
                       else (ISENCODING_no(p0, p1, p2, p3, p4, p5, p6, p7) | false))
                    else (ISENCODING_no(p0, p1, p2, p3, p4, p5, p6, p7) | false))
                 else (ISENCODING_no(p0, p1, p2, p3, p4, p5, p6, p7) | false))
              else (ISENCODING_no(p0, p1, p2, p3, p4, p5, p6, p7) | false))
           else (ISENCODING_no(p0, p1, p2, p3, p4, p5, p6, p7) | false))
        else (ISENCODING_no(p0, p1, p2, p3, p4, p5, p6, p7) | false))
     else (ISENCODING_no(p0, p1, p2, p3, p4, p5, p6, p7) | false))
  else (ISENCODING_no(p0, p1, p2, p3, p4, p5, p6, p7) | false)
end

(* Whether two bytes are "?>" *)
fn _is_close {first,second:int} (first: int first, second: int second): bool(first == 63 && second == 62) =
  if first = 63 then (if second = 62 then true else false) else false

fun _declscan_proved {l:agz}{n:pos}{cells:$A.cells}{i:nat | i <= 257} .<257 - i>.
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, i: int i)
  : [source:int] (DECLSCAN(cells, i, source) | label_source(source)) =
  if i >= n then (DECLSCAN_end(length) | LabelUtf8())
  else if i > 256 then (DECLSCAN_limit() | LabelUtf8())
  else let
    val (first_byte | first) = _byte_at(length | data, n, i)
    val (second_byte | second) = _byte_at(length | data, n, i + 1)
  in
    if _is_close(first, second) then (DECLSCAN_mark(length, byteat_nth(first_byte), second_byte) | LabelUtf8())
    else let
        val (encoding | same) = _is_encoding_at(length | data, n, i)
      in
        if same then let
            prval ISENCODING_yes(_, _, _, _, _, _, _, last_byte) = encoding
            prval () = $A.nth_in_len(last_byte, length)
            val (declared | source) = _declared_proved(length | data, n, i + 8)
          in (DECLSCAN_encoding(length, encoding, declared) | source) end
        else let
            val (rest | source) = _declscan_proved(length | data, n, i + 1)
          in (DECLSCAN_next(length, first_byte, second_byte, encoding, rest) | source) end
      end
  end

(* DETECT(cells, source, mark): the document is in the source with that number (0 UTF-8, 1 UTF-16 little endian, 2 UTF-16 big
   endian, 3 unsupported, 4 on a table), and begins with a byte order mark of `mark` bytes (0 when it has none): by its byte
   order mark, by "<" and a null byte, by the encoding its XML declaration names, else UTF-8. A declaration that says UTF-16
   of bytes that are text is wrong about itself and is read as UTF-8 *)
#pub dataprop DETECT($A.cells, int, int) =
  | {cells:$A.cells} DETECT_bom8(cells, 0, 3) of ($A.NTH(cells, 0, 239), $A.NTH(cells, 1, 187), $A.NTH(cells, 2, 191))
  | {cells:$A.cells} DETECT_utf16le_mark(cells, 1, 2) of ($A.NTH(cells, 0, 255), $A.NTH(cells, 1, 254))
  | {cells:$A.cells} DETECT_utf16be_mark(cells, 2, 2) of ($A.NTH(cells, 0, 254), $A.NTH(cells, 1, 255))
  | {cells:$A.cells} DETECT_utf16le_bare(cells, 1, 0) of ($A.NTH(cells, 0, 60), $A.NTH(cells, 1, 0))
  | {cells:$A.cells} DETECT_utf16be_bare(cells, 2, 0) of ($A.NTH(cells, 0, 0), $A.NTH(cells, 1, 60))
  | {cells:$A.cells}{declared:int | declared == 1 || declared == 2}
    DETECT_declared_text(cells, 0, 0) of ($A.NTH(cells, 0, 60), $A.NTH(cells, 1, 63), $A.NTH(cells, 2, 120), $A.NTH(cells, 3, 109), $A.NTH(cells, 4, 108), DECLSCAN(cells, 5, declared))
  | {cells:$A.cells}{declared:int | declared != 1; declared != 2}
    DETECT_declared(cells, declared, 0) of ($A.NTH(cells, 0, 60), $A.NTH(cells, 1, 63), $A.NTH(cells, 2, 120), $A.NTH(cells, 3, 109), $A.NTH(cells, 4, 108), DECLSCAN(cells, 5, declared))
  | {cells:$A.cells}{b0,b1,b2,b3,b4:int | b0 != 239 || b1 != 187 || b2 != 191; b0 != 255 || b1 != 254; b0 != 254 || b1 != 255;
        b0 != 60 || b1 != 0; b0 != 0 || b1 != 60; b0 != 60 || b1 != 63 || b2 != 120 || b3 != 109 || b4 != 108}
    DETECT_plain(cells, 0, 0) of (BYTEAT(cells, 0, b0), BYTEAT(cells, 1, b1), BYTEAT(cells, 2, b2), BYTEAT(cells, 3, b3), BYTEAT(cells, 4, b4))


(* A document is in one encoding *)
#pub prfun detect_functional {cells:$A.cells}{first_source,second_source,first_mark,second_mark:int}
  (DETECT(cells, first_source, first_mark), DETECT(cells, second_source, second_mark))
  : [first_source == second_source && first_mark == second_mark] void

primplement detect_functional {cells}{first_source,second_source,first_mark,second_mark} (one, other) =
  case+ one of
  | DETECT_bom8(one_0, one_1, one_2) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => ()
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
         prval () = byteat_functional(other_2, BYTEAT_in(one_2))
       in () end)
  | DETECT_utf16le_mark(one_0, one_1) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_mark(other_0, other_1) => ()
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
       in () end)
  | DETECT_utf16be_mark(one_0, one_1) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_mark(other_0, other_1) => ()
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
       in () end)
  | DETECT_utf16le_bare(one_0, one_1) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_bare(other_0, other_1) => ()
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
       in () end)
  | DETECT_utf16be_bare(one_0, one_1) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_bare(other_0, other_1) => ()
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
       in () end)
  | DETECT_declared_text(one_0, one_1, one_2, one_3, one_4, one_scan) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => ()
     | DETECT_declared(other_0, other_1, other_2, other_3, other_4, other_scan) => declscan_functional(one_scan, other_scan)
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
         prval () = byteat_functional(other_2, BYTEAT_in(one_2))
         prval () = byteat_functional(other_3, BYTEAT_in(one_3))
         prval () = byteat_functional(other_4, BYTEAT_in(one_4))
       in () end)
  | DETECT_declared(one_0, one_1, one_2, one_3, one_4, one_scan) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in () end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => declscan_functional(one_scan, other_scan)
     | DETECT_declared(other_0, other_1, other_2, other_3, other_4, other_scan) => declscan_functional(one_scan, other_scan)
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
         prval () = byteat_functional(other_2, BYTEAT_in(one_2))
         prval () = byteat_functional(other_3, BYTEAT_in(one_3))
         prval () = byteat_functional(other_4, BYTEAT_in(one_4))
       in () end)
  | DETECT_plain(one_0, one_1, one_2, one_3, one_4) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
         prval () = byteat_functional(one_2, BYTEAT_in(other_2))
       in () end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
       in () end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
       in () end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
       in () end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
       in () end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
         prval () = byteat_functional(one_2, BYTEAT_in(other_2))
         prval () = byteat_functional(one_3, BYTEAT_in(other_3))
         prval () = byteat_functional(one_4, BYTEAT_in(other_4))
       in () end
     | DETECT_declared(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
         prval () = byteat_functional(one_2, BYTEAT_in(other_2))
         prval () = byteat_functional(one_3, BYTEAT_in(other_3))
         prval () = byteat_functional(one_4, BYTEAT_in(other_4))
       in () end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => ())

(* Whether two bytes are the two given *)
fn _is_pair {first,second,expected_first,expected_second:int}
  (first: int first, second: int second, expected_first: int expected_first, expected_second: int expected_second)
  : bool(first == expected_first && second == expected_second) =
  if first = expected_first then (if second = expected_second then true else false) else false

(* Whether three bytes are 239, 187, 191 *)
fn _is_utf8_mark {b0,b1,b2:int} (b0: int b0, b1: int b1, b2: int b2): bool(b0 == 239 && b1 == 187 && b2 == 191) =
  if b0 = 239 then (if b1 = 187 then (if b2 = 191 then true else false) else false) else false

(* Whether five bytes are "<?xml" *)
fn _is_xml_start {b0,b1,b2,b3,b4:int} (b0: int b0, b1: int b1, b2: int b2, b3: int b3, b4: int b4)
  : bool(b0 == 60 && b1 == 63 && b2 == 120 && b3 == 109 && b4 == 108) =
  if b0 = 60 then
    (if b1 = 63 then (if b2 = 120 then (if b3 = 109 then (if b4 = 108 then true else false) else false) else false) else false)
  else false

(* Whether a source is UTF-16, in either order *)
fn _is_utf16 {source:int} (source: label_source(source)): bool(source == 1 || source == 2) =
  case+ source of
  | LabelUtf16Le() => true
  | LabelUtf16Be() => true
  | LabelUtf8() => false
  | LabelUnsupported() => false
  | LabelCp1250() => false
  | LabelCp1251() => false
  | LabelCp1252() => false
  | LabelCp1253() => false
  | LabelCp1254() => false
  | LabelCp1255() => false
  | LabelCp1256() => false
  | LabelCp1257() => false
  | LabelIso88592() => false
  | LabelIso88595() => false
  | LabelIso88597() => false
  | LabelIso88598() => false
  | LabelIso885915() => false
  | LabelKoi8r() => false

(* How the document is encoded, and how many bytes at its start are a byte order mark, with the proof of it *)
#pub fn text_detect {l:agz}{n:pos}{cells:$A.cells}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n)
  : [source,mark:int] (DETECT(cells, source, mark) | label_source(source), int mark)

implement text_detect {l}{n}{cells} (length | data, n) = let
  val (p0 | b0) = _byte_at(length | data, n, 0)
  val (p1 | b1) = _byte_at(length | data, n, 1)
  val (p2 | b2) = _byte_at(length | data, n, 2)
  val (p3 | b3) = _byte_at(length | data, n, 3)
  val (p4 | b4) = _byte_at(length | data, n, 4)
in
  if _is_utf8_mark(b0, b1, b2) then (DETECT_bom8(byteat_nth(p0), byteat_nth(p1), byteat_nth(p2)) | LabelUtf8(), 3)
  else if _is_pair(b0, b1, 255, 254) then (DETECT_utf16le_mark(byteat_nth(p0), byteat_nth(p1)) | LabelUtf16Le(), 2)
  else if _is_pair(b0, b1, 254, 255) then (DETECT_utf16be_mark(byteat_nth(p0), byteat_nth(p1)) | LabelUtf16Be(), 2)
  else if _is_pair(b0, b1, 60, 0) then (DETECT_utf16le_bare(byteat_nth(p0), byteat_nth(p1)) | LabelUtf16Le(), 0)
  else if _is_pair(b0, b1, 0, 60) then (DETECT_utf16be_bare(byteat_nth(p0), byteat_nth(p1)) | LabelUtf16Be(), 0)
  else if _is_xml_start(b0, b1, b2, b3, b4) then let
      prval n0 = byteat_nth(p0)
      prval n1 = byteat_nth(p1)
      prval n2 = byteat_nth(p2)
      prval n3 = byteat_nth(p3)
      prval n4 = byteat_nth(p4)
      prval () = $A.nth_in_len(n4, length)
      val (scan | declared) = _declscan_proved(length | data, n, 5)
    in
      (* bytes that are text say UTF-16: they are UTF-8 (or ASCII) that is wrong about itself *)
      if _is_utf16(declared) then (DETECT_declared_text(n0, n1, n2, n3, n4, scan) | LabelUtf8(), 0)
      else (DETECT_declared(n0, n1, n2, n3, n4, scan) | declared, 0)
    end
  else (DETECT_plain(p0, p1, p2, p3, p4) | LabelUtf8(), 0)
end
