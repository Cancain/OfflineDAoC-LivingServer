class_name ClassicFont
extends RefCounted
## The 1.65 client's bitmap fonts (pipeline/build_fonts.py -> content/ui/fonts/classic) as Godot fonts: white glyphs,
## tinted by whatever draws them (name plates: light blue for friendly NPCs, con colours for monsters). Pixel-exact:
## draw with nearest filtering.

const DIR := "res://content/ui/fonts/classic"
static var _fonts := {}


static func get_font(name := "14font") -> FontFile:
	if _fonts.has(name):
		return _fonts[name]
	var meta = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [DIR, name]))
	var img := Image.load_from_file(ProjectSettings.globalize_path("%s/%s.png" % [DIR, name]))
	if not (meta is Dictionary) or img == null:
		_fonts[name] = null
		return null
	var h := int(meta.height)
	var f := FontFile.new()
	f.fixed_size = h
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.generate_mipmaps = false
	var size := Vector2i(h, 0)
	f.set_texture_image(0, size, 0, img)
	f.set_cache_ascent(0, h, int(h * 0.8))
	f.set_cache_descent(0, h, h - int(h * 0.8))
	for key in meta.glyphs:
		var code := int(key)
		var g: Array = meta.glyphs[key]
		f.set_glyph_advance(0, h, code, Vector2(int(g[1]) + 1, 0))
		f.set_glyph_offset(0, size, code, Vector2(0, -int(h * 0.8)))
		f.set_glyph_size(0, size, code, Vector2(int(g[1]), h))
		f.set_glyph_uv_rect(0, size, code, Rect2(int(g[0]), 0, int(g[1]), h))
		f.set_glyph_texture_idx(0, size, code, 0)
	f.set_glyph_advance(0, h, 32, Vector2(int(meta.space), 0))
	_fonts[name] = f
	return f
