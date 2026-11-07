(* One entry taken three times, as render (with the sum the archive states), search and read aloud take it: the count of the
   pieces of the same text over the cells of each take is one count *)
fn _static_three_takes {kind:$Z.inflate_kind}{l:agz}{n:pos | n <= 1048576}{cs:$A.cells}{text_len:nat}
  (length: $A.CLEN(cs, n) | method: entry_method(kind), compressed: $A.barr(l, n, cs), n: int n, want_high: int, want_low: int,
   text_len: int text_len): $A.barr(l, n, cs) = let
  val @(once, render) = take_text_proved_sum(length | method, compressed, n, want_high, want_low)
  val @(twice, search) = take_text_proved(length | method, once, n)
  val @(thrice, aloud) = take_text_proved(length | method, twice, n)
  val () = (case+ render of
    | ~TextTaken(render_inflates, render_textof, render_held, _ | render_owner, render_array, render_size) =>
      (case+ search of
       | ~TextTaken(search_inflates, search_textof, search_held, _ | search_owner, search_array, search_size) =>
         (case+ aloud of
          | ~TextTaken(aloud_inflates, aloud_textof, aloud_held, _ | aloud_owner, aloud_array, aloud_size) => let
              prval render_taken = TAKEN_of(render_inflates, render_textof, render_held)
              prval search_taken = TAKEN_of(search_inflates, search_textof, search_held)
              prval aloud_taken = TAKEN_of(aloud_inflates, aloud_textof, aloud_held)
              val @(render_frozen, render_cells) = $A.barr_freeze(render_array)
              val @(search_frozen, search_cells) = $A.barr_freeze(search_array)
              val @(aloud_frozen, aloud_cells) = $A.barr_freeze(aloud_array)
              val () = (if text_len <= render_size then
                (if text_len <= search_size then
                  (if text_len <= aloud_size then let
                     val (render_pieces | _) = pieces_find(render_cells, 0, text_len)
                     val (search_pieces | _) = pieces_find(search_cells, 0, text_len)
                     val (aloud_pieces | _) = pieces_find(aloud_cells, 0, text_len)
                     prval () = pieces_of_taken_functional(render_taken, search_taken, render_pieces, search_pieces)
                     prval () = pieces_of_taken_functional(render_taken, aloud_taken, render_pieces, aloud_pieces)
                   in end
                   else ())
                 else ())
               else ())
              val () = $A.cborrow_drop(render_frozen, render_cells)
              val () = $A.cborrow_drop(search_frozen, search_cells)
              val () = $A.cborrow_drop(aloud_frozen, aloud_cells)
              val () = text_give_back(render_owner, $A.barr_thaw(render_frozen))
              val () = text_give_back(search_owner, $A.barr_thaw(search_frozen))
            in text_give_back(aloud_owner, $A.barr_thaw(aloud_frozen)) end
          | other => let
              val () = text_taken_free(other)
              val () = text_give_back(render_owner, render_array)
            in text_give_back(search_owner, search_array) end)
       | other => let
           val () = text_taken_free(other)
           val () = text_taken_free(aloud)
         in text_give_back(render_owner, render_array) end)
    | other => let
        val () = text_taken_free(other)
        val () = text_taken_free(search)
      in text_taken_free(aloud) end)
in thrice end
