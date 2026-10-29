(* text_proved -- take_text with its proofs: an entry's data inflated by zip's decoder that returns INFLATES, then read as
   text by text_relation's proved functions, so the text comes with INFLATES and TEXTOF over the same cells (quire#848, a
   piece of quire#608). Keyword: text-proved. The detail is in .claude/rules/book-text.md. *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use zip as Z

staload "bytes.sats"
staload "bytesarr.sats"
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

(* What taking an entry's data as text gave. The array of the text is a barr (the decoder's own output or a conversion of it),
   not an arena piece, and holds at most 1048576 bytes (the decoder's bound). Taken: the entry inflates by its method to the
   cells output (INFLATES), the document in them needs the plan and becomes the octets (TEXTOF), and the array holds exactly
   those octets (HOLDS). Refused: the document is in the cells and is refused (TEXTOF). Empty: the entry inflates to nothing.
   Malformed: the decoder refuses the data. Too large: the data or its conversion is over the bound *)
#pub datavtype text_taken($Z.inflate_kind, $A.cells) =
  | {kind:$Z.inflate_kind}{compressed,output,text:$A.cells}{plan:plan}{octets:bytes}{count:pos | count <= 1048576}{l:agz}
    TextTaken(kind, compressed) of ($Z.INFLATES(kind, compressed, output), TEXTOF(output, plan, TOUT_bytes(octets)),
      HOLDS(text, 0, octets, count), $A.CLEN(text, count) | $A.barr(l, count, text), int count)
  | {kind:$Z.inflate_kind}{compressed,output:$A.cells}{out:textout}
    TextRefused(kind, compressed) of ($Z.INFLATES(kind, compressed, output), TEXTOF(output, PlanRefused(), out) | )
  | {compressed:$A.cells}
    TextEmpty($Z.inflate_deflated(), compressed) of ($Z.INFLATES($Z.inflate_deflated(), compressed, $A.cnil()) | )
  | {kind:$Z.inflate_kind}{compressed:$A.cells} TextMalformed(kind, compressed) of ()
  | {kind:$Z.inflate_kind}{compressed:$A.cells} TextTooLarge(kind, compressed) of ()

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
fn _read_text {kind:$Z.inflate_kind}{compressed,output:$A.cells}{n:pos | n <= 1048576}{l:agz}
  (inflates: $Z.INFLATES(kind, compressed, output), length: $A.CLEN(output, n) | inflated: $A.barr(l, n, output), n: int n)
  : text_taken(kind, compressed) = let
  val @(frozen, view) = $A.barr_freeze(inflated)
  val (plan | which) = text_plan_proved(length | view, n)
in
  case+ which of
  | ProvedAsIs() => let
      prval (as_is, held) = _as_is_holds(plan, length)
      val () = $A.cborrow_drop(frozen, view)
      val back = $A.barr_thaw(frozen)
    in TextTaken(inflates, as_is, held, length | back, n) end
  | ProvedRefused() => let
      val () = $A.cborrow_drop(frozen, view)
      val back = $A.barr_thaw(frozen)
      val () = $A.barr_free(back)
    in TextRefused(inflates, plan | ) end
  | ProvedConvert() =>
    (case+ text_convert_size(length | view, n) of
     | ~TextNoConversion() => let
         val () = $A.cborrow_drop(frozen, view)
         val back = $A.barr_thaw(frozen)
         val () = $A.barr_free(back)
       in TextMalformed() end
     | ~TextSized(converting, total_length | count) =>
       if count <= 1048576 then let
         val (text_length | text) = $A.barr_alloc(count)
         val (held, written_length | written) = text_convert_fill(length, converting, total_length, text_length | view, n, text, count)
         val () = $A.cborrow_drop(frozen, view)
         val back = $A.barr_thaw(frozen)
         val () = $A.barr_free(back)
       in TextTaken(inflates, converting, held, written_length | written, count) end
       else let
         val () = $A.cborrow_drop(frozen, view)
         val back = $A.barr_thaw(frozen)
         val () = $A.barr_free(back)
       in TextTooLarge() end)
end

(* An entry's data (the array `compressed`, whose cells are cs) taken as text: inflated by zip's decoder that proves INFLATES
   (a stored entry is a copy of its data), read by text_plan_proved and, when it needs one, converted by text_convert_fill. The
   array is given back as it was *)
#pub fn take_text_proved {kind:$Z.inflate_kind}{l:agz}{n:pos | n <= 1048576}{cs:$A.cells}
  (length: $A.CLEN(cs, n) | method: entry_method(kind), compressed: $A.barr(l, n, cs), n: int n)
  : @($A.barr(l, n, cs), text_taken(kind, cs))

implement take_text_proved {kind}{l}{n}{cs} (length | method, compressed, n) =
  case+ method of
  | MethodStored() => let
      val copy = $A.barr_copy(compressed, n)
    in @(compressed, _read_text($Z.INFLATES_stored{cs}(), length | copy, n)) end
  | MethodDeflated() => let
      val @(frozen, view) = $A.barr_freeze(compressed)
      val inflating = $Z.inflate_cells_proved(length | view, n)
      val () = $A.cborrow_drop(frozen, view)
      val back = $A.barr_thaw(frozen)
    in
      case+ inflating of
      | ~$Z.inflated_cells_done(inflates, output_length | output, size) => @(back, _read_text(inflates, output_length | output, size))
      | ~$Z.inflated_cells_empty(inflates | ) => @(back, TextEmpty(inflates | ))
      | ~$Z.inflated_cells_malformed() => @(back, TextMalformed())
      | ~$Z.inflated_cells_too_large() => @(back, TextTooLarge())
    end

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
  | ~TextTaken(_, _, _, _ | array, _) => $A.barr_free(array)
  | ~TextRefused(_, _ | ) => ()
  | ~TextEmpty(_ | ) => ()
  | ~TextMalformed() => ()
  | ~TextTooLarge() => ()

(* fixture: the-end-of-text-proved *)
(* The end of text_proved: the static fixtures of tests/static/reject named text-proved are put before this line *)

end (* #target wasm *)
