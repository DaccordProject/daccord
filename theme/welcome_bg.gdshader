shader_type canvas_item;

// Animated welcome screen background shader
// GL Compatibility safe — no compute, no advanced features

// Hash-based pseudo-random
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Animated gradient: dark navy to subtle purple, slowly shifting
	float t = TIME * 0.15;
	float gradient = mix(0.08, 0.14, uv.y);
	vec3 navy = vec3(0.06, 0.065, 0.12);
	vec3 purple = vec3(0.10, 0.07, 0.14);
	float blend = sin(t + uv.x * 2.0) * 0.5 + 0.5;
	vec3 bg = mix(navy, purple, blend * 0.6) + gradient * 0.3;

	// Floating bokeh particles — soft glowing circles drifting upward
	float bokeh = 0.0;
	for (int i = 0; i < 15; i++) {
		float fi = float(i);
		float seed = hash(vec2(fi, fi * 0.7));
		float x = fract(seed + sin(TIME * 0.1 * (seed + 0.5) + fi) * 0.08);
		float speed = 0.02 + seed * 0.03;
		float y = fract(seed * 3.7 - TIME * speed);
		float radius = 0.008 + seed * 0.018;
		float dist = length(uv - vec2(x, y));
		float glow = smoothstep(radius, radius * 0.1, dist);
		float alpha = 0.03 + seed * 0.09;
		bokeh += glow * alpha;
	}
	vec3 bokeh_color = vec3(0.345, 0.396, 0.949); // blurple
	bg += bokeh_color * bokeh;

	// Subtle noise shimmer — sparkle dots fading in/out
	float sparkle = hash(uv * 800.0 + TIME * 0.5);
	sparkle = pow(sparkle, 20.0) * 0.08;
	bg += vec3(sparkle);

	COLOR = vec4(bg, 1.0);
}
