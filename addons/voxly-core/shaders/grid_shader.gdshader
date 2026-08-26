shader_type spatial;
render_mode unshaded;

uniform int color_mode : hint_range(0, 1) = 0; // 0=by_axis, 1=custom
uniform vec4 custom_color : source_color = vec4(1.0);
uniform bool cull_faces = false;

varying vec3 local_normal;

void vertex() {
	local_normal = NORMAL;
}

void fragment() {
	// Face culling: discard fragments facing away from the camera
	if (cull_faces) {
		vec3 to_camera = normalize((VIEW_MATRIX * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz - VERTEX);
		float view_angle = dot(normalize(NORMAL), to_camera);
		if (view_angle <= 0.0) {
			discard;
		}
	}
	
	vec4 color;
	if (color_mode == 0) {
		// By axis : color based on dominant normal direction
		vec3 abs_n = abs(local_normal);
		if (abs_n.x >= abs_n.y && abs_n.x >= abs_n.z) {
			color = vec4(1.0, 0.0, 0.0, 1.0); // Red for X
		} else if (abs_n.y >= abs_n.x && abs_n.y >= abs_n.z) {
			color = vec4(0.0, 1.0, 0.0, 1.0); // Green for Y
		} else {
			color = vec4(0.0, 0.0, 1.0, 1.0); // Blue for Z
		}
	} else {
		color = custom_color;
	}
	
	ALBEDO = color.rgb;
	ALPHA = color.a;
}