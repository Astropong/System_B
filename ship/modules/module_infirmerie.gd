@tool
class_name ModuleInfirmerie
extends Module
## Infirmerie : soigne l'équipage.

const ACCENT := Color(0.35, 0.9, 0.45)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.INFIRMERIE


func get_ideal_power() -> float:
	return 600.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Quatre lits, croix médicale au sol.
	for q in QUADRANTS:
		var bed := cells(q.x + 0.7, q.y, 1.6, QUADRANT_SIZE)
		_draw_furniture(bed, ACCENT)
		draw_rect(Rect2(bed.position + Vector2(8, 8), Vector2(bed.size.x - 16, CELL_SIZE * 0.5)), ACCENT.darkened(0.4))
	var c := rect.get_center()
	var emblem := emblem_color(ACCENT)
	draw_rect(Rect2(c - cell_point(0.6, 2.0), cell_point(1.2, 4.0)), emblem)
	draw_rect(Rect2(c - cell_point(2.0, 0.6), cell_point(4.0, 1.2)), emblem)
