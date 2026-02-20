shader_type canvas_item;

uniform float corner_radius : hint_range(0.0, 0.5) = 0.1;
uniform float shimmer_offset : hint_range(-0.5, 1.5) = -0.5;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist;
	if (corner_radius >= 0.5) {
		dist = length(uv);
	} else {
		vec2 q = abs(uv) - vec2(0.5 - corner_radius);
		dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius + 0.5;
	}
	float aa = fwidth(dist);
	float alpha = 1.0 - smoothstep(0.5 - aa, 0.5, dist);

	// Shimmer highlight
	float shimmer = smoothstep(0.15, 0.0, abs(UV.x - shimmer_offset));
	COLOR.rgb += shimmer * 0.15;
	COLOR.a *= alpha;
}
