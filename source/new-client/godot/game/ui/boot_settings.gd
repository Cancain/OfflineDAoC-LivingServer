extends Node
## Autoload "BootSettings": applies the player's saved display settings (window mode, resolution, frame cap) the
## moment the game starts, before the login screen - they used to apply only once the world loaded, so the game
## opened windowed and switched on entering (owner 2026-10-09). Test runs (--ui-test, --shots ...) are left alone so
## they stay in their own window. Options > VIDEO applies changes through apply_display() too.
## Modes: "windowed" (a normal window at the resolution), "borderless" (a borderless window at the resolution,
## centred - the owner's 1920 x 1080 borderless windowed), "fullscreen" (exclusive full screen).

const TEST_FLAGS := ["ui-test", "ui-shots", "shots", "probe", "tour", "bench", "pregame-shot", "login-shot"]

## Developer mode (owner 2026-10-13: "make sure debug mode like ctrl f12 is disabled on the godot release"): the debug
## text (Ctrl+F12), the bot inspector (Ctrl+F11) and the Ctrl+F1..F11 test keys work only with a dev_mode.txt file in
## the game folder (godot/ - the owner's working copy has one; a release package leaves it out) or --dev on the
## command line; test runs always. Everything else is the same either way.
static var dev: bool = _dev_mode()


static func _dev_mode() -> bool:
	if FileAccess.file_exists("res://dev_mode.txt"):
		return true
	for a in OS.get_cmdline_user_args():
		if a == "--dev" or a.trim_prefix("--").split("=")[0] in TEST_FLAGS:
			return true
	return false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.trim_prefix("--").split("=")[0] in TEST_FLAGS:
			return
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return
	if cfg.has_section_key("display", "fps_cap"):
		apply_fps(int(cfg.get_value("display", "fps_cap", 0)))
	if cfg.has_section_key("display", "window_mode") or cfg.has_section_key("display", "resolution"):
		apply_display(String(cfg.get_value("display", "window_mode", "windowed")), cfg.get_value("display", "resolution", []))


static func apply_fps(cap: int) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if cap < 0 else DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = maxi(cap, 0)


static func apply_display(mode: String, res) -> void:
	if mode == "fullscreen":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, mode == "borderless")
	var screen := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(screen) if mode == "windowed" else \
			Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
	var size := Vector2i(int(res[0]), int(res[1])) if res is Array and res.size() == 2 else DisplayServer.window_get_size()
	size = size.min(DisplayServer.screen_get_size(screen))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(area.position + (area.size - size) / 2)
