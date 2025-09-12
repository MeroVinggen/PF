# Replace the existing PathfindingDebugRenderer with this optimized version

@tool
extends Node2D
class_name PathfindingDebugRenderer

@export var systems_to_debug: Array[PathfinderSystem] = []

@export_group("Debug Options")
@export var draw_systems: bool = true
@export var draw_obstacles: bool = true
@export var draw_pathfinders: bool = true
@export var draw_pathfinders_path: bool = true
@export var draw_fps: float = 30.0 :
	set(value):
		draw_fps = value
		draw_timer_cap = 1.0 / draw_fps

@export_group("Colors")
@export var system_bounds_color: Color = Color.DARK_CYAN
@export var obstacle_color: Color = Color.RED
@export var dynamic_obstacle_color: Color = Color.ORANGE
@export var obstacle_disabled_color: Color = Color.GRAY
@export var pathfinder_color: Color = Color.GREEN
@export var pathfinder_buffer_color: Color = Color.CYAN
@export var path_color: Color = Color.YELLOW

# Performance optimization variables
var draw_timer: float = 0.0
# 30 fps by default
var draw_timer_cap: float = 0.032

# Batched draw data
var batched_obstacle_polygons: Array[PackedVector2Array] = []
var batched_obstacle_colors: Array[Color] = []
var batched_path_lines: Array[Array] = []  # Array of [start, end, color]
var batched_circles: Array[Array] = []     # Array of [pos, radius, color]

func _physics_process(delta: float) -> void:
	draw_timer += delta
	if draw_timer >= draw_timer_cap:
		draw_timer = 0.0
		
		_prepare_batched_draw_data()
		queue_redraw()

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
	var disabled_polygons: Array[PackedVector2Array] = []
	var disabled_colors: Array[Color] = []
	
	for system: PathfinderSystem in systems_to_debug:
		for obstacle: PathfinderObstacle in system.obstacles:
			
			# is_inside_tree() - to fix godot leak for keeping ref in arr for removed from scene nodes
			if not is_instance_valid(obstacle) or not obstacle.is_inside_tree():
				continue
			
			# obstacles fix for the editor mode!
			if Engine.is_editor_hint():
				if not obstacle.system:
					obstacle.system = system
				
				obstacle._store_last_state()
			
			if obstacle.cached_world_polygon.size() < 3:
				obstacle.system.array_pool.return_packedVector2_array(obstacle.cached_world_polygon)
				continue
			
			if obstacle.disabled:
				disabled_polygons.append(obstacle.cached_world_polygon)
				disabled_colors.append(obstacle_disabled_color)
				continue
			
			if obstacle.is_static:
				static_polygons.append(obstacle.cached_world_polygon)
				static_colors.append(obstacle_color)
			else:
				dynamic_polygons.append(obstacle.cached_world_polygon)
				dynamic_colors.append(dynamic_obstacle_color)
				
				# Add dynamic indicator circle to batch
				batched_circles.append([obstacle.global_position, 8.0, Color.YELLOW])
				batched_circles.append([obstacle.global_position, 6.0, dynamic_obstacle_color])
	
	# Combine batches
	batched_obstacle_polygons.append_array(static_polygons)
	batched_obstacle_colors.append_array(static_colors)
	batched_obstacle_polygons.append_array(dynamic_polygons)
	batched_obstacle_colors.append_array(dynamic_colors)
	batched_obstacle_polygons.append_array(disabled_polygons)
	batched_obstacle_colors.append_array(disabled_colors)

func _batch_pathfinders():
	for system: PathfinderSystem in systems_to_debug:
		for pathfinder in system.pathfinders:
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
			batched_circles.append([pos, pathfinder.agent_radius, pathfinder_color])
			
			if draw_pathfinders_path:
				_batch_pathfinders_path(pathfinder)

func _batch_pathfinders_path(pathfinder):
		# Batch path lines
		if pathfinder.current_path.size() > 1:
			for i in range(pathfinder.current_path.size() - 1):
				var start = pathfinder.current_path[i]
				var end = pathfinder.current_path[i + 1]
				var segment_color = path_color if i >= pathfinder.path_index else Color.GRAY
				batched_path_lines.append([start, end, segment_color])
			
			# Batch waypoint circles
			for i in range(pathfinder.current_path.size()):
				var point = pathfinder.current_path[i]
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
