shader_type canvas_item;

uniform float circle_radius : hint_range(0.0, 0.5) = 0.5;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	float aa = fwidth(dist);
	COLOR.a *= 1.0 - smoothstep(circle_radius - aa, circle_radius, dist);
}
