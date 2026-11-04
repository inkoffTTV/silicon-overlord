shader_type spatial;
// Procedural "believable toy" surface: object-space patterns (brick, wood, planks, tiles,
// cardboard tape, fabric, concrete stains, pegboard, corrugated), grime, worn bevel edges,
// floor dirt and derivative bump mapping. No textures, no UVs needed.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 albedo : source_color = vec3(0.7);
uniform vec3 albedo2 : source_color = vec3(0.4);
uniform int pattern = 0; // 0 plain 1 brick 2 wood 3 planks 4 tiles 5 cardboard 6 fabric 7 concrete 8 pegboard 9 corrugated
uniform vec2 cell = vec2(0.3, 0.1);
uniform float gap = 0.012;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.8;
uniform float roughness2 : hint_range(0.0, 1.0) = 0.9;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
uniform float grime : hint_range(0.0, 1.0) = 0.3;
uniform float grime_scale = 1.5;
uniform float variation : hint_range(0.0, 1.0) = 0.12;
uniform float speckle : hint_range(0.0, 1.0) = 0.08;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.25;
uniform vec3 edge_color : source_color = vec3(0.85);
uniform float floor_dirt : hint_range(0.0, 1.0) = 0.0;
uniform float bump = 1.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(i), b = hash13(i + vec3(1, 0, 0));
	float c = hash13(i + vec3(0, 1, 0)), d = hash13(i + vec3(1, 1, 0));
	float e = hash13(i + vec3(0, 0, 1)), g = hash13(i + vec3(1, 0, 1));
	float h = hash13(i + vec3(0, 1, 1)), k = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s / 0.875;
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Returns brick-like cell info: x = distance to gap (m), y = per-cell random.
vec2 bricks(vec2 uv, vec2 c, float offset_rows) {
	vec2 q = uv / c;
	float row = floor(q.y);
	q.x += offset_rows * (mod(row, 2.0) * 0.5 + hash12(vec2(row, 7.0)) * 0.0);
	vec2 id = floor(q);
	vec2 f = fract(q);
	vec2 gd = min(f, 1.0 - f) * c;
	return vec2(min(gd.x, gd.y), hash12(id + 13.0));
}

void fragment() {
	vec3 an = abs(ln);
	vec2 uv;
	if (an.y > an.x && an.y > an.z) uv = lp.xz;
	else if (an.x > an.z) uv = vec2(lp.z, lp.y);
	else uv = vec2(lp.x, lp.y);

	float m = 0.0;     // 0 = albedo, 1 = albedo2
	float h = 0.0;     // height for bump (metres-ish * 100)
	float cv = 0.5;    // per-cell random
	float rough = roughness_base;

	if (pattern == 1 || pattern == 4) {
		vec2 b = bricks(uv, cell, pattern == 1 ? 1.0 : 0.0);
		float mortar = 1.0 - smoothstep(gap * 0.45, gap, b.x);
		m = mortar;
		h = smoothstep(0.0, gap * 1.6, b.x) * 0.6 + vnoise(lp * 30.0) * 0.15;
		cv = b.y;
		rough = mix(roughness_base, roughness2, mortar);
	} else if (pattern == 2) {
		float n = vnoise(vec3(uv.x * 1.5, uv.y * 9.0, lp.z * 3.0));
		float rings = sin((uv.y * 70.0 + n * 9.0) * 1.0);
		m = smoothstep(0.2, 1.0, rings) * 0.55;
		h = -m * 0.2;
	} else if (pattern == 3) {
		vec2 c = cell;
		vec2 q = uv / c;
		float row = floor(q.y);
		q.x += hash12(vec2(row, 3.0)) * 3.0;
		vec2 id = floor(q);
		vec2 f = fract(q);
		vec2 gd = min(f, 1.0 - f) * c;
		float g = min(gd.x * 3.0, gd.y);
		float seam = 1.0 - smoothstep(gap * 0.4, gap, g);
		cv = hash12(id + 5.0);
		float n = vnoise(vec3(uv.x * 1.2, uv.y * 14.0, cv * 20.0));
		float rings = sin(uv.y * 90.0 + n * 10.0 + cv * 30.0);
		m = max(seam, smoothstep(0.3, 1.0, rings) * 0.35);
		h = smoothstep(0.0, gap * 2.0, g) * 0.6 - m * 0.1;
		rough = mix(roughness_base, roughness2, seam);
	} else if (pattern == 5) {
		// cardboard: tape band across the top and down two sides, flap seam on top
		bool top = an.y > 0.7;
		float tape = (top || an.x > 0.7) ? 1.0 - smoothstep(cell.x - 0.004, cell.x, abs(lp.z)) : 0.0;
		float seam = top ? 1.0 - smoothstep(0.0015, 0.004, abs(lp.z)) : 0.0;
		m = tape;
		h = -seam * 0.5 + tape * 0.1 + vnoise(lp * 60.0) * 0.08;
		rough = mix(roughness_base, roughness2, tape);
	} else if (pattern == 6) {
		float w = sin(uv.x * 500.0) * sin(uv.y * 500.0);
		h = w * 0.12 + vnoise(lp * 8.0) * 0.4;
		m = vnoise(lp * 3.0) * 0.4;
	} else if (pattern == 7) {
		float s = fbm(lp * 0.9 + 3.0);
		float stain = smoothstep(0.58, 0.78, s);
		vec2 j = abs(fract(uv / cell + 0.5) - 0.5) * cell;
		float joint = 1.0 - smoothstep(0.004, 0.009, min(j.x, j.y));
		m = max(stain * 0.8, joint);
		h = -joint * 0.6 + vnoise(lp * 25.0) * 0.25;
		rough = mix(roughness_base, roughness2, stain);
	} else if (pattern == 8) {
		vec2 f = fract(uv / cell) - 0.5;
		float d = length(f) * cell.x;
		float hole = 1.0 - smoothstep(gap * 0.7, gap, d);
		m = hole;
		h = -hole;
	} else if (pattern == 9) {
		float f = fract(uv.y / cell.y);
		float groove = 1.0 - smoothstep(0.0, 0.12, min(f, 1.0 - f));
		h = sin(f * 6.2831) * 0.25 - groove * 0.6;
		m = groove * 0.6;
	}

	vec3 col = mix(albedo, albedo2, m);
	// per-cell variation
	col *= 1.0 + (cv - 0.5) * 2.0 * variation;
	// speckle / micro variation
	col *= 1.0 - speckle + speckle * 2.0 * vnoise(lp * 45.0);
	// large-scale grime
	float gn = fbm(lp * grime_scale + vec3(5.2, 1.3, 7.7));
	float gm = smoothstep(0.35, 0.85, gn) * grime;
	col *= 1.0 - gm * 0.55;
	rough = clamp(rough + gm * 0.15, 0.0, 1.0);
	// dirt near the floor
	col *= 1.0 - floor_dirt * (1.0 - smoothstep(0.0, 0.45, wp.y)) * 0.5;
	// worn bevels (chamfer faces are not axis-aligned)
	float bevel = 1.0 - max(an.x, max(an.y, an.z));
	float e = smoothstep(0.06, 0.18, bevel) * edge_wear;
	col = mix(col, edge_color, e);

	ALBEDO = clamp(col, 0.0, 1.0);
	ROUGHNESS = rough;
	METALLIC = metallic_base;
	SPECULAR = 0.4;
	EMISSION = emission_color * emission_energy;

	// derivative bump mapping (Mikkelsen) — no tangents needed
	float H = h * 0.0025 * bump;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(H);
	float dhy = dFdy(H);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
