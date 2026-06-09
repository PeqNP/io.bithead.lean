// Copyright © 2026 Bithead LLC. All rights reserved.
//
// Gray-out effect: desaturate to greyscale and reduce alpha to 50%.
// Apply to any CanvasItem via ShaderMaterial.

shader_type canvas_item;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float grey = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(grey), col.a * 0.5);
}
