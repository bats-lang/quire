prfn _static_other_method {compressed,first,second:$A.cells}{first_plan,second_plan:plan}{first_octets,second_octets:bytes}
  (first_inflates: $Z.INFLATES($Z.inflate_stored(), compressed, first), second_inflates: $Z.INFLATES($Z.inflate_deflated(), compressed, second),
   first_text: TEXTOF(first, first_plan, TOUT_bytes(first_octets)), second_text: TEXTOF(second, second_plan, TOUT_bytes(second_octets)))
  : EQB(first_octets, second_octets) = let
  prval (_, same) = text_taken_functional(first_inflates, second_inflates, first_text, second_text)
in same end
