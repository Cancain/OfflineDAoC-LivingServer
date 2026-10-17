class_name GroundClutter
extends Node3D
## DAoC ground clutter: the grass tufts, flowers, reeds and pebbles scattered over the terrain (not fixtures).
## zone.json "clutter" (from pipeline/build_zone.py) carries the realm's grass table (zones/textures/grass_<realm>.csv)
## and sprite sheet; grassmap (value / 10 = group) and densemap (0-255) pick what grows where per 256-unit cell.
## Chunks are built around the viewer with a fixed seed per cell, so every tuft stays where it was.
## Seamless zones: each loaded zone has its own clutter as a child of its ZoneLoader, working in that zone's metres
## (a neighbour's grass grows up to the border from its side).

const CHUNK_M := 32.0
const RADIUS_M := 72.0
const MAX_PER_CELL := 70.0            # tufts in a 6.4 m cell at full density (matched to the client by eye)
const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float sway = 0.06;
uniform float fade_start = 48.0;
uniform float fade_end = 70.0;
varying float fade;
void vertex() {
	// UV2.x = 1 on the top edge of a card: only those vertices move in the wind
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.7 + wp.x * 0.35 + wp.z * 0.27;
	VERTEX.x += sin(t) * sway * UV2.x;
	VERTEX.z += cos(t * 0.8) * sway * 0.6 * UV2.x;
	fade = 1.0 - smoothstep(fade_start, fade_end, length(wp - CAMERA_POSITION_WORLD));
}
void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a * fade;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;   // lit like the ground it grows from
}
"""

## Options > VIDEO grass distance / density (Graphics; the defaults 72 m and full are the values above)
static var radius_m := RADIUS_M
static var density_mult := 1.0

var zone: ZoneLoader
var viewer: Node3D
var _info: Dictionary
var _groups := {}                    # group -> [[item, cumulative chance]], total
var _grass: Image
var _dense: Image
var _material: ShaderMaterial
var _chunks := {}                    # Vector2i -> MeshInstance3D
var _atlas_size := Vector2(512, 512)


func setup(z: ZoneLoader, follow: Node3D) -> bool:
	zone = z
	var c = z.info.get("clutter")
	_info = c if c is Dictionary else {}                  # null in zones with no grass (Uppland)
	if _info.is_empty():
		return false
	_grass = Image.load_from_file(z.dir.path_join(_info.grassmap)) if FileAccess.file_exists(z.dir.path_join(_info.grassmap)) else null
	_dense = Image.load_from_file(z.dir.path_join(_info.densemap)) if FileAccess.file_exists(z.dir.path_join(_info.densemap)) else null
	if _grass == null or _dense == null:                  # listed but not built (City of Camelot): no grass
		return false
	# (it follows you only once it knows the zone grows grass: a zone without any - a city, Uppland - is freed by the
	# caller, and until then it drew nothing from maps that don't exist)
	viewer = follow
	_atlas_size = Vector2(_info.atlas_size[0], _info.atlas_size[1])
	for item in _info.items:
		var g := int(item.group)
		if not _groups.has(g):
			_groups[g] = {"items": [], "total": 0.0}
		_groups[g].total += float(item.chance)
		_groups[g].items.append([item, _groups[g].total])
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_set_fade()
	refresh_textures()
	return true


## The grass reach / density changed: the fade follows the reach (48 / 70 m at 72), the tufts are planted again.
func apply_settings() -> void:
	_set_fade()
	for c in _chunks.keys():
		_chunks[c].queue_free()
	_chunks.clear()


func _set_fade() -> void:
	if _material:
		_material.set_shader_parameter("fade_start", radius_m * 48.0 / 72.0)
		_material.set_shader_parameter("fade_end", radius_m * 70.0 / 72.0)


func refresh_textures() -> void:
	_material.set_shader_parameter("atlas", zone.materials.texture(String(_info.atlas)))


func _process(_delta: float) -> void:
	if viewer == null:
		return
	var p := to_local(viewer.global_position) if is_inside_tree() else viewer.global_position
	var centre := Vector2i(floori(p.x / CHUNK_M), floori(p.z / CHUNK_M))
	var reach := ceili(radius_m / CHUNK_M)
	var wanted := {}
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c := centre + Vector2i(dx, dz)
			var mid := Vector2((c.x + 0.5) * CHUNK_M, (c.y + 0.5) * CHUNK_M)
			if mid.distance_to(Vector2(p.x, p.z)) < radius_m + CHUNK_M * 0.71:
				wanted[c] = true
	for c in _chunks.keys():
		if not wanted.has(c):
			_chunks[c].queue_free()
			_chunks.erase(c)
	var built := 0
	for c in wanted:
		if not _chunks.has(c) and built < 2:           # spread the work over frames
			_chunks[c] = _build_chunk(c)
			built += 1


func _cell_value(img: Image, x: float, z: float) -> int:
	var n := img.get_width()
	var px := clampi(int(x / float(zone.info.size_m) * n), 0, n - 1)
	var pz := clampi(int(z / float(zone.info.size_m) * n), 0, n - 1)
	return roundi(img.get_pixel(px, pz).r * 255.0)


func _build_chunk(c: Vector2i) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell_m := float(zone.info.cell_m)              # 6.4 m: one grassmap / densemap cell
	var x0 := c.x * CHUNK_M
	var z0 := c.y * CHUNK_M
	var cells := int(CHUNK_M / cell_m)
	var count := 0
	for cz in cells:
		for cx in cells:
			var wx := x0 + (cx + 0.5) * cell_m
			var wz := z0 + (cz + 0.5) * cell_m
			if wx < 0 or wz < 0 or wx >= zone.info.size_m or wz >= zone.info.size_m:
				continue
			var density := _cell_value(_dense, wx, wz) / 255.0
			var group := _cell_value(_grass, wx, wz) / 10
			if density <= 0.0 or not _groups.has(group):
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector2i(int(wx / cell_m), int(wz / cell_m)))
			var n := int(round(density * MAX_PER_CELL * density_mult * rng.randf_range(0.7, 1.3)))
			for k in n:
				var x := wx + rng.randf_range(-0.5, 0.5) * cell_m
				var z := wz + rng.randf_range(-0.5, 0.5) * cell_m
				var y := zone.height_at(x, z)
				if y < zone.water_level_at(x, z) - 0.3 and group != 5:
					continue                               # only the underwater group grows below the surface
				_add_tuft(st, _pick(group, rng), Vector3(x, y, z), rng)
				count += 1
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if count > 0:
		mi.mesh = st.commit()
		mi.material_override = _material
	add_child(mi)
	return mi


func _pick(group: int, rng: RandomNumberGenerator) -> Dictionary:
	var g: Dictionary = _groups[group]
	var r := rng.randf() * float(g.total)
	for pair in g.items:
		if r <= pair[1]:
			return pair[0]
	return g.items[-1][0]


func _add_tuft(st: SurfaceTool, item: Dictionary, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var s := 1.0 + rng.randf_range(-1.0, 1.0) * float(item.d_scale)
	var h := (float(item.height) + rng.randf() * float(item.d_height)) * s
	var l := (float(item.length) + rng.randf() * float(item.d_length)) * s
	var w := (float(item.width) + rng.randf() * float(item.d_width)) * s
	var rect: Array = item.rect                       # x1, x2, y1, y2 in sheet pixels
	var u0 := float(rect[0]) / _atlas_size.x
	var u1 := (float(rect[1]) + 1.0) / _atlas_size.x
	var v0 := float(rect[2]) / _atlas_size.y
	var v1 := (float(rect[3]) + 1.0) / _atlas_size.y
	var tint := Color(item.tint[0], item.tint[1], item.tint[2]) * rng.randf_range(0.85, 1.05)
	tint.a = 1.0
	var yaw := rng.randf() * TAU
	var shape := int(item.shape)
	if shape == 2 or shape == 4:
		# lying flat on the ground (pebbles, fallen leaves, lily pads)
		var a := Vector3(cos(yaw), 0, sin(yaw)) * l * 0.5
		var b := Vector3(-sin(yaw), 0, cos(yaw)) * maxf(w, l * 0.6) * 0.5
		var lift := Vector3(0, 0.02, 0)
		_quad(st, pos - a - b + lift, pos + a - b + lift, pos + a + b + lift, pos - a + b + lift, u0, u1, v0, v1, tint, false)
		return
	# upright cards crossed at right angles, bottom edge on the ground
	for k in 2:
		var ang := yaw + k * PI * 0.5
		var side := Vector3(cos(ang), 0, sin(ang)) * l * 0.5
		var top := Vector3(0, h, 0)
		_quad(st, pos - side, pos + side, pos + side + top, pos - side + top, u0, u1, v1, v0, tint, true)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u0: float, u1: float, vb: float, vt: float,
		tint: Color, upright: bool) -> void:
	var verts := [a, b, c, a, c, d]
	var uvs := [Vector2(u0, vb), Vector2(u1, vb), Vector2(u1, vt), Vector2(u0, vb), Vector2(u1, vt), Vector2(u0, vt)]
	var top := [0.0, 0.0, 1.0, 0.0, 1.0, 1.0]
	for i in 6:
		st.set_color(tint)
		st.set_uv(uvs[i])
		st.set_uv2(Vector2(top[i] if upright else 0.0, 0.0))
		st.set_normal(Vector3.UP)
		st.add_vertex(verts[i])
