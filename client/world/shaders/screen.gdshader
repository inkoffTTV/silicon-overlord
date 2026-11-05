shader_type spatial;
// Glowing CRT/LCD screen with fake content. mode: 0 code/IDE, 1 phone CAD, 2 dashboard, 3 blank glow.
render_mode unshaded, cull_back;

uniform int mode = 0;
uniform vec3 tint : source_color = vec3(0.45, 0.75, 1.0);
uniform vec3 bg : source_color = vec3(0.02, 0.04, 0.08);
uniform float energy = 1.6;
uniform float curvature = 0.0;
uniform float flicker = 0.03;
uniform float seed = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float rect(vec2 uv, vec2 a, vec2 b) {
	return step(a.x, uv.x) * step(uv.x, b.x) * step(a.y, uv.y) * step(uv.y, b.y);
}

float rrect_line(vec2 uv, vec2 c, vec2 hs, float r, float w) {
	vec2 q = abs(uv - c) - hs + r;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	return 1.0 - smoothstep(0.0, w, abs(d));
}

void fragment() {
	vec2 uv = UV;
	vec2 cc = uv - 0.5;
	uv = 0.5 + cc * (1.0 + curvature * dot(cc, cc));
	float inside = rect(uv, vec2(0.0), vec2(1.0));
	vec3 col = bg;
	float t = TIME + seed * 10.0;
	if (mode == 0) {
		// code editor: indented dashes of "text"
		float line = floor(uv.y * 22.0);
		float ly = fract(uv.y * 22.0);
		float indent = floor(hash12(vec2(line, seed)) * 4.0) * 0.05;
		float len = 0.2 + hash12(vec2(line, seed + 3.0)) * 0.55;
		float word = step(0.25, fract(uv.x * 9.0 + hash12(vec2(line, 9.0))));
		float txt = rect(vec2(uv.x, ly), vec2(0.08 + indent, 0.3), vec2(0.08 + indent + len, 0.7)) * word;
		float h = hash12(vec2(line, seed + 1.0));
		vec3 c = h < 0.3 ? vec3(0.9, 0.6, 0.3) : (h < 0.6 ? tint : vec3(0.75, 0.9, 0.7));
		col = mix(col, c, txt * 0.85);
		col = mix(col, vec3(0.1, 0.13, 0.2), rect(uv, vec2(0.0), vec2(0.05, 1.0)));
		float cursor = rect(uv, vec2(0.5, 0.36), vec2(0.515, 0.4)) * step(0.5, fract(t * 1.2));
		col = mix(col, vec3(1.0), cursor);
	} else if (mode == 1) {
		// phone CAD wireframe
		vec2 g = abs(fract(uv * 16.0) - 0.5);
		float grid = 1.0 - smoothstep(0.0, 0.04, min(g.x, g.y));
		col += tint * grid * 0.12;
		float body = rrect_line(uv, vec2(0.42, 0.5), vec2(0.15, 0.36), 0.05, 0.006);
		float scr = rrect_line(uv, vec2(0.42, 0.5), vec2(0.13, 0.32), 0.035, 0.004);
		float cam = 1.0 - smoothstep(0.0, 0.006, abs(length(uv - vec2(0.42, 0.8)) - 0.012));
		col = mix(col, tint * 1.2, max(body, max(scr * 0.6, cam)));
		float panel = rect(uv, vec2(0.68, 0.1), vec2(0.95, 0.9));
		col = mix(col, vec3(0.08, 0.1, 0.16), panel * 0.9);
		float pl = floor(uv.y * 14.0);
		float bar = rect(uv, vec2(0.71, 0.0), vec2(0.71 + 0.2 * hash12(vec2(pl, 2.0)), 1.0)) * step(0.4, fract(uv.y * 14.0)) * panel;
		col = mix(col, vec3(0.9, 0.7, 0.35), bar * 0.8);
	} else if (mode == 2) {
		// dashboard: header bar + a wobbling line chart
		col = mix(col, tint * 0.35, rect(uv, vec2(0.0, 0.88), vec2(1.0, 1.0)));
		float x = uv.x;
		float y = 0.08 + 0.12 * (x * 0.6 + 0.15 * sin(x * 9.0 + seed) + 0.05 * sin(x * 31.0 + t * 0.2));
		float l = 1.0 - smoothstep(0.0, 0.012, abs(uv.y - y));
		col = mix(col, vec3(0.4, 1.0, 0.6), l * rect(uv, vec2(0.05, 0.03), vec2(0.95, 0.3)) * 0.6);
	} else {
		col = mix(bg, tint, 0.35);
	}
	// scanlines + flicker + vignette
	col *= 0.85 + 0.15 * sin(uv.y * 900.0);
	col *= 1.0 - flicker * hash12(vec2(floor(t * 24.0), seed));
	col *= 1.0 - 0.6 * dot(cc, cc) * 2.0;
	ALBEDO = col * energy * inside;
}
