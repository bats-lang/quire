fn _static_plan_other_cells {l:agz}{n:pos}{cells,other:$A.cells} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n)
  : [plan:int][out:textout] (TEXTOF(other, plan, out) | text_plan_ix(plan)) = text_plan_proved(length | data, n)
