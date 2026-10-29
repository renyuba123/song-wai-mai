extends CanvasLayer
class_name InputDiagnosticsHUD

## Runtime input probe. Hidden at launch; F9 toggles its phone view.

const PANEL_BG := Color(0.035, 0.055, 0.075, 0.9)
const TEXT_COLOR := Color(0.92, 0.96, 1.0, 1.0)
const MUTED_COLOR := Color(0.66, 0.74, 0.82, 1.0)
const OK_COLOR := Color(0.35, 0.95, 0.68, 1.0)
const WARN_COLOR := Color(1.0, 0.68, 0.28, 1.0)
const ERROR_COLOR := Color(1.0, 0.4, 0.34, 1.0)

var _player: PlayerController = null
var _activation: InputActivationOverlay = null
var _panel: PanelContainer = null
var _focus_label: Label = null
var _activation_label: Label = null
var _event_label: Label = null
var _player_label: Label = null
var _key_event_count := 0
var _last_key_text := "none"
var _last_key_short := "none"
var _last_key_msec := 0
var _enabled := false
var _embedded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	_build()


func setup(player: PlayerController, activation: InputActivationOverlay = null) -> void:
	_player = player
	_activation = activation
	_refresh()


func set_input_activation(activation: InputActivationOverlay) -> void:
	_activation = activation
	_refresh()


func get_key_event_count() -> int:
	return _key_event_count


func get_last_key_text() -> String:
	return _last_key_text


func is_enabled() -> bool:
	return _enabled


func set_embedded(enabled: bool) -> void:
	_embedded = enabled
	if _panel != null:
		_panel.visible = _enabled and not _embedded


func get_diagnostics_text() -> String:
	if _focus_label == null:
		return ""
	return "\n".join([
		_focus_label.text,
		_activation_label.text,
		_event_label.text,
		_player_label.text,
	])


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if _is_raw_key(key_event, KEY_F9):
		if key_event.pressed and not key_event.echo:
			_enabled = not _enabled
			_panel.visible = _enabled and not _embedded
			get_viewport().set_input_as_handled()
		return
	if not key_event.pressed or key_event.echo:
		return
	_key_event_count += 1
	_last_key_msec = Time.get_ticks_msec()
	var display_key := key_event.keycode
	if display_key == KEY_NONE:
		display_key = key_event.physical_keycode
	_last_key_short = OS.get_keycode_string(display_key)
	_last_key_text = "%s key=%d physical=%d unicode=%d" % [
		_last_key_short,
		key_event.keycode,
		key_event.physical_keycode,
		key_event.unicode,
	]
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _focus_label == null:
		return
	var focused := DisplayServer.get_name() == "headless" or DisplayServer.window_is_focused()
	_focus_label.text = "窗口焦点  %s" % ("已获得" if focused else "未获得")
	_focus_label.add_theme_color_override("font_color", OK_COLOR if focused else ERROR_COLOR)

	if _activation != null and not _activation.is_active():
		_activation_label.text = "输入激活  等待鼠标点击画面"
		_activation_label.add_theme_color_override("font_color", WARN_COLOR)
	elif _key_event_count <= 0:
		_activation_label.text = "输入激活  已连接，等待按键"
		_activation_label.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_activation_label.text = "输入激活  已连接，键盘事件已收到"
		_activation_label.add_theme_color_override("font_color", OK_COLOR)

	if _key_event_count <= 0:
		_event_label.text = "键盘输入  尚无事件"
		_event_label.add_theme_color_override("font_color", WARN_COLOR)
	else:
		var age := maxi(0, Time.get_ticks_msec() - _last_key_msec)
		_event_label.text = "键盘输入  已收到 %d 次  最近 %s  %d ms 前" % [
			_key_event_count,
			_last_key_short,
			age,
		]
		_event_label.add_theme_color_override("font_color", OK_COLOR)

	if _player == null:
		_player_label.text = "角色状态  未连接"
		return
	var state := "可控制" if _player.controls_enabled else "菜单中"
	if not _player.is_physics_processing():
		state = "物理处理已停止"
	_player_label.text = "角色状态  %s  速度 %.1f m/s  车头 %.0f°" % [
		state,
		_player.get_current_speed_mps(),
		_player.get_heading_degrees(),
	]
	_player_label.add_theme_color_override(
		"font_color", WARN_COLOR if not _player.controls_enabled else TEXT_COLOR
	)


func _build() -> void:
	var root := Control.new()
	root.name = "InputDiagnosticsOverlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "InputDiagnosticsPanel"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -318
	_panel.offset_right = -18
	_panel.offset_top = 182
	_panel.offset_bottom = 334
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(0.22, 0.74, 0.9, 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)
	_panel.visible = false

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var title := _make_label("输入自检 v3  ·  F9 关闭", 13, MUTED_COLOR)
	box.add_child(title)
	_focus_label = _make_label("", 15, TEXT_COLOR)
	box.add_child(_focus_label)
	_activation_label = _make_label("", 14, TEXT_COLOR)
	box.add_child(_activation_label)
	_event_label = _make_label("", 14, TEXT_COLOR)
	box.add_child(_event_label)
	_player_label = _make_label("", 14, TEXT_COLOR)
	box.add_child(_player_label)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	return label


func _is_raw_key(event: InputEventKey, key: Key) -> bool:
	return (
		event.keycode == key
		or event.physical_keycode == key
		or event.key_label == key
	)
