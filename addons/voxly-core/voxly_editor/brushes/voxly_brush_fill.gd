@tool
extends VoxlyBrush
## Fill brush, flood fills a connected region of voxels starting from the
## hovered voxel. Acts as a region selector, active tool applies its 
## operation to every position in the filled region.
##
## By default the flood ignores voxel IDs (Match ID off); enable Match ID to
## restrict the flood to voxels with the same ID as the clicked voxel.

const ICON := preload("res://addons/voxly-core/assets/icons/fill.svg")

## When true, only spread through voxels with the same ID as the clicked
## voxel (standard flood fill). When false (default), spread through the
## entire connected region regardless of voxel ID. Clicking empty space always
## floods the connected empty region.
var match_id: bool = true

## When true, the region is recomputed every frame and ghosted in the
## viewport preview. Flood fill can be expensive on large models, but the
## preview is capped by preview_voxel_limit so it stays responsive.
var enable_preview: bool = true

## Maximum number of voxels to generate during hover preview so it
## stays responsive on large models. Only affects the preview, never the
## actual operation.
var preview_voxel_limit: int = 2048

func _init() -> void:
	name = "fill"
	display_name = "Flood Fill"
	requires_drag = false
	hit_resolution = HitResolution.VOXEL
	icon = ICON

func get_options() -> Array[Dictionary]:
	return [
		{"label": "Continuous", "property": "continuous", "type": TYPE_BOOL, "default": false},
		{"label": "Match ID", "property": "match_id", "type": TYPE_BOOL, "default": true},
		{"label": "Preview Region", "property": "enable_preview", "type": TYPE_BOOL, "default": true},
		{"label": "Preview Voxel Limit", "property": "preview_voxel_limit", "type": TYPE_INT,
			"default": 2048, "min": 256, "max": 65536, "step": 256},
	]

func get_positions(editor, hit: Dictionary) -> Array[Vector3i]:
	var start := _resolve_start_position(editor, hit)
	if start == Vector3i.MAX:
		return []
	
	var adapter = editor.adapter
	if not adapter:
		return []
	
	# Cap the region during hover preview so it stays responsive.
	# The actual operation always uses the full, uncapped region.
	var max_voxels := 0
	if editor.brush_preview_mode and preview_voxel_limit > 0:
		max_voxels = preview_voxel_limit
	
	var target_id = adapter.voxel_at(start)
	# match_id=true restricts the flood to same-ID voxels (flooding through
	# empty space when the click was on air). match_id=false floods the
	# connected region regardless of ID, bounded by occupancy.
	return _flood_fill(adapter, start, target_id, max_voxels, match_id)

func get_preview_color(editor) -> Color:
	if editor.palette_id >= 0 and editor.voxel_set:
		var voxel_data = editor.voxel_set.get_voxel(editor.palette_id)
		if voxel_data:
			var voxel_color : Color = voxel_data.base_color
			if voxel_color.a == 0:
				voxel_color = Color(1, 1, 1, 0.4)
			voxel_color.a = .4
			return voxel_color
	return Color(0.5, 1, 0.5, 0.4)

func show_preview() -> bool:
	return enable_preview

## Resolves the position the fill starts from for the current hit.
## Returns Vector3i.MAX if there is no usable hit.
func _resolve_start_position(editor, hit: Dictionary) -> Vector3i:
	if hit.is_empty():
		return Vector3i.MAX
	var pos := hit.get("position", Vector3i.ZERO)
	var adapter = editor.adapter
	if not adapter:
		return Vector3i.MAX
	if not adapter.is_voxel_position_valid(pos):
		return Vector3i.MAX
	return pos

## Performs a flood fill starting from the given position.
## When `match_id` is true, only spreads through voxels whose ID equals
## `target_id` (flooding through empty space when clicking air).
## When `match_id` is false, spreads through the entire connected region
## of the same occupancy (filled or empty) regardless of voxel ID.
## When `max_voxels > 0`, stops collecting after that many positions.
func _flood_fill(target, start: Vector3i, target_id, max_voxels: int = 0, use_match_id: bool = false) -> Array[Vector3i]:
	var filled: Array[Vector3i] = []
	var visited: Dictionary[Vector3i, bool] = {}
	var queue: Array[Vector3i] = [start]
	
	var start_is_empty := target_id == null
	
	var directions := [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	
	while not queue.is_empty():
		var current = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		
		# Check bounds via the adapter.
		if not target.is_voxel_position_valid(current):
			continue
		
		var voxel_id = target.voxel_at(current)
		var voxel_is_empty := voxel_id == null
		
		# Occupancy gate: never mix filled and empty voxels in one flood.
		if voxel_is_empty != start_is_empty:
			continue
		
		# Optional same-ID gate (only meaningful when filling solid voxels).
		if use_match_id and not start_is_empty and voxel_id != target_id:
			continue
		
		filled.append(current)
		if max_voxels > 0 and filled.size() >= max_voxels:
			return filled
		for dir in directions:
			var neighbor = current + dir
			if not visited.has(neighbor):
				queue.append(neighbor)
	
	return filled
