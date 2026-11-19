// Shared metre/phase sampling for terrain and its shoulder projection.
// Keeping the endpoint sampler identical avoids a second texture scale or seams.
vec2 ground_phase(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

vec3 ground_site(vec2 uv, vec2 dx, vec2 dy, vec2 site, sampler2D source, sampler2D variant, bool use_variant) {
	vec2 offset = ground_phase(site);
	float turn = floor(offset.y * 4.0);
	if (turn < 1.0) { uv = uv; }
	else if (turn < 2.0) { uv = vec2(-uv.y, uv.x); dx = vec2(-dx.y, dx.x); dy = vec2(-dy.y, dy.x); }
	else if (turn < 3.0) { uv = -uv; dx = -dx; dy = -dy; }
	else { uv = vec2(uv.y, -uv.x); dx = vec2(dx.y, -dx.x); dy = vec2(dy.y, -dy.x); }
	if (use_variant && offset.x > 0.5) {
		return textureGrad(variant, uv + offset, dx, dy).rgb;
	}
	return textureGrad(source, uv + offset, dx, dy).rgb;
}

vec3 ground_colour(vec2 metres, vec2 sample_metres, sampler2D source, sampler2D variant, bool use_variant, bool break_repetition, float mip_bias) {
	vec2 uv = metres / sample_metres;
	// Compute pixel footprint BEFORE phase/variant branches. Native explicit
	// gradients keep mip/anisotropy coherent at phase boundaries. The small
	// positive bias softens subpixel albedo marks, without rescaling metres or
	// blurring silhouettes/UI. No new texture fetches or generated image copy.
	vec2 dx = dFdx(uv) * exp2(mip_bias);
	vec2 dy = dFdy(uv) * exp2(mip_bias);
	if (!break_repetition) { return textureGrad(source, uv, dx, dy).rgb; }
	vec2 grid = metres / 5.6;
	vec2 cell = floor(grid);
	vec2 f = fract(grid);
	vec2 a;
	vec2 b;
	vec2 c;
	vec3 weights;
	if (f.x + f.y <= 1.0) {
		a = cell; b = cell + vec2(1.0, 0.0); c = cell + vec2(0.0, 1.0);
		weights = vec3(1.0 - f.x - f.y, f.x, f.y);
	} else {
		a = cell + vec2(1.0); b = cell + vec2(0.0, 1.0); c = cell + vec2(1.0, 0.0);
		weights = vec3(f.x + f.y - 1.0, 1.0 - f.x, 1.0 - f.y);
	}
	return ground_site(uv, dx, dy, a, source, variant, use_variant) * weights.x
		+ ground_site(uv, dx, dy, b, source, variant, use_variant) * weights.y
		+ ground_site(uv, dx, dy, c, source, variant, use_variant) * weights.z;
}
