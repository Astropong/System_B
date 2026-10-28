@tool
class_name ModuleConstruction
extends Module
## Salle de construction : fabrication de pièces et d'équipements.

const ACCENT := Color(0.7, 0.9, 0.3)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.CONSTRUCTION


func get_ideal_power() -> float:
	return 100.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Caisses de matériaux dans les coins, aire d'assemblage au sol.
	for q in QUADRANTS:
		_draw_furniture(cells(q.x, q.y, 1.4, 1.4), ACCENT)
		_draw_furniture(cells(q.x + 1.6, q.y, 1.4, 1.4), ACCENT)
		_draw_furniture(cells(q.x, q.y + 1.6, 1.4, 1.4), ACCENT)
	var c := rect.get_center()
	var emblem := emblem_color(ACCENT)
	var half := CELL_SIZE * 2.2
	var arm := CELL_SIZE * 1.0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector2 = c + corner * half
		draw_polyline(PackedVector2Array([
			p - Vector2(corner.x * arm, 0), p, p - Vector2(0, corner.y * arm),
		]), emblem, 6.0)
