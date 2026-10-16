extends SceneTree
## Pipeline step (owner 2026-10-10: framerate low for a minute or two after loading): the game's PNG textures -> GPU
## block-compressed images with their mipmaps (BC7 / BPTC, 1 byte per pixel instead of 4 and no decode at load).
## Each <dir>/<name>.png gets <dir>_bc/<name>.res (an Image resource, loaded with ResourceLoader). Skips files that
## are up to date.
##   Godot --headless --path godot -s res://tools/compress_textures.gd -- res://content/characters/fig3_textures/x4plus [--limit=N] [--shard=i/n]


func _initialize() -> void:
	var limit := 1 << 30
	var shard := 0
	var shards := 1
	var dirs := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--limit="):
			limit = int(a.substr(8))
		elif a.begins_with("--shard="):                  # --shard=i/n: every n-th file from i (parallel runs)
			shard = int(a.substr(8).get_slice("/", 0))
			shards = int(a.substr(8).get_slice("/", 1))
		else:
			dirs.append(a)
	var done := 0
	var skipped := 0
	var t0 := Time.get_ticks_msec()
	for d in dirs:
		var out_dir := String(d).trim_suffix("/") + "_bc"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		var files := DirAccess.get_files_at(d)
		for fi in files.size():
			var f := files[fi]
			if not f.to_lower().ends_with(".png") or done >= limit or fi % shards != shard:
				continue
			var src := String(d).path_join(f)
			var dst := out_dir.path_join(f.get_basename() + ".res")
			if FileAccess.file_exists(dst) and FileAccess.get_modified_time(dst) >= FileAccess.get_modified_time(src):
				skipped += 1
				continue
			var img := Image.load_from_file(ProjectSettings.globalize_path(src))
			if img == null:
				printerr("bad png ", src)
				continue
			img.generate_mipmaps()
			img.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_SRGB)
			ResourceSaver.save(img, dst, ResourceSaver.FLAG_COMPRESS)
			done += 1
	print("[bc] compressed %d, up to date %d, %.1f s" % [done, skipped, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
