fn _static_held_other_octets {kind:$Z.inflate_kind}{l:agz}{n:pos | n <= 1048576}{cs:$A.cells}{other:bytes}
  (length: $A.CLEN(cs, n) | method: entry_method(kind), compressed: $A.barr(l, n, cs), n: int n): void = let
  val @(back, taken) = take_text_proved(length | method, compressed, n)
  val () = $A.barr_free(back)
in
  case+ taken of
  | ~TextTaken{k}{c,o,t}{p}{octets}{count}{la}(_, _, held, _ | array, _) => let
      prval wrong: HOLDS(t, 0, other, count) = held
    in $A.barr_free(array) end
  | other_taken => text_taken_free(other_taken)
end
