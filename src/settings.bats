(* settings -- user preferences with IDB persistence *)

#include "share/atspre_staload.hats"

#use builder as B

(* ============================================================
   Settings accessors
   ============================================================ *)

#pub fn settings_font_size(): int

#pub fn settings_theme(): int

#pub fn settings_margin(): int

#pub fn settings_line_height(): int

(* ============================================================
   Implementations (defaults)
   ============================================================ *)

implement settings_font_size () = 16

implement settings_theme () = 0

implement settings_margin () = 20

implement settings_line_height () = 160
