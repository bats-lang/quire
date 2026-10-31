(* text_relation -- what a book's text document needs, as a relation over the
   cells of its bytes (array's cells model), proved (quire#845, quire#608).
   Keyword: text-encoding relation. The detail is in .claude/rules/book-text.md. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A

staload "bytes.sats"
staload "bytesarr.sats"
staload "text_labels.sats"
staload "text_codes.sats"

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

(* Whether the characters are all ASCII, or one of them is not *)
#pub datasort spread = SpreadAscii of () | SpreadWide of ()

(* EQSPREAD(first, second): two spreads are one *)
#pub dataprop EQSPREAD(spread, spread) =
  | {same:spread} EQSPREAD_refl(same, same)

(* From a contradiction, one distance and one spread *)
#pub prfun falsep_stepeq {first_to,second_to:int}{first_spread,second_spread:spread}
  (FALSEP()): (EQI(first_to, second_to), EQSPREAD(first_spread, second_spread))

primplement falsep_stepeq {first_to,second_to}{first_spread,second_spread} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

(* From a contradiction, one spread *)
#pub prfun falsep_eqspread {first,second:spread} (FALSEP()): EQSPREAD(first, second)

primplement falsep_eqspread {first,second} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

(* UTF8STEP(cells, from, to, spread): one UTF-8 character is the bytes [from, to) of the cells, valid by the
   Unicode standard's table of well-formed sequences (no overlong form, no surrogate, nothing past U+10FFFF);
   it is ASCII or it is not (wide) *)
#pub dataprop UTF8STEP($A.cells, int, int, spread) =
  | {cells:$A.cells}{i:nat}{lead:int | 0 <= lead; lead < 128}
    UTF8STEP_one(cells, i, i + 1, SpreadAscii()) of $A.NTH(cells, i, lead)
  | {cells:$A.cells}{i:nat}{lead,first:int | 194 <= lead; lead < 224; 128 <= first; first < 192}
    UTF8STEP_two(cells, i, i + 2, SpreadWide()) of ($A.NTH(cells, i, lead), $A.NTH(cells, i + 1, first))
  | {cells:$A.cells}{i:nat}{lead,first,second:int | 224 <= lead; lead < 240; 128 <= first; first < 192;
        lead != 224 || 160 <= first; lead != 237 || first < 160; 128 <= second; second < 192}
    UTF8STEP_three(cells, i, i + 3, SpreadWide()) of ($A.NTH(cells, i, lead), $A.NTH(cells, i + 1, first), $A.NTH(cells, i + 2, second))
  | {cells:$A.cells}{i:nat}{lead,first,second,third:int | 240 <= lead; lead < 245; 128 <= first; first < 192;
        lead != 240 || 144 <= first; lead != 244 || first < 144; 128 <= second; second < 192; 128 <= third; third < 192}
    UTF8STEP_four(cells, i, i + 4, SpreadWide()) of ($A.NTH(cells, i, lead), $A.NTH(cells, i + 1, first), $A.NTH(cells, i + 2, second), $A.NTH(cells, i + 3, third))

(* A character at an index is one character *)
#pub prfun utf8step_functional {cells:$A.cells}{i:nat}{first_to,second_to:int}{first_spread,second_spread:spread}
  (UTF8STEP(cells, i, first_to, first_spread), UTF8STEP(cells, i, second_to, second_spread))
  : (EQI(first_to, second_to), EQSPREAD(first_spread, second_spread))

primplement utf8step_functional {cells}{i}{first_to,second_to}{first_spread,second_spread} (one, other) =
  case+ one of
  | UTF8STEP_one(lead_one) =>
    (case+ other of
     | UTF8STEP_one(lead_other) => (EQI_refl(), EQSPREAD_refl())
     | UTF8STEP_two(lead_other, _) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end
     | UTF8STEP_three(lead_other, _, _) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end
     | UTF8STEP_four(lead_other, _, _, _) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end)
  | UTF8STEP_two(lead_one, _) =>
    (case+ other of
     | UTF8STEP_one(lead_other) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end
     | UTF8STEP_two(lead_other, _) => (EQI_refl(), EQSPREAD_refl())
     | UTF8STEP_three(lead_other, _, _) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end
     | UTF8STEP_four(lead_other, _, _, _) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end)
  | UTF8STEP_three(lead_one, _, _) =>
    (case+ other of
     | UTF8STEP_one(lead_other) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end
     | UTF8STEP_two(lead_other, _) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end
     | UTF8STEP_three(lead_other, _, _) => (EQI_refl(), EQSPREAD_refl())
     | UTF8STEP_four(lead_other, _, _, _) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end)
  | UTF8STEP_four(lead_one, _, _, _) =>
    (case+ other of
     | UTF8STEP_one(lead_other) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end
     | UTF8STEP_two(lead_other, _) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end
     | UTF8STEP_three(lead_other, _, _) => let prval () = $A.nth_functional(lead_one, lead_other) in falsep_stepeq(contradiction{0}()) end
     | UTF8STEP_four(lead_other, _, _, _) => (EQI_refl(), EQSPREAD_refl()))

(* UTF8RUN(cells, from, to, spread): the bytes [from, to) of the cells are whole UTF-8 characters, one
   after another; they are all ASCII or one of them is not *)
#pub dataprop UTF8RUN($A.cells, int, int, spread) =
  | {cells:$A.cells}{i:nat} UTF8RUN_empty(cells, i, i, SpreadAscii())
  | {cells:$A.cells}{i,next,to:nat | i < next; next <= to}{spread:spread}
    UTF8RUN_ascii(cells, i, to, spread) of (UTF8STEP(cells, i, next, SpreadAscii()), UTF8RUN(cells, next, to, spread))
  | {cells:$A.cells}{i,next,to:nat | i < next; next <= to}{rest_spread:spread}
    UTF8RUN_wide(cells, i, to, SpreadWide()) of (UTF8STEP(cells, i, next, SpreadWide()), UTF8RUN(cells, next, to, rest_spread))

(* A run is one run *)
#pub prfun utf8run_functional {cells:$A.cells}{from,to:nat | from <= to}{first_spread,second_spread:spread}
  (UTF8RUN(cells, from, to, first_spread), UTF8RUN(cells, from, to, second_spread)): EQSPREAD(first_spread, second_spread)

prfun _utf8run_functional {cells:$A.cells}{from,to:nat | from <= to}{first_spread,second_spread:spread} .<to - from>.
  (one: UTF8RUN(cells, from, to, first_spread), other: UTF8RUN(cells, from, to, second_spread)): EQSPREAD(first_spread, second_spread) =
  case+ one of
  | UTF8RUN_empty() =>
    (case+ other of
     | UTF8RUN_empty() => EQSPREAD_refl()
     | UTF8RUN_ascii(_, _) => falsep_eqspread(contradiction{0}())
     | UTF8RUN_wide(_, _) => falsep_eqspread(contradiction{0}()))
  | UTF8RUN_ascii(step_one, rest_one) =>
    (case+ other of
     | UTF8RUN_empty() => falsep_eqspread(contradiction{0}())
     | UTF8RUN_ascii(step_other, rest_other) => let
         prval (EQI_refl(), _) = utf8step_functional(step_one, step_other)
       in _utf8run_functional(rest_one, rest_other) end
     | UTF8RUN_wide(step_other, _) => (let prval (_, second_proof) = utf8step_functional(step_one, step_other) in case+ second_proof of EQSPREAD_refl() =/=> () end))
  | UTF8RUN_wide(step_one, rest_one) =>
    (case+ other of
     | UTF8RUN_empty() => falsep_eqspread(contradiction{0}())
     | UTF8RUN_ascii(step_other, _) => (let prval (_, second_proof) = utf8step_functional(step_one, step_other) in case+ second_proof of EQSPREAD_refl() =/=> () end)
     | UTF8RUN_wide(_, _) => EQSPREAD_refl())

primplement utf8run_functional {cells}{from,to}{first_spread,second_spread} (one, other) = _utf8run_functional(one, other)

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
#pub prfun utf8step_not_bad {cells:$A.cells}{i:nat}{to:int}{spread:spread} (UTF8STEP(cells, i, to, spread), UTF8BAD(cells, i)): FALSEP()

primplement utf8step_not_bad {cells}{i}{to}{spread} (step, bad) =
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
#pub prfun utf8run_bad_not_complete {cells:$A.cells}{from,bad_at,n:nat | from <= bad_at}{leading_spread,spread:spread}
  (UTF8RUN(cells, from, bad_at, leading_spread), UTF8BAD(cells, bad_at), UTF8RUN(cells, from, n, spread), $A.CLEN(cells, n)): FALSEP()

prfun _utf8run_bad_not_complete {cells:$A.cells}{from,bad_at,n:nat | from <= bad_at; from <= n}{leading_spread,spread:spread} .<bad_at - from>.
  (leading: UTF8RUN(cells, from, bad_at, leading_spread), bad: UTF8BAD(cells, bad_at), whole: UTF8RUN(cells, from, n, spread), length: $A.CLEN(cells, n)): FALSEP() =
  case+ leading of
  | UTF8RUN_empty() =>
    (case+ whole of
     | UTF8RUN_empty() => let prval () = utf8bad_in_len(bad, length) in contradiction{0}() end
     | UTF8RUN_ascii(step, _) => utf8step_not_bad(step, bad)
     | UTF8RUN_wide(step, _) => utf8step_not_bad(step, bad))
  | UTF8RUN_ascii(step_leading, rest_leading) =>
    (case+ whole of
     | UTF8RUN_empty() => let prval () = utf8bad_in_len(bad, length) in contradiction{0}() end
     | UTF8RUN_ascii(step_whole, rest_whole) => let
         prval (EQI_refl(), _) = utf8step_functional(step_leading, step_whole)
       in _utf8run_bad_not_complete(rest_leading, bad, rest_whole, length) end
     | UTF8RUN_wide(step_whole, _) => (let prval (_, second_proof) = utf8step_functional(step_leading, step_whole) in case+ second_proof of EQSPREAD_refl() =/=> () end))
  | UTF8RUN_wide(step_leading, rest_leading) =>
    (case+ whole of
     | UTF8RUN_empty() => let prval () = utf8bad_in_len(bad, length) in contradiction{0}() end
     | UTF8RUN_ascii(step_whole, _) => (let prval (_, second_proof) = utf8step_functional(step_leading, step_whole) in case+ second_proof of EQSPREAD_refl() =/=> () end)
     | UTF8RUN_wide(step_whole, rest_whole) => let
         prval (EQI_refl(), _) = utf8step_functional(step_leading, step_whole)
       in _utf8run_bad_not_complete(rest_leading, bad, rest_whole, length) end)

primplement utf8run_bad_not_complete {cells}{from,bad_at,n}{leading_spread,spread} (leading, bad, whole, length) =
  let prval () = utf8bad_in_len(bad, length) in _utf8run_bad_not_complete(leading, bad, whole, length) end

(* A byte that is not -1 is a cell *)
#pub prfun byteat_nth {cells:$A.cells}{i:int}{value:int | 0 <= value} (BYTEAT(cells, i, value)): $A.NTH(cells, i, value)

primplement byteat_nth {cells}{i}{value} (byte) =
  case+ byte of
  | BYTEAT_in(cell) => cell
  | BYTEAT_before() =/=> ()
  | BYTEAT_after(_) =/=> ()

(* Whole characters and then an ASCII one are whole characters of the spread they were *)
#pub prfun utf8run_snoc_ascii {cells:$A.cells}{from,to,after:nat | from <= to; to < after}{spread:spread}
  (UTF8RUN(cells, from, to, spread), UTF8STEP(cells, to, after, SpreadAscii())): UTF8RUN(cells, from, after, spread)

prfun _utf8run_snoc_ascii {cells:$A.cells}{from,to,after:nat | from <= to; to < after}{spread:spread} .<to - from>.
  (run: UTF8RUN(cells, from, to, spread), step: UTF8STEP(cells, to, after, SpreadAscii())): UTF8RUN(cells, from, after, spread) =
  case+ run of
  | UTF8RUN_empty() => UTF8RUN_ascii(step, UTF8RUN_empty())
  | UTF8RUN_ascii(head, rest) => UTF8RUN_ascii(head, _utf8run_snoc_ascii(rest, step))
  | UTF8RUN_wide(head, rest) => UTF8RUN_wide(head, _utf8run_snoc_ascii(rest, step))

primplement utf8run_snoc_ascii {cells}{from,to,after}{spread} (run, step) = _utf8run_snoc_ascii(run, step)

(* Whole characters and then one that is not ASCII are whole characters of which one is not ASCII *)
#pub prfun utf8run_snoc_wide {cells:$A.cells}{from,to,after:nat | from <= to; to < after}{spread:spread}
  (UTF8RUN(cells, from, to, spread), UTF8STEP(cells, to, after, SpreadWide())): UTF8RUN(cells, from, after, SpreadWide())

prfun _utf8run_snoc_wide {cells:$A.cells}{from,to,after:nat | from <= to; to < after}{spread:spread} .<to - from>.
  (run: UTF8RUN(cells, from, to, spread), step: UTF8STEP(cells, to, after, SpreadWide())): UTF8RUN(cells, from, after, SpreadWide()) =
  case+ run of
  | UTF8RUN_empty() => UTF8RUN_wide(step, UTF8RUN_empty())
  | UTF8RUN_ascii(head, rest) => UTF8RUN_ascii(head, _utf8run_snoc_wide(rest, step))
  | UTF8RUN_wide(head, rest) => UTF8RUN_wide(head, _utf8run_snoc_wide(rest, step))

primplement utf8run_snoc_wide {cells}{from,to,after}{spread} (run, step) = _utf8run_snoc_wide(run, step)

(* What a scan of bytes for UTF-8 finds: the bytes are not UTF-8, or they are ASCII only, or they are UTF-8 of other characters *)
#pub datasort scanned = ScannedRefused of () | ScannedAscii of () | ScannedWide of ()

(* EQSCANNED(first, second): two verdicts are one *)
#pub dataprop EQSCANNED(scanned, scanned) =
  | {same:scanned} EQSCANNED_refl(same, same)

(* UTF8SCAN(cells, from, verdict): the bytes of the cells from `from` on are whole UTF-8 characters to their end (all ASCII, or not),
   or they are whole characters and then one that is not whole. The second is the claim that no reading of them as UTF-8 exists
   (utf8run_bad_not_complete) *)
#pub dataprop UTF8SCAN($A.cells, int, scanned) =
  | {cells:$A.cells}{from,n:nat | from <= n}
    UTF8SCAN_ascii(cells, from, ScannedAscii()) of ($A.CLEN(cells, n), UTF8RUN(cells, from, n, SpreadAscii()))
  | {cells:$A.cells}{from,n:nat | from <= n}
    UTF8SCAN_wide(cells, from, ScannedWide()) of ($A.CLEN(cells, n), UTF8RUN(cells, from, n, SpreadWide()))
  | {cells:$A.cells}{from,bad_at:nat | from <= bad_at}{leading_spread:spread}
    UTF8SCAN_bad(cells, from, ScannedRefused()) of (UTF8RUN(cells, from, bad_at, leading_spread), UTF8BAD(cells, bad_at))

(* The verdict of a scan, as a value *)
#pub datatype utf8_verdict(scanned) = Utf8Refused(ScannedRefused()) | Utf8AsciiOnly(ScannedAscii()) | Utf8Wide(ScannedWide())

(* Whether the characters read are all ASCII, as a value *)
datatype spread_value(spread) = ValueAscii(SpreadAscii()) | ValueWide(SpreadWide())

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
fun _utf8_scan_loop {l:agz}{n:pos}{cells:$A.cells}{from,i:nat | from <= i; i <= n}{spread:spread} .<n - i>.
  (length: $A.CLEN(cells, n), run: UTF8RUN(cells, from, i, spread) | data: !$A.cborrow(l, n, cells), n: int n, i: int i, flag: spread_value(spread))
  : [verdict:scanned] (UTF8SCAN(cells, from, verdict) | utf8_verdict(verdict)) =
  if i >= n then
    (case+ flag of
     | ValueAscii() => (UTF8SCAN_ascii(length, run) | Utf8AsciiOnly())
     | ValueWide() => (UTF8SCAN_wide(length, run) | Utf8Wide()))
  else let
    val (lead_cell | lead) = $A.cborrow_get(data, i)
  in
    if lead < 128 then let
        prval run_after = utf8run_snoc_ascii(run, UTF8STEP_one(lead_cell))
      in _utf8_scan_loop(length, run_after | data, n, i + 1, flag) end
    else if lead < 194 then (UTF8SCAN_bad(run, UTF8BAD_lead(lead_cell)) | Utf8Refused())
    else if lead < 224 then let
        val (first_byte | first) = _byte_at(length | data, n, i + 1)
      in
        if _is_continuation(first) then let
            prval first_cell = byteat_nth(first_byte)
            prval () = $A.nth_in_len(first_cell, length)
            prval run_after = utf8run_snoc_wide(run, UTF8STEP_two(lead_cell, first_cell))
          in _utf8_scan_loop(length, run_after | data, n, i + 2, ValueWide()) end
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
                prval run_after = utf8run_snoc_wide(run, UTF8STEP_three(lead_cell, first_cell, second_cell))
              in _utf8_scan_loop(length, run_after | data, n, i + 3, ValueWide()) end
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
                    prval run_after = utf8run_snoc_wide(run, UTF8STEP_four(lead_cell, first_cell, second_cell, third_cell))
                  in _utf8_scan_loop(length, run_after | data, n, i + 4, ValueWide()) end
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
  : [verdict:scanned] (UTF8SCAN(cells, from, verdict) | utf8_verdict(verdict))

implement text_utf8_scan {l}{n}{cells}{from} (length | data, n, from) =
  _utf8_scan_loop(length, UTF8RUN_empty() | data, n, from, ValueAscii())

(* BLANKS(cells, from, to): the bytes [from, to) of the cells are blanks (space, tab, line feed, carriage return) *)
#pub dataprop BLANKS($A.cells, int, int) =
  | {cells:$A.cells}{i:nat} BLANKS_none(cells, i, i)
  | {cells:$A.cells}{i,to:nat | i < to}{value:int | value == 32 || value == 9 || value == 10 || value == 13}
    BLANKS_more(cells, i, to) of ($A.NTH(cells, i, value), BLANKS(cells, i + 1, to))

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
  | {cells:$A.cells}{quote:int}{i,to:nat | i < to}{value:int | value != quote}
    NOQUOTE_more(cells, quote, i, to) of ($A.NTH(cells, i, value), NOQUOTE(cells, quote, i + 1, to))

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
  | {cells:$A.cells}{from,count:nat}{tried:nat | tried < LABEL_COUNT}{label:bytes}{source:tsrc}
    ALLDIFF_more(cells, from, count, tried + 1) of (ALLDIFF(cells, from, count, tried), LABELENTRY(tried, label, source), LABELDIFF(cells, from, count, label))

(* Bytes that are none of the labels tried are not any one of them *)
#pub prfun alldiff_get {cells:$A.cells}{from,count:nat}{tried,index:nat | index < tried}{label:bytes}{source:tsrc}
  (ALLDIFF(cells, from, count, tried), LABELENTRY(index, label, source)): LABELDIFF(cells, from, count, label)

prfun _alldiff_get {cells:$A.cells}{from,count:nat}{tried,index:nat | index < tried}{label:bytes}{source:tsrc} .<tried>.
  (all: ALLDIFF(cells, from, count, tried), entry: LABELENTRY(index, label, source)): LABELDIFF(cells, from, count, label) =
  case+ all of
  | ALLDIFF_none() =/=> ()
  | ALLDIFF_more(rest, last_entry, last_diff) =>
    sif index == tried - 1 then let
        prval (EQB_refl(), _) = entry_functional(last_entry, entry)
      in last_diff end
    else _alldiff_get(rest, entry)

primplement alldiff_get {cells}{from,count}{tried,index}{label}{source} (all, entry) = _alldiff_get(all, entry)

(* LABELSRC(cells, from, count, source): the count bytes of the cells from `from` name the source: the one of a label of the table,
   or none of them (an encoding Quire has no table for) *)
#pub dataprop LABELSRC($A.cells, int, int, tsrc) =
  | {cells:$A.cells}{from,count:nat}{index:nat | index < LABEL_COUNT}{label:bytes}{source:tsrc}
    LABELSRC_listed(cells, from, count, source) of (LABELENTRY(index, label, source), LABELIS(cells, from, count, label))
  | {cells:$A.cells}{from,count:nat}
    LABELSRC_unsupported(cells, from, count, SrcUnsupported()) of ALLDIFF(cells, from, count, LABEL_COUNT)

(* The bytes of a label name one source *)
#pub prfun labelsrc_functional {cells:$A.cells}{from,count:nat}{first,second:tsrc}
  (LABELSRC(cells, from, count, first), LABELSRC(cells, from, count, second)): EQSRC(first, second)

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
               prval (_, same) = entry_functional(entry_one, entry_other)
             in same end))
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
     | LABELSRC_unsupported(_) => EQSRC_refl())

(* The lower case of a byte, with the proof of it *)
fn _lower {raw:int} (raw: int raw): [low:int] (LOWER(raw, low) | int low) =
  if raw >= 65 then (if raw <= 90 then (LOWER_shift() | raw + 32) else (LOWER_same() | raw))
  else (LOWER_same() | raw)

(* LOWEREDCMP(cells, from, label, same): the bytes from `from`, in lower case, begin with label (same) or differ from it *)
dataprop LOWEREDCMP($A.cells, int, bytes, bool) =
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
dataprop LABELCMP($A.cells, int, int, bytes, bool) =
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
  : [source:tsrc] (LABELSRC(cells, from, count, source) | label_source(source)) =
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
  : [source:tsrc] (LABELSRC(cells, from, count, source) | label_source(source))

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

(* DECLARED(cells, i, source): the XML declaration's text from i, just past "encoding", says the source: UTF-8
   when it says none (no "=", no quote, no closing quote), else what the label in the quotes names *)
#pub dataprop DECLARED($A.cells, int, tsrc) =
  | {cells:$A.cells}{i,equals_at:nat | i <= equals_at}{value:int | value != 61}
    DECLARED_no_equals(cells, i, SrcUtf8()) of (SKIP(cells, i, equals_at), BYTEAT(cells, equals_at, value))
  | {cells:$A.cells}{i,equals_at,quote_at:nat | i <= equals_at; equals_at + 1 <= quote_at}{quote:int | quote != 34; quote != 39}
    DECLARED_no_quote(cells, i, SrcUtf8()) of (SKIP(cells, i, equals_at), $A.NTH(cells, equals_at, 61), SKIP(cells, equals_at + 1, quote_at), BYTEAT(cells, quote_at, quote))
  | {cells:$A.cells}{i,equals_at,quote_at,label_end:nat | i <= equals_at; equals_at + 1 <= quote_at; quote_at + 1 <= label_end}{quote:int | quote == 34 || quote == 39}
    DECLARED_unclosed(cells, i, SrcUtf8()) of (SKIP(cells, i, equals_at), $A.NTH(cells, equals_at, 61), SKIP(cells, equals_at + 1, quote_at),
      $A.NTH(cells, quote_at, quote), NOQUOTE(cells, quote, quote_at + 1, label_end), $A.CLEN(cells, label_end))
  | {cells:$A.cells}{i,equals_at,quote_at,label_end:nat | i <= equals_at; equals_at + 1 <= quote_at; quote_at + 1 <= label_end}{quote:int | quote == 34 || quote == 39}{source:tsrc}
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
  : [source:tsrc] (DECLARED(cells, i, source) | label_source(source)) = let
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

(* From a contradiction, one source *)
#pub prfun falsep_eqsrc {first,second:tsrc} (FALSEP()): EQSRC(first, second)

primplement falsep_eqsrc {first,second} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

(* A declaration's text names one source *)
#pub prfun declared_functional {cells:$A.cells}{i:nat}{first,second:tsrc}
  (DECLARED(cells, i, first), DECLARED(cells, i, second)): EQSRC(first, second)

primplement declared_functional {cells}{i}{first,second} (one, other) =
  case+ one of
  | DECLARED_no_equals(skip_one, byte_one) =>
    (case+ other of
     | DECLARED_no_equals(_, _) => EQSRC_refl()
     | DECLARED_no_quote(skip_other, equals_other, _, _) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = byteat_functional(byte_one, BYTEAT_in(equals_other))
       in falsep_eqsrc(contradiction{0}()) end
     | DECLARED_unclosed(skip_other, equals_other, _, _, _, _) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = byteat_functional(byte_one, BYTEAT_in(equals_other))
       in falsep_eqsrc(contradiction{0}()) end
     | DECLARED_label(skip_other, equals_other, _, _, _, _, _) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = byteat_functional(byte_one, BYTEAT_in(equals_other))
       in falsep_eqsrc(contradiction{0}()) end)
  | DECLARED_no_quote(skip_one, equals_one, quote_skip_one, quote_byte_one) =>
    (case+ other of
     | DECLARED_no_equals(skip_other, byte_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = byteat_functional(byte_other, BYTEAT_in(equals_one))
       in falsep_eqsrc(contradiction{0}()) end
     | DECLARED_no_quote(_, _, _, _) => EQSRC_refl()
     | DECLARED_unclosed(skip_other, _, quote_skip_other, quote_other, _, _) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
         prval () = byteat_functional(quote_byte_one, BYTEAT_in(quote_other))
       in falsep_eqsrc(contradiction{0}()) end
     | DECLARED_label(skip_other, _, quote_skip_other, quote_other, _, _, _) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
         prval () = byteat_functional(quote_byte_one, BYTEAT_in(quote_other))
       in falsep_eqsrc(contradiction{0}()) end)
  | DECLARED_unclosed(skip_one, equals_one, quote_skip_one, quote_one, noquote_one, ended_one) =>
    (case+ other of
     | DECLARED_no_equals(skip_other, byte_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = byteat_functional(byte_other, BYTEAT_in(equals_one))
       in falsep_eqsrc(contradiction{0}()) end
     | DECLARED_no_quote(skip_other, _, quote_skip_other, quote_byte_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
         prval () = byteat_functional(quote_byte_other, BYTEAT_in(quote_one))
       in falsep_eqsrc(contradiction{0}()) end
     | DECLARED_unclosed(_, _, _, _, _, _) => EQSRC_refl()
     | DECLARED_label(skip_other, _, quote_skip_other, quote_other, noquote_other, closing_other, _) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
         prval () = $A.nth_functional(quote_one, quote_other)
         prval () = findquote_functional(FINDQUOTE_found(noquote_one, QUOTESTOP_end(ended_one)), FINDQUOTE_found(noquote_other, QUOTESTOP_hit(closing_other)))
         prval () = $A.nth_in_len(closing_other, ended_one)
       in falsep_eqsrc(contradiction{0}()) end)
  | DECLARED_label(skip_one, equals_one, quote_skip_one, quote_one, noquote_one, closing_one, label_one) =>
    (case+ other of
     | DECLARED_no_equals(skip_other, byte_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = byteat_functional(byte_other, BYTEAT_in(equals_one))
       in falsep_eqsrc(contradiction{0}()) end
     | DECLARED_no_quote(skip_other, _, quote_skip_other, quote_byte_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
         prval () = byteat_functional(quote_byte_other, BYTEAT_in(quote_one))
       in falsep_eqsrc(contradiction{0}()) end
     | DECLARED_unclosed(skip_other, _, quote_skip_other, quote_other, noquote_other, ended_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
         prval () = $A.nth_functional(quote_one, quote_other)
         prval () = findquote_functional(FINDQUOTE_found(noquote_one, QUOTESTOP_hit(closing_one)), FINDQUOTE_found(noquote_other, QUOTESTOP_end(ended_other)))
         prval () = $A.nth_in_len(closing_one, ended_other)
       in falsep_eqsrc(contradiction{0}()) end
     | DECLARED_label(skip_other, _, quote_skip_other, quote_other, noquote_other, closing_other, label_other) => let
         prval () = skip_functional(skip_one, skip_other)
         prval () = skip_functional(quote_skip_one, quote_skip_other)
         prval () = $A.nth_functional(quote_one, quote_other)
         prval () = findquote_functional(FINDQUOTE_found(noquote_one, QUOTESTOP_hit(closing_one)), FINDQUOTE_found(noquote_other, QUOTESTOP_hit(closing_other)))
       in labelsrc_functional(label_one, label_other) end)

(* DECLSCAN(cells, i, source): looking from i for the XML declaration's encoding, up to its end ("?>"), the end of the cells
   or 256 bytes: the source it says (UTF-8 when it says none) *)
#pub dataprop DECLSCAN($A.cells, int, tsrc) =
  | {cells:$A.cells}{i,n:nat | n <= i} DECLSCAN_end(cells, i, SrcUtf8()) of $A.CLEN(cells, n)
  | {cells:$A.cells}{i:nat | 256 < i} DECLSCAN_limit(cells, i, SrcUtf8())
  | {cells:$A.cells}{i,n:nat | i < n; i <= 256}
    DECLSCAN_mark(cells, i, SrcUtf8()) of ($A.CLEN(cells, n), $A.NTH(cells, i, 63), BYTEAT(cells, i + 1, 62))
  | {cells:$A.cells}{i,n:nat | i < n; i <= 256}{source:tsrc}
    DECLSCAN_encoding(cells, i, source) of ($A.CLEN(cells, n), ISENCODING(cells, i, true), DECLARED(cells, i + 8, source))
  | {cells:$A.cells}{i,n:nat | i < n; i <= 256}{first,second:int | first != 63 || second != 62}{source:tsrc}
    DECLSCAN_next(cells, i, source) of ($A.CLEN(cells, n), BYTEAT(cells, i, first), BYTEAT(cells, i + 1, second), ISENCODING(cells, i, false), DECLSCAN(cells, i + 1, source))

prfun _declscan_functional {cells:$A.cells}{i:nat | i <= 257}{first,second:tsrc} .<257 - i>.
  (one: DECLSCAN(cells, i, first), other: DECLSCAN(cells, i, second)): EQSRC(first, second) =
  case+ one of
  | DECLSCAN_end(length_one) =>
    (case+ other of
     | DECLSCAN_end(_) => EQSRC_refl()
     | DECLSCAN_limit() => EQSRC_refl()
     | DECLSCAN_mark(length_other, _, _) => let prval () = clen_functional(length_one, length_other) in falsep_eqsrc(contradiction{0}()) end
     | DECLSCAN_encoding(length_other, _, _) => let prval () = clen_functional(length_one, length_other) in falsep_eqsrc(contradiction{0}()) end
     | DECLSCAN_next(length_other, _, _, _, _) => let prval () = clen_functional(length_one, length_other) in falsep_eqsrc(contradiction{0}()) end)
  | DECLSCAN_limit() =>
    (case+ other of
     | DECLSCAN_end(_) => EQSRC_refl()
     | DECLSCAN_limit() => EQSRC_refl()
     | DECLSCAN_mark(_, _, _) => falsep_eqsrc(contradiction{0}())
     | DECLSCAN_encoding(_, _, _) => falsep_eqsrc(contradiction{0}())
     | DECLSCAN_next(_, _, _, _, _) => falsep_eqsrc(contradiction{0}()))
  | DECLSCAN_mark(length_one, mark_one, close_one) =>
    (case+ other of
     | DECLSCAN_end(length_other) => let prval () = clen_functional(length_one, length_other) in falsep_eqsrc(contradiction{0}()) end
     | DECLSCAN_limit() => falsep_eqsrc(contradiction{0}())
     | DECLSCAN_mark(_, _, _) => EQSRC_refl()
     | DECLSCAN_encoding(_, encoding_other, _) =>
       (case+ encoding_other of
        | ISENCODING_yes(first_byte, _, _, _, _, _, _, _) => let
            prval () = $A.nth_functional(mark_one, first_byte)
          in falsep_eqsrc(contradiction{0}()) end)
     | DECLSCAN_next(_, first_other, second_other, _, _) => let
         prval () = byteat_functional(first_other, BYTEAT_in(mark_one))
         prval () = byteat_functional(second_other, close_one)
       in falsep_eqsrc(contradiction{0}()) end)
  | DECLSCAN_encoding(length_one, encoding_one, declared_one) =>
    (case+ other of
     | DECLSCAN_end(length_other) => let prval () = clen_functional(length_one, length_other) in falsep_eqsrc(contradiction{0}()) end
     | DECLSCAN_limit() => falsep_eqsrc(contradiction{0}())
     | DECLSCAN_mark(_, mark_other, _) =>
       (case+ encoding_one of
        | ISENCODING_yes(first_byte, _, _, _, _, _, _, _) => let
            prval () = $A.nth_functional(mark_other, first_byte)
          in falsep_eqsrc(contradiction{0}()) end)
     | DECLSCAN_encoding(_, _, declared_other) => declared_functional(declared_one, declared_other)
     | DECLSCAN_next(_, _, _, plain_other, _) => let
         prval () = isencoding_functional(encoding_one, plain_other)
       in falsep_eqsrc(contradiction{0}()) end)
  | DECLSCAN_next(length_one, first_one, second_one, plain_one, rest_one) =>
    (case+ other of
     | DECLSCAN_end(length_other) => let prval () = clen_functional(length_one, length_other) in falsep_eqsrc(contradiction{0}()) end
     | DECLSCAN_limit() => falsep_eqsrc(contradiction{0}())
     | DECLSCAN_mark(_, mark_other, close_other) => let
         prval () = byteat_functional(first_one, BYTEAT_in(mark_other))
         prval () = byteat_functional(second_one, close_other)
       in falsep_eqsrc(contradiction{0}()) end
     | DECLSCAN_encoding(_, encoding_other, _) => let
         prval () = isencoding_functional(plain_one, encoding_other)
       in falsep_eqsrc(contradiction{0}()) end
     | DECLSCAN_next(_, _, _, _, rest_other) => _declscan_functional(rest_one, rest_other))

(* A scan of a declaration names one source *)
#pub prfun declscan_functional {cells:$A.cells}{i:nat | i <= 257}{first,second:tsrc}
  (DECLSCAN(cells, i, first), DECLSCAN(cells, i, second)): EQSRC(first, second)

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
  : [source:tsrc] (DECLSCAN(cells, i, source) | label_source(source)) =
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

(* DETECT(cells, source, mark): the document is in the source, and begins with a byte order mark of `mark` bytes (0 when it has none):
   by its byte order mark, by "<" and a null byte, by the encoding its XML declaration names, else UTF-8. A declaration that says UTF-16
   of bytes that are text is wrong about itself and is read as UTF-8 *)
#pub dataprop DETECT($A.cells, tsrc, int) =
  | {cells:$A.cells} DETECT_bom8(cells, SrcUtf8(), 3) of ($A.NTH(cells, 0, 239), $A.NTH(cells, 1, 187), $A.NTH(cells, 2, 191))
  | {cells:$A.cells} DETECT_utf16le_mark(cells, SrcUtf16(LittleEndian()), 2) of ($A.NTH(cells, 0, 255), $A.NTH(cells, 1, 254))
  | {cells:$A.cells} DETECT_utf16be_mark(cells, SrcUtf16(BigEndian()), 2) of ($A.NTH(cells, 0, 254), $A.NTH(cells, 1, 255))
  | {cells:$A.cells} DETECT_utf16le_bare(cells, SrcUtf16(LittleEndian()), 0) of ($A.NTH(cells, 0, 60), $A.NTH(cells, 1, 0))
  | {cells:$A.cells} DETECT_utf16be_bare(cells, SrcUtf16(BigEndian()), 0) of ($A.NTH(cells, 0, 0), $A.NTH(cells, 1, 60))
  | {cells:$A.cells}{order:byteorder}
    DETECT_declared_text(cells, SrcUtf8(), 0) of ($A.NTH(cells, 0, 60), $A.NTH(cells, 1, 63), $A.NTH(cells, 2, 120), $A.NTH(cells, 3, 109), $A.NTH(cells, 4, 108), DECLSCAN(cells, 5, SrcUtf16(order)))
  | {cells:$A.cells}
    DETECT_declared_utf8(cells, SrcUtf8(), 0) of ($A.NTH(cells, 0, 60), $A.NTH(cells, 1, 63), $A.NTH(cells, 2, 120), $A.NTH(cells, 3, 109), $A.NTH(cells, 4, 108), DECLSCAN(cells, 5, SrcUtf8()))
  | {cells:$A.cells}
    DETECT_declared_unsupported(cells, SrcUnsupported(), 0) of ($A.NTH(cells, 0, 60), $A.NTH(cells, 1, 63), $A.NTH(cells, 2, 120), $A.NTH(cells, 3, 109), $A.NTH(cells, 4, 108), DECLSCAN(cells, 5, SrcUnsupported()))
  | {cells:$A.cells}{page:codepage}
    DETECT_declared_table(cells, SrcTable(page), 0) of ($A.NTH(cells, 0, 60), $A.NTH(cells, 1, 63), $A.NTH(cells, 2, 120), $A.NTH(cells, 3, 109), $A.NTH(cells, 4, 108), DECLSCAN(cells, 5, SrcTable(page)))
  | {cells:$A.cells}{b0,b1,b2,b3,b4:int | b0 != 239 || b1 != 187 || b2 != 191; b0 != 255 || b1 != 254; b0 != 254 || b1 != 255;
        b0 != 60 || b1 != 0; b0 != 0 || b1 != 60; b0 != 60 || b1 != 63 || b2 != 120 || b3 != 109 || b4 != 108}
    DETECT_plain(cells, SrcUtf8(), 0) of (BYTEAT(cells, 0, b0), BYTEAT(cells, 1, b1), BYTEAT(cells, 2, b2), BYTEAT(cells, 3, b3), BYTEAT(cells, 4, b4))

(* From a contradiction, one source and one mark *)
#pub prfun falsep_detect {first_source,second_source:tsrc}{first_mark,second_mark:int}
  (FALSEP()): (EQSRC(first_source, second_source), EQI(first_mark, second_mark))

primplement falsep_detect {first_source,second_source}{first_mark,second_mark} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

(* A document is in one encoding *)
#pub prfun detect_functional {cells:$A.cells}{first_source,second_source:tsrc}{first_mark,second_mark:int}
  (DETECT(cells, first_source, first_mark), DETECT(cells, second_source, second_mark))
  : (EQSRC(first_source, second_source), EQI(first_mark, second_mark))

primplement detect_functional {cells}{first_source,second_source}{first_mark,second_mark} (one, other) =
  case+ one of
  | DETECT_bom8(one_0, one_1, one_2) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => (EQSRC_refl(), EQI_refl())
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_utf8(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_unsupported(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_table(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
         prval () = byteat_functional(other_2, BYTEAT_in(one_2))
       in falsep_detect(contradiction{0}()) end)
  | DETECT_utf16le_mark(one_0, one_1) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_mark(other_0, other_1) => (EQSRC_refl(), EQI_refl())
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_utf8(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_unsupported(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_table(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
       in falsep_detect(contradiction{0}()) end)
  | DETECT_utf16be_mark(one_0, one_1) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_mark(other_0, other_1) => (EQSRC_refl(), EQI_refl())
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_utf8(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_unsupported(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_table(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
       in falsep_detect(contradiction{0}()) end)
  | DETECT_utf16le_bare(one_0, one_1) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_bare(other_0, other_1) => (EQSRC_refl(), EQI_refl())
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_utf8(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_unsupported(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_table(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
       in falsep_detect(contradiction{0}()) end)
  | DETECT_utf16be_bare(one_0, one_1) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_bare(other_0, other_1) => (EQSRC_refl(), EQI_refl())
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_utf8(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_unsupported(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_table(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
       in falsep_detect(contradiction{0}()) end)
  | DETECT_declared_text(one_0, one_1, one_2, one_3, one_4, one_scan) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => (EQSRC_refl(), EQI_refl())
     | DETECT_declared_utf8(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_declared_unsupported(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_declared_table(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
         prval () = byteat_functional(other_2, BYTEAT_in(one_2))
         prval () = byteat_functional(other_3, BYTEAT_in(one_3))
         prval () = byteat_functional(other_4, BYTEAT_in(one_4))
       in falsep_detect(contradiction{0}()) end)
  | DETECT_declared_utf8(one_0, one_1, one_2, one_3, one_4, one_scan) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_declared_utf8(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval EQSRC_refl() = declscan_functional(one_scan, other_scan)
       in (EQSRC_refl(), EQI_refl()) end
     | DETECT_declared_unsupported(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_declared_table(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
         prval () = byteat_functional(other_2, BYTEAT_in(one_2))
         prval () = byteat_functional(other_3, BYTEAT_in(one_3))
         prval () = byteat_functional(other_4, BYTEAT_in(one_4))
       in falsep_detect(contradiction{0}()) end)
  | DETECT_declared_unsupported(one_0, one_1, one_2, one_3, one_4, one_scan) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_declared_utf8(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_declared_unsupported(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval EQSRC_refl() = declscan_functional(one_scan, other_scan)
       in (EQSRC_refl(), EQI_refl()) end
     | DETECT_declared_table(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
         prval () = byteat_functional(other_2, BYTEAT_in(one_2))
         prval () = byteat_functional(other_3, BYTEAT_in(one_3))
         prval () = byteat_functional(other_4, BYTEAT_in(one_4))
       in falsep_detect(contradiction{0}()) end)
  | DETECT_declared_table(one_0, one_1, one_2, one_3, one_4, one_scan) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = $A.nth_functional(one_0, other_0)
         prval () = $A.nth_functional(one_1, other_1)
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_declared_utf8(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_declared_unsupported(other_0, other_1, other_2, other_3, other_4, other_scan) => (case+ declscan_functional(one_scan, other_scan) of EQSRC_refl() =/=> ())
     | DETECT_declared_table(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval EQSRC_refl() = declscan_functional(one_scan, other_scan)
       in (EQSRC_refl(), EQI_refl()) end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => let
         prval () = byteat_functional(other_0, BYTEAT_in(one_0))
         prval () = byteat_functional(other_1, BYTEAT_in(one_1))
         prval () = byteat_functional(other_2, BYTEAT_in(one_2))
         prval () = byteat_functional(other_3, BYTEAT_in(one_3))
         prval () = byteat_functional(other_4, BYTEAT_in(one_4))
       in falsep_detect(contradiction{0}()) end)
  | DETECT_plain(one_0, one_1, one_2, one_3, one_4) =>
    (case+ other of
     | DETECT_bom8(other_0, other_1, other_2) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
         prval () = byteat_functional(one_2, BYTEAT_in(other_2))
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_mark(other_0, other_1) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_mark(other_0, other_1) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16le_bare(other_0, other_1) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
       in falsep_detect(contradiction{0}()) end
     | DETECT_utf16be_bare(other_0, other_1) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_text(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
         prval () = byteat_functional(one_2, BYTEAT_in(other_2))
         prval () = byteat_functional(one_3, BYTEAT_in(other_3))
         prval () = byteat_functional(one_4, BYTEAT_in(other_4))
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_utf8(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
         prval () = byteat_functional(one_2, BYTEAT_in(other_2))
         prval () = byteat_functional(one_3, BYTEAT_in(other_3))
         prval () = byteat_functional(one_4, BYTEAT_in(other_4))
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_unsupported(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
         prval () = byteat_functional(one_2, BYTEAT_in(other_2))
         prval () = byteat_functional(one_3, BYTEAT_in(other_3))
         prval () = byteat_functional(one_4, BYTEAT_in(other_4))
       in falsep_detect(contradiction{0}()) end
     | DETECT_declared_table(other_0, other_1, other_2, other_3, other_4, other_scan) => let
         prval () = byteat_functional(one_0, BYTEAT_in(other_0))
         prval () = byteat_functional(one_1, BYTEAT_in(other_1))
         prval () = byteat_functional(one_2, BYTEAT_in(other_2))
         prval () = byteat_functional(one_3, BYTEAT_in(other_3))
         prval () = byteat_functional(one_4, BYTEAT_in(other_4))
       in falsep_detect(contradiction{0}()) end
     | DETECT_plain(other_0, other_1, other_2, other_3, other_4) => (EQSRC_refl(), EQI_refl()))

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

(* How the document is encoded, and how many bytes at its start are a byte order mark, with the proof of it *)
#pub fn text_detect {l:agz}{n:pos}{cells:$A.cells}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n)
  : [source:tsrc][mark:int] (DETECT(cells, source, mark) | label_source(source), int mark)

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
      case+ declared of
      | LabelUtf16Le() => (DETECT_declared_text(n0, n1, n2, n3, n4, scan) | LabelUtf8(), 0)
      | LabelUtf16Be() => (DETECT_declared_text(n0, n1, n2, n3, n4, scan) | LabelUtf8(), 0)
      | LabelUtf8() => (DETECT_declared_utf8(n0, n1, n2, n3, n4, scan) | LabelUtf8(), 0)
      | LabelUnsupported() => (DETECT_declared_unsupported(n0, n1, n2, n3, n4, scan) | LabelUnsupported(), 0)
      | LabelCp1250() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelCp1251() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelCp1252() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelCp1253() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelCp1254() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelCp1255() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelCp1256() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelCp1257() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelIso88592() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelIso88595() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelIso88597() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelIso88598() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelIso885915() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
      | LabelKoi8r() => (DETECT_declared_table(n0, n1, n2, n3, n4, scan) | declared, 0)
    end
  else (DETECT_plain(p0, p1, p2, p3, p4) | LabelUtf8(), 0)
end

(* From a contradiction, one verdict *)
#pub prfun falsep_eqscanned {first,second:scanned} (FALSEP()): EQSCANNED(first, second)

primplement falsep_eqscanned {first,second} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

(* A scan of the bytes from one place has one verdict *)
#pub prfun utf8scan_functional {cells:$A.cells}{from:nat}{first,second:scanned}
  (UTF8SCAN(cells, from, first), UTF8SCAN(cells, from, second)): EQSCANNED(first, second)

primplement utf8scan_functional {cells}{from}{first,second} (one, other) =
  case+ one of
  | UTF8SCAN_ascii(length_one, run_one) =>
    (case+ other of
     | UTF8SCAN_ascii(_, _) => EQSCANNED_refl()
     | UTF8SCAN_wide(length_other, run_other) => let
         prval () = clen_functional(length_one, length_other)
       in (case+ utf8run_functional(run_one, run_other) of EQSPREAD_refl() =/=> ()) end
     | UTF8SCAN_bad(leading, bad) =>
       (case+ utf8run_bad_not_complete(leading, bad, run_one, length_one) of FALSEP_mk() =/=> ()))
  | UTF8SCAN_wide(length_one, run_one) =>
    (case+ other of
     | UTF8SCAN_ascii(length_other, run_other) => let
         prval () = clen_functional(length_one, length_other)
       in (case+ utf8run_functional(run_one, run_other) of EQSPREAD_refl() =/=> ()) end
     | UTF8SCAN_wide(_, _) => EQSCANNED_refl()
     | UTF8SCAN_bad(leading, bad) =>
       (case+ utf8run_bad_not_complete(leading, bad, run_one, length_one) of FALSEP_mk() =/=> ()))
  | UTF8SCAN_bad(leading, bad) =>
    (case+ other of
     | UTF8SCAN_ascii(length_other, run_other) =>
       (case+ utf8run_bad_not_complete(leading, bad, run_other, length_other) of FALSEP_mk() =/=> ())
     | UTF8SCAN_wide(length_other, run_other) =>
       (case+ utf8run_bad_not_complete(leading, bad, run_other, length_other) of FALSEP_mk() =/=> ())
     | UTF8SCAN_bad(_, _) => EQSCANNED_refl())

(* Cell i of cells that are longer than i is some value *)
#pub prfun nth_exists {cells:$A.cells}{n,i:nat | i < n} ($A.CLEN(cells, n)): [value:int] $A.NTH(cells, i, value)

prfun _nth_exists {cells:$A.cells}{n,i:nat | i < n} .<i>. (length: $A.CLEN(cells, n)): [value:int] $A.NTH(cells, i, value) =
  case+ length of
  | $A.CLEN_nil() =/=> ()
  | $A.CLEN_cons(rest_length) =>
    sif i == 0 then $A.NTH_here() else $A.NTH_there(_nth_exists{..}{n - 1, i - 1}(rest_length))

primplement nth_exists {cells}{n,i} (length) = _nth_exists(length)

(* Cells that are long enough hold some bytes from i, count of them *)
#pub prfun holds_exists {cells:$A.cells}{i,count,n:nat | i + count <= n} ($A.CLEN(cells, n)): [octets:bytes] HOLDS(cells, i, octets, count)

prfun _holds_exists {cells:$A.cells}{i,count,n:nat | i + count <= n} .<count>. (length: $A.CLEN(cells, n)): [octets:bytes] HOLDS(cells, i, octets, count) =
  sif count == 0 then HOLDS_nil(length)
  else HOLDS_cons(nth_exists{cells}{n, i}(length), _holds_exists{cells}{i + 1, count - 1, n}(length))

primplement holds_exists {cells}{i,count,n} (length) = _holds_exists(length)

(* Any byte string followed by another is some byte string *)
#pub prfun append_exists {front,back:bytes}{count:nat} (LEN(front, count)): [joined:bytes] APPEND(front, back, joined)

prfun _append_exists {front,back:bytes}{count:nat} .<count>. (front_len: LEN(front, count)): [joined:bytes] APPEND(front, back, joined) =
  case+ front_len of
  | LEN_nil() => APPEND_nil()
  | LEN_cons(rest_len) => APPEND_cons(_append_exists(rest_len))

primplement append_exists {front,back}{count} (front_len) = _append_exists(front_len)

(* UNIT16(cells, order, i, unit): the two bytes at i are the 16-bit unit, in the order *)
#pub dataprop UNIT16($A.cells, byteorder, int, int) =
  | {cells:$A.cells}{i:nat}{first,second:int | 0 <= first; first < 256; 0 <= second; second < 256}
    UNIT16_le(cells, LittleEndian(), i, first + 256 * second) of ($A.NTH(cells, i, first), $A.NTH(cells, i + 1, second))
  | {cells:$A.cells}{i:nat}{first,second:int | 0 <= first; first < 256; 0 <= second; second < 256}
    UNIT16_be(cells, BigEndian(), i, 256 * first + second) of ($A.NTH(cells, i, first), $A.NTH(cells, i + 1, second))

(* Two bytes make one unit *)
#pub prfun unit16_functional {cells:$A.cells}{order:byteorder}{i:nat}{first,second:int}
  (UNIT16(cells, order, i, first), UNIT16(cells, order, i, second)): [first == second] void

primplement unit16_functional {cells}{order}{i}{first,second} (one, other) =
  case+ one of
  | UNIT16_le(first_one, second_one) =>
    (case+ other of
     | UNIT16_le(first_other, second_other) => let
         prval () = $A.nth_functional(first_one, first_other)
         prval () = $A.nth_functional(second_one, second_other)
       in () end)
  | UNIT16_be(first_one, second_one) =>
    (case+ other of
     | UNIT16_be(first_other, second_other) => let
         prval () = $A.nth_functional(first_one, first_other)
         prval () = $A.nth_functional(second_one, second_other)
       in () end)

(* A unit is within the cells *)
#pub prfun unit16_in_len {cells:$A.cells}{order:byteorder}{i,n:nat}{unit:int} (UNIT16(cells, order, i, unit), $A.CLEN(cells, n)): [i + 1 < n] void

primplement unit16_in_len {cells}{order}{i,n}{unit} (unit_proof, length) =
  case+ unit_proof of
  | UNIT16_le(_, second) => $A.nth_in_len(second, length)
  | UNIT16_be(_, second) => $A.nth_in_len(second, length)

(* A unit is of 16 bits *)
#pub prfun unit16_range {cells:$A.cells}{order:byteorder}{i:nat}{unit:int} (UNIT16(cells, order, i, unit)): [0 <= unit; unit < 65536] void

primplement unit16_range {cells}{order}{i}{unit} (unit_proof) =
  case+ unit_proof of
  | UNIT16_le(_, _) => ()
  | UNIT16_be(_, _) => ()

(* STEPOF(cells, source, from, to, point): one character of a document in the source is the bytes [from, to) of the cells, and
   stands for the code point. UTF-16: a unit that is no half of a pair is its own code point; a high half and a low half are
   one character beyond U+FFFF; a half alone, or a lone byte at the end, is U+FFFD (65533). A single-byte encoding: a byte
   under 128 is itself, the others are what the table says *)
#pub dataprop STEPOF($A.cells, tsrc, int, int, int) =
  | {cells:$A.cells}{order:byteorder}{i,n:nat | n <= i + 1}{first:int}
    STEPOF_truncated(cells, SrcUtf16(order), i, i + 1, 65533) of ($A.NTH(cells, i, first), $A.CLEN(cells, n))
  | {cells:$A.cells}{order:byteorder}{i:nat}{unit:int | unit < 55296 || 57344 <= unit}
    STEPOF_unit(cells, SrcUtf16(order), i, i + 2, unit) of UNIT16(cells, order, i, unit)
  | {cells:$A.cells}{order:byteorder}{i:nat}{high,low:int | 55296 <= high; high < 56320; 56320 <= low; low < 57344}
    STEPOF_pair(cells, SrcUtf16(order), i, i + 4, 65536 + 1024 * (high - 55296) + (low - 56320)) of (UNIT16(cells, order, i, high), UNIT16(cells, order, i + 2, low))
  | {cells:$A.cells}{order:byteorder}{i,n:nat | n <= i + 3}{high:int | 55296 <= high; high < 56320}
    STEPOF_high_at_end(cells, SrcUtf16(order), i, i + 2, 65533) of (UNIT16(cells, order, i, high), $A.CLEN(cells, n))
  | {cells:$A.cells}{order:byteorder}{i:nat}{high,next:int | 55296 <= high; high < 56320; next < 56320 || 57344 <= next}
    STEPOF_high_alone(cells, SrcUtf16(order), i, i + 2, 65533) of (UNIT16(cells, order, i, high), UNIT16(cells, order, i + 2, next))
  | {cells:$A.cells}{order:byteorder}{i:nat}{low:int | 56320 <= low; low < 57344}
    STEPOF_low_alone(cells, SrcUtf16(order), i, i + 2, 65533) of UNIT16(cells, order, i, low)
  | {cells:$A.cells}{page:codepage}{i:nat}{value:int | 0 <= value; value < 128}
    STEPOF_ascii(cells, SrcTable(page), i, i + 1, value) of $A.NTH(cells, i, value)
  | {cells:$A.cells}{page:codepage}{i:nat}{value:int | 128 <= value; value < 256}{point:int}
    STEPOF_table(cells, SrcTable(page), i, i + 1, point) of ($A.NTH(cells, i, value), TABLEAT(page, value, point))

(* A character at a place is one character *)
#pub prfun stepof_functional {cells:$A.cells}{source:tsrc}{i:nat}{first_to,second_to,first_point,second_point:int}
  (STEPOF(cells, source, i, first_to, first_point), STEPOF(cells, source, i, second_to, second_point))
  : [first_to == second_to && first_point == second_point] void

primplement stepof_functional {cells}{source}{i}{first_to,second_to,first_point,second_point} (one, other) =
  case+ one of
  | STEPOF_truncated(one_nth, one_len) =>
    (case+ other of
     | STEPOF_truncated(other_nth, other_len) => ()
     | STEPOF_unit(other_unit) => let
         prval () = unit16_in_len(other_unit, one_len)
       in () end
     | STEPOF_pair(other_unit, other_next) => let
         prval () = unit16_in_len(other_unit, one_len)
       in () end
     | STEPOF_high_at_end(other_unit, other_len) => let
         prval () = unit16_in_len(other_unit, one_len)
       in () end
     | STEPOF_high_alone(other_unit, other_next) => let
         prval () = unit16_in_len(other_unit, one_len)
       in () end
     | STEPOF_low_alone(other_unit) => let
         prval () = unit16_in_len(other_unit, one_len)
       in () end
     | STEPOF_ascii(other_nth) => ()
     | STEPOF_table(other_nth, other_tab) => ())
  | STEPOF_unit(one_unit) =>
    (case+ other of
     | STEPOF_truncated(other_nth, other_len) => let
         prval () = unit16_in_len(one_unit, other_len)
       in () end
     | STEPOF_unit(other_unit) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_pair(other_unit, other_next) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_high_at_end(other_unit, other_len) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_high_alone(other_unit, other_next) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_low_alone(other_unit) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_ascii(other_nth) => ()
     | STEPOF_table(other_nth, other_tab) => ())
  | STEPOF_pair(one_unit, one_next) =>
    (case+ other of
     | STEPOF_truncated(other_nth, other_len) => let
         prval () = unit16_in_len(one_unit, other_len)
       in () end
     | STEPOF_unit(other_unit) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_pair(other_unit, other_next) => let
         prval () = unit16_functional(one_unit, other_unit)
         prval () = unit16_functional(one_next, other_next)
       in () end
     | STEPOF_high_at_end(other_unit, other_len) => let
         prval () = unit16_functional(one_unit, other_unit)
         prval () = unit16_in_len(one_next, other_len)
       in () end
     | STEPOF_high_alone(other_unit, other_next) => let
         prval () = unit16_functional(one_unit, other_unit)
         prval () = unit16_functional(one_next, other_next)
       in () end
     | STEPOF_low_alone(other_unit) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_ascii(other_nth) => ()
     | STEPOF_table(other_nth, other_tab) => ())
  | STEPOF_high_at_end(one_unit, one_len) =>
    (case+ other of
     | STEPOF_truncated(other_nth, other_len) => let
         prval () = unit16_in_len(one_unit, other_len)
       in () end
     | STEPOF_unit(other_unit) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_pair(other_unit, other_next) => let
         prval () = unit16_functional(one_unit, other_unit)
         prval () = unit16_in_len(other_next, one_len)
       in () end
     | STEPOF_high_at_end(other_unit, other_len) => ()
     | STEPOF_high_alone(other_unit, other_next) => let
         prval () = unit16_functional(one_unit, other_unit)
         prval () = unit16_in_len(other_next, one_len)
       in () end
     | STEPOF_low_alone(other_unit) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_ascii(other_nth) => ()
     | STEPOF_table(other_nth, other_tab) => ())
  | STEPOF_high_alone(one_unit, one_next) =>
    (case+ other of
     | STEPOF_truncated(other_nth, other_len) => let
         prval () = unit16_in_len(one_unit, other_len)
       in () end
     | STEPOF_unit(other_unit) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_pair(other_unit, other_next) => let
         prval () = unit16_functional(one_unit, other_unit)
         prval () = unit16_functional(one_next, other_next)
       in () end
     | STEPOF_high_at_end(other_unit, other_len) => let
         prval () = unit16_functional(one_unit, other_unit)
         prval () = unit16_in_len(one_next, other_len)
       in () end
     | STEPOF_high_alone(other_unit, other_next) => ()
     | STEPOF_low_alone(other_unit) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_ascii(other_nth) => ()
     | STEPOF_table(other_nth, other_tab) => ())
  | STEPOF_low_alone(one_unit) =>
    (case+ other of
     | STEPOF_truncated(other_nth, other_len) => let
         prval () = unit16_in_len(one_unit, other_len)
       in () end
     | STEPOF_unit(other_unit) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_pair(other_unit, other_next) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_high_at_end(other_unit, other_len) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_high_alone(other_unit, other_next) => let
         prval () = unit16_functional(one_unit, other_unit)
       in () end
     | STEPOF_low_alone(other_unit) => ()
     | STEPOF_ascii(other_nth) => ()
     | STEPOF_table(other_nth, other_tab) => ())
  | STEPOF_ascii(one_nth) =>
    (case+ other of
     | STEPOF_truncated(other_nth, other_len) => ()
     | STEPOF_unit(other_unit) => ()
     | STEPOF_pair(other_unit, other_next) => ()
     | STEPOF_high_at_end(other_unit, other_len) => ()
     | STEPOF_high_alone(other_unit, other_next) => ()
     | STEPOF_low_alone(other_unit) => ()
     | STEPOF_ascii(other_nth) => let
         prval () = $A.nth_functional(one_nth, other_nth)
       in () end
     | STEPOF_table(other_nth, other_tab) => let
         prval () = $A.nth_functional(one_nth, other_nth)
       in () end)
  | STEPOF_table(one_nth, one_tab) =>
    (case+ other of
     | STEPOF_truncated(other_nth, other_len) => ()
     | STEPOF_unit(other_unit) => ()
     | STEPOF_pair(other_unit, other_next) => ()
     | STEPOF_high_at_end(other_unit, other_len) => ()
     | STEPOF_high_alone(other_unit, other_next) => ()
     | STEPOF_low_alone(other_unit) => ()
     | STEPOF_ascii(other_nth) => let
         prval () = $A.nth_functional(one_nth, other_nth)
       in () end
     | STEPOF_table(other_nth, other_tab) => let
         prval () = $A.nth_functional(one_nth, other_nth)
         prval () = tableat_functional(one_tab, other_tab)
       in () end)

(* A character is within the cells, and ends within them *)
#pub prfun stepof_bounds {cells:$A.cells}{source:tsrc}{i,n:nat}{to,point:int} (STEPOF(cells, source, i, to, point), $A.CLEN(cells, n)): [i < to; to <= n] void

primplement stepof_bounds {cells}{source}{i,n}{to,point} (step, length) =
  case+ step of
  | STEPOF_truncated(first, _) => $A.nth_in_len(first, length)
  | STEPOF_unit(unit_proof) => unit16_in_len(unit_proof, length)
  | STEPOF_pair(_, low) => unit16_in_len(low, length)
  | STEPOF_high_at_end(high, _) => unit16_in_len(high, length)
  | STEPOF_high_alone(high, _) => unit16_in_len(high, length)
  | STEPOF_low_alone(low) => unit16_in_len(low, length)
  | STEPOF_ascii(value) => $A.nth_in_len(value, length)
  | STEPOF_table(value, _) => $A.nth_in_len(value, length)

(* ENC(point, octets): the code point is the UTF-8 bytes octets (Unicode, table 3-6: one to four bytes; the digits of 64 are
   named, so that no division is stated) *)
#pub dataprop ENC(int, bytes) =
  | {point:int | 0 <= point; point < 128} ENC_one(point, bcons(point, bnil()))
  | {point,high,low:int | 2 <= high; high < 32; 0 <= low; low < 64; point == 64 * high + low}
    ENC_two(point, bcons(192 + high, bcons(128 + low, bnil())))
  | {point,high,middle,low:int | 0 <= high; high < 16; 0 <= middle; middle < 64; 0 <= low; low < 64; 2048 <= point; point == 4096 * high + 64 * middle + low}
    ENC_three(point, bcons(224 + high, bcons(128 + middle, bcons(128 + low, bnil()))))
  | {point,top,high,middle,low:int | 0 <= top; top < 5; 0 <= high; high < 64; 0 <= middle; middle < 64; 0 <= low; low < 64; 65536 <= point; point == 262144 * top + 4096 * high + 64 * middle + low}
    ENC_four(point, bcons(240 + top, bcons(128 + high, bcons(128 + middle, bcons(128 + low, bnil())))))

(* Digits of 64 are unique *)
prfn digit64_unique {high_one,low_one,high_two,low_two:int | 0 <= low_one; low_one < 64; 0 <= low_two; low_two < 64; 64 * high_one + low_one == 64 * high_two + low_two}
  (): [high_one == high_two && low_one == low_two] void = ()

(* A code point is one byte string *)
#pub prfun enc_functional {point:int}{first,second:bytes} (ENC(point, first), ENC(point, second)): EQB(first, second)

primplement enc_functional {point}{first,second} (one, other) =
  case+ one of
  | ENC_one() =>
    (case+ other of
     | ENC_one() => EQB_refl()
     | ENC_two() => falsep_eqb(contradiction{0}())
     | ENC_three() => falsep_eqb(contradiction{0}())
     | ENC_four() => falsep_eqb(contradiction{0}()))
  | ENC_two{point_one, high_one, low_one}() =>
    (case+ other of
     | ENC_one() => falsep_eqb(contradiction{0}())
     | ENC_two{point_two, high_two, low_two}() => let
         prval () = digit64_unique{high_one, low_one, high_two, low_two}()
       in EQB_refl() end
     | ENC_three() => falsep_eqb(contradiction{0}())
     | ENC_four() => falsep_eqb(contradiction{0}()))
  | ENC_three{point_one, high_one, middle_one, low_one}() =>
    (case+ other of
     | ENC_one() => falsep_eqb(contradiction{0}())
     | ENC_two() => falsep_eqb(contradiction{0}())
     | ENC_three{point_two, high_two, middle_two, low_two}() => let
         prval () = digit64_unique{64 * high_one + middle_one, low_one, 64 * high_two + middle_two, low_two}()
         prval () = digit64_unique{high_one, middle_one, high_two, middle_two}()
       in EQB_refl() end
     | ENC_four() => falsep_eqb(contradiction{0}()))
  | ENC_four{point_one, top_one, high_one, middle_one, low_one}() =>
    (case+ other of
     | ENC_one() => falsep_eqb(contradiction{0}())
     | ENC_two() => falsep_eqb(contradiction{0}())
     | ENC_three() => falsep_eqb(contradiction{0}())
     | ENC_four{point_two, top_two, high_two, middle_two, low_two}() => let
         prval () = digit64_unique{64 * (64 * top_one + high_one) + middle_one, low_one, 64 * (64 * top_two + high_two) + middle_two, low_two}()
         prval () = digit64_unique{64 * top_one + high_one, middle_one, 64 * top_two + high_two, middle_two}()
         prval () = digit64_unique{top_one, high_one, top_two, high_two}()
       in EQB_refl() end)

(* A code point is some bytes long *)
#pub prfun enc_len {point:int}{octets:bytes} (ENC(point, octets)): [count:nat | 1 <= count] LEN(octets, count)

primplement enc_len {point}{octets} (enc) =
  case+ enc of
  | ENC_one() => LEN_cons(LEN_nil())
  | ENC_two() => LEN_cons(LEN_cons(LEN_nil()))
  | ENC_three() => LEN_cons(LEN_cons(LEN_cons(LEN_nil())))
  | ENC_four() => LEN_cons(LEN_cons(LEN_cons(LEN_cons(LEN_nil()))))

(* CONV(cells, source, from, to, octets): the document in the source, from `from` to `to`, a character at a time
   (STEPOF), becomes the UTF-8 bytes octets (the bytes of each character's code point, ENC, one after another) *)
#pub dataprop CONV($A.cells, tsrc, int, int, bytes) =
  | {cells:$A.cells}{source:tsrc}{i:nat} CONV_none(cells, source, i, i, bnil())
  | {cells:$A.cells}{source:tsrc}{i,j,to:nat | i < j; j <= to}{point:int}{enc,rest,octets:bytes}
    CONV_more(cells, source, i, to, octets) of (STEPOF(cells, source, i, j, point), ENC(point, enc), CONV(cells, source, j, to, rest), APPEND(enc, rest, octets))

(* A conversion gives one byte string *)
#pub prfun conv_functional {cells:$A.cells}{source:tsrc}{from,to:nat | from <= to}{first,second:bytes}
  (CONV(cells, source, from, to, first), CONV(cells, source, from, to, second)): EQB(first, second)

prfun _conv_functional {cells:$A.cells}{source:tsrc}{from,to:nat | from <= to}{first,second:bytes} .<to - from>.
  (one: CONV(cells, source, from, to, first), other: CONV(cells, source, from, to, second)): EQB(first, second) =
  case+ one of
  | CONV_none() =>
    (case+ other of
     | CONV_none() => EQB_refl()
     | CONV_more(_, _, _, _) => falsep_eqb(contradiction{0}()))
  | CONV_more(step_one, enc_one, rest_one, append_one) =>
    (case+ other of
     | CONV_none() => falsep_eqb(contradiction{0}())
     | CONV_more(step_other, enc_other, rest_other, append_other) => let
         prval () = stepof_functional(step_one, step_other)
         prval EQB_refl() = enc_functional(enc_one, enc_other)
         prval EQB_refl() = _conv_functional(rest_one, rest_other)
       in append_functional(append_one, append_other) end)

primplement conv_functional {cells}{source}{from,to}{first,second} (one, other) = _conv_functional(one, other)

(* A conversion followed by one more character is a conversion *)
#pub prfun conv_snoc {cells:$A.cells}{source:tsrc}{from,mid,after:nat | from <= mid; mid < after}{point:int}{octets,enc,joined:bytes}
  (CONV(cells, source, from, mid, octets), STEPOF(cells, source, mid, after, point), ENC(point, enc), APPEND(octets, enc, joined))
  : CONV(cells, source, from, after, joined)

prfun _conv_snoc {cells:$A.cells}{source:tsrc}{from,mid,after:nat | from <= mid; mid < after}{point:int}{octets,enc,joined:bytes} .<mid - from>.
  (conv: CONV(cells, source, from, mid, octets), step: STEPOF(cells, source, mid, after, point), enc: ENC(point, enc), joined: APPEND(octets, enc, joined))
  : CONV(cells, source, from, after, joined) =
  case+ conv of
  | CONV_none() => (case+ joined of APPEND_nil() => CONV_more(step, enc, CONV_none(), append_nil(enc_len(enc))))
  | CONV_more(step_head, enc_head, rest, append_head) => let
      prval (append_rest, append_joined) = append_assoc(append_head, joined)
    in CONV_more(step_head, enc_head, _conv_snoc(rest, step, enc, append_rest), append_joined) end

primplement conv_snoc {cells}{source}{from,mid,after}{point}{octets,enc,joined} (conv, step, enc, joined) = _conv_snoc(conv, step, enc, joined)

(* A conversion of some characters makes some bytes *)
#pub prfun conv_nonempty {cells:$A.cells}{source:tsrc}{from,to:nat | from < to}{octets:bytes}{size:nat}
  (CONV(cells, source, from, to, octets), LEN(octets, size)): [1 <= size] void

primplement conv_nonempty {cells}{source}{from,to}{octets}{size} (conv, octets_len) =
  case+ conv of
  | CONV_none() =/=> ()
  | CONV_more(_, enc, _, joined) => let
      prval enc_length = enc_len(enc)
      prval rest_len = append_len_rest(joined, enc_length, octets_len)
    in () end

prfun _holds_after_set_later {cells,cells_after:$A.cells}{i,count,at:nat | i + count <= at}{value:int}{octets:bytes} .<count>.
  (cells_set: $A.SETC(cells, at, value, cells_after), holds: HOLDS(cells, i, octets, count)): HOLDS(cells_after, i, octets, count) =
  case+ holds of
  | HOLDS_nil(length) => HOLDS_nil($A.setc_len(cells_set, length))
  | HOLDS_cons(cell, rest) => HOLDS_cons($A.setc_nth_other(cells_set, cell), _holds_after_set_later(cells_set, rest))

(* Setting a cell past the ones a list is held from, and no further than where the list ends, leaves them held *)
#pub prfun holds_after_set_later {cells,cells_after:$A.cells}{i,count,at:nat | i + count <= at}{value:int}{octets:bytes}
  (cells_set: $A.SETC(cells, at, value, cells_after), holds: HOLDS(cells, i, octets, count)): HOLDS(cells_after, i, octets, count)

primplement holds_after_set_later {cells,cells_after}{i,count,at}{value}{octets} (cells_set, holds) = _holds_after_set_later(cells_set, holds)

(* One more byte, held, after the bytes held *)
#pub prfun holds_snoc {cells:$A.cells}{i,count:nat}{value:int}{octets,joined:bytes}
  (HOLDS(cells, i, octets, count), $A.NTH(cells, i + count, value), APPEND(octets, bcons(value, bnil()), joined)): HOLDS(cells, i, joined, count + 1)

prfun _holds_snoc {cells:$A.cells}{i,count:nat}{value:int}{octets,joined:bytes} .<count>.
  (holds: HOLDS(cells, i, octets, count), cell: $A.NTH(cells, i + count, value), joined: APPEND(octets, bcons(value, bnil()), joined)): HOLDS(cells, i, joined, count + 1) =
  case+ holds of
  | HOLDS_nil(length) =>
    (case+ joined of
     | APPEND_nil() => let
         prval () = $A.nth_in_len(cell, length)
       in HOLDS_cons(cell, HOLDS_nil(length)) end)
  | HOLDS_cons(head, rest) =>
    (case+ joined of APPEND_cons(joined_rest) => HOLDS_cons(head, _holds_snoc(rest, cell, joined_rest)))

primplement holds_snoc {cells}{i,count}{value}{octets,joined} (holds, cell, joined) = _holds_snoc(holds, cell, joined)

(* The cells held from 0 for written_count bytes, with the cell written_count set to a byte, hold the bytes and that byte *)
#pub prfun holds_push {cells,cells_after:$A.cells}{written_count:nat}{value:int}{octets,joined:bytes}
  (HOLDS(cells, 0, octets, written_count), $A.SETC(cells, written_count, value, cells_after), APPEND(octets, bcons(value, bnil()), joined)): HOLDS(cells_after, 0, joined, written_count + 1)

primplement holds_push {cells,cells_after}{written_count}{value}{octets,joined} (holds, cells_set, joined) =
  holds_snoc(holds_after_set_later(cells_set, holds), $A.setc_nth_same(cells_set), joined)

(* Whether a unit is the first half of a pair, or the second *)
fn _is_high {unit:int} (unit: int unit): bool(55296 <= unit && unit < 56320) =
  if unit >= 55296 then (if unit < 56320 then true else false) else false

fn _is_low {unit:int} (unit: int unit): bool(56320 <= unit && unit < 57344) =
  if unit >= 56320 then (if unit < 57344 then true else false) else false

(* The 16-bit unit of the two bytes at i, in the order of the source *)
fn _unit16 {l:agz}{n:pos}{cells:$A.cells}{order:byteorder}{i:nat | i + 1 < n}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, source: label_source(SrcUtf16(order)), i: int i)
  : [unit:int] (UNIT16(cells, order, i, unit) | int unit) = let
  val (first_cell | first) = $A.cborrow_get(data, i)
  val (second_cell | second) = $A.cborrow_get(data, i + 1)
in
  case+ source of
  | LabelUtf16Le() => (UNIT16_le(first_cell, second_cell) | first + 256 * second)
  | LabelUtf16Be() => (UNIT16_be(first_cell, second_cell) | 256 * first + second)
end

(* The character at i of a UTF-16 document, with the proof of it *)
fn _step16 {l:agz}{n:pos}{cells:$A.cells}{order:byteorder}{i:nat | i < n}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, source: label_source(SrcUtf16(order)), i: int i)
  : [to,point:int | 0 <= point; point < 1114112] (STEPOF(cells, SrcUtf16(order), i, to, point) | int to, int point) = let
  val (first_cell | first) = $A.cborrow_get(data, i)
in
  if i + 1 >= n then (STEPOF_truncated(first_cell, length) | i + 1, 65533)
  else let
      val (unit_proof | unit) = _unit16(length | data, n, source, i)
      prval () = unit16_range(unit_proof)
    in
      if _is_high(unit) then
        (if i + 3 < n then let
             val (next_proof | next) = _unit16(length | data, n, source, i + 2)
             prval () = unit16_range(next_proof)
           in
             if _is_low(next) then (STEPOF_pair(unit_proof, next_proof) | i + 4, 65536 + 1024 * (unit - 55296) + (next - 56320))
             else (STEPOF_high_alone(unit_proof, next_proof) | i + 2, 65533)
           end
         else (STEPOF_high_at_end(unit_proof, length) | i + 2, 65533))
      else if _is_low(unit) then (STEPOF_low_alone(unit_proof) | i + 2, 65533)
      else (STEPOF_unit(unit_proof) | i + 2, unit)
    end
end

(* The character at i of a single-byte document, with the proof of it *)
fn _step_single {l:agz}{n:pos}{cells:$A.cells}{page:codepage}{i:nat | i < n}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, source: label_source(SrcTable(page)), i: int i)
  : [to,point:int | 0 <= point; point < 1114112] (STEPOF(cells, SrcTable(page), i, to, point) | int to, int point) = let
  val (cell | value) = $A.cborrow_get(data, i)
in
  if value < 128 then (STEPOF_ascii(cell) | i + 1, value)
  else let
      val (table | point) = text_table_point(source, value)
    in (STEPOF_table(cell, table) | i + 1, point) end
end

(* The sources a document is converted from, as a value *)
#pub datatype conv_source(tsrc) = ConvUtf16Le(SrcUtf16(LittleEndian())) | ConvUtf16Be(SrcUtf16(BigEndian())) | ConvCp1250(SrcTable(Cp1250())) | ConvCp1251(SrcTable(Cp1251())) | ConvCp1252(SrcTable(Cp1252())) | ConvCp1253(SrcTable(Cp1253())) | ConvCp1254(SrcTable(Cp1254())) | ConvCp1255(SrcTable(Cp1255())) | ConvCp1256(SrcTable(Cp1256())) | ConvCp1257(SrcTable(Cp1257())) | ConvIso88592(SrcTable(Iso88592())) | ConvIso88595(SrcTable(Iso88595())) | ConvIso88597(SrcTable(Iso88597())) | ConvIso88598(SrcTable(Iso88598())) | ConvIso885915(SrcTable(Iso885915())) | ConvKoi8r(SrcTable(Koi8r()))

(* The character at i of a document that is converted, with the proof of it *)
fn _step_proved {l:agz}{n:pos}{cells:$A.cells}{source:tsrc}{i:nat | i < n}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(source), i: int i)
  : [to,point:int | 0 <= point; point < 1114112] (STEPOF(cells, source, i, to, point) | int to, int point) =
  case+ source of
  | ConvUtf16Le() => _step16(length | data, n, LabelUtf16Le(), i)
  | ConvUtf16Be() => _step16(length | data, n, LabelUtf16Be(), i)
  | ConvCp1250() => _step_single(length | data, n, LabelCp1250(), i)
  | ConvCp1251() => _step_single(length | data, n, LabelCp1251(), i)
  | ConvCp1252() => _step_single(length | data, n, LabelCp1252(), i)
  | ConvCp1253() => _step_single(length | data, n, LabelCp1253(), i)
  | ConvCp1254() => _step_single(length | data, n, LabelCp1254(), i)
  | ConvCp1255() => _step_single(length | data, n, LabelCp1255(), i)
  | ConvCp1256() => _step_single(length | data, n, LabelCp1256(), i)
  | ConvCp1257() => _step_single(length | data, n, LabelCp1257(), i)
  | ConvIso88592() => _step_single(length | data, n, LabelIso88592(), i)
  | ConvIso88595() => _step_single(length | data, n, LabelIso88595(), i)
  | ConvIso88597() => _step_single(length | data, n, LabelIso88597(), i)
  | ConvIso88598() => _step_single(length | data, n, LabelIso88598(), i)
  | ConvIso885915() => _step_single(length | data, n, LabelIso885915(), i)
  | ConvKoi8r() => _step_single(length | data, n, LabelKoi8r(), i)

(* number as 64 times a number and a digit *)
fn _split64 {number:nat} (number: int number): [high,low:nat | number == 64 * high + low; low < 64] (int high, int low) = let
  val high = number / 64
in (high, number - 64 * high) end

(* The UTF-8 bytes of a code point, with the proof of them and how many they are *)
fn _enc_count {point:int | 0 <= point; point < 1114112} (point: int point)
  : [enc:bytes][count:nat] (ENC(point, enc), LEN(enc, count) | int count) =
  if point < 128 then (ENC_one() , LEN_cons(LEN_nil()) | 1)
  else if point < 2048 then let
      val [high:int, low:int] (high_digit, low_digit) = _split64(point)
    in (ENC_two{point, high, low}(), LEN_cons(LEN_cons(LEN_nil())) | 2) end
  else if point < 65536 then let
      val [rest:int, low:int] (rest_digit, low_digit) = _split64(point)
      val [high:int, middle:int] (high_digit, middle_digit) = _split64(rest_digit)
    in (ENC_three{point, high, middle, low}(), LEN_cons(LEN_cons(LEN_cons(LEN_nil()))) | 3) end
  else let
      val [rest:int, low:int] (rest_digit, low_digit) = _split64(point)
      val [rest_two:int, middle:int] (rest_two_digit, middle_digit) = _split64(rest_digit)
      val [top:int, high:int] (top_digit, high_digit) = _split64(rest_two_digit)
    in (ENC_four{point, top, high, middle, low}(), LEN_cons(LEN_cons(LEN_cons(LEN_cons(LEN_nil())))) | 4) end

(* Writes a byte at written_count of an array whose cells hold the bytes written from 0, and holds them with it *)
fn _put_byte {out_location:agz}{size:pos}{out_cells:$A.cells}{written_count:nat | written_count < size}{written:bytes}{value:int | 0 <= value; value < 256}
  (holds: HOLDS(out_cells, 0, written, written_count), written_len: LEN(written, written_count), out_len: $A.CLEN(out_cells, size) | out: $A.barr(out_location, size, out_cells), written_count: int written_count, value: int value)
  : [out_cells_after:$A.cells][joined:bytes] (HOLDS(out_cells_after, 0, joined, written_count + 1), $A.CLEN(out_cells_after, size), LEN(joined, written_count + 1), APPEND(written, bcons(value, bnil()), joined) | $A.barr(out_location, size, out_cells_after)) = let
  val (cells_set | out_after) = $A.barr_set(out, written_count, value)
  prval appended = append_exists{written, bcons(value, bnil())}(written_len)
  prval holds_after = holds_push(holds, cells_set, appended)
  prval joined_len = append_len(appended, written_len, LEN_cons(LEN_nil()))
in (holds_after, $A.setc_len(cells_set, out_len), joined_len, appended | out_after) end

(* Writes the UTF-8 bytes of a code point, whose bytes are given and are given_count, after the written_count bytes written *)
fn _write_point {out_location:agz}{size:pos}{out_cells:$A.cells}{written_count,given_count:nat | written_count + given_count <= size}{written:bytes}{point:int | 0 <= point; point < 1114112}{given:bytes}
  (holds: HOLDS(out_cells, 0, written, written_count), written_len: LEN(written, written_count), out_len: $A.CLEN(out_cells, size), given_enc: ENC(point, given), given_len: LEN(given, given_count)
   | out: $A.barr(out_location, size, out_cells), written_count: int written_count, point: int point)
  : [out_cells_after:$A.cells][joined:bytes] (HOLDS(out_cells_after, 0, joined, written_count + given_count), $A.CLEN(out_cells_after, size), LEN(joined, written_count + given_count), APPEND(written, given, joined) | $A.barr(out_location, size, out_cells_after), int(written_count + given_count)) =
  if point < 128 then let
      prval EQB_refl() = enc_functional(ENC_one(), given_enc)
      prval EQI_refl() = len_functional(given_len, LEN_cons(LEN_nil()))
      val (holds_one, len_one, joined_len_one, appended_one | out_one) = _put_byte(holds, written_len, out_len | out, written_count, point)
    in (holds_one, len_one, joined_len_one, appended_one | out_one, written_count + 1) end
  else if point < 2048 then let
      val [high:int, low:int] (high_digit, low_digit) = _split64(point)
      prval EQB_refl() = enc_functional(ENC_two{point, high, low}(), given_enc)
      prval EQI_refl() = len_functional(given_len, LEN_cons(LEN_cons(LEN_nil())))
      val (holds_one, len_one, joined_len_one, appended_one | out_one) = _put_byte(holds, written_len, out_len | out, written_count, 192 + high_digit)
      val (holds_two, len_two, joined_len_two, appended_two | out_two) = _put_byte(holds_one, joined_len_one, len_one | out_one, written_count + 1, 128 + low_digit)
      prval (APPEND_cons(APPEND_nil()), appended) = append_assoc(appended_one, appended_two)
    in (holds_two, len_two, joined_len_two, appended | out_two, written_count + 2) end
  else if point < 65536 then let
      val [rest:int, low:int] (rest_digit, low_digit) = _split64(point)
      val [high:int, middle:int] (high_digit, middle_digit) = _split64(rest_digit)
      prval EQB_refl() = enc_functional(ENC_three{point, high, middle, low}(), given_enc)
      prval EQI_refl() = len_functional(given_len, LEN_cons(LEN_cons(LEN_cons(LEN_nil()))))
      val (holds_one, len_one, joined_len_one, appended_one | out_one) = _put_byte(holds, written_len, out_len | out, written_count, 224 + high_digit)
      val (holds_two, len_two, joined_len_two, appended_two | out_two) = _put_byte(holds_one, joined_len_one, len_one | out_one, written_count + 1, 128 + middle_digit)
      val (holds_three, len_three, joined_len_three, appended_three | out_three) = _put_byte(holds_two, joined_len_two, len_two | out_two, written_count + 2, 128 + low_digit)
      prval (APPEND_cons(APPEND_nil()), appended_pair) = append_assoc(appended_one, appended_two)
      prval (APPEND_cons(APPEND_cons(APPEND_nil())), appended) = append_assoc(appended_pair, appended_three)
    in (holds_three, len_three, joined_len_three, appended | out_three, written_count + 3) end
  else let
      val [rest:int, low:int] (rest_digit, low_digit) = _split64(point)
      val [rest_two:int, middle:int] (rest_two_digit, middle_digit) = _split64(rest_digit)
      val [top:int, high:int] (top_digit, high_digit) = _split64(rest_two_digit)
      prval EQB_refl() = enc_functional(ENC_four{point, top, high, middle, low}(), given_enc)
      prval EQI_refl() = len_functional(given_len, LEN_cons(LEN_cons(LEN_cons(LEN_cons(LEN_nil())))))
      val (holds_one, len_one, joined_len_one, appended_one | out_one) = _put_byte(holds, written_len, out_len | out, written_count, 240 + top_digit)
      val (holds_two, len_two, joined_len_two, appended_two | out_two) = _put_byte(holds_one, joined_len_one, len_one | out_one, written_count + 1, 128 + high_digit)
      val (holds_three, len_three, joined_len_three, appended_three | out_three) = _put_byte(holds_two, joined_len_two, len_two | out_two, written_count + 2, 128 + middle_digit)
      val (holds_four, len_four, joined_len_four, appended_four | out_four) = _put_byte(holds_three, joined_len_three, len_three | out_three, written_count + 3, 128 + low_digit)
      prval (APPEND_cons(APPEND_nil()), appended_pair) = append_assoc(appended_one, appended_two)
      prval (APPEND_cons(APPEND_cons(APPEND_nil())), appended_triple) = append_assoc(appended_pair, appended_three)
      prval (APPEND_cons(APPEND_cons(APPEND_cons(APPEND_nil()))), appended) = append_assoc(appended_triple, appended_four)
    in (holds_four, len_four, joined_len_four, appended | out_four, written_count + 4) end

(* Writes the converted document from i on, one character at a time, as the conversion of it that is to be written says *)
fun _fill_loop {l:agz}{n:pos}{cells:$A.cells}{source:tsrc}{i:nat | i <= n}
  {out_location:agz}{out_cells:$A.cells}{written_count:nat}{written,rest,total:bytes}{total_count:pos} .<n - i>.
  (length: $A.CLEN(cells, n), remaining: CONV(cells, source, i, n, rest), appended: APPEND(written, rest, total), total_len: LEN(total, total_count),
   holds: HOLDS(out_cells, 0, written, written_count), written_len: LEN(written, written_count), out_len: $A.CLEN(out_cells, total_count)
   | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(source), i: int i, out: $A.barr(out_location, total_count, out_cells), written_count: int written_count)
  : [out_cells_after:$A.cells] (HOLDS(out_cells_after, 0, total, total_count), $A.CLEN(out_cells_after, total_count) | $A.barr(out_location, total_count, out_cells_after)) =
  if i >= n then let
      prval CONV_none() = remaining
      prval EQB_refl() = append_nil_eq(written_len, appended)
      prval EQI_refl() = len_functional(written_len, total_len)
    in (holds, out_len | out) end
  else let
      prval CONV_more(step_proof, enc_proof, rest_proof, appended_char) = remaining
      val (step | to, point) = _step_proved(length | data, n, source, i)
      prval () = stepof_functional(step, step_proof)
      prval rest_len = append_len_rest(appended, written_len, total_len)
      prval enc_length = enc_len(enc_proof)
      prval after_len = append_len_rest(appended_char, enc_length, rest_len)
      val (holds_after, len_after, joined_len, appended_written | out_after, written_after) =
        _write_point(holds, written_len, out_len, enc_proof, enc_length | out, written_count, point)
      prval (appended_enc, appended_rest) = append_assoc_rev(appended_char, appended)
      prval EQB_refl() = append_functional(appended_enc, appended_written)
    in _fill_loop(length, rest_proof, appended_rest, total_len, holds_after, joined_len, len_after | data, n, source, to, out_after, written_after) end

(* The conversion of the document from i on, with the proof of it and of the number of bytes it makes *)
fun _size_loop {l:agz}{n:pos}{cells:$A.cells}{source:tsrc}{mark,i:nat | mark <= i; i <= n}
  {octets:bytes}{total:nat} .<n - i>.
  (length: $A.CLEN(cells, n), conv: CONV(cells, source, mark, i, octets), total_len: LEN(octets, total)
   | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(source), i: int i, total: int total)
  : [all:bytes][size:nat] (CONV(cells, source, mark, n, all), LEN(all, size) | int size) =
  if i >= n then (conv, total_len | total)
  else let
    val (step | to, point) = _step_proved(length | data, n, source, i)
    prval () = stepof_bounds(step, length)
    val [enc:bytes] [count:int] (enc_proof, enc_length | enc_count) = _enc_count(point)
    prval appended = append_exists{octets, enc}(total_len)
    prval joined_len = append_len(appended, total_len, enc_length)
    prval conv_after = conv_snoc(conv, step, enc_proof, appended)
  in _size_loop(length, conv_after, joined_len | data, n, source, to, total + enc_count) end

(* The conversion of the document from mark, with the proof of it and of the number of bytes it makes *)
fn _converted_size {l:agz}{n:pos}{cells:$A.cells}{source:tsrc}{mark:nat | mark <= n}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(source), mark: int mark)
  : [all:bytes][size:nat] (CONV(cells, source, mark, n, all), LEN(all, size) | int size) =
  _size_loop(length, CONV_none(), LEN_nil() | data, n, source, mark, 0)

(* The plan a document needs *)
#pub datasort plan = PlanAsIs of () | PlanConvert of () | PlanRefused of ()

(* EQPLAN(first, second): two plans are one *)
#pub dataprop EQPLAN(plan, plan) =
  | {same:plan} EQPLAN_refl(same, same)

(* What a document becomes: nothing (it is refused), or some bytes *)
#pub datasort textout =
  | TOUT_none of ()
  | TOUT_bytes of (bytes)

(* EQOUT(first, second): two outcomes are one *)
#pub dataprop EQOUT(textout, textout) =
  | {same:textout} EQOUT_refl(same, same)

(* TEXTOF(cells, plan, output): the document in the cells needs the plan and becomes the output: the bytes of the cells (PlanAsIs),
   the bytes of the cells after a byte order mark of three, or the UTF-8 bytes of its characters (CONV: UTF-16 and the single-byte
   encodings) (PlanConvert), or nothing (PlanRefused). Refused is the claim that no reading of the document exists: the bytes are not
   UTF-8 (UTF8SCAN's bad case, which utf8run_bad_not_complete makes exclusive of a reading), or are nothing after their byte order
   mark, or say an encoding Quire has no table for and are not ASCII only *)
#pub dataprop TEXTOF($A.cells, plan, textout) =
  | {cells:$A.cells}{n:nat}{spread:spread}{octets:bytes}
    TEXTOF_utf8_as_is(cells, PlanAsIs(), TOUT_bytes(octets)) of (DETECT(cells, SrcUtf8(), 0), $A.CLEN(cells, n), UTF8RUN(cells, 0, n, spread), HOLDS(cells, 0, octets, n))
  | {cells:$A.cells}{mark,n:nat}{octets:bytes}
    TEXTOF_unsupported_as_is(cells, PlanAsIs(), TOUT_bytes(octets)) of (DETECT(cells, SrcUnsupported(), mark), $A.CLEN(cells, n), UTF8RUN(cells, 0, n, SpreadAscii()), HOLDS(cells, 0, octets, n))
  | {cells:$A.cells}{page:codepage}{mark,n:nat}{spread:spread}{octets:bytes}
    TEXTOF_single_as_is(cells, PlanAsIs(), TOUT_bytes(octets)) of (DETECT(cells, SrcTable(page), mark), $A.CLEN(cells, n), UTF8RUN(cells, 0, n, spread), HOLDS(cells, 0, octets, n))
  | {cells:$A.cells}{n:nat | 3 < n}{spread:spread}{octets:bytes}
    TEXTOF_bom_dropped(cells, PlanConvert(), TOUT_bytes(octets)) of (DETECT(cells, SrcUtf8(), 3), $A.CLEN(cells, n), UTF8RUN(cells, 3, n, spread), HOLDS(cells, 3, octets, n - 3))
  | {cells:$A.cells}{order:byteorder}{mark,n:nat | mark < n}{octets:bytes}
    TEXTOF_utf16_convert(cells, PlanConvert(), TOUT_bytes(octets)) of (DETECT(cells, SrcUtf16(order), mark), $A.CLEN(cells, n), CONV(cells, SrcUtf16(order), mark, n, octets))
  | {cells:$A.cells}{page:codepage}{mark,n:nat | mark < n}{octets:bytes}
    TEXTOF_single_convert(cells, PlanConvert(), TOUT_bytes(octets)) of (DETECT(cells, SrcTable(page), mark), UTF8SCAN(cells, 0, ScannedRefused()), $A.CLEN(cells, n), CONV(cells, SrcTable(page), mark, n, octets))
  | {cells:$A.cells}{mark:nat}
    TEXTOF_utf8_invalid(cells, PlanRefused(), TOUT_none()) of (DETECT(cells, SrcUtf8(), mark), UTF8SCAN(cells, mark, ScannedRefused()))
  | {cells:$A.cells}{mark,n:nat | 0 < mark; n <= mark; mark <= n}{spread:spread}
    TEXTOF_bom_only(cells, PlanRefused(), TOUT_none()) of (DETECT(cells, SrcUtf8(), mark), $A.CLEN(cells, n), UTF8RUN(cells, mark, n, spread))
  | {cells:$A.cells}{order:byteorder}{mark,n:nat | n <= mark}
    TEXTOF_utf16_empty(cells, PlanRefused(), TOUT_none()) of (DETECT(cells, SrcUtf16(order), mark), $A.CLEN(cells, n))
  | {cells:$A.cells}{mark:nat}
    TEXTOF_unsupported_invalid(cells, PlanRefused(), TOUT_none()) of (DETECT(cells, SrcUnsupported(), mark), UTF8SCAN(cells, 0, ScannedRefused()))
  | {cells:$A.cells}{mark,n:nat}
    TEXTOF_unsupported_wide(cells, PlanRefused(), TOUT_none()) of (DETECT(cells, SrcUnsupported(), mark), $A.CLEN(cells, n), UTF8RUN(cells, 0, n, SpreadWide()))

(* Whole characters to the end of the cells are not a scan that found one that is not whole *)
#pub prfun utf8run_refused_not_complete {cells:$A.cells}{from,n:nat | from <= n}{spread:spread}
  (UTF8RUN(cells, from, n, spread), $A.CLEN(cells, n), UTF8SCAN(cells, from, ScannedRefused())): FALSEP()

primplement utf8run_refused_not_complete {cells}{from,n}{spread} (run, length, scan) =
  case+ scan of UTF8SCAN_bad(leading, bad) => utf8run_bad_not_complete(leading, bad, run, length)

(* From a contradiction, one plan and one output *)
#pub prfun falsep_textof {first_plan,second_plan:plan}{first_out,second_out:textout}
  (FALSEP()): (EQPLAN(first_plan, second_plan), EQOUT(first_out, second_out))

primplement falsep_textof {first_plan,second_plan}{first_out,second_out} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

(* A document needs one plan and becomes one output *)
#pub prfun textof_functional {cells:$A.cells}{first_plan,second_plan:plan}{first_out,second_out:textout}
  (TEXTOF(cells, first_plan, first_out), TEXTOF(cells, second_plan, second_out)): (EQPLAN(first_plan, second_plan), EQOUT(first_out, second_out))

primplement textof_functional {cells}{first_plan,second_plan}{first_out,second_out} (one, other) =
  case+ one of
  | TEXTOF_utf8_as_is(one_detect, one_len, one_run, one_holds) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => let
         prval () = clen_functional(one_len, other_len)
         prval EQB_refl() = holds_functional(one_holds, other_holds)
       in (EQPLAN_refl(), EQOUT_refl()) end
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => (let prval (_, second_proof) = detect_functional(one_detect, other_detect) in case+ second_proof of EQI_refl() =/=> () end)
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf8_invalid(other_detect, other_scan) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(one_run, one_len, other_scan)) end
     | TEXTOF_bom_only(other_detect, other_len, other_run) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(contradiction{0}()) end
     | TEXTOF_utf16_empty(other_detect, other_len) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end))
  | TEXTOF_unsupported_as_is(one_detect, one_len, one_run, one_holds) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => let
         prval () = clen_functional(one_len, other_len)
         prval EQB_refl() = holds_functional(one_holds, other_holds)
       in (EQPLAN_refl(), EQOUT_refl()) end
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf8_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_only(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_empty(other_detect, other_len) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(one_run, one_len, other_scan)) end
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
         prval () = clen_functional(one_len, other_len)
       in (case+ utf8run_functional(one_run, other_run) of EQSPREAD_refl() =/=> ()) end)
  | TEXTOF_single_as_is(one_detect, one_len, one_run, one_holds) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => let
         prval () = clen_functional(one_len, other_len)
         prval EQB_refl() = holds_functional(one_holds, other_holds)
       in (EQPLAN_refl(), EQOUT_refl()) end
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(one_run, one_len, other_scan)) end
     | TEXTOF_utf8_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_only(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_empty(other_detect, other_len) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end))
  | TEXTOF_bom_dropped(one_detect, one_len, one_run, one_holds) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => (let prval (_, second_proof) = detect_functional(one_detect, other_detect) in case+ second_proof of EQI_refl() =/=> () end)
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => let
         prval () = clen_functional(one_len, other_len)
         prval EQB_refl() = holds_functional(one_holds, other_holds)
       in (EQPLAN_refl(), EQOUT_refl()) end
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf8_invalid(other_detect, other_scan) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(one_run, one_len, other_scan)) end
     | TEXTOF_bom_only(other_detect, other_len, other_run) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
         prval () = clen_functional(one_len, other_len)
       in falsep_textof(contradiction{0}()) end
     | TEXTOF_utf16_empty(other_detect, other_len) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end))
  | TEXTOF_utf16_convert(one_detect, one_len, one_conv) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
         prval () = clen_functional(one_len, other_len)
         prval EQB_refl() = conv_functional(one_conv, other_conv)
       in (EQPLAN_refl(), EQOUT_refl()) end
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf8_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_only(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_empty(other_detect, other_len) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
         prval () = clen_functional(one_len, other_len)
       in falsep_textof(contradiction{0}()) end
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end))
  | TEXTOF_single_convert(one_detect, one_scan, one_len, one_conv) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(other_run, other_len, one_scan)) end
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
         prval () = clen_functional(one_len, other_len)
         prval EQB_refl() = conv_functional(one_conv, other_conv)
       in (EQPLAN_refl(), EQOUT_refl()) end
     | TEXTOF_utf8_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_only(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_empty(other_detect, other_len) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end))
  | TEXTOF_utf8_invalid(one_detect, one_scan) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(other_run, other_len, one_scan)) end
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(other_run, other_len, one_scan)) end
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf8_invalid(other_detect, other_scan) => (EQPLAN_refl(), EQOUT_refl())
     | TEXTOF_bom_only(other_detect, other_len, other_run) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(other_run, other_len, one_scan)) end
     | TEXTOF_utf16_empty(other_detect, other_len) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end))
  | TEXTOF_bom_only(one_detect, one_len, one_run) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(contradiction{0}()) end
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
         prval () = clen_functional(one_len, other_len)
       in falsep_textof(contradiction{0}()) end
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf8_invalid(other_detect, other_scan) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(one_run, one_len, other_scan)) end
     | TEXTOF_bom_only(other_detect, other_len, other_run) => (EQPLAN_refl(), EQOUT_refl())
     | TEXTOF_utf16_empty(other_detect, other_len) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end))
  | TEXTOF_utf16_empty(one_detect, one_len) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
         prval () = clen_functional(one_len, other_len)
       in falsep_textof(contradiction{0}()) end
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf8_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_only(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_empty(other_detect, other_len) => (EQPLAN_refl(), EQOUT_refl())
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end))
  | TEXTOF_unsupported_invalid(one_detect, one_scan) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(other_run, other_len, one_scan)) end
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf8_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_only(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_empty(other_detect, other_len) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => (EQPLAN_refl(), EQOUT_refl())
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(other_run, other_len, one_scan)) end)
  | TEXTOF_unsupported_wide(one_detect, one_len, one_run) =>
    (case+ other of
     | TEXTOF_utf8_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_as_is(other_detect, other_len, other_run, other_holds) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
         prval () = clen_functional(one_len, other_len)
       in (case+ utf8run_functional(one_run, other_run) of EQSPREAD_refl() =/=> ()) end
     | TEXTOF_single_as_is(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_dropped(other_detect, other_len, other_run, other_holds) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_convert(other_detect, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_single_convert(other_detect, other_scan, other_len, other_conv) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf8_invalid(other_detect, other_scan) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_bom_only(other_detect, other_len, other_run) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_utf16_empty(other_detect, other_len) => (let prval (first_proof, _) = detect_functional(one_detect, other_detect) in case+ first_proof of EQSRC_refl() =/=> () end)
     | TEXTOF_unsupported_invalid(other_detect, other_scan) => let
         prval (EQSRC_refl(), EQI_refl()) = detect_functional(one_detect, other_detect)
       in falsep_textof(utf8run_refused_not_complete(one_run, one_len, other_scan)) end
     | TEXTOF_unsupported_wide(other_detect, other_len, other_run) => (EQPLAN_refl(), EQOUT_refl()))

(* Bytes held are as many as they are held for *)
#pub prfun holds_len {cells:$A.cells}{i,count:nat}{octets:bytes} (HOLDS(cells, i, octets, count)): LEN(octets, count)

prfun _holds_len {cells:$A.cells}{i,count:nat}{octets:bytes} .<count>. (holds: HOLDS(cells, i, octets, count)): LEN(octets, count) =
  case+ holds of
  | HOLDS_nil(_) => LEN_nil()
  | HOLDS_cons(_, rest) => LEN_cons(_holds_len(rest))

primplement holds_len {cells}{i,count}{octets} (holds) = _holds_len(holds)

(* From a contradiction, bytes held *)
#pub prfun falsep_holds {cells:$A.cells}{i:int}{octets:bytes}{count:int} (FALSEP()): HOLDS(cells, i, octets, count)

primplement falsep_holds {cells}{i}{octets}{count} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

(* From a contradiction, a conversion *)
#pub prfun falsep_conv {cells:$A.cells}{source:tsrc}{from,to:int}{octets:bytes} (FALSEP()): CONV(cells, source, from, to, octets)

primplement falsep_conv {cells}{source}{from,to}{octets} (falsity) = case+ falsity of FALSEP_mk() =/=> ()

(* Copies the bytes held from i in the cells to the array, one at a time *)
fun _copy_loop {l:agz}{n:pos}{cells:$A.cells}{i,held_count:nat | i + held_count <= n}{out_location:agz}{out_cells:$A.cells}{written_count:nat}{written,rest,total:bytes}{total_count:pos} .<held_count>.
  (remaining: HOLDS(cells, i, rest, held_count), appended: APPEND(written, rest, total), total_len: LEN(total, total_count),
   holds: HOLDS(out_cells, 0, written, written_count), written_len: LEN(written, written_count), out_len: $A.CLEN(out_cells, total_count)
   | data: !$A.cborrow(l, n, cells), n: int n, i: int i, held_count: int held_count, out: $A.barr(out_location, total_count, out_cells), written_count: int written_count)
  : [out_cells_after:$A.cells] (HOLDS(out_cells_after, 0, total, total_count), $A.CLEN(out_cells_after, total_count) | $A.barr(out_location, total_count, out_cells_after)) =
  if held_count <= 0 then let
      prval HOLDS_nil(_) = remaining
      prval EQB_refl() = append_nil_eq(written_len, appended)
      prval EQI_refl() = len_functional(written_len, total_len)
    in (holds, out_len | out) end
  else let
      prval HOLDS_cons(cell_held, rest_held) = remaining
      val (cell | value) = $A.cborrow_get(data, i)
      prval () = $A.nth_functional(cell, cell_held)
      prval rest_len = append_len_rest(appended, written_len, total_len)
      prval held_len = holds_len(remaining)
      prval EQI_refl() = len_functional(rest_len, held_len)
      val (holds_after, len_after, joined_len, appended_one | out_after) = _put_byte(holds, written_len, out_len | out, written_count, value)
      prval (appended_front, appended_rest) = append_assoc_rev(APPEND_cons(APPEND_nil()), appended)
      prval EQB_refl() = append_functional(appended_front, appended_one)
    in _copy_loop(rest_held, appended_rest, total_len, holds_after, joined_len, len_after | data, n, i + 1, held_count - 1, out_after, written_count + 1) end

(* The conversion of a document that needs one, and is detected as UTF-16 *)
#pub prfun textof_utf16_conv {cells:$A.cells}{order:byteorder}{mark:int}{n:nat}{total:bytes}
  (TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), DETECT(cells, SrcUtf16(order), mark), $A.CLEN(cells, n)): CONV(cells, SrcUtf16(order), mark, n, total)

primplement textof_utf16_conv {cells}{order}{mark}{n}{total} (plan, detect, length) =
  case+ plan of
  | TEXTOF_utf16_convert(plan_detect, plan_length, conv) => let
      prval (EQSRC_refl(), EQI_refl()) = detect_functional(plan_detect, detect)
      prval () = clen_functional(plan_length, length)
    in conv end
  | TEXTOF_bom_dropped(plan_detect, _, _, _) => (let prval (first_proof, _) = detect_functional(plan_detect, detect) in case+ first_proof of EQSRC_refl() =/=> () end)
  | TEXTOF_single_convert(plan_detect, _, _, _) => (let prval (first_proof, _) = detect_functional(plan_detect, detect) in case+ first_proof of EQSRC_refl() =/=> () end)

(* The conversion of a document that needs one, and is detected as a single-byte encoding *)
#pub prfun textof_single_conv {cells:$A.cells}{page:codepage}{mark:int}{n:nat}{total:bytes}
  (TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), DETECT(cells, SrcTable(page), mark), $A.CLEN(cells, n)): CONV(cells, SrcTable(page), mark, n, total)

primplement textof_single_conv {cells}{page}{mark}{n}{total} (plan, detect, length) =
  case+ plan of
  | TEXTOF_single_convert(plan_detect, _, plan_length, conv) => let
      prval (EQSRC_refl(), EQI_refl()) = detect_functional(plan_detect, detect)
      prval () = clen_functional(plan_length, length)
    in conv end
  | TEXTOF_bom_dropped(plan_detect, _, _, _) => (let prval (first_proof, _) = detect_functional(plan_detect, detect) in case+ first_proof of EQSRC_refl() =/=> () end)
  | TEXTOF_utf16_convert(plan_detect, _, _) => (let prval (first_proof, _) = detect_functional(plan_detect, detect) in case+ first_proof of EQSRC_refl() =/=> () end)

(* The bytes of a document that needs a conversion, and is detected as UTF-8, are the bytes after a byte order mark of three *)
#pub prfun textof_bom_holds {cells:$A.cells}{mark:int}{n:nat}{total:bytes}
  (TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), DETECT(cells, SrcUtf8(), mark), $A.CLEN(cells, n)): [mark == 3; 3 < n] HOLDS(cells, 3, total, n - 3)

primplement textof_bom_holds {cells}{mark}{n}{total} (plan, detect, length) =
  case+ plan of
  | TEXTOF_bom_dropped(plan_detect, plan_length, _, held) => let
      prval (_, EQI_refl()) = detect_functional(plan_detect, detect)
      prval () = clen_functional(plan_length, length)
    in held end
  | TEXTOF_utf16_convert(plan_detect, _, _) => (let prval (first_proof, _) = detect_functional(plan_detect, detect) in case+ first_proof of EQSRC_refl() =/=> () end)
  | TEXTOF_single_convert(plan_detect, _, _, _) => (let prval (first_proof, _) = detect_functional(plan_detect, detect) in case+ first_proof of EQSRC_refl() =/=> () end)

(* A document that needs a conversion is not in an encoding Quire has no table for *)
#pub prfun textof_not_unsupported {cells:$A.cells}{mark:int}{total:bytes} (TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), DETECT(cells, SrcUnsupported(), mark)): FALSEP()

primplement textof_not_unsupported {cells}{mark}{total} (plan, detect) =
  case+ plan of
  | TEXTOF_bom_dropped(plan_detect, _, _, _) => (let prval (first_proof, _) = detect_functional(plan_detect, detect) in case+ first_proof of EQSRC_refl() =/=> () end)
  | TEXTOF_utf16_convert(plan_detect, _, _) => (let prval (first_proof, _) = detect_functional(plan_detect, detect) in case+ first_proof of EQSRC_refl() =/=> () end)
  | TEXTOF_single_convert(plan_detect, _, _, _) => (let prval (first_proof, _) = detect_functional(plan_detect, detect) in case+ first_proof of EQSRC_refl() =/=> () end)

(* The byte order mark of a document is within it *)
#pub prfun detect_mark_in_len {cells:$A.cells}{source:tsrc}{mark:int}{n:nat}
  (DETECT(cells, source, mark), $A.CLEN(cells, n)): [0 <= mark; mark <= n] void

primplement detect_mark_in_len {cells}{source}{mark}{n} (detect, length) =
  case+ detect of
  | DETECT_bom8(_, _, third) => $A.nth_in_len(third, length)
  | DETECT_utf16le_mark(_, second) => $A.nth_in_len(second, length)
  | DETECT_utf16be_mark(_, second) => $A.nth_in_len(second, length)
  | DETECT_utf16le_bare(_, _) => ()
  | DETECT_utf16be_bare(_, _) => ()
  | DETECT_declared_text(_, _, _, _, _, _) => ()
  | DETECT_declared_utf8(_, _, _, _, _, _) => ()
  | DETECT_declared_unsupported(_, _, _, _, _, _) => ()
  | DETECT_declared_table(_, _, _, _, _, _) => ()
  | DETECT_plain(_, _, _, _, _) => ()

(* A document detected as a single-byte encoding by its declaration has no byte order mark *)
#pub prfun detect_table_mark {cells:$A.cells}{page:codepage}{mark:int} (DETECT(cells, SrcTable(page), mark)): [mark == 0] void

primplement detect_table_mark {cells}{page}{mark} (detect) =
  case+ detect of
  | DETECT_declared_table(_, _, _, _, _, _) => ()

(* A document detected as UTF-8 has a byte order mark of three bytes, or none *)
#pub prfun detect_utf8_mark {cells:$A.cells}{mark:int} (DETECT(cells, SrcUtf8(), mark)): [mark == 0 || mark == 3] void

primplement detect_utf8_mark {cells}{mark} (detect) =
  case+ detect of
  | DETECT_bom8(_, _, _) => ()
  | DETECT_declared_text(_, _, _, _, _, _) => ()
  | DETECT_declared_utf8(_, _, _, _, _, _) => ()
  | DETECT_plain(_, _, _, _, _) => ()

(* The plan of a document, as a value *)
#pub datatype text_plan_ix(plan) = ProvedAsIs(PlanAsIs()) | ProvedConvert(PlanConvert()) | ProvedRefused(PlanRefused())

(* The detection of UTF-8: the bytes held after a byte order mark are the output *)
fn _after_utf8 {n:pos}{cells:$A.cells}{mark:nat | mark <= n}{spread:spread}
  (length: $A.CLEN(cells, n), detect: DETECT(cells, SrcUtf8(), mark), run: UTF8RUN(cells, mark, n, spread) | n: int n, mark: int mark)
  : [plan:plan][out:textout] (TEXTOF(cells, plan, out) | text_plan_ix(plan)) =
  if mark = 0 then let
      prval held = holds_exists{cells}{0, n, n}(length)
    in (TEXTOF_utf8_as_is(detect, length, run, held) | ProvedAsIs()) end
  else if n - mark <= 0 then (TEXTOF_bom_only(detect, length, run) | ProvedRefused())
  else let
    prval () = detect_utf8_mark(detect)
    prval held = holds_exists{cells}{3, n - 3, n}(length)
  in (TEXTOF_bom_dropped(detect, length, run, held) | ProvedConvert()) end

(* The output of a document in UTF-16, with the proof of it and the number of bytes it makes *)
fn _convert_utf16 {l:agz}{n:pos}{cells:$A.cells}{order:byteorder}{mark:nat | mark < n}
  (length: $A.CLEN(cells, n), detect: DETECT(cells, SrcUtf16(order), mark)
   | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(SrcUtf16(order)), mark: int mark)
  : [total:bytes][size:pos] (TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), LEN(total, size) | int size) = let
  val (conv, total_len | size) = _converted_size(length | data, n, source, mark)
  prval () = conv_nonempty(conv, total_len)
in (TEXTOF_utf16_convert(detect, length, conv), total_len | size) end

(* The output of a document in a single-byte encoding that is not UTF-8, with the proof of it and the number of bytes it makes *)
fn _convert_single {l:agz}{n:pos}{cells:$A.cells}{page:codepage}{mark:nat | mark < n}
  (length: $A.CLEN(cells, n), detect: DETECT(cells, SrcTable(page), mark), scan: UTF8SCAN(cells, 0, ScannedRefused())
   | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(SrcTable(page)), mark: int mark)
  : [total:bytes][size:pos] (TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), LEN(total, size) | int size) = let
  val (conv, total_len | size) = _converted_size(length | data, n, source, mark)
  prval () = conv_nonempty(conv, total_len)
in (TEXTOF_single_convert(detect, scan, length, conv), total_len | size) end

fn _utf16 {l:agz}{n:pos}{cells:$A.cells}{order:byteorder}{mark:nat | mark <= n}
  (length: $A.CLEN(cells, n), detect: DETECT(cells, SrcUtf16(order), mark)
   | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(SrcUtf16(order)), mark: int mark)
  : [plan:plan][out:textout] (TEXTOF(cells, plan, out) | text_plan_ix(plan)) =
  if n - mark <= 0 then (TEXTOF_utf16_empty(detect, length) | ProvedRefused())
  else let
    val (plan, _ | _) = _convert_utf16(length, detect | data, n, source, mark)
  in (plan | ProvedConvert()) end

fn _single_byte {l:agz}{n:pos}{cells:$A.cells}{page:codepage}{mark:nat | mark <= n}
  (length: $A.CLEN(cells, n), detect: DETECT(cells, SrcTable(page), mark)
   | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(SrcTable(page)), mark: int mark)
  : [plan:plan][out:textout] (TEXTOF(cells, plan, out) | text_plan_ix(plan)) = let
  val (scan | verdict) = text_utf8_scan(length | data, n, 0)
in
  case+ verdict of
  | Utf8Refused() => let
      prval () = detect_table_mark(detect)
      val (plan, _ | _) = _convert_single(length, detect, scan | data, n, source, mark)
    in (plan | ProvedConvert()) end
  | Utf8AsciiOnly() => let
      prval UTF8SCAN_ascii(scan_length, run) = scan prval () = clen_functional(scan_length, length)
      prval held = holds_exists{cells}{0, n, n}(length)
    in (TEXTOF_single_as_is(detect, length, run, held) | ProvedAsIs()) end
  | Utf8Wide() => let
      prval UTF8SCAN_wide(scan_length, run) = scan prval () = clen_functional(scan_length, length)
      prval held = holds_exists{cells}{0, n, n}(length)
    in (TEXTOF_single_as_is(detect, length, run, held) | ProvedAsIs()) end
end

(* What the document in the cells needs, with the proof of its relation to them (TEXTOF) *)
#pub fn text_plan_proved {l:agz}{n:pos}{cells:$A.cells}
  (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n)
  : [plan:plan][out:textout] (TEXTOF(cells, plan, out) | text_plan_ix(plan))

implement text_plan_proved {l}{n}{cells} (length | data, n) = let
  val (detect | source, mark) = text_detect(length | data, n)
  prval () = detect_mark_in_len(detect, length)
in
  case+ source of
  | LabelUtf8() => let
      val (scan | verdict) = text_utf8_scan(length | data, n, mark)
    in
      case+ verdict of
      | Utf8Refused() => (TEXTOF_utf8_invalid(detect, scan) | ProvedRefused())
      | Utf8AsciiOnly() => let prval UTF8SCAN_ascii(scan_length, run) = scan prval () = clen_functional(scan_length, length) in _after_utf8(length, detect, run | n, mark) end
      | Utf8Wide() => let prval UTF8SCAN_wide(scan_length, run) = scan prval () = clen_functional(scan_length, length) in _after_utf8(length, detect, run | n, mark) end
    end
  | LabelUtf16Le() => _utf16(length, detect | data, n, ConvUtf16Le(), mark)
  | LabelUtf16Be() => _utf16(length, detect | data, n, ConvUtf16Be(), mark)
  | LabelUnsupported() => let
      val (scan | verdict) = text_utf8_scan(length | data, n, 0)
    in
      case+ verdict of
      | Utf8AsciiOnly() => let
          prval UTF8SCAN_ascii(scan_length, run) = scan prval () = clen_functional(scan_length, length)
          prval held = holds_exists{cells}{0, n, n}(length)
        in (TEXTOF_unsupported_as_is(detect, length, run, held) | ProvedAsIs()) end
      | Utf8Refused() => (TEXTOF_unsupported_invalid(detect, scan) | ProvedRefused())
      | Utf8Wide() => let prval UTF8SCAN_wide(scan_length, run) = scan prval () = clen_functional(scan_length, length) in (TEXTOF_unsupported_wide(detect, length, run) | ProvedRefused()) end
    end
  | LabelCp1250() => _single_byte(length, detect | data, n, ConvCp1250(), mark)
  | LabelCp1251() => _single_byte(length, detect | data, n, ConvCp1251(), mark)
  | LabelCp1252() => _single_byte(length, detect | data, n, ConvCp1252(), mark)
  | LabelCp1253() => _single_byte(length, detect | data, n, ConvCp1253(), mark)
  | LabelCp1254() => _single_byte(length, detect | data, n, ConvCp1254(), mark)
  | LabelCp1255() => _single_byte(length, detect | data, n, ConvCp1255(), mark)
  | LabelCp1256() => _single_byte(length, detect | data, n, ConvCp1256(), mark)
  | LabelCp1257() => _single_byte(length, detect | data, n, ConvCp1257(), mark)
  | LabelIso88592() => _single_byte(length, detect | data, n, ConvIso88592(), mark)
  | LabelIso88595() => _single_byte(length, detect | data, n, ConvIso88595(), mark)
  | LabelIso88597() => _single_byte(length, detect | data, n, ConvIso88597(), mark)
  | LabelIso88598() => _single_byte(length, detect | data, n, ConvIso88598(), mark)
  | LabelIso885915() => _single_byte(length, detect | data, n, ConvIso885915(), mark)
  | LabelKoi8r() => _single_byte(length, detect | data, n, ConvKoi8r(), mark)
end

(* The size of the output of a document that needs a conversion, with the proof of its relation to the document *)
#pub datavtype text_sized($A.cells) =
  | {cells:$A.cells} TextNoConversion(cells)
  | {cells:$A.cells}{total:bytes}{total_count:pos} TextSized(cells) of (TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), LEN(total, total_count) | int total_count)

fn _sized_after_utf8 {n:pos}{cells:$A.cells}{mark:nat | mark <= n}{spread:spread}
  (length: $A.CLEN(cells, n), detect: DETECT(cells, SrcUtf8(), mark), run: UTF8RUN(cells, mark, n, spread) | n: int n, mark: int mark): text_sized(cells) =
  if mark = 0 then TextNoConversion()
  else if n - mark <= 0 then TextNoConversion()
  else let
    prval () = detect_utf8_mark(detect)
    prval held = holds_exists{cells}{3, n - 3, n}(length)
  in TextSized(TEXTOF_bom_dropped(detect, length, run, held), holds_len(held) | n - 3) end

fn _sized_single {l:agz}{n:pos}{cells:$A.cells}{page:codepage}{mark:nat | mark <= n}
  (length: $A.CLEN(cells, n), detect: DETECT(cells, SrcTable(page), mark)
   | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(SrcTable(page)), mark: int mark): text_sized(cells) = let
  val (scan | verdict) = text_utf8_scan(length | data, n, 0)
in
  case+ verdict of
  | Utf8Refused() => let
      prval () = detect_table_mark(detect)
      val (plan, total_len | size) = _convert_single(length, detect, scan | data, n, source, mark)
    in TextSized(plan, total_len | size) end
  | Utf8AsciiOnly() => TextNoConversion()
  | Utf8Wide() => TextNoConversion()
end

fn _sized_utf16 {l:agz}{n:pos}{cells:$A.cells}{order:byteorder}{mark:nat | mark <= n}
  (length: $A.CLEN(cells, n), detect: DETECT(cells, SrcUtf16(order), mark)
   | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(SrcUtf16(order)), mark: int mark): text_sized(cells) =
  if n - mark <= 0 then TextNoConversion()
  else let
    val (plan, total_len | size) = _convert_utf16(length, detect | data, n, source, mark)
  in TextSized(plan, total_len | size) end

(* How many bytes the document makes when it is converted to UTF-8, when it needs that, with the proof of the output (TEXTOF) *)
#pub fn text_convert_size {l:agz}{n:pos}{cells:$A.cells} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n): text_sized(cells)

implement text_convert_size {l}{n}{cells} (length | data, n) = let
  val (detect | source, mark) = text_detect(length | data, n)
  prval () = detect_mark_in_len(detect, length)
in
  case+ source of
  | LabelUtf8() => let
      val (scan | verdict) = text_utf8_scan(length | data, n, mark)
    in
      case+ verdict of
      | Utf8Refused() => TextNoConversion()
      | Utf8AsciiOnly() => let prval UTF8SCAN_ascii(scan_length, run) = scan prval () = clen_functional(scan_length, length) in _sized_after_utf8(length, detect, run | n, mark) end
      | Utf8Wide() => let prval UTF8SCAN_wide(scan_length, run) = scan prval () = clen_functional(scan_length, length) in _sized_after_utf8(length, detect, run | n, mark) end
    end
  | LabelUtf16Le() => _sized_utf16(length, detect | data, n, ConvUtf16Le(), mark)
  | LabelUtf16Be() => _sized_utf16(length, detect | data, n, ConvUtf16Be(), mark)
  | LabelUnsupported() => TextNoConversion()
  | LabelCp1250() => _sized_single(length, detect | data, n, ConvCp1250(), mark)
  | LabelCp1251() => _sized_single(length, detect | data, n, ConvCp1251(), mark)
  | LabelCp1252() => _sized_single(length, detect | data, n, ConvCp1252(), mark)
  | LabelCp1253() => _sized_single(length, detect | data, n, ConvCp1253(), mark)
  | LabelCp1254() => _sized_single(length, detect | data, n, ConvCp1254(), mark)
  | LabelCp1255() => _sized_single(length, detect | data, n, ConvCp1255(), mark)
  | LabelCp1256() => _sized_single(length, detect | data, n, ConvCp1256(), mark)
  | LabelCp1257() => _sized_single(length, detect | data, n, ConvCp1257(), mark)
  | LabelIso88592() => _sized_single(length, detect | data, n, ConvIso88592(), mark)
  | LabelIso88595() => _sized_single(length, detect | data, n, ConvIso88595(), mark)
  | LabelIso88597() => _sized_single(length, detect | data, n, ConvIso88597(), mark)
  | LabelIso88598() => _sized_single(length, detect | data, n, ConvIso88598(), mark)
  | LabelIso885915() => _sized_single(length, detect | data, n, ConvIso885915(), mark)
  | LabelKoi8r() => _sized_single(length, detect | data, n, ConvKoi8r(), mark)
end

fn _fill_converted {l:agz}{n:pos}{cells:$A.cells}{source:tsrc}{mark:nat | mark <= n}
  {total:bytes}{total_count:pos}{out_location:agz}{out_cells:$A.cells}
  (length: $A.CLEN(cells, n), conv: CONV(cells, source, mark, n, total), total_len: LEN(total, total_count), out_len: $A.CLEN(out_cells, total_count)
   | data: !$A.cborrow(l, n, cells), n: int n, source: conv_source(source), mark: int mark, out: $A.barr(out_location, total_count, out_cells))
  : [out_cells_after:$A.cells] (HOLDS(out_cells_after, 0, total, total_count), $A.CLEN(out_cells_after, total_count) | $A.barr(out_location, total_count, out_cells_after)) =
  _fill_loop(length, conv, APPEND_nil(), total_len, HOLDS_nil(out_len), LEN_nil(), out_len | data, n, source, mark, out, 0)

(* Writes the output of the document that needs a conversion, as text_convert_size says it is, in an array of as many cells as there
   are bytes: the cells of the array come to hold them *)
#pub fn text_convert_fill {l:agz}{n:pos}{cells:$A.cells}{total:bytes}{total_count:pos}{out_location:agz}{out_cells:$A.cells}
  (length: $A.CLEN(cells, n), plan: TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), total_len: LEN(total, total_count), out_len: $A.CLEN(out_cells, total_count)
   | data: !$A.cborrow(l, n, cells), n: int n, out: $A.barr(out_location, total_count, out_cells), total_count: int total_count)
  : [out_cells_after:$A.cells] (HOLDS(out_cells_after, 0, total, total_count), $A.CLEN(out_cells_after, total_count) | $A.barr(out_location, total_count, out_cells_after))

implement text_convert_fill {l}{n}{cells}{total}{total_count}{out_location}{out_cells} (length, plan, total_len, out_len | data, n, out, total_count) = let
  val (detect | source, mark) = text_detect(length | data, n)
  prval () = detect_mark_in_len(detect, length)
in
  case+ source of
  | LabelUtf8() => let
      prval held = textof_bom_holds(plan, detect, length)
      prval EQI_refl() = len_functional(holds_len(held), total_len)
    in _copy_loop(held, APPEND_nil(), total_len, HOLDS_nil(out_len), LEN_nil(), out_len | data, n, 3, n - 3, out, 0) end
  | LabelUtf16Le() => _fill_converted(length, textof_utf16_conv(plan, detect, length), total_len, out_len | data, n, ConvUtf16Le(), mark, out)
  | LabelUtf16Be() => _fill_converted(length, textof_utf16_conv(plan, detect, length), total_len, out_len | data, n, ConvUtf16Be(), mark, out)
  | LabelUnsupported() => (falsep_holds(textof_not_unsupported(plan, detect)), out_len | out)
  | LabelCp1250() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvCp1250(), mark, out)
  | LabelCp1251() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvCp1251(), mark, out)
  | LabelCp1252() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvCp1252(), mark, out)
  | LabelCp1253() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvCp1253(), mark, out)
  | LabelCp1254() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvCp1254(), mark, out)
  | LabelCp1255() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvCp1255(), mark, out)
  | LabelCp1256() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvCp1256(), mark, out)
  | LabelCp1257() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvCp1257(), mark, out)
  | LabelIso88592() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvIso88592(), mark, out)
  | LabelIso88595() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvIso88595(), mark, out)
  | LabelIso88597() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvIso88597(), mark, out)
  | LabelIso88598() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvIso88598(), mark, out)
  | LabelIso885915() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvIso885915(), mark, out)
  | LabelKoi8r() => _fill_converted(length, textof_single_conv(plan, detect, length), total_len, out_len | data, n, ConvKoi8r(), mark, out)
end

(* fixture: the-end-of-text-relation-the *)
(* The end of text_relation: the static fixtures of tests/static/reject named text are put before this line *)

end
