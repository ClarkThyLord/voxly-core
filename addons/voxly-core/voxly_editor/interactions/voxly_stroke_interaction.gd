## Continuous paint interaction: stamps the active brush while the mouse is
## held and moved over the model surface. Every stamp is applied live and
## accumulated into a single undo action committed on release.
@tool
class_name VoxlyStrokeInteraction
extends VoxlyInteraction

## Minimum pixel movement between stroke stamps.
const _STROKE_MOTION_THRESHOLD := 1.0

## Minimum interval between live mesh rebuilds during a stroke (ms).
const _STROKE_REBUILD_INTERVAL_MSEC := 100

## Number of stamps applied in the current stroke.
var _stamp_count: int = 0
## Timestamp of the last preview rebuild.
var _last_rebuild_msec: int = 0
## Last pointer position in screen space.
var _last_screen_position := Vector2(-1, -1)
## True when the pointer has left the surface.
var _off_surface: bool = false

## Starts a stroke at the hit position.
func begin(event: InputEventMouse, hit: Dictionary) -> void:
	if not undo_redo:
		return
	editor.begin_stroke()
	_stamp_count = 0
	_last_rebuild_msec = 0
	_last_screen_position = event.position
	_off_surface = false
	_stamp(hit)
	refresh_preview(hit)

## Stamps the brush along the pointer path.
func update(event: InputEventMouse, hit: Dictionary) -> void:
	if not editor.stroke_active:
		return
	if _off_surface:
		_off_surface = false
		_last_screen_position = event.position
	if event.position.distance_to(_last_screen_position) < _STROKE_MOTION_THRESHOLD:
		refresh_preview(hit)
		return
	if _stamp(hit):
		_last_screen_position = event.position
	refresh_preview(hit)

## Ends the stroke and finalizes the edit.
func finish(_event: InputEventMouse, _hit: Dictionary) -> void:
	if not editor.stroke_active:
		return
	editor.end_stroke(editor.adapter, undo_redo)
	if editor.adapter and editor.adapter.is_valid():
		editor.adapter.update()
	_reset()

## Mouse released off-model mid-stroke is routed here by the controller.
func on_enter_off_surface() -> void:
	_off_surface = true
	clear_preview()

## Cancels the stroke.
func cancel() -> void:
	if editor.stroke_active:
		editor.cancel_stroke(editor.adapter)
	_reset()
	clear_preview()

## Refreshes the stroke preview.
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
	show_positions(editor.filter_preview_positions(positions), editor.get_preview_color())

## Applies the brush at the hit, deduplicating against positions already
## touched in this stroke. Returns true if new voxels were actually written.
func _stamp(hit: Dictionary) -> bool:
	if not undo_redo or hit.is_empty() or not editor.adapter:
		return false
	
	var all_positions := editor.get_mirrored_brush_positions(hit)
	if all_positions.is_empty():
		return false
	
	var new_positions: Array[Vector3i] = []
	for position in all_positions:
		if not editor.stroke_has_touched(position):
			new_positions.append(position)
	if new_positions.is_empty():
		return false
	
	_stamp_count += 1
	editor.stroke_mark_touched(new_positions)
	editor.apply_tool(editor.adapter, new_positions, undo_redo)
	if Time.get_ticks_msec() - _last_rebuild_msec >= _STROKE_REBUILD_INTERVAL_MSEC:
		_last_rebuild_msec = Time.get_ticks_msec()
		if editor.adapter.is_valid():
			editor.adapter.update()
	
	return true

## Resets the stroke state.
func _reset() -> void:
	_stamp_count = 0
	_last_rebuild_msec = 0
	_last_screen_position = Vector2(-1, -1)
	_off_surface = false
