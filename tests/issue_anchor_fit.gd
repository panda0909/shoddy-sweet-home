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
	for body in game.issue_bodies.values():
		body.queue_free()
	game.issue_bodies.clear()
	game.issue_records = game._get_issue_definitions()
	for issue in game.issue_records:
		game._add_issue_target(issue)

	var failures := 0
	var anchored := [
		["tv_outlet", "78_Socket", 0.85],
		["sink_leak", "261_CupboardUnits", 0.90],
		["vent_wrong", "255_ExtractorHood", 0.90],
		["kitchen_socket", "195_WallSocket", 0.85],
		["cabinet_blocked", "253_CupboardUnits", 0.90],
		["bed_slope", "BedBase", 0.90],
		["window_sealed", "WindowGlass", 0.65],
		["rug_tilt", "141_Carpet", 0.75],
		["drain_missing", "ImportedBath_DrainCover", 0.55],
		["bath_vent", "ImportedBath_CeilingVent", 0.55]
	]
	for entry in anchored:
		var body := game.issue_bodies.get(entry[0]) as Node3D
		var bounds: AABB = game._find_anchor_bounds(entry[1])
		var expected := bounds.get_center()
		if entry[0] == "bed_slope":
			expected = Vector3(bounds.end.x - 0.10, bounds.position.y + 0.02, bounds.get_center().z)
		if body == null or bounds.size.length() <= 0.0:
			printerr("FAIL missing issue anchor: ", entry[0], " -> ", entry[1])
			failures += 1
		elif body.position.distance_to(expected) > float(entry[2]):
			printerr("FAIL issue drift: ", entry[0], " distance=", body.position.distance_to(expected))
			failures += 1

	var sofa := game.issue_bodies.get("sofa_gap") as Node3D
	if sofa == null or sofa.position.distance_to(Vector3(-6.55, 1.05, 5.84)) > 0.05:
		printerr("FAIL sofa repair opening placement: ", sofa.position if sofa != null else "missing")
		failures += 1
	var tile := game.issue_bodies.get("tile_hollow") as Node3D
	if tile == null or absf(tile.position.x - 7.3) > 0.05 or tile.position.z < -5.90 or tile.position.z > -5.75:
		printerr("FAIL bathroom tile wall placement: ", tile.position if tile != null else "missing")
		failures += 1
	var door := game.issue_bodies.get("bath_door") as Node3D
	var door_anchor: Vector3 = game.get_node("RightInnerDoorFrame").to_global(Vector3(1.30, 1.25, -0.09))
	if door == null or door.position.distance_to(door_anchor) > 0.05:
		printerr("FAIL bathroom door-frame placement: ", door.position if door != null else "missing")
		failures += 1
	var closet := game.issue_bodies.get("closet_deadend") as Node3D
	var closet_anchor: Vector3 = game.get_node("ClosetDoorLeft").position + Vector3(0.50, 0, 0.045)
	if closet == null or closet.position.distance_to(closet_anchor) > 0.05:
		printerr("FAIL closet-door placement: ", closet.position if closet != null else "missing")
		failures += 1

	print("Issue anchors checked: ", anchored.size() + 4)
	print("Issue anchor fit failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
