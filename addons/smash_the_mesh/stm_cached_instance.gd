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
extends STMInstance3D

## This class extends STMInstance3D adding a caching system that only perform computations
## when the data becomes invalid (for example you change the generation parameters).
## The cache is saved as a compressed scene in the disk. The default path is res://stm_cache/.
## It can be reused by multiple istances with the same geometry. Please be careful when there is
## a lot of geometry and many chunks because
## the size of the cache file will grow, so check the folder sometimes.
## To open a cache file you just need to double-click on it. You can check the result and even
## edit as you wish but keep the structure of the tree intact.
## Please remember that when you manually modify a cache file it will ivalidate it. So 
## be sure to set "cache_write = false" to ensure that your modifcations will not be overwritten
## the next time you run your program.
class_name STMCachedInstance3D

#---------------------------------------------------------------------------------------------------
# CONSTANTS
#---------------------------------------------------------------------------------------------------

# The default path name for the cached files
const stm_cache_folder = "stm_cache"

#---------------------------------------------------------------------------------------------------
# PUBLIC VARIABLES
#---------------------------------------------------------------------------------------------------

@export_group("Cache Options", "cache_")

## When this option is enabled the cache will be overwritten when the cache data become invalid.
## If you have many istances that use the same cache file it's advisable to keep only one istance with
## cache_write = true. In this way you can change the data for all the istances from a single place
## (the instance that has cache_write = true)
@export
var cache_write = true

## When this option is enabled the object will try to load the data from the cache file instead of computing
## it. If the cache isn't found then a computation will be performed (at loading time or when it's needed)
## If cache_write = true then the computed data will be saved in the disk and no more computations will be
## performed the next time. If cache_read = false the data will always be computed at run-time.
@export
var cache_read = true

## This is just an info box, that is not meant to be touched. It informs you wether this istance can read 
## the cache from the disk without losing time to recompute the data.
@export 
var cache_is_saved = false:
	set(value):
		if !Engine.is_editor_hint(): return
		if value == cache_is_saved: return
		if stm_no_cache_check:
			cache_is_saved = value
			return
		cache_is_saved = stm_check_cache()

## This string is the name of the file cache on the disk. If you want that multiple istances of the same
## object read from the same cache then they you have to specify the same cache_name for all.
## In this case it's advisable to turn off cache_write for all the istances except one, that you can use to modify the cache.
## If you want to be sure that this data will not be overwritten anymore then you can set cache_write = false for all the objects.
@export_file("*.scn")
var cache_name: String = str(get_instance_id()):
	set(value):
		if value == cache_name: return
		cache_name = value if !value.is_empty() else str(get_instance_id())
		stm_no_cache_check = true
		cache_is_saved = stm_on_cache_path_changed()
		stm_no_cache_check = false
		chunks_reset()

## When this option is true the collision shape of the chunks will be directly read from the cache without
## being recomputed. If you want to keep the chunk data from the cache but to use a different collision shape
## for the chunks then you can set cache_baked_shape = false
@export
var cache_baked_shape = true

## When this option is true all the physics data of the chunks will be directly read from the cache without
## being recomputed. If you want to keep the chunk data from the cache but to have diffrente physics
## settings then you can set cache_baked_physics = false
@export
var cache_baked_physics = false

#---------------------------------------------------------------------------------------------------
# PRIVATE PROPERTIES
#---------------------------------------------------------------------------------------------------

var stm_cache_path:
	get:
		return "res://" + stm_cache_folder + "/" + cache_name + ".scn"
		

#---------------------------------------------------------------------------------------------------
# PRIVATE VARIABLES
#---------------------------------------------------------------------------------------------------

# This manages the metadata written in the cache scene. It's used to check if the cache is still valid
# or need to be recomputed
# [[0: metadata_id: String,1: get: Callable,2: set: Callable,3: compare: Callable]]
var stm_cache_data = [  ["_stm_src_mesh", func(): return mesh.resource_path, func(v): mesh = ResourceLoader.load(v), func(a,b): return a == b],
						["_stm_chunk_brush", func(): return chunk_brush.resource_path, func(v): chunk_brush = ResourceLoader.load(v), func(a,b): return a == b],
						["_stm_chunk_count", func(): return chunk_count, func(v): chunk_count = v, func(a,b): return a == b],
						["_stm_chunk_noise_factor", func(): return chunk_noise_factor, func(v): chunk_noise_factor = v, func(a,b): return a.is_equal_approx(b)],
						["_stm_chunk_vertices_threshold", func(): return chunk_vertices_threshold, func(v): chunk_vertices_threshold = v, func(a,b): return a == b],
						["_stm_chunk_random_sampling", func(): return chunk_random_sampling, func(v): chunk_random_sampling = v, func(a,b): return is_equal_approx(a, b)]
					 ]

# Used internally to change chache_is_saved without performing any control
var stm_no_cache_check = false

#---------------------------------------------------------------------------------------------------
# PUBLIC METHODS
#---------------------------------------------------------------------------------------------------

func _ready():	
	on_fracture_param_changed.connect(stm_check_cache)
	
	var dir = DirAccess.open("res://")
	if !dir.dir_exists(stm_cache_folder):
		dir.make_dir(stm_cache_folder)
	
	if Engine.is_editor_hint():
		cache_is_saved = stm_check_cache()
	super._ready()

#---------------------------------------------------------------------------------------------------
# PRIVATE METHODS
#---------------------------------------------------------------------------------------------------

# Loads the data from the cache
func stm_load_cache() -> Node3D:
	if !cache_read: return null
	var path = stm_cache_path
	if !ResourceLoader.exists(path):
		return null
	var packed_scene = load(path) as PackedScene
	if !packed_scene:
		push_error("*STM: Can't load cache from '", path, "'")
		return null		
	if cache_write and !stm_check_cache(packed_scene):
		return null	
	var root = packed_scene.instantiate() as Node3D	
	if !cache_baked_physics:
		for rb in root.get_children():
			PhysicsTool.update_physics(rb, self, !cache_baked_shape)	
	return root

#---------------------------------------------------------------------------------------------------

# Check if a metadata entry has the same value of the linked option in this istance (see stm_cache_data[])
func stm_check_meta(obj, entry):
	return obj.has_meta(entry[0]) and entry[3].call(obj.get_meta(entry[0]), entry[1].call())

#---------------------------------------------------------------------------------------------------

# Load a metadata entry and updates the value of the linked option in this istance (see stm_cache_data[])
func stm_load_meta(obj, entry):
	if !obj.has_meta(entry[0]): return false
	entry[2].call(obj.get_meta(entry[0]))
	return true

#---------------------------------------------------------------------------------------------------

# Saves the cache into the disk
func stm_save_cache():	
	if !rb_parent || !cache_write: return	
	var scene = PackedScene.new()
	for entry in stm_cache_data:
		scene.set_meta(entry[0], entry[1].call())
	scene.pack(rb_parent)
	ResourceSaver.save(scene, stm_cache_path, ResourceSaver.FLAG_COMPRESS)
	cache_is_saved = true

#---------------------------------------------------------------------------------------------------

# Checks if the cache is still valid
func stm_check_cache(cache = null) -> bool:
	if !cache_read: return false
	if !cache:
		if cache_name.is_empty(): return false
		var path = stm_cache_path
		if path.is_empty(): return false
		if !ResourceLoader.exists(path): return false
		cache = load(path) as PackedScene
	if !cache: return false
	for entry in stm_cache_data:
		if !stm_check_meta(cache, entry): return false
	return true

#---------------------------------------------------------------------------------------------------

# Called when the name of the cache file is changed
func stm_on_cache_path_changed() -> bool:
	if !cache_read: return false
	if cache_name.is_empty(): return false
	var path = stm_cache_path
	if path.is_empty(): return false
	if !ResourceLoader.exists(path): return false
	var packed_scene = load(path) as PackedScene
	if !packed_scene: return false
	
	if cache_write: return true
	
	for entry in stm_cache_data:
		if !stm_load_meta(packed_scene, entry): return false
	
	cache_is_saved = true
	
	return true
	
#---------------------------------------------------------------------------------------------------
# PRIVATE VIRTUAL METHODS
#---------------------------------------------------------------------------------------------------

# This overrides the method from the parent class DestructilbeIstance
func _stm_compute_fractures():
	rb_parent = stm_load_cache()
	if rb_parent: return
	super._stm_compute_fractures()
	print("\t. Saving the cache to '", stm_cache_path, "'")
	stm_save_cache()	
	print("* Done.")
