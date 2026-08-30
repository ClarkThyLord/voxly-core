## Drag-to-define interaction for brushes with [code]requires_drag = true[/code]
## (box, line, extrude). The shape is defined between the press position and
## the current drag position; the tool commits once on release.
@tool
class_name VoxlyDragInteraction
extends VoxlyInteraction

## The brush being dragged.
var _active_brush: VoxlyBrush = null

## Starts the brush drag.
func begin(_event: InputEventMouse, hit: Dictionary) -> void:
	_active_brush = editor.active_brush
	if _active_brush:
		_active_brush.on_drag_start(editor, hit)
		# Show the origin ghost immediately so the drag starts from a visible
		# single voxel.
		refresh_preview(hit)

## Forwards drag movement to the brush.
func update(_event: InputEventMouse, hit: Dictionary) -> void:
	if not _active_brush:
		return
	
	var positions: Array[Vector3i] = _active_brush.on_drag_move(editor, hit)
	# Preview intentionally shows every brush position (even empty cells);
	# however, tools filter at commit time in work(). Positions outside the
	# model shape are clipped so no ghost shows outside.
	show_positions(editor.filter_preview_positions(positions), editor.get_preview_color())

## Ends the brush drag.
func finish(_event: InputEventMouse, _hit: Dictionary) -> void:
	if not _active_brush:
		return
	
	apply_active_tool()
	_active_brush.on_drag_end()
	_active_brush = null
	clear_preview()

## Cancels the drag.
func cancel() -> void:
	if _active_brush:
		_active_brush.on_drag_end()
	_active_brush = null
	clear_preview()

## Refreshes the drag preview.
func refresh_preview(hit: Dictionary) -> void:
	if not _active_brush:
		# No drag in progress: show the "ghost" of a single voxel at the
		# hovered position.
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
		show_positions(editor.filter_preview_positions(positions), editor.get_preview_color())
		return
	
	build_preview_source()
	editor.brush_preview_mode = true
	var positions := get_preview_positions(hit)
	editor.brush_preview_mode = false
	show_positions(editor.filter_preview_positions(positions), editor.get_preview_color())
