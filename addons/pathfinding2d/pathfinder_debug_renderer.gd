# Replace the existing PathfindingDebugRenderer with this optimized version

@tool
extends Node2D
class_name PathfindingDebugRenderer

@export var systems_to_debug: Array[PathfinderSystem] = []
@export var obstacles_to_debug: Array[PathfinderObstacle] = []
@export var pathfinders_to_debug: Array[PathfinderAgent] = []

@export_group("Debug Options")
@export var draw_systems: bool = true
@export var draw_obstacles: bool = true
@export var draw_pathfinders: bool = true
@export var draw_pathfinders_path: bool = true
@export var draw_grid: bool = false
@export var grid_sample_rate: int = 10
@export var draw_fps: float = 30.0 :
	set(value):
		draw_fps = value
		draw_timer_cap = 1.0 / draw_fps

@export_group("Colors")
@export var system_bounds_color: Color = Color.DARK_CYAN
@export var obstacle_color: Color = Color.RED
@export var dynamic_obstacle_color: Color = Color.ORANGE
@export var pathfinder_color: Color = Color.GREEN
@export var pathfinder_buffer_color: Color = Color.CYAN
@export var path_color: Color = Color.YELLOW
@export var grid_clear_color: Color = Color.CORNFLOWER_BLUE
@export var grid_blocked_color: Color = Color.RED

# Performance optimization variables
var draw_timer: float = 0.0
var draw_timer_cap: float = 0.032

# Caching system (#4)
var cached_static_obstacles: Dictionary = {}  # obstacle -> last_transform
var cached_dynamic_paths: Dictionary = {}     # agent -> last_path_hash
var cached_system_bounds: Dictionary = {}     # system -> last_bounds
var draw_data_dirty: bool = true
var last_camera_transform: Transform2D

# Batched draw data (#3)
var batched_obstacle_polygons: Array[PackedVector2Array] = []
var batched_obstacle_colors: Array[Color] = []
var batched_path_lines: Array[Array] = []  # Array of [start, end, color]
var batched_circles: Array[Array] = []     # Array of [pos, radius, color]

func _physics_process(delta: float) -> void:
	draw_timer += delta
	if draw_timer >= draw_timer_cap:
		draw_timer = 0.0
		
		# Check if we need to update cached data
		_update_cache_validity()
		
		if draw_data_dirty:
			_prepare_batched_draw_data()
			draw_data_dirty = false
		
		queue_redraw()

func _update_cache_validity():
	var current_camera = get_viewport().get_camera_2d()
	var camera_changed = false
	
	if current_camera:
		var current_transform = current_camera.get_screen_center_position()
		if current_transform != last_camera_transform:
			camera_changed = true
			last_camera_transform = current_transform
	
	# Check static obstacles for changes
	for obstacle in obstacles_to_debug:
		if not is_instance_valid(obstacle):
			continue
			
		if obstacle.is_static:
			var current_transform = obstacle.global_transform
			if not cached_static_obstacles.has(obstacle) or cached_static_obstacles[obstacle] != current_transform:
				cached_static_obstacles[obstacle] = current_transform
				draw_data_dirty = true
		else:
			# Dynamic obstacles always trigger redraw
			draw_data_dirty = true
	
	# Check pathfinders for path changes
	for pathfinder in pathfinders_to_debug:
		if not is_instance_valid(pathfinder):
			continue
			
		var current_path = pathfinder.get_current_path()
		var path_hash = _hash_path(current_path, pathfinder.path_index, pathfinder.global_position)
		
		if not cached_dynamic_paths.has(pathfinder) or cached_dynamic_paths[pathfinder] != path_hash:
			cached_dynamic_paths[pathfinder] = path_hash
			draw_data_dirty = true
	
	# Check system bounds
	for system in systems_to_debug:
		if not is_instance_valid(system):
			continue
			
		var bounds_hash = _hash_polygon(system.bounds_polygon)
		if not cached_system_bounds.has(system) or cached_system_bounds[system] != bounds_hash:
			cached_system_bounds[system] = bounds_hash
			draw_data_dirty = true
	
	if camera_changed:
		draw_data_dirty = true

func _prepare_batched_draw_data():
	# Clear previous batch data
	batched_obstacle_polygons.clear()
	batched_obstacle_colors.clear()
	batched_path_lines.clear()
	batched_circles.clear()
	
	if draw_obstacles:
		_batch_obstacles()
	
	if draw_pathfinders:
		_batch_pathfinders()

func _batch_obstacles():
	# Separate static and dynamic for different batching strategies
	var static_polygons: Array[PackedVector2Array] = []
	var static_colors: Array[Color] = []
	var dynamic_polygons: Array[PackedVector2Array] = []
	var dynamic_colors: Array[Color] = []
	
	for system: PathfinderSystem in systems_to_debug:
		for obstacle: PathfinderObstacle in system.obstacles:
	
	#for obstacle: PathfinderObstacle in obstacles_to_debug:
			if not is_instance_valid(obstacle):
				continue
			
			# set system only if in editor!
			if Engine.is_editor_hint():
				obstacle.system = system
			
			var world_poly = obstacle.get_world_polygon()
			if world_poly.size() < 3:
				obstacle.system.array_pool.return_packedVector2_array(world_poly)
				continue
			
			var color = dynamic_obstacle_color if not obstacle.is_static else obstacle_color
			
			if obstacle.is_static:
				# duplicate to avoide errs, coz the arr will be cleared when returned to the pool
				static_polygons.append(world_poly.duplicate())
				obstacle.system.array_pool.return_packedVector2_array(world_poly)
				static_colors.append(color)
			else:
				# duplicate to avoide errs, coz the arr will be cleared when returned to the pool
				dynamic_polygons.append(world_poly.duplicate())
				obstacle.system.array_pool.return_packedVector2_array(world_poly)
				dynamic_colors.append(color)
				
				# Add dynamic indicator circle to batch
				batched_circles.append([obstacle.global_position, 8.0, Color.YELLOW])
				batched_circles.append([obstacle.global_position, 6.0, dynamic_obstacle_color])
	
	# Combine batches
	batched_obstacle_polygons.append_array(static_polygons)
	batched_obstacle_colors.append_array(static_colors)
	batched_obstacle_polygons.append_array(dynamic_polygons)
	batched_obstacle_colors.append_array(dynamic_colors)

func _batch_pathfinders():
	for pathfinder in pathfinders_to_debug:
		if not is_instance_valid(pathfinder):
			continue
		
		var pos = pathfinder.global_position
		
		# Batch buffer area
		if pathfinder.agent_buffer > 0:
			var buffer_radius = pathfinder.agent_radius + pathfinder.agent_buffer
			batched_circles.append([pos, buffer_radius, pathfinder_buffer_color * 0.3])
		
		# Batch agent circle
		var color = pathfinder_color
		if pathfinder.consecutive_failed_recalcs > 0:
			color = Color.PURPLE
		batched_circles.append([pos, pathfinder.agent_radius, color])
		
		if draw_pathfinders_path:
			_batch_pathfinders_path(pathfinder)

func _batch_pathfinders_path(pathfinder):
		# Batch path lines
		var path = pathfinder.get_current_path()
		if path.size() > 1:
			for i in range(path.size() - 1):
				var start = path[i]
				var end = path[i + 1]
				var segment_color = path_color if i >= pathfinder.path_index else Color.GRAY
				batched_path_lines.append([start, end, segment_color])
			
			# Batch waypoint circles
			for i in range(path.size()):
				var point = path[i]
				var waypoint_color = Color.WHITE if i == pathfinder.path_index else (Color.GRAY if i < pathfinder.path_index else path_color)
				batched_circles.append([point, 5.0, waypoint_color])
		
		# Batch target circle
		if pathfinder.is_moving and pathfinder.target_position != Vector2.ZERO:
			batched_circles.append([pathfinder.target_position, 8.0, Color.MAGENTA])

func _draw():
	# Draw systems (usually static, so can be cached separately)
	if draw_systems:
		_draw_systems()
	
	# Draw batched obstacles
	_draw_batched_obstacles()
	
	# Draw batched pathfinders
	_draw_batched_pathfinders()

func _draw_systems():
	for system in systems_to_debug:
		if not is_instance_valid(system):
			continue
		
		# Draw system bounds
		if system.bounds_polygon.size() >= 3:
			var points = system.bounds_polygon
			for i in range(points.size()):
				var start = points[i]
				var end = points[(i + 1) % points.size()]
				draw_line(start, end, system_bounds_color, 2.0)
		
		# Draw grid if enabled (this is expensive, keep it optional)
		if draw_grid and system.grid_manager.grid.size() > 0:
			var i = 0
			for pos in system.grid_manager.grid.keys():
				if i % grid_sample_rate == 0:
					var color = grid_clear_color if system.grid_manager.grid[pos] else grid_blocked_color
					draw_circle(pos, 2.0, color)
				i += 1

func _draw_batched_obstacles():
	# Draw all obstacle polygons in batches
	for i in range(batched_obstacle_polygons.size()):
		var poly = batched_obstacle_polygons[i]
		var color = batched_obstacle_colors[i] if i < batched_obstacle_colors.size() else obstacle_color
		
		# Draw filled polygon
		draw_colored_polygon(poly, color * 0.7)
		
		# Draw outline
		var outline = poly + PackedVector2Array([poly[0]])
		draw_polyline(outline, color, 2.0)

func _draw_batched_pathfinders():
	# Draw all path lines
	for line_data in batched_path_lines:
		draw_line(line_data[0], line_data[1], line_data[2], 3.0)
	
	# Draw all circles (agents, buffers, waypoints, targets)
	for circle_data in batched_circles:
		draw_circle(circle_data[0], circle_data[1], circle_data[2])

func _hash_path(path: PackedVector2Array, path_index: int, agent_pos: Vector2) -> int:
	var hash = 0
	hash = hash ^ path.size()
	hash = hash ^ path_index
	hash = hash ^ int(agent_pos.x * 100) ^ int(agent_pos.y * 100)
	
	# Sample a few path points for hash (don't hash entire path for performance)
	var sample_points = min(5, path.size())
	for i in sample_points:
		var point = path[i * path.size() / sample_points]
		hash = hash ^ int(point.x * 100) ^ int(point.y * 100)
	
	return hash

func _hash_polygon(poly: PackedVector2Array) -> int:
	var hash = poly.size()
	for point in poly:
		hash = hash ^ int(point.x * 100) ^ int(point.y * 100)
	return hash

# Public interface remains the same
func add_system(system: PathfinderSystem):
	if system not in systems_to_debug:
		systems_to_debug.append(system)
		draw_data_dirty = true

func remove_system(system: PathfinderSystem):
	systems_to_debug.erase(system)
	cached_system_bounds.erase(system)
	draw_data_dirty = true

func add_obstacle(obstacle: PathfinderObstacle):
	if obstacle not in obstacles_to_debug:
		obstacles_to_debug.append(obstacle)
		draw_data_dirty = true

func remove_obstacle(obstacle: PathfinderObstacle):
	obstacles_to_debug.erase(obstacle)
	cached_static_obstacles.erase(obstacle)
	draw_data_dirty = true

func add_pathfinder(pathfinder: PathfinderAgent):
	if pathfinder not in pathfinders_to_debug:
		pathfinders_to_debug.append(pathfinder)
		draw_data_dirty = true

func remove_pathfinder(pathfinder: PathfinderAgent):
	pathfinders_to_debug.erase(pathfinder)
	cached_dynamic_paths.erase(pathfinder)
	draw_data_dirty = true

func clear_all():
	systems_to_debug.clear()
	obstacles_to_debug.clear()
	pathfinders_to_debug.clear()
	cached_static_obstacles.clear()
	cached_dynamic_paths.clear()
	cached_system_bounds.clear()
	draw_data_dirty = true
