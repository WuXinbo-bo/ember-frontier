shader_type spatial;
render_mode diffuse_burley;
// Small disposable earth band outside actual live ground-level foundations.
// One existing soil image, opaque cutout/depth, no fake contact shadow or soil fact.
uniform sampler2D soil_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
	vec3 soil = texture(soil_texture, UV / 1.6).rgb;
	ALBEDO = soil;
	ROUGHNESS = 0.96;
	SPECULAR = 0.25;
	ALPHA = clamp(COLOR.a * 1.6 + (soil.r - 0.35) * 0.5, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.4;
}
