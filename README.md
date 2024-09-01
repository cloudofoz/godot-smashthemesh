![Version](https://img.shields.io/badge/Godot-v4.3-informational) ![License](https://img.shields.io/github/license/cloudofoz/godot-smashthemesh)

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

## Getting Started

TODO

## How-to

TODO

## License

[MIT License](/LICENSE.md)
