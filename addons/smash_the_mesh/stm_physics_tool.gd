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

const stm_eps = 0.001

#---------------------------------------------------------------------------------------------------
# PRIVATE VARIABLES
#---------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------------------------
# PUBLIC METHODS
#---------------------------------------------------------------------------------------------------

static func gen_rigid_body(mesh_or_instance, from: STMInstance3D, owner: Node3D = null) -> RigidBody3D:
	var rb = RigidBody3D.new()
	var mesh_node: MeshInstance3D
	var shape_node = CollisionShape3D.new()
	
	if mesh_or_instance is Mesh:
		mesh_node = MeshInstance3D.new()
		mesh_node.mesh = mesh_or_instance
	elif mesh_or_instance is MeshInstance3D:
		mesh_node = mesh_or_instance
	else:
		return null
	
	rb.add_child(shape_node)
	shape_node.add_child(mesh_node)
	
	update_physics(rb, from, true)
	
	if !(shape_node.shape is ConvexPolygonShape3D):
		shape_node.position = mesh_node.get_aabb().get_center()
		mesh_node.transform = shape_node.transform.inverse()
	
	if owner:
		owner.add_child(rb)
		mesh_node.owner = owner
		shape_node.owner = owner
		rb.owner = owner
		
	return rb

static func gen_rigid_bodies(chunks: Array, from: STMInstance3D) -> Node3D:
	var parent = Node3D.new()
	parent.name = "STMChunks"

	for e in chunks:
		gen_rigid_body(e, from, parent)

	return parent


static func update_physics(rb: RigidBody3D, from: STMInstance3D, update_shape: bool):
	var shape_node = rb.get_child(0) as CollisionShape3D
	var mesh_node = shape_node.get_child(0) as MeshInstance3D	
	assert(shape_node and mesh_node)
	
	var c_bbox = mesh_node.mesh.get_aabb()
	var c_size = c_bbox.size
	
	if from:
		var c_volume = c_size.x * c_size.y * c_size.z
		rb.mass = max(0.1, from.phys_total_mass * c_volume / from.stm_phys_volume)
		rb.physics_material_override = from.phys_material
		
		rb.collision_layer = from.phys_collision_layer
		rb.collision_mask = from.phys_mask_layer
		rb.collision_priority = from.phys_collision_priority

	if !update_shape: return
	
	var shape: Shape3D
	match(clamp(from.phys_shape, 0, 4)):
		0: # SPHERE
			shape = SphereShape3D.new()
			shape.radius = (c_size.x + c_size.y + c_size.z) / 3.0 / 2.0 
			
		1: # BOX
			shape = BoxShape3D.new()
			shape.size = c_size
			
		2: # CAPSULE
			shape = CapsuleShape3D.new()
			var h_idx = 0
			for i in range(1,3):
				if c_size[i] > c_size[h_idx]:
					h_idx = i
			shape.radius = max(c_size[(h_idx+1)%3],c_size[(h_idx+2)%3]) / 2.0
			shape.height = c_size[h_idx]
			stm_align_node_to_axis(shape_node, h_idx)
			
		3: # CYLINDER
			shape = CylinderShape3D.new()
			var h_idx = 0
			for i in range(1,3):
				if c_size[i] > c_size[h_idx]:
					h_idx = i
			shape.radius = max(c_size[(h_idx+1)%3],c_size[(h_idx+2)%3]) / 2.0
			shape.height = c_size[h_idx]
			stm_align_node_to_axis(shape_node, h_idx)
			
		4: # CONVEX MESH
			shape = stm_create_convex_shape(mesh_node)
			
	shape_node.shape = shape

#---------------------------------------------------------------------------------------------------
# PRIVATE METHODS
#---------------------------------------------------------------------------------------------------

static func stm_create_convex_shape(mesh_instance: MeshInstance3D) -> ConvexPolygonShape3D:
	mesh_instance.create_convex_collision(true, true)
	var static_obj = mesh_instance.get_child(0) as StaticBody3D
	assert(static_obj)
	var obj_collision_shape = static_obj.get_child(0) as CollisionShape3D
	assert(obj_collision_shape)
	var convex_shape = obj_collision_shape.shape
	mesh_instance.remove_child(static_obj)
	static_obj.free()
	return convex_shape

static func stm_align_node(node: Node3D, direction: Vector3):
	var angle_to = Vector3.UP.angle_to(direction)
	var pivot = Vector3.UP.cross(direction).normalized()
	node.transform = node.transform.rotated_local(pivot, angle_to)

static func stm_align_node_to_axis(node: Node3D, axis_idx: int):
	if axis_idx == 1: return # already aligned
	var direction = Vector3.ZERO
	direction[axis_idx] = 1.0
	stm_align_node(node, direction)
	
