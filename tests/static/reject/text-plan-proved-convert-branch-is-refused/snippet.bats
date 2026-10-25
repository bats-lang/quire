prfn _static_needs_refused {cells:$A.cells}{out:textout} (plan: TEXTOF(cells, PlanRefused(), out)): void = ()

fn _static_convert_branch_is_refused {l:agz}{n:pos}{cells:$A.cells} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n): void = let
  val [plan:plan][out:textout] (plan_proof | choice) = text_plan_proved(length | data, n)
in
  case+ choice of
  | ProvedAsIs() => ()
  | ProvedConvert() => let prval () = _static_needs_refused{cells}{out}(plan_proof) in () end
  | ProvedRefused() => ()
end
