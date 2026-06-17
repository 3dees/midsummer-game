// Vertical motion-blur for the slot-reel spin. Samples the texture along Y and
// averages, so a fast-cycling reel smears into a vertical streak. `strength` is
// eased to 0 as each column settles. Cheap: 9 taps per pixel.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 0.05) = 0.0;

void fragment() {
	vec4 acc = vec4(0.0);
	for (int i = -4; i <= 4; i++) {
		float off = float(i) * strength;
		acc += texture(TEXTURE, UV + vec2(0.0, off));
	}
	COLOR = acc / 9.0;
}
