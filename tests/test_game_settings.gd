extends SceneTree

## GameSettings persistence, clamping, defaults, and live application.

var _failed := false
var _config_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_config_path = "res://.godot/test_game_settings_%d.cfg" % OS.get_process_id()
	_remove_config(false)

	var missing := GameSettings.new()
	missing.config_path = _config_path
	_expect(not missing.load_settings(), "missing config should report no saved settings")
	_check_defaults(missing, "missing config")
	missing.free()

	var legacy_config := ConfigFile.new()
	legacy_config.set_value(GameSettings.SECTION_AUDIO, "master_volume", 0.6)
	legacy_config.set_value(GameSettings.SECTION_TRAFFIC, "density", 1.0)
	_expect(
		legacy_config.save(_config_path) == OK,
		"legacy config should save to the temporary path"
	)
	var migrated := GameSettings.new()
	migrated.config_path = _config_path
	_expect(migrated.load_settings(), "legacy config should load")
	_expect(
		is_equal_approx(migrated.traffic_density, GameSettings.DEFAULT_TRAFFIC_DENSITY),
		"legacy 1.0x traffic density should migrate to the 3.0x default"
	)
	migrated.traffic_density = 1.5
	_expect(migrated.save_settings(), "a migrated setting should remain editable")
	var edited_migration := GameSettings.new()
	edited_migration.config_path = _config_path
	_expect(edited_migration.load_settings(), "edited migrated setting should reload")
	_expect(
		is_equal_approx(edited_migration.traffic_density, 1.5),
		"after migration, an explicit traffic density choice should be preserved"
	)
	edited_migration.free()
	var migrated_config := ConfigFile.new()
	_expect(
		migrated_config.load(_config_path) == OK,
		"migrated config should reload from disk"
	)
	_expect(
		int(migrated_config.get_value(GameSettings.SECTION_META, "version", 0))
			== GameSettings.SETTINGS_VERSION,
		"setting migration should record the new config version"
	)
	migrated.free()
	_expect(_remove_config(true), "legacy config should be removable")

	var settings := GameSettings.new()
	settings.config_path = _config_path
	settings.set_master_volume(-1.0)
	settings.set_mouse_sensitivity(0.0)
	settings.set_traffic_density(9.0)
	_expect(is_zero_approx(settings.master_volume), "master volume must clamp at zero")
	_expect(
		is_equal_approx(settings.mouse_sensitivity, 0.0005),
		"mouse sensitivity must clamp at its minimum"
	)
	_expect(
		is_equal_approx(settings.traffic_density, 3.0),
		"traffic density must clamp at its maximum"
	)

	settings.master_volume = 0.42
	settings.mouse_sensitivity = 0.0065
	settings.traffic_density = 2.3
	settings.fullscreen = true
	_expect(settings.save_settings(), "settings should save to the temporary config")

	var restored := GameSettings.new()
	restored.config_path = _config_path
	_expect(restored.load_settings(), "saved settings should load again")
	_expect(is_equal_approx(restored.master_volume, 0.42), "master volume did not persist")
	_expect(
		is_equal_approx(restored.mouse_sensitivity, 0.0065),
		"mouse sensitivity did not persist"
	)
	_expect(
		is_equal_approx(restored.traffic_density, 2.3),
		"traffic density did not persist"
	)
	_expect(restored.fullscreen, "fullscreen setting did not persist")

	var player := PlayerController.new()
	var traffic := TrafficSpawner.new()
	root.add_child(player)
	root.add_child(traffic)
	restored.apply_to(player, traffic)
	_expect(
		is_equal_approx(player.mouse_sensitivity, restored.mouse_sensitivity),
		"applying settings should update player mouse sensitivity"
	)
	_expect(
		is_equal_approx(traffic.traffic_density, restored.traffic_density),
		"applying settings should update traffic density"
	)
	player.free()
	traffic.free()

	restored.reset_to_defaults(false)
	_check_defaults(restored, "reset settings")
	restored.free()
	settings.free()

	_expect(_remove_config(true), "temporary settings config should be removable")
	if _failed:
		printerr("FAIL game settings")
	else:
		print("PASS game settings")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL game settings: ", message)


func _check_defaults(settings: GameSettings, context: String) -> void:
	_expect(
		is_equal_approx(GameSettings.DEFAULT_TRAFFIC_DENSITY, 3.0),
		"default traffic density constant should be 3.0"
	)
	_expect(
		is_equal_approx(settings.master_volume, GameSettings.DEFAULT_MASTER_VOLUME),
		"%s master volume should use the default" % context
	)
	_expect(
		is_equal_approx(
			settings.mouse_sensitivity,
			GameSettings.DEFAULT_MOUSE_SENSITIVITY
		),
		"%s mouse sensitivity should use the default" % context
	)
	_expect(
		is_equal_approx(settings.traffic_density, GameSettings.DEFAULT_TRAFFIC_DENSITY),
		"%s traffic density should use the default" % context
	)
	_expect(
		settings.fullscreen == GameSettings.DEFAULT_FULLSCREEN,
		"%s fullscreen should use the default" % context
	)


func _remove_config(expect_success: bool) -> bool:
	if not FileAccess.file_exists(_config_path):
		return true
	var error := DirAccess.remove_absolute(
		ProjectSettings.globalize_path(_config_path)
	)
	if expect_success:
		_expect(error == OK, "failed to remove temporary settings config: %s" % error)
	return error == OK
