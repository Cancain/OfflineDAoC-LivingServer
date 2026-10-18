class_name Emblems
extends RefCounted
## Guild emblems as the client draws them (owner 2026-10-17: the server's gamebot guilds - their cloaks and shields
## carry the guild emblem; pipeline/build_emblems.py -> content/emblems). The emblem number: logo << 9 | pattern << 7 |
## primary << 3 | secondary (the logo's 0x10000 bit: insignia 128-255). game.dll 0x481606 builds, for each colour pair
## (primary * 8 + secondary), four 2 x 4 pixel pattern textures from fixed masks (primary where the mask is 0); items
## draw pattern (UV set 0) x their own texture x 2 x the logo's red (0x481901 - the logo black on white, clamped); the
## Catacombs cloaks the same in their pixel shaders ($baseTexture x $detailTexture x 2 x $insigniaTexture).r).
## The products are the client's, in its gamma space; the shaders turn the result to linear at the end.

const DIR := "res://content/emblems"

static var _data := {}
static var _patterns := {}                      # pattern * 128 + colour pair (0x200 none) -> ImageTexture
static var _logos := {}                         # logo id -> Texture2D (null: none)
static var _surfaces := {}                      # a weapon texture path -> Texture2D
static var _shield_shader: Shader


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/emblems.json")) \
				if FileAccess.file_exists(DIR + "/emblems.json") else null
		_data = parsed if parsed is Dictionary else {"primary": [], "secondary": [], "masks": [], "logos": {}}
	return _data


## {logo, pattern, primary, secondary} of an emblem number.
static func decode(emblem: int) -> Dictionary:
	return {"logo": emblem >> 9, "pattern": (emblem >> 7) & 3, "primary": (emblem >> 3) & 15, "secondary": emblem & 7}


static func encode(logo: int, pattern: int, primary: int, secondary: int) -> int:
	return (logo << 9) | ((pattern & 3) << 7) | ((primary & 15) << 3) | (secondary & 7)


## A palette colour: set "primary" (16 dark ones) or "secondary" (8 light ones) - patterns.csv.
static func color(set_name: String, i: int) -> Color:
	var list: Array = data().get(set_name, [])
	if i < 0 or i >= list.size() or list[i] == null:
		return Color(0.5, 0.5, 0.5)
	var c: Array = list[i].rgb
	return Color8(int(c[0]), int(c[1]), int(c[2]))


static func color_name(set_name: String, i: int) -> String:
	var list: Array = data().get(set_name, [])
	return String(list[i].name) if i >= 0 and i < list.size() and list[i] != null else ""


## The 2 x 4 pattern texture of an emblem (0: the client's flat 0x80 grey - the item's own look).
static func pattern_texture(emblem: int) -> Texture2D:
	var d := decode(emblem)
	var key := 0x200 if emblem <= 0 or d.logo == 0 else int(d.pattern) * 128 + int(d.primary) * 8 + int(d.secondary)
	if not _patterns.has(key):
		var img := Image.create(2, 4, false, Image.FORMAT_RGB8)
		if key == 0x200:
			img.fill(Color8(0x80, 0x80, 0x80))
		else:
			var mask: Array = (data().masks as Array)[int(d.pattern)] if (data().masks as Array).size() > int(d.pattern) \
					else [0, 0, 0, 0, 0, 0, 0, 0]
			var a := color("primary", int(d.primary))
			var b := color("secondary", int(d.secondary))
			for i in 8:
				img.set_pixel(i % 2, i / 2, b if int(mask[i]) == 1 else a)
		_patterns[key] = ImageTexture.create_from_image(img)
	return _patterns[key]


## The logo's picture (insignia.csv), null for none.
static func logo_texture(logo: int) -> Texture2D:
	if logo <= 0:
		return null
	if not _logos.has(logo):
		var info: Dictionary = (data().logos as Dictionary).get(str(logo), {})
		var path := "%s/insignia/%s.png" % [DIR, String(info.get("file", ""))]
		var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if info.has("file") and FileAccess.file_exists(path) else null
		if img:
			img.generate_mipmaps()
		_logos[logo] = ImageTexture.create_from_image(img) if img else null
	return _logos[logo]


static func logo_name(logo: int) -> String:
	return String((data().logos as Dictionary).get(str(logo), {}).get("name", ""))


static func logo_ids() -> Array:
	var out := []
	for k in (data().logos as Dictionary).keys():
		out.append(int(k))
	out.sort()
	return out


static func _surface(path: String) -> Texture2D:
	if not _surfaces.has(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
		if img:
			img.generate_mipmaps()
		_surfaces[path] = ImageTexture.create_from_image(img) if img else null
	return _surfaces[path]


## An emblem shield's material: its surface texture (its own UVs, the glTF's UV) under the guild emblem - the pattern on
## the NIF's set 0 (TEXCOORD_3 = CUSTOM0.zw, pipeline/build_weapons.py) and the logo on set 1 (UV2).
static func shield_material(surface_path: String, emblem: int) -> ShaderMaterial:
	if _shield_shader == null:
		_shield_shader = Shader.new()
		_shield_shader.code = """shader_type spatial;
render_mode cull_back;
uniform sampler2D surface_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pattern_tex : filter_linear, repeat_enable;
uniform sampler2D logo_tex : filter_linear_mipmap, repeat_disable;
uniform bool has_logo = false;
uniform vec3 tint = vec3(1.0);
varying vec2 pattern_uv;
void vertex() {
	pattern_uv = CUSTOM0.zw;
}
void fragment() {
	vec3 s = texture(surface_tex, UV).rgb;
	vec3 p = texture(pattern_tex, pattern_uv).rgb;
	float l = has_logo ? texture(logo_tex, UV2).r : 1.0;
	vec3 c = clamp(s * p * 2.0 * l, 0.0, 1.0) * tint;
	ALBEDO = pow(c, vec3(2.2));
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shield_shader
	m.set_shader_parameter("surface_tex", _surface(surface_path))
	m.set_shader_parameter("pattern_tex", pattern_texture(emblem))
	var logo := logo_texture(decode(emblem).logo) if emblem > 0 else null
	m.set_shader_parameter("logo_tex", logo)
	m.set_shader_parameter("has_logo", logo != null)
	return m
