shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;

// Pixel art post-process. The camera quad leaves CanvasLayer text and HUD sharp.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;

uniform float pixel_size : hint_range(1.0, 12.0, 0.25) = 1.5;
uniform float color_steps : hint_range(8.0, 128.0, 1.0) = 64.0;
uniform float dither_strength : hint_range(0.0, 1.0, 0.05) = 0.0;
uniform float saturation : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float edge_highlight : hint_range(0.0, 1.0, 0.05) = 0.4;
uniform float black_line_width : hint_range(0.0, 3.0, 0.25) = 1.0;
uniform float highlight_line_width : hint_range(0.0, 3.0, 0.25) = 1.0;
uniform float line_thin_start : hint_range(0.0, 200.0, 1.0) = 8.0;
uniform float line_thin_end : hint_range(1.0, 300.0, 1.0) = 50.0;
uniform float far_line_thickness : hint_range(0.25, 1.0, 0.05) = 0.55;

float view_depth(vec2 uv, float raw_depth, mat4 inverse_projection) {
	vec4 view = inverse_projection * vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
	return -view.z / view.w;
}

// x: geometric edge, y: brighter face, z: silhouette against the background.
vec3 edge_at(vec2 uv, vec3 center_normal, float center_distance, float center_luma, float lod, mat4 inverse_projection) {
	float raw_depth = texture(depth_texture, uv).r;
	// Draw the silhouette on the object side, leaving sky/background untouched.
	if (raw_depth <= 0.00001) return vec3(1.0);
	float distance = view_depth(uv, raw_depth, inverse_projection);
	vec3 neighbor_normal = texture(normal_texture, uv).rgb * 2.0 - 1.0;
	float bend = 1.0 - dot(center_normal, neighbor_normal);
	// Large depth changes need a stronger normal turn. Depth by itself would
	// draw false horizontal stripes across a flat road near the horizon.
	float min_bend = abs(distance - center_distance) > max(0.15, center_distance * 0.03) ? 0.35 : 0.18;
	if (bend <= min_bend) return vec3(0.0);
	vec3 neighbor_color = textureLod(screen_texture, uv, lod).rgb;
	float neighbor_luma = dot(neighbor_color, vec3(0.2126, 0.7152, 0.0722));
	float edge = smoothstep(min_bend, min_bend + 0.27, bend);
	return vec3(edge, edge * step(neighbor_luma + 0.01, center_luma), 0.0);
}

vec3 edge_ring(vec2 uv, vec2 offset, vec3 normal, float distance, float luma, float lod, mat4 inverse_projection, vec2 min_uv, vec2 max_uv) {
	vec3 result = vec3(0.0);
	result = max(result, edge_at(clamp(uv + vec2(offset.x, 0.0), min_uv, max_uv), normal, distance, luma, lod, inverse_projection));
	result = max(result, edge_at(clamp(uv - vec2(offset.x, 0.0), min_uv, max_uv), normal, distance, luma, lod, inverse_projection));
	result = max(result, edge_at(clamp(uv + vec2(0.0, offset.y), min_uv, max_uv), normal, distance, luma, lod, inverse_projection));
	result = max(result, edge_at(clamp(uv - vec2(0.0, offset.y), min_uv, max_uv), normal, distance, luma, lod, inverse_projection));
	return result;
}

// A fixed ordered pattern avoids temporal noise and shimmering.
float bayer4(vec2 pixel) {
	vec2 p = mod(pixel, 4.0);
	float x = p.x;
	float y = p.y;
	if (y < 1.0) {
		if (x < 1.0) return 0.0;
		if (x < 2.0) return 8.0;
		if (x < 3.0) return 2.0;
		return 10.0;
	}
	if (y < 2.0) {
		if (x < 1.0) return 12.0;
		if (x < 2.0) return 4.0;
		if (x < 3.0) return 14.0;
		return 6.0;
	}
	if (y < 3.0) {
		if (x < 1.0) return 3.0;
		if (x < 2.0) return 11.0;
		if (x < 3.0) return 1.0;
		return 9.0;
	}
	if (x < 1.0) return 15.0;
	if (x < 2.0) return 7.0;
	if (x < 3.0) return 13.0;
	return 5.0;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 viewport = max(VIEWPORT_SIZE, vec2(1.0));
	float block_size = max(1.0, pixel_size);
	vec2 pixel = floor(SCREEN_UV * viewport / block_size);
	vec2 sample_uv = (pixel + vec2(0.5)) * block_size / viewport;
	// A partial block at the right or bottom must sample inside the image.
	sample_uv = clamp(sample_uv, vec2(0.5) / viewport, vec2(1.0) - vec2(0.5) / viewport);

	// Read a prefiltered mip level so fine road textures do not alias into
	// high-contrast dots when four source pixels become one output block.
	float lod = log2(block_size) * 0.5;
	vec3 color = max(textureLod(screen_texture, sample_uv, lod).rgb, vec3(0.0));
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = max(mix(vec3(luma), color, saturation), vec3(0.0));
	if (black_line_width > 0.0 || (highlight_line_width > 0.0 && edge_highlight > 0.0)) {
		float raw_depth = texture(depth_texture, sample_uv).r;
		if (raw_depth > 0.00001) {
			float distance = view_depth(sample_uv, raw_depth, INV_PROJECTION_MATRIX);
			float thin_end = max(line_thin_end, line_thin_start + 0.01);
			float thin = smoothstep(line_thin_start, thin_end, distance);
			float coverage = mix(1.0, far_line_thickness, thin);
			{
				vec3 normal = texture(normal_texture, sample_uv).rgb * 2.0 - 1.0;
				vec2 min_uv = vec2(0.5) / viewport;
				vec2 max_uv = vec2(1.0) - min_uv;
				float black = 0.0;
				if (black_line_width > 0.0) {
					vec3 near_edge = edge_ring(sample_uv, vec2(block_size * black_line_width) / viewport, normal, distance, luma, lod, INV_PROJECTION_MATRIX, min_uv, max_uv);
					black = step(0.1, near_edge.x);
					// A near crease covers both faces. At a distance, keep the dark
					// face only; silhouettes retain their one-pixel object-side line.
					float bright_crease = step(0.1, near_edge.y) * (1.0 - step(0.1, near_edge.z));
					black *= 1.0 - thin * bright_crease;
				}
				if (highlight_line_width > 0.0 && edge_highlight > 0.0 && black < 0.01) {
					vec3 inner_edge = edge_ring(sample_uv, vec2(block_size * (black_line_width + highlight_line_width)) / viewport, normal, distance, luma, lod, INV_PROJECTION_MATRIX, min_uv, max_uv);
					float highlight = step(0.1, inner_edge.y) * edge_highlight * coverage;
					color += (vec3(1.0) - clamp(color, vec3(0.0), vec3(1.0))) * highlight * 0.45;
				}
				// A subpixel line is represented by partial coverage instead of
				// unstable samples below one physical screen pixel.
				color = mix(color, vec3(0.0), black * coverage);
			}
		}
	}

	float steps = max(color_steps, 2.0);
	float threshold = (bayer4(pixel) + 0.5) / 16.0 - 0.5;
	// Preserve highlights above 1.0 instead of clipping HDR values.
	ALBEDO = floor(color * steps + 0.5 + threshold * dither_strength) / steps;
}
