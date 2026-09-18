extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await physics_frame

	# Open every interior door exactly as the player would before inspecting the
	# adjacent room. The route points deliberately pass the furniture fronts and
	# side aisles rather than teleporting between rooms.
	for door_id in ["LivingDoor", "LeftInnerDoor", "RightInnerDoor", "BedroomDoor"]:
		var data: Dictionary = game.doors[door_id]
		data["is_open"] = true
		game.doors[door_id] = data
		(data["pivot"] as Node3D).rotation.y = float(data["closed_angle"]) + float(data["open_delta"])

	var routes := [
		["living furniture aisle", [Vector3(-8.8, 1.0, 1.0), Vector3(-8.8, 1.0, 5.25), Vector3(-3.6, 1.0, 5.25), Vector3(-3.6, 1.0, 1.15)]],
		["living coffee table perimeter", [Vector3(-8.0, 1.0, 2.2), Vector3(-7.0, 1.0, 2.2), Vector3(-7.0, 1.0, 3.55), Vector3(-5.0, 1.0, 3.55), Vector3(-5.0, 1.0, 2.2)]],
		["kitchen furniture aisle", [Vector3(7.8, 1.0, 0.8), Vector3(9.2, 1.0, 0.8), Vector3(9.2, 1.0, 5.25), Vector3(7.8, 1.0, 5.25)]],
		["kitchen dining perimeter", [Vector3(9.2, 1.0, 1.6), Vector3(9.2, 1.0, 5.25), Vector3(8.2, 1.0, 5.25), Vector3(8.2, 1.0, 4.85), Vector3(9.2, 1.0, 4.85)]],
		["bedroom furniture aisle", [Vector3(-8.5, 1.0, -1.0), Vector3(-8.5, 1.0, -3.65), Vector3(-8.35, 1.0, -3.65), Vector3(-8.35, 1.0, -5.25), Vector3(-3.8, 1.0, -5.25), Vector3(-3.8, 1.0, -1.0)]],
		["bedroom closet and desk perimeter", [Vector3(-3.8, 1.0, -1.0), Vector3(-3.8, 1.0, -4.05), Vector3(-3.2, 1.0, -4.05), Vector3(-3.2, 1.0, -2.1), Vector3(-3.8, 1.0, -1.0)]],
		["bathroom furniture aisle", [Vector3(7.8, 1.0, -1.0), Vector3(9.2, 1.0, -1.0), Vector3(9.2, 1.0, -5.5), Vector3(4.0, 1.0, -5.5), Vector3(1.2, 1.0, -5.5)]],
		["bathroom wet-zone perimeter", [Vector3(9.2, 1.0, -1.0), Vector3(9.2, 1.0, -5.5), Vector3(8.6, 1.0, -5.5), Vector3(8.6, 1.0, -4.0), Vector3(9.2, 1.0, -3.0)]]
	]
	var failures := 0
	for route_data in routes:
		var route_name: String = route_data[0]
		var points: Array = route_data[1]
		game.player.position = points[0]
		game.player.velocity = Vector3.ZERO
		var route_ok := true
		for point_index in range(1, points.size()):
			if not await _walk_to(game, points[point_index]):
				printerr("FAIL player furniture route ", route_name, " at ", points[point_index], " ended=", game.player.position)
				failures += 1
				route_ok = false
				break
		if route_ok:
			print("PASS player furniture route ", route_name)

	print("Player furniture walkthrough failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _walk_to(game: Node, target: Vector3) -> bool:
	for step in range(220):
		var offset: Vector3 = target - game.player.position
		offset.y = 0.0
		if offset.length() < 0.24:
			return true
		var motion := offset.normalized() * minf(0.075, offset.length())
		game.player.velocity = motion / (1.0 / 60.0)
		game.player.move_and_collide(motion)
		await physics_frame
	game.player.velocity = Vector3.ZERO
	return game.player.position.distance_to(target) < 0.32
