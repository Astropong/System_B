@tool
class_name ModuleOxygene
extends Module
## Générateur d'oxygène : renouvelle l'air du vaisseau.

const ACCENT := Color(0.55, 0.9, 1.0)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.OXYGENE


func get_ideal_power() -> float:
	return 700.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Quatre groupes de trois bouteilles, bulles au sol.
	for q in QUADRANTS:
		for p in [Vector2(0.8, 0.8), Vector2(2.2, 0.8), Vector2(1.5, 2.2)]:
			_draw_round_furniture(cell_point(q.x + p.x, q.y + p.y), CELL_SIZE * 0.6, ACCENT)
	var c := rect.get_center()
	var emblem := emblem_color(ACCENT)
	draw_arc(c + cell_point(-0.6, 0.6), CELL_SIZE * 1.3, 0.0, TAU, 48, emblem, 5.0)
	draw_arc(c + cell_point(1.1, -0.9), CELL_SIZE * 0.8, 0.0, TAU, 48, emblem, 5.0)
	draw_arc(c + cell_point(1.5, 1.2), CELL_SIZE * 0.45, 0.0, TAU, 32, emblem, 4.0)
