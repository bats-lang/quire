(* A link found with the one out of the book forgotten: the browser's
   own link would be taken as none *)
fn _static_is_link (found: !link_found): bool =
  case+ found of
  | NoLink() => false
  | InBook(_, _, _, _) => true

