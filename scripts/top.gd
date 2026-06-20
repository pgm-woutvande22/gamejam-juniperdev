extends CharacterBody3D

@export var planet_path: NodePath
@export var camera_path: NodePath            # the Camera3D that follows the top
@export var light_path: NodePath             # the DirectionalLight3D that follows the top
@export var radius: float = 5.0
@export var move_speed: float = 4.0          # top speed in units/sec along the surface
@export var turn_speed: float = 1.5          # radians/sec (keyboard turning)
@export var full_speed_distance: float = 6.0 # cursor distance (surface units) at which you hit top speed; closer = slower
@export var accel_speed: float = 8.0         # acceleration (units/sec^2): caps how fast speed AND direction can change; lower = more elastic
@export var friction: float = 2.0            # how quickly it coasts to a stop when you let go (lower = longer glide)
@export var spin_visual_speed: float = 1080.0 # deg/sec, purely cosmetic
@export var dash_distance: float = 12.0      # max surface distance a single dash covers
@export var dash_duration: float = 0.18      # how long the dash burst lasts (lower = snappier)
@export var dash_cooldown: float = 0.6       # min time between dashes
@export var dash_particles_path: NodePath    # optional GPUParticles3D trail dropped behind the top while dashing
@export var dash_colors: Array[Color] = []   # palette tinted into the trail per dash; empty = random hue
@export var dash_indicator_path: NodePath    # optional flat ring (PlaneMesh + dash_indicator.gdshader) showing cooldown
@export var camera_distance: float = 10.0    # how far the camera sits from the top
@export_range(10.0, 89.0) var camera_pitch_deg: float = 60.0 # 89 = straight overhead, lower = more behind-and-above

var planet_center: Vector3
var planet_radius: float = 0.0               # planet's surface radius, used for cursor raycasts
var heading: Vector3 = Vector3.FORWARD       # tangent direction the top faces
var surface_vel: Vector3 = Vector3.ZERO      # current velocity as a tangent vector (units/sec along surface)
var view_dir: Vector3 = Vector3.FORWARD      # camera's stable "behind" direction; parallel-transported as
											 # the top moves so the view doesn't spin when you change heading
var dash_time_left: float = 0.0              # >0 while a dash is in progress
var dash_cooldown_left: float = 0.0          # >0 while dash is recharging
var dash_axis: Vector3 = Vector3.ZERO        # fixed great-circle axis the active dash rotates around
var dash_angular_speed: float = 0.0          # radians/sec the active dash rotates the position vector
var prev_rmb: bool = false                   # last frame's right-mouse state, for edge detection

@onready var mesh: Node3D = $TopMesh
@onready var camera: Camera3D = get_node_or_null(camera_path)
@onready var light: DirectionalLight3D = get_node_or_null(light_path)
@onready var dash_particles: GPUParticles3D = get_node_or_null(dash_particles_path)
@onready var dash_indicator: MeshInstance3D = get_node_or_null(dash_indicator_path)

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
	_setup_dash_colors()
	_update_camera(up)
	_update_light(up)

func _physics_process(delta: float) -> void:
	var up := (global_position - planet_center).normalized()

	# keep the carried momentum tangent to the surface as the top travels
	surface_vel -= up * surface_vel.dot(up)

	if dash_cooldown_left > 0.0:
		dash_cooldown_left -= delta
	_update_dash_indicator()

	# --- right click: start a dash toward the cursor (quick burst, not affected by friction/accel) ---
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if rmb and not prev_rmb and dash_time_left <= 0.0 and dash_cooldown_left <= 0.0:
		_start_dash(up)
	prev_rmb = rmb

	# --- while dashing, override normal movement: rotate along the fixed great-circle axis ---
	if dash_time_left > 0.0:
		var step := minf(dash_time_left, delta)
		dash_time_left -= delta
		var angle := dash_angular_speed * step
		var p := (global_position - planet_center).rotated(dash_axis, angle)
		global_position = planet_center + p.normalized() * radius
		up = (global_position - planet_center).normalized()
		# carry momentum out of the dash so it eases back into normal movement
		heading = _project_tangent(dash_axis.cross(up), up)
		surface_vel = heading * move_speed
		global_transform.basis = Basis.looking_at(heading, up)
		mesh.rotate_object_local(Vector3.UP, deg_to_rad(spin_visual_speed) * delta)
		_set_trail(true)   # always trail while dashing
		_update_camera(up)
		_update_light(up)
		return

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
				# speed ramps linearly from 0 (cursor on the top) to move_speed at full_speed_distance
				var t := clampf(dist / maxf(full_speed_distance, 0.001), 0.0, 1.0)
				target_vel = dir.normalized() * (move_speed * t)
	else:
		# keyboard fallback when not dragging
		var turn := Input.get_axis("move_right", "move_left")
		heading = _project_tangent(heading.rotated(up, turn * turn_speed * delta), up)
		var fwd := Input.get_axis("move_back", "move_forward")
		if fwd != 0.0:
			target_vel = heading * (fwd * move_speed)

	# --- ease velocity toward the target at a capped rate, so the top can't change speed OR
	#     direction instantly: it must decelerate out of its current heading and accelerate into
	#     the new one, giving an elastic turn. coast to a stop with friction when released ---
	if target_vel.length() > 0.01:
		var dv := target_vel - surface_vel
		var max_step := accel_speed * delta
		if dv.length() > max_step:
			surface_vel += dv * (max_step / dv.length())
		else:
			surface_vel = target_vel
	else:
		surface_vel = surface_vel.lerp(Vector3.ZERO, clampf(friction * delta, 0.0, 1.0))

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

	# --- trail is dash-only (see the dash branch above); keep it off during normal movement ---
	_set_trail(false)

	_update_camera(up)   # follow the top every frame, recentering immediately (no lag = no spiral)
	_update_light(up)

func _update_dash_indicator() -> void:
	# fill the ring as the cooldown recharges: 0 right after a dash, 1.0 when ready again
	if dash_indicator == null:
		return
	var mat := dash_indicator.get_active_material(0) as ShaderMaterial
	if mat == null:
		return
	var p := 1.0
	if dash_cooldown > 0.0:
		p = clampf(1.0 - dash_cooldown_left / dash_cooldown, 0.0, 1.0)
	mat.set_shader_parameter("progress", p)

func _setup_dash_colors() -> void:
	# build a Color Initial Ramp so EACH particle samples a random color from the palette,
	# giving a multi-colored trail (all colors at once). dash_colors empty = a rainbow.
	if dash_particles == null:
		return
	var mat := dash_particles.process_material as ParticleProcessMaterial
	if mat == null:
		return

	var gradient := Gradient.new()
	# Gradient.new() ships with 2 default stops; we replace them wholesale below
	var cols := dash_colors
	if cols.is_empty():
		cols = [Color.RED, Color.YELLOW, Color.GREEN, Color.CYAN, Color.BLUE, Color.MAGENTA]
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in cols.size():
		# spread the palette evenly from 0..1 so the random sample hits all colors equally
		offsets.append(0.0 if cols.size() == 1 else float(i) / float(cols.size() - 1))
		colors.append(cols[i])
	gradient.offsets = offsets
	gradient.colors = colors

	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	mat.color_initial_ramp = ramp   # per-particle: each draws a random point on this ramp
	mat.color = Color.WHITE         # keep base white so the ramp colors show true

func _set_trail(on: bool) -> void:
	# toggle continuous emission; particles use world-space coords so they stay
	# put as the top moves away, forming a trail rather than a clump on the player
	if dash_particles != null and dash_particles.emitting != on:
		dash_particles.emitting = on

func _start_dash(up: Vector3) -> void:
	# pick the tangent direction to dash in: toward the cursor if it's over the planet,
	# otherwise straight ahead along the current heading
	var dir := heading
	var dist := dash_distance
	var target = _cursor_planet_point()
	if target != null:
		var point: Vector3 = target
		var to_dir := (point - planet_center).normalized()
		var cos_a := clampf(up.dot(to_dir), -1.0, 1.0)
		var to_tangent := to_dir - up * cos_a
		if to_tangent.length() > 0.0001:
			dir = to_tangent.normalized()
			# don't overshoot the cursor; cap at dash_distance for far targets
			dist = minf(acos(cos_a) * radius, dash_distance)
	if dist <= 0.001:
		return
	dash_axis = up.cross(dir).normalized()
	var total_angle := dist / radius
	dash_angular_speed = total_angle / maxf(dash_duration, 0.001)
	dash_time_left = dash_duration
	dash_cooldown_left = dash_cooldown

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

func get_surface_speed() -> float:
	# current speed along the surface (units/sec). during a dash, report the dash's true
	# speed rather than the carried-out momentum, so dashing can hit an enemy's kill threshold.
	if dash_time_left > 0.0:
		return dash_angular_speed * radius
	return surface_vel.length()

func bounce_off(from_pos: Vector3) -> void:
	# rebound away from a contact point (e.g. an enemy we hit too slowly to kill).
	var up := (global_position - planet_center).normalized()
	# contact normal in the tangent plane, pointing from the obstacle toward us
	var normal := _project_tangent(global_position - from_pos, up)
	if normal == Vector3.ZERO:
		normal = -heading
	dash_time_left = 0.0                       # cancel any active dash so the bounce isn't ignored
	surface_vel = surface_vel.bounce(normal)   # reflect velocity off the contact
	# guarantee a minimum outward push even if we were nearly stopped on impact
	var min_push := move_speed * 0.5
	var outward := surface_vel.dot(normal)
	if outward < min_push:
		surface_vel += normal * (min_push - outward)
	if surface_vel.length() > 0.001:
		heading = _project_tangent(surface_vel, up)

func _project_tangent(v: Vector3, up: Vector3) -> Vector3:
	# remove the component along 'up' so the vector stays on the tangent plane
	return (v - up * v.dot(up)).normalized()
