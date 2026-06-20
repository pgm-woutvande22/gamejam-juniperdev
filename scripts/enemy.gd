extends CharacterBody3D

# An enemy that lives on the planet surface, using the same position-vector rotation
# the Top uses (see scripts/top.gd). "Down" is always toward the planet center; the
# enemy stays glued to the surface and chases the player along great circles.

signal died(enemy: Node, score: int)   # emitted on death; connect in the level for score/SFX

# Scene wiring (per instance) — these stay on the node, not the type, because they
# point at other nodes in this specific level.
@export var planet_path: NodePath
@export var target_path: NodePath              # who to chase (the Top); empty = just patrol

# Assign an EnemyType .tres to define this enemy's stats + look. When set, it overrides
# every fallback value below in _ready. Leave empty to tune a one-off enemy by hand.
@export var type: EnemyType

# Fallback stats, used when no `type` is assigned (and as the live values once a type
# is applied). See scripts/enemy_type.gd for what each one means.
@export_group("Fallback stats (overridden by type)")
@export var radius: float = 10.0               # auto-derived from the planet in _ready
@export var move_speed: float = 18.0
@export var turn_speed: float = 4.0
@export var chase_range: float = 60.0
@export var separation_radius: float = 6.0
@export var separation_strength: float = 1.5
@export var kill_threshold: float = 45.0
@export var max_health: float = 50.0
@export var hit_distance: float = 4.0
@export var hit_cooldown: float = 0.4
@export var score: int = 100
@export var surface_offset: float = 0.0        # extra lift above the auto "rest on surface" height
@export var face_player: bool = true           # flip the sprite horizontally to look toward the Top

var planet_center: Vector3
var heading: Vector3 = Vector3.FORWARD         # tangent direction the enemy faces
var health: float = 0.0
var hit_cooldown_left: float = 0.0

@onready var sprite: Sprite3D = get_node_or_null("EnemyMesh")
@onready var target: Node3D = get_node_or_null(target_path)

func _ready() -> void:
	_apply_type()
	if sprite != null:
		# when we roll the sprite to face the player we drive its full orientation, so the engine's
		# auto-billboard must be off (it would fight our roll). otherwise let it auto-billboard.
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED if face_player else BaseMaterial3D.BILLBOARD_ENABLED
	var planet := get_node(planet_path)
	planet_center = planet.global_position
	# orbit radius = planet surface; the billboard sprite is centered on the surface point
	var planet_radius := _sphere_world_radius(planet)
	if planet_radius > 0.0:
		radius = planet_radius
	# snap onto the surface and make the heading tangent to it
	var up := (global_position - planet_center).normalized()
	if up == Vector3.ZERO:
		up = Vector3.UP
	global_position = planet_center + up * radius
	heading = _project_tangent(heading, up)
	health = max_health
	_place_sprite()
	add_to_group("enemies")   # so enemies can find each other for anti-clump separation

func _physics_process(delta: float) -> void:
	var up := (global_position - planet_center).normalized()

	if hit_cooldown_left > 0.0:
		hit_cooldown_left -= delta

	# --- contact with the player: kill on a fast enough hit, otherwise bounce + chip ---
	if target != null and hit_cooldown_left <= 0.0:
		if global_position.distance_to(target.global_position) <= hit_distance:
			_resolve_contact()

	# --- decide which tangent direction we want to face ---
	var desired := heading
	var chasing := false
	if target != null:
		var to_target := (target.global_position - planet_center).normalized()
		var cos_a := clampf(up.dot(to_target), -1.0, 1.0)
		var dist := acos(cos_a) * radius                 # surface distance to the player
		if dist <= chase_range:
			var tangent := to_target - up * cos_a        # direction toward the player along the surface
			if tangent.length() > 0.0001:
				desired = tangent.normalized()
				chasing = true

	# --- anti-clump: steer away from nearby enemies, blended in with the chase direction ---
	var sep := _separation(up)
	if sep.length() > 0.0001:
		desired = (desired + sep.normalized() * separation_strength).normalized()
	elif not chasing:
		return                                            # nothing to chase and no crowding: idle

	# --- ease the heading toward the desired direction at a capped turn rate ---
	var angle_to := heading.angle_to(desired)
	if angle_to > 0.0001:
		var step := minf(angle_to, turn_speed * delta)
		var axis := heading.cross(desired).normalized()
		if axis.length() > 0.0001:
			heading = _project_tangent(heading.rotated(axis, step), up)

	# --- move along the surface by rotating the position vector around the planet center ---
	var move_axis := up.cross(heading).normalized()
	var travel := (move_speed * delta) / radius
	var p := (global_position - planet_center).rotated(move_axis, travel)
	global_position = planet_center + p.normalized() * radius
	up = (global_position - planet_center).normalized()
	heading = _project_tangent(heading, up)              # keep heading tangent after moving

	# --- orient: local up = surface normal, local -Z = heading. the sprite billboards to
	#     the camera on its own, so this only keeps the node's frame consistent for collision ---
	global_transform.basis = Basis.looking_at(heading, up)

	# --- face the player: roll the billboard around the view axis so the sprite's BOTTOM edge
	#     points at the Top, wherever the player is on the planet ---
	if face_player and sprite != null and target != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_orient_sprite_to_player(cam)

func _apply_type() -> void:
	# copy the assigned type's stats into our live values. no-op if no type is set,
	# so a hand-tuned enemy keeps its inspector values.
	if type == null:
		return
	move_speed = type.move_speed
	turn_speed = type.turn_speed
	chase_range = type.chase_range
	separation_radius = type.separation_radius
	separation_strength = type.separation_strength
	kill_threshold = type.kill_threshold
	max_health = type.max_health
	hit_distance = type.hit_distance
	hit_cooldown = type.hit_cooldown
	score = type.score
	# apply the look to the billboard sprite
	if sprite != null:
		if type.texture != null:
			sprite.texture = type.texture
		# tint (rgb) and transparency are separate knobs; force alpha solid so opacity owns it
		sprite.modulate = Color(type.modulate.r, type.modulate.g, type.modulate.b, 1.0)
		sprite.transparency = clampf(1.0 - type.opacity, 0.0, 1.0)
		# size
		sprite.pixel_size = type.pixel_size
		sprite.scale = Vector3.ONE * type.sprite_scale
		surface_offset = type.surface_offset
		face_player = type.face_player

func _place_sprite() -> void:
	# lift the sprite along the surface normal so its BASE rests on the surface, not its center.
	# a billboard rotates to face the camera, so a center-on-surface sprite tilts and clips into
	# the planet. raising it by half its world height keeps the whole quad above the surface.
	# (local +Y is the surface normal — the node's basis is set to looking_at(heading, up).)
	if sprite == null:
		return
	var half_h := 0.0
	if sprite.texture != null:
		half_h = sprite.texture.get_height() * sprite.pixel_size * sprite.scale.y * 0.5
	sprite.position = Vector3.UP * (half_h + surface_offset)

func _separation(up: Vector3) -> Vector3:
	# sum a push away from every other enemy within separation_radius, weighted by how close
	# they are (closer = stronger), then flatten it onto the tangent plane. returns a raw
	# (un-normalized) vector so the caller can normalize/weight it.
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector3 = global_position - (other as Node3D).global_position
		var d := away.length()
		if d > 0.0001 and d < separation_radius:
			push += away.normalized() * (1.0 - d / separation_radius)
	return push - up * push.dot(up)   # project onto the tangent plane (keep magnitude)

func _orient_sprite_to_player(cam: Camera3D) -> void:
	# build the sprite's orientation by hand: face the camera (so it stays a flat billboard) AND
	# roll it so the texture's bottom (-Y) points toward the Top on screen.
	var pos := sprite.global_position
	var z_axis := (cam.global_position - pos).normalized()        # sprite front (+Z) faces the camera
	if z_axis == Vector3.ZERO:
		return
	# direction to the player, flattened into the screen plane (perpendicular to the view axis)
	var to_player := target.global_position - pos
	var screen_dir := to_player - z_axis * to_player.dot(z_axis)
	if screen_dir.length() < 0.0001:
		return
	screen_dir = screen_dir.normalized()
	var y_axis := -screen_dir                                     # +Y is up, so -Y (bottom) faces the player
	var x_axis := y_axis.cross(z_axis).normalized()
	y_axis = z_axis.cross(x_axis).normalized()                    # re-orthonormalize
	var b := Basis(x_axis, y_axis, z_axis).scaled(sprite.scale)   # keep the sprite's scale
	sprite.global_transform = Transform3D(b, pos)

func _resolve_contact() -> void:
	# read how fast the player is moving along the surface (dash-aware, see top.gd)
	var speed := 0.0
	if target.has_method("get_surface_speed"):
		speed = target.get_surface_speed()
	hit_cooldown_left = hit_cooldown

	if speed >= kill_threshold:
		_die()
		return

	# sub-threshold: the enemy takes the player's speed as damage and shoves the player back
	health -= speed
	if target.has_method("bounce_off"):
		target.bounce_off(global_position)
	if health <= 0.0:
		_die()

func _die() -> void:
	# TODO: spawn a death effect / play a sound here
	died.emit(self, score)
	queue_free()

func _sphere_world_radius(node: Node) -> float:
	# read a SphereMesh's radius and apply the node's world scale; 0.0 if it isn't a sphere
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is SphereMesh:
		var local_r: float = ((node as MeshInstance3D).mesh as SphereMesh).radius
		return local_r * (node as Node3D).global_transform.basis.get_scale().x
	return 0.0

func _project_tangent(v: Vector3, up: Vector3) -> Vector3:
	# remove the component along 'up' so the vector stays on the tangent plane
	return (v - up * v.dot(up)).normalized()
