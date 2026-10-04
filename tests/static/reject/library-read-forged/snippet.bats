(* A proof that the library is read, made without reading it: a file
   handed over at start would be imported into the library the read then
   replaces (#262) *)
fn _static_forged (): void = _external_wait(LibraryReadProof() | 1)
