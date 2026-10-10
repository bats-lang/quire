(* A page's height given as the container's, a fraction of a pixel in a
   window that has one: a vertical book's pages would drift down the page *)
fn _static_page_height (): void = let
  val _ = page_height_rule(ContainerLessInsets())
in () end
