extends SceneTree

## Deterministic traffic-signal phases, stopping rules, pedestrian windows,
## and the packaged signal model.

const EPS := 0.001

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var network := _make_crossroad_network()
	var signals := TrafficSignals.new()
	signals.build(network)
	_check_signal_detection(signals)
	_check_phase_states(signals)
	_check_stopping_rules(signals)
	_check_pedestrian_phase(signals)
	_check_main_controller_override(network)
	_check_visible_signal_heads(network)
	_check_phase_determinism(network, signals)
	_check_model_resource()
	signals.free()
	network = null

	if _failed:
		printerr("FAIL traffic signals")
	else:
		print("PASS traffic signals")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL traffic signals: ", message)


func _make_crossroad_network() -> RoadNetwork:
	var network := RoadNetwork.new()
	network.seed_value = 0
	network.map_size = Vector2(400.0, 400.0)
	network.widths = Vector3(40.0, 30.0, 18.0)
	var points: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(0.0, -40.0),
		Vector2(40.0, 0.0),
		Vector2(0.0, 40.0),
		Vector2(-40.0, 0.0),
	]
	network.nodes = points
	var segments: Array[Dictionary] = [
		{"a": 0, "b": 1, "kind": RoadNetwork.MAIN},
		{"a": 0, "b": 2, "kind": RoadNetwork.MAIN},
		{"a": 0, "b": 3, "kind": RoadNetwork.MAIN},
		{"a": 0, "b": 4, "kind": RoadNetwork.MAIN},
	]
	network.edges = segments
	return network


func _check_signal_detection(signals: TrafficSignals) -> void:
	_expect(signals.is_signalized(0), "crossroad node must be signalized")
	_expect(
		signals.get_signal_node_ids() == [0],
		"only the four-arm junction should be signalized"
	)
	_expect(
		signals.get_vehicle_state(99, Vector2.UP) == TrafficSignals.VehicleState.GREEN,
		"an unsignalized junction must remain passable"
	)
	_expect(
		signals.can_pedestrian_cross(99),
		"pedestrians must remain free to cross at an unsignalized junction"
	)


func _check_phase_states(signals: TrafficSignals) -> void:
	var north := Vector2.UP
	var east := Vector2.RIGHT
	signals.set_phase_seconds(0.0)
	_expect(
		signals.get_vehicle_state(0, north) == TrafficSignals.VehicleState.GREEN,
		"phase A should start green"
	)
	_expect(
		signals.get_vehicle_state(0, east) == TrafficSignals.VehicleState.RED,
		"phase B should start red"
	)
	_expect(
		not signals.can_pedestrian_cross(0),
		"pedestrians must wait while vehicles are moving"
	)

	signals.set_phase_seconds(TrafficSignals.PHASE_A_YELLOW_START + 0.5)
	_expect(
		signals.get_vehicle_state(0, north) == TrafficSignals.VehicleState.YELLOW,
		"phase A should switch to yellow at 12 seconds"
	)
	signals.set_phase_seconds(TrafficSignals.PHASE_B_GREEN_START + 0.5)
	_expect(
		signals.get_vehicle_state(0, east) == TrafficSignals.VehicleState.GREEN,
		"phase B should switch to green after the all-red interval"
	)
	_expect(
		signals.get_vehicle_state(0, north) == TrafficSignals.VehicleState.RED,
		"phase A should remain red during phase B"
	)
	signals.set_phase_seconds(TrafficSignals.PHASE_B_YELLOW_START + 0.5)
	_expect(
		signals.get_vehicle_state(0, east) == TrafficSignals.VehicleState.YELLOW,
		"phase B should switch to yellow at 29 seconds"
	)


func _check_stopping_rules(signals: TrafficSignals) -> void:
	signals.set_phase_seconds(TrafficSignals.PHASE_A_GREEN_START + 0.5)
	_expect(
		not signals.should_vehicle_stop(0, Vector2.UP, 20.0),
		"green must allow approach"
	)
	signals.set_phase_seconds(TrafficSignals.PHASE_A_YELLOW_START + 0.5)
	_expect(
		signals.should_vehicle_stop(0, Vector2.UP, 20.0),
		"yellow must stop vehicles far enough from the junction"
	)
	_expect(
		not signals.should_vehicle_stop(0, Vector2.UP, 6.99),
		"yellow must let a vehicle close to the stop line continue"
	)
	_expect(
		not signals.should_vehicle_stop(
			0,
			Vector2.UP,
			TrafficSignals.RED_BRAKE_DISTANCE_M + 1.0
		),
		"yellow must not freeze traffic before the braking zone"
	)
	signals.set_phase_seconds(TrafficSignals.PHASE_A_YELLOW_START + 3.5)
	_expect(
		signals.should_vehicle_stop(0, Vector2.UP, 20.0),
		"red must stop vehicles at the junction approach"
	)
	_expect(
		not signals.should_vehicle_stop(0, Vector2.UP, 60.0),
		"red must not stop vehicles before the braking zone"
	)
	_expect(
		not signals.should_vehicle_stop(0, Vector2.UP, 60.0, true),
		"a vehicle already inside the junction must always clear it"
	)


func _check_pedestrian_phase(signals: TrafficSignals) -> void:
	signals.set_phase_seconds(TrafficSignals.PEDESTRIAN_START - 0.01)
	_expect(
		not signals.can_pedestrian_cross(0),
		"pedestrian window must not open before its phase"
	)
	signals.set_phase_seconds(TrafficSignals.PEDESTRIAN_START + 0.5)
	_expect(
		signals.can_pedestrian_cross(0),
		"pedestrian window should open at 34 seconds"
	)
	signals.set_phase_seconds(TrafficSignals.CYCLE_SECONDS - 0.01)
	_expect(
		signals.can_pedestrian_cross(0),
		"pedestrian window should remain open until the cycle ends"
	)
	signals.set_phase_seconds(0.0)
	_expect(
		not signals.can_pedestrian_cross(0),
		"the next cycle must close the pedestrian window"
	)


func _check_main_controller_override(network: RoadNetwork) -> void:
	var signals := TrafficSignals.new()
	signals.build(network)
	signals.set_phase_seconds(TrafficSignals.PEDESTRIAN_START + 0.5)
	_expect(
		signals.can_pedestrian_cross(0),
		"main-controller override test must start in the pedestrian window"
	)
	_expect(
		not signals.trigger_main_controller_red(99, Vector2.UP),
		"an unsignalized junction cannot enter forced red"
	)
	_expect(
		not signals.trigger_main_controller_red(0, Vector2.ZERO, 0.5),
		"forced red requires a valid incoming direction"
	)
	_expect(
		signals.trigger_main_controller_red(0, Vector2.UP, 0.5),
		"a signalized junction should accept a directed forced red"
	)
	_expect(signals.is_main_controller_red(0), "forced red should become active")
	_expect(
		signals.get_vehicle_state(0, Vector2.UP) == TrafficSignals.VehicleState.RED,
		"the main controller's approach must turn red"
	)
	_expect(
		signals.get_vehicle_state(0, Vector2.DOWN) == TrafficSignals.VehicleState.RED,
		"the opposite approach on the same traffic axis must also turn red"
	)
	_expect(
		signals.get_vehicle_state(0, Vector2.RIGHT) == TrafficSignals.VehicleState.GREEN,
		"the conflicting cross-traffic axis must stay green"
	)
	_expect(
		signals.get_vehicle_state(0, Vector2.LEFT) == TrafficSignals.VehicleState.GREEN,
		"both directions on the conflicting axis must stay green"
	)
	_expect(
		not signals.can_pedestrian_cross(0),
		"pedestrians must not start crossing during forced red"
	)
	_expect(
		signals.should_vehicle_stop(0, Vector2.UP, 20.0),
		"approaching vehicles must stop for forced red"
	)
	_expect(
		not signals.should_vehicle_stop(0, Vector2.UP, 40.0),
		"forced red must not freeze vehicles away from the junction"
	)
	_expect(
		not signals.should_vehicle_stop(0, Vector2.UP, 40.0, true),
		"vehicles already inside the junction must clear forced red"
	)
	_expect(
		not signals.should_vehicle_stop(0, Vector2.RIGHT, 20.0),
		"cross traffic on the green axis must keep moving"
	)

	signals.advance(0.4)
	_expect(
		signals.is_main_controller_red(0),
		"forced red must remain active for the requested hold time"
	)
	signals.advance(0.2)
	_expect(
		not signals.is_main_controller_red(0),
		"forced red must expire after its hold time"
	)
	_expect(
		signals.can_pedestrian_cross(0),
		"the original pedestrian phase must resume after forced red"
	)

	var player := Node3D.new()
	var junction := signals.get_junction_position(0)
	root.add_child(player)
	player.global_position = junction + Vector3(
		-(TrafficSignals.MAIN_CONTROLLER_RED_RADIUS_M - 1.0),
		0.0,
		0.0
	)
	player.rotation.y = -PI * 0.5
	signals.set_player(player)
	signals.advance(0.1)
	_expect(
		signals.is_main_controller_red(0),
		"the player entering the detection radius must force the signal red"
	)
	_expect(
		signals.get_forced_red_remaining(0)
		>= TrafficSignals.MAIN_CONTROLLER_RED_HOLD_SECONDS - 0.01,
		"automatic forced red should use the long hold duration"
	)
	_expect(
		signals.get_main_controller_red_group(0)
		== signals.get_approach_group(0, Vector2.RIGHT),
		"automatic forced red should use the player's facing direction"
	)
	_expect(
		signals.get_vehicle_state(0, Vector2.RIGHT) == TrafficSignals.VehicleState.RED,
		"the approach faced by the player must show red"
	)
	_expect(
		signals.get_vehicle_state(0, Vector2.UP) == TrafficSignals.VehicleState.GREEN,
		"cross traffic must show green while the player faces the red approach"
	)
	player.global_position = junction + Vector3(
		0.0,
		0.0,
		-(TrafficSignals.MAIN_CONTROLLER_RED_RADIUS_M - 1.0)
	)
	player.rotation.y = 0.0
	signals.advance(0.1)
	_expect(
		signals.get_vehicle_state(0, Vector2.UP) == TrafficSignals.VehicleState.RED,
		"turning toward the other axis must move the red light to that axis"
	)
	_expect(
		signals.get_vehicle_state(0, Vector2.RIGHT) == TrafficSignals.VehicleState.GREEN,
		"the previous red axis must turn green after the player changes facing"
	)

	player.global_position = junction + Vector3(
		-(TrafficSignals.MAIN_CONTROLLER_RED_RADIUS_M + 100.0),
		0.0,
		0.0
	)
	signals.advance(TrafficSignals.MAIN_CONTROLLER_RED_HOLD_SECONDS - 0.05)
	_expect(
		signals.is_main_controller_red(0),
		"forced red must remain after the player leaves"
	)
	signals.advance(0.1)
	_expect(
		not signals.is_main_controller_red(0),
		"forced red should resume the normal cycle after the hold expires"
	)
	player.free()
	signals.free()


func _check_visible_signal_heads(network: RoadNetwork) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var signals := TrafficSignals.new()
	signals.build(network)
	_expect(
		signals.get_visible_signal_count() == 1,
		"the nearby junction must create one visible signal assembly"
	)
	var root := signals.get_node_or_null("SignalVisuals/Signal0") as Node3D
	_expect(root != null, "the visible signal assembly must be reachable")
	if root == null:
		signals.free()
		return
	signals.trigger_main_controller_red(0, Vector2.UP, 5.0)
	var states: Array[int] = []
	for pole_index in 2:
		var pole := root.get_node_or_null("Pole%d" % pole_index) as Node3D
		_expect(
			pole != null,
			"the junction must expose both visible traffic-light axes"
		)
		if pole == null:
			continue
		var head := pole.get_node_or_null("StateHead") as Node3D
		_expect(head != null, "each visible pole must have a signal head")
		if head == null:
			continue
		var arm := Vector2(-sin(pole.rotation.y), -cos(pole.rotation.y))
		var expected := int(signals.get_vehicle_state(0, -arm))
		states.append(expected)
		var actual := _active_lamp_index(head)
		_expect(
			actual == expected,
			"visible lamp %d must match state %d for its approach" % [
				actual,
				expected,
			]
		)
	_expect(states.size() == 2, "both visible signal axes must report a state")
	if states.size() != 2:
		signals.free()
		return
	var first_state := states[0]
	var second_state := states[1]
	_expect(
		first_state != second_state,
		"the two visible signal axes must show opposite states during override"
	)
	_expect(
		first_state == TrafficSignals.VehicleState.RED
		or second_state == TrafficSignals.VehicleState.RED,
		"one visible signal axis must show red"
	)
	_expect(
		first_state == TrafficSignals.VehicleState.GREEN
		or second_state == TrafficSignals.VehicleState.GREEN,
		"the conflicting visible signal axis must show green"
	)
	signals.free()


func _active_lamp_index(head: Node3D) -> int:
	for lamp_index in 3:
		var lamp := head.get_node_or_null("Lamp%d" % lamp_index) as MeshInstance3D
		if lamp == null:
			continue
		var material := lamp.material_override as StandardMaterial3D
		if material != null and material.emission_energy_multiplier > 1.0:
			return lamp_index
	return -1


func _check_phase_determinism(
	network: RoadNetwork,
	first: TrafficSignals
) -> void:
	var second := TrafficSignals.new()
	second.build(network)
	for sample in [0.0, 5.5, 12.5, 17.5, 29.5, 34.5, 49.5]:
		first.set_phase_seconds(sample)
		second.set_phase_seconds(sample)
		_expect(
			first.get_vehicle_state(0, Vector2.UP) == second.get_vehicle_state(
				0,
				Vector2.UP
			),
			"northbound phase must be deterministic at %.1f seconds" % sample
		)
		_expect(
			first.get_vehicle_state(0, Vector2.RIGHT) == second.get_vehicle_state(
				0,
				Vector2.RIGHT
			),
			"eastbound phase must be deterministic at %.1f seconds" % sample
		)
		_expect(
			first.can_pedestrian_cross(0) == second.can_pedestrian_cross(0),
			"pedestrian phase must be deterministic at %.1f seconds" % sample
		)
	second.free()


func _check_model_resource() -> void:
	var model := load(TrafficSignals.LIGHT_MODEL_PATH) as PackedScene
	_expect(model != null, "packaged traffic-light GLB must load as a PackedScene")
	if model != null:
		var instance := model.instantiate()
		_expect(instance is Node3D, "traffic-light model root must be a Node3D")
		instance.free()
