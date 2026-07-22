shader_type canvas_item;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(source.rgb * vec3(0.8, 1.0, 0.9), source.a);
}
