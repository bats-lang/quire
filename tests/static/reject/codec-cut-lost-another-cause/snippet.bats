(* the cut a record had is the cut it is said to have had *)
prfn _static_lostcat_changes_cause {first_cause,both_cause:seqcause}{first,second,both:lost}{first_n:nat}
  (cat: LOSTCAT(first, second, both, first_n)): LOSTCAT(lt_cut(first_cause, first), second, lt_cut(both_cause, both), first_n+1) = LOSTCAT_cut(cat)
