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
	var failures := 0
	var expected_ids := [
		"sofa_gap", "sink_leak", "vent_wrong", "kitchen_socket", "cabinet_blocked", "cabinet_wear",
		"bed_slope", "window_sealed", "closet_deadend", "drain_missing", "tile_hollow", "bath_vanity", "bath_door", "bath_vent"
	]
	if game.issue_records.size() != 14:
		printerr("FAIL issue pool count: ", game.issue_records.size())
		failures += 1
	for expected_id in expected_ids:
		var found := false
		for issue in game.issue_records:
			if str(issue["id"]) == expected_id:
				found = true
				break
		if not found:
			printerr("FAIL missing required issue definition: ", expected_id)
			failures += 1
	for issue in game.issue_records:
		game._add_issue_target(issue)

	var anchored := [
		["sink_leak", "261_CupboardUnits", 0.90],
		["vent_wrong", "255_ExtractorHood", 0.90],
		["kitchen_socket", "195_WallSocket", 0.85],
		["cabinet_blocked", "253_CupboardUnits", 0.90],
		["cabinet_wear", "74_CupboardUnits", 0.90],
		["bed_slope", "BedBase", 0.90],
		["window_sealed", "WindowGlass", 0.65],
		["drain_missing", "ImportedBath_DrainCover", 0.55],
		["bath_vent", "ImportedBath_CeilingVent", 0.55]
	]
	for entry in anchored:
		var body := game.issue_bodies.get(entry[0]) as Node3D
		var bounds: AABB = game._find_anchor_bounds(entry[1])
		var expected := bounds.get_center()
		if entry[0] == "bed_slope":
			expected = Vector3(bounds.end.x - 0.10, bounds.position.y + 0.02, bounds.get_center().z)
		elif entry[0] == "cabinet_wear":
			expected = Vector3(bounds.position.x - 0.045, bounds.get_center().y, bounds.get_center().z)
		if body == null or bounds.size.length() <= 0.0:
			printerr("FAIL missing issue anchor: ", entry[0], " -> ", entry[1])
			failures += 1
		elif body.position.distance_to(expected) > float(entry[2]):
			printerr("FAIL issue drift: ", entry[0], " distance=", body.position.distance_to(expected))
			failures += 1

	var sofa := game.issue_bodies.get("sofa_gap") as Node3D
	var sofa_group: AABB = game._find_anchor_group_bounds(["63_SofaLeather", "65_SofaLeather", "134_SofaLeather", "136_SofaLeather", "137_SofaLeather", "138_SofaLeather", "139_SofaLeather"])
	var front_wall: AABB = game._find_anchor_bounds("FrontWallLeft")
	var sofa_expected := Vector3(sofa_group.get_center().x, clampf(sofa_group.end.y + 0.42, 0.85, 1.35), front_wall.position.z - 0.035) if sofa_group.has_volume() and front_wall.has_volume() else Vector3(-6.55, 1.05, 5.84)
	if sofa == null or sofa.position.distance_to(sofa_expected) > 0.05:
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
	var vanity_issue := game.issue_bodies.get("bath_vanity") as Node3D
	var vanity_anchor: Vector3 = game.get_node("RightInnerDoorFrame").to_global(Vector3(1.30, 0.24, -0.09)) + Vector3(-0.45, 0, -0.28)
	if vanity_issue == null or vanity_issue.position.distance_to(vanity_anchor) > 0.05:
		printerr("FAIL bathroom door/vanity issue placement: ", vanity_issue.position if vanity_issue != null else "missing")
		failures += 1
	var closet := game.issue_bodies.get("closet_deadend") as Node3D
	var closet_anchor: Vector3 = game.get_node("ClosetDoorLeft").position + Vector3(0.50, 0, 0.045)
	if closet == null or closet.position.distance_to(closet_anchor) > 0.05:
		printerr("FAIL closet-door placement: ", closet.position if closet != null else "missing")
		failures += 1

	print("Issue anchors checked: ", anchored.size() + 5)
	print("Issue anchor fit failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
