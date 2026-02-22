shader_type canvas_item;

uniform float radius : hint_range(0.0, 0.5) = 0.5;
uniform float ring_opacity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(0.231, 0.647, 0.365, 1.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist;
	if (radius >= 0.5) {
		// Pure circle
		dist = length(uv);
	} else {
		// Rounded rectangle
		vec2 q = abs(uv) - vec2(0.5 - radius);
		dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius + 0.5;
		dist = dist; // normalize
	}
	// Smooth edge
	float aa = fwidth(dist);
	float alpha = 1.0 - smoothstep(0.5 - aa, 0.5, dist);
	COLOR.a *= alpha;

	// Speaking ring: draw a ring just inside the outer edge
	if (ring_opacity > 0.0) {
		float ring_width = 0.045;
		float ring_outer = 0.48;
		float ring_inner = ring_outer - ring_width;
		float ring = smoothstep(ring_inner - aa, ring_inner, dist)
					* (1.0 - smoothstep(ring_outer - aa, ring_outer, dist));
		COLOR.rgb = mix(COLOR.rgb, ring_color.rgb, ring * ring_opacity);
	}
}
