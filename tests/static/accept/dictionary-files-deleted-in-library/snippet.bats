(* The same call from library.bats, where the function is, checks: the
   reject fixture of the same name fails for it having no #pub, not for a
   misspelt name (quire#628) *)
fn _static_dictionary_files_deleted_here (): void = _dictionary_files_delete(DictFileKeysNil())
