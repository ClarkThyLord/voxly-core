@tool
extends VoxlyEditOperation
## Paste the clipboard voxels at the hovered voxel position.
## The clipboard's minimum corner is aligned to the hit position.

func _init() -> void:
	id = "paste_voxels"
	category = "clipboard"
	display_name = "Paste"
	modifies_voxels = true
	shortcut = make_shortcut(KEY_V, true, false, true)

func is_available(editor) -> bool:
	return editor != null and editor.clipboard != null and not editor.clipboard.is_empty()

func execute(editor, undo_redo: EditorUndoRedoManager, anchor: Vector3i = Vector3i.MAX) -> void:
	var target := _get_target(editor)
	if target == null or editor.clipboard.is_empty():
		return
	
	# Anchor to the hovered voxel, or 0,0,0 if no hit yet.
	if anchor == Vector3i.MAX:
		anchor = Vector3i.ZERO
		if not editor.last_hit.is_empty():
			anchor = editor.last_hit.get("position", Vector3i.ZERO)
	
	# Compute the clipboard's min corner for offsetting.
	var min_corner := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for pos in editor.clipboard:
		min_corner.x = mini(min_corner.x, pos.x)
		min_corner.y = mini(min_corner.y, pos.y)
		min_corner.z = mini(min_corner.z, pos.z)
	
	undo_redo.create_action("Voxly Paste")
	for pos in editor.clipboard:
		var dest = anchor + (pos - min_corner)
		if target.has_method("is_voxel_position_valid"):
			if not target.is_voxel_position_valid(dest):
				continue
		var old_id = target.get_voxel(dest)
		undo_redo.add_do_method(target, "set_voxel", dest, editor.clipboard[pos])
		if old_id != null:
			undo_redo.add_undo_method(target, "set_voxel", dest, old_id)
		else:
			undo_redo.add_undo_method(target, "remove_voxel", dest)
	_record_rebuild(undo_redo, target)
	undo_redo.commit_action()
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "OpPaste",
		"Pasted %d voxels at %s" % [editor.clipboard.size(), anchor])
