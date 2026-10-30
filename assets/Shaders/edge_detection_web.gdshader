shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;

// The Web Compatibility renderer has no normal/roughness buffer. Keep the
// color treatment and find visible edges from the screen image instead.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float pixel_size : hint_range(1.0, 12.0, 0.25) = 1.0;
uniform float color_steps : hint_range(8.0, 128.0, 1.0) = 64.0;
uniform float dither_strength : hint_range(0.0, 1.0, 0.05) = 1.0;
uniform float saturation : hint_range(0.0, 2.0, 0.05) = 1.2;
uniform float edge_highlight : hint_range(0.0, 1.0, 0.05) = 0.7;
uniform float black_line_width : hint_range(0.0, 3.0, 0.25) = 1.0;
uniform float highlight_line_width : hint_range(0.0, 3.0, 0.25) = 1.25;

float bayer4(vec2 pixel) {
	vec2 p = mod(pixel, 4.0);
	if (p.y < 1.0) return p.x < 1.0 ? 0.0 : p.x < 2.0 ? 8.0 : p.x < 3.0 ? 2.0 : 10.0;
	if (p.y < 2.0) return p.x < 1.0 ? 12.0 : p.x < 2.0 ? 4.0 : p.x < 3.0 ? 14.0 : 6.0;
	if (p.y < 3.0) return p.x < 1.0 ? 3.0 : p.x < 2.0 ? 11.0 : p.x < 3.0 ? 1.0 : 9.0;
	return p.x < 1.0 ? 15.0 : p.x < 2.0 ? 7.0 : p.x < 3.0 ? 13.0 : 5.0;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 viewport = max(VIEWPORT_SIZE, vec2(1.0));
	float block_size = max(1.0, pixel_size);
	vec2 pixel = floor(SCREEN_UV * viewport / block_size);
	vec2 margin = vec2(0.5) / viewport;
	vec2 uv = clamp((pixel + vec2(0.5)) * block_size / viewport, margin, vec2(1.0) - margin);
	float lod = log2(block_size) * 0.5;
	vec3 color = max(textureLod(screen_texture, uv, lod).rgb, vec3(0.0));
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = max(mix(vec3(luma), color, saturation), vec3(0.0));

	// A four-neighbor color gradient outlines visible geometry without a normal buffer.
	vec2 offset = vec2(max(1.0, block_size * black_line_width)) / viewport;
	vec3 left_color = textureLod(screen_texture, clamp(uv - vec2(offset.x, 0.0), margin, vec2(1.0) - margin), lod).rgb;
	vec3 right_color = textureLod(screen_texture, clamp(uv + vec2(offset.x, 0.0), margin, vec2(1.0) - margin), lod).rgb;
	vec3 up_color = textureLod(screen_texture, clamp(uv - vec2(0.0, offset.y), margin, vec2(1.0) - margin), lod).rgb;
	vec3 down_color = textureLod(screen_texture, clamp(uv + vec2(0.0, offset.y), margin, vec2(1.0) - margin), lod).rgb;
	float gradient = max(length(left_color - right_color), length(up_color - down_color));
	float edge = smoothstep(0.10, 0.32, gradient);
	float neighbor_luma = dot((left_color + right_color + up_color + down_color) * 0.25, vec3(0.2126, 0.7152, 0.0722));
	float dark_side = step(luma, neighbor_luma + 0.025);
	color = mix(color, vec3(0.0), edge * dark_side * min(black_line_width, 1.0) * 0.75);
	color += (vec3(1.0) - clamp(color, vec3(0.0), vec3(1.0))) * edge * (1.0 - dark_side) * edge_highlight * min(highlight_line_width, 1.0) * 0.25;

	float threshold = (bayer4(pixel) + 0.5) / 16.0 - 0.5;
	ALBEDO = floor(color * max(color_steps, 2.0) + 0.5 + threshold * dither_strength) / max(color_steps, 2.0);
}
