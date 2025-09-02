@tool
extends Node2D
class_name PathfindingDebugRenderer

@export var systems_to_debug: Array[PathfinderSystem] = []
@export var obstacles_to_debug: Array[PathfinderObstacle] = []
@export var pathfinders_to_debug: Array[Pathfinder] = []

@export_group("Debug Options")
@export var draw_systems: bool = true
@export var draw_obstacles: bool = true
@export var draw_pathfinders: bool = true
@export var draw_grid: bool = false
@export var grid_sample_rate: int = 10
@export var draw_fps: float = 30.0 :
	set(value):
		draw_fps = value
		draw_timer_cap = 1.0 / draw_fps

@export_group("Colors")
@export var system_bounds_color: Color = Color.BLUE
@export var obstacle_color: Color = Color.RED
@export var dynamic_obstacle_color: Color = Color.ORANGE
@export var pathfinder_color: Color = Color.GREEN
@export var pathfinder_buffer_color: Color = Color.CYAN
@export var path_color: Color = Color.YELLOW
@export var grid_clear_color: Color = Color.GREEN
@export var grid_blocked_color: Color = Color.RED

var draw_timer: float = 0.0
var draw_timer_cap: float = 0.032

func _process(delta: float) -> void:
	draw_timer += delta
	if draw_timer >= draw_timer_cap:
		draw_timer = 0.0
		queue_redraw()

func _draw():
	if draw_systems:
		_draw_systems()
	
	if draw_obstacles:
		_draw_obstacles()
	
	if draw_pathfinders:
		_draw_pathfinders()

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
		
		# Draw grid if enabled
		if draw_grid and system.grid.size() > 0:
			var i = 0
			for pos in system.grid.keys():
				if i % grid_sample_rate == 0:
					var color = grid_clear_color if system.grid[pos] else grid_blocked_color
					draw_circle(pos, 2.0, color * 0.3)
				i += 1

func _draw_obstacles():
	for obstacle in obstacles_to_debug:
		if not is_instance_valid(obstacle):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		if world_poly.size() >= 3:
			# Choose color based on static/dynamic
			var color = dynamic_obstacle_color if not obstacle.is_static else obstacle_color
			
			# Draw filled polygon
			draw_colored_polygon(world_poly, color * 0.7)
			
			# Draw outline
			var outline = world_poly + PackedVector2Array([world_poly[0]])
			draw_polyline(outline, color, 2.0)
			
			# Draw dynamic indicator
			if not obstacle.is_static:
				draw_circle(obstacle.global_position, 8.0, Color.YELLOW)
				draw_circle(obstacle.global_position, 6.0, dynamic_obstacle_color)

func _draw_pathfinders():
	for pathfinder in pathfinders_to_debug:
		if not is_instance_valid(pathfinder):
			continue
		
		# Draw buffer area (underneath)
		if pathfinder.agent_buffer > 0:
			var buffer_radius = pathfinder.agent_radius + pathfinder.agent_buffer
			draw_circle(pathfinder.global_position, buffer_radius, pathfinder_buffer_color * 0.3)
			draw_arc(pathfinder.global_position, buffer_radius, 0, TAU, 32, pathfinder_buffer_color * 0.7, 1.0)
		
		# Draw agent with status color
		var color = pathfinder_color
		if pathfinder.consecutive_failed_recalcs > 0:
			color = Color.PURPLE
		
		draw_circle(pathfinder.global_position, pathfinder.agent_radius, color * 0.7)
		draw_arc(pathfinder.global_position, pathfinder.agent_radius, 0, TAU, 32, color, 2.0)
		
		# Draw path
		var path = pathfinder.get_current_path()
		if path.size() > 1:
			for i in range(path.size() - 1):
				var start = path[i]
				var end = path[i + 1]
				var segment_color = path_color if i >= pathfinder.path_index else Color.GRAY
				draw_line(start, end, segment_color, 3.0)
			
			# Draw waypoints
			for i in range(path.size()):
				var point = path[i]
				var waypoint_color = Color.WHITE if i == pathfinder.path_index else (Color.GRAY if i < pathfinder.path_index else path_color)
				draw_circle(point, 5.0, waypoint_color)
		
		# Draw target
		if pathfinder.is_moving and pathfinder.target_position != Vector2.ZERO:
			draw_circle(pathfinder.target_position, 8.0, Color.MAGENTA)

func add_system(system: PathfinderSystem):
	if system not in systems_to_debug:
		systems_to_debug.append(system)

func remove_system(system: PathfinderSystem):
	systems_to_debug.erase(system)

func add_obstacle(obstacle: PathfinderObstacle):
	if obstacle not in obstacles_to_debug:
		obstacles_to_debug.append(obstacle)

func remove_obstacle(obstacle: PathfinderObstacle):
	obstacles_to_debug.erase(obstacle)

func add_pathfinder(pathfinder: Pathfinder):
	if pathfinder not in pathfinders_to_debug:
		pathfinders_to_debug.append(pathfinder)

func remove_pathfinder(pathfinder: Pathfinder):
	pathfinders_to_debug.erase(pathfinder)

func clear_all():
	systems_to_debug.clear()
	obstacles_to_debug.clear()
	pathfinders_to_debug.clear()

func auto_discover_in_scene():
	"""Auto-populate arrays with all pathfinding nodes in the scene"""
	clear_all()
	_find_pathfinding_nodes(get_tree().current_scene)

func _find_pathfinding_nodes(node: Node):
	if node is PathfinderSystem:
		add_system(node)
	elif node is PathfinderObstacle:
		add_obstacle(node)
	elif node is Pathfinder:
		add_pathfinder(node)
	
	for child in node.get_children():
		_find_pathfinding_nodes(child)
