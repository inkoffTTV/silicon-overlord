extends Node
## Flickering light (dying fluorescent tube / old bulb). Drives a Light3D and, optionally,
## an emissive StandardMaterial3D so the tube and its light blink together.

@export var light: Light3D
@export var material: StandardMaterial3D
@export var base_energy := 1.0
@export var base_emission := 4.0
## 0 = steady with a rare stutter, 1 = constantly unstable
@export var instability := 0.25
@export var buzz := 0.04

var _t := 0.0
var _next := 1.5
var _burst := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	if light:
		base_energy = light.light_energy

func _process(delta: float) -> void:
	_t += delta
	var k := 1.0 - buzz * (0.5 + 0.5 * sin(_t * 120.0 * TAU / 60.0))
	if _burst > 0.0:
		_burst -= delta
		k *= 0.15 if _rng.randf() < 0.5 else 1.0
	elif _t > _next:
		_t = 0.0
		_next = _rng.randf_range(0.6, 6.0) * (1.2 - instability)
		_burst = _rng.randf_range(0.05, 0.45)
	if light:
		light.light_energy = base_energy * k
	if material:
		material.emission_energy_multiplier = base_emission * k
