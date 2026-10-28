extends Node3D
class_name TestGodView

## 测试用上帝视角。只在调试/测试构建中由 main.gd 创建，
## 导出正式版本时不实例化，也不注册全局输入动作。
##
## F3 在主场景中切换上帝视角；WASD 平移，鼠标滚轮缩放。
## 开启时暂停玩家的物理移动并释放鼠标，关闭时恢复第一人称相机。

const TOGGLE_KEY := KEY_F3
const MIN_VIEW_SIZE := 40.0
const DEFAULT_VIEW_SIZE := 260.0
const PAN_FACTOR := 0.55
const HINT_TEXT := "测试上帝视角\nF3 返回玩家 · WASD 平移 · 滚轮缩放"

var camera: Camera3D = null

var _player: PlayerController = null
var _map_size := Vector2(2400.0, 2400.0)
var _target := Vector2.ZERO
var _view_size := DEFAULT_VIEW_SIZE
var _active := false
var _hint: Label = null


static func is_test_only_enabled() -> bool:
	return OS.is_debug_build()


func setup(player_node: PlayerController, map_size: Vector2) -> void:
	_player = player_node
	if map_size.x > RoadNetwork.EPS and map_size.y > RoadNetwork.EPS:
		_map_size = map_size
	if _player != null:
		_target = Vector2(_player.global_position.x, _player.global_position.z)
	_clamp_target()


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "GodCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _view_size
	camera.near = 0.05
	camera.far = maxf(_map_size.x, _map_size.y) * 2.0 + 200.0
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = false
	add_child(camera)
	_add_hint()
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == TOGGLE_KEY:
			toggle()
			get_viewport().set_input_as_handled()
			return
	if not _active or not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_view_size(_view_size * 0.88)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_view_size(_view_size / 0.88)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _active:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length_squared() <= 0.0:
		return
	# 相机朝下、屏幕上方对应 -Z；W 让 target.z 减小，画面向北平移。
	_target += Vector2(input.x, input.y) * (_view_size * PAN_FACTOR * delta)
	_clamp_target()
	_update_camera()


func set_active(value: bool) -> void:
	if value == _active:
		return
	_active = value
	if _active:
		_enter()
	else:
		_exit()


func toggle() -> void:
	set_active(not _active)


func is_active() -> bool:
	return _active


func _enter() -> void:
	if _player == null or camera == null:
		_active = false
		return
	_target = Vector2(_player.global_position.x, _player.global_position.z)
	_clamp_target()
	_update_camera()
	if _player.camera != null:
		_player.camera.current = false
	camera.current = true
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _hint != null:
		_hint.visible = true


func _exit() -> void:
	if camera != null:
		camera.current = false
	if _player != null:
		_player.set_physics_process(true)
		if _player.camera != null:
			_player.camera.current = true
	Input.set_mouse_mode(
		Input.MOUSE_MODE_CAPTURED
		if _player == null or _player.controls_enabled
		else Input.MOUSE_MODE_VISIBLE
	)
	if _hint != null:
		_hint.visible = false


func _set_view_size(value: float) -> void:
	var maximum := maxf(_map_size.x, _map_size.y) * 1.2
	_view_size = clampf(value, MIN_VIEW_SIZE, maximum)
	_clamp_target()
	_update_camera()


func _clamp_target() -> void:
	var half := _map_size * 0.5
	var half_view := _view_size * 0.5
	_target.x = _clamp_axis(_target.x, half.x, half_view)
	_target.y = _clamp_axis(_target.y, half.y, half_view)


func _clamp_axis(value: float, half_map: float, half_view: float) -> float:
	if half_view >= half_map:
		return 0.0
	return clampf(value, -half_map + half_view, half_map - half_view)


func _update_camera() -> void:
	if camera == null:
		return
	camera.size = _view_size
	camera.position = Vector3(_target.x, maxf(_map_size.x, _map_size.y) * 0.6 + 100.0, _target.y)


func _add_hint() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TestHint"
	layer.layer = 100
	add_child(layer)
	_hint = Label.new()
	_hint.position = Vector2(16.0, 16.0)
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color.WHITE)
	_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hint.add_theme_constant_override("shadow_offset_x", 2)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.text = HINT_TEXT
	_hint.visible = false
	layer.add_child(_hint)
