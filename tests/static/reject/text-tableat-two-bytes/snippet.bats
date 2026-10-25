prfn _static_table_two_bytes {source,first_byte,second_byte,first,second:int} (one: TABLEAT(source, first_byte, first), two: TABLEAT(source, second_byte, second)): [first == second] void =
  tableat_functional(one, two)
