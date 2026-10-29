extends CanvasLayer
class_name PauseController

## A single menu layer serves the game pause, settings, and exit confirmation.
## The existing GameSettings and OrderManager remain the source of truth.

const CARD_BG := Color(0.105, 0.127, 0.177, 0.97)
const INNER_BG := Color(0.085, 0.108, 0.155, 0.88)
const BORDER := Color(0.32, 0.37, 0.48, 0.72)
const TEXT := Color(0.89, 0.91, 0.95)
const MUTED := Color(0.68, 0.73, 0.81)
const GOLD := Color(1.0, 0.78, 0.35)
const DARK_TEXT := Color(0.17, 0.18, 0.22)

var _orders: OrderManager = null
var _player: PlayerController = null
var _settings: GameSettings = null
var _traffic: TrafficSpawner = null
var _overlay: Control = null
var _card: PanelContainer = null
var _pause_page: VBoxContainer = null
var _settings_page: VBoxContainer = null
var _exit_page: VBoxContainer = null
var _resume_button: Button = null
var _pause_options: Array[Button] = []
var _pause_arrows: Array[Label] = []
var _settings_tabs: Array[Button] = []
var _settings_rows: Array[Control] = []
var _row_categories: Array[int] = []
var _volume_slider: HSlider = null
var _volume_value: Label = null
var _sensitivity_slider: HSlider = null
var _sensitivity_value: Label = null
var _density_slider: HSlider = null
var _density_value: Label = null
var _fullscreen_check: CheckBox = null
var _controls_help: Label = null
var _controls_before_pause := false
var _settings_from_start := false
var _exit_from_start := false
var _selected_pause_option := 0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func setup(
	orders: OrderManager,
	player: PlayerController,
	settings: GameSettings = null,
	traffic: TrafficSpawner = null
) -> void:
	_orders = orders
	_player = player
	_traffic = traffic
	if settings == null:
		settings = GameSettings.new()
		settings.name = "GameSettings"
		add_child(settings)
		settings.load_settings()
	_settings = settings
	_settings.apply_to(_player, _traffic)
	_sync_settings_controls()


func can_pause() -> bool:
	if _orders == null or _player == null or not _player.controls_enabled:
		return false
	if not _player.is_physics_processing():
		return false
	var session := _orders.get_session()
	if session == null or not session.is_active():
		return false
	var hud := _orders.get_hud()
	return hud == null or not hud.is_any_modal_visible()


func is_pause_visible() -> bool:
	return _overlay != null and _overlay.visible


func is_settings_visible() -> bool:
	return _settings_page != null and _settings_page.visible


func is_exit_confirmation_visible() -> bool:
	return _exit_page != null and _exit_page.visible


func open_start_settings() -> void:
	if is_pause_visible():
		return
	_settings_from_start = true
	_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	open_settings()


func open_settings() -> void:
	if not is_pause_visible():
		return
	_sync_settings_controls()
	_select_settings_tab(0)
	_pause_page.visible = false
	_exit_page.visible = false
	_settings_page.visible = true
	_set_card_size(Vector2(420, 360))
	var apply_button := find_child("BackButton", true, false) as Button
	if apply_button != null:
		apply_button.grab_focus()


func back_to_pause() -> void:
	if not is_settings_visible():
		return
	_save_settings()
	if _settings_from_start:
		_settings_from_start = false
		_overlay.visible = false
		_show_pause_page()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_focus_start_menu_option(1)
	else:
		_show_pause_page()
		_resume_button.grab_focus()


func open_exit_confirmation() -> void:
	if is_exit_confirmation_visible():
		return
	_exit_from_start = not get_tree().paused
	_overlay.visible = true
	_pause_page.visible = false
	_settings_page.visible = false
	_exit_page.visible = true
	_set_card_size(Vector2(340, 132))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var cancel_button := find_child("CancelExitButton", true, false) as Button
	if cancel_button != null:
		cancel_button.grab_focus()


func cancel_exit_confirmation() -> void:
	if not is_exit_confirmation_visible():
		return
	if _exit_from_start:
		_overlay.visible = false
		_show_pause_page()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_focus_start_menu_option(2)
	else:
		_show_pause_page()
		_resume_button.grab_focus()


func confirm_exit() -> void:
	get_tree().quit()


func open_pause() -> bool:
	if is_pause_visible() or not can_pause():
		return false
	_controls_before_pause = _player.controls_enabled
	_player.set_controls_enabled(false)
	_settings_from_start = false
	_overlay.visible = true
	_show_pause_page()
	_select_pause_option(0)
	_resume_button.grab_focus()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


func close_pause() -> void:
	if not is_pause_visible():
		return
	_save_settings()
	_exit_pause()
	_restore_controls(_controls_before_pause)


func resume() -> void:
	close_pause()


func restart_order() -> void:
	if not is_pause_visible() or _orders == null:
		return
	_exit_pause()
	if not _orders.handle_restart():
		_restore_controls(_controls_before_pause)


func return_to_menu() -> void:
	if not is_pause_visible() or _orders == null:
		return
	_exit_pause()
	_orders.return_to_start_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func get_seed_text() -> String:
	var city_text := "—"
	var order_text := "—"
	if _orders != null:
		var order := _orders.get_current_order()
		if order != null:
			city_text = str(order.city_seed)
			order_text = str(order.order_seed)
		else:
			order_text = str(_orders.get_order_seed())
	return "城市种子 %s · 订单种子 %s" % [city_text, order_text]


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if is_exit_confirmation_visible():
		cancel_exit_confirmation()
	elif is_settings_visible():
		back_to_pause()
	elif is_pause_visible():
		close_pause()
	else:
		open_pause()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_pause_visible() and get_tree() != null:
		get_tree().paused = false


func _exit_pause() -> void:
	_overlay.visible = false
	_show_pause_page()
	if is_inside_tree():
		get_tree().paused = false


func _restore_controls(enabled: bool) -> void:
	if _player != null and enabled and not _player.controls_enabled:
		_player.set_controls_enabled(true)


func _focus_start_menu_option(index: int) -> void:
	if _orders == null:
		return
	var hud := _orders.get_hud()
	if hud == null:
		return
	var art := hud.find_child("StartBackdrop", true, false) as StartMenuArt
	if art != null:
		art.focus_option(index)


func _build() -> void:
	_overlay = Control.new()
	_overlay.name = "PauseOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	add_child(_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.06, 0.42)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(shade)

	_card = PanelContainer.new()
	_card.name = "MenuCard"
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_theme_stylebox_override("panel", _card_style())
	_overlay.add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 11)
	margin.add_theme_constant_override("margin_bottom", 11)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(margin)

	var pages := VBoxContainer.new()
	pages.name = "PageHost"
	pages.alignment = BoxContainer.ALIGNMENT_CENTER
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(pages)
	_build_pause_page(pages)
	_build_settings_page(pages)
	_build_exit_page(pages)
	_show_pause_page()


func _build_pause_page(pages: VBoxContainer) -> void:
	_pause_page = VBoxContainer.new()
	_pause_page.name = "PausePage"
	_pause_page.add_theme_constant_override("separation", 2)
	_pause_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.add_child(_pause_page)

	var title := _make_label(14, TEXT)
	title.text = "GAME PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 25
	_pause_page.add_child(title)
	_add_pause_option("继续游戏", resume)
	_add_pause_option("设置", open_settings)
	_add_pause_option("返回主菜单", return_to_menu)
	_add_pause_option("退出游戏", open_exit_confirmation)
	for i in _pause_options.size():
		_pause_options[i].focus_neighbor_top = _pause_options[i].get_path_to(_pause_options[(i - 1 + _pause_options.size()) % _pause_options.size()])
		_pause_options[i].focus_neighbor_bottom = _pause_options[i].get_path_to(_pause_options[(i + 1) % _pause_options.size()])


func _add_pause_option(caption: String, action: Callable) -> void:
	var index := _pause_options.size()
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 23
	row.add_theme_constant_override("separation", 6)
	_pause_page.add_child(row)
	var arrow := _make_label(13, GOLD)
	arrow.text = "▶"
	arrow.custom_minimum_size.x = 19
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(arrow)
	var button := Button.new()
	button.text = caption
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_focus_color", GOLD)
	button.mouse_entered.connect(_hover_pause_option.bind(index))
	button.focus_entered.connect(func() -> void: _select_pause_option(index))
	button.pressed.connect(action)
	row.add_child(button)
	_pause_options.append(button)
	_pause_arrows.append(arrow)
	if index == 0:
		_resume_button = button


func _hover_pause_option(index: int) -> void:
	_pause_options[index].grab_focus()
	_select_pause_option(index)


func _select_pause_option(index: int) -> void:
	_selected_pause_option = index
	for i in _pause_options.size():
		_pause_arrows[i].visible = i == index
		_pause_options[i].add_theme_color_override(
			"font_color", GOLD if i == index else TEXT
		)


func _build_settings_page(pages: VBoxContainer) -> void:
	_settings_page = VBoxContainer.new()
	_settings_page.name = "SettingsPage"
	_settings_page.add_theme_constant_override("separation", 8)
	_settings_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_page.visible = false
	pages.add_child(_settings_page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_settings_page.add_child(header)
	var gear := _make_gear_icon()
	header.add_child(gear)
	var title := _make_label(15, TEXT)
	title.text = "SETTINGS"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	_settings_page.add_child(tabs)
	var names := ["游戏", "画面", "音频", "控制"]
	for i in names.size():
		var tab := Button.new()
		tab.text = names[i]
		tab.custom_minimum_size = Vector2(0, 27)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 12)
		tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		tab.pressed.connect(_select_settings_tab.bind(i))
		tabs.add_child(tab)
		_settings_tabs.append(tab)

	var content := PanelContainer.new()
	content.custom_minimum_size.y = 217
	content.add_theme_stylebox_override("panel", _inner_style())
	_settings_page.add_child(content)
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 10)
	content_margin.add_theme_constant_override("margin_right", 10)
	content_margin.add_theme_constant_override("margin_top", 5)
	content_margin.add_theme_constant_override("margin_bottom", 5)
	content.add_child(content_margin)
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 4)
	content_margin.add_child(options)

	var language := HBoxContainer.new()
	language.custom_minimum_size.y = 27
	options.add_child(language)
	var language_caption := _make_label(12, MUTED)
	language_caption.text = "语言"
	language_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language.add_child(language_caption)
	var language_value := _make_label(12, MUTED)
	language_value.text = "简体中文"
	language_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	language.add_child(language_value)
	_register_settings_row(language, 0)

	var volume := _make_slider_row(options, "主音量", 0.0, 1.0, 0.01, GameSettings.DEFAULT_MASTER_VOLUME)
	_volume_slider = volume["slider"] as HSlider
	_volume_slider.name = "VolumeSlider"
	_volume_value = volume["value"] as Label
	_volume_slider.value_changed.connect(_on_volume_changed)
	_register_settings_row(volume["row"] as Control, 2)

	var sensitivity := _make_slider_row(options, "鼠标灵敏度", 0.0005, 0.01, 0.0005, GameSettings.DEFAULT_MOUSE_SENSITIVITY)
	_sensitivity_slider = sensitivity["slider"] as HSlider
	_sensitivity_slider.name = "SensitivitySlider"
	_sensitivity_value = sensitivity["value"] as Label
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	_register_settings_row(sensitivity["row"] as Control, 3)

	var density := _make_slider_row(options, "交通密度", 0.1, 3.0, 0.1, GameSettings.DEFAULT_TRAFFIC_DENSITY)
	_density_slider = density["slider"] as HSlider
	_density_slider.name = "DensitySlider"
	_density_value = density["value"] as Label
	_density_slider.value_changed.connect(_on_density_changed)
	_register_settings_row(density["row"] as Control, 0)

	_fullscreen_check = CheckBox.new()
	_fullscreen_check.name = "FullscreenCheck"
	_fullscreen_check.text = "全屏显示"
	_fullscreen_check.custom_minimum_size.y = 27
	_fullscreen_check.add_theme_font_size_override("font_size", 12)
	_fullscreen_check.add_theme_color_override("font_color", MUTED)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	options.add_child(_fullscreen_check)
	_register_settings_row(_fullscreen_check, 1)

	_controls_help = _make_label(11, MUTED)
	_controls_help.name = "ControlsHelp"
	_controls_help.text = "W / S 加速与刹车\nA / D 转向 · 鼠标视角\nE 取餐 / 送达 · Esc 暂停"
	_controls_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options.add_child(_controls_help)
	_register_settings_row(_controls_help, 3)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	_settings_page.add_child(footer)
	var reset := _make_action_button("恢复默认", false)
	reset.name = "ResetButton"
	reset.pressed.connect(_reset_settings)
	footer.add_child(reset)
	var apply := _make_action_button("应用", true)
	apply.name = "BackButton"
	apply.pressed.connect(back_to_pause)
	footer.add_child(apply)


func _build_exit_page(pages: VBoxContainer) -> void:
	_exit_page = VBoxContainer.new()
	_exit_page.name = "ExitPage"
	_exit_page.alignment = BoxContainer.ALIGNMENT_CENTER
	_exit_page.add_theme_constant_override("separation", 12)
	_exit_page.visible = false
	pages.add_child(_exit_page)
	var prompt := HBoxContainer.new()
	prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt.add_theme_constant_override("separation", 10)
	_exit_page.add_child(prompt)
	var warning_box := PanelContainer.new()
	var warning_style := StyleBoxFlat.new()
	warning_style.bg_color = GOLD
	warning_style.set_corner_radius_all(3)
	warning_box.add_theme_stylebox_override("panel", warning_style)
	warning_box.custom_minimum_size = Vector2(23, 23)
	prompt.add_child(warning_box)
	var warning := _make_label(17, DARK_TEXT)
	warning.text = "!"
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning_box.add_child(warning)
	var message := _make_label(14, TEXT)
	message.text = "确定要退出游戏吗?"
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.add_child(message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	_exit_page.add_child(actions)
	var cancel := _make_action_button("取消", false)
	cancel.name = "CancelExitButton"
	cancel.pressed.connect(cancel_exit_confirmation)
	actions.add_child(cancel)
	var exit := _make_action_button("退出", true)
	exit.name = "ConfirmExitButton"
	exit.pressed.connect(confirm_exit)
	actions.add_child(exit)


func _make_slider_row(parent: VBoxContainer, caption: String, minimum: float, maximum: float, step: float, initial: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 27
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := _make_label(12, MUTED)
	label.text = caption
	label.custom_minimum_size.x = 91
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(150, 25)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(slider)
	var value := _make_label(11, MUTED)
	value.custom_minimum_size.x = 45
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	return {"row": row, "slider": slider, "value": value}


func _register_settings_row(row: Control, category: int) -> void:
	_settings_rows.append(row)
	_row_categories.append(category)


func _select_settings_tab(index: int) -> void:
	for i in _settings_tabs.size():
		var selected := i == index
		_settings_tabs[i].add_theme_stylebox_override("normal", _button_style(selected))
		_settings_tabs[i].add_theme_stylebox_override("hover", _button_style(selected))
		_settings_tabs[i].add_theme_stylebox_override("pressed", _button_style(selected))
		_settings_tabs[i].add_theme_color_override("font_color", DARK_TEXT if selected else MUTED)
		_settings_tabs[i].add_theme_color_override("font_hover_color", DARK_TEXT if selected else TEXT)
	for i in _settings_rows.size():
		_settings_rows[i].visible = (_row_categories[i] == index or (index == 0 and _settings_rows[i] != _controls_help))


func _show_pause_page() -> void:
	if _pause_page != null:
		_pause_page.visible = true
	if _settings_page != null:
		_settings_page.visible = false
	if _exit_page != null:
		_exit_page.visible = false
	_set_card_size(Vector2(330, 154))
	_select_pause_option(_selected_pause_option)


func _set_card_size(size: Vector2) -> void:
	if _card == null:
		return
	_card.offset_left = -size.x * 0.5
	_card.offset_right = size.x * 0.5
	_card.offset_top = -size.y * 0.5
	_card.offset_bottom = size.y * 0.5


func _sync_settings_controls() -> void:
	if _settings == null:
		return
	if _volume_slider != null:
		_volume_slider.set_value_no_signal(_settings.master_volume)
	if _sensitivity_slider != null:
		_sensitivity_slider.set_value_no_signal(_settings.mouse_sensitivity)
	if _density_slider != null:
		_density_slider.set_value_no_signal(_settings.traffic_density)
	if _fullscreen_check != null:
		_fullscreen_check.set_pressed_no_signal(_settings.fullscreen)
	_refresh_settings_labels()


func _refresh_settings_labels() -> void:
	if _settings == null:
		return
	if _volume_value != null:
		_volume_value.text = "%d%%" % roundi(_settings.master_volume * 100.0)
	if _sensitivity_value != null:
		_sensitivity_value.text = "%.1f" % (_settings.mouse_sensitivity * 1000.0)
	if _density_value != null:
		_density_value.text = "%.1fx" % _settings.traffic_density


func _on_volume_changed(value: float) -> void:
	if _settings == null:
		return
	_settings.set_master_volume(value)
	_settings.apply_to(_player, _traffic)
	_refresh_settings_labels()


func _on_sensitivity_changed(value: float) -> void:
	if _settings == null:
		return
	_settings.set_mouse_sensitivity(value)
	_settings.apply_to(_player, _traffic)
	_refresh_settings_labels()


func _on_density_changed(value: float) -> void:
	if _settings == null:
		return
	_settings.set_traffic_density(value)
	_settings.apply_to(_player, _traffic)
	_refresh_settings_labels()


func _on_fullscreen_toggled(value: bool) -> void:
	if _settings == null:
		return
	_settings.set_fullscreen(value)
	_settings.apply_to(_player, _traffic)


func _reset_settings() -> void:
	if _settings == null:
		return
	_settings.reset_to_defaults()
	_settings.apply_to(_player, _traffic)
	_settings.save_settings()
	_sync_settings_controls()


func _save_settings() -> void:
	if _settings != null:
		_settings.save_settings()


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_gear_icon() -> TextureRect:
	# Draw the icon locally so its color stays consistent across system emoji fonts.
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in 48:
		for x in 48:
			var delta := Vector2(float(x) + 0.5, float(y) + 0.5) - Vector2(24, 24)
			var radius := delta.length()
			var tooth := absf(sin(atan2(delta.y, delta.x) * 8.0)) > 0.82
			if radius >= 6.0 and (radius <= 15.5 or (tooth and radius <= 21.0)):
				image.set_pixel(x, y, TEXT)
	var icon := TextureRect.new()
	icon.texture = ImageTexture.create_from_image(image)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.custom_minimum_size = Vector2(24, 24)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _make_action_button(caption: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(94, 30)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", _button_style(primary))
	button.add_theme_stylebox_override("hover", _button_style(primary, true))
	button.add_theme_stylebox_override("pressed", _button_style(primary))
	button.add_theme_stylebox_override("focus", _focus_style())
	button.add_theme_color_override("font_color", DARK_TEXT if primary else TEXT)
	button.add_theme_color_override("font_hover_color", DARK_TEXT if primary else TEXT)
	button.add_theme_color_override("font_focus_color", DARK_TEXT if primary else TEXT)
	button.add_theme_color_override("font_pressed_color", DARK_TEXT if primary else TEXT)
	return button


func _button_style(primary: bool, hover := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = (Color(1.0, 0.83, 0.46) if hover else GOLD) if primary else (Color(0.39, 0.44, 0.56) if hover else Color(0.31, 0.35, 0.45))
	style.border_color = Color(0.64, 0.68, 0.78, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(1.0, 0.86, 0.52, 0.68)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 9
	return style


func _inner_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = INNER_BG
	style.border_color = Color(0.27, 0.32, 0.42, 0.52)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style
