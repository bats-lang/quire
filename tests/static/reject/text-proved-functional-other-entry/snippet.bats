prfn _static_other_entry {kind:$Z.inflate_kind}{first_cells,second_cells,first,second:$A.cells}{first_plan,second_plan:plan}{first_octets,second_octets:bytes}
  (first_inflates: $Z.INFLATES(kind, first_cells, first), second_inflates: $Z.INFLATES(kind, second_cells, second),
   first_text: TEXTOF(first, first_plan, TOUT_bytes(first_octets)), second_text: TEXTOF(second, second_plan, TOUT_bytes(second_octets)))
  : EQB(first_octets, second_octets) = let
  prval (_, same) = text_taken_functional(first_inflates, second_inflates, first_text, second_text)
in same end
