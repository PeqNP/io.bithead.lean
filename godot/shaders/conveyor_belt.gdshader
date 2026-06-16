// Copyright © 2026 Bithead LLC. All rights reserved.
//
// Conveyor belt animation: scrolls a tiled chevron texture along the belt's
// UV direction. Works on any Line2D with Texture Mode = Tile.
//
// speed_px: Desired speed in pixels per second.
// tex_width: Pixel width of one repeat of your chevron texture.

shader_type canvas_item;

uniform float speed_px : hint_range(0.0, 500.0) = 60.0;
uniform float tex_width : hint_range(1.0, 512.0) = 64.0;

void fragment() {
	float uv_speed = speed_px / tex_width;
	vec2 animated_uv = mod(UV - vec2(TIME * uv_speed, 0.0), vec2(1.0));
	COLOR = texture(TEXTURE, animated_uv);
}