@tool
extends Button

signal voxel_selected(voxel_id: int)

signal voxel_unselected(voxel_id: int)

signal voxel_right_clicked(voxel_id: int, at_position: Vector2)

@export_range(-1, 100, 1, "or_greater")
var voxel_id: int = 0:
	set = set_voxel_id

@export
var voxel_set: VoxelSet = null:
	set = set_voxel_set

@export
var display_face := Vector3i.ZERO

@export
var tooltip : bool = true:
	set = set_tooltip

@onready
var _color_rect: ColorRect = %Color

@onready
var _texture_rect: TextureRect = %Texture

var _voxel: Voxel = null

# True when update() was called before @onready nodes were available.
var _pending_update := false

func _ready() -> void:
	if _pending_update:
		update()

func update() -> void:
	if not voxel_set:
		return

	# Guard: @onready children may not be available yet
	if not _color_rect or not _texture_rect:
		_pending_update = true
		return

	var voxel: Voxel = voxel_set.get_voxel(voxel_id)
	_voxel = voxel

	if not voxel:
		_color_rect.color = Color.TRANSPARENT
		_texture_rect.texture = null
		tooltip_text = ""
		return

	# Color swatch
	_color_rect.color = voxel.get_face_color(display_face)
	_color_rect.visible = true

	# Texture from atlas — color modulated by face color
	var uv = voxel.get_face_texture_xy(display_face)
	if uv >= Vector2i.ZERO and uv != -Vector2i.ONE and voxel_set.is_texture_ready():
		var sub := voxel_set.get_texture_atlas_sub_texture(uv)
		if sub:
			_texture_rect.texture = sub
			_texture_rect.visible = true
			_texture_rect.modulate = voxel.get_face_color(display_face)
			_color_rect.visible = false
		else:
			_texture_rect.texture = null
			_texture_rect.visible = false
	else:
		_texture_rect.texture = null
		_texture_rect.visible = false

	# Tooltip
	var vname: String = voxel.name
	if vname.is_empty():
		vname = "(unnamed)"
	if tooltip:
		tooltip_text = "ID: " + str(voxel_id)
		if not vname.is_empty():
			tooltip_text += "\nName: " + vname
		if not voxel.tags.is_empty():
			tooltip_text += "\nTags: " + ", ".join(voxel.tags)
	else:
		tooltip_text = ""

func set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if new_voxel_set == voxel_set:
		return
	
	# Disconnect old voxel's changed signal
	if _voxel and _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.disconnect(_on_voxel_changed)
	
	voxel_set = new_voxel_set
	_voxel = voxel_set.get_voxel(voxel_id) if voxel_set else null
	
	# Connect new voxel's changed signal for self-update on edits
	if _voxel and not _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.connect(_on_voxel_changed)
	
	if not is_inside_tree():
		_pending_update = true
	else:
		update()

func set_voxel_id(new_voxel_id: int) -> void:
	if new_voxel_id == voxel_id:
		return
	
	# Disconnect old voxel's changed signal
	if _voxel and _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.disconnect(_on_voxel_changed)
	
	voxel_id = new_voxel_id
	_voxel = voxel_set.get_voxel(voxel_id) if voxel_set else null
	
	# Connect new voxel's changed signal
	if _voxel and not _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.connect(_on_voxel_changed)
	
	if not is_inside_tree():
		_pending_update = true
	else:
		update()

func set_tooltip(new_tooltip : bool) -> void:
	if new_tooltip == tooltip:
		return
	
	tooltip = new_tooltip
	if not tooltip:
		tooltip_text = ""

func _on_voxel_changed() -> void:
	# Only update this single button — no full list rebuild
	update()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			voxel_right_clicked.emit(voxel_id, get_screen_position() + event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if event.is_ctrl_pressed():
				if button_pressed:
					voxel_unselected.emit(voxel_id)
				else:
					voxel_selected.emit(voxel_id)
			else:
				voxel_selected.emit(voxel_id)
			accept_event()
