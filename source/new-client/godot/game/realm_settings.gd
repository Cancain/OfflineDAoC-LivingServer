class_name RealmSettings
extends RefCounted
## Server-side settings for the offline realm, set on the character screen's REALM OPTIONS (owner 2026-10-09: "that
## will be where the future bot controls and server settings like xp rate will go"). Saved in user://realm.cfg.
## Defaults are the old OfflineDAoC server's (ServerProperty xp_rate = 1).
## Two experience rates (owner 2026-10-10, bot plan phase 1): you and your companions, and the gamebots - each
## 1x / 3x / 5x / 10x / 25x / 50x (an older saved 2x / 4x reads as the next rate below).

const PATH := "user://realm.cfg"
const XP_RATES := [1, 3, 5, 10, 25, 50]

static var _cfg: ConfigFile


static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg


## You and your companions.
static func xp_rate() -> int:
	return _snap(int(_load().get_value("server", "xp_rate", 1)))


static func set_xp_rate(v: int) -> void:
	_load().set_value("server", "xp_rate", v)
	_cfg.save(PATH)


## The gamebots (the world host reads it).
static func bot_xp_rate() -> int:
	return _snap(int(_load().get_value("server", "bot_xp_rate", 1)))


static func set_bot_xp_rate(v: int) -> void:
	_load().set_value("server", "bot_xp_rate", v)
	_cfg.save(PATH)


static func _snap(v: int) -> int:
	var best := 1
	for r in XP_RATES:
		if r <= v:
			best = r
	return best


## The world host (bot plan phase 3) writes the unix time into this file every few seconds while it runs: a fresh
## heartbeat = MMOENGINE ONLINE on the login screen. No host yet = always offline.
const HOST_HEARTBEAT := "user://world_host.heartbeat"


static func host_online() -> bool:
	if not FileAccess.file_exists(HOST_HEARTBEAT):
		return false
	var t := FileAccess.get_file_as_string(HOST_HEARTBEAT).strip_edges().to_float()
	return Time.get_unix_time_from_system() - t < 10.0


# --- the bot world (bot plan phase 2: REALM OPTIONS' Bot Roster and World Settings tabs) ----------------------------

const DEFAULT_TOTAL_BOTS := 3000             # owner 2026-10-11: 1,000 / 1,000 / 1,000 by default (the 1.0-speed goal)
const TESTED_BOTS := 3000                    # more asks "are you sure? untested" (the phase 0 performance target)
const REALMS := ["alb", "mid", "hib"]        # the realm split's order: Albion, Midgard, Hibernia
## The bots the world host has made, written by the host (phase 3): [{name, realm, class, level, spec, zone, goal,
## state}] - the Bot Roster tab's live list.
const BOT_ROSTER_PATH := "user://world/bot_roster.json"


## How many bots the permanent roster holds (the world host creates them over time until it is reached).
static func total_bots() -> int:
	return maxi(0, int(_load().get_value("bots", "total", DEFAULT_TOTAL_BOTS)))


static func set_total_bots(v: int) -> void:
	_load().set_value("bots", "total", maxi(0, v))
	_cfg.save(PATH)


## The realm split in percent [Albion, Midgard, Hibernia] - an even third each unless set.
static func realm_split() -> Array:
	var v = _load().get_value("bots", "split", [])
	if v is Array and v.size() == 3:
		return [float(v[0]), float(v[1]), float(v[2])]
	return [100.0 / 3.0, 100.0 / 3.0, 100.0 / 3.0]


static func set_realm_split(v: Array) -> void:
	_load().set_value("bots", "split", [float(v[0]), float(v[1]), float(v[2])])
	_cfg.save(PATH)


static func even_split() -> void:
	_load().set_value("bots", "split", [])
	_cfg.save(PATH)


## The bots each realm gets for a total: the split's shares, rounded so they add up exactly (largest remainder) -
## 1,500 at the even split = 500 / 500 / 500.
static func realm_counts(total: int, split: Array = []) -> Array:
	var sp: Array = split if split.size() == 3 else realm_split()
	var sum := maxf(0.0001, float(sp[0]) + float(sp[1]) + float(sp[2]))
	var exact := []
	var out := []
	var given := 0
	for i in 3:
		exact.append(total * float(sp[i]) / sum)
		out.append(int(floor(exact[i] + 1e-6)))
		given += out[i]
	var order := [0, 1, 2]
	order.sort_custom(func(a, b): return exact[a] - out[a] > exact[b] - out[b])
	for k in total - given:
		out[order[k % 3]] += 1
	return out


## "KEEP THE BOTS PLAYING WHILE THE GAME IS CLOSED" (owner 2026-10-10: OFF by default - opt in): with it on, MMOEngine
## stays in the tray after the game closes and the bots keep playing while you are offline.
static func background_host() -> bool:
	return bool(_load().get_value("bots", "background", false))


static func set_background_host(on: bool) -> void:
	_load().set_value("bots", "background", on)
	_cfg.save(PATH)


## Forget the cached settings so the next read sees what another process saved (the world host re-reads REALM
## OPTIONS while it runs).
static func reload() -> void:
	_cfg = null


## The game writes the unix time here every few seconds while it runs; the world host (started by the game with
## the background setting off) stops once this goes stale.
const GAME_HEARTBEAT := "user://game.heartbeat"
const WORLD_DIR := "user://world"
const BOTS_PATH := "user://world/bots.json"     # the permanent roster: one character dictionary per bot (+ "bot")
