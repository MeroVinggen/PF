@tool
extends RefCounted
class_name QuadTree

var system: PathfinderSystem
var bounds: Rect2
var max_objects: int
var max_levels: int
var level: int

var objects: Array[PathfinderObstacle] = []
var nodes: Array[QuadTree] = []

func _init(systemRef: PathfinderSystem, boundary: Rect2, max_objs: int = 10, max_lvls: int = 5, lvl: int = 0):
	system = systemRef
	bounds = boundary
	max_objects = max_objs
	max_levels = max_lvls
	level = lvl

func clear():
	objects.clear()
	for node in nodes:
		if node:
			node.clear()
	nodes.clear()

func split():
	var sub_width = bounds.size.x / 2
	var sub_height = bounds.size.y / 2
	var x = bounds.position.x
	var y = bounds.position.y
	
	nodes.resize(4)
	nodes[0] = QuadTree.new(system, Rect2(x + sub_width, y, sub_width, sub_height), max_objects, max_levels, level + 1)
	nodes[1] = QuadTree.new(system, Rect2(x, y, sub_width, sub_height), max_objects, max_levels, level + 1)
	nodes[2] = QuadTree.new(system, Rect2(x, y + sub_height, sub_width, sub_height), max_objects, max_levels, level + 1)
	nodes[3] = QuadTree.new(system, Rect2(x + sub_width, y + sub_height, sub_width, sub_height), max_objects, max_levels, level + 1)

func get_index(obstacle_bounds: Rect2) -> int:
	var index = -1
	var vertical_midpoint = bounds.position.x + (bounds.size.x / 2)
	var horizontal_midpoint = bounds.position.y + (bounds.size.y / 2)
	
	var top_quadrant = (obstacle_bounds.position.y < horizontal_midpoint and obstacle_bounds.position.y + obstacle_bounds.size.y < horizontal_midpoint)
	var bottom_quadrant = (obstacle_bounds.position.y > horizontal_midpoint)
	
	if obstacle_bounds.position.x < vertical_midpoint and obstacle_bounds.position.x + obstacle_bounds.size.x < vertical_midpoint:
		if top_quadrant:
			index = 1
		elif bottom_quadrant:
			index = 2
	elif obstacle_bounds.position.x > vertical_midpoint:
		if top_quadrant:
			index = 0
		elif bottom_quadrant:
			index = 3
	
	return index

func insert(obstacle: PathfinderObstacle):
	if not nodes.is_empty():
		var obstacle_bounds = PathfindingUtils.get_polygon_bounds(obstacle.cached_world_polygon)
		var index = get_index(obstacle_bounds)
		
		if index != -1:
			nodes[index].insert(obstacle)
			return
	
	objects.append(obstacle)
	
	if objects.size() > max_objects and level < max_levels:
		if nodes.is_empty():
			split()
		
		var i = 0
		while i < objects.size():
			var obj_bounds = PathfindingUtils.get_polygon_bounds(objects[i].cached_world_polygon)
			var index = get_index(obj_bounds)
			if index != -1:
				nodes[index].insert(objects[i])
				objects.remove_at(i)
			else:
				i += 1

func retrieve(return_objects: Array[PathfinderObstacle], bounds_to_check: Rect2):
	var index = get_index(bounds_to_check)
	if index != -1 and not nodes.is_empty():
		nodes[index].retrieve(return_objects, bounds_to_check)
	
	return_objects.append_array(objects)

func get_obstacles_in_bounds(query_bounds: Rect2) -> Array[PathfinderObstacle]:
	# will be returned to pool in place of usage
	var result: Array[PathfinderObstacle] = system.array_pool.get_obstacle_array()
	retrieve(result, query_bounds)
	return result
