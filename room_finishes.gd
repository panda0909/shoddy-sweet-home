extends RefCounted

static func build(room: Node3D) -> void:
	for tile in [false, true]:
		var shader := Shader.new()
		shader.code = """shader_type spatial;
uniform bool tile = false;
varying vec3 p;
void vertex(){p = VERTEX;}
void fragment(){
	vec2 uv = p.xz;
	vec2 cell = tile ? uv / 0.65 : uv / vec2(1.6, 0.22);
	if(!tile){cell.x += mod(floor(cell.y), 2.0) * 0.5;}
	vec2 edge = min(fract(cell), 1.0-fract(cell));
	vec2 aa = max(fwidth(cell), vec2(0.001));
	vec2 seams = 1.0 - smoothstep(vec2(0.003), vec2(0.003) + aa, edge);
	float joint = max(seams.x, seams.y);
	float grain = tile ? 0.0 : sin(p.z * 35.0 + sin(p.x * 2.0) * 1.5) * 0.008;
	float variation = fract(sin(dot(floor(cell), vec2(12.9898,78.233))) * 43758.5453);
	vec3 base = tile ? vec3(0.49,0.52,0.49) : vec3(0.43,0.32,0.21);
	base *= 0.94 + variation * 0.12;
	ALBEDO = mix(base + grain, base * 0.78, joint);
	ROUGHNESS = tile ? 0.55 : 0.78;
}"""
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("tile", tile)
		if tile:
			room._add_box("BathFinish", Vector3(9.7, 0.012, 5.7), Vector3(5, 0.009, -3), mat, false)
		else:
			room.get_node("Floor/Mesh").material_override = mat
	# Flush skirting along exterior walls only; leave the entrance gap clear.
	for x in [-9.83, 9.83]:
		room._add_box("SideSkirting", Vector3(0.05, 0.10, 11.6), Vector3(x, 0.055, 0), room._mat(Color(0.67,0.63,0.54)), false)
	room._add_box("BackSkirting", Vector3(19.6,0.10,0.05), Vector3(0,0.055,-5.83), room._mat(Color(0.67,0.63,0.54)), false)
	# Fine matte plaster breaks up flat grey walls without noisy bitmap tiling.
	var plaster := Shader.new()
	plaster.code = """shader_type spatial;
varying vec3 p;
void vertex(){p = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float fade = 1.0-smoothstep(0.004,0.02,length(fwidth(p)));
 float n = sin(p.x*117.0+p.z*83.0)*sin(p.y*131.0)*fade;
 ALBEDO = vec3(0.70,0.67,0.60) + n*0.006;
 ROUGHNESS = 0.92;
}"""
	var paint := ShaderMaterial.new()
	paint.shader = plaster
	for node in room.get_children():
		if "Wall" in node.name or str(node.name).begins_with("Divider"):
			var surface := node.get_node_or_null("Mesh") as MeshInstance3D
			if surface:
				surface.material_override = paint
	# Replace the imported blown-out window card with a restrained frosted pane.
	var pane := room.find_child("184_diffuse_00", true, false) as MeshInstance3D
	if pane:
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.48, 0.65, 0.70)
		glass.roughness = 0.30
		glass.emission_enabled = true
		glass.emission = Color(0.15, 0.21, 0.23)
		glass.emission_energy_multiplier = 0.35
		pane.material_override = glass
		var bounds: AABB = pane.global_transform * pane.get_aabb()
		var center := bounds.get_center()
		var trim = room._mat(Color(0.73, 0.71, 0.64))
		for x in [bounds.position.x, center.x, bounds.end.x]:
			room._add_box("LivingWindowMullion", Vector3(0.045, bounds.size.y + 0.08, 0.065), Vector3(x, center.y, center.z - 0.04), trim, false)
		for y in [bounds.position.y, bounds.end.y]:
			room._add_box("LivingWindowRail", Vector3(bounds.size.x + 0.08, 0.045, 0.065), Vector3(center.x, y, center.z - 0.04), trim, false)
