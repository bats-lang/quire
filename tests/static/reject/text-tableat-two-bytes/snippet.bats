prfn _static_table_two_bytes {page:codepage}{first_byte,second_byte,first,second:int} (one: TABLEAT(page, first_byte, first), two: TABLEAT(page, second_byte, second)): [first == second] void =
  tableat_functional(one, two)
