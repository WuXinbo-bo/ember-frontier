shader_type spatial;
render_mode diffuse_burley, depth_draw_never, cull_disabled;
#include "res://scripts/environment/ground_sampling.gdshaderinc"

uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_variant : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_variant : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D edge_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 grass_metres = vec2(1.6);
uniform vec2 earth_metres = vec2(1.6);
uniform bool earth_use_variant = false;
uniform float grass_mip_bias : hint_range(0.0, 2.0) = 0.75;
uniform float earth_mip_bias : hint_range(0.0, 2.0) = 0.75;

void fragment() {
	// UV is continuous world XZ metres; UV2 is the original 1.6 x .65 m strip.
	// The sparse delivered 09 alpha perturbs the boundary, rather than drawing
	// its brown dots as a standalone dark/dashed outline. Fade only the small
	// strip edges back into the actual terrain; do not write coplanar depth at
	// orthogonal road corners. These ground projections never cast shadows.
	float fleck = texture(edge_texture, UV2).a;
	float earth_weight = smoothstep(0.12, 0.88, UV2.y + (fleck - 0.5) * 0.18);
	vec3 grass = ground_colour(UV, grass_metres, grass_texture, grass_variant, true, true, grass_mip_bias);
	vec3 earth = ground_colour(UV, earth_metres, earth_texture, earth_variant, earth_use_variant, true, earth_mip_bias);
	ALBEDO = mix(grass, earth, earth_weight);
	ALPHA = 1.0 - abs(UV2.y * 2.0 - 1.0);
	ROUGHNESS = 0.96;
	SPECULAR = 0.25;
}
