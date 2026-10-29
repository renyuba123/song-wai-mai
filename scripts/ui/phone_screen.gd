extends MeshInstance3D
class_name PhoneOrderScreen

## Keyboard shortcuts live here only. No project input settings or player edits.
const TEST_KEY := KEY_O
const ACCEPT_KEY := KEY_Y
const REJECT_KEY := KEY_N
const DEMO_PREFIX := "phone-demo/"
@export var enable_test_orders := true

@onready var viewport: SubViewport = $SubViewport
@onready var notification: PhoneOrderNotification = $SubViewport/Phone_Ui/OrderNotification
var _manager: OrderManager
var _demo_serial := 0
var _demo_restore_revision := 0

func _ready() -> void:
	# Use the existing viewport and mesh. Instance-local material prevents
	# multiple players' phones from sharing the same rendered texture.
	var material := StandardMaterial3D.new()
	material.resource_local_to_scene = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	# Existing BoxMesh +Z face occupies U 0..1/3, V 0..1/2 of its atlas.
	# Correct UV mapping in the material; do not edit the mesh geometry.
	if mesh is BoxMesh:
		material.uv1_scale = Vector3(3.0, 2.0, 1.0)
	material.texture_repeat = false
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material_override = material
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	notification.order_accepted.connect(_on_accepted)
	notification.order_rejected.connect(_on_rejected)

func bind_order_manager(manager: OrderManager) -> void:
	if _manager == manager:
		return
	if is_instance_valid(_manager) and _manager.order_offered.is_connected(_show_offer):
		_manager.order_offered.disconnect(_show_offer)
	_manager = manager
	if _manager != null:
		_manager.phone_notifications_enabled = true
		_manager.order_offered.connect(_show_offer)
		_show_offer(_manager.get_phone_offer())

func _show_offer(data: Dictionary) -> void:
	if not data.is_empty():
		_demo_restore_revision += 1
		notification.show_order(data)

func show_order(data: Dictionary) -> bool:
	return notification.show_order(data)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == TEST_KEY and enable_test_orders and OS.is_debug_build():
		show_test_order()
	elif key == ACCEPT_KEY and notification.has_pending_order:
		notification.accept_order()
	elif key == REJECT_KEY and notification.has_pending_order:
		notification.reject_order()
	else:
		return
	get_viewport().set_input_as_handled()

func show_test_order() -> void:
	_demo_serial += 1
	_demo_restore_revision += 1
	show_order({
		"id": DEMO_PREFIX + str(_demo_serial),
		"shop_name": "小镇披萨店",
		"pickup_address": "商业街 12 号",
		"destination_address": "幸福小区",
		"distance_m": 1200.0,
		"reward_yuan": 8.50,
	})

func _on_accepted(id: String) -> void:
	if id.begins_with(DEMO_PREFIX):
		_restore_real_offer_later()
	elif is_instance_valid(_manager):
		_manager.accept_phone_order(id)

func _on_rejected(id: String) -> void:
	if id.begins_with(DEMO_PREFIX):
		_restore_real_offer_later()
	elif is_instance_valid(_manager):
		_manager.reject_phone_order(id)

func _restore_real_offer_later() -> void:
	var revision := _demo_restore_revision
	await get_tree().create_timer(2.0).timeout
	if revision == _demo_restore_revision and is_instance_valid(_manager) and not notification.has_pending_order:
		_show_offer(_manager.get_phone_offer())
