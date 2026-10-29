extends CanvasLayer
class_name TouchControls

## 手机浏览器用的触屏层：左下摇杆移动，右半屏拖动视角，右下三个按钮。
## 只在玩家可操作（配送进行中）时显示；菜单和结算仍用界面按钮。

const JOY_RADIUS := 90.0
const JOY_DEADZONE := 0.15
const LOOK_GAIN := 1.0
const BUTTON_SIZE := 68.0
const BUTTON_MARGIN := 24.0

## 测试用：无触屏环境也能强制创建。
static var force_enabled := false


## 手机浏览器或触屏设备；桌面端保持键盘鼠标。
static func is_touch_device() -> bool:
	return (
		force_enabled
		or DisplayServer.is_touchscreen_available()
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)

var player: PlayerController = null

var _overlay: Control
var _buttons: Array[Button] = []
var _rest_origin := Vector2.ZERO
var _joy_index := -1
var _look_index := -1
var _joy_origin := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _active := false


func setup(target: PlayerController) -> void:
	player = target


func _ready() -> void:
	layer = 100
	_build()
	_layout()
	_apply_visibility(false)
	get_viewport().size_changed.connect(_layout)


## 摇杆位移（像素）换算成 -1..1 的轴向值，带死区和长度截断。
static func joystick_axis(offset: Vector2, radius: float = JOY_RADIUS) -> Vector2:
	var axis := offset / radius
	if axis.length() > 1.0:
		axis = axis.normalized()
	if absf(axis.x) < JOY_DEADZONE:
		axis.x = 0.0
	if absf(axis.y) < JOY_DEADZONE:
		axis.y = 0.0
	return axis


func _build() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)

	_add_button("interact", "E", "取餐/送达")
	_add_button("restart", "R", "重新开始")
	_add_button("pause", "Ⅱ", "暂停")


func _add_button(action: String, label: String, hint: String) -> void:
	var button := Button.new()
	button.text = label
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 26)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.0, 0.0, 0.42)
	normal.border_color = Color(1.0, 1.0, 1.0, 0.55)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(int(BUTTON_SIZE / 2.0))
	button.add_theme_stylebox_override("normal", normal)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1.0, 0.55, 0.18, 0.75)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover", normal)

	button.pressed.connect(_emit_action.bind(action))
	add_child(button)
	_buttons.append(button)


func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_overlay.position = Vector2.ZERO
	_overlay.size = viewport_size
	_rest_origin = Vector2(
		JOY_RADIUS + BUTTON_MARGIN + 12.0,
		viewport_size.y - JOY_RADIUS - BUTTON_MARGIN - 12.0
	)
	if _buttons.size() == 3:
		var right := viewport_size.x - BUTTON_MARGIN - BUTTON_SIZE
		var bottom := viewport_size.y - BUTTON_MARGIN - BUTTON_SIZE
		_buttons[0].position = Vector2(right, bottom - BUTTON_SIZE - 16.0)
		_buttons[1].position = Vector2(right, bottom)
		_buttons[2].position = Vector2(right - BUTTON_SIZE - 16.0, bottom)
		_buttons[0].size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		_buttons[1].size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		_buttons[2].size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	_overlay.queue_redraw()


func _process(_delta: float) -> void:
	if player == null:
		return
	var should_show := player.controls_enabled
	if should_show == _active:
		return
	_apply_visibility(should_show)
	if not should_show:
		_joy_index = -1
		_look_index = -1
		_set_joystick(Vector2.ZERO)
		_overlay.queue_redraw()


func _apply_visibility(visible_now: bool) -> void:
	_active = visible_now
	_overlay.visible = visible_now
	for button in _buttons:
		button.visible = visible_now


func _input(event: InputEvent) -> void:
	if not _active or player == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event)
		else:
			_touch_up(event)
	elif event is InputEventScreenDrag:
		_drag(event)


func _touch_down(event: InputEventScreenTouch) -> void:
	if _point_on_button(event.position):
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var in_joystick_zone := (
		event.position.x < viewport_size.x * 0.5
		and event.position.y > viewport_size.y * 0.45
	)
	if in_joystick_zone:
		if _joy_index == -1:
			_joy_index = event.index
			_joy_origin = event.position
			_joy_knob = event.position
			_set_joystick(Vector2.ZERO)
			_overlay.queue_redraw()
		return

	if _look_index == -1:
		_look_index = event.index


func _touch_up(event: InputEventScreenTouch) -> void:
	if event.index == _joy_index:
		_joy_index = -1
		_set_joystick(Vector2.ZERO)
		_overlay.queue_redraw()
	elif event.index == _look_index:
		_look_index = -1


func _drag(event: InputEventScreenDrag) -> void:
	if event.index == _joy_index:
		var offset := event.position - _joy_origin
		if offset.length() > JOY_RADIUS:
			offset = offset.normalized() * JOY_RADIUS
		_joy_knob = _joy_origin + offset
		_set_joystick(joystick_axis(offset))
		_overlay.queue_redraw()
	elif event.index == _look_index:
		player.apply_look(event.relative * LOOK_GAIN)


func _set_joystick(axis: Vector2) -> void:
	_press_axis("move_right", maxf(axis.x, 0.0))
	_press_axis("move_left", maxf(-axis.x, 0.0))
	_press_axis("move_back", maxf(axis.y, 0.0))
	_press_axis("move_forward", maxf(-axis.y, 0.0))


func _press_axis(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _emit_action(action: String) -> void:
	if player == null or not player.controls_enabled:
		return
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _point_on_button(position: Vector2) -> bool:
	for button in _buttons:
		if button.visible and button.get_global_rect().has_point(position):
			return true
	return false


func _draw_overlay() -> void:
	var origin := _joy_origin if _joy_index != -1 else _rest_origin
	var knob := _joy_knob if _joy_index != -1 else _rest_origin

	_overlay.draw_circle(origin, JOY_RADIUS + 8.0, Color(0.0, 0.0, 0.0, 0.18))
	_overlay.draw_circle(origin, JOY_RADIUS, Color(1.0, 1.0, 1.0, 0.10))
	_overlay.draw_arc(
		origin, JOY_RADIUS, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.45), 3.0
	)
	_overlay.draw_circle(knob, 34.0, Color(1.0, 1.0, 1.0, 0.35))
	_overlay.draw_arc(
		knob, 34.0, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.75), 3.0
	)
