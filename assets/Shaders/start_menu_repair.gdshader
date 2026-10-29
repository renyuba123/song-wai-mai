shader_type canvas_item;

// Keep the supplied art intact outside the original menu lettering.
uniform int selected = 0;
uniform sampler2D artwork : source_color;
const vec2 IMAGE_SIZE = vec2(1672.0, 941.0);

vec4 original_at(vec2 pixel) {
	return texture(artwork, pixel / IMAGE_SIZE);
}

vec4 repaired_row(vec2 pixel, float top, float bottom) {
	float blend = (pixel.y - top) / (bottom - top);
	return mix(original_at(vec2(pixel.x, top - 1.0)), original_at(vec2(pixel.x, bottom + 1.0)), blend);
}

bool pale_letter(vec4 color) {
	return color.r > 0.44 && color.g > 0.44 && color.b > 0.44 && abs(color.r - color.b) < 0.12;
}

void fragment() {
	vec2 pixel = UV * IMAGE_SIZE;
	vec4 color = texture(TEXTURE, UV);

	// Remove the reference image's fixed selection arrow and unused rows.
	if (pixel.x >= 102.0 && pixel.x < 140.0 && pixel.y >= 397.0 && pixel.y < 443.0) {
		float blend = (pixel.x - 102.0) / 38.0;
		color = mix(original_at(vec2(101.0, pixel.y)), original_at(vec2(141.0, pixel.y)), blend);
	}
	bool continue_text = pixel.x >= 160.0 && pixel.x < 335.0 && pixel.y >= 405.0 && pixel.y < 433.0;
	bool load_text = pixel.x >= 160.0 && pixel.x < 370.0 && pixel.y >= 506.0 && pixel.y < 534.0;
	bool old_settings_text = pixel.x >= 160.0 && pixel.x < 330.0 && pixel.y >= 557.0 && pixel.y < 585.0;
	bool old_exit_text = pixel.x >= 160.0 && pixel.x < 245.0 && pixel.y >= 607.0 && pixel.y < 635.0;
	if (continue_text) {
		color = repaired_row(pixel, 405.0, 433.0);
	}
	if (load_text) {
		color = repaired_row(pixel, 506.0, 534.0);
	}
	if (old_settings_text) {
		color = repaired_row(pixel, 557.0, 585.0);
	}
	if (old_exit_text) {
		color = repaired_row(pixel, 607.0, 635.0);
	}

	// START GAME stays at its original position, including its original pixels.
	bool start_text = pixel.x >= 160.0 && pixel.x < 370.0 && pixel.y >= 447.0 && pixel.y < 492.0;
	if (start_text && pale_letter(color) && selected == 0) {
		color.rgb = vec3(1.0, 0.79, 0.43) * (0.64 + color.r * 0.36);
	}

	// Reuse the original letter pixels, shifted up by exactly one 51 px row.
	bool settings_row = pixel.x >= 160.0 && pixel.x < 325.0 && pixel.y >= 507.0 && pixel.y < 537.0;
	bool exit_row = pixel.x >= 160.0 && pixel.x < 245.0 && pixel.y >= 558.0 && pixel.y < 586.0;
	if (settings_row || exit_row) {
		vec4 letter = original_at(pixel + vec2(0.0, 51.0));
		if (pale_letter(letter)) {
			color.rgb = letter.rgb;
			if ((settings_row && selected == 1) || (exit_row && selected == 2)) {
				color.rgb = vec3(1.0, 0.79, 0.43) * (0.64 + letter.r * 0.36);
			}
		}
	}
	COLOR = color;
}
