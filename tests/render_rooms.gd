extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.set_process_input(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	game.hud.hide()
	for tool in game.held_tools:
		tool.hide()
	var views := [
		["living", Vector3(-3.3, 1.6, 1.2), Vector3(-6.8, 1, 3.6)],
		["kitchen", Vector3(1.0, 1.6, 0.7), Vector3(5, 1, 3.4)],
		["bedroom", Vector3(-0.7, 1.6, -2.6), Vector3(-6, 1, -3.8)],
		["bathroom", Vector3(1, 1.6, -0.6), Vector3(5, 1, -4)]
	]
	for view in views:
		game.camera.global_position = view[1]
		game.camera.look_at(view[2])
		for warmup in range(30):
			await process_frame
		var times: Array[float] = []
		var last := Time.get_ticks_usec()
		for sample in range(120):
			await process_frame
			var now := Time.get_ticks_usec()
			times.append(float(now - last) / 1000.0)
			last = now
		times.sort()
		print(view[0], " frame_ms median=", times[60], " p95=", times[114], " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/" + view[0] + ".png")
	game.queue_free()
	await process_frame
	quit()
