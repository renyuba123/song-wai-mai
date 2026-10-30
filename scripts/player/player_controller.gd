extends CharacterBody3D
class_name PlayerController

## 第一人称骑行：油门、刹车和摩托车式转向。
## W/S 控制车速，A/D 转车把并带动整车转向；转率随车速变化，静止时不能原地转身。
## 视角只在骑手头上转动，不改变车头方向和前进方向。

signal pedestrian_hit(pedestrian: Pedestrian, compensation: int)

const PEDESTRIAN_COMPENSATION := 1000
const PEDESTRIAN_SLOWDOWN_DURATION_S := 2.5
const PEDESTRIAN_SLOWDOWN_MULTIPLIER := 0.42
const PEDESTRIAN_MIN_IMPACT_SPEED_MPS := 1.5
const PEDESTRIAN_HIT_SIZE := Vector3(1.3, 1.8, 2.8)
const PEDESTRIAN_HIT_CENTER := Vector3(0.0, 0.9, -0.45)
const WEB_POST_PROCESS_SHADER := preload("res://assets/Shaders/edge_detection_web.gdshader")

@export_group("Movement")
## 最高车速（米/秒）。交接包把车流提速到 18 m/s，主控需要更快才能穿插。
@export var move_speed := 23.0
## 按住 Shift 且向前行驶时的速度、加速度倍率（松开恢复原值）。
@export var shift_boost_speed_multiplier := 1.5
@export var shift_boost_acceleration_multiplier := 1.5
## 倒车最高速度（米/秒）。
@export var reverse_speed := 3.0
## 起步时的加速度（米/秒²），越接近最高车速加速越弱。
## 23 m/s 的最高车速要在大约四秒内跑到九成，靠的就是这个更大的起步推力。
@export var acceleration := 20.0
## 刹车减速度（米/秒²）。
@export var brake_deceleration := 26.0
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

@export_group("Speedometer")
@export var speedometer_needle: Node3D
## 表盘满刻度对应的实际车速（公里/小时）。
@export_range(1.0, 300.0, 1.0) var speedometer_max_kmh := 130.0
## 指针在零速和满刻度时相对模型原始姿态的角度。
@export_range(-180.0, 180.0, 1.0) var needle_zero_angle := 90.0
@export_range(-180.0, 180.0, 1.0) var needle_max_angle := -90.0

@onready var camera: Camera3D = $Camera3D
@onready var body_model: Node3D = get_node_or_null("电鸡模型")

## 菜单、接单和结算期间关闭移动与视角，避免鼠标操作界面时角色跟着转。
var controls_enabled := true

var _pitch := 0.0
## 相机相对车头的水平转角；视角自由转动，不影响行进方向。
var _yaw := 0.0
var _steer_base_y := 0.0
var _needle_base_y := 0.0
var _pedestrian_hit_area: Area3D = null
var _pedestrian_slowdown_remaining := 0.0
var _hit_pedestrian_ids := {}
var _pending_pedestrians := {}

## 当前车速（米/秒，负数为倒车）和车把角度（弧度，左正右负）。
var _speed := 0.0
var _steer_angle := 0.0


func _ready() -> void:
	_configure_post_process_shader()
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.PLAYER_MASK
	_ensure_pedestrian_hit_area()

	if controls_enabled:
		_capture_mouse_if_supported()

	if steering_pivot:
		_steer_base_y = steering_pivot.rotation.y
	else:
		push_warning("未指定 Steering Pivot！")
	if speedometer_needle:
		_needle_base_y = speedometer_needle.rotation.y
		speedometer_needle.rotation.y = _needle_base_y + deg_to_rad(needle_zero_angle)


func _configure_post_process_shader() -> void:
	if not OS.has_feature("web"):
		return
	var post_process := camera.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if post_process == null or post_process.mesh == null:
		return
	var original_material := post_process.mesh.material as ShaderMaterial
	if original_material == null:
		return
	var web_material := original_material.duplicate() as ShaderMaterial
	web_material.shader = WEB_POST_PROCESS_SHADER
	var web_mesh := post_process.mesh.duplicate() as Mesh
	web_mesh.material = web_material
	post_process.mesh = web_mesh


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
	_update_speedometer(delta)
	if steering_pivot == null:
		return

	# 车把跟 A/D：平滑到当前转向角，松键后自然回正。
	steering_pivot.rotation.y = lerp_angle(
		steering_pivot.rotation.y,
		_steer_base_y + _steer_angle,
		1.0 - exp(-24.0 * delta)
	)


func _update_speedometer(delta: float) -> void:
	if speedometer_needle == null:
		return
	# CharacterBody3D 的实际位移速度可反映碰撞后的车速；忽略垂直下落。
	var actual_velocity := get_real_velocity()
	var speed_kmh := Vector2(actual_velocity.x, actual_velocity.z).length() * 3.6
	var speed_ratio := clampf(speed_kmh / maxf(speedometer_max_kmh, 1.0), 0.0, 1.0)
	var target_angle := _needle_base_y + deg_to_rad(
		lerpf(needle_zero_angle, needle_max_angle, speed_ratio)
	)
	speedometer_needle.rotation.y = lerpf(
		speedometer_needle.rotation.y,
		target_angle,
		1.0 - exp(-12.0 * delta)
	)


func _physics_process(delta: float) -> void:
	if _pedestrian_slowdown_remaining > 0.0:
		_pedestrian_slowdown_remaining = maxf(
			_pedestrian_slowdown_remaining - delta,
			0.0
		)

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
	_process_pending_pedestrian_hits()


func get_pedestrian_hit_area() -> Area3D:
	return _pedestrian_hit_area


func get_pedestrian_speed_multiplier() -> float:
	return (
		PEDESTRIAN_SLOWDOWN_MULTIPLIER
		if _pedestrian_slowdown_remaining > 0.0
		else 1.0
	)


func get_pedestrian_slowdown_remaining() -> float:
	return _pedestrian_slowdown_remaining


func get_planar_velocity() -> Vector2:
	return Vector2(velocity.x, velocity.z)


func get_planar_speed() -> float:
	return get_planar_velocity().length()


## 当前车速（米/秒，负数为倒车）；输入自检面板用它显示车速。
func get_current_speed_mps() -> float:
	return _speed


## 车头相对初始朝向的角度，用于 HUD 显示。
func get_heading_degrees() -> float:
	return fposmod(rad_to_deg(rotation.y), 360.0)


func handle_pedestrian_impact(pedestrian: Pedestrian) -> bool:
	if not controls_enabled or not is_instance_valid(pedestrian):
		return false
	var pedestrian_id := pedestrian.get_instance_id()
	if _hit_pedestrian_ids.has(pedestrian_id):
		return false
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if planar_speed < PEDESTRIAN_MIN_IMPACT_SPEED_MPS:
		return false

	_hit_pedestrian_ids[pedestrian_id] = true
	_pedestrian_slowdown_remaining = PEDESTRIAN_SLOWDOWN_DURATION_S
	var slowed_speed := planar_speed * PEDESTRIAN_SLOWDOWN_MULTIPLIER
	velocity.x = velocity.x / planar_speed * slowed_speed
	velocity.z = velocity.z / planar_speed * slowed_speed
	# _physics_process 每帧会按 _speed 重算水平速度，这里同步压低车速。
	_speed *= PEDESTRIAN_SLOWDOWN_MULTIPLIER
	pedestrian_hit.emit(pedestrian, PEDESTRIAN_COMPENSATION)
	return true


func _ensure_pedestrian_hit_area() -> void:
	if is_instance_valid(_pedestrian_hit_area):
		return
	_pedestrian_hit_area = Area3D.new()
	_pedestrian_hit_area.name = "PedestrianHitArea"
	_pedestrian_hit_area.position = PEDESTRIAN_HIT_CENTER
	_pedestrian_hit_area.collision_layer = CollisionLayers.TRIGGER
	_pedestrian_hit_area.collision_mask = CollisionLayers.PEDESTRIAN
	_pedestrian_hit_area.monitoring = true
	_pedestrian_hit_area.monitorable = false
	var collision := CollisionShape3D.new()
	collision.name = "HitShape"
	var shape := BoxShape3D.new()
	shape.size = PEDESTRIAN_HIT_SIZE
	collision.shape = shape
	_pedestrian_hit_area.add_child(collision)
	_pedestrian_hit_area.body_entered.connect(
		_on_pedestrian_hit_body_entered
	)
	_pedestrian_hit_area.body_exited.connect(
		_on_pedestrian_hit_body_exited
	)
	add_child(_pedestrian_hit_area)


func _on_pedestrian_hit_body_entered(body: Node3D) -> void:
	if body is Pedestrian:
		var pedestrian := body as Pedestrian
		_pending_pedestrians[pedestrian.get_instance_id()] = pedestrian
		handle_pedestrian_impact(pedestrian)


func _on_pedestrian_hit_body_exited(body: Node3D) -> void:
	if body is Pedestrian:
		_pending_pedestrians.erase(body.get_instance_id())


## body_entered 只触发一次；保持重叠列表，静止贴住行人后起步仍能补结算。
func _process_pending_pedestrian_hits() -> void:
	for pedestrian_id in _pending_pedestrians.keys():
		var pedestrian = _pending_pedestrians.get(pedestrian_id)
		if not is_instance_valid(pedestrian):
			_pending_pedestrians.erase(pedestrian_id)
			continue
		handle_pedestrian_impact(pedestrian as Pedestrian)


func _update_speed(throttle: float, delta: float) -> void:
	## throttle 正向为油门、负向先刹车再倒车。
	## 加速力随车速上升而衰减，滑行时按滚阻加风阻减速，接近真实车辆的手感。
	## 撞到行人的 2.5 秒内最高车速按倍率压低，油门输入仍然有效。
	var shift_boosting := controls_enabled and throttle > 0.01 and Input.is_key_pressed(KEY_SHIFT)
	var max_speed := move_speed * get_pedestrian_speed_multiplier()
	if shift_boosting:
		max_speed *= shift_boost_speed_multiplier
	if throttle > 0.01:
		if _speed < 0.0:
			_speed = move_toward(_speed, 0.0, brake_deceleration * delta)
		else:
			var ratio := clampf(_speed / max_speed, 0.0, 1.0)
			var drive := acceleration * throttle * (1.0 - ratio)
			if shift_boosting:
				drive *= shift_boost_acceleration_multiplier
			_speed = minf(_speed + drive * delta, max_speed)
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
		var ratio := clampf(absf(_speed) / max_speed, 0.0, 1.0)
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
	if has_node("MotorcycleAudio"):
		$MotorcycleAudio.reset_audio()

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
	_pedestrian_slowdown_remaining = 0.0
	_hit_pedestrian_ids.clear()
	_pending_pedestrians.clear()

	camera.rotation = Vector3.ZERO

	if steering_pivot:
		steering_pivot.rotation.y = _steer_base_y

	reset_physics_interpolation()
