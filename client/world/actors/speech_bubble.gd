extends Node3D
## Comic speech bubble above an avatar / NPC (WORLD agent). say(text, seconds) pops it in, fades it out.
## Camera-facing, readable through the lo-fi filter (dark text on warm paper, black border).

const SHADER := preload("res://world/actors/bubble.gdshader")
const PX := 0.0042          # label pixel size (world units per font pixel)
const FONT_PX := 34
const MAX_W := 560.0        # wrap width in font pixels

var label: Label3D
var bg: MeshInstance3D
var mat: ShaderMaterial
var _left := 0.0
var _a := 0.0
var _base_y := 0.0
var _base_set := false

func _ready() -> void:
	bg = MeshInstance3D.new()
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = 0
	bg.material_override = mat
	add_child(bg)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = FONT_PX
	label.pixel_size = PX
	label.modulate = Color(0.08, 0.08, 0.1)
	label.outline_size = 0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = MAX_W
	label.render_priority = 2
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	label.no_depth_test = false
	if ResourceLoader.exists("res://ui/fonts/Inter-SemiBold.ttf"):
		label.font = load("res://ui/fonts/Inter-SemiBold.ttf")
	add_child(label)
	visible = false

func say(text: String, seconds: float) -> void:
	text = text.strip_edges()
	if text.length() > 140:
		text = text.substr(0, 137) + "..."
	if text == "":
		return
	label.text = text
	var font: Font = label.font if label.font else ThemeDB.fallback_font
	var sz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, MAX_W, FONT_PX, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	var w := minf(sz.x, MAX_W) * PX + 0.16
	var h := sz.y * PX + 0.1
	var tail := 0.09
	var q := QuadMesh.new()
	q.size = Vector2(w, h + tail)
	bg.mesh = q
	bg.position = Vector3(0, (h + tail) * 0.5 - tail, 0)
	label.position = Vector3(0, h * 0.5, 0)
	mat.set_shader_parameter("size", Vector2(w, h))
	mat.set_shader_parameter("tail", tail)
	mat.set_shader_parameter("radius", minf(0.09, h * 0.45))
	_left = maxf(seconds, 1.5)
	if not _base_set:
		_base_y = position.y
		_base_set = true
	visible = true

func is_showing() -> bool:
	return visible and _left > 0.0

func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	var want := 1.0 if _left > 0.0 else 0.0
	_a = move_toward(_a, want, delta * (6.0 if want > 0.5 else 2.5))
	position.y = _base_y + (1.0 - _a) * -0.08
	mat.set_shader_parameter("alpha", _a)
	label.modulate.a = _a
	if _a <= 0.0 and _left <= 0.0:
		visible = false
