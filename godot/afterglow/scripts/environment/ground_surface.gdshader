shader_type spatial;
render_mode diffuse_burley;
#include "res://scripts/environment/ground_sampling.gdshaderinc"
// Reuse the declared source pair at its metre scale. Three deterministic
// phase samples vary the repeated 1.6 m stamp without new generated images, geometry,
// simulation state, time noise or chunk-local seeds. Only opaque ground uses it.
uniform sampler2D ground_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D variant_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 sample_metres = vec2(1.6);
uniform bool break_repetition = true;
uniform bool use_variant = false;
uniform float detail_mip_bias : hint_range(0.0, 2.0) = 0.75;

void fragment() {
	ALBEDO = ground_colour(UV, sample_metres, ground_texture, variant_texture, use_variant, break_repetition, detail_mip_bias);
	ROUGHNESS = 0.96;
	SPECULAR = 0.25;
}
