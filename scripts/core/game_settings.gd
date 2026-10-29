extends Node
class_name GameSettings

## Persistent player settings. The service owns values only; callers decide
## when to apply them to the player and traffic systems.

signal settings_changed

const DEFAULT_MASTER_VOLUME := 0.8
const DEFAULT_MOUSE_SENSITIVITY := 0.0025
const DEFAULT_TRAFFIC_DENSITY := 3.0
const DEFAULT_FULLSCREEN := false
const SETTINGS_VERSION := 3

const SECTION_META := "meta"
const SECTION_AUDIO := "audio"
const SECTION_CONTROLS := "controls"
const SECTION_TRAFFIC := "traffic"
const SECTION_DISPLAY := "display"

@export var config_path := "user://settings.cfg"

var master_volume := DEFAULT_MASTER_VOLUME
var mouse_sensitivity := DEFAULT_MOUSE_SENSITIVITY
var traffic_density := DEFAULT_TRAFFIC_DENSITY
var fullscreen := DEFAULT_FULLSCREEN


func load_settings() -> bool:
	var config := ConfigFile.new()
	var error := config.load(config_path)
	if error != OK:
		reset_to_defaults(false)
		return false
	master_volume = clampf(
		float(config.get_value(SECTION_AUDIO, "master_volume", DEFAULT_MASTER_VOLUME)),
		0.0,
		1.0
	)
	var saved_version := int(config.get_value(SECTION_META, "version", 0))
	mouse_sensitivity = clampf(
		float(config.get_value(
			SECTION_CONTROLS,
			"mouse_sensitivity",
			DEFAULT_MOUSE_SENSITIVITY
		)),
		0.0005,
		0.01
	)
	traffic_density = clampf(
		float(config.get_value(
			SECTION_TRAFFIC,
			"density",
			DEFAULT_TRAFFIC_DENSITY
		)),
		0.1,
		3.0
	)
	# Older saves must adopt the denser traffic default once. Explicit choices
	# made after this migration are preserved on subsequent launches.
	if saved_version < SETTINGS_VERSION:
		traffic_density = maxf(traffic_density, DEFAULT_TRAFFIC_DENSITY)
	fullscreen = bool(config.get_value(
		SECTION_DISPLAY,
		"fullscreen",
		DEFAULT_FULLSCREEN
	))
	if saved_version < SETTINGS_VERSION:
		save_settings()
	settings_changed.emit()
	return true


func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION_META, "version", SETTINGS_VERSION)
	config.set_value(SECTION_AUDIO, "master_volume", master_volume)
	config.set_value(SECTION_CONTROLS, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION_TRAFFIC, "density", traffic_density)
	config.set_value(SECTION_DISPLAY, "fullscreen", fullscreen)
	return config.save(config_path) == OK


func reset_to_defaults(notify := true) -> void:
	master_volume = DEFAULT_MASTER_VOLUME
	mouse_sensitivity = DEFAULT_MOUSE_SENSITIVITY
	traffic_density = DEFAULT_TRAFFIC_DENSITY
	fullscreen = DEFAULT_FULLSCREEN
	if notify:
		settings_changed.emit()


func set_master_volume(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(master_volume, next):
		return
	master_volume = next
	settings_changed.emit()


func set_mouse_sensitivity(value: float) -> void:
	var next := clampf(value, 0.0005, 0.01)
	if is_equal_approx(mouse_sensitivity, next):
		return
	mouse_sensitivity = next
	settings_changed.emit()


func set_traffic_density(value: float) -> void:
	var next := clampf(value, 0.1, 3.0)
	if is_equal_approx(traffic_density, next):
		return
	traffic_density = next
	settings_changed.emit()


func set_fullscreen(value: bool) -> void:
	if fullscreen == value:
		return
	fullscreen = value
	settings_changed.emit()


func apply_to(
	player: PlayerController = null,
	traffic: TrafficSpawner = null
) -> void:
	var master_index := AudioServer.get_bus_index("Master")
	if master_index >= 0:
		AudioServer.set_bus_volume_db(master_index, get_master_volume_db())
	if player != null:
		player.mouse_sensitivity = mouse_sensitivity
	if traffic != null:
		traffic.traffic_density = traffic_density
		if traffic.network != null and player != null:
			traffic.update_traffic(player.global_position, true)
	if DisplayServer.get_name() != "headless":
		var mode := (
			DisplayServer.WINDOW_MODE_FULLSCREEN
			if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED
		)
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)


func get_master_volume_db() -> float:
	return linear_to_db(maxf(master_volume, 0.0001))
