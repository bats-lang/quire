prfn _static_needs_convert {cells:$A.cells}{out:textout} (plan: TEXTOF(cells, PlanConvert(), out)): void = ()

fn _static_as_is_branch_is_convert {l:agz}{n:pos}{cells:$A.cells} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n): void = let
  val [plan:plan][out:textout] (plan_proof | choice) = text_plan_proved(length | data, n)
in
  case+ choice of
  | ProvedAsIs() => let prval () = _static_needs_convert{cells}{out}(plan_proof) in () end
  | ProvedConvert() => ()
  | ProvedRefused() => ()
end
