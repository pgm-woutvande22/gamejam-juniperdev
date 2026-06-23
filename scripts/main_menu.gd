extends Control

# Title-screen menu. Set as the project's main scene so it loads on launch;
# Play swaps in the gameplay level, Quit exits.

@export_file("*.tscn") var level_scene: String = "res://scences/level.tscn"
@export var spin_speed_deg: float = 6.0   # how fast the background planet rotates (deg/sec)

@export_group("Floating crabs")
@export var crab_texture: Texture2D                 # defaults to assets/Crab.png if left empty
@export var crab_count: int = 8                     # how many crabs drift around the menu
@export var crab_drift_speed: float = 40.0          # pixels/sec the crabs travel across screen
@export var crab_spin_speed_deg: float = 30.0       # max rotation speed (deg/sec, randomized per crab)
@export var crab_scale_min: float = 0.4
@export var crab_scale_max: float = 0.9

@onready var play_button: Button = $CenterContainer/VBoxContainer/PlayButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton
@onready var planet: Node3D = $Planet
@onready var cloud_layer: Node3D = $CloudLayer
@onready var crab_layer: Node2D = $CrabLayer

var _crabs: Array[Sprite2D] = []


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	play_button.grab_focus()   # so the menu is keyboard/controller navigable out of the box
	_spawn_crabs()


func _process(delta: float) -> void:
	# slow idle spin so the menu feels alive; clouds drift a touch faster for parallax
	var step := deg_to_rad(spin_speed_deg) * delta
	planet.rotate_y(step)
	cloud_layer.rotate_y(step * 1.15)
	_update_crabs(delta)


func _spawn_crabs() -> void:
	if crab_texture == null:
		crab_texture = load("res://assets/Crab.png")
	var screen := get_viewport_rect().size
	for i in crab_count:
		var crab := Sprite2D.new()
		crab.texture = crab_texture
		crab.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # keep pixel art crisp
		crab.scale = Vector2.ONE * randf_range(crab_scale_min, crab_scale_max)
		crab.position = Vector2(randf() * screen.x, randf() * screen.y)
		crab.rotation = randf() * TAU
		# per-crab motion stored as metadata: a drift direction and a spin rate
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		crab.set_meta("vel", dir * crab_drift_speed * randf_range(0.5, 1.0))
		crab.set_meta("spin", deg_to_rad(randf_range(-crab_spin_speed_deg, crab_spin_speed_deg)))
		crab_layer.add_child(crab)
		_crabs.append(crab)


func _update_crabs(delta: float) -> void:
	var screen := get_viewport_rect().size
	var margin := 96.0   # wrap a bit off-screen so crabs don't pop at the edge
	for crab in _crabs:
		crab.position += crab.get_meta("vel") as Vector2 * delta
		crab.rotation += crab.get_meta("spin") as float * delta
		# wrap around screen edges for an endless drift
		if crab.position.x < -margin:
			crab.position.x = screen.x + margin
		elif crab.position.x > screen.x + margin:
			crab.position.x = -margin
		if crab.position.y < -margin:
			crab.position.y = screen.y + margin
		elif crab.position.y > screen.y + margin:
			crab.position.y = -margin


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(level_scene)


func _on_quit_pressed() -> void:
	get_tree().quit()
