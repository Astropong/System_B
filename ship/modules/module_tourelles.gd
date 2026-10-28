@tool
class_name ModuleTourelles
extends Module
## Tourelles : défense du vaisseau.

const ACCENT := Color(1.0, 0.35, 0.3)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.TOURELLES


func get_ideal_power() -> float:
	return 100.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Quatre postes de tir orientés vers l'extérieur, viseur au sol.
	var c := rect.get_center()
	var half := QUADRANT_SIZE / 2.0
	for q in QUADRANTS:
		var base := cell_point(q.x + half, q.y + half)
		var dir := (base - c).normalized()
		draw_line(base, base + dir * CELL_SIZE * 1.6, ACCENT, 8.0)
		_draw_round_furniture(base, CELL_SIZE * 0.9, ACCENT)
	var emblem := emblem_color(ACCENT)
	draw_arc(c, CELL_SIZE * 1.8, 0.0, TAU, 48, emblem, 5.0)
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + dir * CELL_SIZE * 0.6, c + dir * CELL_SIZE * 2.6, emblem, 5.0)
