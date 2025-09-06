@tool
extends RefCounted
class_name PathfindingValidator

# Validate PathfinderSystem configuration
static func validate_pathfinder_system(system: PathfinderSystem) -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if system.bounds_polygon.size() < 3:
		warnings.append("Bounds polygon needs at least 3 points")
	
	if system.grid_size <= 0:
		warnings.append("Grid size must be greater than 0")
	elif system.grid_size < 5:
		warnings.append("Very small grid size (%s) may cause performance issues" % system.grid_size)
	elif system.grid_size > 100:
		warnings.append("Large grid size (%s) may reduce pathfinding precision" % system.grid_size)
	
	if system.dynamic_update_rate <= 0:
		warnings.append("Dynamic update rate must be greater than 0")
	elif system.dynamic_update_rate < 0.05:
		warnings.append("Very frequent dynamic updates (%.3fs) may impact performance" % system.dynamic_update_rate)
	
	# Cross-component validation with pathfinders
	for pathfinder in system.pathfinders:
		if is_instance_valid(pathfinder):
			if pathfinder.agent_radius > system.grid_size * 2:
				warnings.append("Agent radius (%.1f) is much larger than grid size (%.1f) - consider increasing grid size" % [pathfinder.agent_radius, system.grid_size])
	
	return warnings

# Validate PathfinderObstacle configuration  
static func validate_pathfinder_obstacle(obstacle: PathfinderObstacle) -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if obstacle.obstacle_polygon.size() < 3:
		warnings.append("Obstacle polygon needs at least 3 points to form a valid obstacle")
	elif obstacle.obstacle_polygon.size() > 50:
		warnings.append("Very complex polygon (%d points) may impact performance" % obstacle.obstacle_polygon.size())
	
	# Check for very small obstacles that might cause issues
	var bounds = PathfindingUtils.get_polygon_bounds(obstacle.obstacle_polygon)
	if bounds.size.x < 5 or bounds.size.y < 5:
		warnings.append("Very small obstacle (%.1f x %.1f) may cause pathfinding issues" % [bounds.size.x, bounds.size.y])
	
	if not obstacle.is_static:
		warnings.append("Dynamic obstacles will impact performance - use sparingly")
		
		# Additional warnings for dynamic obstacles
		if bounds.size.x > 200 or bounds.size.y > 200:
			warnings.append("Large dynamic obstacle may cause frequent path recalculations")
	
	# Check for self-intersecting polygon (basic check)
	if _has_self_intersections(obstacle.obstacle_polygon):
		warnings.append("Polygon may have self-intersections which can cause undefined behavior")
	
	return warnings

# Validate PathfinderAgent configuration
static func validate_pathfinder(pathfinder: PathfinderAgent) -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if pathfinder.agent_radius <= 0:
		warnings.append("Agent radius must be greater than 0")
	elif pathfinder.agent_radius > 100:
		warnings.append("Very large agent radius (%.1f) may cause pathfinding issues" % pathfinder.agent_radius)
	
	if pathfinder.agent_buffer < 0:
		warnings.append("Agent buffer cannot be negative")
	elif pathfinder.agent_buffer > pathfinder.agent_radius:
		warnings.append("Agent buffer (%.1f) larger than radius (%.1f) may be excessive" % [pathfinder.agent_buffer, pathfinder.agent_radius])

	return warnings

# Helper function to detect basic self-intersections in polygon
static func _has_self_intersections(polygon: PackedVector2Array) -> bool:
	if polygon.size() < 4:
		return false
	
	# Check if any non-adjacent edges intersect
	for i in range(polygon.size()):
		var edge1_start = polygon[i]
		var edge1_end = polygon[(i + 1) % polygon.size()]
		
		for j in range(i + 2, polygon.size()):
			# Skip adjacent edges and the edge that closes the polygon
			if j == (i + polygon.size() - 1) % polygon.size():
				continue
				
			var edge2_start = polygon[j]
			var edge2_end = polygon[(j + 1) % polygon.size()]
			
			if _line_segments_intersect(edge1_start, edge1_end, edge2_start, edge2_end):
				return true
	
	return false

# Helper function to check if two line segments intersect
static func _line_segments_intersect(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> bool:
	var o1 = _orientation(p1, q1, p2)
	var o2 = _orientation(p1, q1, q2)
	var o3 = _orientation(p2, q2, p1)
	var o4 = _orientation(p2, q2, q1)
	
	# General case
	if o1 != o2 and o3 != o4:
		return true
	
	return false

# Helper function to find orientation of ordered triplet (p, q, r)
static func _orientation(p: Vector2, q: Vector2, r: Vector2) -> int:
	var val = (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
	if abs(val) < 0.001:
		return 0  # Collinear
	return 1 if val > 0 else 2  # Clock or Counterclock wise
