@tool
extends OptionButton

## Emitted when the user selects a different material.
signal material_id_changed(material_id: String)

## The VoxelSet whose materials to display.
@export
var voxel_set: VoxelSet = null:
	set = _set_voxel_set

## Currently selected material id. Empty string means nothing selected.
@export
var material_id: String = "":
	set = _set_material_id

## If true, shows an "Unset" option (empty id) at the top of the list.
@export
var show_unset: bool = false:
	set = _set_show_unset

## If true, shows a "Default" option (empty id) representing VoxelSet default_material.
@export
var show_default: bool = false:
	set = _set_show_default

## Text shown for the "Unset" option when show_unset is true.
var _unset_label := "Unset"

## Text shown for the "Default" option when show_default is true.
var _default_label := "Default"

var _pending_refresh := false
var _unset_index := -1
var _default_index := -1

func _set_voxel_set(new_set: VoxelSet) -> void:
	if voxel_set == new_set:
		return
	if voxel_set and voxel_set.materials_changed.is_connected(_refresh):
		voxel_set.materials_changed.disconnect(_refresh)
	voxel_set = new_set
	if voxel_set and not voxel_set.materials_changed.is_connected(_refresh):
		voxel_set.materials_changed.connect(_refresh)
	if is_inside_tree():
		_refresh()
	else:
		_pending_refresh = true

func _set_material_id(new_id: String) -> void:
	if new_id == material_id:
		return
	material_id = new_id
	_sync_selection()

func _set_show_unset(value: bool) -> void:
	if value == show_unset:
		return
	show_unset = value
	_refresh()

func _set_show_default(value: bool) -> void:
	if value == show_default:
		return
	show_default = value
	_refresh()

func _ready() -> void:
	item_selected.connect(_on_item_selected)
	
	if _pending_refresh:
		_refresh()

## Sets the label text used for the "Unset" option.
func set_unset_label(text: String) -> void:
	if text == _unset_label:
		return
	_unset_label = text
	if show_unset:
		_refresh()

## Sets the label text used for the "Default" option.
func set_default_label(text: String) -> void:
	if text == _default_label:
		return
	_default_label = text
	if show_default:
		_refresh()

## Rebuilds the dropdown from the VoxelSet's materials.
func refresh() -> void:
	_refresh()

func _refresh() -> void:
	_pending_refresh = false
	_unset_index = -1
	_default_index = -1
	clear()
	
	if not voxel_set:
		material_id = ""
		return
	
	if show_unset:
		_unset_index = item_count
		add_item(_unset_label)
		set_item_metadata(_unset_index, "")
	
	if show_default:
		_default_index = item_count
		add_item(_default_label)
		set_item_metadata(_default_index, "")
	
	for id in voxel_set.get_material_ids():
		var idx := item_count
		add_item(id)
		set_item_metadata(idx, id)
	
	# Prune selection if the named material no longer exists.
	if not material_id.is_empty() and not voxel_set.material_id_exists(material_id):
		material_id = ""
	
	_sync_selection()

func _sync_selection() -> void:
	# Empty id normally means "unset". When the Default option is shown, an
	# empty id preferences that option so the default material is displayed.
	if material_id.is_empty() or not voxel_set or not voxel_set.material_id_exists(material_id):
		if _default_index >= 0:
			selected = _default_index
		elif _unset_index >= 0:
			selected = _unset_index
		else:
			selected = -1
		return
	
	for i in item_count:
		if get_item_metadata(i) == material_id:
			selected = i
			return

	selected = -1

func _on_item_selected(index: int) -> void:
	var id := str(get_item_metadata(index))
	if id == material_id:
		return
	material_id = id
	material_id_changed.emit(id)
