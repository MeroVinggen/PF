@tool
extends RefCounted
class_name PathNode

var parent: PathNode = null
var position: Vector2
var g_score: float
var f_score: float
var h_score: float

func _init(pos: Vector2 = Vector2.ZERO, g: float = 0.0, h: float = 0.0):
	position = pos
	g_score = g
	h_score = h
	f_score = g + h
