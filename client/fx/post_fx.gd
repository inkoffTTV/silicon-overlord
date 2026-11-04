extends CanvasLayer
## Lo-fi post-processing layer + 3D resolution scaling. Quality "lo-fi" (default) or "clean",
## read from user://settings.cfg [graphics] quality. Call apply_quality("clean") to switch at runtime.

const SHADER := preload("res://fx/post_fx.gdshader")
const SETTINGS := "user://settings.cfg"

const PRESETS := {
	"lo-fi": {"scale": 0.5, "pixel_size": 2.0, "aberration": 1.3, "grain": 0.055, "vignette": 0.5, "lift": 0.03,
		"saturation": 0.84, "contrast": 1.08, "dither_levels": 40.0},
	"clean": {"scale": 1.0, "pixel_size": 1.0, "aberration": 0.0, "grain": 0.0, "vignette": 0.3, "lift": 0.015,
		"saturation": 0.92, "contrast": 1.04, "dither_levels": 0.0},
}

var quality := "lo-fi"
var rect: ColorRect
var mat: ShaderMaterial

func _ready() -> void:
	layer = -1
	rect = ColorRect.new()
	rect.name = "PostFX"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	add_child(rect)
	apply_quality(read_quality())

static func read_quality() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		var q := str(cfg.get_value("graphics", "quality", "lo-fi"))
		if PRESETS.has(q):
			return q
	return "lo-fi"

func apply_quality(q: String) -> void:
	if not PRESETS.has(q):
		q = "lo-fi"
	quality = q
	var p: Dictionary = PRESETS[q]
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = p["scale"]
	# Godot's own TAA/FXAA blur the look; keep the image crisp in lo-fi, smooth in clean.
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if q == "lo-fi" else Viewport.SCREEN_SPACE_AA_FXAA
	for k in p:
		if k != "scale":
			mat.set_shader_parameter(k, p[k])
