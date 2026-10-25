prfn _static_not_unsupported_refusal {cells:$A.cells}{mark:int}{total:bytes} (plan: TEXTOF(cells, PlanRefused(), TOUT_bytes(total)), detect: DETECT(cells, SrcUnsupported(), mark)): FALSEP() =
  textof_not_unsupported{cells}{mark}{total}(plan, detect)
