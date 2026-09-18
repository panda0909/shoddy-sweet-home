extends SceneTree

## Verifies the release-style startup contract: the entrance and living room
## become playable before the remaining rooms are requested in sequence.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Progressive startup requires a graphical display; skipped in headless mode")
		quit()
		return

	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	var failures := 0
	var initial_observed := false
	var initial_room_count := -1
	var initial_request_id := ""

	for frame in range(1200):
		await process_frame
		if game.initial_room_ready:
			initial_observed = true
			initial_room_count = game.loaded_rooms.size()
			initial_request_id = str(game.room_request_id)
			break

	if not initial_observed:
		printerr("FAIL initial room never became ready")
		failures += 1
	else:
		if initial_room_count != 1 or not game.loaded_rooms.has("客廳"):
			printerr("FAIL initial startup exposed an unexpected room set: ", game.loaded_rooms)
			failures += 1
		if initial_request_id != "kitchen":
			printerr("FAIL background queue did not request kitchen after initial room: ", initial_request_id)
			failures += 1

	for frame in range(1800):
		await process_frame
		if game.loaded_rooms.size() == 4 and not game.progressive_loading:
			break

	if game.loaded_rooms.size() != 4 or game.progressive_loading:
		printerr("FAIL progressive startup did not finish all rooms: ", game.loaded_rooms, " queue=", game.room_load_queue)
		failures += 1

	print("Progressive startup initial rooms: ", initial_room_count)
	print("Progressive startup final rooms: ", game.loaded_rooms.size())
	print("Progressive startup failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
