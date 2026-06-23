extends CanvasLayer

@export var bey: CharacterBody3D
@onready var RPMLabel: Label = $RPM
@onready var SpeedLabel: Label = $Speed

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if bey.has_method("get_current_spin_speed"):
		RPMLabel.text = "RPM: " + str(bey.get_current_spin_speed())
	if bey.has_method("get_surface_speed"):
		SpeedLabel.text = "Speed: " + str(snapped(bey.get_surface_speed(), 0)) 
