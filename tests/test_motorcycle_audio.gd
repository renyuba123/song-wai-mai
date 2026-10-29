extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := Node.new()
	var audio := MotorcycleAudio.new()
	audio.set_physics_process(false)
	player.add_child(audio)
	for name in ["Start", "Drive", "Stop"]:
		var sound := AudioStreamPlayer.new()
		sound.name = name
		sound.bus = &"Motorcycle"
		audio.add_child(sound)
	audio.get_node("Start").stream = load("res://assets/audio/motorcycle/start_a1.mp3")
	audio.get_node("Drive").stream = load("res://assets/audio/motorcycle/drive_b1.mp3")
	audio.get_node("Stop").stream = load("res://assets/audio/motorcycle/stop_c2_6_to_10.ogg")
	root.add_child(player)
	audio.set_physics_process(false)
	await process_frame
	assert(audio.state == MotorcycleAudio.State.IDLE)
	assert(not audio.get_node("Start").playing)
	assert(not audio.get_node("Drive").playing)
	assert(not audio.get_node("Stop").playing)

	audio.update_for_speed(0.4, 0.016)
	assert(audio.state == MotorcycleAudio.State.STARTING)
	audio.update_for_speed(0.2, 0.016)
	assert(audio.state == MotorcycleAudio.State.STARTING)
	audio.get_node("Start").finished.emit()
	assert(audio.state == MotorcycleAudio.State.DRIVING)
	assert(audio.get_node("Drive").playing)
	audio.update_for_speed(10.0, 0.2)
	assert(audio.get_node("Drive").pitch_scale > audio.min_drive_pitch)
	audio.update_for_speed(0.0, 0.2)
	assert(audio.state == MotorcycleAudio.State.STOPPING)
	audio.get_node("Stop").finished.emit()
	assert(audio.state == MotorcycleAudio.State.IDLE)
	audio.update_for_speed(0.0, 0.2)
	assert(audio.state == MotorcycleAudio.State.IDLE)
	audio.update_for_speed(-0.5, 0.2)
	assert(audio.state == MotorcycleAudio.State.REVERSING)
	assert(not audio.get_node("Start").playing)
	assert(not audio.get_node("Stop").playing)
	audio.update_for_speed(0.5, 0.016)
	assert(audio.state == MotorcycleAudio.State.STARTING)
	audio.reset_audio()
	assert(audio.state == MotorcycleAudio.State.IDLE)
	assert(not audio.get_node("Start").playing)

	var ambience: Node = load("res://scenes/world/city_ambience_audio.tscn").instantiate()
	root.add_child(ambience)
	await process_frame
	assert(ambience.get_node("CrowdA").playing)
	assert(ambience.get_node("TrafficA").playing)
	assert(ambience.get_node("CrowdA").bus == &"Ambience")
	assert(audio.get_node("Drive").bus == &"Motorcycle")
	assert(AudioServer.get_bus_index(&"Ambience") >= 0)
	assert(AudioServer.get_bus_index(&"Motorcycle") >= 0)
	var crowd_a: AudioStreamPlayer = ambience.get_node("CrowdA")
	crowd_a.seek(crowd_a.stream.get_length() - 0.5)
	ambience._process(0.1)
	assert(ambience.get_node("CrowdB").playing)
	print("PASS: motorcycle and city ambience audio")
	player.queue_free()
	ambience.queue_free()
	await process_frame
	quit()
