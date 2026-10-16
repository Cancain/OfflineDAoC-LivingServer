shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Zone water from the client's own pieces only (owner rule 2026-10-09: bring assets over, don't replace them):
//   - the zone's water texture (sector.dat [riverNN] texture=watery.tga), scrolling at the river's flow value
//   - the client's environment-bump map app/water/bump3.tga (du/dv in RG) offsetting the lookups, as the client's
//     bump stage does: this is the fine moving ripple in the client
//   - a sky cloud layer (zones/sky) as the reflected environment, no trees or shore
//   - plain alpha blending, so the bottom shows through in the shallows
// Still to confirm against the client (listed in WORLD IMPORT LESSONS.md): exact env texture, blend amounts, alpha.

uniform sampler2D water_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bump_tex : filter_linear_mipmap, repeat_enable;          // du/dv in RG, 0.5 = no offset
uniform sampler2D env_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float water_repeat_m = 12.0;
uniform float bump_repeat_m = 6.0;
uniform float bump_scale = 0.06;         // how far the du/dv map pushes the lookups
uniform float env_amount = 0.45;
uniform float opacity = 0.78;
uniform vec2 drift = vec2(0.010, 0.004); // repeats per second, from the zone's flow value
uniform vec3 sky_color : source_color = vec3(0.55, 0.68, 0.78);
uniform vec3 sun_dir = vec3(0.4, 0.7, 0.5);              // kept for the loader; unused
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.86);
uniform bool use_color = false;          // the Shrouded Isles' textureless water: sector.dat base_color
uniform vec3 base_color : source_color = vec3(0.333, 0.314, 0.251);
// The textureless water's depth (owner 2026-10-15: Modernagrav's sea "completely clear ... you can see the bottom",
// the client's is dark grey): the base colour's own 0.35 alpha over the shallows, darker and closer to opaque as the
// water behind the surface gets deeper - the scene's depth under it, so it follows the real sea bed.
uniform bool depth_fade = false;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float deep_m = 4.0;              // this much water behind the surface: fully deep
uniform float deep_opacity = 0.92;
uniform float deep_dark = 0.5;           // the deep colour: base_color times this

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = world_pos.xz;
	vec2 dudv = texture(bump_tex, p / bump_repeat_m + drift * t * 4.0).rg * 2.0 - 1.0;
	vec3 surface = use_color ? base_color : texture(water_tex, p / water_repeat_m + drift * t + dudv * bump_scale).rgb;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_eye = normalize(cam - world_pos);
	vec3 r = reflect(-to_eye, vec3(0.0, 1.0, 0.0));
	vec2 env_uv = r.xz / (abs(r.y) + 0.25) * 0.35 + dudv * bump_scale + vec2(t * 0.003, 0.0);
	vec3 env = texture(env_tex, env_uv).rgb * sky_color * 1.6;
	float alpha = opacity;
	if (depth_fade) {
		float d = texture(depth_tex, SCREEN_UV).r;
		vec4 bed = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
		bed.xyz /= bed.w;
		float k = smoothstep(0.0, 1.0, clamp(distance(bed.xyz, VERTEX) / deep_m, 0.0, 1.0));
		surface = mix(surface, surface * deep_dark, k);
		alpha = mix(opacity, deep_opacity, k);
	}
	ALBEDO = mix(surface, env, env_amount);
	ALPHA = alpha;
}
