extends Resource
class_name DeliveryOrder

## 一单外卖任务的数据契约。订单状态机不在本资源里实现；这里只保存
## 可复现的城市/订单种子、起点、商家、顾客和两段导航路径长度。

const NO_ROUTE_DISTANCE := -1.0

@export var city_seed: int = 0
@export var order_seed: int = 0
@export var start: SpawnPoint = null
@export var merchant: CitySite = null
@export var customer: CitySite = null

## 从玩家起点到商家取餐点的导航路径长度，单位米。
@export var pickup_path_length_m: float = NO_ROUTE_DISTANCE

## 从商家取餐点到顾客送达点的导航路径长度，单位米。
@export var delivery_path_length_m: float = NO_ROUTE_DISTANCE


func validate(network: RoadNetwork = null) -> Array[String]:
	var errors: Array[String] = []
	if start == null:
		errors.append("订单缺少起点")
	else:
		if start.kind != SpawnPoint.Kind.PLAYER_START:
			errors.append("订单起点类型不是玩家起点")
		errors.append_array(start.validate(network))
	if merchant == null:
		errors.append("订单缺少商家")
	else:
		if merchant.kind != CitySite.Kind.MERCHANT:
			errors.append("订单商家类型不正确")
		errors.append_array(merchant.validate(network))
	if customer == null:
		errors.append("订单缺少顾客")
	else:
		if customer.kind != CitySite.Kind.RESIDENTIAL:
			errors.append("订单顾客类型不正确")
		errors.append_array(customer.validate(network))
	if merchant != null and customer != null and merchant.id == customer.id:
		errors.append("商家和顾客不能是同一个站点")
	if network != null and city_seed != network.seed_value:
		errors.append("订单城市种子与路网种子不一致")
	if not is_finite(pickup_path_length_m) or pickup_path_length_m < 0.0:
		errors.append("取餐路径长度未计算或无效")
	if not is_finite(delivery_path_length_m) or delivery_path_length_m < 0.0:
		errors.append("送达路径长度未计算或无效")
	return errors


func is_valid(network: RoadNetwork = null) -> bool:
	return validate(network).is_empty()


func get_total_path_length_m() -> float:
	if pickup_path_length_m < 0.0 or delivery_path_length_m < 0.0:
		return NO_ROUTE_DISTANCE
	return pickup_path_length_m + delivery_path_length_m
