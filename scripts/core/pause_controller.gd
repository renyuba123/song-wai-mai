extends CanvasLayer
class_name PauseController

## 配送中的暂停菜单：Esc 冻结场景树、释放鼠标并停玩家输入，
## 再按 Esc 或“继续”恢复；“重开本单”“返回主菜单”直接复用
## OrderManager 现有接口，不另写一套状态切换。

const PANEL_BG := Color(0.045, 0.06, 0.09, 0.84)
const TEXT_COLOR := Color(0.96, 0.97, 1.0, 1.0)
const MUTED_COLOR := Color(0.72, 0.78, 0.86, 1.0)
const ACCENT_COLOR := Color(1.0, 0.72, 0.28, 1.0)

var _orders: OrderManager = null
var _player: PlayerController = null
var _settings: GameSettings = null
var _traffic: TrafficSpawner = null
var _overlay: Control = null
var _seed_label: Label = null
var _resume_button: Button = null
var _pause_page: VBoxContainer = null
var _settings_page: VBoxContainer = null
var _volume_slider: HSlider = null
var _volume_value: Label = null
var _sensitivity_slider: HSlider = null
var _sensitivity_value: Label = null
var _density_slider: HSlider = null
var _density_value: Label = null
var _fullscreen_check: CheckBox = null
var _controls_before_pause := false


func _ready() -> void:
	# 暂停时根节点仍要处理 Esc，内部遮罩在暂停期间才处理按钮。
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
	## 只在配送进行中允许暂停；菜单、接单、结算和开始界面都返回 false。
	if _orders == null or _player == null or not _player.controls_enabled:
		return false
	if not _player.is_physics_processing():
		# 上帝视角等调试状态会关闭玩家物理，不要在那种状态下抢鼠标。
		return false
	var session := _orders.get_session()
	if session == null or not session.is_active():
		return false
	var hud := _orders.get_hud()
	if hud != null and hud.is_any_modal_visible():
		return false
	return true


func is_pause_visible() -> bool:
	return _overlay != null and _overlay.visible


func is_settings_visible() -> bool:
	return _settings_page != null and _settings_page.visible


func open_settings() -> void:
	if not is_pause_visible() or not is_instance_valid(_settings_page):
		return
	_sync_settings_controls()
	_pause_page.visible = false
	_settings_page.visible = true
	var back := _settings_page.get_node_or_null("BackButton") as Button
	if back != null:
		back.grab_focus()


func back_to_pause() -> void:
	if not is_settings_visible():
		return
	_save_settings()
	_show_pause_page()


func open_pause() -> bool:
	if is_pause_visible() or not can_pause():
		return false
	_controls_before_pause = _player.controls_enabled
	_player.set_controls_enabled(false)
	_refresh_seed_text()
	_overlay.visible = true
	_resume_button.grab_focus()
	get_tree().paused = true
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
	## handle_restart 在活动会话下重开同一单，并自己恢复玩家控制与位置。
	if not is_pause_visible() or _orders == null:
		return
	_exit_pause()
	if not _orders.handle_restart():
		_restore_controls(_controls_before_pause)


func return_to_menu() -> void:
	## return_to_start_menu 自己会关闭玩家控制并切回开始界面。
	if not is_pause_visible() or _orders == null:
		return
	_exit_pause()
	_orders.return_to_start_menu()


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
	if is_pause_visible():
		if is_settings_visible():
			back_to_pause()
		else:
			close_pause()
	else:
		# 开始菜单/接单/结算下按 Esc 不打开暂停层，也不让事件继续传给其它输入。
		open_pause()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	## 场景卸载或测试失败时不要把整个进程留在暂停状态。
	if is_pause_visible() and get_tree() != null:
		get_tree().paused = false


func _exit_pause() -> void:
	_overlay.visible = false
	_show_pause_page()
	if is_inside_tree():
		get_tree().paused = false


func _restore_controls(enabled: bool) -> void:
	if _player == null:
		return
	if enabled and not _player.controls_enabled:
		_player.set_controls_enabled(true)


func _refresh_seed_text() -> void:
	if _seed_label != null:
		_seed_label.text = get_seed_text()


func _build() -> void:
	_overlay = Control.new()
	_overlay.name = "PauseOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_overlay.visible = false
	add_child(_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -260
	panel.offset_bottom = 260
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style())
	_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var page_host := VBoxContainer.new()
	page_host.name = "PageHost"
	page_host.alignment = BoxContainer.ALIGNMENT_CENTER
	page_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(page_host)

	_pause_page = VBoxContainer.new()
	_pause_page.name = "PausePage"
	_pause_page.add_theme_constant_override("separation", 14)
	_pause_page.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_host.add_child(_pause_page)

	var title := _make_label(28, ACCENT_COLOR)
	title.text = "已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_page.add_child(title)

	_seed_label = _make_label(16, MUTED_COLOR)
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_page.add_child(_seed_label)

	var hint := _make_label(14, MUTED_COLOR)
	hint.text = (
		"点“继续”返回游戏"
		if TouchControls.is_touch_device()
		else "Esc 或“继续”返回游戏"
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_page.add_child(hint)

	_resume_button = _make_button("继续")
	_resume_button.pressed.connect(resume)
	_pause_page.add_child(_resume_button)

	var settings_button := _make_button("设置")
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(open_settings)
	_pause_page.add_child(settings_button)

	var restart_button := _make_button("重开本单")
	restart_button.pressed.connect(restart_order)
	_pause_page.add_child(restart_button)

	var menu_button := _make_button("返回主菜单")
	menu_button.pressed.connect(return_to_menu)
	_pause_page.add_child(menu_button)

	_build_settings_page(page_host)


func _build_settings_page(page_host: VBoxContainer) -> void:
	_settings_page = VBoxContainer.new()
	_settings_page.name = "SettingsPage"
	_settings_page.add_theme_constant_override("separation", 16)
	_settings_page.alignment = BoxContainer.ALIGNMENT_CENTER
	_settings_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_page.visible = false
	page_host.add_child(_settings_page)

	var title := _make_label(28, ACCENT_COLOR)
	title.text = "设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_page.add_child(title)

	var volume_row := _make_slider_row(
		_settings_page,
		"主音量",
		0.0,
		1.0,
		0.01,
		GameSettings.DEFAULT_MASTER_VOLUME
	)
	_volume_slider = volume_row["slider"] as HSlider
	_volume_slider.name = "VolumeSlider"
	_volume_value = volume_row["value"] as Label
	_volume_slider.value_changed.connect(_on_volume_changed)

	var sensitivity_row := _make_slider_row(
		_settings_page,
		"鼠标灵敏度",
		0.0005,
		0.01,
		0.0005,
		GameSettings.DEFAULT_MOUSE_SENSITIVITY
	)
	_sensitivity_slider = sensitivity_row["slider"] as HSlider
	_sensitivity_slider.name = "SensitivitySlider"
	_sensitivity_value = sensitivity_row["value"] as Label
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)

	var density_row := _make_slider_row(
		_settings_page,
		"交通密度",
		0.1,
		3.0,
		0.1,
		GameSettings.DEFAULT_TRAFFIC_DENSITY
	)
	_density_slider = density_row["slider"] as HSlider
	_density_slider.name = "DensitySlider"
	_density_value = density_row["value"] as Label
	_density_slider.value_changed.connect(_on_density_changed)

	_fullscreen_check = CheckBox.new()
	_fullscreen_check.name = "FullscreenCheck"
	_fullscreen_check.text = "全屏显示"
	_fullscreen_check.custom_minimum_size = Vector2(0, 44)
	_fullscreen_check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fullscreen_check.add_theme_font_size_override("font_size", 18)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_settings_page.add_child(_fullscreen_check)

	var reset_button := _make_button("恢复默认")
	reset_button.name = "ResetButton"
	reset_button.pressed.connect(_reset_settings)
	_settings_page.add_child(reset_button)

	var back_button := _make_button("返回")
	back_button.name = "BackButton"
	back_button.pressed.connect(back_to_pause)
	_settings_page.add_child(back_button)


func _make_slider_row(
	parent: VBoxContainer,
	caption: String,
	minimum: float,
	maximum: float,
	step: float,
	initial: float
) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var label := _make_label(17, TEXT_COLOR)
	label.text = caption
	label.custom_minimum_size.x = 116
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(210, 34)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(slider)

	var value_label := _make_label(15, MUTED_COLOR)
	value_label.custom_minimum_size.x = 62
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	return {"slider": slider, "value": value_label}


func _show_pause_page() -> void:
	if is_instance_valid(_settings_page):
		_settings_page.visible = false
	if is_instance_valid(_pause_page):
		_pause_page.visible = true


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
	if _volume_value != null and _settings != null:
		_volume_value.text = "%d%%" % roundi(_settings.master_volume * 100.0)
	if _sensitivity_value != null and _settings != null:
		_sensitivity_value.text = "%.1f" % (_settings.mouse_sensitivity * 1000.0)
	if _density_value != null and _settings != null:
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
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(220, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 22)
	return button


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(1.0, 0.72, 0.28, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
