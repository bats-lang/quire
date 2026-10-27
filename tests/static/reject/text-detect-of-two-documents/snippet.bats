prfn _static_two_documents {first_cells,second_cells:$A.cells}{first_source,second_source:tsrc}{first_mark,second_mark:int}
  (one: DETECT(first_cells, first_source, first_mark), two: DETECT(second_cells, second_source, second_mark)): (EQSRC(first_source, second_source), EQI(first_mark, second_mark)) = detect_functional(one, two)
