extends RefCounted
class_name OrderSession

## 单笔订单的纯状态机：取餐、送达、超时结算。
## 不依赖场景树，订单管理器只负责节点、输入、传送和界面。

enum State { TO_MERCHANT, TO_CUSTOMER, DELIVERED, FAILED }

const INTERACT_RADIUS_M := 4.0
const TIME_FACTOR := 1.6
const TIME_BUFFER_S := 30.0
const MIN_TIME_LIMIT_S := 60.0

signal state_changed(state: int)
signal finished(success: bool)

var order: DeliveryOrder = null
var state: int = State.TO_MERCHANT
var time_limit: float = 0.0
var time_remaining: float = 0.0


func _init(source_order: DeliveryOrder, player_speed_mps: float) -> void:
	order = source_order
	time_limit = calculate_time_limit(source_order, player_speed_mps)
	time_remaining = time_limit


static func calculate_time_limit(
	source_order: DeliveryOrder, player_speed_mps: float
) -> float:
	## 接单界面和实际会话共用同一套时限公式，避免展示值与倒计时不一致。
	var total := (
		source_order.get_total_path_length_m() if source_order != null else -1.0
	)
	var speed := maxf(player_speed_mps, 0.1)
	return maxf(MIN_TIME_LIMIT_S, total / speed * TIME_FACTOR + TIME_BUFFER_S)


func advance(delta: float) -> void:
	if not is_active() or delta <= 0.0:
		return
	time_remaining = maxf(0.0, time_remaining - delta)
	if time_remaining <= 0.0:
		_finish(false)


func try_interact(player_position: Vector3) -> bool:
	if not can_interact(player_position):
		return false
	if state == State.TO_MERCHANT:
		state = State.TO_CUSTOMER
		state_changed.emit(state)
		return true
	if state == State.TO_CUSTOMER:
		_finish(true)
		return true
	return false


func get_target_site() -> CitySite:
	if order == null:
		return null
	if state == State.TO_MERCHANT:
		return order.merchant
	if state == State.TO_CUSTOMER:
		return order.customer
	return null


func get_target_position() -> Vector3:
	var site := get_target_site()
	if site == null or site.spawn_point == null:
		return Vector3.INF
	return site.spawn_point.position


func get_distance_to_target(player_position: Vector3) -> float:
	var target := get_target_position()
	if not target.is_finite():
		return INF
	return Vector2(player_position.x, player_position.z).distance_to(
		Vector2(target.x, target.z)
	)


func can_interact(player_position: Vector3) -> bool:
	return is_active() and get_distance_to_target(player_position) <= INTERACT_RADIUS_M


func get_objective_text() -> String:
	match state:
		State.TO_MERCHANT:
			return "前往商家取餐"
		State.TO_CUSTOMER:
			return "送达顾客"
		State.DELIVERED:
			return "订单完成"
		State.FAILED:
			return "订单失败"
	return ""


func get_interact_prompt() -> String:
	if state == State.TO_MERCHANT:
		return "按 E 取餐"
	if state == State.TO_CUSTOMER:
		return "按 E 送达"
	return ""


func get_elapsed_s() -> float:
	return maxf(0.0, time_limit - time_remaining)


func is_active() -> bool:
	return state == State.TO_MERCHANT or state == State.TO_CUSTOMER


func is_finished() -> bool:
	return not is_active()


func is_success() -> bool:
	return state == State.DELIVERED


func _finish(success: bool) -> void:
	if not is_active():
		return
	state = State.DELIVERED if success else State.FAILED
	if not success:
		time_remaining = 0.0
	state_changed.emit(state)
	finished.emit(success)
