## Button that displays a single voxel.
##
## Renders the voxel face preview (color and/or texture) and emits
## selection, unselection, and right-click signals.
@tool
extends Button

## Emitted when a voxel is selected (left click).
signal voxel_selected(voxel_id: int)

## Emitted when a voxel is unselected (ctrl+left click while selected).
signal voxel_unselected(voxel_id: int)

## Emitted when the button is right-clicked.
signal voxel_right_clicked(voxel_id: int, at_position: Vector2)

## Determines which face to display on the button.
## DETECT automatically picks the best face, such that:
## front texture > any face override > base > color.
enum DisplayFace {
	DETECT = -1,
	BASE = 0,
	FRONT = 1,
	BACK = 2,
	LEFT = 3,
	RIGHT = 4,
	TOP = 5,
	BOTTOM = 6,
}

## Which face to display on this button.
@export var display_face: DisplayFace = DisplayFace.DETECT:
	set = set_display_face

## The voxel ID to display.
@export_range(-1, 100, 1, "or_greater")
var voxel_id: int = 0:
	set = set_voxel_id

## The VoxelSet providing the voxel definition.
@export var voxel_set: VoxelSet = null:
	set = set_voxel_set

## Whether the tooltip shows the voxel's name and tags.
@export var tooltip: bool = true:
	set = set_tooltip

## Color swatch showing the voxel base color.
@onready var _color_rect: ColorRect = %Color
## Texture display for textured voxels.
@onready var _texture_rect: TextureRect = %Texture

## The voxel resource currently displayed.
var _voxel: Voxel = null

# True when update() was called before @onready nodes were available.
## True while an update is queued for the ready state.
var _pending_update := false

## Applies any pending update on entering the tree.
func _ready() -> void:
	if _pending_update:
		update()

## Sets which face is shown on this button.
func set_display_face(new_display_face: DisplayFace) -> void:
	if new_display_face == display_face:
		return
	display_face = new_display_face
	if is_inside_tree():
		update()

## Resolves the display face enum to an actual Vector3i direction, applying
## DETECT logic to auto-pick the best face.
func _resolve_display_face(voxel: Voxel) -> Vector3i:
	match display_face:
		DisplayFace.BASE:
			return Vector3i.ZERO
		DisplayFace.FRONT:
			return Vector3i.FORWARD
		DisplayFace.BACK:
			return Vector3i.BACK
		DisplayFace.LEFT:
			return Vector3i.LEFT
		DisplayFace.RIGHT:
			return Vector3i.RIGHT
		DisplayFace.TOP:
			return Vector3i.UP
		DisplayFace.BOTTOM:
			return Vector3i.DOWN
		DisplayFace.DETECT:
			return _detect_best_face(voxel)
		_:
			return Vector3i.ZERO

## Auto-detects the best face to display, with this priority:
## 1. Front face texture override.
## 2. Any face with a texture override (first found).
## 3. Base texture (fall back to base if any texture exists).
## 4. Default to BASE (color only).
func _detect_best_face(voxel: Voxel) -> Vector3i:
	# Priority 1: front face texture override.
	if voxel.has_face_texture_cell(Vector3i.FORWARD, false):
		return Vector3i.FORWARD
	
	# Priority 2: any other face with a texture override.
	for face in Voxel.FACES:
		if voxel.has_face_texture_cell(face, false):
			return face
	
	# Priority 3: base texture (show base to display it).
	if voxel.has_base_texture_cell():
		return Vector3i.ZERO
	
	# Priority 4: default to base (color only).
	return Vector3i.ZERO

## Refreshes the button visuals from the current voxel.
func update() -> void:
	if not voxel_set:
		return
	
	# @onready children may not be available yet.
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
	
	var face: Vector3i = _resolve_display_face(voxel)
	
	# Color swatch always forces alpha to 1 for visibility.
	var face_color := voxel.get_face_color(face)
	face_color.a = 1.0
	_color_rect.color = face_color
	_color_rect.visible = true
	
	# Texture from the atlas, modulated by the face color (alpha forced to 1).
	var texture_cell = voxel.get_face_texture_cell(face)
	if texture_cell >= Vector2i.ZERO and texture_cell != -Vector2i.ONE and voxel_set.is_texture_ready():
		var sub_texture := voxel_set.get_texture_atlas_sub_texture(texture_cell)
		if sub_texture:
			_texture_rect.texture = sub_texture
			_texture_rect.visible = true
			var modulate := voxel.get_face_color(face)
			modulate.a = 1.0
			_texture_rect.modulate = modulate
			_color_rect.visible = false
		else:
			_texture_rect.texture = null
			_texture_rect.visible = false
	else:
		_texture_rect.texture = null
		_texture_rect.visible = false
	
	# Tooltip.
	var voxel_name: String = voxel.name
	if voxel_name.is_empty():
		voxel_name = "(unnamed)"
	if tooltip:
		tooltip_text = "ID: " + str(voxel_id)
		if not voxel_name.is_empty():
			tooltip_text += "\nName: " + voxel_name
		if not voxel.tags.is_empty():
			tooltip_text += "\nTags: " + ", ".join(voxel.tags)
	else:
		tooltip_text = ""

## Sets the voxel set this button reads from.
func set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if new_voxel_set == voxel_set:
		return
	
	# Disconnect the old voxel's changed signal.
	if _voxel and _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.disconnect(_on_voxel_changed)
	
	voxel_set = new_voxel_set
	_voxel = voxel_set.get_voxel(voxel_id) if voxel_set else null
	
	# Connect the new voxel's changed signal for self-update on edits.
	if _voxel and not _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.connect(_on_voxel_changed)
	
	if not is_inside_tree():
		_pending_update = true
	else:
		update()

## Sets the voxel ID to display.
func set_voxel_id(new_voxel_id: int) -> void:
	if new_voxel_id == voxel_id:
		return
	
	# Disconnect the old voxel's changed signal.
	if _voxel and _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.disconnect(_on_voxel_changed)
	
	voxel_id = new_voxel_id
	_voxel = voxel_set.get_voxel(voxel_id) if voxel_set else null
	
	# Connect the new voxel's changed signal.
	if _voxel and not _voxel.changed.is_connected(_on_voxel_changed):
		_voxel.changed.connect(_on_voxel_changed)
	
	if not is_inside_tree():
		_pending_update = true
	else:
		update()

## Toggles whether the voxel name tooltip is shown.
func set_tooltip(new_tooltip: bool) -> void:
	if new_tooltip == tooltip:
		return
	
	tooltip = new_tooltip
	if not tooltip:
		tooltip_text = ""

## Refreshes the button when the voxel data changes.
func _on_voxel_changed() -> void:
	update()

## Emits selection and right-click signals from mouse input.
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
