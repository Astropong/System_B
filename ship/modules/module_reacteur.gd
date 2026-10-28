@tool
class_name ModuleReacteur
extends Module
## Réacteur : propulsion du vaisseau.

const ACCENT := Color(1.0, 0.5, 0.15)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.REACTEUR


func get_ideal_power() -> float:
	return 100.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Quatre réservoirs de refroidissement, cœur du réacteur au sol.
	var half := QUADRANT_SIZE / 2.0
	for q in QUADRANTS:
		_draw_round_furniture(cell_point(q.x + half, q.y + half), CELL_SIZE * 1.3, ACCENT)
		draw_circle(cell_point(q.x + half, q.y + half), CELL_SIZE * 0.35, ACCENT)
	var c := rect.get_center()
	var emblem := emblem_color(ACCENT)
	draw_arc(c, CELL_SIZE * 2.4, 0.0, TAU, 64, emblem, 6.0)
	draw_arc(c, CELL_SIZE * 1.5, 0.0, TAU, 64, emblem, 4.0)
	draw_circle(c, CELL_SIZE * 0.7, emblem)
