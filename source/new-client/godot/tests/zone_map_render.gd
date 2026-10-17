extends Node
## Build step (not a test): the zone's map picture. The 1.65 client has no zone map art, so the map is the zone itself
## seen straight down - an orthographic render of the real terrain, water, buildings and trees at noon, no fog, no
## people - saved as content/zones/zoneNNN/map.png (2048 x 2048, north up). The Map window (M) shows it.
##   Godot --path godot -- --skip-login --zone=200 --probe=zone_map_render --mute
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var zone: ZoneLoader = viewer.zone
	var size := float(zone.info.size_m)
	if viewer.sky:
		viewer.sky.set_hour(12.0)
		viewer.sky.time_scale = 0.0
	if viewer.sky and viewer.sky.environment:
		viewer.sky.environment.fog_enabled = false
		viewer.sky.environment.volumetric_fog_enabled = false
	if viewer.ui:
		viewer.ui.visible = false
	if viewer.npcs:
		viewer.npcs.visible = false
	viewer.player.visible = false
	for g in get_tree().current_scene.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D                  # no view-distance culling from the high camera
		gi.visibility_range_end = 0.0
		gi.visibility_range_begin = 0.0
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 2048)
	vp.world_3d = get_viewport().world_3d
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.near = 1.0
	cam.far = 6000.0
	vp.add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3(0, 0, -1)), Vector3(size * 0.5, 3000.0, size * 0.5))
	cam.current = true
	for i in 90:                                           # streaming chunks / clutter settle
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var out := ProjectSettings.globalize_path(zone.dir.path_join("map.png"))
	img.save_png(out)
	print("[map] saved ", out, " ", img.get_size(), " zone ", size, " m")
	get_tree().quit()
