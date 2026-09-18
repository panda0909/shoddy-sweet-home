extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	var failures := 0
	var shadows: Array = game.find_children("*", "MeshInstance3D", true, false)
	var shadow_count := 0
	for node in shadows:
		if node.has_meta("contact_shadow"):
			shadow_count += 1
			if node.get_child_count() != 0:
				printerr("FAIL contact shadow has child/collision: ", node.name)
				failures += 1
	if shadow_count < 5:
		printerr("FAIL too few furniture contact shadows: ", shadow_count)
		failures += 1

	var kitchen := game.get_node_or_null("KitchenRealAsset") as Node3D
	if kitchen == null or not is_equal_approx(kitchen.scale.x, 0.72):
		printerr("FAIL kitchen hero scale: ", kitchen.scale if kitchen != null else "missing")
		failures += 1
	for detail in game.find_children("KitchenDetail_*", "Node3D", true, false):
		if detail.find_child("CollisionShape3D", true, false) != null:
			printerr("FAIL kitchen detail blocks movement: ", detail.name)
			failures += 1
	var living_details: Array = game.find_children("LivingDetail_*", "StaticBody3D", true, false)
	if living_details.size() < 5:
		printerr("FAIL too few bounds-attached living details: ", living_details.size())
		failures += 1
	for detail in living_details:
		if detail.get_node_or_null("CollisionShape3D") != null:
			printerr("FAIL living detail blocks movement: ", detail.name)
			failures += 1
	var sofa_bounds: AABB = game._find_anchor_group_bounds(["63_SofaLeather", "65_SofaLeather", "134_SofaLeather", "136_SofaLeather", "137_SofaLeather", "138_SofaLeather", "139_SofaLeather"])
	var front_wall: AABB = game._find_anchor_bounds("FrontWallLeft")
	var sofa_clearance := front_wall.position.z - sofa_bounds.end.z if sofa_bounds.has_volume() and front_wall.has_volume() else -1.0
	if sofa_clearance < 1.00 or sofa_clearance > 1.20:
		printerr("FAIL living sofa service clearance: ", sofa_clearance)
		failures += 1
	var living_window: AABB = game._find_anchor_bounds("LivingWindowGlass")
	var window_reveal := sofa_bounds.position.x - living_window.end.x if sofa_bounds.has_volume() and living_window.has_volume() else -1.0
	if window_reveal < 0.30:
		printerr("FAIL living sofa overlaps window opening: ", window_reveal)
		failures += 1
	for window_piece in ["LivingWindowGlass", "LivingWindowFrame_Top", "LivingWindowFrame_Center"]:
		if game.get_node_or_null(window_piece) == null:
			printerr("FAIL missing rebuilt living window piece: ", window_piece)
			failures += 1

	print("Furniture contact shadows: ", shadow_count)
	print("Kitchen hero scale: ", kitchen.scale.x if kitchen != null else -1.0)
	print("Living bounds details: ", living_details.size())
	print("Living sofa service clearance: ", sofa_clearance)
	print("Living sofa/window reveal: ", window_reveal)
	print("Room finish quality failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
