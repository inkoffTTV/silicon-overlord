shader_type canvas_item;
// Lo-fi camera look: chunky pixels, chromatic aberration, grading (lifted blacks, desaturation,
// split toning), vignette, animated film grain, ordered dithering.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float pixel_size = 1.0;            // screen pixels per "lo-fi" pixel
uniform float aberration = 1.2;            // px at the corners
uniform float grain = 0.05;
uniform float vignette = 0.45;
uniform float lift = 0.025;
uniform float saturation = 0.86;
uniform float contrast = 1.06;
uniform float exposure = 1.0;
uniform vec3 shadow_tint = vec3(0.92, 1.0, 1.10);
uniform vec3 highlight_tint = vec3(1.06, 1.0, 0.92);
uniform float dither_levels = 48.0;        // 0 = off
uniform float scanline = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return m[i] / 16.0 - 0.5;
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = floor(FRAGCOORD.xy / pixel_size);
	vec2 uv = (px + 0.5) * pixel_size / res;
	vec2 d = uv - 0.5;
	float r2 = dot(d, d);
	vec2 off = d * r2 * 4.0 * aberration * SCREEN_PIXEL_SIZE * 2.0;
	vec3 col;
	col.r = textureLod(screen_tex, uv + off, 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv - off, 0.0).b;

	col *= exposure;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	// split toning by luminance
	col *= mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.6, l));
	// lifted blacks
	col = col * (1.0 - lift) + lift * vec3(0.55, 0.6, 0.7);
	// vignette
	float v = smoothstep(0.85, 0.2, length(d * vec2(1.15, 1.0)));
	col *= mix(1.0 - vignette, 1.0, v);
	// grain (animated, per lo-fi pixel)
	float g = hash12(px + fract(TIME * 13.7) * 311.0) - 0.5;
	col += g * grain * (0.6 + 0.8 * (1.0 - l));
	// scanlines
	col *= 1.0 - scanline * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159));
	// ordered dithering + quantisation
	if (dither_levels > 0.0) {
		col += bayer4(px) / dither_levels;
		col = floor(col * dither_levels + 0.5) / dither_levels;
	}
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
