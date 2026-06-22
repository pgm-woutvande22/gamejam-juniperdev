shader_type sky;
// Stylized pixel-space background: a dark vertical gradient with sparse, twinkling pixel stars.
// Used by the level's WorldEnvironment, so it renders behind the planet at infinity from any angle.

uniform vec3 horizon_color : source_color = vec3(0.06, 0.05, 0.12);  // color near the "horizon" (dir.y ~ 0)
uniform vec3 zenith_color : source_color = vec3(0.02, 0.02, 0.05);   // color overhead/below (dir.y -> ±1)
uniform float star_scale : hint_range(20.0, 600.0) = 220.0;          // star grid resolution (higher = smaller/denser cells)
uniform float star_density : hint_range(0.0, 0.2) = 0.03;            // fraction of cells that hold a star
uniform float star_brightness : hint_range(0.0, 3.0) = 1.0;
uniform vec3 star_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float twinkle_speed : hint_range(0.0, 8.0) = 1.5;
// rotation applied to the view direction before sampling stars. driven from script with only a
// FRACTION of the camera's rotation, so the starfield drifts slower than the camera (parallax).
uniform mat3 sky_rot = mat3(1.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(sky_rot * EYEDIR);
	// vertical gradient across the sphere of directions
	float g = clamp(abs(dir.y), 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, g);

	// stars: snap the view direction to a grid, hash each cell, light the sparse winners
	vec3 cell = floor(dir * star_scale);
	float h = hash13(cell);
	if (h > 1.0 - star_density) {
		float seed = hash13(cell + 7.0);
		float twinkle = 0.55 + 0.45 * sin(TIME * twinkle_speed + seed * 6.2831);
		float boost = 1.0 + step(0.72, seed) * 1.6;   // a rarer subset of stars burns brighter
		col += star_color * star_brightness * twinkle * boost;
	}
	COLOR = col;
}
