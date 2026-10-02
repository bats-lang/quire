(* A plain case: the Trash left out goes unseen *)
datatype shelf = OnShelf | Hidden | Archived | Trash
fn label (shelf: shelf): string =
  case shelf of
  | OnShelf() => "Library"
  | Hidden() => "Hidden"
  | Archived() => "Archived"
(* in a comment, case shelf of is not code, nor in "case x of" *)
