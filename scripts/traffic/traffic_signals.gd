extends Node3D
class_name TrafficSignals

## Deterministic intersection phases shared by cars and pedestrians.
## Signal geometry is created only near the player; all intersections keep
## their logical phase without paying for full-map visual instances.

enum VehicleState {
	RED,
	YELLOW,
	GREEN,
}

const LIGHT_MODEL_PATH := "res://assets/models/装饰模型/红绿灯.glb"
const SIGNAL_HEIGHT_M := 5.4
const VISUAL_RADIUS_M := 260.0
const MAX_VISIBLE_SIGNALS := 8
const VISUAL_REFRESH_SECONDS := 1.0
const JUNCTION_MATCH_DISTANCE_M := 13.0
const VEHICLE_APPROACH_DISTANCE_M := 60.0
const RED_BRAKE_DISTANCE_M := 30.0
const YELLOW_COMMIT_DISTANCE_M := 7.0
const MAIN_CONTROLLER_RED_RADIUS_M := 42.0
const MAIN_CONTROLLER_RED_HOLD_SECONDS := 22.0
const GREEN_SECONDS := 12.0
const YELLOW_SECONDS := 3.0
const ALL_RED_SECONDS := 2.0
const PEDESTRIAN_SECONDS := 16.0
const PHASE_A_GREEN_START := 0.0
const PHASE_A_YELLOW_START := GREEN_SECONDS
const PHASE_B_GREEN_START := GREEN_SECONDS + YELLOW_SECONDS + ALL_RED_SECONDS
const PHASE_B_YELLOW_START := PHASE_B_GREEN_START + GREEN_SECONDS
const PEDESTRIAN_START := PHASE_B_YELLOW_START + YELLOW_SECONDS + ALL_RED_SECONDS
const CYCLE_SECONDS := PEDESTRIAN_START + PEDESTRIAN_SECONDS

const LAMP_RED := Color("ff4a3d")
const LAMP_YELLOW := Color("ffd45f")
const LAMP_GREEN := Color("58e68b")
const LAMP_OFF := Color("252b30")

var network: RoadNetwork = null

var _signal_nodes: Dictionary = {}
var _arm_directions: Dictionary = {}
var _phase_seconds := 0.0
var _phase_seed_offset := 0.0
var _player: Node3D = null
var _camera: Camera3D = null
var _visual_container: Node3D = null
var _visuals: Dictionary = {}
var _visual_clock := 0.0
var _model_scene: PackedScene = null
var _forced_red_remaining: Dictionary = {}
var _forced_red_groups: Dictionary = {}


func build(source_network: RoadNetwork) -> void:
	_clear()
	network = source_network
	if network == null or network.nodes.is_empty():
		return
	_phase_seed_offset = float(posmod(network.seed_value, 997)) * 0.071
	_phase_seconds = 0.0

	var arms_by_node: Dictionary = {}
	for node_id in network.nodes.size():
		var empty_arms: Array[Vector2] = []
		arms_by_node[node_id] = empty_arms
	for edge in network.edges:
		var a := int(edge.a)
		var b := int(edge.b)
		var delta: Vector2 = network.nodes[b] - network.nodes[a]
		if delta.length_squared() <= RoadNetwork.EPS * RoadNetwork.EPS:
			continue
		var direction := delta.normalized()
		var arms_a := _arms_from_dict(arms_by_node, a)
		var arms_b := _arms_from_dict(arms_by_node, b)
		arms_a.append(direction)
		arms_b.append(-direction)
		arms_by_node[a] = arms_a
		arms_by_node[b] = arms_b

	for node_id in network.nodes.size():
		var arms := _arms_from_dict(arms_by_node, node_id)
		if arms.size() < 3:
			continue
		_signal_nodes[node_id] = true
		_arm_directions[node_id] = arms

	if not _signal_nodes.is_empty() and DisplayServer.get_name() != "headless":
		_model_scene = load(LIGHT_MODEL_PATH) as PackedScene
		if _model_scene == null:
			push_warning("TrafficSignals: unable to load %s" % LIGHT_MODEL_PATH)
		_visual_container = Node3D.new()
		_visual_container.name = "SignalVisuals"
		add_child(_visual_container)
		_refresh_visuals(true)


func set_player(player: Node3D) -> void:
	_player = player
	_camera = player.get_node_or_null("Camera3D") if player != null else null
	_refresh_visuals(true)


func is_signalized(node_id: int) -> bool:
	return _signal_nodes.has(node_id)


func get_signal_node_ids() -> Array[int]:
	var result: Array[int] = []
	for node_id in _signal_nodes:
		result.append(int(node_id))
	result.sort()
	return result


func get_vehicle_state(node_id: int, incoming_direction: Vector2) -> VehicleState:
	if not _signal_nodes.has(node_id):
		return VehicleState.GREEN
	var group := _approach_group(node_id, incoming_direction)
	if is_main_controller_red(node_id):
		return (
			VehicleState.RED
			if group == get_main_controller_red_group(node_id)
			else VehicleState.GREEN
		)
	var phase := _node_phase(node_id)
	if (
		phase >= PHASE_A_GREEN_START
		and phase < PHASE_A_YELLOW_START
		and group == 0
	):
		return VehicleState.GREEN
	if (
		phase >= PHASE_A_YELLOW_START
		and phase < PHASE_A_YELLOW_START + YELLOW_SECONDS
		and group == 0
	):
		return VehicleState.YELLOW
	if (
		phase >= PHASE_B_GREEN_START
		and phase < PHASE_B_YELLOW_START
		and group == 1
	):
		return VehicleState.GREEN
	if (
		phase >= PHASE_B_YELLOW_START
		and phase < PHASE_B_YELLOW_START + YELLOW_SECONDS
		and group == 1
	):
		return VehicleState.YELLOW
	return VehicleState.RED


func can_vehicle_enter(node_id: int, incoming_direction: Vector2) -> bool:
	return get_vehicle_state(node_id, incoming_direction) == VehicleState.GREEN


func should_vehicle_stop(
	node_id: int,
	incoming_direction: Vector2,
	distance_to_junction: float,
	already_in_junction := false
) -> bool:
	if already_in_junction:
		return false
	var state := get_vehicle_state(node_id, incoming_direction)
	if state == VehicleState.RED:
		# A red light only controls the stop-line approach. Cars further back
		# keep moving until they reach the braking zone instead of freezing
		# anywhere on the road.
		return distance_to_junction <= RED_BRAKE_DISTANCE_M
	if state == VehicleState.YELLOW:
		return (
			distance_to_junction > YELLOW_COMMIT_DISTANCE_M
			and distance_to_junction <= RED_BRAKE_DISTANCE_M
		)
	return false


func can_pedestrian_cross(node_id: int) -> bool:
	if not _signal_nodes.has(node_id):
		return true
	if is_main_controller_red(node_id):
		return false
	var phase := _node_phase(node_id)
	return phase >= PEDESTRIAN_START and phase < CYCLE_SECONDS


func trigger_main_controller_red(
	node_id: int,
	incoming_direction: Vector2,
	hold_seconds := MAIN_CONTROLLER_RED_HOLD_SECONDS
) -> bool:
	if (
		not _signal_nodes.has(node_id)
		or incoming_direction.length_squared() <= 0.000001
		or hold_seconds <= 0.0
	):
		return false
	var group := _approach_group(node_id, incoming_direction)
	var current := float(_forced_red_remaining.get(node_id, 0.0))
	var group_changed := int(_forced_red_groups.get(node_id, -1)) != group
	_forced_red_remaining[node_id] = maxf(current, hold_seconds)
	_forced_red_groups[node_id] = group
	if current <= 0.0 or group_changed:
		_refresh_visual_states()
	return true


func is_main_controller_red(node_id: int) -> bool:
	return float(_forced_red_remaining.get(node_id, 0.0)) > 0.0


func get_forced_red_remaining(node_id: int) -> float:
	return maxf(float(_forced_red_remaining.get(node_id, 0.0)), 0.0)


func get_main_controller_red_group(node_id: int) -> int:
	return int(_forced_red_groups.get(node_id, -1))


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	_phase_seconds = fmod(_phase_seconds + delta, CYCLE_SECONDS)
	_advance_forced_red(delta)
	_refresh_main_controller_red()


func find_signal_node(
	position: Vector3,
	max_distance := JUNCTION_MATCH_DISTANCE_M
) -> int:
	if network == null or _signal_nodes.is_empty():
		return -1
	var point := Vector2(position.x, position.z)
	var closest_id := -1
	var closest_distance := max_distance
	for node_id in _signal_nodes:
		var distance := point.distance_to(network.nodes[int(node_id)])
		if distance < closest_distance:
			closest_distance = distance
			closest_id = int(node_id)
	return closest_id


func get_approach_group(node_id: int, incoming_direction: Vector2) -> int:
	return _approach_group(node_id, incoming_direction)


func set_phase_seconds(value: float) -> void:
	_phase_seconds = maxf(value, 0.0)
	_refresh_visual_states()


func get_phase_seconds() -> float:
	return _phase_seconds


func get_visible_signal_count() -> int:
	return _visuals.size()


func get_junction_position(node_id: int) -> Vector3:
	if network == null or node_id < 0 or node_id >= network.nodes.size():
		return Vector3.INF
	var point: Vector2 = network.nodes[node_id]
	return Vector3(point.x, RoadNetwork.SURFACE_Y, point.y)


func _physics_process(delta: float) -> void:
	advance(delta)
	_visual_clock += delta
	if _visual_clock >= VISUAL_REFRESH_SECONDS:
		_visual_clock = 0.0
		_refresh_visuals()
		_refresh_visual_states()


func _node_phase(node_id: int) -> float:
	var offset := _phase_seed_offset + float(node_id) * 1.37
	return fmod(_phase_seconds + offset, CYCLE_SECONDS)


func _advance_forced_red(delta: float) -> void:
	var expired := false
	for node_id in _forced_red_remaining.keys():
		var remaining := float(_forced_red_remaining[node_id]) - delta
		if remaining <= 0.0:
			_forced_red_remaining.erase(node_id)
			_forced_red_groups.erase(node_id)
			expired = true
		else:
			_forced_red_remaining[node_id] = remaining
	if expired:
		_refresh_visual_states()


func _refresh_main_controller_red() -> void:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		return
	var player_point := Vector2(_player.global_position.x, _player.global_position.z)
	var player_forward := -_player.global_transform.basis.z
	var incoming_direction := Vector2(player_forward.x, player_forward.z)
	if incoming_direction.length_squared() <= 0.000001:
		return
	incoming_direction = incoming_direction.normalized()
	for node_id in _signal_nodes:
		var junction := _junction_position(int(node_id))
		var distance := player_point.distance_to(Vector2(junction.x, junction.z))
		if distance <= MAIN_CONTROLLER_RED_RADIUS_M:
			trigger_main_controller_red(int(node_id), incoming_direction)


func _approach_group(node_id: int, incoming_direction: Vector2) -> int:
	if incoming_direction.length_squared() <= 0.000001:
		return 0
	var arms := _get_arm_directions(node_id)
	if arms.is_empty():
		return 0
	var reference := arms[0].normalized()
	return 0 if absf(reference.dot(incoming_direction.normalized())) >= 0.45 else 1


func _refresh_visuals(force := false) -> void:
	if (
		not force
		and (not is_instance_valid(_visual_container) or _signal_nodes.is_empty())
	):
		return
	if (
		not is_instance_valid(_visual_container)
		or _signal_nodes.is_empty()
		or DisplayServer.get_name() == "headless"
	):
		return
	var focus := (
		Vector3(_player.global_position.x, RoadNetwork.SURFACE_Y, _player.global_position.z)
		if is_instance_valid(_player)
		else _junction_position(_signal_nodes.keys()[0])
	)
	var nearby: Array[Dictionary] = []
	for node_id in _signal_nodes:
		var position := _junction_position(int(node_id))
		var distance := Vector2(
			position.x - focus.x,
			position.z - focus.z
		).length()
		if distance <= VISUAL_RADIUS_M:
			nearby.append({"id": int(node_id), "distance": distance})
	nearby.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if not is_equal_approx(float(first["distance"]), float(second["distance"])):
			return float(first["distance"]) < float(second["distance"])
		return int(first["id"]) < int(second["id"])
	)

	var keep: Dictionary = {}
	for index in mini(nearby.size(), MAX_VISIBLE_SIGNALS):
		var node_id := int(nearby[index]["id"])
		keep[node_id] = true
		if not _visuals.has(node_id):
			_create_visual(node_id)
	for node_id in _visuals.keys():
		if keep.has(node_id):
			continue
		var visual: Node3D = _visuals[node_id]
		_visuals.erase(node_id)
		if is_instance_valid(visual):
			visual.free()
	_refresh_visual_states()


func _create_visual(node_id: int) -> void:
	if _model_scene == null or not is_instance_valid(_visual_container):
		return
	var junction := _junction_position(node_id)
	var arms := _get_arm_directions(node_id)
	if arms.is_empty():
		return
	var half_width := _widest_redline(node_id) * 0.5
	var root := Node3D.new()
	root.name = "Signal%d" % node_id
	root.position = junction
	_visual_container.add_child(root)

	var reference := arms[0].normalized()
	_create_signal_pole(root, reference, half_width, 0)
	for arm in arms:
		var normalized_arm := arm.normalized()
		if absf(reference.dot(normalized_arm)) < 0.45:
			_create_signal_pole(root, normalized_arm, half_width, 1)
			break
	_visuals[node_id] = root


func _create_signal_pole(
	parent: Node3D,
	arm: Vector2,
	half_width: float,
	pole_index: int
) -> void:
	var left := Vector2(arm.y, -arm.x)
	var pole := Node3D.new()
	pole.name = "Pole%d" % pole_index
	pole.position = Vector3(
		left.x * (half_width + 2.2),
		0.0,
		left.y * (half_width + 2.2)
	)
	pole.rotation.y = atan2(-arm.x, -arm.y)
	parent.add_child(pole)

	var model := _model_scene.instantiate() as Node3D
	pole.add_child(model)
	var bounds := _combined_aabb(model)
	if bounds.size.y > 0.001:
		var factor := SIGNAL_HEIGHT_M / bounds.size.y
		model.scale = Vector3.ONE * factor
		model.position = Vector3(
			-bounds.get_center().x * factor,
			-bounds.position.y * factor,
			-bounds.get_center().z * factor
		)

	var indicator := _create_indicator()
	indicator.position = Vector3(0.0, SIGNAL_HEIGHT_M - 0.55, 0.0)
	pole.add_child(indicator)


func _create_indicator() -> Node3D:
	var indicator := Node3D.new()
	indicator.name = "StateHead"
	var backing := MeshInstance3D.new()
	backing.name = "Backing"
	var backing_mesh := BoxMesh.new()
	backing_mesh.size = Vector3(0.46, 1.28, 0.16)
	backing.mesh = backing_mesh
	var backing_material := StandardMaterial3D.new()
	backing_material.albedo_color = Color("11171c")
	backing_material.roughness = 0.55
	backing.material_override = backing_material
	indicator.add_child(backing)
	for lamp_index in 3:
		var lamp := MeshInstance3D.new()
		lamp.name = "Lamp%d" % lamp_index
		var sphere := SphereMesh.new()
		sphere.radius = 0.14
		sphere.height = 0.28
		lamp.mesh = sphere
		lamp.position = Vector3(0.0, 0.38 - float(lamp_index) * 0.38, -0.11)
		var material := StandardMaterial3D.new()
		material.albedo_color = LAMP_OFF
		material.roughness = 0.3
		material.emission_enabled = true
		material.emission = LAMP_OFF
		material.emission_energy_multiplier = 0.05
		lamp.material_override = material
		indicator.add_child(lamp)
	return indicator


func _refresh_visual_states() -> void:
	for node_id in _visuals:
		var root: Node3D = _visuals[node_id]
		if not is_instance_valid(root):
			continue
		for pole_index in 2:
			var pole := root.get_node_or_null("Pole%d" % pole_index) as Node3D
			if pole == null:
				continue
			# Each head faces outward along its arm, so traffic approaching
			# that face travels in the opposite direction.
			var arm := Vector2(-sin(pole.rotation.y), -cos(pole.rotation.y))
			var state := get_vehicle_state(int(node_id), -arm)
			var head := pole.get_node_or_null("StateHead") as Node3D
			if head == null:
				continue
			for lamp_index in 3:
				var lamp := head.get_node_or_null("Lamp%d" % lamp_index) as MeshInstance3D
				if lamp == null:
					continue
				var material := lamp.material_override as StandardMaterial3D
				if material == null:
					continue
				var active := (
					(state == VehicleState.RED and lamp_index == 0)
					or (state == VehicleState.YELLOW and lamp_index == 1)
					or (state == VehicleState.GREEN and lamp_index == 2)
				)
				var color: Color = [LAMP_RED, LAMP_YELLOW, LAMP_GREEN][lamp_index]
				material.albedo_color = color if active else LAMP_OFF
				material.emission = color if active else LAMP_OFF
				material.emission_energy_multiplier = 2.8 if active else 0.05


func _widest_redline(node_id: int) -> float:
	var widest := 14.0
	if network == null or node_id < 0 or node_id >= network.nodes.size():
		return widest
	for edge in network.edges:
		if int(edge.a) == node_id or int(edge.b) == node_id:
			widest = maxf(widest, float(network.widths[int(edge.kind)]))
	return widest


func _combined_aabb(root: Node3D) -> AABB:
	var has_bounds := false
	var bounds := AABB()
	for child in root.get_children():
		var child_bounds := _node_bounds(child)
		if child_bounds.size == Vector3.ZERO:
			continue
		if not has_bounds:
			bounds = child_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(child_bounds)
	return bounds if has_bounds else AABB(Vector3.ZERO, Vector3.ONE)


func _node_bounds(node: Node) -> AABB:
	var has_bounds := false
	var bounds := AABB()
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_instance := node as MeshInstance3D
		bounds = mesh_instance.transform * mesh_instance.get_aabb()
		has_bounds = true
	for child in node.get_children():
		var child_bounds := _node_bounds(child)
		if child_bounds.size == Vector3.ZERO:
			continue
		if node is Node3D:
			child_bounds = (node as Node3D).transform * child_bounds
		if not has_bounds:
			bounds = child_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(child_bounds)
	return bounds if has_bounds else AABB()


func _junction_position(node_id: int) -> Vector3:
	return get_junction_position(node_id)


func _arms_from_dict(source: Dictionary, node_id: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var raw = source.get(node_id)
	if raw is Array:
		for value in raw:
			if value is Vector2:
				result.append(value)
	return result


func _get_arm_directions(node_id: int) -> Array[Vector2]:
	return _arms_from_dict(_arm_directions, node_id)


func _clear() -> void:
	for visual in _visuals.values():
		if is_instance_valid(visual):
			visual.free()
	_visuals.clear()
	if is_instance_valid(_visual_container):
		_visual_container.free()
	_visual_container = null
	_signal_nodes.clear()
	_arm_directions.clear()
	_forced_red_remaining.clear()
	_forced_red_groups.clear()
	_visual_clock = 0.0
	_model_scene = null
