(* A shelf's label with the Trash forgotten: a book moved there would
   have no shelf the library could name *)
fn _static_shelf_label (shelf: shelf): string =
  case+ shelf of
  | OnShelf() => "Library"
  | Hidden() => "Hidden"
  | Archived() => "Archived"
