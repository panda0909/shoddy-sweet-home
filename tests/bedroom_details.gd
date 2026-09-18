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
	var oak_a := game._wood_mat(Color(0.72, 0.47, 0.25)) as StandardMaterial3D
	var oak_b := game._wood_mat(Color(0.72, 0.47, 0.25)) as StandardMaterial3D
	var fabric_a := game._fabric_mat(Color(0.34, 0.48, 0.59)) as StandardMaterial3D
	var fabric_b := game._fabric_mat(Color(0.34, 0.48, 0.59)) as StandardMaterial3D
	if oak_a == null or oak_b == null or oak_a.get_instance_id() != oak_b.get_instance_id():
		printerr("FAIL identical oak tones do not reuse a PBR material")
		failures += 1
	if fabric_a == null or fabric_b == null or fabric_a.get_instance_id() != fabric_b.get_instance_id():
		printerr("FAIL identical fabric tones do not reuse a PBR material")
		failures += 1
	var bedroom_roots := [
		"BedroomRug", "BedBase", "BedHeadboard", "Mattress", "Duvet", "PillowLeft", "PillowRight", "BedThrow",
		"BedsideTable_Left", "BedsideTable_Right", "BedsideLampShade_Left", "BedsideLampShade_Right",
		"Closet", "ClosetDoorLeft", "ClosetDoorRight", "Desk", "DeskTop", "Monitor", "MonitorStand",
		"DeskChairBack", "DeskChairSeat", "Bookcase", "WindowFrame", "WindowGlass", "CurtainLeft", "CurtainRight",
		"WallArtFrame", "WallArt", "BedroomPlantPot", "BedroomPlant"
	]
	for root_id in bedroom_roots:
		var bedroom_root := game.get_node_or_null(root_id) as Node
		if bedroom_root == null:
			continue
		for mesh_node in bedroom_root.find_children("*", "MeshInstance3D", true, false):
			var mesh := mesh_node as MeshInstance3D
			if mesh != null and mesh.material_override is ShaderMaterial:
				printerr("FAIL ShaderMaterial overrides bedroom PBR flow: ", mesh.get_path())
				failures += 1
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
		"Duvet/QuiltSurface",
		"DeskChairSeat/BackCushion", "DeskChairSeat/BaseArm_0",
		"Desk/FrontApron", "DeskTop/DesktopFrontNosing", "DeskTop/DesktopLeftReturn",
		"DeskTop/KeyboardKey_00", "DeskTop/KeyboardKey_11", "Monitor/MonitorScreen",
		"Monitor/MonitorBezelTop", "Monitor/MonitorBezelBottom", "MonitorStand/MonitorFoot",
		"BedroomPlant/Stem_0", "BedroomPlant/Stem_15",
		"CurtainLeft/CurtainRod", "CurtainRight/CurtainRod"
	]:
		if game.get_node_or_null(id) == null:
			printerr("FAIL missing P0 finish detail: ", id)
			failures += 1
	var quilt_surface := game.get_node_or_null("Duvet/QuiltSurface") as MeshInstance3D
	if quilt_surface == null or not quilt_surface.mesh is ArrayMesh or quilt_surface.mesh.get_aabb().size.x < 3.0:
		printerr("FAIL duvet quilt surface is incomplete")
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
	for id in ["Desk/Leg_0", "Desk/Leg_3", "Desk/BackPanel", "Desk/FrontApron", "CurtainLeft/DrapePanel", "CurtainRight/DrapePanel"]:
		var structural_mesh := game.get_node_or_null(id) as MeshInstance3D
		if structural_mesh == null or not structural_mesh.mesh is ArrayMesh:
			printerr("FAIL structural detail is still a sharp box: ", id)
			failures += 1
	for id in ["CurtainLeft/DrapePanel", "CurtainRight/DrapePanel"]:
		var drape := game.get_node_or_null(id) as MeshInstance3D
		if drape == null or drape.mesh.get_surface_count() == 0 or drape.mesh.get_aabb().size.y < 1.5:
			printerr("FAIL curtain drape mesh is incomplete: ", id)
			failures += 1
	for id in ["CurtainLeft/DrapeHem", "CurtainRight/DrapeHem"]:
		if game.get_node_or_null(id) == null:
			printerr("FAIL missing curtain hem: ", id)
			failures += 1
	for id in ["Desk/Leg_0", "Desk/Leg_3", "Desk/BackPanel", "Desk/FrontApron", "Desk/DrawerBodyLeft", "Desk/DrawerBodyRight", "Desk/DrawerFront"]:
		var desk_mesh := game.get_node_or_null(id) as MeshInstance3D
		var desk_material := desk_mesh.material_override as StandardMaterial3D if desk_mesh != null else null
		if desk_material == null or desk_material.albedo_texture == null or desk_material.roughness_texture == null:
			printerr("FAIL desk wood detail is outside the shared PBR path: ", id)
			failures += 1
	var key_count := game.get_node("DeskTop").find_children("KeyboardKey_*", "MeshInstance3D", true, false).size()
	if key_count != 12:
		printerr("FAIL keyboard keycap count: ", key_count)
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

	print("Bedroom PBR cache entries: oak=", game.wood_material_cache.size(), " fabric=", game.fabric_material_cache.size())
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
