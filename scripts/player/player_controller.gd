extends CharacterBody3D
class_name PlayerController

## 第一人称骑行：油门、刹车和摩托车式转向。
## W/S 控制车速，A/D 转车把并带动整车转向；转率随车速变化，静止时不能原地转身。
## 视角只在骑手头上转动，不改变车头方向和前进方向。

@export_group("Movement")
## 最高车速（米/秒）。
@export var move_speed := 9.0
## 倒车最高速度（米/秒）。
@export var reverse_speed := 3.0
## 起步时的加速度（米/秒²），越接近最高车速加速越弱。
@export var acceleration := 10.0
## 刹车减速度（米/秒²）。
@export var brake_deceleration := 18.0
## 倒车起步加速度（米/秒²）。
@export var reverse_acceleration := 6.0
## 滑行时固定的滚动阻力减速（米/秒²）。
@export var coast_deceleration := 3.0
## 滑行时随车速增加的风阻减速（米/秒²，满速时）。
@export var coast_drag := 3.0
@export var mouse_sensitivity := 0.0025
@export var gravity := 9.8

@export_group("Touch Look")
## 触屏拖动一屏宽转过的角度；按视口比例换算，避免高像素密度手机上一划就转好几圈。
@export var touch_yaw_per_screen := TAU * 0.6
## 触屏拖动一屏高转过的角度。
@export var touch_pitch_per_screen := PI * 0.55
## 触屏低头极限，比鼠标小，避免镜头一路压到车顶。
@export var touch_pitch_limit := deg_to_rad(60.0)

@export_group("Scooter Steering")
## 在 Inspector 中拖入 GLB 里的 Empty 节点
@export var steering_pivot: Node3D

## 车头最大左右转向角度
@export var max_steer_angle := 30.0

## 车把转到满舵的最大角速度（度/秒），按下 A/D 时按这个速度跟手。
@export var steer_speed := 160.0

## 满舵且车速达到 steer_full_speed 时整车的转向角速度（度/秒）。
@export var max_turn_rate := 105.0

## 车速达到该值才给满舵转率；车速越低转得越慢，静止时不能转身。
@export var steer_full_speed := 5.0

@onready var camera: Camera3D = $Camera3D
@onready var body_model: Node3D = get_node_or_null("电鸡模型")

## 菜单、接单和结算期间关闭移动与视角，避免鼠标操作界面时角色跟着转。
var controls_enabled := true

var _pitch := 0.0
## 相机相对车头的水平转角；视角自由转动，不影响行进方向。
var _yaw := 0.0
var _steer_base_y := 0.0

## 当前车速（米/秒，负数为倒车）和车把角度（弧度，左正右负）。
var _speed := 0.0
var _steer_angle := 0.0


func _ready() -> void:
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.PLAYER_MASK

	if controls_enabled:
		_capture_mouse_if_supported()

	if steering_pivot:
		_steer_base_y = steering_pivot.rotation.y
	else:
		push_warning("未指定 Steering Pivot！")


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if enabled:
		_capture_mouse_if_supported()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_steer_angle = 0.0


## 触屏设备没有可捕获的鼠标，保持可见指针，视角交给 TouchControls。
func _capture_mouse_if_supported() -> void:
	if DisplayServer.is_touchscreen_available():
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion \
	and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative)


## 鼠标视角入口；参数为像素位移。
func apply_look(relative: Vector2) -> void:
	if not controls_enabled or relative == Vector2.ZERO:
		return
	_apply_look_radians(
		-relative.x * mouse_sensitivity,
		-relative.y * mouse_sensitivity,
		deg_to_rad(89.0)
	)


## 触屏视角入口；参数为画布像素位移，按视口尺寸归一化后再换算角度。
func apply_look_touch(relative: Vector2) -> void:
	if not controls_enabled or relative == Vector2.ZERO:
		return
	var view_size := get_viewport().get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	_apply_look_radians(
		-relative.x / view_size.x * touch_yaw_per_screen,
		-relative.y / view_size.y * touch_pitch_per_screen,
		touch_pitch_limit
	)


func _apply_look_radians(
	yaw_delta: float,
	pitch_delta: float,
	pitch_limit: float
) -> void:
	if not controls_enabled or (yaw_delta == 0.0 and pitch_delta == 0.0):
		return

	# 1. 水平视角：只转相机，不改车头朝向和前进方向
	_yaw = wrapf(_yaw + yaw_delta, -PI, PI)

	# 2. 上下视角控制
	_pitch = clampf(
		_pitch + pitch_delta,
		-pitch_limit,
		pitch_limit
	)

	camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if steering_pivot == null:
		return

	# 车把跟 A/D：平滑到当前转向角，松键后自然回正。
	steering_pivot.rotation.y = lerp_angle(
		steering_pivot.rotation.y,
		_steer_base_y + _steer_angle,
		1.0 - exp(-24.0 * delta)
	)


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_back"
		)

	_update_speed(-input.y, delta)
	_update_steering(input.x, delta)

	var forward := -transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.000001:
		forward = forward.normalized()
	velocity.x = forward.x * _speed
	velocity.z = forward.z * _speed

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()


func _update_speed(throttle: float, delta: float) -> void:
	## throttle 正向为油门、负向先刹车再倒车。
	## 加速力随车速上升而衰减，滑行时按滚阻加风阻减速，接近真实车辆的手感。
	if throttle > 0.01:
		if _speed < 0.0:
			_speed = move_toward(_speed, 0.0, brake_deceleration * delta)
		else:
			var ratio := clampf(_speed / move_speed, 0.0, 1.0)
			var drive := acceleration * throttle * (1.0 - ratio)
			_speed = minf(_speed + drive * delta, move_speed)
	elif throttle < -0.01:
		if _speed > 0.0:
			_speed = move_toward(
				_speed, 0.0, brake_deceleration * -throttle * delta
			)
		else:
			var ratio := clampf(-_speed / reverse_speed, 0.0, 1.0)
			var drive := reverse_acceleration * -throttle * (1.0 - ratio)
			_speed = maxf(_speed - drive * delta, -reverse_speed)
	else:
		var ratio := clampf(absf(_speed) / move_speed, 0.0, 1.0)
		var drag := coast_deceleration + coast_drag * ratio * ratio
		_speed = move_toward(_speed, 0.0, drag * delta)


func _update_steering(steer_axis: float, delta: float) -> void:
	## A/D 直接控制车把角度，再由车速换算出整车转率。
	var max_steer_rad := deg_to_rad(max_steer_angle)
	if max_steer_rad <= 0.0:
		return
	# 动作里 move_left 为负 x，所以左转取正角度。
	var target_angle := -steer_axis * max_steer_rad
	_steer_angle = move_toward(
		_steer_angle,
		target_angle,
		deg_to_rad(steer_speed) * delta
	)
	if absf(_speed) < 0.05:
		return
	var speed_ratio := clampf(absf(_speed) / steer_full_speed, 0.0, 1.0)
	# 车速越高转向越迟钝，接近最高车速时转率压到六成多。
	speed_ratio *= 1.0 - 0.35 * clampf(absf(_speed) / move_speed, 0.0, 1.0)
	var steer_ratio := _steer_angle / max_steer_rad
	var yaw_delta := (
		deg_to_rad(max_turn_rate)
		* steer_ratio
		* speed_ratio
		* signf(_speed)
		* delta
	)
	rotate_y(yaw_delta)


func reset_to(start: SpawnPoint) -> void:
	if start == null:
		return

	global_position = start.position
	rotation = Vector3(
		0.0,
		start.facing_yaw,
		0.0
	)

	velocity = Vector3.ZERO

	_pitch = 0.0
	_yaw = 0.0
	_speed = 0.0
	_steer_angle = 0.0

	camera.rotation = Vector3.ZERO

	if steering_pivot:
		steering_pivot.rotation.y = _steer_base_y

	reset_physics_interpolation()
