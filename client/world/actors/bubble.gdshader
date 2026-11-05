shader_type spatial;
// Speech bubble / tag background: camera-facing rounded rectangle with a little tail at the bottom.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 fill : source_color = vec4(0.97, 0.96, 0.92, 0.94);
uniform vec4 border : source_color = vec4(0.08, 0.08, 0.1, 1.0);
uniform vec2 size = vec2(1.0, 0.4);     // world size of the rectangle (without the tail)
uniform float radius = 0.08;
uniform float tail = 0.08;              // tail height (world units), drawn below the rectangle
uniform float alpha = 1.0;

varying vec2 lp;

void vertex() {
	// billboard, keep the node scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	lp = VERTEX.xy;
}

float sd_round_rect(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	// quad spans size.x by (size.y + tail); rectangle centred above the tail
	vec2 p = lp - vec2(0.0, tail * 0.5);
	float d = sd_round_rect(p, size * 0.5, radius);
	// tail: triangle hanging under the rect (apex at the bottom), slightly left of centre
	vec2 tp = lp - vec2(-size.x * 0.12, tail * 0.5 - size.y * 0.5);
	float tri = max(abs(tp.x) - (tp.y + tail) * 0.45, max(-tp.y - tail, tp.y - 0.03));
	d = min(d, tri - 0.004);
	float aa = fwidth(d) * 1.2;
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float edge = 1.0 - smoothstep(-aa, aa, d + 0.012);
	vec4 c = mix(border, fill, edge);
	ALBEDO = c.rgb;
	ALPHA = inside * c.a * alpha;
}
