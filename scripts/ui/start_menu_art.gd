extends Control
class_name StartMenuArt

signal start_pressed
signal settings_pressed
signal exit_pressed

const ART := preload("res://assets/ui/start_reference.png")
const REPAIR := preload("res://assets/Shaders/start_menu_repair.gdshader")
const ART_SIZE := Vector2(1672.0, 941.0)
const ROW_Y := [469.0, 520.0, 571.0]

var _image: TextureRect
var _arrow: Polygon2D
var _buttons: Array[Button] = []
var _selected := 0
var _art_origin := Vector2.ZERO
var _art_scale := 1.0
var _active := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image = TextureRect.new()
	_image.name = "ReferenceImage"
	_image.texture = ART
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var repair := ShaderMaterial.new()
	repair.shader = REPAIR
	repair.set_shader_parameter("artwork", ART)
	_image.material = repair
	add_child(_image)
	for index in 3:
		var button := Button.new()
		button.name = ["StartButton", "SettingsButton", "ExitButton"][index]
		button.text = ""
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, empty)
		button.focus_entered.connect(_select.bind(index))
		button.mouse_entered.connect(_hover.bind(index))
		if index == 0:
			button.pressed.connect(func() -> void: start_pressed.emit())
		elif index == 1:
			button.pressed.connect(func() -> void: settings_pressed.emit())
		elif index == 2:
			button.pressed.connect(func() -> void: exit_pressed.emit())
		add_child(button)
		_buttons.append(button)
	_buttons[0].focus_neighbor_bottom = _buttons[0].get_path_to(_buttons[1])
	_buttons[1].focus_neighbor_top = _buttons[1].get_path_to(_buttons[0])
	_buttons[1].focus_neighbor_bottom = _buttons[1].get_path_to(_buttons[2])
	_buttons[2].focus_neighbor_top = _buttons[2].get_path_to(_buttons[1])
	_arrow = Polygon2D.new()
	_arrow.color = Color("ffd17b")
	add_child(_arrow)
	resized.connect(_layout)
	_layout()

func set_active(active: bool) -> void:
	_active = active
	set_process_input(active)
	_update_arrow()

func focus_default() -> void:
	focus_option(0)

func focus_option(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		return
	_select(index)
	_buttons[index].grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _hover(index: int) -> void:
	if _active and not _buttons[index].disabled:
		_buttons[index].grab_focus()
		_select(index)

func _select(index: int) -> void:
	if not _active or _buttons[index].disabled:
		return
	_selected = index
	(_image.material as ShaderMaterial).set_shader_parameter("selected", index)
	_update_arrow()

func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_art_scale = minf(size.x / ART_SIZE.x, size.y / ART_SIZE.y)
	_art_origin = (size - ART_SIZE * _art_scale) * 0.5
	_image.position = _art_origin
	_image.size = ART_SIZE * _art_scale
	var positions := [Vector2(156,444),Vector2(156,495),Vector2(156,546)]
	for index in 3:
		_buttons[index].position = _art_origin + positions[index] * _art_scale
		_buttons[index].size = Vector2(223, 49) * _art_scale
	_update_arrow()

func _update_arrow() -> void:
	if _arrow == null:
		return
	_arrow.visible = _active
	_arrow.position = _art_origin + Vector2(120.0, ROW_Y[_selected]) * _art_scale
	_arrow.polygon = PackedVector2Array([
		Vector2(-11, -15) * _art_scale,
		Vector2(12, 0) * _art_scale,
		Vector2(-11, 15) * _art_scale,
	])
