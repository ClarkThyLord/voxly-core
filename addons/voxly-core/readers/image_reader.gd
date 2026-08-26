@tool
class_name ImageReader
extends RefCounted
## Reads 2D image files (PNG, JPG, etc.) and converts them to 3D voxel content.
##
## Each non-transparent pixel becomes a voxel. The image is placed on the Z=0 plane
## by default, with optional depth extrusion to create thicker voxel models.

const DEBUG_CONTEXT := "ImageReader"

## Maximum number of colors allowed in auto-generated palette
const MAX_PALETTE_COLORS: int = 256

## Reads an Image and converts it to voxel content, optional dictionary:
## alpha_threshold (float): Alpha cutoff (0.0–1.0). Pixels below this are ignored. Default: 0.1
## depth (int): Number of voxel layers to extrude along Z. Default: 1 (flat)
## max_colors (int): Maximum colors in palette. Default: 256
## flip_x (bool): Flip output horizontally. Default: false
## flip_y (bool): Flip output vertically. Default: false
## @return: Dictionary with "error", "voxels", and "palette" keys
static func read(image: Image, options: Dictionary = {}) -> Dictionary:
	var result := {
		"error": OK,
		"voxels": {},
		"palette": {},
	}
	
	var alpha_threshold: float = options.get("alpha_threshold", 0.1)
	var depth: int = options.get("depth", 1)
	var max_colors: int = options.get("max_colors", MAX_PALETTE_COLORS)
	var flip_x: bool = options.get("flip_x", false)
	var flip_y: bool = options.get("flip_y", false)
	
	depth = maxi(depth, 1)
	max_colors = clamp(max_colors, 1, MAX_PALETTE_COLORS)
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Reading image: %dx%d, depth=%d, max_colors=%d" % [image.get_width(), image.get_height(), depth, max_colors])
	
	image = _prepare_image(image, flip_x, flip_y)
	
	# Collect all unique colors and build the palette
	var color_to_id: Dictionary = {}
	var next_id: int = 0
	
	for x in image.get_width():
		for y in image.get_height():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a >= alpha_threshold:
				var opaque_color := Color(pixel.r, pixel.g, pixel.b, 1.0)
				var color_key := _color_to_key(opaque_color)
				if not color_to_id.has(color_key):
					color_to_id[color_key] = next_id
					var voxel := Voxel.new()
					voxel.base_color = opaque_color
					voxel.name = "color_%d" % next_id
					result["palette"][next_id] = voxel
					next_id += 1
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Image palette: %d colors from image" % result["palette"].size())
	
	# Quantize palette if needed
	if result["palette"].size() > max_colors:
		_quantize_palette(result, color_to_id, max_colors)
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Quantized palette to %d colors" % result["palette"].size())
	
	# Create voxels
	for x in image.get_width():
		for y in image.get_height():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a >= alpha_threshold:
				var opaque_color := Color(pixel.r, pixel.g, pixel.b, 1.0)
				var color_key := _color_to_key(opaque_color)
				var voxel_id: int = color_to_id.get(color_key, -1)
				if voxel_id == -1:
					# Quantization may have changed the key, find the nearest match
					voxel_id = _find_nearest_color(color_to_id, opaque_color)
				# Invert Y so the image appears upright when imported.
				var voxel_y := image.get_height() - 1 - y
				for z in depth:
					result["voxels"][Vector3i(x, voxel_y, z)] = voxel_id
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Generated %d voxels from image" % result["voxels"].size())
	
	return result

## Reads an image file from disk and converts it to voxel content.
static func read_file(file_path: String, options: Dictionary = {}) -> Dictionary:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Reading image file: '%s'" % file_path)
	
	# Read file bytes directly and load via format-specific loader
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Failed to open image file: '%s'" % file_path)
		return { "error": ERR_FILE_CANT_OPEN, "voxels": {}, "palette": {} }
	
	var ext := file_path.get_extension().to_lower()
	var buffer := file.get_buffer(file.get_length())
	file.close()
	
	var image := Image.new()
	var load_error: int
	
	match ext:
		"png":
			load_error = image.load_png_from_buffer(buffer)
		"jpg", "jpeg":
			load_error = image.load_jpg_from_buffer(buffer)
		"bmp":
			load_error = image.load_bmp_from_buffer(buffer)
		"tga":
			load_error = image.load_tga_from_buffer(buffer)
		"webp":
			load_error = image.load_webp_from_buffer(buffer)
		_:
			# Fallback: try direct file load
			image = Image.load_from_file(file_path)
			if image == null:
				load_error = ERR_FILE_UNRECOGNIZED
			else:
				load_error = OK
	
	if load_error != OK or image == null or image.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Failed to load image file: '%s'" % file_path)
		return { "error": ERR_FILE_CANT_OPEN, "voxels": {}, "palette": {} }
	
	var options_copy: Dictionary = options.duplicate()
	options_copy["max_colors"] = options.get("max_colors", MAX_PALETTE_COLORS)
	var result := read(image, options_copy)
	
	if result.get("error") == OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Image read OK: %d voxels, %d palette colors" % [result.get("voxels", {}).size(), result.get("palette", {}).size()])
	
	return result

## Converts a Color to a string key for dictionary lookups.
## Rounds to 8-bit precision to handle float rounding differences.
static func _color_to_key(color: Color) -> String:
	var r := roundi(color.r8)
	var g := roundi(color.g8)
	var b := roundi(color.b8)
	var a := roundi(color.a8)
	return "%d_%d_%d_%d" % [r, g, b, a]

## Finds the nearest color in a color_to_id dictionary by Euclidean distance.
## Used as a fallback when quantization changes exact color keys.
static func _find_nearest_color(color_to_id: Dictionary, target: Color) -> int:
	var best_id: int = 0
	var best_dist: float = INF
	var tr := target.r8
	var tg := target.g8
	var tb := target.b8
	for key in color_to_id:
		var parts: PackedStringArray = key.split("_")
		if parts.size() >= 3:
			var kr := int(parts[0])
			var kg := int(parts[1])
			var kb := int(parts[2])
			var dr := tr - kr
			var dg := tg - kg
			var db := tb - kb
			var dist := dr * dr + dg * dg + db * db
			if dist < best_dist:
				best_dist = dist
				best_id = color_to_id[key]
	return best_id

## Prepares the image: converts to RGBA8 and applies flips.
static func _prepare_image(image: Image, flip_x: bool, flip_y: bool) -> Image:
	var prepared := image.duplicate()
	
	# Convert to RGBA8 format if not already
	if prepared.get_format() != Image.FORMAT_RGBA8:
		prepared.convert(Image.FORMAT_RGBA8)
	
	# Apply flips
	if flip_x:
		prepared.flip_x()
	if flip_y:
		prepared.flip_y()
	
	return prepared

## Simplistic color quantization: reduces the number of colors by rounding
## each channel to the nearest step and merging duplicates.
static func _quantize_palette(result: Dictionary, color_to_id: Dictionary, max_colors: int) -> void:
	var palette: Dictionary = result["palette"]
	
	# Downscale each color's precision to reduce unique colors
	var precision := 4  # Divide 0-255 into 64 steps (256/4 = 64)
	var step: int = 256 / precision
	
	while palette.size() > max_colors and step < 256:
		var quantized_map: Dictionary = {}
		var new_palette: Dictionary = {}
		var new_color_to_id: Dictionary = {}
		var next_id: int = 0
		
		for voxel_id in palette:
			var voxel: Voxel = palette[voxel_id]
			var c := voxel.base_color
			var r := roundi(c.r8 / step) * step
			var g := roundi(c.g8 / step) * step
			var b := roundi(c.b8 / step) * step
			var qkey := "%d_%d_%d_255" % [r, g, b]
			
			if not quantized_map.has(qkey):
				var qvoxel := Voxel.new()
				qvoxel.base_color = Color8(r, g, b, 255)
				qvoxel.name = "quantized_%d" % next_id
				new_palette[next_id] = qvoxel
				new_color_to_id[qkey] = next_id
				quantized_map[qkey] = next_id
				next_id += 1
		
		# Update the palette
		palette.clear()
		for vid in new_palette:
			palette[vid] = new_palette[vid]
		
		# Update color_to_id mapping
		color_to_id.clear()
		for k in new_color_to_id:
			color_to_id[k] = new_color_to_id[k]
		
		step *= 2  # Increase step for next iteration if still too many colors
	
	result["palette"] = palette
