extends Node3D
## An employee NPC (WORLD agent). Original "bean" worker (see worker_rig.gd) dressed by station/role, placed by
## staff.gd on a slot {pos, yaw, pose, seat_h}. Name tag fades in when the local player is close.
## Look is derived from the employee id, so a person always looks the same.

const Rig := preload("res://world/actors/worker_rig.gd")
const Bubble := preload("res://world/actors/speech_bubble.gd")
const HQ := preload("res://world/live/hq_state.gd")

const SKINS := [Color(0.96, 0.8, 0.66), Color(0.86, 0.66, 0.5), Color(0.72, 0.52, 0.36), Color(0.55, 0.38, 0.25), Color(0.4, 0.27, 0.18), Color(0.93, 0.76, 0.6)]
const HAIRS := [Color(0.1, 0.07, 0.05), Color(0.25, 0.16, 0.09), Color(0.55, 0.38, 0.2), Color(0.85, 0.7, 0.4), Color(0.6, 0.25, 0.12), Color(0.45, 0.45, 0.47)]
const QUIPS := {
	"design": ["Moving that button 0.2 mm.", "It compiles!", "Who touched my CAD file?", "Rounder corners. Trust me."],
	"research": ["What if... smaller transistors?", "Need more coffee.", "Eureka! ...no, wait.", "Science takes time."],
	"assembly": ["Screw #4 again...", "Careful, it's hot!", "Another one done.", "Where's the tiny screwdriver?"],
	"office": ["Synergy!", "Let's circle back.", "Numbers look... okay?", "Is it Friday yet?"],
}

var employee: Dictionary = {}
var station := "office"
var rig: Node3D
var tag: Label3D
var bubble: Node3D
var _tag_a := 0.0
var _chk := 0.0
var _quip_t := 0.0
var _rng := RandomNumberGenerator.new()

func setup(e: Dictionary, slot: Dictionary) -> void:
	employee = e
	station = HQ.station_of(e)
	var id := str(e.get("id", "npc"))
	_rng.seed = hash(id)
	name = "NPC_" + id.validate_node_name()
	rig = Rig.new()
	rig.name = "Rig"
	rig.head_style = "bean"
	rig.skin = SKINS[_rng.randi() % SKINS.size()]
	rig.hair = HAIRS[_rng.randi() % HAIRS.size()]
	rig.hair_style = _rng.randi() % 4
	rig.shirt = HQ.STATION_SHIRT.get(station, Color(0.4, 0.4, 0.45))
	rig.pants = [Color(0.18, 0.22, 0.32), Color(0.22, 0.2, 0.18), Color(0.15, 0.15, 0.17)][_rng.randi() % 3]
	var role := str(e.get("role", ""))
	match role:
		"Researcher":
			rig.accessory = "coat"
			rig.shirt = Color(0.35, 0.5, 0.75)
		"SoftwareEngineer":
			rig.accessory = "headset"
		"Worker":
			rig.accessory = "vest"
			rig.hat_color = Color(0.95, 0.78, 0.1)
			rig.shirt = Color(0.42, 0.44, 0.46)
		"QCEngineer":
			rig.accessory = "vest"
			rig.hair_style = 2
			rig.hat_color = Color(0.2, 0.6, 0.9)
			rig.shirt = Color(0.42, 0.44, 0.46)
		"Marketer", "FinancialAnalyst":
			rig.accessory = "tie"
		"LogisticsManager":
			rig.accessory = "vest"
	rig.seat_h = float(slot.get("seat_h", 0.47))
	rig.pose = str(slot.get("pose", "stand_think"))
	add_child(rig)
	tag = Label3D.new()
	tag.name = "NameTag"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 1.95 if not str(slot.get("pose", "")).begins_with("sit") else 1.55, 0)
	tag.font_size = 40
	tag.pixel_size = 0.0006
	tag.fixed_size = true
	tag.outline_size = 12
	tag.outline_modulate = Color(0, 0, 0, 0.85)
	tag.text = "%s\n%s" % [str(e.get("name", "Employee")), HQ.role_label(role)]
	tag.modulate = Color(1, 1, 1, 0)
	tag.outline_modulate.a = 0.0
	tag.line_spacing = -4.0
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		tag.font = load("res://ui/fonts/Inter-Bold.ttf")
	add_child(tag)
	bubble = Bubble.new()
	bubble.position = tag.position + Vector3(0, 0.3, 0)
	add_child(bubble)
	position = slot.get("pos", Vector3.ZERO)
	rotation.y = float(slot.get("yaw", 0.0))
	_quip_t = _rng.randf_range(8.0, 25.0)

func say(text: String, seconds: float = 3.0) -> void:
	if rig:
		rig.talk(seconds)
	if bubble:
		bubble.say(text, seconds)

func _process(delta: float) -> void:
	_chk -= delta
	if _chk <= 0.0:
		_chk = 0.2
		var near := false
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam:
			near = cam.global_position.distance_to(global_position + Vector3(0, 1.2, 0)) < 3.2
		_tag_target = 1.0 if near else 0.0
		if near and rig:
			match str(rig.pose):
				"sit_type":
					if _rng.randf() < 0.12:
						Sfx.play("keyboard", global_position + Vector3(0, 0.8, 0), -12.0)
				"stand_scribble":
					if _rng.randf() < 0.07:
						Sfx.play("marker", global_position + Vector3(0, 1.4, 0), -10.0)
				"stand_assemble":
					if _rng.randf() < 0.04:
						Sfx.play("solder", global_position + Vector3(0, 1.0, 0), -14.0)
		_quip_t -= 0.2
		if _quip_t <= 0.0:
			_quip_t = _rng.randf_range(20.0, 45.0)
			if near:
				var q: Array = QUIPS.get(station, QUIPS.office)
				say(q[_rng.randi() % q.size()], 3.0)
	_tag_a = move_toward(_tag_a, _tag_target, delta * 4.0)
	if tag:
		tag.modulate.a = _tag_a
		tag.outline_modulate.a = _tag_a * 0.85
		tag.visible = _tag_a > 0.01

var _tag_target := 0.0
