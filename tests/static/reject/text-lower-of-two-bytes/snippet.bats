prfn _static_lower_two_bytes {first_raw,second_raw,first,second:int} (one: LOWER(first_raw, first), other: LOWER(second_raw, second)): [first == second] void =
  lower_functional(one, other)
