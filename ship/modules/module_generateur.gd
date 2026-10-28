@tool
class_name ModuleGenerateur
extends Module
## Générateur : produit l'électricité du vaisseau.

const ACCENT := Color(1.0, 0.85, 0.25)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.GENERATEUR


func get_ideal_power() -> float:
	return 300.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Quatre bancs de trois batteries, éclair au sol.
	for q in QUADRANTS:
		for i in 3:
			_draw_furniture(cells(q.x + 0.1 + i * 1.0, q.y, 0.8, QUADRANT_SIZE), ACCENT)
	var c := rect.get_center()
	draw_colored_polygon(PackedVector2Array([
		c + cell_point(0.5, -2.0), c + cell_point(-1.2, 0.3), c + cell_point(0.0, 0.3),
		c + cell_point(-0.5, 2.0), c + cell_point(1.2, -0.3), c + cell_point(0.0, -0.3),
	]), emblem_color(ACCENT))
