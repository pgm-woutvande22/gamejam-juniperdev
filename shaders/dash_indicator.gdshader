// Radial cooldown ring for the dash. Draws a flat ring (on a PlaneMesh) that fills
// clockwise from the top as `progress` goes 0 -> 1. progress = 1 means dash is ready.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(0.25, 0.85, 1.0, 1.0);  // recharged portion
uniform vec4 empty_color : source_color = vec4(1.0, 1.0, 1.0, 0.12);  // not-yet-charged portion
uniform vec4 ready_color : source_color = vec4(0.4, 1.0, 0.6, 1.0);   // full ring when ready
uniform float inner_radius : hint_range(0.0, 1.0) = 0.78;
uniform float outer_radius : hint_range(0.0, 1.0) = 0.96;
uniform float edge_softness : hint_range(0.0, 0.1) = 0.02;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;            // remap UV to -1..1, center at 0
	float r = length(p);

	// soft-edged ring mask
	float ring = smoothstep(inner_radius - edge_softness, inner_radius + edge_softness, r)
			   * (1.0 - smoothstep(outer_radius - edge_softness, outer_radius + edge_softness, r));
	if (ring < 0.001) {
		discard;
	}

	// angle as 0..1, starting at the top (12 o'clock), increasing clockwise
	float frac = atan(p.x, p.y) / (2.0 * PI);
	if (frac < 0.0) {
		frac += 1.0;
	}

	vec4 col = frac <= progress ? fill_color : empty_color;
	if (progress >= 0.999) {
		col = ready_color;             // fully charged: whole ring lights up
	}

	ALBEDO = col.rgb;
	ALPHA = col.a * ring;
}
