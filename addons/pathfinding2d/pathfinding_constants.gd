@tool
extends RefCounted
class_name PathfindingConstants

# === A* PATHFINDING CONSTANTS ===
const MAX_PATHFINDING_ITERATIONS: int = 3000
const GOAL_TOLERANCE_FACTOR: float = 0.7  # Multiplied by grid_size
const GOAL_TOLERANCE_MIN_FACTOR: float = 0.5  # Multiplied by radius
const NODE_DISTANCE_THRESHOLD: float = 0.3  # For node matching in open set
const SAFETY_MARGIN: float = 0.5  # Added to collision checks
const SAMPLE_DISTANCE_FACTOR: float = 0.5  # Grid_size * factor for path sampling

# === CIRCLE POSITION FINDING CONSTANTS ===
const SEARCH_STEP_FACTOR: float = 0.5  # min(grid_size * factor, radius * factor)
const MAX_SEARCH_RADIUS_GRID_FACTOR: float = 12.0  # grid_size * factor
const MAX_SEARCH_RADIUS_AGENT_FACTOR: float = 6.0  # radius * factor
const SEARCH_ANGLE_STEP: float = PI / 8  # 8 directions per search circle

# === NEIGHBOR GENERATION CONSTANTS ===
const LARGE_AGENT_THRESHOLD: float = 0.7  # Ratio of radius to grid_size
const ADAPTIVE_STEP_FACTOR: float = 0.8  # For larger agents
const HALF_STEP_THRESHOLD: float = 0.5  # When to add half-steps
const MIN_STEP_SIZE_FACTOR: float = 0.5  # Minimum step as factor of grid_size

# === OBSTACLE CHANGE DETECTION CONSTANTS ===
const DYNAMIC_POSITION_THRESHOLD: float = 0.3  # Position change threshold for dynamic
const STATIC_POSITION_THRESHOLD: float = 0.8   # Position change threshold for static
const DYNAMIC_ROTATION_THRESHOLD: float = 0.003  # Rotation change threshold for dynamic
const STATIC_ROTATION_THRESHOLD: float = 0.008   # Rotation change threshold for static
const POLYGON_CHANGE_THRESHOLD: float = 0.05    # Polygon vertex change threshold
const TRANSFORM_SCALE_THRESHOLD: float = 0.01   # Scale change threshold

# === GRID MANAGEMENT CONSTANTS ===
const GRID_EXPANSION_FACTOR: float = 3.0  # Multiply by grid_size for obstacle bounds
const GRID_BUFFER_FACTOR: float = 2.0     # Buffer around dynamic obstacles

# === PATHFINDER CONSTANTS ===
const MAX_FAILED_RECALCULATIONS: int = 3
const RETRY_DELAY_SECONDS: float = 2.0

# === OBSTACLE MANAGER CONSTANTS ===
const VALIDITY_CACHE_INTERVAL: float = 0.5   # Check validity every N seconds
const BATCH_PROCESSING_INTERVAL: float = 0.1 # Process batches every N seconds
const MAX_BATCH_SIZE: int = 10               # Max items in batch before force processing
const CLEANUP_THRESHOLD: int = 2             # Only log cleanup if more than N removed

# === PATHFINDING BOUNDS CONSTANTS ===
const BOUNDS_EXPANSION_CONSERVATIVE: float = 50.0  # Conservative bounds expansion
const CLEARANCE_BASE_ADDITION: float = 15.0        # Base clearance addition
const CLEARANCE_SAFETY_MARGIN: float = 10.0        # Additional safety margin
const CLEARANCE_MULTIPLIERS: Array[float] = [1.0, 2.0, 3.0, 4.0]  # Progressive clearance attempts

# === SEARCH DIRECTION CONSTANTS ===
const CARDINAL_DIRECTIONS: Array[Vector2] = [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)
]

const DIAGONAL_DIRECTIONS: Array[Vector2] = [
	Vector2(0.707, 0.707), Vector2(-0.707, 0.707), 
	Vector2(0.707, -0.707), Vector2(-0.707, -0.707)
]

const RADIAL_TEST_ANGLES: Array[float] = [0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]

# === PERFORMANCE CONSTANTS ===
const MIN_LINE_LENGTH_SQUARED: float = 0.001  # For degenerate line detection
const TRANSFORM_COMPARISON_EPSILON: float = 0.01
