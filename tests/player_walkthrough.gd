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

	var failures := 0
	var routes := [
		# The opened leaf rests along the hinge line; a real player walks through
		# the clear side of the doorway rather than through the resting panel.
		["LivingDoor", Vector3(-1.35, 1.0, 2.75), Vector3(1.35, 1.0, 2.75)],
		["LeftInnerDoor", Vector3(-7.50, 1.0, 1.35), Vector3(-7.50, 1.0, -1.35)],
		["RightInnerDoor", Vector3(7.50, 1.0, 1.35), Vector3(7.50, 1.0, -1.35)],
		["BedroomDoor", Vector3(-1.35, 1.0, -2.40), Vector3(1.35, 1.0, -2.40)]
	]
	for route in routes:
		var door_id: String = route[0]
		var start: Vector3 = route[1]
		var target: Vector3 = route[2]
		_reset_door(game, door_id)
		game.player.position = start
		game.player.velocity = Vector3.ZERO
		game._toggle_door(door_id)
		game._animate_doors(1.0)
		var reached := await _walk_player(game, target)
		if not reached:
			printerr("FAIL player could not pass ", door_id, " from ", start, " to ", target, "; ended at ", game.player.position)
			failures += 1
		else:
			print("PASS player walkthrough ", door_id, " end=", game.player.position)

	print("Player walkthrough failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _reset_door(game: Node, door_id: String) -> void:
	for id in game.doors:
		var data: Dictionary = game.doors[id]
		data["is_open"] = false
		game.doors[id] = data
		var pivot := data["pivot"] as Node3D
		if str(data.get("mode", "hinged")) == "sliding":
			pivot.position = data["closed_position"]
		else:
			pivot.rotation.y = float(data["closed_angle"])
	var target_data: Dictionary = game.doors[door_id]
	var target_pivot := target_data["pivot"] as Node3D
	if str(target_data.get("mode", "hinged")) == "sliding":
		target_pivot.position = target_data["closed_position"]
	else:
		target_pivot.rotation.y = float(target_data["closed_angle"])


func _walk_player(game: Node, target: Vector3) -> bool:
	for step in range(160):
		var offset: Vector3 = target - game.player.position
		offset.y = 0.0
		if offset.length() < 0.22:
			return true
		var motion: Vector3 = offset.normalized() * minf(0.08, offset.length())
		game.player.velocity = motion / (1.0 / 60.0)
		game.player.move_and_collide(motion)
		await physics_frame
	game.player.velocity = Vector3.ZERO
	return game.player.position.distance_to(target) < 0.30
