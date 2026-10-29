extends SceneTree
var failed := false
var accepted: Array[String] = []
var rejected: Array[String] = []
func _initialize() -> void:
	call_deferred('_run')
func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr('FAIL phone: ', message)
func press(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = key
	event.pressed = false
	root.push_input(event)
func _run() -> void:
	var main: Node = load('res://scenes/main/main.tscn').instantiate()
	root.add_child(main)
	await process_frame
	var phone := main.get_node('Player/MeshInstance3D') as PhoneOrderScreen
	var orders := main.get_node('OrderSystem') as OrderManager
	var ui := phone.notification
	ui.order_accepted.connect(func(id: String) -> void: accepted.append(id))
	ui.order_rejected.connect(func(id: String) -> void: rejected.append(id))
	expect(phone.viewport.size == Vector2i(720,1080), 'reuse viewport resolution')
	expect(phone.material_override.albedo_texture == phone.viewport.get_texture(), 'screen must use existing viewport')
	expect(phone.mesh.size == Vector3(0.08,0.15,0.01), 'mesh geometry changed')
	expect(phone.get_children().filter(func(n: Node) -> bool: return n is SubViewport).size() == 1, 'duplicate viewport')
	var initial := orders.get_phone_offer()
	expect(not initial.is_empty() and orders.get_current_order() == null, 'real order should wait for acceptance')
	await press(KEY_N)
	expect(orders.get_phone_offer().is_empty() and orders.get_current_order() == null, 'real rejection must not start delivery')
	expect(rejected.size() == 1 and rejected[0] == initial.id, 'reject forwards unique real ID')
	expect(orders.handle_restart(), 'request next offer')
	var real_offer := orders.get_phone_offer()
	await press(KEY_O)
	var demo_id := ui.current_order_id
	expect(ui.shop_label.text == '小镇披萨店' and ui.reward_label.text == '¥ 8.50', 'mock fields')
	await create_timer(0.4).timeout
	expect(ui.card.visible and ui.card.modulate.a > 0.99 and absf(ui.card.position.y - ui.CARD_TOP) < 0.1, 'enter animation')
	expect(ui.card.position.y + ui.card.size.y <= phone.viewport.size.y, 'card overflows screen')
	await press(KEY_Y)
	await press(KEY_Y)
	expect(accepted.size() == 1 and accepted[0] == demo_id, 'accept once only')
	expect(orders.get_current_order() == null and orders.get_phone_offer().id == real_offer.id, 'demo must not mutate actual order')
	await create_timer(0.25).timeout
	expect(ui.feedback.visible and not ui.card.visible, 'success feedback')
	for index in 5:
		await press(KEY_O)
	await create_timer(0.4).timeout
	expect(ui.has_pending_order and ui.card.visible and not ui.feedback.visible, 'new offer cancels previous animation')
	expect(ui.get_children().filter(func(n: Node) -> bool: return n is PanelContainer).size() == 1, 'card duplication')
	await press(KEY_N)
	await create_timer(0.25).timeout
	expect(not ui.has_pending_order and not ui.card.visible, 'reject exit animation')
	expect(not ui.show_order({'id':'invalid'}), 'malformed order rejected')
	phone.show_order(real_offer)
	await press(KEY_Y)
	expect(orders.get_current_order() != null and orders.get_phone_offer().is_empty(), 'real accept starts existing delivery system')
	expect(not orders.accept_phone_order(str(real_offer.id)), 'stale/repeated ID must not reactivate order')
	var active := orders.get_current_order()
	await press(KEY_O)
	await press(KEY_N)
	expect(orders.get_current_order() == active, 'demo reject preserves active delivery')
	phone.show_test_order()
	var before_button := accepted.size()
	ui.accept_button.pressed.emit()
	expect(accepted.size() == before_button + 1, 'UI accept button wiring')
	phone.show_test_order()
	var before_reject := rejected.size()
	ui.reject_button.pressed.emit()
	expect(rejected.size() == before_reject + 1, 'UI reject button wiring')
	var long_data := {"id":"long", "shop_name":"很长的商家名称".repeat(8), "pickup_address":"很长的取餐地点".repeat(8), "destination_address":"很长的送达地点".repeat(8), "distance_m":1200.0, "reward_yuan":8.5}
	expect(ui.show_order(long_data), 'external dictionary API')
	await create_timer(0.4).timeout
	expect(ui.card.position.y + ui.card.size.y <= phone.viewport.size.y, 'long content must fit')
	var player: Node3D = main.get_node('Player')
	expect(player.is_physics_processing(), 'phone must not pause vehicle movement')
	expect(player.get('steering_pivot') != null, 'existing steering pivot remains connected')
	ui.reject_order()
	await create_timer(2.1).timeout
	main.queue_free()
	await process_frame
	print('Phone UI viewport/keyboard/animation/manager integration: passed=',not failed)
	quit(1 if failed else 0)
