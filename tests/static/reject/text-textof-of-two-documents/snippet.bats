prfn _static_textof_two_documents {first_cells,second_cells:$A.cells}{first_plan,second_plan:plan}{first_out,second_out:textout}
  (one: TEXTOF(first_cells, first_plan, first_out), two: TEXTOF(second_cells, second_plan, second_out)): (EQPLAN(first_plan, second_plan), EQOUT(first_out, second_out)) = textof_functional(one, two)
