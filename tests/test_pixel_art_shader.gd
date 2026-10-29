extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const SHADER_PATH := "res://assets/Shaders/edge_detection.gdshader"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		printerr("FAIL pixel shader could not be loaded")
		quit(1)
		return

	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	await process_frame

	var camera := player.get_node_or_null("Camera3D") as Camera3D
	var post_process := player.get_node_or_null(
		"Camera3D/MeshInstance3D"
	) as MeshInstance3D
	var material: ShaderMaterial = null
	if post_process != null and post_process.mesh != null:
		material = post_process.mesh.material as ShaderMaterial

	var ok: bool = (
		camera != null
		and camera.current
		and post_process != null
		and post_process.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and post_process.extra_cull_margin >= 16000.0
		and material != null
		and material.shader == shader
		and material.get_shader_parameter("pixel_size") >= 1.0
		and material.get_shader_parameter("color_steps") == 64.0
		and material.get_shader_parameter("edge_highlight") >= 0.0
		and material.get_shader_parameter("black_line_width") >= 0.0
		and material.get_shader_parameter("highlight_line_width") >= 0.0
		and material.get_shader_parameter("line_thin_end") > material.get_shader_parameter("line_thin_start")
		and material.get_shader_parameter("far_line_thickness") > 0.0
	)

	if ok:
		print("PASS pixel shader loaded and attached to the player camera")
	else:
		printerr(
			"FAIL pixel shader camera=", camera != null,
			" quad=", post_process != null,
			" material=", material != null
		)

	player.queue_free()
	await process_frame
	quit(0 if ok else 1)
