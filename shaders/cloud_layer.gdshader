shader_type spatial;
// A transparent cloud shell: put this on a sphere slightly larger than the planet, so the player and
// enemies orbit *inside* it and the clouds drift overhead. Procedural noise -> alpha, animated by a
// slow rotation around the poles. Pixel-snapped to match the planet's chunky look.
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 cloud_color : source_color = vec3(0.922, 0.929, 0.914); // #ebede9
uniform float pixel_density : hint_range(8.0, 400.0) = 100.0;
uniform float cloud_scale : hint_range(0.5, 8.0) = 3.0;
uniform float coverage : hint_range(0.0, 1.0) = 0.62;   // higher = fewer clouds
uniform float softness : hint_range(0.001, 0.3) = 0.06; // edge feather of each cloud
uniform float opacity : hint_range(0.0, 1.0) = 0.85;    // max cloud opacity
uniform float speed = 0.015;                            // drift speed around the poles
uniform float morph_speed : hint_range(0.0, 1.0) = 0.2; // how fast cloud shapes form/dissolve (0 = static shapes)
uniform float morph_amount : hint_range(0.0, 4.0) = 1.0; // how far through the noise volume the shapes wander

// --- soft volume (shade by cloud thickness; no directional ripples) ---
uniform float under_shade : hint_range(0.0, 1.0) = 0.7;      // brightness of thin cloud edges
uniform float volume_range : hint_range(0.01, 0.6) = 0.25;   // density span over which edges brighten to full core

const int OCTAVES = 6;
// rotation applied to the domain each octave so features don't align on a grid (kills the repeat)
const mat3 OCT_ROT = mat3(
		vec3(0.00, 0.80, 0.60),
		vec3(-0.80, 0.36, -0.48),
		vec3(-0.60, -0.48, 0.64));

varying vec3 v_obj_pos;

void vertex() {
	v_obj_pos = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < OCTAVES; i++) {
		v += a * vnoise(p);
		p = OCT_ROT * (p * 2.0);   // rotate + scale each octave so detail never lines up -> no repeat
		a *= 0.5;
	}
	return v;
}

// cloud density at a (drift-rotated) direction; pixel-snapped + morphed so it matches the look
float density_at(vec3 d, vec3 m) {
	vec3 pd = floor(d * pixel_density) / pixel_density;
	return fbm(pd * cloud_scale + m + 10.0);
}

void fragment() {
	vec3 dir = normalize(v_obj_pos);
	// drift the clouds by rotating the sample around the y (pole) axis over time
	float ang = TIME * speed;
	mat2 rot = mat2(vec2(cos(ang), -sin(ang)), vec2(sin(ang), cos(ang)));
	dir.xz = rot * dir.xz;
	// evolve the shapes: wander through the 3D noise volume so puffs form and dissolve in place
	vec3 m = vec3(sin(TIME * morph_speed * 0.7),
			cos(TIME * morph_speed * 1.1),
			sin(TIME * morph_speed * 0.5)) * morph_amount;

	float c = density_at(dir, m);

	// soft volume: shade by the cloud's own thickness -> dense cores bright, thin wisps darker.
	// driven by the density value (not cell-to-cell differences), so there's no rippling.
	float thickness = smoothstep(coverage, coverage + volume_range, c);
	float bright = mix(under_shade, 1.0, thickness);

	float a = smoothstep(coverage, coverage + softness, c) * opacity;
	ALBEDO = cloud_color * bright;
	ALPHA = a;
}
