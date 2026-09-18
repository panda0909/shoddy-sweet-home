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
	var wood_parts := [
		"BedBase", "BedHeadboard", "Closet", "ClosetDoorLeft", "ClosetDoorRight",
		"DeskTop", "Bookcase", "BedsideTable_Left", "BedsideTable_Right"
	]
	for id in wood_parts:
		var part := game.get_node_or_null(id) as Node3D
		var mesh := part.get_node_or_null("Mesh") as MeshInstance3D if part != null else null
		var material := mesh.material_override as StandardMaterial3D if mesh != null else null
		if material == null or material.albedo_texture == null or material.roughness_texture == null:
			printerr("FAIL wood PBR material: ", id)
			failures += 1
		if material == null or not material.normal_enabled or material.normal_texture == null:
			printerr("FAIL wood normal detail: ", id)
			failures += 1

	for id in ["BedsideTable_Left", "BedsideTable_Right", "Desk", "DeskTop", "Mattress", "Duvet", "BedroomRug", "BedroomPlantPot"]:
		if game.get_node_or_null(id) == null:
			printerr("FAIL missing bedroom prop: ", id)
			failures += 1

	for id in ["PipingFront", "PipingBack", "PipingLeft", "PipingRight"]:
		if game.get_node_or_null("Mattress/" + id) == null:
			printerr("FAIL missing mattress detail: ", id)
			failures += 1
	for id in [
		"BedsideLampShade_Left/LampBulb", "BedsideLampShade_Right/LampBulb",
		"BedsideLampShade_Left/LampShadeRim", "BedsideLampShade_Right/LampSocket",
		"Closet/ClosetInteriorShadow", "Closet/ClosetBottomRail", "Closet/ClosetTopRail",
		"Closet/ClosetCenterSeam", "Closet/ClosetHandleMountLeft",
		"Bookcase/Shelf_0", "Bookcase/Shelf_1",
		"Bookcase/Shelf_2", "BedroomBook_0/Binding", "BedroomRug/RugFringe_0", "BedroomRug/RugFringe_11",
		"BedroomRug/RugTuft_0", "BedroomRug/RugTuft_6",
		"Mattress/SideBandFront", "Duvet/DuvetFold_0", "Duvet/DuvetFold_2",
		"DeskChairSeat/BackCushion", "DeskChairSeat/BaseArm_0",
		"BedroomPlant/Stem_0", "BedroomPlant/Stem_15",
		"CurtainLeft/CurtainRod", "CurtainRight/CurtainRod"
	]:
		if game.get_node_or_null(id) == null:
			printerr("FAIL missing P0 finish detail: ", id)
			failures += 1
	var left_rod := game.get_node_or_null("CurtainLeft/CurtainRod") as MeshInstance3D
	if left_rod != null and absf(left_rod.rotation.z - PI / 2.0) > 0.01:
		printerr("FAIL curtain rod is not horizontal")
		failures += 1
	var window_bounds: AABB = game._find_anchor_bounds("WindowGlass")
	var curtain_rail := game.get_node_or_null("BedroomCurtainRail") as MeshInstance3D
	var expected_rail := Vector3(window_bounds.get_center().x, window_bounds.end.y + 0.22, window_bounds.end.z + 0.035) if window_bounds.has_volume() else Vector3.ZERO
	if curtain_rail == null or not window_bounds.has_volume() or curtain_rail.global_position.distance_to(expected_rail) > 0.06:
		printerr("FAIL curtain rail is not attached to the bedroom window bounds")
		failures += 1
	for id in ["BedroomCurtainFinialLeft", "BedroomCurtainFinialRight"]:
		if game.get_node_or_null(id) == null:
			printerr("FAIL missing curtain rail finial: ", id)
			failures += 1
	for id in ["BedsideLampShade_Left/Mesh", "BedsideLampShade_Right/Mesh"]:
		var shade_mesh := game.get_node_or_null(id) as MeshInstance3D
		var shade := shade_mesh.mesh as CylinderMesh if shade_mesh != null else null
		if shade == null or shade.bottom_radius <= shade.top_radius:
			printerr("FAIL lamp shade does not have a tapered profile: ", id)
			failures += 1
	for id in ["Desk/DrawerBodyCollisionLeft", "Desk/DrawerBodyCollisionRight", "DeskTop/DeskTopCollision"]:
		var collision := game.get_node_or_null(id) as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			printerr("FAIL missing box-form desk assembly collision: ", id)
			failures += 1
	for id in ["Desk/Leg", "Desk/BackPanel", "CurtainLeft/Pleat", "CurtainRight/Pleat"]:
		var structural_mesh := game.get_node_or_null(id) as MeshInstance3D
		if structural_mesh == null or not structural_mesh.mesh is ArrayMesh:
			printerr("FAIL structural detail is still a sharp box: ", id)
			failures += 1
	if game.get_node_or_null("DeskTop/CableGrommet") == null:
		printerr("FAIL missing desk cable grommet")
		failures += 1

	for child in game.get_children():
		failures += _count_concave(child)
	for id in ["Desk", "DeskTop"]:
		var furniture: Node = game.get_node_or_null(id)
		if furniture == null:
			continue
		for shape_node in furniture.find_children("*", "CollisionShape3D", true, false):
			if not shape_node.shape is BoxShape3D:
				printerr("FAIL non-box bedroom collision: ", shape_node.get_path())
				failures += 1
	var old_desk_collision := game.get_node_or_null("Desk/CollisionShape3D") as CollisionShape3D
	if old_desk_collision != null and not old_desk_collision.disabled:
		printerr("FAIL hidden desk shell collision remains active")
		failures += 1

	print("Bedroom detail failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _count_concave(node: Node) -> int:
	var failures := 0
	for child in node.get_children():
		if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
			printerr("FAIL concave bedroom collision: ", child.get_path())
			failures += 1
		failures += _count_concave(child)
	return failures
