shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 white_echo = vec3(0.89, 0.94, 0.86);
	COLOR = vec4(mix(source.rgb, white_echo, intensity), source.a);
}
