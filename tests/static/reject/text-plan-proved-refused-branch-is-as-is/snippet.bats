prfn _static_needs_as_is {cells:$A.cells}{out:textout} (plan: TEXTOF(cells, PlanAsIs(), out)): void = ()

fn _static_refused_branch_is_as_is {l:agz}{n:pos}{cells:$A.cells} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n): void = let
  val [plan:plan][out:textout] (plan_proof | choice) = text_plan_proved(length | data, n)
in
  case+ choice of
  | ProvedAsIs() => ()
  | ProvedConvert() => ()
  | ProvedRefused() => let prval () = _static_needs_as_is{cells}{out}(plan_proof) in () end
end
