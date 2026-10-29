
extends Node
class_name MotorcycleAudio

enum State { IDLE, STARTING, DRIVING, STOPPING, REVERSING }

@export_range(0.05, 3.0, 0.01) var move_enter_mps := 0.35
@export_range(0.01, 2.0, 0.01) var move_exit_mps := 0.12
@export_range(1.0, 50.0, 0.1) var max_speed_mps := 23.0
@export_range(0.01, 1.0, 0.01) var fade_time_s := 0.18
@export_range(0.5, 2.0, 0.01) var min_drive_pitch := 0.82
@export_range(0.5, 2.0, 0.01) var max_drive_pitch := 1.24
@export_range(-60.0, 6.0, 0.1) var drive_volume_db := -5.0

@export_group("Shift Pitch")
## 按住 W + Shift 后，Drive 循环最终保持的固定音高。
@export_range(1.0, 3.0, 0.01) var shift_drive_pitch := 1.70
## Shift 按下后，从正常音高升到加速音高的过渡时长（秒）。
@export_range(0.1, 3.0, 0.05) var shift_pitch_rise_time_s := 0.75
## Shift 松开后，返回正常车速音高的过渡时长（秒）。
@export_range(0.1, 3.0, 0.05) var shift_pitch_fall_time_s := 0.45

@onready var _player: PlayerController = get_parent() as PlayerController
@onready var _start: AudioStreamPlayer = $Start
@onready var _drive: AudioStreamPlayer = $Drive
@onready var _stop: AudioStreamPlayer = $Stop

var state := State.IDLE
var _drive_level := 0.0
var _shift_pitch_blend := 0.0


func _ready() -> void:
	reset_audio()
	if _drive.stream is AudioStreamMP3:
		(_drive.stream as AudioStreamMP3).loop = true
	elif _drive.stream is AudioStreamOggVorbis:
		(_drive.stream as AudioStreamOggVorbis).loop = true
	_start.finished.connect(_on_start_finished)
	_stop.finished.connect(_on_stop_finished)


func _physics_process(delta: float) -> void:
	if _player == null:
		return

	# 根据玩家实际移动速度驱动声音
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var actual := _player.get_real_velocity()
	actual.y = 0.0

	update_for_speed(actual.dot(forward), delta)


func update_for_speed(signed_speed_mps: float, delta: float) -> void:
	var moving_forward := signed_speed_mps >= move_enter_mps
	var moving_back := signed_speed_mps <= -move_enter_mps
	var nearly_stopped := absf(signed_speed_mps) <= move_exit_mps

	match state:
		State.IDLE, State.STOPPING:
			if moving_forward:
				_begin_start()
			elif moving_back:
				_begin_reverse()

		State.STARTING, State.DRIVING:
			if moving_back:
				_begin_reverse()
			elif nearly_stopped:
				_begin_stop()

		State.REVERSING:
			if moving_forward:
				_begin_start()
			elif nearly_stopped:
				state = State.IDLE

	var target := 0.0

	if state == State.DRIVING:
		target = clampf(
			signed_speed_mps / max_speed_mps,
			0.0,
			1.0
		)

	_drive_level = move_toward(
		_drive_level,
		target,
		delta / maxf(fade_time_s, 0.01)
	)

	if _drive.playing:
		# 原有音量渐变
		_drive.volume_db = (
			drive_volume_db
			+ linear_to_db(maxf(_drive_level, 0.001))
		)

		# 正常行驶：保持原来的速度相关音高
		var base_pitch := lerpf(
			min_drive_pitch,
			max_drive_pitch,
			target
		)

		# 检测 W + Shift
		var shift_boosting := (
			state == State.DRIVING
			and _player != null
			and _player.controls_enabled
			and Input.is_key_pressed(KEY_SHIFT)
			and Input.is_action_pressed("move_forward")
			and not Input.is_action_pressed("move_back")
		)

		# 按住 Shift 升至 1.0，松开降至 0.0
		var desired_blend := 1.0 if shift_boosting else 0.0

		var blend_time := (
			shift_pitch_rise_time_s
			if shift_boosting
			else shift_pitch_fall_time_s
		)

		_shift_pitch_blend = move_toward(
			_shift_pitch_blend,
			desired_blend,
			delta / maxf(blend_time, 0.01)
		)

		# 在普通行驶音高和 Shift 高音之间平滑过渡
		_drive.pitch_scale = lerpf(
			base_pitch,
			shift_drive_pitch,
			_shift_pitch_blend
		)

		if _drive_level <= 0.001 and state != State.DRIVING:
			_drive.stop()


func reset_audio() -> void:
	state = State.IDLE
	_drive_level = 0.0
	_shift_pitch_blend = 0.0

	_start.stop()
	_drive.stop()
	_stop.stop()

	_drive.volume_db = -80.0


func _begin_start() -> void:
	_stop.stop()
	_drive.stop()

	_drive_level = 0.0
	_shift_pitch_blend = 0.0

	_start.stop()

	state = State.STARTING
	_start.play()


func _begin_drive() -> void:
	state = State.DRIVING
	_drive.volume_db = -80.0
	_drive.play()


func _begin_stop() -> void:
	_start.stop()
	state = State.STOPPING

	_stop.stop()
	_stop.play()


func _begin_reverse() -> void:
	_start.stop()
	_stop.stop()

	state = State.REVERSING

	# 倒车保持原来的静音逻辑


func _on_start_finished() -> void:
	if state == State.STARTING:
		_begin_drive()


func _on_stop_finished() -> void:
	if state == State.STOPPING:
		state = State.IDLE
