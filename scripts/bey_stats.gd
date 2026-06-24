extends CanvasLayer

@export var bey: CharacterBody3D
@export var spawner: Node3D
@onready var RPMLabel: Label = $RPM
@onready var SpeedLabel: Label = $Speed
@onready var ScoreLabel: Label = $Score

var total_score: int

func _ready() -> void:
	if spawner.has_signal("enemy_died"):
		spawner.enemy_died.connect(_add_to_score)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if bey.has_method("get_current_spin_speed"):
		RPMLabel.text = "RPM: " + str(bey.get_current_spin_speed())
	if bey.has_method("get_surface_speed"):
		SpeedLabel.text = "Speed: " + str(snapped(bey.get_surface_speed(), 0))
	ScoreLabel.text = "Score: " + str(total_score)

func _add_to_score(enemy: Node3D, score: int) -> void:
	total_score += score
