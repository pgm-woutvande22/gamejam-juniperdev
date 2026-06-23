extends CanvasLayer

# Top-left HUD: a countdown to the next wave, with the current wave number below it.
# Reads the live wave state straight off the Spawner (see scripts/spawner.gd), found via
# the "spawner" group so no path wiring is needed. Set spawner_path to override.

@export var spawner_path: NodePath

@onready var timer_label: Label = $VBox/TimerLabel
@onready var wave_label: Label = $VBox/WaveLabel

var spawner: Node

func _ready() -> void:
	_resolve_spawner()

func _process(_delta: float) -> void:
	if spawner == null or not is_instance_valid(spawner):
		_resolve_spawner()
		if spawner == null:
			return

	var wave := int(spawner.get("wave"))
	var wave_timer := float(spawner.get("wave_timer"))
	var wave_duration := float(spawner.get("wave_duration"))

	if wave_duration <= 0.0:
		timer_label.text = "Next wave: --"      # wave system disabled on the spawner
	else:
		timer_label.text = "Next wave: %ds" % int(ceil(maxf(wave_timer, 0.0)))
	wave_label.text = "Wave %d" % maxi(wave, 0)

func _resolve_spawner() -> void:
	spawner = get_node_or_null(spawner_path)
	if spawner == null:
		spawner = get_tree().get_first_node_in_group("spawner")
