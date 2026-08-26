shader_type spatial;

// The atlas texture containing all voxel cell textures.
uniform sampler2D atlas_texture : source_color;
// The size of one atlas cell in UV space (cell_pixels / atlas_pixels).
uniform vec2 uv_scale;

void fragment() {
	// Convert cell-local UV to atlas UV:
	//   fract(UV)           : wraps [0..N) into [0..1), N = scale_by
	//   * uv_scale          : maps within a single cell's UV footprint
	//   + UV2 * uv_scale    : offsets to the correct cell in the atlas
	vec2 atlas_uv = fract(UV) * uv_scale + UV2 * uv_scale;
	
	// Sample the atlas texture.
	// COLOR interpolates vertex colors (defaults to white if not set),
	// so multiplying with tex_color blends vertex tint with the texture.
	ALBEDO = texture(atlas_texture, atlas_uv).rgb * COLOR.rgb;
}