extends RefCounted

static func apply(room: Node3D) -> void:
	for id in ["BedBase", "BedHeadboard", "Closet", "ClosetDoorLeft", "ClosetDoorRight", "DeskTop", "Bookcase", "BedsideTable_Left", "BedsideTable_Right"]:
		var part := room.get_node_or_null(id)
		if part == null:
			continue
		var mesh: MeshInstance3D = part.get_node("Mesh")
		var material := mesh.material_override as StandardMaterial3D
		if material != null:
			# Keep the same PBR path as main.gd. The former procedural shader
			# replaced both the generated albedo and roughness textures.
			material.albedo_texture = room.generated_oak_texture
			material.roughness_texture = room.generated_oak_roughness_texture
			material.normal_enabled = room.generated_oak_normal_texture != null
			material.normal_texture = room.generated_oak_normal_texture
			material.normal_scale = 0.18
			material.roughness = 0.58
		if mesh.mesh is BoxMesh:
			mesh.mesh = rounded(mesh.mesh.size, 0.025)
	for id in ["Mattress", "Duvet", "PillowLeft", "PillowRight", "BedThrow", "DeskChairBack"]:
		var mesh: MeshInstance3D = room.get_node(id).get_node("Mesh")
		mesh.mesh = rounded(mesh.mesh.size, 0.07 if "Pillow" in id else 0.035)
		var material := mesh.material_override as StandardMaterial3D
		if material != null:
			material.normal_enabled = room.generated_fabric_normal_texture != null
			material.normal_texture = room.generated_fabric_normal_texture
			material.normal_scale = 0.12
	# Replace the solid desk front with four legs and a modesty panel.
	var desk: Node3D = room.get_node("Desk")
	desk.get_node("Mesh").hide()
	desk.get_node("CollisionShape3D").disabled = true
	for x in [-1.05, 1.05]:
		for z in [-0.27, 0.27]:
			room._add_door_frame_piece(desk, "Leg", Vector3(0.065, 0.85, 0.065), Vector3(x, 0, z), room._mat(Color(0.15, 0.13, 0.10)))
			_add_box_collision(desk, "LegCollision", Vector3(0.13, 0.85, 0.13), Vector3(x, 0, z))
	room._add_door_frame_piece(desk, "BackPanel", Vector3(2.2, 0.28, 0.04), Vector3(0, 0.20, -0.31), room._mat(Color(0.3, 0.19, 0.11)))
	_add_box_collision(desk, "BackPanelCollision", Vector3(2.2, 0.28, 0.04), Vector3(0, 0.20, -0.31))
	# Two shallow drawer pedestals turn the desk from a hidden shell into a
	# readable piece of joinery. Their bodies and drawer fronts remain separate
	# so the collision stays a pair of simple boxes instead of a trimesh.
	for side_data in [["Left", -0.82], ["Right", 0.82]]:
		var side_name: String = side_data[0]
		var side_x: float = side_data[1]
		room._add_door_frame_piece(desk, "DrawerBody" + side_name, Vector3(0.42, 0.50, 0.62), Vector3(side_x, -0.17, 0.02), room._wood_mat(Color(0.63, 0.40, 0.22)))
		_add_box_collision(desk, "DrawerBodyCollision" + side_name, Vector3(0.42, 0.50, 0.62), Vector3(side_x, -0.17, 0.02))
		_add_detail_box(desk, "DrawerFront" + side_name, Vector3(0.34, 0.16, 0.025), Vector3(side_x, -0.02, 0.34), room._wood_mat(Color(0.72, 0.47, 0.25)))
		_add_detail_box(desk, "DrawerPull" + side_name, Vector3(0.13, 0.022, 0.032), Vector3(side_x, -0.02, 0.365), room._mat(Color(0.56, 0.42, 0.24)))
	var desk_top: Node3D = room.get_node("DeskTop")
	_add_box_collision(desk_top, "DeskTopCollision", Vector3(2.55, 0.10, 0.85), Vector3.ZERO)
	# A small cable grommet is an actual desk detail, not a floating UI clue.
	_add_detail_cylinder(desk_top, "CableGrommet", 0.055, 0.018, Vector3(-0.82, 0.062, -0.22), room._mat(Color(0.08, 0.09, 0.10)))

	# Mattress piping, duvet seams and a shallow throw fold make the soft parts
	# read as manufactured fabric instead of flat colored boxes.
	var mattress: Node3D = room.get_node("Mattress")
	var fabric_trim: Material = room._fabric_mat(Color(0.90, 0.92, 0.91))
	_add_detail_box(mattress, "PipingFront", Vector3(3.04, 0.025, 0.025), Vector3(0, 0.215, 1.20), fabric_trim)
	_add_detail_box(mattress, "PipingBack", Vector3(3.04, 0.025, 0.025), Vector3(0, 0.215, -1.20), fabric_trim)
	_add_detail_box(mattress, "PipingLeft", Vector3(0.025, 0.025, 2.38), Vector3(-1.53, 0.215, 0), fabric_trim)
	_add_detail_box(mattress, "PipingRight", Vector3(0.025, 0.025, 2.38), Vector3(1.53, 0.215, 0), fabric_trim)
	var duvet: Node3D = room.get_node("Duvet")
	for seam_index in range(4):
		_add_detail_box(duvet, "DuvetSeam_%d" % seam_index, Vector3(0.025, 0.018, 1.34), Vector3(-1.15 + seam_index * 0.77, 0.09, 0), fabric_trim)
	# A narrow side band and soft transverse folds give the mattress and duvet
	# manufactured thickness instead of reading as two unbroken cuboids.
	_add_detail_box(mattress, "SideBandFront", Vector3(3.00, 0.12, 0.025), Vector3(0, -0.11, 1.24), room._fabric_mat(Color(0.60, 0.67, 0.72)))
	_add_detail_box(mattress, "SideBandLeft", Vector3(0.025, 0.12, 2.35), Vector3(-1.51, -0.11, 0), room._fabric_mat(Color(0.60, 0.67, 0.72)))
	for fold_index in range(3):
		_add_detail_box(duvet, "DuvetFold_%d" % fold_index, Vector3(0.42, 0.028, 1.22), Vector3(-0.82 + fold_index * 0.78, 0.125, 0.02), room._fabric_mat(Color(0.48, 0.63, 0.75)))
	# A drawer front and small pulls give each bedside table a usable visual scale.
	for bedside_id in ["BedsideTable_Left", "BedsideTable_Right"]:
		var bedside: Node3D = room.get_node(bedside_id)
		_add_detail_box(bedside, "DrawerFront", Vector3(0.56, 0.22, 0.025), Vector3(0, 0.12, 0.315), room._wood_mat(Color(0.74, 0.48, 0.27)))
		_add_detail_box(bedside, "DrawerPull", Vector3(0.18, 0.025, 0.035), Vector3(0, 0.12, 0.335), room._mat(Color(0.55, 0.40, 0.20)))
		var lamp_shade := room.get_node("BedsideLampShade_" + ("Left" if "Left" in bedside_id else "Right"))
		var shade_mesh := lamp_shade.get_node("Mesh") as MeshInstance3D
		if shade_mesh != null and shade_mesh.mesh is CylinderMesh:
			var shade := shade_mesh.mesh as CylinderMesh
			shade.top_radius = 0.17
			shade.bottom_radius = 0.25
			shade.radial_segments = 24
			shade.rings = 4
		_add_detail_cylinder(lamp_shade, "LampShadeRim", 0.255, 0.025, Vector3(0, -0.135, 0), room._mat(Color(0.48, 0.32, 0.18)))
		_add_detail_cylinder(lamp_shade, "LampSocket", 0.075, 0.08, Vector3(0, 0.02, 0), room._mat(Color(0.28, 0.22, 0.15)))
		_add_detail_sphere(lamp_shade, "LampBulb", 0.065, Vector3(0, 0.105, 0), room._emissive_mat(Color(1.0, 0.70, 0.25), 1.15))
	# Closet construction lines and visible hinges make the doors read as parts.
	var closet_left: Node3D = room.get_node("ClosetDoorLeft")
	var closet_right: Node3D = room.get_node("ClosetDoorRight")
	for door in [closet_left, closet_right]:
		_add_detail_box(door, "InsetPanel", Vector3(0.82, 1.82, 0.012), Vector3(0, 0, 0.026), room._wood_mat(Color(0.62, 0.39, 0.22)))
		_add_detail_box(door, "UpperHinge", Vector3(0.06, 0.12, 0.025), Vector3(-0.38, 0.76, 0.04), room._mat(Color(0.26, 0.23, 0.19)))
		_add_detail_box(door, "LowerHinge", Vector3(0.06, 0.12, 0.025), Vector3(-0.38, -0.76, 0.04), room._mat(Color(0.26, 0.23, 0.19)))
		_add_detail_box(door, "DoorEdgeBand", Vector3(0.025, 1.92, 0.022), Vector3(0.48, 0, 0.042), room._wood_mat(Color(0.48, 0.28, 0.14)))
	var closet: Node3D = room.get_node("Closet")
	_add_detail_box(closet, "ClosetInteriorShadow", Vector3(2.05, 1.96, 0.025), Vector3(0, 0, -0.31), room._mat(Color(0.055, 0.038, 0.026)))
	_add_detail_box(closet, "ClosetBottomRail", Vector3(2.12, 0.055, 0.045), Vector3(0, -1.06, 0.335), room._wood_mat(Color(0.55, 0.33, 0.18)))
	_add_detail_box(closet, "ClosetTopRail", Vector3(2.12, 0.055, 0.045), Vector3(0, 1.06, 0.335), room._wood_mat(Color(0.55, 0.33, 0.18)))
	_add_detail_box(closet, "ClosetCenterSeam", Vector3(0.025, 1.95, 0.03), Vector3(0, 0, 0.35), room._mat(Color(0.20, 0.12, 0.07)))
	_add_detail_box(closet, "ClosetHandleMountLeft", Vector3(0.10, 0.10, 0.03), Vector3(-0.49, 0, 0.38), room._mat(Color(0.32, 0.25, 0.18)))
	_add_detail_box(closet, "ClosetHandleMountRight", Vector3(0.10, 0.10, 0.03), Vector3(0.49, 0, 0.38), room._mat(Color(0.32, 0.25, 0.18)))
	# Desk details: a recessed drawer, monitor foot, keyboard and chair arms/base.
	_add_detail_box(desk, "DrawerFront", Vector3(1.05, 0.18, 0.025), Vector3(0, 0.30, 0.38), room._wood_mat(Color(0.72, 0.47, 0.25)))
	_add_detail_box(desk, "DrawerPull", Vector3(0.20, 0.025, 0.035), Vector3(0, 0.30, 0.40), room._mat(Color(0.56, 0.42, 0.24)))
	_add_detail_box(room.get_node("DeskTop"), "Keyboard", Vector3(0.65, 0.025, 0.22), Vector3(0.20, 0.08, 0.18), room._mat(Color(0.06, 0.07, 0.08)))
	var chair: Node3D = room.get_node("DeskChairSeat")
	_add_detail_box(chair, "ArmLeft", Vector3(0.07, 0.22, 0.42), Vector3(-0.34, 0.15, 0), room._fabric_mat(Color(0.42, 0.56, 0.66)))
	_add_detail_box(chair, "ArmRight", Vector3(0.07, 0.22, 0.42), Vector3(0.34, 0.15, 0), room._fabric_mat(Color(0.42, 0.56, 0.66)))
	_add_detail_box(chair, "BackCushion", Vector3(0.48, 0.48, 0.055), Vector3(0, 0.20, -0.055), room._fabric_mat(Color(0.34, 0.48, 0.59)))
	_add_detail_box(chair, "SeatEdge", Vector3(0.68, 0.055, 0.45), Vector3(0, 0.02, 0.02), room._fabric_mat(Color(0.34, 0.48, 0.59)))
	_add_detail_box(chair, "ChairStem", Vector3(0.08, 0.30, 0.08), Vector3(0, -0.20, 0), room._mat(Color(0.12, 0.14, 0.16)))
	for wheel_index in range(5):
		var wheel_angle := TAU * float(wheel_index) / 5.0
		_add_detail_box(chair, "Wheel_%d" % wheel_index, Vector3(0.10, 0.04, 0.18), Vector3(cos(wheel_angle) * 0.27, -0.36, sin(wheel_angle) * 0.27), room._mat(Color(0.05, 0.06, 0.07)))
		_add_detail_box(chair, "BaseArm_%d" % wheel_index, Vector3(0.055, 0.035, 0.25), Vector3(cos(wheel_angle) * 0.14, -0.31, sin(wheel_angle) * 0.14), room._mat(Color(0.12, 0.14, 0.16)))
	# Rug edge and corner lift add thickness without adding a movement obstacle.
	var rug: Node3D = room.get_node("BedroomRug")
	var rug_trim: Material = room._fabric_mat(Color(0.16, 0.21, 0.25))
	_add_detail_box(rug, "RugFrontEdge", Vector3(4.65, 0.025, 0.08), Vector3(0, 0.045, 1.76), rug_trim)
	_add_detail_box(rug, "RugBackEdge", Vector3(4.65, 0.025, 0.08), Vector3(0, 0.045, -1.76), rug_trim)
	_add_detail_box(rug, "RugCornerLift", Vector3(0.28, 0.06, 0.28), Vector3(-2.16, 0.09, 1.56), rug_trim)
	for fringe_index in range(12):
		_add_detail_box(rug, "RugFringe_%d" % fringe_index, Vector3(0.12, 0.018, 0.10), Vector3(-2.05 + fringe_index * 0.37, 0.055, 1.84), rug_trim)
	for tuft_index in range(7):
		_add_detail_box(rug, "RugTuft_%d" % tuft_index, Vector3(4.05, 0.012, 0.018), Vector3(0, 0.058, -1.35 + tuft_index * 0.42), room._fabric_mat(Color(0.22, 0.28, 0.33)))
	# Soil, pot rim and a stem turn the plant into a small assembled prop.
	var pot: Node3D = room.get_node("BedroomPlantPot")
	_add_detail_cylinder(pot, "Soil", 0.19, 0.025, Vector3(0, 0.22, 0), room._mat(Color(0.12, 0.07, 0.035)))
	_add_detail_cylinder(pot, "PotRim", 0.285, 0.045, Vector3(0, 0.17, 0), room._mat(Color(0.42, 0.25, 0.14)))
	# Replace the cylindrical foliage with individual curved leaves.
	var plant: Node3D = room.get_node("BedroomPlant")
	plant.get_node("Mesh").hide()
	for i in range(16):
		var stem := _add_detail_cylinder(plant, "Stem_%d" % i, 0.012, 0.32, Vector3(0, -0.30 + i * 0.043, 0), room._mat(Color(0.10, 0.22, 0.08)))
		var stem_angle: float = i * 2.399
		stem.rotation = Vector3(0.25, -stem_angle, 0.12)
		var leaf := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 16
		sphere.rings = 8
		leaf.mesh = sphere
		leaf.scale = Vector3(0.15, 0.035, 0.43)
		var angle: float = i * 2.399
		leaf.position = Vector3(cos(angle) * 0.18, -0.25 + i * 0.043, sin(angle) * 0.18)
		leaf.rotation = Vector3(0.45, -angle, 0.25)
		leaf.material_override = room._mat(Color(0.10 + (i % 3) * 0.025, 0.25 + (i % 4) * 0.025, 0.09))
		plant.add_child(leaf)
	# Three slightly different shelf thicknesses make the bookcase read as a
	# built cabinet rather than a single brown volume.
	var bookcase: Node3D = room.get_node("Bookcase")
	for shelf_index in range(3):
		_add_detail_box(bookcase, "Shelf_%d" % shelf_index, Vector3(0.68, 0.045, 0.34), Vector3(0, -0.72 + shelf_index * 0.70, 0), room._wood_mat(Color(0.55, 0.34, 0.19)))
	for book_index in range(6):
		var book := room.get_node_or_null("BedroomBook_%d" % book_index) as Node3D
		if book == null:
			continue
		_add_detail_box(book, "Binding", Vector3(0.025, 0.43, 0.30), Vector3(-0.075, 0, 0.015), room._mat(Color(0.78, 0.66, 0.38)))
	# Pleats give the curtains depth without altering their collision footprint.
	for id in ["CurtainLeft", "CurtainRight"]:
		var curtain: Node3D = room.get_node(id)
		curtain.get_node("Mesh").hide()
		var rod := _add_detail_cylinder(curtain, "CurtainRod", 0.035, 0.62, Vector3(0, 0.88, 0), room._mat(Color(0.32, 0.26, 0.18)))
		# CylinderMesh is vertical by default; a curtain rod must run across the
		# panel instead of appearing as a standing pole through the window.
		rod.rotation.z = PI / 2.0
		_add_detail_box(curtain, "CurtainHeader", Vector3(0.46, 0.10, 0.08), Vector3(0, 0.77, 0), room._fabric_mat(Color(0.20, 0.27, 0.36)))
		for i in range(10):
			room._add_door_frame_piece(curtain, "Pleat", Vector3(0.052, 1.65, 0.06), Vector3(-0.22 + i * 0.048, 0, sin(i * 1.8) * 0.025), room._mat(Color(0.25, 0.32, 0.42)))
	# Complete the two panels with one continuous rail derived from the actual
	# window glass. The original per-panel rods made the curtains read as two
	# floating poles when the window was moved with the escape-window clue.
	var window_bounds: AABB = room._find_anchor_bounds("WindowGlass")
	if window_bounds.has_volume():
		var rail_material: Material = room._mat(Color(0.32, 0.26, 0.18))
		var rail_position := Vector3(window_bounds.get_center().x, window_bounds.end.y + 0.22, window_bounds.end.z + 0.035)
		room._add_door_frame_piece(room, "BedroomCurtainRail", Vector3(window_bounds.size.x + 0.32, 0.055, 0.055), rail_position, rail_material)
		_add_detail_sphere(room, "BedroomCurtainFinialLeft", 0.055, rail_position + Vector3(-(window_bounds.size.x + 0.32) * 0.5, 0, 0), rail_material)
		_add_detail_sphere(room, "BedroomCurtainFinialRight", 0.055, rail_position + Vector3((window_bounds.size.x + 0.32) * 0.5, 0, 0), rail_material)


static func _add_detail_box(parent: Node3D, node_name: String, size: Vector3, local_pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var minimum := minf(size.x, minf(size.y, size.z))
	mesh.mesh = rounded(size, minf(0.025, minimum * 0.24)) if minimum >= 0.035 else _plain_box(size)
	mesh.position = local_pos
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh


static func _add_detail_sphere(parent: Node3D, node_name: String, radius: float, local_pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var sphere := SphereMesh.new()
	sphere_radius(sphere, radius)
	mesh.mesh = sphere
	mesh.position = local_pos
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh


static func sphere_radius(sphere: SphereMesh, radius: float) -> void:
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8


static func _plain_box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _add_detail_cylinder(parent: Node3D, node_name: String, radius: float, height: float, local_pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	mesh.mesh = cylinder
	mesh.position = local_pos
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh


static func _add_box_collision(parent: Node3D, node_name: String, size: Vector3, local_pos: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	collision.name = node_name
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = local_pos
	parent.add_child(collision)
	return collision

static func rounded(size: Vector3, radius: float) -> ArrayMesh:
	var base := BoxMesh.new()
	base.size = size
	base.subdivide_width = 10
	base.subdivide_height = 10
	base.subdivide_depth = 10
	var arrays := base.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var r := minf(radius, minf(size.x, minf(size.y, size.z)) * 0.45)
	var core := size * 0.5 - Vector3.ONE * r
	for i in range(vertices.size()):
		var v := vertices[i]
		var nearest := Vector3(clampf(v.x, -core.x, core.x), clampf(v.y, -core.y, core.y), clampf(v.z, -core.z, core.z))
		normals[i] = (v - nearest).normalized()
		vertices[i] = nearest + normals[i] * r
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
