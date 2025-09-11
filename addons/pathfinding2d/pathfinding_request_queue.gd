@tool
extends RefCounted
class_name PathfindingRequestQueue

var system: PathfinderSystem
var request_queue: Array[PathfindingRequest] = []
var max_requests_per_frame: int = 3
var max_time_budget_ms: float = 5.0

func _init(pathfinder_system: PathfinderSystem, requests_per_frame: int = 3, time_budget: float = 5.0):
	system = pathfinder_system
	max_requests_per_frame = requests_per_frame
	max_time_budget_ms = time_budget

func queue_request(agent: PathfinderAgent, start: Vector2, end: Vector2, agent_full_size: float, mask: int):
	var request = system.array_pool.get_pathfinding_request()
	request.agent = agent
	request.start = start
	request.end = end
	request.agent_full_size = agent_full_size
	request.mask = mask
	request_queue.append(request)

func process_queue():
	var start_time = Time.get_ticks_msec()
	var processed = 0
	
	while not request_queue.is_empty() and processed < max_requests_per_frame:
		var elapsed = Time.get_ticks_msec() - start_time
		if elapsed > max_time_budget_ms:
			break
		
		var request = request_queue.pop_front()
		_process_request(request)
		processed += 1

func _process_request(request: PathfindingRequest):
	var path = PathfindingUtils.find_path_for_circle(
		system, request.start, request.end, request.agent_full_size
	)
	
	if is_instance_valid(request.agent):
		request.agent._on_queued_path_result(path)
		
	system.array_pool.return_pathfinding_request(request)
