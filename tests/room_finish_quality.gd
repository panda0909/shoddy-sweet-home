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
	# The imported living asset used to lose furniture fragments when a source
	# mesh touched a generous doorway safety volume. Validate the actual hero
	# meshes against the LivingDoor opening in both closed and open states so a
	# future scale/offset change cannot silently hide a sofa or make the passage
	# visually impassable again.
	var living_asset := game.get_node_or_null("LivingRoomRealAsset") as Node3D
	var living_door_pivot := game.get_node_or_null("LivingDoorPivot") as Node3D
	var living_door := game.get_node_or_null("LivingDoorPivot/LivingDoor") as StaticBody3D
	if living_asset == null or living_door_pivot == null or living_door == null:
		printerr("FAIL missing living hero asset or hinged doorway")
		failures += 1
	else:
		var original_angle := living_door_pivot.rotation.y
		living_door_pivot.rotation.y = float(game.doors["LivingDoor"]["closed_angle"])
		var closed_bounds := _visual_bounds(living_door)
		living_door_pivot.rotation.y = float(game.doors["LivingDoor"]["closed_angle"]) + float(game.doors["LivingDoor"]["open_delta"])
		var open_bounds := _visual_bounds(living_door)
		living_door_pivot.rotation.y = original_angle
		var door_corridor := closed_bounds.merge(open_bounds).grow(0.32) if closed_bounds.has_volume() and open_bounds.has_volume() else AABB()
		var blocked_meshes := 0
		var visual_only_meshes := 0
		for mesh_node in living_asset.find_children("*", "MeshInstance3D", true, false):
			var living_mesh := mesh_node as MeshInstance3D
			if living_mesh == null or living_mesh.mesh == null:
				continue
			if living_mesh.has_meta("hidden_for_door_clearance") or living_mesh.has_meta("door_clearance_visual_only"):
				visual_only_meshes += 1
			if not living_mesh.visible:
				continue
			var mesh_bounds: AABB = living_mesh.global_transform * living_mesh.get_aabb()
			if door_corridor.has_volume() and mesh_bounds.intersects(door_corridor):
				blocked_meshes += 1
		if blocked_meshes > 0:
			printerr("FAIL living hero furniture intersects doorway safety corridor: ", blocked_meshes)
			failures += 1
		if visual_only_meshes > 0:
			printerr("FAIL living hero mesh was hidden or made visual-only for door clearance: ", visual_only_meshes)
			failures += 1
		if not closed_bounds.has_volume() or not open_bounds.has_volume():
			printerr("FAIL living door has no closed/open visual bounds")
			failures += 1
		print("Living doorway closed bounds: ", closed_bounds)
		print("Living doorway open bounds: ", open_bounds)
		print("Living doorway furniture conflicts: ", blocked_meshes)
	for window_piece in ["LivingWindowGlass", "LivingWindowFrame_Top", "LivingWindowFrame_Center", "LivingWindowSill", "LivingWindowLatch"]:
		if game.get_node_or_null(window_piece) == null:
			printerr("FAIL missing rebuilt living window piece: ", window_piece)
			failures += 1
	var living_glass := game.get_node_or_null("LivingWindowGlass/Mesh") as MeshInstance3D
	if living_glass == null or not living_glass.mesh is ArrayMesh:
		printerr("FAIL living window glass still uses a sharp box silhouette")
		failures += 1
	for fireplace_piece in ["LivingDetail_FireplaceHearthEdge", "LivingDetail_FireplaceMantelEdge", "LivingDetail_FireplaceSideTrim"]:
		if game.get_node_or_null(fireplace_piece) == null:
			printerr("FAIL missing bounds-attached fireplace detail: ", fireplace_piece)
			failures += 1
	for coffee_piece in ["LivingDetail_CoffeeTableLeg_0", "LivingDetail_CoffeeTableLeg_3", "LivingDetail_CoffeeTableLowerBraceX", "LivingDetail_CoffeeTableFoot_0"]:
		if game.get_node_or_null(coffee_piece) == null:
			printerr("FAIL missing coffee table underframe detail: ", coffee_piece)
			failures += 1
	var coffee_legs: Array = game.find_children("LivingDetail_CoffeeTableLeg_*", "StaticBody3D", true, false)
	if coffee_legs.size() != 4:
		printerr("FAIL coffee table leg count: ", coffee_legs.size())
		failures += 1
	for coffee_detail in game.find_children("LivingDetail_CoffeeTable*", "StaticBody3D", true, false):
		if coffee_detail.get_node_or_null("CollisionShape3D") != null:
			printerr("FAIL coffee table finish detail blocks movement: ", coffee_detail.name)
			failures += 1
	var tv_bounds: AABB = game._find_living_mesh_bounds("60_TvBevel")
	var tv_console := game.get_node_or_null("LivingDetail_TvConsole") as Node3D
	var tv_expected := Vector3(tv_bounds.end.x + 0.24 * 0.50 + 0.025, tv_bounds.position.y - 0.10, tv_bounds.get_center().z) if tv_bounds.has_volume() else Vector3.ZERO
	if not tv_bounds.has_volume() or tv_console == null or tv_console.global_position.distance_to(tv_expected) > 0.05:
		printerr("FAIL TV console is not attached to imported TV bounds")
		failures += 1
	var sideboard_bounds: AABB = game._find_anchor_group_bounds(["54_WhitePaint", "55_WhitePaint", "56_WhitePaint", "57_DrawerHandles", "58_WhitePaint", "59_WhitePaint"])
	var sideboard_top := game.get_node_or_null("LivingDetail_SideboardTop") as Node3D
	var sideboard_expected := Vector3(sideboard_bounds.get_center().x, sideboard_bounds.end.y + 0.02, sideboard_bounds.get_center().z) if sideboard_bounds.has_volume() else Vector3.ZERO
	if not sideboard_bounds.has_volume() or sideboard_top == null or sideboard_top.global_position.distance_to(sideboard_expected) > 0.05:
		printerr("FAIL sideboard finish is not attached to imported white-paint bounds")
		failures += 1
	for sideboard_piece in ["LivingDetail_SideboardPlinth", "LivingDetail_SideboardFrontInset"]:
		if game.get_node_or_null(sideboard_piece) == null:
			printerr("FAIL missing sideboard finish: ", sideboard_piece)
			failures += 1
	var sideboard_pulls: Array = game.find_children("LivingDetail_SideboardDrawerPull_*", "StaticBody3D", true, false)
	if sideboard_pulls.size() != 4:
		printerr("FAIL sideboard drawer pull count: ", sideboard_pulls.size())
		failures += 1
	else:
		for pull in sideboard_pulls:
			if pull.get_node_or_null("CollisionShape3D") != null or pull.global_position.x <= sideboard_bounds.end.x:
				printerr("FAIL sideboard drawer pull is not a render-only front detail: ", pull.name)
				failures += 1
	var sofa_shelf := game.get_node_or_null("LivingDetail_SofaWallShelf") as Node3D
	var sofa_shelf_mesh := sofa_shelf.get_node_or_null("Mesh") as MeshInstance3D if sofa_shelf != null else null
	var sofa_shelf_bounds: AABB = sofa_shelf_mesh.global_transform * sofa_shelf_mesh.get_aabb() if sofa_shelf_mesh != null else AABB()
	var front_wall_for_shelf: AABB = game._find_anchor_bounds("FrontWallLeft")
	var sofa_for_shelf: AABB = game._find_anchor_group_bounds(["63_SofaLeather", "65_SofaLeather", "134_SofaLeather", "136_SofaLeather", "137_SofaLeather", "138_SofaLeather", "139_SofaLeather"])
	if sofa_shelf == null or sofa_shelf_mesh == null or sofa_shelf.find_child("CollisionShape3D", true, false) != null:
		printerr("FAIL missing or collidable sofa wall shelf")
		failures += 1
	elif not front_wall_for_shelf.has_volume() or not sofa_for_shelf.has_volume() or absf(sofa_shelf.global_position.x - sofa_for_shelf.get_center().x) > 0.05 or sofa_shelf.global_position.y < sofa_for_shelf.end.y + 0.50 or sofa_shelf.global_position.y > 2.35 or sofa_shelf.global_position.z >= front_wall_for_shelf.position.z:
		printerr("FAIL sofa wall shelf is not attached to sofa/front-wall bounds: ", sofa_shelf.global_position)
		failures += 1
	if game.get_node_or_null("LivingDetail_SofaWallShelfBracket_0") == null or game.get_node_or_null("LivingDetail_SofaWallShelfBracket_1") == null:
		printerr("FAIL sofa wall shelf brackets are incomplete")
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


func _visual_bounds(node: Node) -> AABB:
	var result := AABB()
	var has_bounds := false
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh == null or mesh.mesh == null or not mesh.visible:
			continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		if not has_bounds:
			result = bounds
			has_bounds = true
		else:
			result = result.merge(bounds)
	return result
