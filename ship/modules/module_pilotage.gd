@tool
class_name ModulePilotage
extends Module
## Pilotage : poste de commande du vaisseau.

const ACCENT := Color(0.45, 0.65, 1.0)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.PILOTAGE


func get_ideal_power() -> float:
	return 800.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# À l'avant (à droite) : deux consoles et leurs sièges ; à l'arrière :
	# deux tables de navigation. Chevron vers l'avant au sol.
	for y in [2.5, 10.0]:
		_draw_furniture(cells(14.0, y, 1.0, 3.5), ACCENT)
		_draw_round_furniture(cell_point(12.5, y + 1.75), CELL_SIZE * 0.6, ACCENT)
	for q in [QUADRANTS[0], QUADRANTS[2]]:
		_draw_furniture(cells(q.x, q.y + 0.5, QUADRANT_SIZE, 2.0), ACCENT)
	var c := rect.get_center()
	draw_polyline(PackedVector2Array([
		c + cell_point(-1.0, -2.0), c + cell_point(1.0, 0.0), c + cell_point(-1.0, 2.0),
	]), emblem_color(ACCENT), CELL_SIZE * 0.5)
