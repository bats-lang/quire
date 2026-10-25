prfn _static_two_documents {first_cells,second_cells:$A.cells}{first_source,second_source,first_mark,second_mark:int}
  (one: DETECT(first_cells, first_source, first_mark), two: DETECT(second_cells, second_source, second_mark)): [first_source == second_source] void = detect_functional(one, two)
