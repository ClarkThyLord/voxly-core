@tool
@icon("res://addons/voxly-core/assets/icons/voxel.svg")
class_name Voxel
extends Resource
## A Resource that defines the properties of a single voxel type.
## Stores visual data: color, texture atlas coordinates, and material references.
## Supports per-face overrides for all visual properties.

## Emitted when the voxel's name is changed.
signal name_changed

## Emitted when the voxel's tags are changed.
signal tags_changed

## Emitted when the voxel's base color is changed.
signal base_color_changed

## Emitted when a specific face color is changed.
signal face_color_changed(face: Vector3i)

## Emitted when the voxel's base texture is changed.
signal base_texture_xy_changed

## Emitted when a specific face texture is changed.
signal face_texture_xy_changed(face: Vector3i)

## Emitted when the voxel's base material id is changed.
signal base_material_id_changed

## Emitted when a specific face material id is changed.
signal face_material_id_changed(face: Vector3i)

# Face direction constants.
const FACE_TOP := Vector3i.UP
const FACE_BOTTOM := Vector3i.DOWN
const FACE_FRONT := Vector3i.FORWARD
const FACE_BACK := Vector3i.BACK
const FACE_RIGHT := Vector3i.RIGHT
const FACE_LEFT := Vector3i.LEFT

## All six face directions.
const FACES: Array[Vector3i] = [
	FACE_TOP,
	FACE_BOTTOM,
	FACE_FRONT,
	FACE_BACK,
	FACE_RIGHT,
	FACE_LEFT
]

## All six face names.
const FACE_NAMES : Dictionary[Vector3i, String] = {
	FACE_TOP: "Top",
	FACE_BOTTOM: "Bottom",
	FACE_FRONT: "Front",
	FACE_BACK: "Back",
	FACE_RIGHT: "Right",
	FACE_LEFT: "Left"
}

## Adjacent face mappings for greedy meshing.
## Each entry maps a face to its adjacent faces in [right, left, down, up] order.
const ADJACENT_FACES: Dictionary[Vector3i, Array] = {
	FACE_TOP: [FACE_RIGHT, FACE_LEFT, FACE_BACK, FACE_FRONT],
	FACE_BOTTOM: [FACE_RIGHT, FACE_LEFT, FACE_BACK, FACE_FRONT],
	FACE_RIGHT: [FACE_TOP, FACE_BOTTOM, FACE_BACK, FACE_FRONT],
	FACE_LEFT: [FACE_TOP, FACE_BOTTOM, FACE_BACK, FACE_FRONT],
	FACE_FRONT: [FACE_TOP, FACE_BOTTOM, FACE_RIGHT, FACE_LEFT],
	FACE_BACK: [FACE_TOP, FACE_BOTTOM, FACE_RIGHT, FACE_LEFT]
}

# Color is "unset" if alpha is 0, regardless of rgb values.
const UNSET_COLOR := Color.TRANSPARENT

# Texture x,y is "unset" if has negative x or y value
const UNSET_TEXTURE_XY := -Vector2i.ONE

# Material id is "unset" if is empty
const UNSET_MATERIAL_ID := ""

## Display name for this voxel type
@export
var name: String = "":
	set = set_name,
	get = get_name

## Tag identifiers (e.g., ["flammable", "ore", "solid"]).
@export
var tags: Array[String] = []:
	set = set_tags,
	get = get_tags

## Base color applied to all faces unless overridden per-face.
## Color with alpha value 0 will render white to all color unset faces.
@export
var base_color: Color = Color.WHITE:
	set = set_base_color,
	get = get_base_color

## Base texture atlas coordinates (XY grid position).
## Neither x or y can be negative for valid value.
@export
var base_texture_xy: Vector2i = UNSET_TEXTURE_XY:
	set = set_base_texture_xy,
	get = get_base_texture_xy

## Base material ID string (references a material in VoxelSet).
## Empty string means no material override.
@export
var base_material_id: String = UNSET_MATERIAL_ID:
	set = set_base_material_id,
	get = get_base_material_id

@export_group("Face Overrides")
@export_subgroup("Colors")
@export var top_face_color: Color = UNSET_COLOR:
	set = set_top_face_color
@export var bottom_face_color: Color = UNSET_COLOR:
	set = set_bottom_face_color
@export var front_face_color: Color = UNSET_COLOR:
	set = set_front_face_color
@export var back_face_color: Color = UNSET_COLOR:
	set = set_back_face_color
@export var right_face_color: Color = UNSET_COLOR:
	set = set_right_face_color
@export var left_face_color: Color = UNSET_COLOR:
	set = set_left_face_color

@export_subgroup("Textures")
@export var top_face_texture_xy: Vector2i = UNSET_TEXTURE_XY:
	set = set_top_face_texture_xy
@export var bottom_face_texture_xy: Vector2i = UNSET_TEXTURE_XY:
	set = set_bottom_face_texture_xy
@export var front_face_texture_xy: Vector2i = UNSET_TEXTURE_XY:
	set = set_front_face_texture_xy
@export var back_face_texture_xy: Vector2i = UNSET_TEXTURE_XY:
	set = set_back_face_texture_xy
@export var right_face_texture_xy: Vector2i = UNSET_TEXTURE_XY:
	set = set_right_face_texture_xy
@export var left_face_texture_xy: Vector2i = UNSET_TEXTURE_XY:
	set = set_left_face_texture_xy

@export_subgroup("Materials")
@export var top_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_top_face_material_id
@export var bottom_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_bottom_face_material_id
@export var front_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_front_face_material_id
@export var back_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_back_face_material_id
@export var right_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_right_face_material_id
@export var left_face_material_id: String = UNSET_MATERIAL_ID:
	set = set_left_face_material_id

func set_name(new_name: String) -> void:
	if new_name == name:
		return
	name = new_name
	name_changed.emit()
	changed.emit()

func get_name() -> String:
	return name

func set_tags(new_tags: Array[String]) -> void:
	if new_tags == tags:
		return
	tags = new_tags
	tags_changed.emit()
	changed.emit()

func get_tags() -> Array[String]:
	return tags

func set_base_color(new_base_color: Color) -> void:
	if new_base_color == base_color:
		return
	base_color = new_base_color
	base_color_changed.emit()
	changed.emit()

func set_face_color(face: Vector3i, face_color_value: Color) -> void:
	if not FACE_NAMES.has(face):
		return
	match face:
		FACE_TOP:
			top_face_color = face_color_value
		FACE_BOTTOM:
			bottom_face_color = face_color_value
		FACE_FRONT:
			front_face_color = face_color_value
		FACE_BACK:
			back_face_color = face_color_value
		FACE_RIGHT:
			right_face_color = face_color_value
		FACE_LEFT:
			left_face_color = face_color_value
		_:
			return

func set_top_face_color(color_value: Color) -> void:
	if color_value == top_face_color:
		return
	top_face_color = color_value
	face_color_changed.emit(FACE_TOP)
	changed.emit()

func set_bottom_face_color(color_value: Color) -> void:
	if color_value == bottom_face_color:
		return
	bottom_face_color = color_value
	face_color_changed.emit(FACE_BOTTOM)
	changed.emit()

func set_front_face_color(color_value: Color) -> void:
	if color_value == front_face_color:
		return
	front_face_color = color_value
	face_color_changed.emit(FACE_FRONT)
	changed.emit()

func set_back_face_color(color_value: Color) -> void:
	if color_value == back_face_color:
		return
	back_face_color = color_value
	face_color_changed.emit(FACE_BACK)
	changed.emit()

func set_right_face_color(color_value: Color) -> void:
	if color_value == right_face_color:
		return
	right_face_color = color_value
	face_color_changed.emit(FACE_RIGHT)
	changed.emit()

func set_left_face_color(color_value: Color) -> void:
	if color_value == left_face_color:
		return
	left_face_color = color_value
	face_color_changed.emit(FACE_LEFT)
	changed.emit()

func has_base_color() -> bool:
	return base_color.a > 0

func get_base_color() -> Color:
	return base_color

func has_face_color(face: Vector3i, include_base : bool = true) -> bool:
	match face:
		FACE_TOP:
			return top_face_color.a > 0 or (include_base and base_color.a > 0)
		FACE_BOTTOM:
			return bottom_face_color.a > 0 or (include_base and base_color.a > 0)
		FACE_FRONT:
			return front_face_color.a > 0 or (include_base and base_color.a > 0)
		FACE_BACK:
			return back_face_color.a > 0 or (include_base and base_color.a > 0)
		FACE_RIGHT:
			return right_face_color.a > 0 or (include_base and base_color.a > 0)
		FACE_LEFT:
			return left_face_color.a > 0 or (include_base and base_color.a > 0)
	return (include_base and base_color.a > 0)

func get_face_color(face: Vector3i, include_base : bool = true) -> Color:
	match face:
		FACE_TOP:
			return top_face_color if top_face_color.a > 0 or not include_base else base_color
		FACE_BOTTOM:
			return bottom_face_color if bottom_face_color.a > 0 or not include_base else base_color
		FACE_FRONT:
			return front_face_color if front_face_color.a > 0 or not include_base else base_color
		FACE_BACK:
			return back_face_color if back_face_color.a > 0 or not include_base else base_color
		FACE_RIGHT:
			return right_face_color if right_face_color.a > 0 or not include_base else base_color
		FACE_LEFT:
			return left_face_color if left_face_color.a > 0 or not include_base else base_color
	return base_color

func get_top_face_color(include_base : bool = true) -> Color:
	return get_face_color(FACE_TOP, include_base)
func get_bottom_face_color(include_base : bool = true) -> Color:
	return get_face_color(FACE_BOTTOM, include_base)
func get_front_face_color(include_base : bool = true) -> Color:
	return get_face_color(FACE_FRONT, include_base)
func get_back_face_color(include_base : bool = true) -> Color:
	return get_face_color(FACE_BACK, include_base)
func get_right_face_color(include_base : bool = true) -> Color:
	return get_face_color(FACE_RIGHT, include_base)
func get_left_face_color(include_base : bool = true) -> Color:
	return get_face_color(FACE_LEFT, include_base)

func set_base_texture_xy(new_base_texture_xy: Vector2i) -> void:
	if new_base_texture_xy == base_texture_xy:
		return
	base_texture_xy = new_base_texture_xy
	base_texture_xy_changed.emit()
	changed.emit()

func set_face_texture_xy(face: Vector3i, new_texture_xy: Vector2i) -> void:
	if not ADJACENT_FACES.has(face):
		return
	match face:
		FACE_TOP:
			set_top_face_texture_xy(new_texture_xy)
		FACE_BOTTOM:
			set_bottom_face_texture_xy(new_texture_xy)
		FACE_FRONT:
			set_front_face_texture_xy(new_texture_xy)
		FACE_BACK:
			set_back_face_texture_xy(new_texture_xy)
		FACE_RIGHT:
			set_right_face_texture_xy(new_texture_xy)
		FACE_LEFT:
			set_left_face_texture_xy(new_texture_xy)
		_:
			return

func set_top_face_texture_xy(texture_xy_pos: Vector2i) -> void:
	if texture_xy_pos == top_face_texture_xy:
		return
	top_face_texture_xy = texture_xy_pos
	face_texture_xy_changed.emit(FACE_TOP)
	changed.emit()

func set_bottom_face_texture_xy(texture_xy_pos: Vector2i) -> void:
	if texture_xy_pos == bottom_face_texture_xy:
		return
	bottom_face_texture_xy = texture_xy_pos
	face_texture_xy_changed.emit(FACE_BOTTOM)
	changed.emit()

func set_front_face_texture_xy(texture_xy_pos: Vector2i) -> void:
	if texture_xy_pos == front_face_texture_xy:
		return
	front_face_texture_xy = texture_xy_pos
	face_texture_xy_changed.emit(FACE_FRONT)
	changed.emit()

func set_back_face_texture_xy(texture_xy_pos: Vector2i) -> void:
	if texture_xy_pos == back_face_texture_xy:
		return
	back_face_texture_xy = texture_xy_pos
	face_texture_xy_changed.emit(FACE_BACK)
	changed.emit()

func set_right_face_texture_xy(texture_xy_pos: Vector2i) -> void:
	if texture_xy_pos == right_face_texture_xy:
		return
	right_face_texture_xy = texture_xy_pos
	face_texture_xy_changed.emit(FACE_RIGHT)
	changed.emit()

func set_left_face_texture_xy(texture_xy_pos: Vector2i) -> void:
	if texture_xy_pos == left_face_texture_xy:
		return
	left_face_texture_xy = texture_xy_pos
	face_texture_xy_changed.emit(FACE_LEFT)
	changed.emit()

func has_base_texture_xy() -> bool:
	return base_texture_xy > UNSET_TEXTURE_XY

func get_base_texture_xy() -> Vector2i:
	return base_texture_xy

func has_face_texture_xy(face: Vector3i, include_base : bool = true) -> bool:
	match face:
		FACE_TOP:
			return top_face_texture_xy > UNSET_TEXTURE_XY or (include_base and base_texture_xy > UNSET_TEXTURE_XY)
		FACE_BOTTOM:
			return bottom_face_texture_xy > UNSET_TEXTURE_XY or (include_base and base_texture_xy > UNSET_TEXTURE_XY)
		FACE_FRONT:
			return front_face_texture_xy > UNSET_TEXTURE_XY or (include_base and base_texture_xy > UNSET_TEXTURE_XY)
		FACE_BACK:
			return back_face_texture_xy > UNSET_TEXTURE_XY or (include_base and base_texture_xy > UNSET_TEXTURE_XY)
		FACE_RIGHT:
			return right_face_texture_xy > UNSET_TEXTURE_XY or (include_base and base_texture_xy > UNSET_TEXTURE_XY)
		FACE_LEFT:
			return left_face_texture_xy > UNSET_TEXTURE_XY or (include_base and base_texture_xy > UNSET_TEXTURE_XY)
	return (include_base and base_texture_xy > UNSET_TEXTURE_XY)

func get_face_texture_xy(face: Vector3i, include_base : bool = true) -> Vector2i:
	match face:
		FACE_TOP:
			return top_face_texture_xy if top_face_texture_xy > UNSET_TEXTURE_XY else (base_texture_xy if include_base else UNSET_TEXTURE_XY)
		FACE_BOTTOM:
			return bottom_face_texture_xy if bottom_face_texture_xy > UNSET_TEXTURE_XY else (base_texture_xy if include_base else UNSET_TEXTURE_XY)
		FACE_FRONT:
			return front_face_texture_xy if front_face_texture_xy > UNSET_TEXTURE_XY else (base_texture_xy if include_base else UNSET_TEXTURE_XY)
		FACE_BACK:
			return back_face_texture_xy if back_face_texture_xy > UNSET_TEXTURE_XY else (base_texture_xy if include_base else UNSET_TEXTURE_XY)
		FACE_RIGHT:
			return right_face_texture_xy if right_face_texture_xy > UNSET_TEXTURE_XY else (base_texture_xy if include_base else UNSET_TEXTURE_XY)
		FACE_LEFT:
			return left_face_texture_xy if left_face_texture_xy > UNSET_TEXTURE_XY else (base_texture_xy if include_base else UNSET_TEXTURE_XY)
	return base_texture_xy if include_base else UNSET_TEXTURE_XY

func get_top_face_texture_xy(include_base : bool = true) -> Vector2i:
	return get_face_texture_xy(FACE_TOP, include_base)
func get_bottom_face_texture_xy(include_base : bool = true) -> Vector2i:
	return get_face_texture_xy(FACE_BOTTOM, include_base)
func get_front_face_texture_xy(include_base : bool = true) -> Vector2i:
	return get_face_texture_xy(FACE_FRONT, include_base)
func get_back_face_texture_xy(include_base : bool = true) -> Vector2i:
	return get_face_texture_xy(FACE_BACK, include_base)
func get_right_face_texture_xy(include_base : bool = true) -> Vector2i:
	return get_face_texture_xy(FACE_RIGHT, include_base)
func get_left_face_texture_xy(include_base : bool = true) -> Vector2i:
	return get_face_texture_xy(FACE_LEFT, include_base)

func set_base_material_id(new_base_material_id: String) -> void:
	if new_base_material_id == base_material_id:
		return
	base_material_id = new_base_material_id
	base_material_id_changed.emit()
	changed.emit()

func set_face_material_id(face: Vector3i, new_material_id: String) -> void:
	if not ADJACENT_FACES.has(face):
		return
	match face:
		FACE_TOP:
			set_top_face_material_id(new_material_id)
		FACE_BOTTOM:
			set_bottom_face_material_id(new_material_id)
		FACE_FRONT:
			set_front_face_material_id(new_material_id)
		FACE_BACK:
			set_back_face_material_id(new_material_id)
		FACE_RIGHT:
			set_right_face_material_id(new_material_id)
		FACE_LEFT:
			set_left_face_material_id(new_material_id)
		_:
			return

func set_top_face_material_id(material: String) -> void:
	if material == top_face_material_id:
		return
	top_face_material_id = material
	face_material_id_changed.emit(FACE_TOP)
	changed.emit()

func set_bottom_face_material_id(material: String) -> void:
	if material == bottom_face_material_id:
		return
	bottom_face_material_id = material
	face_material_id_changed.emit(FACE_BOTTOM)
	changed.emit()

func set_front_face_material_id(material: String) -> void:
	if material == front_face_material_id:
		return
	front_face_material_id = material
	face_material_id_changed.emit(FACE_FRONT)
	changed.emit()

func set_back_face_material_id(material: String) -> void:
	if material == back_face_material_id:
		return
	back_face_material_id = material
	face_material_id_changed.emit(FACE_BACK)
	changed.emit()

func set_right_face_material_id(material: String) -> void:
	if material == right_face_material_id:
		return
	right_face_material_id = material
	face_material_id_changed.emit(FACE_RIGHT)
	changed.emit()

func set_left_face_material_id(material: String) -> void:
	if material == left_face_material_id:
		return
	left_face_material_id = material
	face_material_id_changed.emit(FACE_LEFT)
	changed.emit()

func has_base_material_id() -> bool:
	return base_material_id != UNSET_MATERIAL_ID

func get_base_material_id() -> String:
	return base_material_id

func has_face_material_id(face: Vector3i, include_base : bool = true) -> bool:
	match face:
		FACE_TOP:
			return top_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
		FACE_BOTTOM:
			return bottom_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
		FACE_FRONT:
			return front_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
		FACE_BACK:
			return back_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
		FACE_RIGHT:
			return right_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
		FACE_LEFT:
			return left_face_material_id != UNSET_MATERIAL_ID or (include_base and base_material_id != UNSET_MATERIAL_ID)
	return (include_base and base_material_id != UNSET_MATERIAL_ID)

func get_face_material_id(face: Vector3i, include_base : bool = true) -> String:
	match face:
		FACE_TOP:
			return top_face_material_id if top_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
		FACE_BOTTOM:
			return bottom_face_material_id if bottom_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
		FACE_FRONT:
			return front_face_material_id if front_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
		FACE_BACK:
			return back_face_material_id if back_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
		FACE_RIGHT:
			return right_face_material_id if right_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
		FACE_LEFT:
			return left_face_material_id if left_face_material_id != UNSET_MATERIAL_ID else (base_material_id if include_base else UNSET_MATERIAL_ID)
	return base_material_id if include_base else UNSET_MATERIAL_ID

# Convenience per-face getters
func get_top_face_material_id(include_base : bool = true) -> String:
	return get_face_material_id(FACE_TOP, include_base)
func get_bottom_face_material_id(include_base : bool = true) -> String:
	return get_face_material_id(FACE_BOTTOM, include_base)
func get_front_face_material_id(include_base : bool = true) -> String:
	return get_face_material_id(FACE_FRONT, include_base)
func get_back_face_material_id(include_base : bool = true) -> String:
	return get_face_material_id(FACE_BACK, include_base)
func get_right_face_material_id(include_base : bool = true) -> String:
	return get_face_material_id(FACE_RIGHT, include_base)
func get_left_face_material_id(include_base : bool = true) -> String:
	return get_face_material_id(FACE_LEFT, include_base)

## Returns true if the base color is translucent (0 < alpha < 1.0).
## Alpha 0 is the "unset" sentinel, it does NOT apply
## a tint, so it must not make the voxel translucent.
func is_base_color_translucent() -> bool:
	return base_color.a > 0.0 and base_color.a < 1.0

## Returns true if the resolved color for the given face is translucent
## (0 < alpha < 1.0). When `include_base` is true, the base color
## is considered when the face has no override.
func is_face_color_translucent(face: Vector3i, include_base: bool = true) -> bool:
	var face_color := get_face_color(face, include_base)
	return face_color.a > 0.0 and face_color.a < 1.0

func is_top_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_TOP, include_base)
func is_bottom_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_BOTTOM, include_base)
func is_front_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_FRONT, include_base)
func is_back_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_BACK, include_base)
func is_right_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_RIGHT, include_base)
func is_left_face_color_translucent(include_base: bool = true) -> bool:
	return is_face_color_translucent(FACE_LEFT, include_base)

## Returns true if the base color or any per-face color override is translucent.
## This is the color-only test for translucency; material transparency must be
## checked separately via VoxelSet.is_voxel_opaque().
func has_translucent_colors() -> bool:
	if is_base_color_translucent():
		return true
	# Per-face color overrides (face-only, no base fallback).
	for face in FACES:
		if is_face_color_translucent(face, false):
			return true
	return false

## Copies all properties from another Voxel.
func copy_from(source_voxel: Voxel) -> void:
	if not source_voxel:
		return
	
	name = source_voxel.name
	tags = source_voxel.tags.duplicate()
	base_color = source_voxel.base_color
	base_texture_xy = source_voxel.base_texture_xy
	base_material_id = source_voxel.base_material_id
	
	top_face_color = source_voxel.top_face_color
	bottom_face_color = source_voxel.bottom_face_color
	front_face_color = source_voxel.front_face_color
	back_face_color = source_voxel.back_face_color
	right_face_color = source_voxel.right_face_color
	left_face_color = source_voxel.left_face_color
	
	top_face_texture_xy = source_voxel.top_face_texture_xy
	bottom_face_texture_xy = source_voxel.bottom_face_texture_xy
	front_face_texture_xy = source_voxel.front_face_texture_xy
	back_face_texture_xy = source_voxel.back_face_texture_xy
	right_face_texture_xy = source_voxel.right_face_texture_xy
	left_face_texture_xy = source_voxel.left_face_texture_xy
	
	top_face_material_id = source_voxel.top_face_material_id
	bottom_face_material_id = source_voxel.bottom_face_material_id
	front_face_material_id = source_voxel.front_face_material_id
	back_face_material_id = source_voxel.back_face_material_id
	right_face_material_id = source_voxel.right_face_material_id
	left_face_material_id = source_voxel.left_face_material_id
