extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await physics_frame
	var failures := 0
	for id in game.doors:
		var d: Dictionary = game.doors[id]
		var pivot: Node3D = d["pivot"]
		var angle: float = d["closed_angle"]
		var basis := Basis(Vector3.UP, angle)
		var center: Vector3 = pivot.position + basis * Vector3(float(d["width"]) / 2.0, 0, 0)
		var normal := basis * Vector3.FORWARD
		for opened in [false, true]:
			game.doors[id]["is_open"] = opened
			game._animate_doors(1.0)
			await physics_frame
			await physics_frame
			for side in [-1.0, 1.0]:
				var start: Vector3 = center + normal * side * 0.8 + Vector3(0, 0.02, 0)
				var collision := KinematicCollision3D.new()
				var hit: bool = game.player.test_move(Transform3D(Basis.IDENTITY, start), normal * side * -1.6, collision)
				if hit == opened:
					printerr("FAIL ", id, " open=", opened, " side=", side)
					if hit:
						printerr("Blocked by ", collision.get_collider().name)
					failures += 1
				else:
					print("PASS ", id, " open=", opened, " side=", side)
		game.doors[id]["is_open"] = false
		game._animate_doors(1.0)
	# Previously open, visible partition sections must block a player's capsule.
	for point in [Vector3(0, 0.02, 0.8), Vector3(-4, 0.02, 0), Vector3(4, 0.02, 0)]:
		var normal := Vector3.RIGHT if point.x == 0 else Vector3.FORWARD
		var hit: bool = game.player.test_move(Transform3D(Basis.IDENTITY, point + normal * 0.8), -normal * 1.6)
		if not hit:
			printerr("FAIL wall ", point)
			failures += 1
	print("Door passage failures: ", failures)
	# Round reset restores all state, and pause freezes the game clock.
	game.player.position = Vector3(9, 2, 9)
	game._start_round()
	if game.player.position.distance_to(Vector3(-2.0, 0.05, 1.0)) > 0.01:
		failures += 1
	for id in game.doors:
		if game.doors[id]["is_open"]:
			failures += 1
	var before: float = game.time_left
	game._set_paused(true)
	game._process(1.0)
	if game.time_left != before:
		failures += 1
	game._set_paused(false)
	# Moving doors stop rather than sweep through the player's footprint.
	var door: Dictionary = game.doors["FrontEntrance"]
	game.player.position = door["pivot"].position + Vector3(0.85, 0.02, 0)
	game.doors["FrontEntrance"]["is_open"] = true
	game._animate_doors(1.0)
	if absf(door["pivot"].rotation.y) > 0.001:
		failures += 1
	print("Passage / reset / pause / anti-pinch failures: ", failures)
	for index in range(4):
		game._select_tool(index)
		game._play_inspection_feedback()
		if game.inspection_audio.stream.data.size() != 13230:
			failures += 1
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
