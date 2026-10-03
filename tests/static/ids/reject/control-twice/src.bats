fn _make (): void = ui_text_btn("bats-root", "panel-close", "Close")
#pub fn panel_control_id (control: panel_control): [id_len:pos | id_len < 256] string id_len
implement panel_control_id (control) =
  case+ control of
  | PanelClose() => "panel-close"
  | PanelShut() => "panel-close"
