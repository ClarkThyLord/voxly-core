shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, depth_test_disabled;

// Renders only the outer edges of a unit box mesh, producing a thick,
// camera-independent wireframe outline.
//
// The shader evaluates the local vertex position and discards pixels that
// are not near the edges of the cube, leaving behind a wireframe cage.

uniform vec4 outline_color : source_color = vec4(0.2, 1.0, 0.8, 0.9);
uniform float outline_thickness : hint_range(0.0, 0.5) = 0.08;

// Varying variable to pass local vertex position to the fragment shader.
varying vec3 local_pos;

void vertex() {
	// Spatial meshes are normalized around 0.0.
	// Standard BoxMesh goes from -0.5 to 0.5 on all axes.
	local_pos = VERTEX;
}

void fragment() {
	// Get absolute distance from the center of the box face (0.5 is the extreme edge).
	vec3 dist = 0.5 - abs(local_pos);
	
	// Count how many axes are currently inside an "edge zone".
	int edge_count = 0;
	if (dist.x < outline_thickness) edge_count++;
	if (dist.y < outline_thickness) edge_count++;
	if (dist.z < outline_thickness) edge_count++;
	
	// If the pixel is near less than 2 edges, it's a flat face, so throw it away.
	// If it's near 2 or 3 edges, it's a wireframe line or corner.
	if (edge_count < 2) {
		discard;
	}
	
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}