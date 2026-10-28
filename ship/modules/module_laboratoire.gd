@tool
class_name ModuleLaboratoire
extends Module
## Laboratoire : recherche et analyses.

const ACCENT := Color(1.0, 0.45, 0.75)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.LABORATOIRE


func get_ideal_power() -> float:
	return 100.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Quatre paillasses avec leurs fioles, molécule au sol.
	for q in QUADRANTS:
		var bench := cells(q.x, q.y + 1.0, QUADRANT_SIZE, 1.2)
		_draw_furniture(bench, ACCENT)
		for k in 3:
			draw_circle(bench.position + Vector2((0.6 + k * 0.9) * CELL_SIZE, bench.size.y / 2.0), 7.0, ACCENT)
	var c := rect.get_center()
	var emblem := emblem_color(ACCENT)
	var hexagon := PackedVector2Array()
	for k in 7:
		hexagon.append(c + Vector2.from_angle(PI / 6.0 + k * TAU / 6.0) * CELL_SIZE * 2.0)
	draw_polyline(hexagon, emblem, 5.0)
	for k in [0, 2, 4]:
		draw_circle(hexagon[k], CELL_SIZE * 0.35, emblem)
