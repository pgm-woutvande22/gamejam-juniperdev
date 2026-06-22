extends Node3D

# Spawns enemies onto the planet surface over time. Drop this node into a level, wire its
# planet_path / target_path, and assign enemy_scene + one or more EnemyType resources. It picks
# random points on the sphere (kept a safe surface-distance away from the player), instances
# enemy.tscn there, and lets the enemy snap itself onto the surface in its own _ready
# (see scripts/enemy.gd) — so this spawner stays a thin "where + when + which type" layer.

signal enemy_spawned(enemy: Node)
signal enemy_died(enemy: Node, score: int)   # re-emitted from each spawned enemy for the level to total up

# --- wiring (point at this level's nodes) ---
@export var planet_path: NodePath
@export var target_path: NodePath               # the Top; passed through to each enemy so it chases
@export var enemy_scene: PackedScene            # res://scences/enemy.tscn

# --- which enemies ---
# Assign one or more EnemyType .tres files. Each spawn picks one at random (uniform). Leave empty
# to use whatever the enemy scene's own `type`/fallback stats already define.
@export var enemy_types: Array[EnemyType] = []

# --- when ---
@export var autostart: bool = true              # begin spawning on _ready
@export var initial_spawn: int = 0              # enemies dropped immediately on start
@export var spawn_interval: float = 2.0         # seconds between spawns at the start
@export var spawn_interval_min: float = 0.5     # interval floor as difficulty ramps up
@export var ramp_time: float = 90.0             # seconds over which interval eases from max -> min (0 = no ramp)

# --- how many ---
@export var max_alive: int = 30                 # stop spawning while this many enemies exist; 0 = unlimited

# --- where ---
@export var min_spawn_distance: float = 30.0    # min surface distance from the player (so enemies don't pop on top of you)
@export var spawn_behind_player: bool = false   # bias spawns to the far side of the planet from the player's heading
@export var max_placement_tries: int = 16       # attempts to find a valid point before giving up this tick

var planet_center: Vector3
var radius: float = 100.0
var time_alive: float = 0.0
var spawn_timer: float = 0.0
var running: bool = false

@onready var target: Node3D = get_node_or_null(target_path)
@onready var planet: Node3D = get_node_or_null(planet_path)

func _ready() -> void:
	if planet != null:
		planet_center = planet.global_position
		var r := _sphere_world_radius(planet)
		if r > 0.0:
			radius = r
	else:
		push_warning("Spawner: planet_path did not resolve to a node.")
	if autostart:
		start()

func start() -> void:
	running = true
	for i in initial_spawn:
		spawn_one()
	spawn_timer = current_interval()

func stop() -> void:
	running = false

func _physics_process(delta: float) -> void:
	if not running:
		return
	time_alive += delta
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer += current_interval()
		if _can_spawn():
			spawn_one()

func current_interval() -> float:
	# ease the gap between spawns from spawn_interval down to spawn_interval_min over ramp_time
	if ramp_time <= 0.0:
		return spawn_interval
	var t := clampf(time_alive / ramp_time, 0.0, 1.0)
	return lerpf(spawn_interval, spawn_interval_min, t)

func _can_spawn() -> bool:
	if max_alive <= 0:
		return true
	return get_tree().get_nodes_in_group("enemies").size() < max_alive

# Instance one enemy at a valid surface point. Returns the enemy, or null if no scene is set.
func spawn_one() -> Node:
	if enemy_scene == null:
		push_warning("Spawner: enemy_scene is not assigned.")
		return null
	var enemy := enemy_scene.instantiate()
	# wire the per-instance references before _ready runs (the enemy reads these in its _ready).
	# pass ABSOLUTE paths: the enemy becomes our child, so its scene's relative "../Planet" would
	# resolve against us, not the level — give it the real node paths instead.
	if planet != null:
		enemy.planet_path = planet.get_path()
	if target != null:
		enemy.target_path = target.get_path()
	if not enemy_types.is_empty():
		enemy.type = enemy_types[randi() % enemy_types.size()]
	# place it on the surface BEFORE add_child: add_child runs the enemy's _ready, which snaps it
	# to the surface from its current position — so the position must be set first. to_local maps
	# the world point into our local frame (the enemy is parented to us).
	enemy.position = to_local(planet_center + _pick_spawn_dir() * radius)
	add_child(enemy)
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
	enemy_spawned.emit(enemy)
	return enemy

func _pick_spawn_dir() -> Vector3:
	# random unit direction on the sphere, retried until it clears min_spawn_distance from the player
	var player_up := Vector3.ZERO
	if target != null:
		player_up = (target.global_position - planet_center).normalized()
	for _i in maxi(max_placement_tries, 1):
		var dir := _random_unit_vector()
		if spawn_behind_player and target != null:
			# fold the sample onto the hemisphere away from the player
			if dir.dot(player_up) > 0.0:
				dir = -dir
		if player_up == Vector3.ZERO:
			return dir
		var surface_dist := acos(clampf(dir.dot(player_up), -1.0, 1.0)) * radius
		if surface_dist >= min_spawn_distance:
			return dir
	# fell through: just put it on the exact opposite side of the player
	return -player_up if player_up != Vector3.ZERO else _random_unit_vector()

func _random_unit_vector() -> Vector3:
	# uniform point on the unit sphere (z uniform, angle uniform) — no clustering at the poles
	var z := randf_range(-1.0, 1.0)
	var a := randf_range(0.0, TAU)
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(a), z, r * sin(a))

func _on_enemy_died(enemy: Node, score: int) -> void:
	enemy_died.emit(enemy, score)

func _sphere_world_radius(node: Node) -> float:
	# read a SphereMesh's radius and apply the node's world scale; 0.0 if it isn't a sphere
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is SphereMesh:
		var local_r: float = ((node as MeshInstance3D).mesh as SphereMesh).radius
		return local_r * (node as Node3D).global_transform.basis.get_scale().x
	return 0.0
