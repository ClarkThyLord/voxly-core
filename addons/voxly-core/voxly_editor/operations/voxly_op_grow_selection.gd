@tool
extends VoxlyEditOperation
## Grow selection, expands the current selection outward by N voxels.
## Only filled neighbors are added, so the selection stays aligned to content.

const MAX_STEPS := 64

## Steps to grow. Set by the menu before executing.
var steps: int = 1

func _init() -> void:
	id = "grow_selection"
	category = "selection"
	display_name = "Grow"
	prompts_for_options = true

func is_available(editor) -> bool:
	return editor != null and editor.selection != null and editor.selection.count() > 0

## Count submenu entries 1..5 for the quick-count menu.
func get_count_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for count in range(1, 6):
		entries.append({"label": str(count), "count": count})
	return entries

## Returns the option schema used by the ContextWindow's "Other..." prompt.
func get_options() -> Array[Dictionary]:
	return [
		{
			"label": "Steps",
			"property": "steps",
			"type": TYPE_INT,
			"min": 1,
			"max": MAX_STEPS,
			"step": 1,
			"default": 1,
		},
	]

func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null or editor.selection.count() == 0:
		return
	
	var old_positions = editor.selection.to_array()
	var current = editor.selection.to_array()
	var step_count := clampi(steps, 1, MAX_STEPS)
	
	for _step in range(step_count):
		var seen: Dictionary[Vector3i, bool] = {}
		for pos in current:
			seen[pos] = true
	
		var next = current.duplicate()
		for pos in current:
			for dir in _neighbors():
				var neighbor = pos + dir
				if seen.has(neighbor):
					continue
				if target.has_method("is_voxel_position_valid"):
					if not target.is_voxel_position_valid(neighbor):
						continue
				if target.get_voxel(neighbor) != null and not next.has(neighbor):
					next.append(neighbor)
					seen[neighbor] = true
		current = next
	
	undo_redo.create_action("Voxly Grow Selection")
	undo_redo.add_do_method(editor.selection, "set_positions", current)
	undo_redo.add_undo_method(editor.selection, "set_positions", old_positions)
	undo_redo.commit_action()
