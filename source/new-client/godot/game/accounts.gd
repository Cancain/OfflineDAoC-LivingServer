class_name Accounts
extends RefCounted
## Local accounts for the offline game (no server): user://accounts.cfg keeps each account's salted, iterated
## SHA-256 password hash (never the password). user://login.cfg remembers the login screen's "Save username" /
## "Save password" choices; it is written encrypted with a key tied to this machine, so a saved password isn't
## readable as plain text on disk.

const ACCOUNTS_PATH := "user://accounts.cfg"
const LOGIN_PATH := "user://login.cfg"
const HASH_ROUNDS := 4096
const NAME_MIN := 3
const NAME_MAX := 20
const PASSWORD_MIN := 4

static var account := ""                     # who is logged in this session


static func _hash(password: String, salt: String) -> String:
	var digest := (salt + password).to_utf8_buffer()
	for i in HASH_ROUNDS:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(digest)
		ctx.update(salt.to_utf8_buffer())
		digest = ctx.finish()
	return digest.hex_encode()


static func _section(username: String) -> String:
	return "account_" + username.to_lower()


static func exists(username: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(ACCOUNTS_PATH)
	return cfg.has_section(_section(username))


## "" on success, else the reason shown to the player.
static func create(username: String, password: String, confirm: String) -> String:
	username = username.strip_edges()
	if username.length() < NAME_MIN or username.length() > NAME_MAX:
		return "Account names are %d to %d characters." % [NAME_MIN, NAME_MAX]
	var re := RegEx.create_from_string("^[A-Za-z0-9]+$")
	if re.search(username) == null:
		return "Account names use letters and numbers only."
	if password.length() < PASSWORD_MIN:
		return "Passwords need at least %d characters." % PASSWORD_MIN
	if password != confirm:
		return "The passwords don't match."
	var cfg := ConfigFile.new()
	cfg.load(ACCOUNTS_PATH)
	if cfg.has_section(_section(username)):
		return "That account name is taken."
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	cfg.set_value(_section(username), "name", username)
	cfg.set_value(_section(username), "salt", salt)
	cfg.set_value(_section(username), "hash", _hash(password, salt))
	cfg.set_value(_section(username), "created", Time.get_datetime_string_from_system())
	cfg.set_value(_section(username), "welcome_pending", true)
	if cfg.save(ACCOUNTS_PATH) != OK:
		return "Could not save the account."
	return ""


## "" on success, else the reason shown to the player.
static func login(username: String, password: String) -> String:
	var cfg := ConfigFile.new()
	cfg.load(ACCOUNTS_PATH)
	var sec := _section(username.strip_edges())
	if not cfg.has_section(sec):
		return "No account by that name. Create one first."
	if _hash(password, String(cfg.get_value(sec, "salt", ""))) != String(cfg.get_value(sec, "hash", "")):
		return "Wrong password."
	account = String(cfg.get_value(sec, "name", username))
	cfg.set_value(sec, "last_login", Time.get_datetime_string_from_system())
	cfg.save(ACCOUNTS_PATH)
	return ""


static func _key() -> String:
	return "mmoengine-login-" + OS.get_unique_id()


## {save_username, save_password, username, password}
static func saved_login() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load_encrypted_pass(LOGIN_PATH, _key()) != OK:
		return {"save_username": false, "save_password": false, "username": "", "password": ""}
	return {"save_username": bool(cfg.get_value("login", "save_username", false)),
			"save_password": bool(cfg.get_value("login", "save_password", false)),
			"username": String(cfg.get_value("login", "username", "")),
			"password": String(cfg.get_value("login", "password", ""))}


static func remember(username: String, password: String, save_username: bool, save_password: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("login", "save_username", save_username)
	cfg.set_value("login", "save_password", save_password)
	cfg.set_value("login", "username", username if save_username or save_password else "")
	cfg.set_value("login", "password", password if save_password else "")
	cfg.save_encrypted_pass(LOGIN_PATH, _key())


## The one-time welcome box (bot plan phase 2): due once for an account created from now on, never for older ones.
static func welcome_due(username: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(ACCOUNTS_PATH)
	return bool(cfg.get_value(_section(username), "welcome_pending", false))


static func welcome_done(username: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(ACCOUNTS_PATH)
	if cfg.has_section(_section(username)):
		cfg.set_value(_section(username), "welcome_pending", false)
		cfg.save(ACCOUNTS_PATH)
