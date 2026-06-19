extends CharacterBody3D

@export var planet_path: NodePath
@export var camera_path: NodePath            # the Camera3D that follows the top
@export var light_path: NodePath             # the DirectionalLight3D that follows the top
@export var radius: float = 5.0
@export var move_speed: float = 4.0          # units/sec along the surface
@export var turn_speed: float = 2.5          # radians/sec
@export var spin_visual_speed: float = 1080.0 # deg/sec, purely cosmetic
@export var camera_distance: float = 10.0    # how far the camera sits from the top
@export_range(10.0, 89.0) var camera_pitch_deg: float = 60.0 # 89 = straight overhead, lower = more behind-and-above

var planet_center: Vector3
var heading: Vector3 = Vector3.FORWARD       # tangent direction the top faces

@onready var mesh: Node3D = $TopMesh
@onready var camera: Camera3D = get_node_or_null(camera_path)
@onready var light: DirectionalLight3D = get_node_or_null(light_path)

func _ready() -> void:
	var planet := get_node(planet_path)
	planet_center = planet.global_position
	# derive the orbit radius from the actual planet so the top can't drift off the
	# surface: planet's world radius + the top's own radius (so it rests on top, not half-buried)
	var planet_radius := _sphere_world_radius(planet)
	if planet_radius > 0.0:
		radius = planet_radius + _sphere_world_radius(mesh)
	# snap onto the surface and make heading tangent to it
	var up := (global_position - planet_center).normalized()
	if up == Vector3.ZERO:
		up = Vector3.UP
	global_position = planet_center + up * radius
	heading = _project_tangent(heading, up)
	_update_camera(up)
	_update_light(up)

func _physics_process(delta: float) -> void:
	var up := (global_position - planet_center).normalized()

	# --- turn: rotate heading around the surface normal ---
	var turn := Input.get_axis("move_right", "move_left")
	heading = _project_tangent(heading.rotated(up, turn * turn_speed * delta), up)

	# --- move: rotate the position vector around the planet center ---
	var fwd := Input.get_axis("move_back", "move_forward")
	if fwd != 0.0:
		var axis := up.cross(heading).normalized()
		var angle := (fwd * move_speed * delta) / radius
		var p := (global_position - planet_center).rotated(axis, angle)
		global_position = planet_center + p.normalized() * radius
		up = (global_position - planet_center).normalized()
		heading = _project_tangent(heading, up)

	# --- orient the top: local up = surface normal, local -Z = heading ---
	global_transform.basis = Basis.looking_at(heading, up)

	# --- spin the visual mesh around its own up ---
	mesh.rotate_object_local(Vector3.UP, deg_to_rad(spin_visual_speed) * delta)

	_update_camera(up)
	_update_light(up)

func _update_camera(up: Vector3) -> void:
	# place the camera relative to the top: pitch tilts it from straight overhead (89 deg)
	# down toward a behind-and-above chase angle, pulling back along the heading as it lowers
	if camera == null:
		return
	var pitch := deg_to_rad(clampf(camera_pitch_deg, 10.0, 89.0))
	var offset_dir := up * sin(pitch) - heading * cos(pitch)
	camera.global_position = global_position + offset_dir * camera_distance
	camera.look_at(global_position, up)

func _update_light(up: Vector3) -> void:
	# directional light position is ignored; only its -Z (the light direction) matters.
	# aim it down the surface normal, tilted slightly along heading for soft shading.
	if light == null:
		return
	light.global_position = global_position + up * 10.0 - heading * 4.0
	light.look_at(global_position, heading)

func _sphere_world_radius(node: Node) -> float:
	# read a SphereMesh's radius and apply the node's world scale; 0.0 if it isn't a sphere
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is SphereMesh:
		var local_r: float = ((node as MeshInstance3D).mesh as SphereMesh).radius
		return local_r * (node as Node3D).global_transform.basis.get_scale().x
	return 0.0

func _project_tangent(v: Vector3, up: Vector3) -> Vector3:
	# remove the component along 'up' so the vector stays on the tangent plane
	return (v - up * v.dot(up)).normalized()
