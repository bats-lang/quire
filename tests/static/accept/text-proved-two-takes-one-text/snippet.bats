(* Two takes of one entry's cells, by one method, are the same text *)
fn _static_two_takes {kind:$Z.inflate_kind}{l:agz}{n:pos | n <= 1048576}{cs:$A.cells}
  (length: $A.CLEN(cs, n) | method: entry_method(kind), compressed: $A.barr(l, n, cs), n: int n): $A.barr(l, n, cs) = let
  val @(once, first) = take_text_proved(length | method, compressed, n)
  val @(twice, second) = take_text_proved(length | method, once, n)
  val () = (case+ first of
    | ~TextTaken(first_inflates, first_text, _, _ | first_array, _) => let
        val () = (case+ second of
          | ~TextTaken(second_inflates, second_text, _, _ | second_array, _) => let
              prval (_, EQB_refl()) = text_taken_functional(first_inflates, second_inflates, first_text, second_text)
            in $A.barr_free(second_array) end
          | other => text_taken_free(other))
      in $A.barr_free(first_array) end
    | other => let
        val () = text_taken_free(other)
      in text_taken_free(second) end)
in twice end
