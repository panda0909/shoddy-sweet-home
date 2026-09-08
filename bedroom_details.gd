extends RefCounted

static func apply(room: Node3D) -> void:
	var timber := Shader.new()
	timber.code = """shader_type spatial;
uniform vec4 tint : source_color = vec4(0.38, 0.22, 0.12, 1.0);
varying vec3 local_pos;
void vertex(){ local_pos = VERTEX; }
void fragment(){
	float grain = sin(local_pos.x * 140.0 + sin(local_pos.y * 4.0 + local_pos.z * 3.0) * 6.0);
	float fine = sin(local_pos.x * 410.0 + local_pos.z * 12.0);
	ALBEDO = tint.rgb * (0.87 + 0.08 * grain + 0.035 * fine);
	ROUGHNESS = 0.66;
}"""
	for id in ["BedBase", "BedHeadboard", "Closet", "ClosetDoorLeft", "ClosetDoorRight", "DeskTop", "Bookcase", "BedsideTable_-8.25", "BedsideTable_-4.15"]:
		var part := room.get_node_or_null(id)
		if part == null:
			continue
		var mesh: MeshInstance3D = part.get_node("Mesh")
		var old: StandardMaterial3D = mesh.material_override
		var material := ShaderMaterial.new()
		material.shader = timber
		material.set_shader_parameter("tint", old.albedo_color)
		mesh.material_override = material
		if mesh.mesh is BoxMesh:
			mesh.mesh = rounded(mesh.mesh.size, 0.025)
	for id in ["Mattress", "Duvet", "PillowLeft", "PillowRight", "BedThrow", "DeskChairBack"]:
		var mesh: MeshInstance3D = room.get_node(id).get_node("Mesh")
		mesh.mesh = rounded(mesh.mesh.size, 0.07 if "Pillow" in id else 0.035)
	# Replace the solid desk front with four legs and a modesty panel.
	var desk: Node3D = room.get_node("Desk")
	desk.get_node("Mesh").hide()
	desk.get_node("CollisionShape3D").disabled = true
	for x in [-1.05, 1.05]:
		for z in [-0.27, 0.27]:
			room._add_door_frame_piece(desk, "Leg", Vector3(0.065, 0.85, 0.065), Vector3(x, 0, z), room._mat(Color(0.15, 0.13, 0.10)))
	room._add_door_frame_piece(desk, "BackPanel", Vector3(2.2, 0.28, 0.04), Vector3(0, 0.20, -0.31), room._mat(Color(0.3, 0.19, 0.11)))
	for part in desk.get_children():
		if part is MeshInstance3D and part.visible:
			part.create_trimesh_collision()
	room.get_node("DeskTop/Mesh").create_trimesh_collision()
	# Replace the cylindrical foliage with individual curved leaves.
	var plant: Node3D = room.get_node("BedroomPlant")
	plant.get_node("Mesh").hide()
	for i in range(16):
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
	# Pleats give the curtains depth without altering their collision footprint.
	for id in ["CurtainLeft", "CurtainRight"]:
		var curtain: Node3D = room.get_node(id)
		curtain.get_node("Mesh").hide()
		for i in range(10):
			room._add_door_frame_piece(curtain, "Pleat", Vector3(0.052, 1.65, 0.06), Vector3(-0.22 + i * 0.048, 0, sin(i * 1.8) * 0.025), room._mat(Color(0.25, 0.32, 0.42)))

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
