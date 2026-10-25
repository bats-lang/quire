prfn _static_enc_two_points {first_point,second_point:int}{first,second:bytes} (one: ENC(first_point, first), two: ENC(second_point, second)): EQB(first, second) = enc_functional(one, two)
