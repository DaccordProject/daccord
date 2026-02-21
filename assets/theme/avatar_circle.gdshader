shader_type canvas_item;

uniform float radius : hint_range(0.0, 0.5) = 0.5;

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
}
