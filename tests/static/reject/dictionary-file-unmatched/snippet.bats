(* A dictionary's file kept with the .syn forgotten: its other forms
   would never be looked up *)
fn _static_kept (file_kind: dictionary_file): bool =
  case+ file_kind of
  | IfoFile() => true | IdxFile() => true | DictFile() => true | DictZipFile() => true
  | OtherFile() => false
