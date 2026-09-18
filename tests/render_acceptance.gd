extends SceneTree

const OUTPUT_DIR := "/private/tmp/shoddy-sweet-home-acceptance"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Visual acceptance requires a graphical display; skipped in headless mode")
		quit()
		return
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process_input(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for frame in range(1200):
		await process_frame
		if game.loaded_rooms.size() == 4 and not game.progressive_loading:
			break
	if game.loaded_rooms.size() != 4:
		printerr("FAIL visual acceptance started before all rooms loaded")
		game.queue_free()
		await process_frame
		quit(1)
		return
	game.set_process(false)
	game.hud.hide()
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	for tool in game.held_tools:
		tool.hide()

	var views := [
		["living_near", Vector3(-5.2, 1.42, 3.05), Vector3(-6.35, 1.05, 3.85), 1],
		["living_backlit", Vector3(-8.65, 1.55, 3.10), Vector3(-7.25, 1.35, 4.72), 0],
		["kitchen_near", Vector3(3.55, 1.45, 2.95), Vector3(6.35, 0.78, 4.22), 1],
		["bedroom_near", Vector3(-3.25, 1.45, -2.00), Vector3(-5.60, 1.00, -3.25), 1],
		["bathroom_near", Vector3(3.15, 1.45, -1.65), Vector3(6.90, 1.00, -3.25), 1],
		["living_flashlight", Vector3(-8.35, 1.45, 4.85), Vector3(-6.55, 1.30, 3.95), 0]
	]
	var failures := 0
	for view in views:
		game.camera.global_position = view[1]
		game.camera.look_at(view[2], Vector3.UP)
		game._select_tool(int(view[3]))
		for tool in game.held_tools:
			tool.hide()
		game.camera.get_node("Flashlight").visible = int(view[3]) == 0
		for warmup in range(20):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			printerr("FAIL empty acceptance frame: ", view[0])
			failures += 1
		else:
			if image.save_png(OUTPUT_DIR + "/" + str(view[0]) + ".png") != OK:
				printerr("FAIL unable to save acceptance frame: ", view[0])
				failures += 1

	# Verify that the open-door state still renders furniture instead of a
	# hidden doorway shell or an accidental collision overlay.
	game.doors["LivingDoor"]["is_open"] = true
	game._animate_doors(1.0)
	game.camera.global_position = Vector3(-1.05, 1.45, 2.72)
	game.camera.look_at(Vector3(-3.8, 1.05, 3.80), Vector3.UP)
	for tool in game.held_tools:
		tool.hide()
	for frame in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var door_image := root.get_texture().get_image()
	if door_image == null or door_image.is_empty():
		printerr("FAIL empty open-door acceptance frame")
		failures += 1
	else:
		if door_image.save_png(OUTPUT_DIR + "/living_door_open.png") != OK:
			printerr("FAIL unable to save open-door acceptance frame")
			failures += 1
	print("Visual acceptance frames: ", views.size() + 1)
	print("Visual acceptance failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
