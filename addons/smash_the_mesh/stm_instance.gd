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

@tool
extends MeshInstance3D

## This class can automatically break a mesh and then adds physics to the generated chunks.
## This can be done at loading time (chunk_opt_preload = true)
## or when the method 'smash_the_mesh()' is called.
## Useful for very light geometry that doesn't require too much computation. 
## If performance is an issue it's really advisable to use STMCachedInstance3D.
class_name STMInstance3D

#---------------------------------------------------------------------------------------------------
# CONSTANTS
#---------------------------------------------------------------------------------------------------

const StandardBrush = preload("brushes/stm_brush_standard.mesh") 
const FractureTool = preload("stm_fracture_tool.gd") 
const PhysicsTool = preload("stm_physics_tool.gd") 

# This is an hardcoded limit for the voxel size along each axis.
# Please be careful when you change this limit because the computation times can grow quite fast:
# With chunk_safe_limit = 6 you could have a maximum of 6 * 6 * 6 = 216 chunks for each mesh
const chunk_safe_limit = 6

#---------------------------------------------------------------------------------------------------
# PUBLIC VARIABLES
#---------------------------------------------------------------------------------------------------

## The original (source) mesh that you want to break
@export var original_mesh: Mesh:
	set(value):
		if original_mesh == value: return
		original_mesh = value
		mesh = value
		if original_mesh: 
			stm_update_mesh_volume()
			on_fracture_param_changed.emit()

@export_group("Chunks Generation", "chunk_")

## This mesh is used as an intersection volume for each voxel to create the chunks. 
## Its shape can change the result quite a lot and
## also can create unwanted artifacts, if the shape is not well chosen. 
## If you want to create your own brush meshes then you should keep it centered on the origin of the system with
## a size not too distant from the unit: 1x1x1 size. If you change these conventions too much it could produce 
## unpredictable results. 
## A set of experimental brush meshes can be found on the sub-folder "brushes".
## The "wood" brush, for example, behaved particulary well to simulate the typical breaking of some wood material
@export var chunk_brush: Mesh = StandardBrush:
	set(value):
		if chunk_brush == value: return
		chunk_brush = value
		on_fracture_param_changed.emit()

## This is the material that will be used for the inner parts of chunks. 
@export var chunk_inner_material: StandardMaterial3D = StandardMaterial3D.new()

## As a 3D voxel grid this is can also represent the maximum numbers of chunks that will be created for each axis.
## The maximum number of possible created chunks will be chunk_count.x * chunk_count.y * chunk_count.z.
## An example: If you have a tall object (Y axis) and thin (X, Z) then you can try to increase just the count on the Y,
## while keeping the other two values at the minimum. Choosing well this numbers is important to obtain the desired effect.
@export var chunk_count: Vector3i = Vector3i(2,2,2):
	set(value):
		if chunk_count == value: return
		value.x = clamp(value.x, 1, chunk_safe_limit)
		value.y = clamp(value.y, 1, chunk_safe_limit)
		value.z = clamp(value.z, 1, chunk_safe_limit)
		chunk_count = value
		on_fracture_param_changed.emit()

## This threshold represents the minimum number of vertices necessary for a chunk to not be discarded. Choosing well this
## value is important to avoid meaningless chunks. Nevertheless big values can reduce the amount of chunks that are created.
## Tip: Keep a look at the console when the chunks are generated to see the amount of vertices for each chunk. Then
## you can set this value accordingly.
@export var chunk_vertices_threshold: int = 32:
	set(value):
		if(chunk_vertices_threshold == value): return
		chunk_vertices_threshold = value
		on_fracture_param_changed.emit()

## When this option is set to false the chunks will be removed from the mesh starting from the minimum position of the bounding box.
## You can try to turn off this flag if you need a bit more regular results.
@export var chunk_random_sampling: bool = true:
	set(value):
		if chunk_random_sampling == value: return
		chunk_random_sampling = value
		on_fracture_param_changed.emit()

## The amount of noise that will be applied to the brush geometry before the computations. It can help to create some
## interesting irregularities but it can create also a lot of artifacts. 
## It a factor that depends on the size of the mesh. If you see too much artifacts try to set the noise factor = 0
@export var chunk_noise_factor: Vector3 = Vector3.ZERO:
	set(value):
		if chunk_noise_factor.is_equal_approx(value): return
		value.x = clamp(value.x, 0, 1.0)
		value.y = clamp(value.y, 0, 1.0)
		value.z = clamp(value.z, 0, 1.0)
		chunk_noise_factor = value
		on_fracture_param_changed.emit()

@export_subgroup("Options", "chunk_opt_")

## If this parameter is set to true then any possible chunk computation for this istance will be performed at loading time.
## When it's turned off the chunks will be calculated only when you call the method smash_the_mesh()
@export var chunk_opt_preload: bool = true

## If this option is set to true, smash_the_mesh() will be called since the beginning 
@export
var chunk_opt_already_smashed = false

@export_group("Chunks Physics", "phys_")

## The collision shape that it will be used for each chunks
## If you need a particular precision with the collisions you can use ConvexShape, but there could be some performance loss
## when there are a lot of chunks
@export_enum("Sphere: 0", "Box: 1", "Capsule: 2", "Cylinder: 3", "ConvexShape: 4" )
var phys_shape = 1

## This value represent the mass for the whole geometry. Each chunk will have a fraciton of this mass based on its volume/size.
@export_range(0.01, 10, 0.1, "or_greater")
var phys_total_mass = 1.0

## This is the physical material that will be applied to each chunk
@export
var phys_material: PhysicsMaterial = null

## These are the physics layers that the chunk will check for collisions
@export_flags_3d_physics
var phys_collision_layer: int = 1

## These are the physics layers where the chunk will stay when another collider check for collisions
@export_flags_3d_physics
var phys_mask_layer: int = 1 # 1 << 2

## Represents how much a collider will be let to penetrate into another 
@export_range(0.0, 1.0, 0.05, "or_greater")
var phys_collision_priority = 1.0

#---------------------------------------------------------------------------------------------------
# SIGNALS
#---------------------------------------------------------------------------------------------------

signal on_fracture_param_changed

#---------------------------------------------------------------------------------------------------
# PRIVATE VARIABLES
#---------------------------------------------------------------------------------------------------

# This node will hold all the rigid bodies chunks after you call "smash_the_mesh()" otherwise
# it will be null. If you want to iterate over the rigid-bodies it's adisable to call
# chunks_iterate() instead with a callback.
# Neverthelss the structure of a chunk is the following:
# rb_parent(the root for all) > RigidBody3D(the first node of each chunk) > CollisionShape3D > MeshInstance3D
# This is the hiearchical structure of a chunk and each node has exactly one child.
var rb_parent: Node3D

# Used internally to keep track of the total volume of this mesh based on the bounding box
var stm_phys_volume: float = 1.0

# This value represents when smash_the_mesh() has been called (time in ms from the start of the program)
# It will be 0 before. It can be used to remove the chunks after some time.
# Time.get_ticks_msec() - stm_alive_time = The time passed from the spawning of the chunks
var stm_alive_time: float = 0

#---------------------------------------------------------------------------------------------------
# PUBLIC VIRTUAL METHODS
#---------------------------------------------------------------------------------------------------

# Called when the node enters the scene tree for the first time.
func _ready():

	assert(!rb_parent)

	if Engine.is_editor_hint():
		return

	if chunk_opt_preload: 
		_stm_compute_fractures()

	if chunk_opt_already_smashed:
		smash_the_mesh()

# This virtual method is overridden by the CachedDestructibleMesh
# It's the code that starts the chunks computation
func _stm_compute_fractures():
	
	if(!mesh || !chunk_brush): return
	
	var fracture = FractureTool.new(self)
	
	print("* STM Add-on: Computing fractures for '", name, "'")
	print("   . Tool initializing...")
	
	fracture.begin(mesh)
	
	if chunk_inner_material:
		chunk_brush.surface_set_material(0, chunk_inner_material)
	
	# Fracture a mesh, it returns an array with all the chunk meshes
	var opt = { "noise": chunk_noise_factor, "vertices_threshold": chunk_vertices_threshold, "optimize": true, "random_sampling": chunk_random_sampling }
	var result = fracture.fracture(chunk_brush, chunk_count, opt)
	
	fracture.end()
	
	if !is_inside_tree(): return
	print("\t. Adding physics to the chunks...")
	
	# Add physics to the chunk. It accepts the chunk meshes as input and it return the root for all the phyisical chunks.
	rb_parent = PhysicsTool.gen_rigid_bodies(result, self)

	print("* Done.")

#---------------------------------------------------------------------------------------------------
# PUBLIC METHODS
#---------------------------------------------------------------------------------------------------

# This method will return true if this instance has been smashed
func is_smashed():
	return stm_alive_time > 0

# This method will hide the mesh and it will spawn the physical chunks on its place. 
# Chunks will not appear before you call this method
func smash_the_mesh():	
	if stm_alive_time > 0 or !is_inside_tree(): return	
	
	stm_alive_time = Time.get_ticks_msec()
	
	# Get the chunks (from cache or from computations)
	if !rb_parent: _stm_compute_fractures()
	
	self.visible = false
	
	# Chunks root is placed in the same spot of this istance
	rb_parent.global_transform = self.global_transform
	
	# RigidBody3D are the root of each chunk, but the documentation says you cannot scale the RigidBody.
	# So we apply the mesh scale of each chunk to the direct child (the collision shape) as if 
	# it was centered in the origin.
	# The initial transformation is stored. This is useful when you want
	# to revert the chunks at the initial position
	var global_scale_t = global_basis.get_scale()
	
	for rb in rb_parent.get_children():
		if rb.has_meta("stm_start_transform"):
			rb.transform = rb.get_meta("stm_start_transform")
		else:
			rb.set_meta("stm_start_transform", rb.transform)
			
		var cs = rb.get_child(0)
		if cs.has_meta("stm_start_transform"):
			cs.transform = cs.get_meta("stm_start_transform")
		else:
			cs.set_meta("stm_start_transform", cs.transform)
		cs.transform = cs.transform.translated_local(-cs.position).scaled_local(global_scale_t).translated_local(cs.position)

	# We put the chunks in the scene
	get_tree().root.add_child.call_deferred(rb_parent, false, Node.INTERNAL_MODE_BACK)
	
	# Experimental ( a bit hardcoded, probably it will be modified )
	# If the original mesh istance was already part of some physical simulation
	# then the chunk will inherit part of its linear and angular velocity.
	# This will search for the parent rigidbody as the immediate parent or the parent of the parent.
	# My convention is that a MeshInstance3D is child of a CollisionShape3D that is child of a RigidBody3D
	# but a mesh instance could directly be parented with a rigid body object. Other situations are not supported
	# by this code.
	var rb_ancestor = $"../.." as RigidBody3D
	if !rb_ancestor: rb_ancestor = $".." as RigidBody3D
	if rb_ancestor:
		for n in rb_parent.get_children():
			var rb = n as RigidBody3D
			if !rb: continue
			rb.linear_velocity += rb_ancestor.linear_velocity * 0.1
			rb.angular_velocity += rb_ancestor.angular_velocity * 0.1

# This is an helper method to automatically add a rigid body and a collision shape 
# this this instance. It will use the same physics settings of the chunks.
func add_physics_to_self():
	var rb_ancestor = $"../.." as RigidBody3D
	if !rb_ancestor: rb_ancestor = $".." as RigidBody3D	
	if rb_ancestor: return
	var rb = RigidBody3D.new()
	var cs = CollisionShape3D.new()	
	rb.position = position
	rb.rotation = rotation
	cs.scale = scale
	rb.add_child(cs)
	var prev_parent = self.get_parent()
	self.reparent(cs)
	PhysicsTool.update_physics(rb, self, true)
	prev_parent.add_child(rb)
	self.transform = Transform3D.IDENTITY

#---------------------------------------------------------------------------------------------------
# PUBLIC METHODS - INTERACT WITH THE CHUNKS
#---------------------------------------------------------------------------------------------------

# This method will iterate over all the chunks rigid-bodies
# It can be used to perform operations on the chunks of this istance. 
# For example you can apply a force to all the chunks 
# 	callback := func(rb: RigidBody3D, from: DestructableMesh)
# To obtain the CollisionShape3D of the chunk from the callback:
# 	var collision_shape = rb.get_child(0) as CollisionShape3D
# To obtain the MeshInstance3D of the chunk:
#	var mesh_instance = collision_shape.get_child(0) as MeshInstance3D
func chunks_iterate(callback: Callable):
	if !rb_parent: return
	for c in rb_parent.get_children():
		var rb = c as RigidBody3D
		if !rb: return
		callback.call(rb, self)

# This method will return the time elapsed since smash_the_mesh() was called
# It will return 0 otherwise
func chunks_get_elapsed_time() -> float:
	return Time.get_ticks_msec() - stm_alive_time if stm_alive_time > 0 else 0

# This method will update the elapsed time as if smash_the_mesh() has
# been just called. Useful when you want to restart some time based
# animation without having to restore the chunks at their original state
func chunks_restart_elapsed_time():
	stm_alive_time = Time.get_ticks_msec()

# This method will remove all the chunks of this mesh 
func chunks_kill():
	if !rb_parent: return
	get_tree().root.remove_child(rb_parent)
	rb_parent.queue_free()
	rb_parent = null

# This method will reset this instance as it was before calling smash_the_mesh()
func chunks_reset():
	if !rb_parent: return
	if is_equal_approx(stm_alive_time, 0): return
	get_tree().root.remove_child(rb_parent)
	stm_alive_time = 0
	self.visible = true

# This method can freeze / unfreeze the phisics simulation of the chunks
func chunks_freeze(enable: bool):
	if !rb_parent: return
	chunks_iterate(func(rb,_s): rb.freeze = enable)

# This method can revert the chunks to their start position
# weight: the amount of repair from 0 to 1
# You can call this method each frame with a low value of weight to
# create a backward animation to the original position
# Tip: Be sure to call chunks_freeze() before, to not mess with the physics
func chunks_repair(weight: float):
	if !rb_parent or !is_smashed(): return
	for rb in rb_parent.get_children():
		var origin_t = rb.get_meta("stm_start_transform", Transform3D.IDENTITY)
		rb.position = rb.position.lerp(origin_t.origin, weight)
		rb.rotation = rb.rotation.lerp(origin_t.basis.get_euler(), weight)

#---------------------------------------------------------------------------------------------------
# PRIVATE METHODS
#---------------------------------------------------------------------------------------------------

func stm_update_mesh_volume():
	if !mesh: return
	var src_size = get_aabb().size
	stm_phys_volume = src_size.x * src_size.y * src_size.z

##--------------------------------------------------------------------------------

# (!) This feature is very experimental, it could be expanded in the future versions.
# As for now I'm not documenting it, as it's incomplete.
func cut_the_mesh(cutter_mesh: ArrayMesh):
	if !mesh || !cutter_mesh: return
	
	var a = cutter_mesh.get_aabb()
	
	var b = get_aabb() * self.global_transform
	b.position = global_position

	if !a.intersects(b):
		return
	
	if chunk_inner_material:
		chunk_brush.surface_set_material(0, chunk_inner_material)
	
	var cutter = FractureTool.new(self)
	
	cutter.begin(mesh)

	var result = cutter.cut(cutter_mesh, Transform3D.IDENTITY, true)
	
	cutter.end()
	
	if !result || result.size() != 2: return
	
	rb_parent = PhysicsTool.gen_rigid_body(result[0], self)

	mesh = result[1]
