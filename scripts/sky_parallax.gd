extends WorldEnvironment

# Makes the starfield background drift SLOWER than the camera (parallax), for a sense of depth and
# gentler motion. The space_sky shader samples stars through a `sky_rot` matrix; each frame we feed
# it only a fraction of the camera's current rotation, so the stars rotate at `parallax` x camera.

@export_range(0.0, 1.0) var parallax: float = 0.3   # 0 = stars locked to screen, 1 = full camera tracking

var _mat: ShaderMaterial

func _ready() -> void:
	if environment != null and environment.sky != null:
		_mat = environment.sky.sky_material as ShaderMaterial

func _process(_delta: float) -> void:
	if _mat == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# camera world rotation; sampling through its inverse cancels the pan (screen-locked stars),
	# and re-applying `parallax` of it lets them drift at a reduced rate.
	var cam_basis := cam.global_transform.basis.orthonormalized()
	var partial := Quaternion.IDENTITY.slerp(cam_basis.get_rotation_quaternion(), parallax)
	_mat.set_shader_parameter("sky_rot", Basis(partial) * cam_basis.inverse())
