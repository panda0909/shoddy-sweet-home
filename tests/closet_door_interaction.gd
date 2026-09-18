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
	for id in ["ClosetDoorLeft", "ClosetDoorRight"]:
		var data: Dictionary = game.doors.get(id, {})
		var door := game.get_node_or_null(id) as StaticBody3D
		if door == null or str(data.get("mode", "")) != "sliding":
			printerr("FAIL missing sliding closet door registration: ", id)
			failures += 1
			continue
		var closed_position: Vector3 = data["closed_position"]
		var open_offset: Vector3 = data["open_offset"]
		if open_offset.length() < 0.70:
			printerr("FAIL sliding travel is too short: ", id, " offset=", open_offset)
			failures += 1
		door.position = closed_position
		data["is_open"] = false
		game.doors[id] = data
		game._animate_doors(1.0)
		if door.position.distance_to(closed_position) > 0.01:
			printerr("FAIL closed closet door moved: ", id)
			failures += 1
		data["is_open"] = true
		game.doors[id] = data
		game._animate_doors(1.0)
		var expected_open := closed_position + open_offset
		if door.position.distance_to(expected_open) > 0.01:
			printerr("FAIL open closet door did not travel with collision: ", id, " got=", door.position, " expected=", expected_open)
			failures += 1
		if door.get_node_or_null("ClosetHandleLeft") == null and door.get_node_or_null("ClosetHandleRight") == null:
			printerr("FAIL handle is not attached to moving door: ", id)
			failures += 1
		data["is_open"] = false
		game.doors[id] = data
		game._animate_doors(1.0)
	print("Closet sliding door failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
