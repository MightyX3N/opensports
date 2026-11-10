// as ours.gdshader, for see-through surfaces (shadows, decals with soft edges)
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, specular_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform float unlit = 1.0;
uniform vec4 tint = vec4(1.0);

void fragment() {
	vec4 base = texture(tex, UV) * COLOR * tint;
	ALBEDO = base.rgb;
	ALPHA = base.a;
}
