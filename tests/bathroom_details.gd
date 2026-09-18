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

	var required := [
		"ImportedBath_ToiletBase", "ImportedBath_ToiletTank", "ImportedBath_ToiletSeat",
		"ImportedBath_ToiletWater", "ImportedBath_ToiletBowlRim", "ImportedBath_ToiletBowlInset",
		"ImportedBath_ToiletHingeLeft", "ImportedBath_ToiletHingeRight", "ImportedBath_FlushButtonRing", "ImportedBath_FlushLever",
		"ImportedBath_ShowerTray", "ImportedBath_ShowerGlass", "ImportedBath_ShowerPipe",
		"ImportedBath_ShowerHead", "ImportedBath_ShowerFrame_Left", "ImportedBath_ShowerFrame_Top",
		"ImportedBath_ShowerHeadRose", "ImportedBath_ShowerNozzle_0", "ImportedBath_ShowerNozzle_7",
		"ImportedBath_ShowerShelf", "ImportedBath_ShowerControl", "ImportedBath_ShowerControlRing", "ImportedBath_ShowerDrainCrossA", "ImportedBath_ShowerDrainCrossB", "ImportedBath_ShowerThreshold", "ImportedBath_ShowerGlassSeal", "ImportedBath_ShowerGlassHandle", "ImportedBath_TowelBar",
		"ImportedBath_DrainCover", "ImportedBath_VanityCounterEdge", "ImportedBath_VanityFrontLip", "ImportedBath_TowelFold_0", "ImportedBath_TowelFold_2",
		"ImportedBath_VanityBasinLeft", "ImportedBath_VanityBasinRight",
		"ImportedBath_VanityFaucetLeft", "ImportedBath_VanityFaucetRight",
		"ImportedBath_VanityHandle_0", "ImportedBath_VanityHandle_3",
		"ImportedBath_MirrorEdgeTop", "ImportedBath_MirrorEdgeLeft", "ImportedBath_MirrorEdgeRight"
	]
	var failures := 0
	var detail_root: Node = game.get_node_or_null("BathroomDetailBatch")
	var detail_batches: Array = detail_root.find_children("StaticBatch_*", "MeshInstance3D", true, false) if detail_root != null else []
	if detail_root == null or detail_batches.size() < 3:
		printerr("FAIL bathroom details were not batched: ", detail_batches.size())
		failures += 1
	if detail_batches.size() > 12:
		printerr("FAIL bathroom detail material batches regressed: ", detail_batches.size())
		failures += 1
	for node_name in required:
		if game.find_child(node_name, true, false) == null:
			printerr("FAIL missing imported bathroom detail: ", node_name)
			failures += 1
	for node_name in ["ImportedBath_ToiletBase", "ImportedBath_ToiletTank", "ImportedBath_ToiletSeat", "ImportedBath_ShowerTray"]:
		var node: Node = game.find_child(node_name, true, false)
		if node == null or node.find_child("CollisionShape3D", true, false) == null:
			printerr("FAIL missing bathroom collision: ", node_name)
			failures += 1
	var toilet_mesh := game.find_child("ImportedBath_ToiletBase", true, false).find_child("Mesh", true, false) as MeshInstance3D
	if toilet_mesh == null or not toilet_mesh.mesh is SphereMesh:
		printerr("FAIL toilet base still uses a low-detail cylinder silhouette")
		failures += 1
	else:
		var bowl := toilet_mesh.mesh as SphereMesh
		if bowl.radial_segments < 24 or bowl.rings < 12:
			printerr("FAIL toilet bowl segment quality: ", bowl.radial_segments, "x", bowl.rings)
			failures += 1
	var tank_mesh := game.find_child("ImportedBath_ToiletTank", true, false).find_child("Mesh", true, false) as MeshInstance3D
	if tank_mesh == null or not tank_mesh.mesh is ArrayMesh:
		printerr("FAIL toilet tank still uses a sharp box silhouette")
		failures += 1
	var seat_mesh := game.find_child("ImportedBath_ToiletSeat", true, false).find_child("Mesh", true, false) as MeshInstance3D
	if seat_mesh == null or not seat_mesh.mesh is SphereMesh:
		printerr("FAIL toilet seat still uses a low-detail cylinder silhouette")
		failures += 1
	else:
		var seat := seat_mesh.mesh as SphereMesh
		if seat.radial_segments < 24 or seat.rings < 12:
			printerr("FAIL toilet seat segment quality: ", seat.radial_segments, "x", seat.rings)
			failures += 1
	var lid_mesh := game.find_child("ImportedBath_ToiletLid", true, false).find_child("Mesh", true, false) as MeshInstance3D
	if lid_mesh == null or not lid_mesh.mesh is ArrayMesh:
		printerr("FAIL toilet lid still uses a sharp box silhouette")
		failures += 1
	for basin_name in ["ImportedBath_VanityBasinLeft", "ImportedBath_VanityBasinRight"]:
		var basin_mesh := game.find_child(basin_name, true, false).find_child("Mesh", true, false) as MeshInstance3D
		if basin_mesh == null or not basin_mesh.mesh is SphereMesh:
			printerr("FAIL vanity basin still uses a low-detail cylinder silhouette: ", basin_name)
			failures += 1
		else:
			var basin := basin_mesh.mesh as SphereMesh
			if basin.radial_segments < 20 or basin.rings < 10:
				printerr("FAIL vanity basin segment quality: ", basin_name)
				failures += 1
	var vanity_source_bounds: AABB = game._find_anchor_group_bounds(["43_Marble", "838_Marble"])
	var vanity_counter := game.find_child("ImportedBath_VanityCounterEdge", true, false) as Node3D
	var vanity_expected := Vector3(vanity_source_bounds.get_center().x, vanity_source_bounds.end.y + 0.11, vanity_source_bounds.get_center().z) if vanity_source_bounds.has_volume() else Vector3.ZERO
	if not vanity_source_bounds.has_volume() or vanity_counter == null or vanity_counter.global_position.distance_to(vanity_expected) > 0.06:
		printerr("FAIL vanity counter is not attached to imported marble bounds")
		failures += 1
	var bathroom_reference_bounds: AABB = game._find_bathroom_mesh_bounds("849_Ceiling")
	var toilet_base := game.find_child("ImportedBath_ToiletBase", true, false) as Node3D
	var toilet_expected := Vector3(bathroom_reference_bounds.end.x - 0.20, 0.31, bathroom_reference_bounds.position.z + bathroom_reference_bounds.size.z * 0.58) if bathroom_reference_bounds.has_volume() else Vector3.ZERO
	if not bathroom_reference_bounds.has_volume() or toilet_base == null or toilet_base.global_position.distance_to(toilet_expected) > 0.06:
		printerr("FAIL toilet fixture is not attached to bathroom room bounds")
		failures += 1
	for node_name in required:
		var detail: Node = game.find_child(node_name, true, false)
		if detail != null and detail.find_child("CollisionShape3D", true, false) != null and ("Vanity" in node_name or "MirrorEdge" in node_name):
			printerr("FAIL bathroom finish detail blocks movement: ", node_name)
			failures += 1
	var door_leaf := game.find_child("RightInnerDoor", true, false) as StaticBody3D
	var door_mesh := door_leaf.get_node_or_null("Mesh") as MeshInstance3D if door_leaf != null else null
	var vanity := game.find_child("ImportedBath_VanityCounterEdge", true, false) as StaticBody3D
	var vanity_mesh := vanity.get_node_or_null("Mesh") as MeshInstance3D if vanity != null else null
	if door_mesh == null or vanity_mesh == null:
		printerr("FAIL missing bathroom door or vanity bounds probe")
		failures += 1
	else:
		var vanity_bounds: AABB = vanity_mesh.global_transform * vanity_mesh.get_aabb()
		for opened in [false, true]:
			game.doors["RightInnerDoor"]["is_open"] = opened
			game._animate_doors(1.0)
			var door_bounds: AABB = door_mesh.global_transform * door_mesh.get_aabb()
			if door_bounds.intersects(vanity_bounds):
				printerr("FAIL bathroom door sweep overlaps vanity; open=", opened)
				failures += 1
	var tray_node: Node = game.find_child("ImportedBath_ShowerTray", true, false)
	var tray_mesh := tray_node.find_child("Mesh", true, false) as MeshInstance3D if tray_node != null else null
	var tray_bounds: AABB = tray_mesh.global_transform * tray_mesh.get_aabb() if tray_mesh != null else AABB()
	for fitting_name in ["ImportedBath_ShowerPipe", "ImportedBath_ShowerHead", "ImportedBath_ShowerControl"]:
		var fitting: Node = game.find_child(fitting_name, true, false)
		if fitting == null or not tray_bounds.has_volume() or absf((fitting as Node3D).global_position.x - tray_bounds.get_center().x) > tray_bounds.size.x * 0.75 or absf((fitting as Node3D).global_position.z - tray_bounds.get_center().z) > tray_bounds.size.z * 0.75:
			printerr("FAIL shower fitting is outside tray alignment: ", fitting_name)
			failures += 1
	var shower_ring := game.find_child("ImportedBath_ShowerControlRing", true, false) as Node3D
	var shower_control := game.find_child("ImportedBath_ShowerControl", true, false) as Node3D
	if shower_ring == null or shower_control == null or shower_ring.global_position.distance_to(shower_control.global_position + Vector3(0, 0.025, 0)) > 0.06:
		printerr("FAIL shower control ring is not attached to the control bounds")
		failures += 1
	var nozzle_count: int = game.find_children("ImportedBath_ShowerNozzle_*", "StaticBody3D", true, false).size()
	if nozzle_count != 8:
		printerr("FAIL shower head nozzle count: ", nozzle_count)
		failures += 1
	var glass_node: Node = game.find_child("ImportedBath_ShowerGlass", true, false)
	var glass_mesh := glass_node.find_child("Mesh", true, false) as MeshInstance3D if glass_node != null else null
	var glass_bounds: AABB = glass_mesh.global_transform * glass_mesh.get_aabb() if glass_mesh != null else AABB()
	if not tray_bounds.has_volume() or not glass_bounds.has_volume() or absf(glass_bounds.get_center().x - tray_bounds.get_center().x) > tray_bounds.size.x * 0.5 + 0.35 or absf(glass_bounds.get_center().z - tray_bounds.get_center().z) > 0.10:
		printerr("FAIL shower glass is not attached to tray bounds")
		failures += 1
	var threshold := game.find_child("ImportedBath_ShowerThreshold", true, false) as Node3D
	var glass_handle := game.find_child("ImportedBath_ShowerGlassHandle", true, false) as Node3D
	if threshold == null or glass_handle == null or not tray_bounds.has_volume() or absf(threshold.global_position.x - glass_bounds.get_center().x) > 0.12 or absf(threshold.global_position.z - tray_bounds.get_center().z) > tray_bounds.size.z * 0.60 or absf(glass_handle.global_position.x - glass_bounds.get_center().x) > 0.18 or absf(glass_handle.global_position.z - glass_bounds.get_center().z) > 0.10:
		printerr("FAIL shower threshold/handle is not attached to glass and tray bounds")
		failures += 1
	var towel_left_bounds: AABB = game._find_bathroom_mesh_bounds("835_StainlessSmooth")
	var towel_right_bounds: AABB = game._find_bathroom_mesh_bounds("834_StainlessSmooth")
	var towel_bar := game.find_child("ImportedBath_TowelBar", true, false) as Node3D
	if not towel_left_bounds.has_volume() or not towel_right_bounds.has_volume() or towel_bar == null:
		printerr("FAIL towel rail anchors are missing from the imported wall")
		failures += 1
	else:
		var towel_expected_x := (towel_left_bounds.get_center().x + towel_right_bounds.get_center().x) * 0.5
		var towel_expected_y := (towel_left_bounds.get_center().y + towel_right_bounds.get_center().y) * 0.5 + 0.22
		var towel_expected_z := maxf(towel_left_bounds.end.z, towel_right_bounds.end.z) + 0.025
		if towel_bar.global_position.distance_to(Vector3(towel_expected_x, towel_expected_y, towel_expected_z)) > 0.06:
			printerr("FAIL towel rail is not attached to imported wall mounts: ", towel_bar.global_position)
			failures += 1
	var ceiling_bounds: AABB = game._find_bathroom_mesh_bounds("849_Ceiling")
	var ceiling_vent := game.find_child("ImportedBath_CeilingVent", true, false) as Node3D
	var vent_expected := Vector3(ceiling_bounds.end.x - 1.35, ceiling_bounds.end.y + 0.17, ceiling_bounds.end.z - 0.064) if ceiling_bounds.has_volume() else Vector3.ZERO
	if not ceiling_bounds.has_volume() or ceiling_vent == null or ceiling_vent.global_position.distance_to(vent_expected) > 0.06:
		printerr("FAIL bathroom exhaust vent is not attached to ceiling bounds")
		failures += 1
	print("Imported bathroom detail nodes: ", required.size(), "; shower nozzles: ", nozzle_count, "; material batches: ", detail_batches.size())
	print("Bathroom detail failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
