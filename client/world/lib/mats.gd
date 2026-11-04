extends RefCounted
## Material recipes for the world (see docs/VISUAL_STYLE.md). All procedural, cached by name+tint.
## Usage: const Mats = preload("res://world/lib/mats.gd"); Mats.m("block_wall")

const SURFACE := preload("res://world/shaders/surface.gdshader")
const SCREEN := preload("res://world/shaders/screen.gdshader")

# name -> params for surface.gdshader
const RECIPES := {
	# architecture
	"concrete_floor": {"albedo": Color(0.40, 0.39, 0.37), "albedo2": Color(0.20, 0.19, 0.18), "pattern": 7, "cell": Vector2(2.4, 2.4),
		"roughness_base": 0.78, "roughness2": 0.45, "grime": 0.55, "grime_scale": 0.9, "speckle": 0.14, "bump": 0.8},
	"block_wall": {"albedo": Color(0.47, 0.49, 0.45), "albedo2": Color(0.33, 0.33, 0.31), "pattern": 1, "cell": Vector2(0.40, 0.20),
		"gap": 0.011, "grime": 0.45, "floor_dirt": 0.8, "variation": 0.05, "bump": 1.4},
	"brick": {"albedo": Color(0.46, 0.21, 0.15), "albedo2": Color(0.52, 0.50, 0.46), "pattern": 1, "cell": Vector2(0.26, 0.085),
		"gap": 0.011, "grime": 0.4, "variation": 0.22, "floor_dirt": 0.6, "bump": 1.5},
	"plaster": {"albedo": Color(0.70, 0.66, 0.58), "grime": 0.35, "speckle": 0.05, "floor_dirt": 0.5},
	"plaster_cool": {"albedo": Color(0.58, 0.62, 0.62), "grime": 0.3, "speckle": 0.05, "floor_dirt": 0.5},
	"drywall": {"albedo": Color(0.44, 0.42, 0.39), "grime": 0.25, "speckle": 0.04},
	"ceiling_tiles": {"albedo": Color(0.70, 0.69, 0.64), "albedo2": Color(0.45, 0.45, 0.43), "pattern": 4, "cell": Vector2(0.6, 0.6), "gap": 0.014,
		"grime": 0.3, "variation": 0.04, "bump": 0.6},
	"floor_tiles": {"albedo": Color(0.52, 0.50, 0.46), "albedo2": Color(0.28, 0.27, 0.25), "pattern": 4, "cell": Vector2(0.5, 0.5), "gap": 0.006,
		"roughness_base": 0.35, "grime": 0.35, "variation": 0.06},
	"carpet": {"albedo": Color(0.22, 0.25, 0.30), "albedo2": Color(0.16, 0.18, 0.22), "pattern": 6, "roughness_base": 1.0, "grime": 0.35, "speckle": 0.2},
	"asphalt": {"albedo": Color(0.13, 0.13, 0.14), "albedo2": Color(0.08, 0.08, 0.09), "pattern": 7, "cell": Vector2(40.0, 40.0), "grime": 0.5,
		"speckle": 0.3, "roughness_base": 0.9, "roughness2": 0.4},
	"sidewalk": {"albedo": Color(0.42, 0.41, 0.39), "albedo2": Color(0.25, 0.25, 0.24), "pattern": 7, "cell": Vector2(1.5, 1.5), "grime": 0.4},
	"grass": {"albedo": Color(0.12, 0.17, 0.08), "albedo2": Color(0.08, 0.10, 0.05), "pattern": 6, "roughness_base": 1.0, "speckle": 0.35, "grime": 0.5},
	"siding": {"albedo": Color(0.55, 0.58, 0.60), "albedo2": Color(0.30, 0.32, 0.34), "pattern": 3, "cell": Vector2(30.0, 0.2), "gap": 0.02, "grime": 0.3},
	"siding_warm": {"albedo": Color(0.62, 0.52, 0.40), "albedo2": Color(0.33, 0.27, 0.20), "pattern": 3, "cell": Vector2(30.0, 0.2), "gap": 0.02, "grime": 0.3},
	"roof": {"albedo": Color(0.15, 0.13, 0.13), "albedo2": Color(0.08, 0.07, 0.07), "pattern": 1, "cell": Vector2(0.35, 0.2), "gap": 0.02, "grime": 0.4},
	# wood
	"wood": {"albedo": Color(0.46, 0.30, 0.17), "albedo2": Color(0.30, 0.18, 0.09), "pattern": 2, "roughness_base": 0.7, "edge_wear": 0.3,
		"edge_color": Color(0.62, 0.46, 0.30), "grime": 0.25},
	"wood_dark": {"albedo": Color(0.24, 0.15, 0.09), "albedo2": Color(0.14, 0.08, 0.05), "pattern": 2, "roughness_base": 0.55, "edge_wear": 0.3,
		"edge_color": Color(0.42, 0.30, 0.20), "grime": 0.2},
	"plywood": {"albedo": Color(0.64, 0.50, 0.33), "albedo2": Color(0.50, 0.36, 0.21), "pattern": 2, "roughness_base": 0.8, "edge_wear": 0.4,
		"edge_color": Color(0.75, 0.62, 0.42), "grime": 0.35},
	"wood_planks": {"albedo": Color(0.44, 0.30, 0.18), "albedo2": Color(0.16, 0.10, 0.06), "pattern": 3, "cell": Vector2(1.2, 0.16), "gap": 0.006,
		"roughness_base": 0.55, "roughness2": 0.9, "grime": 0.35, "variation": 0.18},
	"pegboard": {"albedo": Color(0.55, 0.42, 0.28), "albedo2": Color(0.06, 0.05, 0.04), "pattern": 8, "cell": Vector2(0.05, 0.05), "gap": 0.005, "grime": 0.3},
	"cork": {"albedo": Color(0.58, 0.42, 0.26), "albedo2": Color(0.40, 0.27, 0.15), "pattern": 6, "speckle": 0.45, "roughness_base": 1.0},
	# metal / plastic
	"metal": {"albedo": Color(0.62, 0.62, 0.64), "metallic_base": 0.85, "roughness_base": 0.38, "grime": 0.3, "edge_wear": 0.3, "edge_color": Color(0.85, 0.85, 0.87)},
	"steel_dark": {"albedo": Color(0.22, 0.23, 0.25), "metallic_base": 0.7, "roughness_base": 0.5, "grime": 0.35, "edge_wear": 0.4, "edge_color": Color(0.6, 0.6, 0.62)},
	"metal_green": {"albedo": Color(0.20, 0.30, 0.25), "metallic_base": 0.3, "roughness_base": 0.55, "grime": 0.35, "edge_wear": 0.55, "edge_color": Color(0.55, 0.55, 0.55)},
	"metal_red": {"albedo": Color(0.55, 0.10, 0.07), "metallic_base": 0.25, "roughness_base": 0.5, "grime": 0.3, "edge_wear": 0.55, "edge_color": Color(0.6, 0.6, 0.6)},
	"metal_blue": {"albedo": Color(0.12, 0.22, 0.40), "metallic_base": 0.25, "roughness_base": 0.5, "grime": 0.3, "edge_wear": 0.5, "edge_color": Color(0.6, 0.6, 0.6)},
	"metal_yellow": {"albedo": Color(0.75, 0.55, 0.08), "metallic_base": 0.2, "roughness_base": 0.55, "grime": 0.35, "edge_wear": 0.5, "edge_color": Color(0.55, 0.55, 0.55)},
	"rollup": {"albedo": Color(0.60, 0.62, 0.60), "albedo2": Color(0.35, 0.36, 0.35), "pattern": 9, "cell": Vector2(1.0, 0.24), "metallic_base": 0.4,
		"roughness_base": 0.55, "grime": 0.5, "floor_dirt": 1.0},
	"plastic_white": {"albedo": Color(0.80, 0.79, 0.74), "roughness_base": 0.4, "grime": 0.3, "edge_wear": 0.0},
	"plastic_beige": {"albedo": Color(0.72, 0.67, 0.55), "roughness_base": 0.45, "grime": 0.35},
	"plastic_black": {"albedo": Color(0.045, 0.045, 0.05), "roughness_base": 0.42, "grime": 0.15, "edge_wear": 0.15, "edge_color": Color(0.2, 0.2, 0.22)},
	"plastic_grey": {"albedo": Color(0.25, 0.26, 0.28), "roughness_base": 0.5, "grime": 0.2},
	"plastic_orange": {"albedo": Color(0.85, 0.32, 0.06), "roughness_base": 0.45, "grime": 0.25},
	"rubber": {"albedo": Color(0.03, 0.03, 0.03), "roughness_base": 0.9, "grime": 0.1},
	"whiteboard": {"albedo": Color(0.86, 0.87, 0.85), "roughness_base": 0.12, "grime": 0.2, "grime_scale": 3.0, "speckle": 0.02},
	"paper": {"albedo": Color(0.85, 0.83, 0.76), "roughness_base": 0.95, "grime": 0.2, "speckle": 0.03},
	"cardboard": {"albedo": Color(0.56, 0.41, 0.24), "albedo2": Color(0.66, 0.57, 0.40), "pattern": 5, "cell": Vector2(0.03, 0.0),
		"roughness_base": 0.95, "roughness2": 0.35, "grime": 0.35, "grime_scale": 4.0, "edge_wear": 0.3, "edge_color": Color(0.42, 0.30, 0.17)},
	"fabric": {"albedo": Color(0.36, 0.30, 0.14), "pattern": 6, "roughness_base": 1.0, "grime": 0.45, "grime_scale": 2.0, "speckle": 0.15},
	"fabric_blue": {"albedo": Color(0.12, 0.17, 0.28), "pattern": 6, "roughness_base": 1.0, "grime": 0.4, "speckle": 0.15},
	"ceramic": {"albedo": Color(0.85, 0.84, 0.80), "roughness_base": 0.2, "grime": 0.1},
	"tv_black": {"albedo": Color(0.03, 0.03, 0.035), "roughness_base": 0.25, "grime": 0.05},
}

static var _cache := {}

## Get a surface material by recipe name. `tint` multiplies albedo/albedo2. `extra` overrides params.
static func m(name: String, tint: Color = Color.WHITE, extra: Dictionary = {}) -> Material:
	var key := "%s|%s|%s" % [name, tint.to_html(), str(extra)]
	if _cache.has(key):
		return _cache[key]
	var r: Dictionary = RECIPES.get(name, RECIPES["plaster"])
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE
	for k in r:
		mat.set_shader_parameter(k, _conv(r[k]))
	for k in extra:
		mat.set_shader_parameter(k, _conv(extra[k]))
	if tint != Color.WHITE:
		var a: Color = r.get("albedo", Color(0.7, 0.7, 0.7))
		var b: Color = r.get("albedo2", Color(0.4, 0.4, 0.4))
		mat.set_shader_parameter("albedo", _conv(a * tint))
		mat.set_shader_parameter("albedo2", _conv(b * tint))
	_cache[key] = mat
	return mat

static func _conv(v: Variant) -> Variant:
	return v  # Colors stay Colors so source_color uniforms get sRGB->linear conversion

## Glowing emissive material for bulbs, LEDs, neon, lit windows.
static func glow(color: Color, energy: float = 3.0) -> Material:
	var key := "glow|%s|%s" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.4
	_cache[key] = mat
	return mat

## Screen material (see screen.gdshader). Not cached: each screen may animate differently.
static func screen(mode: int, tint: Color = Color(0.45, 0.75, 1.0), energy: float = 1.6, seed: float = 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SCREEN
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("energy", energy)
	mat.set_shader_parameter("seed", seed)
	return mat

static func glass(tint: Color = Color(0.6, 0.7, 0.75, 0.18)) -> Material:
	var key := "glass|%s" % tint.to_html()
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = tint
	mat.roughness = 0.08
	mat.metallic_specular = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = mat
	return mat

static func unlit(color: Color) -> Material:
	var key := "unlit|%s" % color.to_html()
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = mat
	return mat
