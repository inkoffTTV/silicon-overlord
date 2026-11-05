shader_type spatial;
// Objective highlight (WORLD agent): used as GeometryInstance3D.material_overlay. Inverted hull grown along the
// normals by a constant on-screen width + a soft fresnel rim on the surface itself, pulsing. Never touches the
// object's own (shared) materials.
render_mode unshaded, cull_front, depth_draw_never, blend_add, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.76, 0.29);
uniform float width = 0.0028;       // hull growth per metre of view depth (≈ constant pixels)
uniform float strength = 1.0;       // 0 = off (fade in/out)
uniform float pulse_speed = 3.2;

void vertex() {
	vec4 vpos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float depth = max(-vpos.z, 0.2);
	// model space normal growth; the objects are mostly unscaled
	VERTEX += NORMAL * width * depth;
}

void fragment() {
	float p = 0.62 + 0.38 * sin(TIME * pulse_speed);
	ALBEDO = color * 1.5 * p * strength;
	ALPHA = 1.0;
}
