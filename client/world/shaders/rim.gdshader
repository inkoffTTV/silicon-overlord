shader_type spatial;
// Objective highlight, surface pass (WORLD agent): soft pulsing fresnel glow added on top of the object.
// Chained with outline.gdshader through next_pass; used as material_overlay.
render_mode unshaded, cull_back, depth_draw_never, blend_add, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.76, 0.29);
uniform float strength = 1.0;
uniform float pulse_speed = 3.2;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float p = 0.6 + 0.4 * sin(TIME * pulse_speed);
	ALBEDO = color * (f * 0.75 + 0.05) * p * strength;
}
