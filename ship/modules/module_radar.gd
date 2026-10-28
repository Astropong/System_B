@tool
class_name ModuleRadar
extends Module
## Radar : détecte ce qui entoure le vaisseau.

const ACCENT := Color(0.3, 0.95, 0.85)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.RADAR


func get_ideal_power() -> float:
	return 100.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Quatre pupitres tournés vers le centre, écran radar au sol.
	for i in QUADRANTS.size():
		var q := QUADRANTS[i]
		var y := q.y + QUADRANT_SIZE - 1.0 if i < 2 else q.y
		_draw_furniture(cells(q.x, y, QUADRANT_SIZE, 1.0), ACCENT)
		draw_line(cell_point(q.x + 0.4, y + 0.5), cell_point(q.x + QUADRANT_SIZE - 0.4, y + 0.5),
				ACCENT.darkened(0.3), 3.0)
	var c := rect.get_center()
	var emblem := emblem_color(ACCENT)
	for r in [1.0, 2.0, 3.0]:
		draw_arc(c, CELL_SIZE * r, 0.0, TAU, 64, emblem, 3.0)
	draw_line(c, c + Vector2.from_angle(-PI / 5.0) * CELL_SIZE * 3.0, emblem, 4.0)
