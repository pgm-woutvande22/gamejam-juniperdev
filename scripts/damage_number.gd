extends Label3D

# Floating combat text: a number that pops above an enemy when it's hit, drifts up the screen,
# and fades out. Spawned by enemy.gd on contact (see _spawn_damage_number). It's a Label3D so it
# billboards to the camera by itself — no screen-projection needed. Self-animating and
# self-freeing: set amount / is_crit / spawn_position BEFORE add_child, then it runs in _ready.

@export var lifetime: float = 0.7                    # seconds before it finishes fading and frees itself
@export var float_distance: float = 8.0              # world units it drifts (along the camera's up) while alive
@export var spread: float = 2.0                      # random horizontal jitter so stacked hits don't overlap
@export var normal_color: Color = Color(1, 1, 1)     # tint for a regular hit
@export var crit_color: Color = Color(1, 0.85, 0.2)  # tint for a killing blow
@export var crit_scale: float = 1.6                  # size multiplier for a killing blow

# --- set these before add_child ---
var amount: float = 0.0
var is_crit: bool = false
var spawn_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	top_level = true                                 # ignore the parent's transform; spawn_position is world-space
	text = str(roundi(amount))
	modulate = crit_color if is_crit else normal_color
	if is_crit:
		scale *= crit_scale

	# drift "up the screen" using the camera's own axes, so it reads as rising regardless of view angle
	var rise := Vector3.UP
	var side := Vector3.RIGHT
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		rise = cam.global_transform.basis.y
		side = cam.global_transform.basis.x
	# stagger the start sideways a touch so multiple numbers from one cluster don't stack exactly
	var start_pos := spawn_position + side * randf_range(-spread, spread)
	global_position = start_pos
	var end_pos := start_pos + rise * float_distance

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "global_position", end_pos, lifetime)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# fade the fill AND the outline together — otherwise the (black) outline lingers as the
	# fill disappears, so the number looks like it's fading to black instead of vanishing
	tween.tween_property(self, "modulate:a", 0.0, lifetime).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "outline_modulate:a", 0.0, lifetime).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)
