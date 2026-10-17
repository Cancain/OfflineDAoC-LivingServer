// A ghost's glow (the server's GHOST flag - a spiritmaster's spirit pets, owner 2026-10-14: "in the original client they
// had like a subtle white glow to them ... here they appear as translucent grey"): drawn over the translucent figure
// as a material overlay, adding a soft white light - brighter toward the silhouette - whatever the scene's lighting.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.86, 0.92, 1.0);
uniform float strength = 0.16;
uniform float rim = 0.45;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float edge = pow(1.0 - facing, 2.0);
	ALBEDO = tint * (strength + edge * rim);
}
