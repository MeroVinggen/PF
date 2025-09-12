extends Node2D

# Export properties for testing
@export_group("Test Parameters")
@export var update_frequency: int = 30 :
	set(value):
		update_frequency = value
		draw_timer_cap = 1.0 / update_frequency
@export var entities_scale: float = 1.0
@export var agents_amount: int = 100
@export var agents_radius: float = 8.0
@export var agent_speed: float = 100.0
@export var static_obstacles_amount: int = 20
@export var dynamic_obstacles_amount: int = 10
@export var dynamic_obstacles_speed: float = 50.0
@export var targets_amount: int = 5

# Scene references
@onready var pathfinding_system: PathfinderSystem = $PathfinderSystem
@onready var debug_renderer: PathfindingDebugRenderer = $PathfindingDebugRenderer
@onready var stop_agents: Button = $UIContainer/VBoxContainer/stop_agents
@onready var restart: Button = $UIContainer/VBoxContainer/restart


@onready var spawn_targets_btn: Button = $UIContainer/VBoxContainer/spawn_targets_btn
@onready var move_dynamic_btn: Button = $UIContainer/VBoxContainer/move_dynamic_btn
@onready var fps_label: Label = $UIContainer/VBoxContainer/FPSLabel
@onready var stats_label: Label = $UIContainer/VBoxContainer/StatsLabel

# Performance optimization variables
var draw_timer: float = 0.0
# 30 fps by default
var draw_timer_cap: float = 0.032

# Runtime data
var agents: Array[PathfinderAgent] = []
var static_obstacles: Array[PathfinderObstacle] = []
var dynamic_obstacles: Array[PathfinderObstacle] = []
var targets: Array[Node2D] = []
var dynamic_moving: bool = false

# Obstacle presets
var obstacle_shapes = [
	# Square
	PackedVector2Array([
		Vector2(-20, -20), Vector2(20, -20), 
		Vector2(20, 20), Vector2(-20, 20)
	]),
	# Triangle
	PackedVector2Array([
		Vector2(0, -25), Vector2(22, 15), Vector2(-22, 15)
	]),
	# Hexagon
	PackedVector2Array([
		Vector2(20, 0), Vector2(10, 17), Vector2(-10, 17),
		Vector2(-20, 0), Vector2(-10, -17), Vector2(10, -17)
	])
]

func _ready():
	_setup_pathfinding_system()
	_spawn_all_entities()
	
	# Connect signals
	spawn_targets_btn.pressed.connect(_on_spawn_targets_pressed)
	move_dynamic_btn.pressed.connect(_on_move_dynamic_pressed)
	stop_agents.pressed.connect(_on_stop_agents)
	restart.pressed.connect(_on_restart)

func _physics_process(delta: float) -> void:
	draw_timer += delta
	if draw_timer < draw_timer_cap:
		return
	
	draw_timer = 0.0
	
	_update_stats()
	_update_agent_movement(delta)
	if dynamic_moving:
		_update_dynamic_obstacles()


func _setup_pathfinding_system():
	pathfinding_system.init()
	
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Set system bounds to viewport
	pathfinding_system.bounds_polygon = PackedVector2Array([
		Vector2(50, 50),
		Vector2(viewport_size.x - 50, 50),
		Vector2(viewport_size.x - 50, viewport_size.y - 50),
		Vector2(50, viewport_size.y - 50)
	])
	

func _spawn_all_entities():
	_clear_all_entities()
	_spawn_static_obstacles()
	_spawn_dynamic_obstacles()
	_spawn_agents()

func _clear_all_entities():
	for agent in agents:
		if is_instance_valid(agent):
			agent.queue_free()
	for obstacle in static_obstacles + dynamic_obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	for target in targets:
		if is_instance_valid(target):
			target.queue_free()
	
	agents.clear()
	static_obstacles.clear()
	dynamic_obstacles.clear()
	targets.clear()

func _spawn_static_obstacles():
	var viewport_size = get_viewport().get_visible_rect().size
	
	for i in static_obstacles_amount:
		var obstacle = PathfinderObstacle.new()
		obstacle.is_static = true
		obstacle.layer = 1
		
		# Random shape and scale
		var shape = obstacle_shapes[randi() % obstacle_shapes.size()]
		var scale_factor = randf_range(0.5, 1.5) * entities_scale
		obstacle.obstacle_polygon = PackedVector2Array()
		for point in shape:
			obstacle.obstacle_polygon.append(point * scale_factor)
		
		# Random position (avoid edges)
		obstacle.global_position = Vector2(
			randf_range(100, viewport_size.x - 100),
			randf_range(100, viewport_size.y - 100)
		)
		
		add_child(obstacle)
		static_obstacles.append(obstacle)
		pathfinding_system.obstacle_manager.register_obstacle(obstacle)

func _spawn_dynamic_obstacles():
	var viewport_size = get_viewport().get_visible_rect().size
	
	for i in dynamic_obstacles_amount:
		var obstacle = PathfinderObstacle.new()
		obstacle.is_static = false
		obstacle.layer = 1
		obstacle.update_frequency = 60.0  # High frequency for dynamic
		
		# Random shape (usually smaller than static)
		var shape = obstacle_shapes[randi() % obstacle_shapes.size()]
		var scale_factor = randf_range(0.3, 0.8) * entities_scale
		obstacle.obstacle_polygon = PackedVector2Array()
		for point in shape:
			obstacle.obstacle_polygon.append(point * scale_factor)
		
		# Random position
		obstacle.global_position = Vector2(
			randf_range(150, viewport_size.x - 150),
			randf_range(150, viewport_size.y - 150)
		)
		
		# Add velocity for movement
		obstacle.set_meta("velocity", Vector2(
			randf_range(-dynamic_obstacles_speed, dynamic_obstacles_speed),
			randf_range(-dynamic_obstacles_speed, dynamic_obstacles_speed)
		))
		
		add_child(obstacle)
		dynamic_obstacles.append(obstacle)
		pathfinding_system.obstacle_manager.register_obstacle(obstacle)

func _spawn_agents():
	var viewport_size = get_viewport().get_visible_rect().size
	var spawn_attempts = agents_amount * 5  # Prevent infinite loops
	
	for i in agents_amount:
		var agent = PathfinderAgent.new()
		agent.agent_radius = agents_radius * entities_scale
		agent.agent_buffer = 2.0 * entities_scale
		agent.mask = 1
		
		# Find safe spawn position
		var safe_pos = _find_safe_spawn_position(agent.agent_radius)
		if safe_pos == Vector2.INF:
			print("Could not find safe position for agent ", i)
			continue
			
		agent.global_position = safe_pos
		agent.set_meta("speed", agent_speed * entities_scale)
		agent.set_meta("target_pos", Vector2.ZERO)
		agent.set_meta("distance", 0.0)
		agent.set_meta("direction", Vector2.ZERO)
		
		add_child(agent)
		agents.append(agent)
		pathfinding_system.register_pathfinder(agent)

func _find_safe_spawn_position(radius: float) -> Vector2:
	var viewport_size = get_viewport().get_visible_rect().size
	var attempts = 50
	
	for i in attempts:
		var test_pos = Vector2(
			randf_range(radius + 100, viewport_size.x - radius - 100),
			randf_range(radius + 100, viewport_size.y - radius - 100)
		)
		
		var safe = true
		# Check against all obstacles
		for obstacle in static_obstacles + dynamic_obstacles:
			if test_pos.distance_to(obstacle.global_position) < (radius + 50):
				safe = false
				break
		
		if safe:
			return test_pos
	
	return Vector2.INF

func _spawn_targets():
	# Clear existing targets
	for target in targets:
		if is_instance_valid(target):
			target.queue_free()
	targets.clear()
	
	var viewport_size = get_viewport().get_visible_rect().size
	
	for i in targets_amount:
		var target = Node2D.new()
		target.global_position = Vector2(
			randf_range(100, viewport_size.x - 100),
			randf_range(100, viewport_size.y - 100)
		)
		
		add_child(target)
		targets.append(target)

func _update_agent_movement(delta):
	for agent in agents:
		if not is_instance_valid(agent) or not agent.is_moving:
			continue
	
		var speed = agent.get_meta("speed", agent_speed)
		var current_target = agent.get_meta("target_pos")
		var distance = agent.get_meta("distance")
		var direction = agent.get_meta("direction")
		var update_current_target = agent.get_next_waypoint()
		
		if update_current_target == current_target:
			distance = agent.global_position.distance_to(current_target)
			make_step(delta, agent, distance, direction, speed)
			return
		
		current_target = update_current_target
		
		if current_target == Vector2.INF:
			return
		
		# target point been updated - recalc movement data
		direction = (current_target - agent.global_position).normalized()
		distance = agent.global_position.distance_to(current_target)
		make_step(delta, agent, distance, direction, speed)


func make_step(delta: float, agent, distance, direction, speed) -> void:
	# Close enough to waypoint
	if distance < 5.0:
		agent.advance_to_next_waypoint()
	else:
		agent.global_position += direction * speed * delta

func _update_dynamic_obstacles():
	var viewport_size = get_viewport().get_visible_rect().size
	var bounds = Rect2(50, 50, viewport_size.x - 100, viewport_size.y - 100)
	
	for obstacle in dynamic_obstacles:
		if not is_instance_valid(obstacle):
			continue
			
		var velocity = obstacle.get_meta("velocity", Vector2.ZERO)
		var new_pos = obstacle.global_position + velocity * get_process_delta_time()
		
		# Bounce off bounds
		if new_pos.x < bounds.position.x or new_pos.x > bounds.position.x + bounds.size.x:
			velocity.x = -velocity.x
		if new_pos.y < bounds.position.y or new_pos.y > bounds.position.y + bounds.size.y:
			velocity.y = -velocity.y
		
		obstacle.set_meta("velocity", velocity)
		obstacle.global_position = obstacle.global_position + velocity * get_process_delta_time()

func _update_stats():
	fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
	stats_label.text = "Agents: %d | Static: %d | Dynamic: %d | Targets: %d" % [
		agents.size(), static_obstacles.size(), dynamic_obstacles.size(), targets.size()
	]

func _on_spawn_targets_pressed():
	_spawn_targets()
	
	# Assign random targets to agents
	if targets.is_empty():
		return
		
	for agent in agents:
		if not is_instance_valid(agent):
			continue
			
		var target = targets[randi() % targets.size()]
		agent.find_path_to(target.global_position)

func _on_move_dynamic_pressed():
	dynamic_moving = !dynamic_moving
	move_dynamic_btn.text = "Stop Dynamic Movement" if dynamic_moving else "Start Dynamic Movement"

# Target visualization
func _draw():
	for target in targets:
		if is_instance_valid(target):
			draw_circle(target.global_position, 15, Color.MAGENTA, false, 3.0)

func _on_stop_agents():
	for agent in agents:
		if not is_instance_valid(agent):
			continue
		agent.stop_movement()

func _on_restart():
	get_tree().reload_current_scene()
