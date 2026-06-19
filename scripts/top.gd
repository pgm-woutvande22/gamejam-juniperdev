extends CharacterBody3D

@export var planet_path: NodePath
@export var camera_path: NodePath            # the Camera3D that follows the top
@export var light_path: NodePath             # the DirectionalLight3D that follows the top
@export var radius: float = 5.0
@export var move_speed: float = 4.0          # units/sec along the surface (also caps mouse-drag speed)
@export var turn_speed: float = 1.5          # radians/sec (keyboard turning)
@export var drag_strength: float = 8.0       # mouse-drag: how hard the top is pulled to the cursor (higher = snappier)
@export var accel_speed: float = 12.0        # how quickly the top ramps up to drag speed (higher = snappier)
@export var friction: float = 2.0            # how quickly it coasts to a stop when you let go (lower = longer glide)
@export var spin_visual_speed: float = 1080.0 # deg/sec, purely cosmetic
@export var camera_distance: float = 10.0    # how far the camera sits from the top
@export_range(10.0, 89.0) var camera_pitch_deg: float = 60.0 # 89 = straight overhead, lower = more behind-and-above

var planet_center: Vector3
var planet_radius: float = 0.0               # planet's surface radius, used for cursor raycasts
var heading: Vector3 = Vector3.FORWARD       # tangent direction the top faces
var surface_vel: Vector3 = Vector3.ZERO      # current velocity as a tangent vector (units/sec along surface)
var view_dir: Vector3 = Vector3.FORWARD      # camera's stable "behind" direction; parallel-transported as
											 # the top moves so the view doesn't spin when you change heading

@onready var mesh: Node3D = $TopMesh
@onready var camera: Camera3D = get_node_or_null(camera_path)
@onready var light: DirectionalLight3D = get_node_or_null(light_path)

func _ready() -> void:
	var planet := get_node(planet_path)
	planet_center = planet.global_position
	# derive the orbit radius from the actual planet so the top can't drift off the
	# surface: planet's world radius + the top's own radius (so it rests on top, not half-buried)
	planet_radius = _sphere_world_radius(planet)
	if planet_radius > 0.0:
		radius = planet_radius + _sphere_world_radius(mesh)
	# snap onto the surface and make heading tangent to it
	var up := (global_position - planet_center).normalized()
	if up == Vector3.ZERO:
		up = Vector3.UP
	global_position = planet_center + up * radius
	heading = _project_tangent(heading, up)
	view_dir = heading
	_update_camera(up)
	_update_light(up)

func _physics_process(delta: float) -> void:
	var up := (global_position - planet_center).normalized()

	# keep the carried momentum tangent to the surface as the top travels
	surface_vel -= up * surface_vel.dot(up)

	# --- decide the velocity we want this frame from input ---
	var target_vel := Vector3.ZERO
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var target = _cursor_planet_point()
		if target != null:
			var point: Vector3 = target
			var to_dir := (point - planet_center).normalized()
			var cos_a := clampf(up.dot(to_dir), -1.0, 1.0)
			var dist := acos(cos_a) * radius          # surface distance to the cursor
			var dir := to_dir - up * cos_a            # tangent pointing toward the cursor
			if dir.length() > 0.0001:
				# speed scales with distance (eases off as the cursor nears the top), capped
				target_vel = dir.normalized() * min(dist * drag_strength, move_speed)
	else:
		# keyboard fallback when not dragging
		var turn := Input.get_axis("move_right", "move_left")
		heading = _project_tangent(heading.rotated(up, turn * turn_speed * delta), up)
		var fwd := Input.get_axis("move_back", "move_forward")
		if fwd != 0.0:
			target_vel = heading * (fwd * move_speed)

	# --- ease velocity toward the target: accelerate while driven, coast when released ---
	var rate := accel_speed if target_vel.length() > 0.01 else friction
	surface_vel = surface_vel.lerp(target_vel, clampf(rate * delta, 0.0, 1.0))

	# --- move along the surface by the current velocity, carrying the velocity with us ---
	var speed := surface_vel.length()
	if speed > 0.001:
		var move_axis := up.cross(surface_vel).normalized()
		var angle := (speed * delta) / radius
		var p := (global_position - planet_center).rotated(move_axis, angle)
		global_position = planet_center + p.normalized() * radius
		up = (global_position - planet_center).normalized()
		surface_vel = surface_vel.rotated(move_axis, angle)   # parallel-transport along the path
		heading = surface_vel.normalized()

	# --- orient the top: local up = surface normal, local -Z = heading ---
	global_transform.basis = Basis.looking_at(heading, up)

	# --- spin the visual mesh around its own up ---
	mesh.rotate_object_local(Vector3.UP, deg_to_rad(spin_visual_speed) * delta)

	_update_camera(up)   # follow the top every frame, recentering immediately (no lag = no spiral)
	_update_light(up)

func _update_camera(up: Vector3) -> void:
	# keep the top centered every frame, but recenter IMMEDIATELY (no smoothing). a lagging camera
	# rotates its look-at angle toward the lag direction, which curves the drag target and spirals.
	# snapping to the top each frame keeps the view frame consistent, so dragging tracks straight.
	# view_dir (the "behind" direction) is parallel-transported, not tied to heading, so changing
	# drag direction doesn't spin the view either.
	if camera == null:
		return
	view_dir = _project_tangent(view_dir, up)
	var pitch := deg_to_rad(clampf(camera_pitch_deg, 10.0, 89.0))
	var offset_dir := up * sin(pitch) - view_dir * cos(pitch)
	camera.global_position = global_position + offset_dir * camera_distance
	camera.look_at(global_position, up)

func _update_light(up: Vector3) -> void:
	# directional light position is ignored; only its -Z (the light direction) matters.
	# aim it down the surface normal, tilted along the stable view_dir (not heading) so the
	# shading doesn't swing around as you change drag direction.
	if light == null:
		return
	light.global_position = global_position + up * 10.0 - view_dir * 4.0
	light.look_at(global_position, view_dir)

func _sphere_world_radius(node: Node) -> float:
	# read a SphereMesh's radius and apply the node's world scale; 0.0 if it isn't a sphere
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is SphereMesh:
		var local_r: float = ((node as MeshInstance3D).mesh as SphereMesh).radius
		return local_r * (node as Node3D).global_transform.basis.get_scale().x
	return 0.0

func _cursor_planet_point() -> Variant:
	# ray from the camera through the mouse, intersected with the planet sphere; null on a miss.
	# the planet is a perfect sphere, so this is exact — no collider needed.
	if camera == null:
		return null
	var mouse := camera.get_viewport().get_mouse_position()
	var o := camera.project_ray_origin(mouse)
	var d := camera.project_ray_normal(mouse)   # unit length, so a = 1 in the quadratic below
	var oc := o - planet_center
	var b := 2.0 * d.dot(oc)
	var c := oc.dot(oc) - planet_radius * planet_radius
	var disc := b * b - 4.0 * c
	if disc < 0.0:
		return null                             # cursor isn't over the planet
	var s := sqrt(disc)
	var t := (-b - s) * 0.5                      # nearest intersection
	if t < 0.0:
		t = (-b + s) * 0.5                       # camera inside the sphere: take the far hit
	if t < 0.0:
		return null
	return o + d * t

func _project_tangent(v: Vector3, up: Vector3) -> Vector3:
	# remove the component along 'up' so the vector stays on the tangent plane
	return (v - up * v.dot(up)).normalized()
