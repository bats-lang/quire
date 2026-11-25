(* an outside text of cells the program made, given the proof of other cells (keyword: outside-text) *)
fn _static_forged {a,b,text:$A.cells}{plan:plan}{octets:bytes}{count:int} (from: $BO.OUTSIDE_READ(a), read: TEXTOF(b, plan, TOUT_bytes(octets)), held: HOLDS(text, 0, octets, count)): OUTSIDE_TAKEN(a, text, count) = OUTSIDE_TAKEN_of(from, read, held)
