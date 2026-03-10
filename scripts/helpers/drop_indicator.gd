class_name DropIndicator
extends RefCounted

## Shared drag-and-drop visual indicator helpers used by channel items,
## guild icons, and guild folders.


## Clears the drop indicator state. Returns false so callers can assign
## it directly: `_drop_hovered = DropIndicator.clear(self, _drop_hovered)`
static func clear(control: Control, drop_hovered: bool) -> bool:
	if drop_hovered:
		control.queue_redraw()
	return false


## Draws a horizontal line at the top or bottom of the control to indicate
## where a dragged item will be inserted.
static func draw_line_indicator(control: Control, drop_hovered: bool, drop_above: bool) -> void:
	if not drop_hovered:
		return
	var line_color := ThemeManager.get_color("accent")
	if drop_above:
		control.draw_line(Vector2(0, 0), Vector2(control.size.x, 0), line_color, 2.0)
	else:
		control.draw_line(Vector2(0, control.size.y), Vector2(control.size.x, control.size.y), line_color, 2.0)
