![Version](https://img.shields.io/badge/Godot-v4.3-informational) ![License](https://img.shields.io/github/license/cloudofoz/godot-smashthemesh?version=1.0.1)

## Introduction

**Smash The Mesh (STM)** is a Godot add-on that allows you to **break a 3D mesh** into **multiple pieces** and then **apply physics** to each fragment. It also offers the ability to **save the results to disk (cache)** and load them quickly, thereby avoiding the need for repetitive, often time-consuming computations.

<p align="center"> 
  <img src="media/stm_title.png" width="400"/>   
</p>

#### *Note*: This is a *BETA* version and is still under development. It should be tested thoroughly to assess its suitability for your needs.

<br>

### Under the Hood

STM uses Godot's **Constructive Solid Geometry (CSG)** system to create fragments from a mesh.

<br>

## STM Nodes

- <h3> <img src="addons/smash_the_mesh/stm_icon.svg" width="20"/> STMInstance3D</h3>

  This class is ideal for handling lightweight geometry (with few chunks) that doesn't require intensive computation. It can automatically break a mesh and apply physics to the resulting chunks. This can be done either at loading time (with `preloading = true`) or when the `smash_the_mesh()` method is called. For performance-critical scenarios, it is highly recommended to use `STMCachedInstance3D`.

- <h3> <img src="addons/smash_the_mesh/stm_cached_icon.svg" width="20"/> STMCachedInstance3D</h3>

  This class extends `STMInstance3D` by adding a caching system that only recomputes data when it becomes invalid (for example, if you change the generation parameters). The cache is stored as a compressed scene on the disk, with the default path set to `res://stm_cache/`. This cache can be reused across multiple instances with the same geometry. However, be cautious when dealing with a lot of geometry and many fragments, as the size of the cache file will increase. It’s a good idea to periodically check the folder.

  To open a cache file, simply double-click on it. You can inspect the result and even make edits as needed, but it's important to maintain the tree structure. Note that manually modifying a cache file will invalidate it, so be sure to set `can_write = false` to ensure your changes are not overwritten the next time the program runs.

## API Documentation

### `is_smashed() -> bool`
**Description:**  
Returns `true` if the current instance has been smashed, otherwise returns `false`.

### `smash_the_mesh()`
**Description:**  
Hides the mesh of the current instance and spawns the physical chunks in its place.  
Note: The chunks will not appear until this method is called.

### `add_physics_to_self()`
**Description:**  
Automatically adds a `RigidBody3D` and a `CollisionShape3D` to the current instance, using the same physics settings as the chunks.

### `chunks_iterate(callback: Callable)`
**Description:**  
Iterates over all the chunks' `RigidBody3D` instances, allowing you to perform operations on the chunks of this instance.  
**Example usage:**

```gdscript
# Apply a force to all chunks
callback := func(rb: RigidBody3D, from: DestructableMesh):
    var collision_shape = rb.get_child(0) as CollisionShape3D
    var mesh_instance = collision_shape.get_child(0) as MeshInstance3D
```

### `chunks_get_elapsed_time() -> float`
**Description:**  
Returns the time elapsed (in seconds) since `smash_the_mesh()` was called.  
Returns `0` if `smash_the_mesh()` has not been called.

### `chunks_restart_elapsed_time()`
**Description:**  
Updates the elapsed time as if `smash_the_mesh()` was just called.  
This is useful for restarting time-based animations without restoring the chunks to their original state.

### `chunks_kill()`
**Description:**  
Removes all the chunks of this mesh instance.

### `chunks_reset()`
**Description:**  
Resets this instance to its state before `smash_the_mesh()` was called.

### `chunks_freeze(enable: bool)`
**Description:**  
Freezes or unfreezes the physics simulation of the chunks.  
- `enable`: Pass `true` to freeze the simulation, or `false` to unfreeze it.

### `chunks_repair(weight: float)`
**Description:**  
Reverts the chunks to their starting position.  
- `weight`: The amount of repair, from `0` (no repair) to `1` (fully repaired).  
This method can be called each frame with a low value of `weight` to create a backward animation to the original position.  
**Tip:** Ensure that `chunks_freeze()` is called before using this method to avoid disrupting the physics simulation.

## Getting Started

TODO

## How-to

TODO

## License

[MIT License](/LICENSE.md)
