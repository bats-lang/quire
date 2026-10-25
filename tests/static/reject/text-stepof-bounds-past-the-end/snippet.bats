prfn _static_step_past_end {cells:$A.cells}{source:int}{i,n:nat}{to,point:int} (step: STEPOF(cells, source, i, to, point), length: $A.CLEN(cells, n)): [to < n] void = stepof_bounds(step, length)
