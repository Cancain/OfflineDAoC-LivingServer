shader_type sky;
// DAoC sky dome, drawn from the client's sky_*.dat values (zones/sky/sky.mpk, exported by pipeline/build_sky.py).
// Colours arrive already blended for the time of day and storm level (game/sky_system.gd):
//   canopy rings: zenith, east1..4 / west1..4 from overhead down to the horizon, nadir below; east/west blend by
//   which side of the sky the sun's path is on. Two cloud layers (top, bottom) scroll at the file's tile and speed
//   and are tinted by the cloud colour rings (alpha = cloud cover per ring). Sun disk + glow + flare, moon over its
//   dark backing disk, and stars, using the client's textures.

uniform vec4 canopy_zenith : source_color;
uniform vec4 canopy_east[4];
uniform vec4 canopy_west[4];
uniform vec4 canopy_nadir : source_color;
uniform vec4 cloud_zenith : source_color;
uniform vec4 cloud_east[4];
uniform vec4 cloud_west[4];

uniform sampler2D cloud_top : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_bot : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_top2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_bot2 : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 cloud_tiles = vec4(4.0, 5.0, 4.0, 3.0);      // top, bot, top2, bot2
uniform vec4 cloud_speeds = vec4(4.0, 6.0, 5.0, 9.0);     // client values; the client multiplies by 0.001
uniform float storm = 0.0;                                // 0 clear .. 1 full storm: blends to the *2 cloud layers
uniform float cloud_time = 0.0;

uniform sampler2D sun_disk_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D sun_glow_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D sun_flare_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D moon_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D moonback_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D star_tex : source_color, filter_linear, repeat_disable;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec4 sun_disk_color : source_color;
uniform vec4 sun_glow_color : source_color;
uniform vec4 sun_flare_color : source_color;
uniform vec4 moon_color : source_color;
uniform vec4 moonback_color : source_color;
uniform vec3 sizes = vec3(15.0, 175.0, 175.0);           // sun disk, glow, flare scale (at distance 1000)
uniform float moon_size = 15.0;
uniform float star_scale = 2.5;
uniform float star_density = 700.0;
uniform float star_visibility = 0.0;

vec4 ring_color(vec4 zenith, vec4 east[4], vec4 west[4], vec3 dir) {
	// elevation 90 -> 0 degrees spans zenith, ring1 .. ring4; east/west by the side of the sky
	float elev = degrees(asin(clamp(dir.y, -1.0, 1.0)));
	float t = clamp((90.0 - elev) / 22.5, 0.0, 4.0);     // 0 zenith, 1..4 rings
	float side = clamp(dir.x * 0.5 + 0.5, 0.0, 1.0);     // +x is east
	vec4 e = zenith;
	vec4 w = zenith;
	int i = int(floor(t));
	float f = fract(t);
	vec4 e0 = i == 0 ? zenith : east[max(i - 1, 0)];
	vec4 w0 = i == 0 ? zenith : west[max(i - 1, 0)];
	vec4 e1 = east[min(i, 3)];
	vec4 w1 = west[min(i, 3)];
	if (t >= 4.0) {
		e0 = east[3]; e1 = east[3]; w0 = west[3]; w1 = west[3];
	}
	e = mix(e0, e1, f);
	w = mix(w0, w1, f);
	return mix(w, e, side);
}

vec4 sprite(sampler2D tex, vec3 dir, vec3 center, float size) {
	// a camera-facing billboard on the sky sphere, size in the client's units at distance 1000
	vec3 c = normalize(center);
	float d = dot(dir, c);
	if (d <= 0.0) return vec4(0.0);
	vec3 up = abs(c.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, c));
	vec3 up2 = cross(c, right);
	vec3 p = dir / d - c;                                // point on the plane tangent to the sky at the centre
	vec2 uv = vec2(dot(p, right), dot(p, up2)) * (1000.0 / size) * 0.5 + 0.5;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return vec4(0.0);
	return texture(tex, uv);
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 col;
	if (dir.y >= 0.0) {
		col = ring_color(canopy_zenith, canopy_east, canopy_west, dir).rgb;
	} else {
		col = mix(canopy_east[3].rgb * 0.5 + canopy_west[3].rgb * 0.5, canopy_nadir.rgb, clamp(-dir.y * 3.0, 0.0, 1.0));
	}

	// stars, faded in at night under clear skies
	if (star_visibility > 0.001 && dir.y > 0.0) {
		// grid sized so the expected star count matches the file's max_stars: a unit sphere through a grid of
		// `cells` per unit crosses about 2*pi*1.5*cells^2 cells on the visible half, and half of them hold a star
		// (the first version used sqrt(max_stars)*2 and showed ~12x too many, owner 2026-10-09)
		float cells = sqrt(star_density / 4.7);
		vec3 g = floor(dir * cells);
		float h = hash(g);
		if (h > 0.5) {
			vec3 star = normalize((g + vec3(hash(g + 1.3), hash(g + 2.7), hash(g + 5.1))) / cells);
			vec4 s = sprite(star_tex, dir, star, star_scale);
			col += s.rgb * s.a * star_visibility * (0.5 + h * 0.5);
		}
	}

	// moon over its dark backing disk
	vec4 mb = sprite(moonback_tex, dir, moon_dir, moon_size);
	col = mix(col, moonback_color.rgb * mb.rgb, mb.a * moonback_color.a * star_visibility);
	vec4 mn = sprite(moon_tex, dir, moon_dir, moon_size);
	col += mn.rgb * moon_color.rgb * mn.a * moon_color.a * max(star_visibility, 0.15);

	// sun glow, flare and disk (additive, alpha = strength from the file)
	vec4 gl = sprite(sun_glow_tex, dir, sun_dir, sizes.y);
	col += gl.rgb * sun_glow_color.rgb * gl.a * sun_glow_color.a;
	vec4 fl = sprite(sun_flare_tex, dir, sun_dir, sizes.z);
	col += fl.rgb * sun_flare_color.rgb * fl.a * sun_flare_color.a;
	vec4 sd = sprite(sun_disk_tex, dir, sun_dir, sizes.x);
	col += sd.rgb * sun_disk_color.rgb * sd.a * sun_disk_color.a;

	// clouds: two layers projected on a flat ceiling, tinted and faded by the cloud colour rings
	if (dir.y > 0.0) {
		vec2 base = dir.xz / (dir.y + 0.12);
		vec4 cc = ring_color(cloud_zenith, cloud_east, cloud_west, dir);
		float t = cloud_time * 0.001;
		vec4 top = mix(texture(cloud_top, base / cloud_tiles.x * 0.5 + vec2(t * cloud_speeds.x, 0.0)),
				texture(cloud_top2, base / cloud_tiles.z * 0.5 + vec2(t * cloud_speeds.z, 0.0)), storm);
		vec4 bot = mix(texture(cloud_bot, base / cloud_tiles.y * 0.5 + vec2(t * cloud_speeds.y, t * cloud_speeds.y * 0.3)),
				texture(cloud_bot2, base / cloud_tiles.w * 0.5 + vec2(t * cloud_speeds.w, t * cloud_speeds.w * 0.3)), storm);
		float a_top = dot(top.rgb, vec3(0.333)) * top.a * cc.a;
		float a_bot = dot(bot.rgb, vec3(0.333)) * bot.a * cc.a;
		col = mix(col, cc.rgb * top.rgb * 1.2, clamp(a_top, 0.0, 1.0));
		col = mix(col, cc.rgb * bot.rgb * 1.2, clamp(a_bot, 0.0, 1.0));
	}
	COLOR = col;
}
