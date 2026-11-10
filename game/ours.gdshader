// Open Sports' own models: vertex colours and a texture with soft toy-like lighting (sky /
// ground ambient, a wrapped sun, specular and a rim light) and distance fog.
shader_type spatial;
render_mode unshaded, cull_disabled, specular_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform float spec = 0.15;
uniform float shine = 24.0;
uniform float rim = 0.0;
uniform float unlit = 0.0;
uniform bool cull_back = true;
uniform vec4 tint = vec4(1.0);
global uniform vec3 os_sun;
global uniform vec3 os_sun_col;
global uniform vec3 os_sky;
global uniform vec3 os_ground;
global uniform vec3 os_fog_col;
global uniform vec2 os_fog;

varying vec3 v_world;
varying vec3 v_normal;
varying float v_depth;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	if (cull_back && !FRONT_FACING) { discard; }
	vec4 base = texture(tex, UV) * COLOR * tint;
	if (base.a < 0.02) { discard; }
	vec3 n = normalize(v_normal);
	if (!FRONT_FACING) { n = -n; }
	float hemi = n.y * 0.5 + 0.5;
	vec3 amb = mix(os_ground, os_sky, hemi);
	float d = dot(n, os_sun);
	float diff = max(d, 0.0) * 0.75 + 0.25 * max(d * 0.5 + 0.5, 0.0);
	vec3 eye = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(eye - v_world);
	vec3 h = normalize(os_sun + v);
	float sp = pow(max(dot(n, h), 0.0), shine) * spec;
	float rm = pow(1.0 - max(dot(n, v), 0.0), 3.0) * rim;
	vec3 lit = base.rgb * (amb + os_sun_col * diff) + vec3(sp) + vec3(rm);
	lit = mix(lit, base.rgb, unlit);
	float fog = clamp((v_depth - os_fog.x) / (os_fog.y - os_fog.x), 0.0, 1.0);
	lit = mix(lit, os_fog_col, fog * fog);
	ALBEDO = lit;
}
