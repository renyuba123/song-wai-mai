extends CanvasLayer
class_name InputActivationOverlay

signal activated

const OVERLAY_LAYER := 140
const PANEL_BG := Color(0.035, 0.055, 0.075, 0.96)
const TEXT_COLOR := Color(0.96, 0.98, 1.0, 1.0)
const MUTED_COLOR := Color(0.68, 0.78, 0.88, 1.0)
const ACCENT_COLOR := Color(0.2, 0.82, 0.98, 1.0)

var _overlay: Control = null
var _title: Label = null
var _hint: Label = null
var _active := false
var _menu_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = OVERLAY_LAYER
	_build()
	if DisplayServer.get_name() == "headless":
		_active = true
		_overlay.visible = false
	else:
		show_reactivation("点击画面开始")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _menu_mode:
			return
		show_reactivation("窗口已失去焦点，点击画面继续")


func _input(event: InputEvent) -> void:
	if _active:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			# Keyboard activation is a fallback for systems where the first
			# synthetic or touch-driven mouse click does not reach the game.
			activate()
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
			return
		# This event can only arrive after Windows delivered a real click to the
		# game window. Activate here so keyboard focus belongs to this process.
		activate()
		get_viewport().set_input_as_handled()


func activate() -> void:
	if _active:
		return
	_active = true
	_overlay.visible = false
	var game_window := get_window()
	game_window.grab_focus()
	if not _menu_mode:
		get_viewport().gui_release_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if _menu_mode else Input.MOUSE_MODE_CAPTURED)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("大城市送外卖")
	print(
		"INPUT_ACTIVATED focus=", DisplayServer.window_is_focused(),
		" renderer=", RenderingServer.get_video_adapter_name()
	)
	activated.emit()


func set_menu_mode(enabled: bool) -> void:
	_menu_mode = enabled
	if enabled:
		_active = true
		_overlay.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif not DisplayServer.is_touchscreen_available():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func is_active() -> bool:
	return _active


func is_waiting_for_activation() -> bool:
	return not _active and DisplayServer.get_name() != "headless"


func get_activation_title() -> String:
	return _title.text if _title != null else ""


func show_reactivation(reason: String = "窗口已失去焦点，点击画面继续") -> void:
	if DisplayServer.get_name() == "headless":
		return
	_active = false
	_title.text = reason
	_hint.text = "点击游戏画面，或按任意键开始"
	_title.add_theme_color_override("font_color", ACCENT_COLOR)
	_overlay.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	DisplayServer.window_set_title("大城市送外卖 | 点击画面或按任意键开始")


func _build() -> void:
	_overlay = Control.new()
	_overlay.name = "ActivationOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.02, 0.035, 0.68)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(shade)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -310.0
	panel.offset_right = 310.0
	panel.offset_top = -104.0
	panel.offset_bottom = 104.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = ACCENT_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_title = Label.new()
	_title.name = "ActivationTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", TEXT_COLOR)
	box.add_child(_title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", MUTED_COLOR)
	box.add_child(_hint)

	var controls := Label.new()
	controls.text = "点击画面或按任意键开始  ·  WASD / 方向键移动  ·  R 重启  ·  Esc 暂停"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_font_size_override("font_size", 15)
	controls.add_theme_color_override("font_color", TEXT_COLOR)
	box.add_child(controls)
