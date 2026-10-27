extends RefCounted
class_name OrderGenerator

## 从已生成的城市和已就绪的导航中确定性地选择一单。
## 起点来自 CityContent.player_starts；商家和顾客必须与起点两两可达。
## 同一城市种子和订单种子总是得到相同的起点、站点和路径长度。

const ORDER_RNG_SALT := 0x0D3E5EED


static func generate(
	city: CityContent,
	network: RoadNetwork,
	navigation: NavigationService,
	order_seed: int
) -> DeliveryOrder:
	if city == null or network == null or navigation == null:
		return null
	if not navigation.is_ready():
		return null
	var starts := city.get_available_player_starts()
	if starts.is_empty():
		return null
	var merchants: Array[CitySite] = []
	var customers: Array[CitySite] = []
	for site in city.sites:
		if site == null or site.spawn_point == null:
			continue
		if site.kind == CitySite.Kind.MERCHANT:
			merchants.append(site)
		elif site.kind == CitySite.Kind.RESIDENTIAL:
			customers.append(site)
	if merchants.is_empty() or customers.is_empty():
		return null

	var rng := RandomNumberGenerator.new()
	rng.seed = network.seed_value ^ order_seed ^ ORDER_RNG_SALT
	_shuffle(starts, rng)
	_shuffle(merchants, rng)
	_shuffle(customers, rng)

	for start in starts:
		var from := navigation.get_closest_point(start.position)
		if not from.is_finite():
			continue
		for merchant in merchants:
			var pickup_target := navigation.get_closest_point(merchant.spawn_point.position)
			if not pickup_target.is_finite():
				continue
			var pickup_path := navigation.find_path(from, pickup_target)
			if pickup_path.size() < 2:
				continue
			var pickup_length := NavigationService.get_path_length(pickup_path)
			if pickup_length <= 0.0:
				continue
			for customer in customers:
				if customer.id == merchant.id:
					continue
				var delivery_target := navigation.get_closest_point(customer.spawn_point.position)
				if not delivery_target.is_finite():
					continue
				var delivery_path := navigation.find_path(pickup_target, delivery_target)
				if delivery_path.size() < 2:
					continue
				var delivery_length := NavigationService.get_path_length(delivery_path)
				if delivery_length <= 0.0:
					continue
				var order := DeliveryOrder.new()
				order.city_seed = network.seed_value
				order.order_seed = order_seed
				order.start = start
				order.merchant = merchant
				order.customer = customer
				order.pickup_path_length_m = pickup_length
				order.delivery_path_length_m = delivery_length
				if order.is_valid(network):
					return order
	return null


static func signature(order: DeliveryOrder) -> String:
	if order == null:
		return ""
	var start := order.start
	if start == null:
		return ""
	return "%d|%s|%s|%.3f|%.3f" % [
		start.road_edge_id,
		order.merchant.id if order.merchant != null else &"",
		order.customer.id if order.customer != null else &"",
		start.position.x,
		start.position.z,
	]


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temp = values[index]
		values[index] = values[other]
		values[other] = temp
