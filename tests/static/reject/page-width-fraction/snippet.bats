(* A page's width given as the container's less the insets, a fraction of
   a pixel in a window that has one: the page's offsets would drift *)
fn _static_page_width (): void = let
  val _ = page_width_rule(ContainerLessInsets())
in () end
