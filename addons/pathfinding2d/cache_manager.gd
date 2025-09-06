@tool
extends RefCounted
class_name CacheManager

var validity_cache: Dictionary = {}
var cache_timer: float = 0.0
var cache_interval: float = PathfindingConstants.VALIDITY_CACHE_INTERVAL

func _init(update_interval: float = PathfindingConstants.VALIDITY_CACHE_INTERVAL):
	cache_interval = update_interval

func update_cache(delta: float, items: Array) -> void:
	cache_timer += delta
	
	if cache_timer >= cache_interval:
		_refresh_validity_cache(items)
		cache_timer = 0.0

func is_item_valid_cached(item) -> bool:
	if item in validity_cache:
		return validity_cache[item]
	else:
		# Fallback for new items not yet cached
		return is_instance_valid(item)

func invalidate_cache() -> void:
	validity_cache.clear()
	cache_timer = 0.0

func get_cached_valid_items(items: Array) -> Array[PathfinderObstacle]:
	var valid_items: Array[PathfinderObstacle] = []
	
	for item in items:
		if is_item_valid_cached(item):
			valid_items.append(item)
	
	return valid_items

func remove_invalid_items(items: Array) -> Array:
	var initial_size = items.size()
	var filtered_items = items.filter(func(item): return is_item_valid_cached(item))
	
	# Log cleanup if significant
	if filtered_items.size() < initial_size - PathfindingConstants.CLEANUP_THRESHOLD:
		print("Cache: Cleaned up ", initial_size - filtered_items.size(), " invalid items")
	
	return filtered_items

func _refresh_validity_cache(items: Array) -> void:
	validity_cache.clear()
	
	for item in items:
		validity_cache[item] = is_instance_valid(item)
