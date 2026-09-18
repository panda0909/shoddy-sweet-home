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
		"KitchenDetail_SinkBasin", "KitchenDetail_SinkRim", "KitchenDetail_SinkDrain", "KitchenDetail_FaucetStem",
		"KitchenDetail_FaucetSpout", "KitchenDetail_FaucetHandle", "KitchenDetail_CuttingBoard",
		"KitchenDetail_Cup", "KitchenDetail_SinkLeakTrap", "KitchenDetail_SinkLeakJoint", "KitchenDetail_SinkLeakDrop",
		"KitchenDetail_FridgeHandle", "KitchenDetail_UnderCabinetLight",
		"KitchenDetail_CookerKnob_0", "KitchenDetail_CookerKnob_3",
		"KitchenDetail_FridgeDoorPanel", "KitchenDetail_FridgeGasketTop", "KitchenDetail_FridgeGasketBottom",
		"KitchenDetail_FridgeHingeTop", "KitchenDetail_FridgeHingeBottom", "KitchenDetail_FridgeDisplay",
		"KitchenDetail_OvenGlass", "KitchenDetail_OvenHandle", "KitchenDetail_OvenFrameTop",
		"KitchenDetail_ExtractorHood_Rim", "KitchenDetail_ExtractorHood_Duct", "KitchenDetail_ExtractorHood_Flange", "KitchenDetail_ExtractorHood_UpperJoint",
		"KitchenDetail_SinkBacksplash", "KitchenDetail_SinkBacksplashSeal", "KitchenDetail_SinkCabinetToeKick", "KitchenDetail_SinkCabinetSideSeal",
		"KitchenDetail_TableEdge_Front", "KitchenDetail_TableEdge_Back", "KitchenDetail_FridgeDoorSweep",
		"KitchenDetail_TableEdge_Left", "KitchenDetail_TableEdge_Right", "KitchenDetail_ChairLeg_00_0",
		"KitchenDetail_ChairCrossbarX_00", "KitchenDetail_ChairCrossbarZ_00"
	]
	var failures := 0
	for node_name in required:
		if game.get_node_or_null(node_name) == null:
			printerr("FAIL missing kitchen detail: ", node_name)
			failures += 1
	for node in game.find_children("KitchenDetail_*", "StaticBody3D", true, false):
		if node.get_node_or_null("CollisionShape3D") != null:
			printerr("FAIL kitchen detail became a movement collider: ", node.name)
			failures += 1
	var dining_pads: Array = game.find_children("KitchenDetail_ChairPad_*", "StaticBody3D", true, false)
	if dining_pads.is_empty():
		printerr("FAIL no bounds-attached dining chair pads")
		failures += 1
	var chair_seats: Array = []
	for pad in dining_pads:
		if "Piping" not in pad.name and "Fastener" not in pad.name:
			chair_seats.append(pad)
	var chair_piping: Array = game.find_children("KitchenDetail_ChairPad_Piping_*", "StaticBody3D", true, false)
	var chair_fasteners: Array = game.find_children("KitchenDetail_ChairPad_Fastener_*", "StaticBody3D", true, false)
	if chair_piping.size() < 16 or chair_fasteners.size() < 16:
		printerr("FAIL dining chair upholstery/hardware details: piping=", chair_piping.size(), " fasteners=", chair_fasteners.size())
		failures += 1
	for detail in chair_piping + chair_fasteners:
		if detail.get_node_or_null("CollisionShape3D") != null:
			printerr("FAIL dining chair finish detail blocks movement: ", detail.name)
			failures += 1
	var table_foot_pads: Array = game.find_children("KitchenDetail_TableFootPad_*", "StaticBody3D", true, false)
	if table_foot_pads.size() != 4:
		printerr("FAIL dining table floor contact pads: ", table_foot_pads.size())
		failures += 1
	var chair_legs: Array = game.find_children("KitchenDetail_ChairLeg_*", "StaticBody3D", true, false)
	var chair_crossbars: Array = game.find_children("KitchenDetail_ChairCrossbar*", "StaticBody3D", true, false)
	if chair_legs.size() < chair_seats.size() * 4 or chair_crossbars.size() < chair_seats.size() * 2:
		printerr("FAIL dining chair underframes: seats=", chair_seats.size(), " legs=", chair_legs.size(), " crossbars=", chair_crossbars.size())
		failures += 1
	var sink_worktop: AABB = game._find_kitchen_mesh_bounds("123_Worktops")
	var sink := game.get_node_or_null("KitchenDetail_SinkBasin") as Node3D
	if not sink_worktop.has_volume() or sink == null or sink.global_position.distance_to(sink_worktop.get_center()) > 0.40:
		printerr("FAIL sink is not attached to real worktop bounds")
		failures += 1
	var sink_mesh := sink.get_node_or_null("Mesh") as MeshInstance3D if sink != null else null
	if sink_mesh == null or not sink_mesh.mesh is ArrayMesh or sink_mesh.mesh.get_surface_count() == 0:
		printerr("FAIL sink still uses a low-detail or solid basin mesh")
		failures += 1
	else:
		var sink_bounds := sink_mesh.mesh.get_aabb()
		if sink_bounds.size.x < 0.20 or sink_bounds.size.z < 0.20 or sink_bounds.size.y < 0.04:
			printerr("FAIL sink basin shell dimensions: ", sink_bounds)
			failures += 1
	var sink_drain := game.get_node_or_null("KitchenDetail_SinkDrain") as Node3D
	if sink_drain == null or sink_drain.find_child("CollisionShape3D", true, false) != null:
		printerr("FAIL sink drain missing or blocks movement")
		failures += 1
	var leak_position := Vector3.ZERO
	var sink_cabinet: AABB = game._find_kitchen_mesh_bounds("261_CupboardUnits")
	for issue in game._get_issue_definitions():
		if str(issue["id"]) == "sink_leak":
			leak_position = issue["pos"]
			break
	if leak_position == Vector3.ZERO or not sink_worktop.has_volume() or not sink_cabinet.has_volume() or absf(leak_position.x - (sink_cabinet.position.x - 0.035)) > 0.06 or absf(leak_position.z - (sink_worktop.get_center().z + sink_worktop.size.z * 0.08)) > 0.06:
		printerr("FAIL sink leak issue is not attached to the real sink plumbing bounds")
		failures += 1
	var backsplash := game.get_node_or_null("KitchenDetail_SinkBacksplash") as Node3D
	var backsplash_seal := game.get_node_or_null("KitchenDetail_SinkBacksplashSeal") as Node3D
	var toe_kick := game.get_node_or_null("KitchenDetail_SinkCabinetToeKick") as Node3D
	var side_seal := game.get_node_or_null("KitchenDetail_SinkCabinetSideSeal") as Node3D
	if not sink_worktop.has_volume() or not sink_cabinet.has_volume() or backsplash == null or backsplash_seal == null or toe_kick == null or side_seal == null:
		printerr("FAIL sink run finish details are missing")
		failures += 1
	else:
		var expected_backdrop := Vector3(sink_worktop.end.x + 0.016, sink_worktop.end.y + clampf(sink_cabinet.size.y * 0.16, 0.08, 0.14) * 0.50, sink_worktop.get_center().z)
		if backsplash.global_position.distance_to(expected_backdrop) > 0.05 or backsplash_seal.global_position.x < sink_worktop.end.x - 0.02 or backsplash.global_position.z < sink_worktop.position.z or backsplash.global_position.z > sink_worktop.end.z:
			printerr("FAIL sink backsplash is not attached to measured worktop bounds")
			failures += 1
		var expected_toe_kick := Vector3(sink_cabinet.position.x - 0.013, sink_cabinet.position.y + clampf(sink_cabinet.size.y * 0.12, 0.07, 0.11) * 0.50 + 0.012, sink_cabinet.get_center().z)
		if toe_kick.global_position.distance_to(expected_toe_kick) > 0.05 or side_seal.global_position.x < sink_cabinet.position.x - 0.04 or side_seal.global_position.z < sink_cabinet.position.z or side_seal.global_position.z > sink_cabinet.end.z:
			printerr("FAIL sink cabinet toe-kick/seal is not attached to measured cabinet bounds")
			failures += 1
	var table_bounds: AABB = game._find_kitchen_mesh_bounds("63_Tabletop")
	var cooker_bounds: AABB = game._find_kitchen_mesh_bounds("251_CookerBlack")
	var cooker_knob := game.get_node_or_null("KitchenDetail_CookerKnob_0") as Node3D
	if not cooker_bounds.has_volume() or cooker_knob == null or absf(cooker_knob.global_position.x - (cooker_bounds.position.x - 0.035)) > 0.06 or cooker_knob.global_position.y < cooker_bounds.position.y or cooker_knob.global_position.y > cooker_bounds.end.y:
		printerr("FAIL cooker knobs are not attached to the real cooker bounds")
		failures += 1
	var cutting_board := game.get_node_or_null("KitchenDetail_CuttingBoard") as Node3D
	if not sink_worktop.has_volume() or cutting_board == null or cutting_board.global_position.x < sink_worktop.position.x or cutting_board.global_position.x > sink_worktop.end.x or cutting_board.global_position.z < sink_worktop.position.z or cutting_board.global_position.z > sink_worktop.end.z:
		printerr("FAIL cutting board is not attached to the real worktop bounds")
		failures += 1
	var table_edge := game.get_node_or_null("KitchenDetail_TableEdge_Front") as Node3D
	if not table_bounds.has_volume() or table_edge == null:
		printerr("FAIL dining table bounds-attached edge")
		failures += 1
	var upper_cabinet_bounds: AABB = game._find_kitchen_mesh_bounds("74_CupboardUnits")
	var cabinet_light := game.get_node_or_null("KitchenDetail_UnderCabinetLight") as Node3D
	if not upper_cabinet_bounds.has_volume() or cabinet_light == null:
		printerr("FAIL missing upper-cabinet light anchor")
		failures += 1
	elif cabinet_light.global_position.y >= upper_cabinet_bounds.position.y or absf(cabinet_light.global_position.x - upper_cabinet_bounds.get_center().x) > 0.25 or absf(cabinet_light.global_position.z - upper_cabinet_bounds.get_center().z) > 0.25:
		printerr("FAIL under-cabinet light is not attached to upper cabinet bounds: ", cabinet_light.global_position)
		failures += 1
	var hood_bounds: AABB = game._find_kitchen_mesh_bounds("255_ExtractorHood")
	var hood_rim := game.get_node_or_null("KitchenDetail_ExtractorHood_Rim") as Node3D
	var hood_rim_expected := Vector3(hood_bounds.get_center().x, hood_bounds.position.y - 0.018, hood_bounds.get_center().z) if hood_bounds.has_volume() else Vector3.ZERO
	if not hood_bounds.has_volume() or hood_rim == null or hood_rim.global_position.distance_to(hood_rim_expected) > 0.05:
		printerr("FAIL extractor hood trim is not attached to real hood bounds")
		failures += 1
	var hood_joint := game.get_node_or_null("KitchenDetail_ExtractorHood_UpperJoint") as Node3D
	var upper_run_bounds: AABB = game._find_anchor_group_bounds(["70_CupboardUnits", "74_CupboardUnits"])
	var hood_joint_expected_y := hood_bounds.end.y + maxf(0.035, upper_run_bounds.end.y - hood_bounds.end.y) * 0.50 if hood_bounds.has_volume() and upper_run_bounds.has_volume() else 0.0
	if not hood_bounds.has_volume() or not upper_run_bounds.has_volume() or hood_joint == null or absf(hood_joint.global_position.x - hood_bounds.get_center().x) > 0.05 or absf(hood_joint.global_position.z - hood_bounds.get_center().z) > 0.05 or absf(hood_joint.global_position.y - hood_joint_expected_y) > 0.05:
		printerr("FAIL extractor hood upper joint is not attached to hood/cabinet bounds")
		failures += 1
	else:
		var joint_mesh := hood_joint.get_node_or_null("Mesh") as MeshInstance3D
		var joint_box := joint_mesh.mesh as BoxMesh if joint_mesh != null else null
		if joint_box == null or joint_box.size.y <= 0.0 or joint_box.size.y > 0.20:
			printerr("FAIL extractor hood upper joint has invalid bridge height")
			failures += 1
	var fridge_bounds: AABB = game._find_kitchen_mesh_bounds("253_CupboardUnits")
	var fridge_handle := game.get_node_or_null("KitchenDetail_FridgeHandle") as Node3D
	var fridge_handle_expected := Vector3(fridge_bounds.position.x - 0.035, fridge_bounds.get_center().y, fridge_bounds.get_center().z) if fridge_bounds.has_volume() else Vector3.ZERO
	if not fridge_bounds.has_volume() or fridge_handle == null or fridge_handle.global_position.distance_to(fridge_handle_expected) > 0.06:
		printerr("FAIL refrigerator handle is not attached to the imported cabinet bounds")
		failures += 1
	else:
		var handle_mesh := fridge_handle.get_node_or_null("Mesh") as MeshInstance3D
		var handle_box := handle_mesh.mesh as BoxMesh if handle_mesh != null else null
		if handle_box == null or handle_box.size.y < 0.48 or handle_box.size.y > 0.68:
			printerr("FAIL refrigerator handle has unexpected vertical proportion")
			failures += 1
	var fridge_panel := game.get_node_or_null("KitchenDetail_FridgeDoorPanel") as Node3D
	var fridge_panel_expected := Vector3(fridge_bounds.position.x - 0.014, fridge_bounds.get_center().y, fridge_bounds.get_center().z) if fridge_bounds.has_volume() else Vector3.ZERO
	if not fridge_bounds.has_volume() or fridge_panel == null or fridge_panel.global_position.distance_to(fridge_panel_expected) > 0.06:
		printerr("FAIL refrigerator door panel is not attached to the imported front bounds")
		failures += 1
	var fridge_sweep := game.get_node_or_null("KitchenDetail_FridgeDoorSweep") as MeshInstance3D
	if fridge_sweep == null or not fridge_sweep.mesh is ImmediateMesh or fridge_sweep.visible:
		printerr("FAIL refrigerator sweep visual is not a hidden render-only debug mesh")
		failures += 1
	else:
		if fridge_sweep.get_node_or_null("CollisionShape3D") != null or not fridge_sweep.has_meta("no_collision"):
			printerr("FAIL refrigerator sweep visual can affect movement")
			failures += 1
		game._toggle_geometry_debug()
		if not fridge_sweep.visible:
			printerr("FAIL refrigerator sweep visual did not enable")
			failures += 1
		game._toggle_geometry_debug()
		if fridge_sweep.visible:
			printerr("FAIL refrigerator sweep visual did not disable")
			failures += 1
	var oven_glass := game.get_node_or_null("KitchenDetail_OvenGlass") as Node3D
	var oven_expected_x := cooker_bounds.position.x - 0.015 if cooker_bounds.has_volume() else 0.0
	if not cooker_bounds.has_volume() or oven_glass == null or absf(oven_glass.global_position.x - oven_expected_x) > 0.06:
		printerr("FAIL oven front is not attached to the imported cooker bounds")
		failures += 1
	var oven_glass_mesh := oven_glass.get_node_or_null("Mesh") as MeshInstance3D if oven_glass != null else null
	var oven_glass_material := oven_glass_mesh.material_override as StandardMaterial3D if oven_glass_mesh != null else null
	if oven_glass_material == null or oven_glass_material.clearcoat < 0.45 or oven_glass_material.clearcoat_roughness > 0.16:
		printerr("FAIL kitchen oven glass clearcoat tuning")
		failures += 1
	var fridge_enamel_node := game.get_node_or_null("KitchenDetail_FridgeDoorPanel") as Node3D
	var fridge_enamel_mesh := fridge_enamel_node.get_node_or_null("Mesh") as MeshInstance3D if fridge_enamel_node != null else null
	var fridge_enamel_material := fridge_enamel_mesh.material_override as StandardMaterial3D if fridge_enamel_mesh != null else null
	if fridge_enamel_material == null or fridge_enamel_material.clearcoat < 0.18:
		printerr("FAIL refrigerator enamel clearcoat tuning")
		failures += 1
	print("Kitchen detail nodes: ", required.size(), "; dining pads: ", dining_pads.size(), "; chair legs: ", chair_legs.size(), "; table foot pads: ", table_foot_pads.size())
	print("Kitchen detail failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
