# Copyright (C) 2024 Claudio Z. (cloudofoz)
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#---------------------------------------------------------------------------------------------------
# CONSTANTS
#---------------------------------------------------------------------------------------------------

#const stm_eps = 0.001

#---------------------------------------------------------------------------------------------------
# PRIVATE VARIABLES
#---------------------------------------------------------------------------------------------------

var stm_parent_node: Node3D
var stm_csg_source_node = CSGMesh3D.new()
var stm_csg_chunk_node  = CSGMesh3D.new()
var stm_mdt = MeshDataTool.new()
var stm_st = SurfaceTool.new()

#---------------------------------------------------------------------------------------------------
# CONSTRUCTOR
#---------------------------------------------------------------------------------------------------

func _init(parent_node: Node3D):
	stm_parent_node = parent_node
	stm_csg_source_node.add_child(stm_csg_chunk_node)

#---------------------------------------------------------------------------------------------------
# PUBLIC METHODS
#---------------------------------------------------------------------------------------------------
	
func begin(source_mesh: Mesh):
	
	if !(source_mesh is ArrayMesh):
		stm_st.create_from(source_mesh,0)
		source_mesh = stm_st.commit()
	
	stm_csg_source_node.mesh = source_mesh
	#stm_parent_node.add_child(stm_csg_source_node, false, Node.INTERNAL_MODE_BACK )
	#stm_csg_source_node.visible = true

func end():
	stm_csg_chunk_node.queue_free()
	stm_csg_source_node.queue_free()
	#stm_parent_node.remove_child(stm_csg_source_node)
	#stm_csg_source_node.visible = false

func fracture(chunk_mesh: Mesh, chunks_count: Vector3i, opt: Dictionary):
	
	if !chunk_mesh: return	
	stm_csg_chunk_node.mesh = ArrayMesh.new()
	var chunk_data: Array = stm_fracture_process_chunk(chunk_mesh)	
	var chunks = Array()	
	var src_bbox = stm_csg_source_node.mesh.get_aabb()	
	var chunk_size = src_bbox.size / Vector3(chunks_count.x, chunks_count.y, chunks_count.z)
	var chunk_position: Vector3 = Vector3.ZERO	
	#var chunk_center = src_bbox.position
	var chunk_center = src_bbox.position + chunk_mesh.get_aabb().size * 0.5
	var count = chunks_count.x * chunks_count.y * chunks_count.z
	var idx   = 1
	
	# 1.0 : chunk_size = chunk_aabb : X
	chunk_data.push_back(chunk_size) # 3 # * chunk_mesh.get_aabb().size
	chunk_data.push_back(opt.noise) # 4
	chunk_data.push_back(opt.optimize) # 5
	chunk_data.push_back(opt.vertices_threshold) # 6
		
	# chunk_data := [0: chunk_mesh, 1: chunk_unique_vertices, 2: chunk_idx_map, 3: chunk_size, 4: chunk_noise, 5: optimize_flag, 6: chunk_vertices_threshold ]
	
	var z_range = range(chunks_count.z)
	var y_range = range(chunks_count.y)
	var x_range = range(chunks_count.x)
	
	var shuffle: bool = opt.random_sampling
	
	if shuffle: z_range.shuffle()
	for z in z_range:
		chunk_position.z = chunk_center.z + z * chunk_size.z
		if shuffle: y_range.shuffle()
		for y in y_range:
			chunk_position.y = chunk_center.y + y * chunk_size.y
			if shuffle: x_range.shuffle()
			for x in x_range:
				chunk_position.x = chunk_center.x + x * chunk_size.x
				print("\t\t# computing chunk ", idx, "/", count)
				idx += 1
				var chunk = stm_fracture_eat_a_chunk(chunk_position, chunk_data)
				if chunk: chunks.push_back( chunk )
				
	return chunks

#experimental
func cut(cutter_mesh: Mesh, transform: Transform3D = Transform3D.IDENTITY, optimize = false) -> Array:

	stm_csg_source_node.transform = stm_parent_node.global_transform
	stm_csg_chunk_node.transform =  stm_parent_node.global_transform.affine_inverse() * transform 
	stm_csg_chunk_node.mesh = cutter_mesh

	stm_csg_chunk_node.operation = CSGShape3D.OPERATION_INTERSECTION
	var first_chunk: Mesh = stm_grab_result_data()
	
	if first_chunk.get_surface_count() < 1: return []
	
	stm_csg_chunk_node.operation = CSGShape3D.OPERATION_SUBTRACTION
	var second_chunk: Mesh = stm_grab_result_data()
	
	if second_chunk.get_surface_count() < 1: return []
	
	if optimize:
		first_chunk = stm_optimize_mesh(first_chunk)
		second_chunk = stm_optimize_mesh(second_chunk)
	
	return [first_chunk, second_chunk]

#---------------------------------------------------------------------------------------------------
# PRIVATE METHODS - FRACTURE MODULE
#---------------------------------------------------------------------------------------------------

# Returns: [0: chunk_mesh, 1: vertices, 2: index map]
func stm_fracture_process_chunk(chunk_mesh: Mesh):
	
	if chunk_mesh.get_surface_count() > 1:
		push_warning("Fracture Brush: should have one single surface")
	
	var vertices  = PackedVector3Array()
	var idx_map   = []
	
	var src_verts = chunk_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	
	for u_idx in range(src_verts.size()):
		var u = src_verts[u_idx]
		var found = false
		for i in range(vertices.size()):
			if u.is_equal_approx(vertices[i]):
				idx_map[i].push_back(u_idx)
				found = true
				break
		if !found:
			vertices.push_back(u)
			idx_map.push_back([u_idx])
	
	return [chunk_mesh, vertices, idx_map]

func stm_fracture_eat_a_chunk(where: Vector3, chunk_data: Array) -> Mesh:
	
	# chunk_data := [0: chunk_mesh, 1: chunk_unique_vertices, 2: chunk_idx_map, 3: chunk_size, 4: chunk_noise, 5: optimize_flag, 6: chunk_vertices_threshold ]
	stm_fracture_gen_chunk(chunk_data)
	
	stm_csg_chunk_node.position = where

	stm_csg_chunk_node.operation = CSGShape3D.OPERATION_INTERSECTION
	var eaten_chunk: Mesh =  stm_grab_result_data()
	
	if eaten_chunk.get_surface_count() < 1 || eaten_chunk.surface_get_array_len(0) < chunk_data[6]:
		return null
	
	if chunk_data[5]: # optimize
		eaten_chunk = stm_optimize_mesh(eaten_chunk)
	
	stm_csg_chunk_node.operation = CSGShape3D.OPERATION_SUBTRACTION
	stm_csg_source_node.mesh = stm_grab_result_data()
	
	return eaten_chunk

func stm_fracture_gen_chunk(chunk_data: Array):
	# chunk_data := [0: chunk_mesh, 1: chunk_unique_vertices, 2: chunk_idx_map, 3: chunk_size, 4: chunk_noise, 5: optimize_flag, 6: chunk_vertices_threshold ]
	stm_mdt.clear()
	stm_mdt.create_from_surface(chunk_data[0], 0)
	var vertices: PackedVector3Array = chunk_data[1]
	var idx_map: Array  = chunk_data[2]
	for u_idx in range(vertices.size()):
		var u = vertices[u_idx]
		u += u.normalized() * chunk_data[3] * (Vector3.ONE + stm_rnd_vector(Vector3.ZERO, chunk_data[4]))
		for v_idx in idx_map[u_idx]:
			stm_mdt.set_vertex(v_idx, u)
	var ret_mesh = stm_csg_chunk_node.mesh as ArrayMesh
	ret_mesh.clear_surfaces()
	stm_mdt.commit_to_surface(ret_mesh)
	
#---------------------------------------------------------------------------------------------------
# PRIVATE METHODS - COMMON MODULE
#---------------------------------------------------------------------------------------------------

func stm_rnd_vector_uniform(minv: float, maxv: float):
	return Vector3(randf_range(minv, maxv),randf_range(minv, maxv),randf_range(minv, maxv))
	
func stm_rnd_vector(minv: Vector3, maxv: Vector3):
	return Vector3(randf_range(minv.x, maxv.x), randf_range(minv.y, maxv.y), randf_range(minv.z, maxv.z))

func stm_optimize_mesh(mesh: Mesh) -> Mesh:
	var optimized_mesh = ArrayMesh.new()
		
	# The mesh could be optimized further but I changed my code to just use SurfaceTool methods, 
	# it's faster since it's implemented in C++
	for i in range(mesh.get_surface_count()):
		print("\t\t\t| Mesh optimization...")
		
		stm_st.create_from(mesh, i)
		stm_st.index()
		stm_st.generate_normals()
		stm_st.generate_tangents()
		stm_st.commit(optimized_mesh)
		
		var src_vcount = mesh.surface_get_array_len(i)
		var opt_vcount = optimized_mesh.surface_get_array_len(i)
		print("\t\t\t- surface #", i, ": original(", src_vcount, ") | optimized(", opt_vcount,") vertices.")
	
	return optimized_mesh

func stm_grab_result_data() -> Mesh:
	# https://github.com/godotengine/godot/issues/72814
	stm_csg_source_node._update_shape()
	var mesh_arrays = stm_csg_source_node.get_meshes()
	if(mesh_arrays.size() != 2):
		push_warning("stm_grab_result_mesh(): can't obtain the result mesh.")
		return null
	return mesh_arrays[1]
