shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 0.2, 1.0);
uniform float outline_width = 0.05;

void vertex() {
	vec3 normal_scaled = NORMAL * outline_width;
	VERTEX += normal_scaled;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
