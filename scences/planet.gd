extends MeshInstance3D


@export var cube: PackedScene
@export var delay_in_seconds: float = 1.0

func get_point_on_sphere() -> Vector3:
	var sphere_pos = self.global_position
	var base_radius = self.mesh.radius
	var actual_radius = base_radius * self.global_transform.basis.get_scale().x
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var random_direction = Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
	var final_world_point = sphere_pos + (random_direction * actual_radius)
	
	return final_world_point

func _ready() -> void:
	while true:
		var new_cube = cube.instantiate()
		new_cube.position = get_point_on_sphere()
		$"..".add_child(new_cube)
		await get_tree().create_timer(delay_in_seconds).timeout
