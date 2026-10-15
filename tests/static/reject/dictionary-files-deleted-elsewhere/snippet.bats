(* A dictionary's files deleted from another module than the Empty Trash
   dialog's: the function that deletes them has no #pub (quire#628) *)
fn _static_dictionary_files_deleted_elsewhere (): void = _dictionary_files_delete(DictFileKeysNil())
