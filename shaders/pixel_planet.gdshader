shader_type spatial;
// Flat-lit (uniform brightness) procedural Earth on a real 3D sphere, generated from 3D noise (no
// texture). Pixel-snapped for a chunky look. Also samples the SAME cloud field used by the cloud
// shell and projects it down as a moving shadow on the surface.
render_mode unshaded;

// --- look / pixelation ---
uniform float pixel_density : hint_range(8.0, 400.0) = 100.0;   // lower = chunkier pixel cells
uniform float edge_sharpness : hint_range(0.001, 0.15) = 0.012; // smaller = crisper terrain edges

// --- continents ---
uniform float continent_scale : hint_range(0.5, 8.0) = 1.9;
uniform float sea_level : hint_range(0.0, 1.0) = 0.46;
uniform float warp : hint_range(0.0, 1.0) = 0.45;
uniform float seed = 0.0;

// --- water (deep -> shallow toward the coast) ---
uniform vec3 water0 : source_color = vec3(0.557, 0.749, 0.898);  // #8ebfe5
uniform vec3 water1 : source_color = vec3(0.631, 0.816, 0.949);  // #a1d0f2
uniform vec3 water2 : source_color = vec3(0.722, 0.882, 0.980);  // #b8e1fa

// --- land (low -> high) ---
uniform vec3 land0 : source_color = vec3(0.580, 0.741, 0.537);   // #94bd89
uniform vec3 land1 : source_color = vec3(0.655, 0.769, 0.553);   // #a7c48d
uniform vec3 land2 : source_color = vec3(0.737, 0.792, 0.580);   // #bcca94

// --- mountains (low -> high) ---
uniform vec3 mtn0 : source_color = vec3(0.902, 0.875, 0.702);    // #e6dfb3
uniform vec3 mtn1 : source_color = vec3(0.914, 0.843, 0.659);    // #e9d7a8
uniform vec3 mtn2 : source_color = vec3(0.765, 0.651, 0.420);    // #c3a66b
uniform vec3 mtn3 : source_color = vec3(0.667, 0.541, 0.322);    // #aa8a52
uniform vec3 mtn4 : source_color = vec3(0.612, 0.475, 0.271);    // #9c7945
uniform vec3 mtn5 : source_color = vec3(0.710, 0.667, 0.557);    // #b5aa8e

// --- cloud shadows (these MUST match the cloud_layer material's settings to line up) ---
uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.25; // how much the shadow darkens the ground
uniform vec3 cloud_shadow_dir = vec3(1.0, 0.0, 0.6);   // direction the shadow is offset from under the cloud (sun angle)
uniform float cloud_shadow_offset : hint_range(0.0, 0.5) = 0.08;   // how far the shadow slides off from directly below
uniform float cloud_pixel_density = 100.0;
uniform float cloud_scale = 3.0;
uniform float cloud_coverage = 0.62;
uniform float cloud_softness = 0.06;
uniform float cloud_speed = 0.035;
uniform float cloud_morph_speed = 0.2;
uniform float cloud_morph_amount = 1.0;

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

float sstep(float edge, float x) {
	return smoothstep(edge - edge_sharpness, edge + edge_sharpness, x);
}

void fragment() {
	vec3 dir = normalize(v_obj_pos);
	vec3 pdir = floor(dir * pixel_density) / pixel_density;   // snap to chunky cells
	vec3 dom = pdir * continent_scale + seed;

	float elevation = fbm(dom + warp * fbm(dom * 0.5 + 5.0));

	vec3 col;
	if (elevation < sea_level) {
		// water: deepest -> shallow as it approaches the coast
		col = water0;
		col = mix(col, water1, sstep(sea_level - 0.16, elevation));
		col = mix(col, water2, sstep(sea_level - 0.05, elevation));
	} else {
		// land in the lowlands, then a 6-step mountain gradient at higher elevations
		float l = (elevation - sea_level) / max(1.0 - sea_level, 0.001);
		col = land0;
		col = mix(col, land1, sstep(0.10, l));
		col = mix(col, land2, sstep(0.20, l));
		col = mix(col, mtn0, sstep(0.32, l));
		col = mix(col, mtn1, sstep(0.43, l));
		col = mix(col, mtn2, sstep(0.54, l));
		col = mix(col, mtn3, sstep(0.65, l));
		col = mix(col, mtn4, sstep(0.76, l));
		col = mix(col, mtn5, sstep(0.87, l));
	}

	// cloud shadow: sample the SAME cloud field (offset toward the sun so the shadow is visible next
	// to the cloud, not hidden under it) and darken the ground where a cloud covers it.
	vec3 sdir = normalize(dir + normalize(cloud_shadow_dir) * cloud_shadow_offset);
	float ca = TIME * cloud_speed;
	mat2 crot = mat2(vec2(cos(ca), -sin(ca)), vec2(sin(ca), cos(ca)));
	sdir.xz = crot * sdir.xz;
	vec3 cm = vec3(sin(TIME * cloud_morph_speed * 0.7),
			cos(TIME * cloud_morph_speed * 1.1),
			sin(TIME * cloud_morph_speed * 0.5)) * cloud_morph_amount;
	vec3 cpd = floor(sdir * cloud_pixel_density) / cloud_pixel_density;
	float cd = fbm(cpd * cloud_scale + cm + 10.0);
	float shadow = smoothstep(cloud_coverage, cloud_coverage + cloud_softness, cd);
	col *= mix(1.0, 1.0 - cloud_shadow_strength, shadow);

	// uniform brightness otherwise: the biome color is output flat across the whole planet
	ALBEDO = clamp(col, 0.0, 1.0);
}
