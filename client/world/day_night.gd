extends Node
## Day–night cycle through the windows (WORLD agent, 0.5.0). The game has no clock hours, so the sky runs one slow
## cycle per in-game month (elapsedDays % 30 + a smooth client-side fraction), never faster than MIN_CYCLE real
## seconds, frozen while paused. Phase 0 = dusk (the look the rest of the game was tuned for), 0.25 midnight,
## 0.5 dawn, 0.75 noon. Night/dusk take most of the cycle: the moody lo-fi look stays the default.
## Drives: the procedural sky colours, a little ambient, and per-window "daylight" spots the level offers through
## level.daylight_windows() -> [{pos, target}] (level space), and a sun that lights ONLY the outdoor scenery: the
## level's "Outside" node meshes get render layer 2 and the sun's cull mask is layer 2, so nothing leaks indoors.
## Off during the early story chapters (dark garage).
##   world.day_night.force(phase)  (screenshots / tests; -1 = back to the clock)

const Story := preload("res://world/live/story_state.gd")
const DAYS := 30.0
const MIN_CYCLE := 90.0

var world: Node3D
var sky: ProceduralSkyMaterial
var env: Environment
var phase := 0.0
var forced := -1.0
var _lights: Array = []
var _level_ref: Node3D
var _last_day := -1.0
var _day_t := 0.0
var _sun: DirectionalLight3D
const SUN_LAYER := 2

const NIGHT_TOP := Color(0.02, 0.03, 0.08)
const NIGHT_HOR := Color(0.08, 0.08, 0.15)
const DUSK_TOP := Color(0.06, 0.09, 0.25)
const DUSK_HOR := Color(0.85, 0.42, 0.28)
const DAY_TOP := Color(0.22, 0.38, 0.7)
const DAY_HOR := Color(0.72, 0.74, 0.76)

func force(p: float) -> void:
	forced = p
	if p >= 0.0:
		phase = fposmod(p, 1.0)
		_apply()

## 0 = night, 1 = full day
func daylight() -> float:
	return clampf(sin(TAU * (phase - 0.5)) * 1.5 - 0.35, 0.0, 1.0)

func _target(s: Dictionary) -> float:
	var t: Variant = s.get("time")
	if not (t is Dictionary):
		return 0.0
	var d := float(t.get("elapsedDays", t.get("day", 0)))
	if d != _last_day:
		_last_day = d
		_day_t = 0.0
	var spd := float(t.get("speed", 1))
	var frac := clampf(_day_t * spd / 2.0, 0.0, 0.99)
	return fposmod((d + frac) / DAYS, 1.0)

func _process(dt: float) -> void:
	if sky == null:
		return
	_day_t += dt
	var s: Dictionary = Game.state
	if forced >= 0.0:
		phase = forced
	elif s.is_empty() or (Story.active(s) and Story.chapter(s) < 5):
		phase = move_toward(phase, 0.0, dt / MIN_CYCLE) if phase < 0.5 else fposmod(phase + dt / MIN_CYCLE, 1.0)
	else:
		var tgt := _target(s)
		var ahead := fposmod(tgt - phase, 1.0)
		if ahead < 0.5:
			phase = fposmod(phase + minf(ahead, dt / MIN_CYCLE * maxf(1.0, ahead * 20.0)), 1.0)
	_apply()

func _apply() -> void:
	if sky == null:
		return
	var day := daylight()
	var dusk := clampf(1.0 - absf(fposmod(phase + 0.5, 1.0) - 0.5) * 6.0, 0.0, 1.0)   # around phase 0
	var dawn := clampf(1.0 - absf(phase - 0.5) * 7.0, 0.0, 1.0)
	var top := NIGHT_TOP.lerp(DUSK_TOP, maxf(dusk, dawn * 0.8)).lerp(DAY_TOP, day)
	var hor := NIGHT_HOR.lerp(DUSK_HOR, dusk).lerp(Color(0.95, 0.6, 0.45), dawn * 0.7).lerp(DAY_HOR, day)
	sky.sky_top_color = top
	sky.sky_horizon_color = hor
	if env:
		env.ambient_light_energy = 0.07 + 0.09 * day
	if _sun == null and world:
		_sun = DirectionalLight3D.new()
		_sun.name = "Sun"
		_sun.light_cull_mask = SUN_LAYER
		_sun.shadow_enabled = false
		_sun.light_volumetric_fog_energy = 0.0
		_sun.light_color = Color(1.0, 0.93, 0.82)
		_sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
		world.add_child(_sun)
	if _sun:
		_sun.light_energy = day * 1.3
		_sun.visible = day > 0.01
	_update_window_lights(day)

func _update_window_lights(day: float) -> void:
	var lv: Node3D = world.get_level() if world and world.has_method("get_level") else null
	if lv != _level_ref:
		_level_ref = lv
		for l in _lights:
			if is_instance_valid(l):
				l.queue_free()
		_lights.clear()
		var outside: Node = lv.get_node_or_null("Outside") if lv else null
		if outside:
			for vi in outside.find_children("*", "VisualInstance3D", true, false):
				(vi as VisualInstance3D).layers |= SUN_LAYER
		if lv and lv.has_method("daylight_windows"):
			for w in lv.daylight_windows():
				var sp := SpotLight3D.new()
				sp.name = "Daylight"
				lv.add_child(sp)
				var pos: Vector3 = w.pos
				var tg: Vector3 = w.target
				sp.transform = Transform3D(Basis.looking_at(tg - pos, Vector3.UP), pos)
				sp.light_color = Color(0.9, 0.95, 1.0)
				sp.spot_range = pos.distance_to(tg) * 1.6
				sp.spot_angle = 48.0
				sp.spot_angle_attenuation = 1.2
				sp.light_volumetric_fog_energy = 1.6
				sp.shadow_enabled = false
				_lights.append(sp)
	for l in _lights:
		if is_instance_valid(l):
			(l as SpotLight3D).light_energy = day * 2.2
			(l as SpotLight3D).visible = day > 0.01
