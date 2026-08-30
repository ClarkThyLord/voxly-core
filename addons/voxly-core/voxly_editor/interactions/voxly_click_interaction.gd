## Single-click interaction: applies the active brush + tool once to the
## hovered position on mouse press (no drag, no stroke). This is the behavior
## for brushes with [code]requires_drag = false[/code] and [code]continuous = false[/code].
@tool
class_name VoxlyClickInteraction
extends VoxlyInteraction

## Applies the tool to the clicked position.
func begin(_event: InputEventMouse, _hit: Dictionary) -> void:
	apply_active_tool()

## Refreshes the click preview.
func refresh_preview(hit: Dictionary) -> void:
	if not editor.adapter or not editor.adapter.is_valid():
		clear_preview()
		return
	
	build_preview_source()
	if editor.active_tool and not editor.active_tool.show_preview():
		clear_preview()
		return
	
	if editor.active_brush and not editor.active_brush.show_preview():
		clear_preview()
		return
	
	editor.brush_preview_mode = true
	var positions := get_preview_positions(hit)
	editor.brush_preview_mode = false
	
	# Preview intentionally shows every brush position (even empty cells) so
	# the ghost is always visible while hovering. However, tools that only act
	# on existing voxels (like select) filter positions at commit time in
	# work(). Positions outside the model shape are clipped so no ghost shows
	# outside.
	show_positions(editor.filter_preview_positions(positions), editor.get_preview_color())
